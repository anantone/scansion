#!/usr/bin/env ruby
# frozen_string_literal: true

require "ffi"

# Remplacement « drop-in » du wrapper CLI d'espeak-ng, appelant la bibliothèque
# C d'espeak-ng directement via FFI — aucun processus engendré par mot.
#
#   apt install libespeak-ng-dev       # Debian/Ubuntu
#   brew install espeak-ng             # macOS (la lib est keg-only, voir ci-dessous)
#
# Si la bibliothèque vit hors du chemin de recherche par défaut (p. ex.
# installation Homebrew keg-only), définir PHONEMIZER_ESPEAK_LIB dans
# l'environnement avant de charger ce fichier :
#
#   ENV["PHONEMIZER_ESPEAK_LIB"] =
#     %x(brew --prefix espeak-ng).strip + "/lib/libespeak-ng.dylib"
#
# Contrat du backend (vérifié contre libespeak-ng 1.1.51) :
#   espeak_TextToPhonemes traduit une *clause* par appel — le texte jusqu'à
#   une virgule, un point-virgule, deux-points, un point ou terminateur
#   similaire — en avançant son pointeur de texte et en renvoyant NULL en fin
#   d'entrée. Les mots d'une même clause s'influencent (liaisons, consonnes
#   finales prononcées).
#
#   Différence IMPORTANTE avec le binaire CLI : la fonction n'offre AUCUNE
#   isolation entre les morceaux concaténés — les sauts de ligne ne sont que
#   des espaces et les morceaux adjacents fusionnent. Grouper plusieurs mots
#   dans un même tampon corromprait donc silencieusement les résultats ; chaque
#   morceau a son propre appel. C'est un appel de fonction en processus, bien
#   moins coûteux que le fork+exec par mot du CLI.
#
#   --ipa correspond au bit 1 de phonememode (0x02) ; --sep aux bits 8-23. Le
#   pipeline phonemize demande toujours l'octet sentinelle \x01 comme
#   séparateur inter-phones, donc n'importe quel phone_sep utilisateur
#   (multi-caractères, espaces, « - ») se reporte sur la sortie sans risque de
#   collision ; espeak_raw, lui, transmet les séparateurs d'un seul octet tels
#   quels, comme --sep.
#
#   Sélection de voix calquée sur le CLI : espeak_SetVoiceByName reconnaît les
#   voix installées (« en-us ») ; les codes qu'il ne connaît pas (« fr-fr »
#   quand seul « fr » est installé) retombent sur espeak_SetVoiceByProperties
#   avec les critères de langue — exactement ce que fait le CLI espeak-ng en
#   interne.
module Phonemizer
  module_function

  DEFAULT_LANGUAGE = "en-us"

  # Conservé pour la compatibilité d'API avec le wrapper CLI. Les appels en
  # processus sont bon marché et libespeak-ng n'est pas thread-safe : il n'y a
  # donc rien à mettre en pool.
  DEFAULT_WORKERS = 1

  # espeak émet des balises de langue entre parenthèses lors des changements de
  # langue, p. ex. (en) / (fr) / (pt-br) ; le motif couvre toute balise qu'espeak
  # peut émettre.
  LANG_SWITCH = /\((?:[a-z]{2,3}(?:-[a-z0-9]+)*)\)/

  # Caractères qu'espeak chercherait à prononcer ; on les découpe à la place.
  # Les apostrophes sont EXCLUES exprès : elles doivent rester à l'intérieur du
  # mot qu'elles élident (aujourd'hui, l'instar). Les couper transcrirait les
  # deux moitiés séparément et perdrait les consonnes de liaison
  # (oʒuʁdɥi -> oʒuʁ + yi).
  PUNCT = /([[:punct:]&&[^'’‘]]+)/

  # Cache partagé par les fonctions du module. Une constante (pas un @ivar)
  # pour que les méthodes fonctionnent pareil appelées via
  # Phonemizer.phonemize(...) ou après `include Phonemizer` — les copies
  # module_function ne portent pas le contexte de variable d'instance du module.
  CACHE = {}

  # ---------------------------------------------------------------- FFI

  module LibEspeak
    extend FFI::Library

    ffi_lib [ENV["PHONEMIZER_ESPEAK_LIB"], "libespeak-ng.so.1",
             "libespeak-ng.so", "libespeak-ng.dylib"].compact

    AUDIO_OUTPUT_SYNCHRONOUS = 2       # pas de sortie audio, pas de file asynchrone
    CHARS_UTF8               = 1       # espeakCHARS_UTF8
    INITIALIZE_DONT_EXIT     = 0x8000  # valeur de retour d'erreur au lieu de exit()
    PHONEME_IPA              = 0x02    # bit 1 de phonememode : sortie IPA

    EE_OK             = 0
    EE_INTERNAL_ERROR = -1

    # Séparateur inter-phones sentinelle demandé à espeak (encodé dans les bits
    # 8-23 de phonememode). \x01 n'apparaît jamais dans la sortie IPA, donc le
    # reporter ensuite sur le phone_sep de l'utilisateur ne peut pas entrer en
    # collision, quel que soit le phone_sep (multi-caractères, espaces, même « - »).
    SEP_CHAR = "\x01"

    attach_function :espeak_Initialize, %i[int int pointer int], :int
    attach_function :espeak_SetVoiceByName, [:string], :int
    attach_function :espeak_SetVoiceByProperties, [:pointer], :int
    attach_function :espeak_TextToPhonemes, %i[pointer int int], :string

    # espeak_VOICE — seuls les champs renseignés ; le reste reste à zéro.
    # NOTE : FFI interdit d'ASSIGNER les champs :string en ligne (ce sont des
    # raccourcis en lecture seule pour char*). Les membres char* sont donc
    # déclarés :pointer et alimentés par un MemoryPointer contenant une chaîne
    # terminée par NUL (voir with_voice).
    class Voice < FFI::Struct
      layout :name, :pointer, :languages, :pointer, :identifier, :pointer,
             :gender, :uint8, :age, :uint8, :variant, :uint8, :xx1, :uint8,
             :score, :int, :spare, :pointer
    end

    # phonememode : toujours de l'IPA ; séparateur sentinelle seulement en mode
    # sep. Utilisé par le pipeline phonemize (stitch reporte la sentinelle ensuite).
    module_function

    def phonememode(phone_sep)
      mode = PHONEME_IPA
      mode |= (SEP_CHAR.ord << 8) unless phone_sep.empty?
      mode
    end

    # espeak_Initialize doit tourner une fois avant toute chose. Idempotent.
    # AUDIO_OUTPUT_SYNCHRONOUS : aucun périphérique audio n'est touché ;
    # DONT_EXIT fait d'un espeak-ng-data manquant une erreur de retour plutôt
    # qu'un exit() brutal.
    def init!
      return true if @initialized
      rate = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, nil,
                               INITIALIZE_DONT_EXIT)
      if rate == EE_INTERNAL_ERROR
        raise "échec d'espeak_Initialize : espeak-ng-data est-il installé ?"
      end
      @initialized = true
    end
  end

  # ---------------------------------------------------------------- API publique

  # Entrée : une String (un énoncé) ou un Array de mots.
  # Retourne une String (ou un Array de Strings, à la forme de l'entrée).
  #
  # Options :
  #   language:        voix espeak, défaut « en-us »
  #   phone_sep:       inséré entre les phones, défaut « » (mɑ̃ʒe)
  #   word_sep:        joint les énoncés multi-mots,  défaut «  »
  #   strip_stress:    retire ˈ ˌ de la sortie,      défaut true
  #   language_switch: :remove (défaut) ou :keep
  #   workers:         accepté, ignoré (conservé pour la compatibilité d'API ;
  #                    la bibliothèque est appelée en processus et n'est pas
  #                    thread-safe)
  def phonemize(words, language: DEFAULT_LANGUAGE, phone_sep: "",
                word_sep: " ", strip_stress: true, language_switch: :remove,
                workers: nil)
    if words.is_a?(Array)
      phonemize_batch(words, language:, phone_sep:, word_sep:,
                      strip_stress:, language_switch:)
    else
      phonemize_batch([words], language:, phone_sep:, word_sep:,
                      strip_stress:, language_switch:).first
    end
  end

  def clear_cache
    CACHE.clear
  end

  # Compatibilité wrapper CLI : transcription brute d'un énoncé. Renvoie l'IPA
  # brute (accents de stress, tirets de liaison et balises de langue intacts).
  #
  # Calque l'espeak_raw du gem, où --sep=<car> fait séparer les phones par
  # espeak lui-même avec le caractère de l'utilisateur (les frontières de mot
  # sortent en double espace en mode sep). Les séparateurs d'un octet sont
  # transmis tels quels via les bits 8-23 de phonememode — le même réglage que
  # tourne le --sep du CLI — vérifié pour produire une sortie identique octet
  # par octet pour sep=" ".
  # Les séparateurs multi-octets sont inexpressibles au niveau d'espeak (le
  # champ fait un octet ; --sep a la même limite), donc ils retombent sur la
  # sentinelle puis sont substitués ; la sortie brute ne diffère alors du CLI
  # que par des frontières de mot espacées une seule fois.
  #
  # Le saut de ligne final du CLI (espeak imprime une ligne entière) n'est pas
  # reproduit ; tous les consommateurs de cette valeur, dans les deux
  # implémentations, retirent les espaces autour avant usage.
  def espeak_raw(text, language, phone_sep: nil)
    with_voice(language) do
      text = text.to_s
      sep  = phone_sep.to_s

      out =
        if sep.empty?
          transcribe_piece(text, LibEspeak::PHONEME_IPA)
        elsif sep.bytesize == 1
          # Parité CLI : transmettre l'octet du séparateur dans les bits 8-23
          # de phonememode, exactement ce que fait --sep=<car> au niveau d'espeak.
          mode = LibEspeak::PHONEME_IPA | (sep.getbyte(0) << 8)
          transcribe_piece(text, mode)
        else
          # Séparateur multi-octets : impossible au niveau d'espeak.
          # Transcrire avec la sentinelle, puis substituer le séparateur de
          # l'utilisateur.
          out = transcribe_piece(text, LibEspeak.phonememode(sep))
          out.gsub(LibEspeak::SEP_CHAR, sep)
        end

      warn "ATTENTION : espeak-ng n'a rien renvoyé pour : #{text[0, 40].inspect}" \
        if out.strip.empty? && !text.strip.empty?

      out
    end
  end

  # ---------------------------------------------------------------- pipeline

  def phonemize_batch(words, language:, phone_sep:, word_sep:,
                     strip_stress:, language_switch:)
    # Garde-fou pour nil : ne copier que si un élément n'est pas déjà une String
    words = words.map(&:to_s) unless words.all? { |w| w.is_a?(String) }

    # Cache : les formes de mots se répètent constamment dans un lexique. Les
    # options sont fixées pour tout l'appel, donc la clé est une fonction pure
    # du mot — on la mémoïse pour ne construire chaque tableau de clé qu'une
    # fois par mot unique.
    key_of = Hash.new do |h, w|
      h[w] = [w, language, phone_sep, word_sep, strip_stress, language_switch]
    end
    todo = words.uniq.reject { |w| CACHE.key?(key_of[w]) }

    unless todo.empty?
      with_voice(language) do
        # Ponctuation : découper les énoncés sur la ponctuation, ne transcrire
        # que les morceaux propres, puis remettre la ponctuation en place
        chunks = todo.map { |w| split_punctuation(w) }

        mode = LibEspeak.phonememode(phone_sep)
        clean_words = chunks.flatten.reject { |p| PUNCT.match?(p) }.uniq
        ipa_map = clean_words.each_with_object({}) do |piece, map|
          map[piece] = transcribe_piece(piece, mode)
        end

        todo.each_with_index do |w, i|
          CACHE[key_of[w]] = stitch(chunks[i], ipa_map,
                                     phone_sep:, word_sep:, strip_stress:,
                                     language_switch:)
        end
      end
    end

    words.map { |w| CACHE[key_of[w]] }
  end

  # énoncé -> [ponct, mot, ponct, mot, ...]
  def split_punctuation(word)
    word.split(PUNCT).reject(&:empty?)
  end

  # Reassemble un énoncé : ponctuation remise en place, séparateurs appliqués.
  # ipa_map associe à chaque morceau sa transcription IPA brute (indexée par
  # le contenu).
  def stitch(parts, ipa_map, phone_sep:, word_sep:, strip_stress:,
             language_switch:)
    parts.map do |part|
      next part if PUNCT.match?(part)               # ponctuation : telle quelle
      t = ipa_map[part] || ""
      t = t.gsub(LANG_SWITCH, "") if language_switch == :remove
      # Toujours retirer les accents de stress ; ne retirer le tiret de liaison
      # qu'en mode contigu, où espeak l'émet (p. ex. « les amis » -> « le-z
      # ami »). En mode sep, on a transcrit avec la sentinelle, donc un « - »
      # de l'utilisateur dans phone_sep doit survivre.
      if strip_stress
        t = t.delete("ˈˌ")
        t = t.delete("-") if phone_sep.empty?
      end
      if phone_sep.empty?
        # phones contigus : un simple espace est une frontière de mot
        t = t.gsub(" ", word_sep)
      else
        # Mode sep : la sentinelle \x01 sépare les phones, un simple espace
        # marque une frontière de mot. Report en une passe, donc phone_sep et
        # word_sep peuvent contenir N'IMPORTE quels caractères — y compris des
        # espaces — sans collision.
        t = t.gsub(/[\x01 ]/) do |ch|
          ch == LibEspeak::SEP_CHAR ? phone_sep : word_sep
        end
      end
      t
    end.join
  end

  # ---------------------------------------------------------------- internes

  # La sélection de voix de libespeak-ng est un état global ; la définir avant
  # de transcrire. Initialisation garantie : tout point d'entrée passe par ici.
  #
  # Calque le CLI d'espeak-ng : SetVoiceByName reconnaît les voix et variantes
  # installées ; les codes de langue purs qu'il ne connaît pas (« fr-fr » sur
  # un système qui n'installe que « fr ») retombent sur SetVoiceByProperties,
  # qui correspond sur la langue (plus le dialecte) seule.
  #
  # Le champ languages doit être un char* terminé par NUL : la coercition
  # :string de Ruby ne s'applique qu'aux ARGUMENTS de fonction, pas aux champs
  # de struct, et les champs :string d'une struct sont en lecture seule en FFI —
  # d'où le MemoryPointer explicite ici. `lang` est gardé vivant sur la pile
  # locale pendant toute la durée de l'appel, ce qui satisfait l'exigence de
  # durée de vie de la struct.
  def with_voice(language)
    LibEspeak.init!
    rc = LibEspeak.espeak_SetVoiceByName(language)
    if rc != LibEspeak::EE_OK
      lang = FFI::MemoryPointer.from_string(language) # terminée par NUL
      spec = LibEspeak::Voice.new
      spec[:languages] = lang
      rc = LibEspeak.espeak_SetVoiceByProperties(spec)
    end
    unless rc == LibEspeak::EE_OK
      raise "espeak-ng : impossible de sélectionner la voix #{language.inspect}"
    end

    yield
  end

  # Transcrit un morceau avec le phonememode donné. Un morceau ne contient
  # normalement qu'une seule clause (la ponctuation a été découpée en amont),
  # mais on continue à vider les clauses par précaution : un terminateur
  # parasite serait sinon silencieusement perdu, et joindre les fragments
  # garde un résultat sain.
  #
  # Les fragments de clause sont joints par un simple espace, comme la sortie
  # IPA sur une ligne du CLI (« mots séparés par des espaces sur une ligne,
  # dans l'ordre d'entrée » — l'API C les délivre juste une clause à la fois).
  def transcribe_piece(piece, mode)
    buf = FFI::MemoryPointer.from_string(piece)
    tp  = FFI::MemoryPointer.new(:pointer)
    tp.write_pointer(buf)

    clauses = []
    while (clause = LibEspeak.espeak_TextToPhonemes(
             tp, LibEspeak::CHARS_UTF8, mode
           ))
      clauses << clause
      break if tp.read_pointer.null?
    end
    # FFI renvoie des chaînes ASCII-8BIT ; la charge IPA est en UTF-8.
    clauses.join(" ").strip.force_encoding(Encoding::UTF_8)
  end
end

# ---------------------------------------------------------------------------
# Mode exécutable : calque le bin/phonemize du gem pour que ce fichier unique
# serve à la fois de bibliothèque et de commande. Ne tourne que s'il est invoqué
# directement (ruby phonemizer_ffi.rb ... ou via un lien/execbit), donc le
# charger depuis ailleurs reste sans effet de bord.
#
# Différences avec le bin/phonemize du gem, toutes imposées par le backend :
#   * pas de flag --workers/-j (backend FFI monothread)
#   * mode stdin ajouté : le CLI n'a pas d'interface batch sur stdin, et la
#     bibliothèque n'a pas de pool de workers, donc les lignes depuis stdin
#     sont la voie naturelle à haut débit pour ce backend.
if $PROGRAM_NAME == __FILE__
  require "optparse"

  options = {
    language: Phonemizer::DEFAULT_LANGUAGE,
    phone_sep: "",
    word_sep: " ",
    strip_stress: true,
    language_switch: :remove
  }

  parser = OptionParser.new do |o|
    o.banner = "Utilisation : #{File.basename($PROGRAM_NAME)} [options] [texte | fichier]"
    o.on("-l", "--language LANG",
         "voix espeak (défaut : #{Phonemizer::DEFAULT_LANGUAGE})") { |v| options[:language] = v }
    o.on("-p", "--phone-sep SEP",
         "séparateur entre phones (défaut : aucun)") { |v| options[:phone_sep] = v }
    o.on("-w", "--word-sep SEP",
         "séparateur entre les mots d'un même énoncé (défaut : espace)") { |v| options[:word_sep] = v }
    o.on("-s", "--[no-]strip-stress",
         "retirer les accents de stress et les tirets de liaison (défaut : oui)") { |v| options[:strip_stress] = v }
    o.on("-k", "--keep-language-switch",
         "garder les balises de langue (en)/(fr) en ligne (défaut : les retirer)") { options[:language_switch] = :keep }
    o.on("-h", "--help", "afficher cette aide") do
      puts o
      exit
    end
  end
  parser.parse!(ARGV)

  # Mode batch stdin : une ligne = un énoncé, transcrit en un seul lot.
  if ARGV.empty? && !$stdin.tty?
    lines = $stdin.read.lines.map(&:strip).reject(&:empty?)
    exit if lines.empty?
    Phonemizer.phonemize(lines, **options).each { |line| puts line }
  else
    text = ARGV.join(" ")
    if File.file?(text)
      lines = File.readlines(text, chomp: true).reject(&:empty?)
      Phonemizer.phonemize(lines, **options).each { |line| puts line }
    else
      puts Phonemizer.phonemize(text, **options)
    end
  end
end
