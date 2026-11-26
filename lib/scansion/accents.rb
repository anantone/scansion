# frozen_string_literal: true

#
# accents.rb — accents de phrase (groupes rythmiques, ˈ) et accents
# secondaires de mots (ˌ), par-dessus le gem scansion et phonemizer_ffi.
#
# Modèle (règles de Delattre, encodées) :
#   1. Deux couches d'accent : chaque GROUPE rythmique porte un accent (ˈ,
#      « accent de phrase ») sur sa dernière syllabe accentuable ; et chaque
#      MOT plein porte un accent interne (ˌ, « accent secondaire ») sur sa
#      propre dernière syllabe accentuable.
#   2. Une syllabe au noyau schwa (e caduc restauré, /ə/) — ou un simple
#      glide — ne porte jamais l'accent : il retombe sur la syllabe
#      accentuable précédente.
#   3. Frontières de groupe (syntagmes) : avant une conjonction, un verbe
#      auxiliaire, une préposition (sauf « de + nom nu » : « peau d'ange »),
#      ou un déterminant ouvrant un nouveau syntagme (sauf si le mot
#      précédent est fonctionnel ou une préposition : « à partir du col »,
#      « que le fond ») ; plus après chaque ponctuation et en fin de vers.
#      En mode CONTEMPORAIN (mode: :contemporain) s'ajoutent : une frontière entre
#      deux mots pleins (« de bile | noire »), « alors » en conjonction
#      (« cerveau | alors que rien »), et aucune frontière ne tombe à
#      l'intérieur d'un mot (l'aligneur rend la voyelle initiale au mot
#      suivant : « cerveau alors » -> sɛʁ-vo | a-lɔʁ).
#      Un accent par groupe, sur sa dernière syllabe accentuable ; l'accent
#      du dernier groupe est la rime. Si aucun groupe ne se termine avant la
#      césure (6//6, 4//4), une frontière y est forcée.
#
# L'alignement mot -> syllabe consomme Scansion::Result#word_spans (calculé
# par le gem lui-même, donc sans dérive) ; le matching IPA sur mot isolé
# n'est gardé qu'en repli pour les résultats non alignés (~), sans spans.
#
# Usage :
#   require "scansion/accents"
#   a = Scansion::Accents.analyze_line("Au coin du feu, dans la langueur des rêveries!")
#   puts a.render        # syllabes, frontières de groupe (|) et accents (ˈ/ˌ)
#   a.accents            # => indices 0-based des syllabes accentuées (phrase)
#   a.word_accents       # => indices 0-based des accents secondaires (mots)
#   a.warnings           # problèmes d'alignement / validation
#
# Corpus :
#   Scansion::Accents.analyze_lines(File.readlines("corpus.txt", chomp: true))

require_relative 'syllabification'
require_relative 'rythme'
require 'phonemizer_ffi'

module Scansion
  # Accents de phrase (groupes rythmiques, ˈ) et accents secondaires de mot
  # (ˌ) pour la poésie française, par-dessus la syllabification du gem.
  # Points d'entrée : Accents.analyze_line, Accents.analyze_lines,
  # Accents.word_accents. Voir le commentaire d'en-tête du fichier pour le
  # modèle accentuel.
  module Accents
    SCHWA = 'ə'
    GLIDES = 'yɥ'

    # Characters treated as vocalic when looking for a syllable nucleus
    # (incl. nasal vowels, which espeak writes as vowel + combining tilde U+0303).
    VOYELLES = "aeiouyɑɛɔøœəãẽĩõũ\u0303"

    REGEXP_PONCTUATION = /\A[,;:.!?…—–«»]\z/

    # Classes de mots fonctionnels (sans accent propre). Un groupe rythmique se
    # termine à la frontière devant certains d'entre eux (voir boundary_before?).
    # « en » est retiré de PREPOSITIONS : pronom (« en finir » ne ouvre pas de groupe),
    # il reste dans PRONOMS. Comme préposition (« en ville ») il ne forcera plus
    # de frontière — compromis accepté (le groupe verbal l'absorbe).
    PREPOSITIONS = %w[à au aux dans par pour sur sous vers chez sans contre entre de d
                      dessous dessus dedans dehors avant après depuis jusqu jusque malgré selon].to_h do |w|
      [w,
       true]
    end.freeze
    DETERMINANTS = %w[le la les l un une du des au ce cet cette ces mon ton son ma ta mes tes ses
                      notre votre leur nos vos leurs quel quels quelle quelles
                      tout tous toute toutes].to_h { |w| [w, true] }.freeze
    CONJONCTIONS = %w[et ou mais donc or ni car que qu si quoique lorsque quand puisque].to_h { |w| [w, true] }.freeze
    AUXILIAIRES = %w[suis es est sommes êtes sont étais était étaient été
                     ai as a avons avez ont avais avait avaient eu eut].to_h { |w| [w, true] }.freeze
    PRONOMS = %w[je j tu t il elle on nous vous ils elles me m te se y en leur leurs ne pas plus jamais rien qui quoi
                 dont où lequel laquelle lesquels lesquelles].to_h do |w|
      [w, true]
    end.freeze
    # pronoms indéfinis seuls : ils ouvrent un groupe (« qu'amer » | « aucun s'efface »)
    INDEFINIS = %w[aucun aucune aucuns aucunes quelques plusieurs tout tous toute toutes
                   autre autres même mêmes chacun chacune chaque].to_h { |w| [w, true] }.freeze
    MOTS_FONCTIONNELS = PREPOSITIONS.merge(DETERMINANTS).merge(CONJONCTIONS)
                                    .merge(AUXILIAIRES).merge(PRONOMS).merge(INDEFINIS).freeze

    # Mode contemporain (mode: :contemporain) uniquement :
    # « alors » se comporte comme une conjonction — frontière AVANT lui, mais
    # le groupe ne se coupe pas après (« cerveau | alors que rien »).
    CONTEMP_CONJONCTIONS = %w[alors].to_h { |w| [w, true] }.freeze
    # Pronoms traités comme « pleins » côté PRÉCÉDENT en contemporain
    # (« qui | s'écoule », « rien | qui jaillisse », « jamais | lové »).
    CONTEMP_PRONOMS_PLEINS = %w[qui jamais rien leur leurs].freeze

    # Word token: Unicode word chars plus apostrophes (elisions: l'amour) and
    # internal hyphens (porte-parapluie).
    REGEXP_MOTS = /[\p{Word}'’-]+|[,;:.!?…—–«»"]/

    # keyword_init structs take keyword arguments only.
    Token = Struct.new(:surface, :kind, :debut, :fin, keyword_init: true) # kind: :word | :punct
    Group = Struct.new(:tokens, :accent)

    # Résultat de l'analyse accentuelle d'un vers (voir
    # Scansion::Accents.analyze_line / .analyze_lines) :
    # - +text+         : vers d'origine ;
    # - +syllables+    : syllabes IPA (sans marque d'accent) ;
    # - +tokens+       : mots et ponctuation avec leurs indices de syllabes ;
    # - +groups+       : groupes rythmiques (frontière « | », accent de phrase ˈ) ;
    # - +word_accents+ : indices des syllabes portant un accent de mot ˌ ;
    # - +warnings+     : avertissements (ex. pas de frontière à la césure).
    Analysis = Struct.new(:text, :syllables, :tokens, :groups, :word_accents, :warnings, keyword_init: true) do
      # Accents de phrase (primaire, ˈ) : indice de la dernière syllabe de
      # chaque groupe rythmique.
      # @return [Array<Integer>]
      def accents
        groups.filter_map(&:accent)
      end

      # Transcription avec marques d'accent : « ˈ » = accent de phrase (fin de
      # groupe, séparée par « | »), « ˌ » = accent interne de mot.
      # Ex. « me-ˌpɛʁ-kʁi-ˈɛ |-də-su-me-ˈpje ».
      # @return [String]
      def render
        syllables.each_with_index.map do |s, i|
          marked = if groups.any? { |g| g.accent == i }
                     "ˈ#{s}" # accent de phrase (primaire)
                   elsif word_accents.to_a.include?(i)
                     "ˌ#{s}" # accent interne du mot (secondaire)
                   else
                     s
                   end
          boundary = groups.any? { |g| g.tokens.last&.fin == i }
          boundary ? "#{marked} |" : marked
        end.join('-').sub(/ \|$/, '')
      end
    end

    class << self
      # Analyse accentuelle d'un poème entier (syllabification via
      # Scansion.process_lines, puis groupes rythmiques et accents de mot).
      # Le régime se règle par `mode` (:auto par défaut — détection sur une
      # 1re passe, voir Scansion.detect_mode) : :classique = césure et
      # accents de groupe classiques, aucun tirage 2.6 ; :contemporain =
      # règles de groupement 3.3 + tirage accentuel 2.6 (Scansion::Rythme)
      # appliqué à chaque vers.
      # @param lines [Array<String>] les vers
      # @param mode [Symbol] :auto (défaut), :classique ou :contemporain
      # @return [Array<Scansion::Accents::Analysis>]
      def analyze_lines(lines, mode: :auto)
        cache = {}
        results = begin
          Scansion.process_lines(lines, mode: mode, cache: cache)
        rescue StandardError
          lines.map { |l| Scansion.process_line(l, mode: mode) }
        end
        mode = Scansion.detect_mode(lines, cache: cache) if mode == :auto
        contemporain = (mode == :contemporain)
        results.zip(lines).map do |res, text|
          # règle 2.6 (Scansion::Rythme) : tirage accentuel, mode contemporain
          res = Scansion::Rythme.accent_pull(text, res, cache: cache) if contemporain
          analyze_result(res, text, contemporain: contemporain)
        end
      end

      # Analyse accentuelle d'un seul vers. En mode :contemporain, applique
      # d'abord le tirage accentuel 2.6 (Scansion::Rythme.accent_pull) ;
      # jamais en mode :classique. :auto détecte le régime sur le seul vers.
      # @param text [String] le vers
      # @param mode [Symbol] :auto (défaut), :classique ou :contemporain
      # @return [Scansion::Accents::Analysis]
      def analyze_line(text, mode: :auto)
        cache = {}
        mode = Scansion.detect_mode([text], cache: cache) if mode == :auto
        res = Scansion.process_line(text, mode: mode, cache: cache)
        res = Scansion::Rythme.accent_pull(text, res, cache: cache) if mode == :contemporain
        analyze_result(res, text, contemporain: mode == :contemporain)
      end

      # Fragments clitiques (l', j', n', c', d', m', t', s') : la « vraie » tête
      # du mot est la première partie qui n'est pas un fragment — « c'est » ->
      # est (auxiliaire, fonctionnel), « l'ombre » -> ombre (nom, PAS le
      # déterminant « l »), « n'est » -> est.
      FRAGMENTS_CLITIQUES = %w[c d j l m n s t].freeze

      # tête du mot : première partie non clitique (« c'est » -> « est »,
      # « l'ombre » -> « ombre ») ; un mot est fonctionnel si TOUTES ses
      # parties le sont (« n'est » -> n + est)
      def head_of(tok)
        return nil unless tok.kind == :word

        pcs = pieces(tok).map(&:downcase)
        pcs.find { |p| !FRAGMENTS_CLITIQUES.include?(p) } || pcs.first
      end

      # Une frontière de groupe AVANT tokens[i] (mot) :
      #  - conjonction (que, et, ou, mais…)                          -> oui
      #  - verbe auxiliaire (n'est, est, a…)                           -> oui
      #  - préposition, sauf « de/d' + nom nu » (complément : « peau d'ange ») -> oui
      #  - déterminant qui OUVRE un nouveau syntagme, sauf si le mot
      #    précédent est fonctionnel ou une préposition (PP : « à partir du col »)
      # fin de verbe fini (heuristique sans POS) : -ont, -ez, -ons, -ais, -ait,
      # -ai/-as/-a, -is/-it/-ît, -e. Un déterminant après un verbe fini reste
      # dans le groupe verbal (« font un reflet », « fondra la mer ») ; après
      # un participe ou un nom, il ouvre un nouveau syntagme (« ciselant | le
      # cristal », « l'ombre | les escrocs »).
      TERMINAISONS_VERBE_FINI = /(?:ont|ez|ons|ais|aient|ait|ai|as|a|is|it|ît)\z/

      def finite_verb_head?(head)
        !head.nil? && head.match?(TERMINAISONS_VERBE_FINI)
      end

      def boundary_before?(tokens, i, contemporain: false)
        tok = tokens[i]
        return false unless tok.kind == :word
        return false if i.zero?

        pcs = pieces(tok)
        head = head_of(tok).to_s # saute les fragments clitiques (c'est -> est)
        last = pcs.last.to_s.downcase
        nxt = tokens[i + 1]
        nxt_head = nxt ? head_of(nxt) : nil
        prev = tokens[i - 1]
        prev_head = prev ? head_of(prev) : nil
        prev2 = i >= 2 ? tokens[i - 2] : nil # pas d'index négatif !
        prev2_head = prev2 ? head_of(prev2) : nil

        return true if pcs.size == 1 && INDEFINIS.key?(head) # aucun, tout, autre… seuls
        return true if CONJONCTIONS.key?(head) || CONJONCTIONS.key?(last)
        return true if contemporain && CONTEMP_CONJONCTIONS.key?(head) # « alors »
        return true if AUXILIAIRES.key?(last) # n'est, est, a…

        # « en » : pronom devant un verbe à l'infinitif ou un nom (« en finir »
        # ne coupe pas), préposition devant un déterminant (« en ta toison »
        # coupe)
        if head == 'en'
          # mode contemporain : mot plein suivi de « en » -> frontière
          # (« je prie | en silence »)
          if contemporain && prev.kind == :word && prev_head &&
             (!MOTS_FONCTIONNELS.key?(prev_head) || CONTEMP_PRONOMS_PLEINS.include?(prev_head))
            return true
          end

          return nxt_head && DETERMINANTS.key?(nxt_head) ? true : false
        end

        if PREPOSITIONS.key?(head)
          # « d'ange » (de + nom nu soudé) : pas de frontière
          return false if %w[de d].include?(head) && pcs.size > 1

          # « de + nom nu » complément ne coupe pas, même en contemporain :
          # « l'absence de sens », « le sens de l'écrit », « peau d'ange »
          return false if %w[de d].include?(head) && nxt_head && !DETERMINANTS.key?(nxt_head)

          # mode contemporain : mot plein suivi d'une préposition (autre que
          # de) -> frontière (« d'or | en ta chair »)
          if contemporain && prev.kind == :word && prev_head &&
             (!MOTS_FONCTIONNELS.key?(prev_head) || CONTEMP_PRONOMS_PLEINS.include?(prev_head))
            return true
          end

          return true
        end
        if DETERMINANTS.key?(head)
          # le déterminant appartient au syntagme précédent (« que le fond »,
          # « sans l'accuser ») si le mot d'avant est fonctionnel
          return false if prev_head && MOTS_FONCTIONNELS.key?(prev_head)
          # après un verbe fini, le COD reste dans le groupe verbal
          # (« font un reflet », « fondra la mer »)
          return false if prev.kind == :word && finite_verb_head?(prev_head)
          # « du/des » (génitif) collé à une PP (« à partir du col ») : pas de
          # frontière ; un article plein (« les escrocs » après « l’ombre ») ouvre
          # bien un nouveau syntagme
          return false if %w[du des].include?(head) && prev2_head && PREPOSITIONS.key?(prev2_head.to_s)

          return true
        end
        # participe passé / adjectif verbal en -é/-i/-u après un mot PLEIN :
        # il ouvre un nouveau groupe (« la date | choisie »), sauf nom propre
        # capitalisé (« le dogue Liberté »). Les verbes finis restent avec leur
        # sujet (« mes pères criaient » -> un seul groupe).
        if prev_head && prev.kind == :word && !MOTS_FONCTIONNELS.key?(prev_head) &&
           !finite_verb_head?(prev_head) &&
           tok.surface[0] == tok.surface[0].downcase &&
           head.match?(/(?:é|ée|és|ées|i|ie|is|ies|u|ue|us|ues|it|ît)s?\z/)
          return true
        end

        # Mode contemporain : frontière entre deux mots PLEINS (« bile | noire »,
        # « reflets | dérisoires », « reins | l'épaule », « pères | criaient »).
        # Les déterminants après un verbe fini restent dans le groupe verbal
        # (règle ci-dessus : « font un reflet »).
        if contemporain && prev.kind == :word && prev_head
          prev_plein = !MOTS_FONCTIONNELS.key?(prev_head) ||
                       CONTEMP_PRONOMS_PLEINS.include?(prev_head)
          plein = !MOTS_FONCTIONNELS.key?(head) || head == 'qui' || PRONOMS.key?(head)
          # la négation « pas » reste dans le groupe verbal (« ne meurt | pas »
          # -> en fait « ne meurt pas » ne coupe pas)
          plein &&= head != 'pas'
          return true if prev_plein && plein
        end

        false
      end

      # Analyse accentuelle d'un Result DÉJÀ calculé (ex. par process_line) :
      # utile aux outils en aval (gem claudel) qui réutilisent une scansion
      # existante. Public.
      # @param res [Scansion::Result] résultat de process_line/scan_line
      # @param text [String] le vers d'origine
      # @param contemporain [Boolean] applique les règles de groupement du
      #   vers contemporain (voir boundary_before?)
      # @return [Scansion::Accents::Analysis]
      def analyze_result(res, text, contemporain: false)
        warns = []
        warns << 'scansion could not align: res.aligned is false' if res.respond_to?(:aligned) && !res.aligned

        # sanitize: un backend peut émettre des apostrophes ou autres signes
        # de ponctuation dans l"IPA — on ne garde que lettres/marques IPA
        syls = res.phones.split('-').map { |s| s.strip.gsub(/[[:punct:]]/u, '') }.reject(&:empty?)
        # Sanity guard: phone segments should be 1:1 with the counted syllables
        # (CLI example: "o-kwɛ̃-dy-fø-dɑ̃-la-lɑ̃-gœʁ-de-ʁɛ-və-ʁi" = 12/12).
        if res.respond_to?(:syllables) && res.syllables != syls.size
          warns << "syllable count (#{res.syllables}) != phone segments (#{syls.size}); alignment may drift"
        end

        # tokenize the NORMALIZED text: its word pieces then line up 1:1 with
        # Scansion.words_of / Result#word_spans
        tokens = tokenize(Scansion.normalize_input(text))
        align_words(res, tokens, syls, warns)
        groups = merge_function_groups(split_caesura(build_groups(tokens, contemporain: contemporain), syls))
        groups.each { |g| g.accent = place_accent(g, syls) }
        wacc = word_accents(tokens, syls, caesura_index(syls.size))

        analysis = Analysis.new(text: text, syllables: syls, tokens: tokens,
                                groups: groups, word_accents: wacc, warnings: warns)
        analysis.warnings.concat(validate(analysis))
        analysis
      end

      private

      # ---- tokenization -------------------------------------------------------

      def tokenize(text)
        text.scan(REGEXP_MOTS).map do |m|
          kind = m.match?(REGEXP_PONCTUATION) ? :punct : :word
          Token.new(surface: m, kind: kind)
        end
      end

      # pieces of a word token, split exactly like Scansion.words_of
      # (apostrophes and hyphens are separators: "l'accuser" -> ["l", "accuser"])
      def pieces(tok)
        tok.surface.split(/['’-]/).reject(&:empty?)
      end

      # ---- token <-> syllable alignment -----------------------------------------
      #
      # Preferred path: Result#word_spans, computed by scansion itself while
      # aligning letters to phones — exact by construction, no extra espeak call.
      #
      # Fallback (results without spans, e.g. espeak-raw fallbacks): phonemize
      # each distinct word in isolation, then greedily match its IPA
      # (schwa-stripped) against consecutive line syllables. Stripping ə absorbs
      # the main source of noise between isolated and in-line phonemization: e
      # caduc restored by scansion in context but absent in the isolated word
      # (and occasionally the reverse). Words that cannot be matched fall back to
      # a proportional split of the remaining syllables and are reported.
      #
      # Note: phonemizer_ffi is not thread-safe (global libespeak-ng state) —
      # wrap corpus-wide calls in a Mutex if you parallelize elsewhere.

      def align_words(res, tokens, syls, warns)
        return if syls.empty?

        words = tokens.select { |t| t.kind == :word }
        return if words.empty?

        spans = res.respond_to?(:word_spans) ? res.word_spans : nil
        if spans && spans.size == words.sum { |t| pieces(t).size }
          si = 0
          words.each do |tok|
            first = nil
            last = nil
            pieces(tok).each do
              sp = spans[si]
              si += 1
              next unless sp && sp[:last] >= sp[:first]

              first = sp[:first] if first.nil? || sp[:first] < first
              last = sp[:last] if last.nil? || sp[:last] > last
            end
            tok.debut = first
            tok.fin = last
          end
          return
        end

        align_words_ipa(words, syls, warns)
      end

      def align_words_ipa(words, syls, warns)
        uniq = words.map { |t| t.surface.downcase }.uniq
        ipa_list = Phonemizer.phonemize(uniq, language: 'fr-fr')
        ipa_list = [ipa_list] if ipa_list.is_a?(String) # single-word input
        ipa = uniq.zip(ipa_list).to_h

        pos = 0
        unmatched = []
        words.each_with_index do |tok, wi|
          target = norm(ipa[tok.surface.downcase])
          start  = pos
          rest_words = words.size - wi # this word + following words
          acc = ''

          if target.empty? # word that phonemizes to nothing (e.g. lone mute e)
            pos += 1 unless syls.size - pos - 1 < rest_words - 1
          else
            while pos < syls.size && (syls.size - pos - 1) >= rest_words - 1
              candidate = acc + norm(syls[pos])
              break unless target.start_with?(candidate)

              acc = candidate
              pos += 1
              break if acc == target
            end
          end

          if pos == start || (!target.empty? && acc != target)
            # no full match: share the remaining syllables proportionally
            share = [[(syls.size - pos).fdiv(rest_words).ceil, 1].max, syls.size - pos].min
            pos += share
            unmatched << tok.surface
          end
          tok.debut = start
          tok.fin   = pos - 1
        end

        warns << "unaligned words (proportional fallback): #{unmatched.uniq.join(', ')}" if unmatched.any?
      end

      def norm(str)
        str.to_s.tr(SCHWA, '').tr('-', '')
      end

      # ---- grouping ------------------------------------------------------------

      # Accent INTERNE de chaque mot plein : sa dernière syllabe à noyau
      # accentué (on remonte au-dessus d'un éventuel schwa final — « muette »
      # mu-ɛ-tə porte donc son accent sur le « ɛ »). Les mots fonctionnels
      # n'ont pas d'accent propre.
      # index de la césure (0-based) : 6//6 pour 12, 4//4 pour 8
      def caesura_index(n)
        if n == 12
          5
        else
          (n == 8 ? 3 : nil)
        end
      end

      # Indices des syllabes portant un accent de mot (ˌ) : dernière syllabe
      # accentuable de chaque mot plein (les mots fonctionnels n'en ont pas).
      # Si +caesura+ est donné (indice de la syllabe de césure, ex. 5 pour un
      # alexandrin), un mot qui chevauche la césure y concentre son accent
      # (ictus de césure).
      # @param tokens [Array<Token>] mots avec leurs indices de syllabes
      # @param syls [Array<String>] syllabes IPA
      # @param caesura [Integer, nil] indice de la syllabe de césure
      # @return [Array<Integer>]
      def word_accents(tokens, syls, caesura = nil)
        acc = []
        tokens.each do |t|
          next unless t.kind == :word && t.debut && t.fin && t.fin >= t.debut
          next if pieces(t).all? { |p| MOTS_FONCTIONNELS.key?(p.downcase) } # mot fonctionnel
          # les verbes finis ne portent pas d’accent secondaire propre (ˌ) :
          # « font », « fondra » restent sans ˌ au milieu du groupe verbal
          next if finite_verb_head?(head_of(t))

          i = t.fin
          i -= 1 while i > t.debut && !accent_bearing?(syls[i])
          # ictus de césure : un mot coupé par la césure (4//4, 6//6) porte son
          # accent secondaire SUR la syllabe de césure, plus fort que sa finale
          # (« res|piration » -> ˌʁɛs et non ˌsjɔ̃)
          if caesura && t.debut <= caesura && caesura <= t.fin &&
             accent_bearing?(syls[caesura]) && caesura < i
            i = caesura
          end
          acc << i if accent_bearing?(syls[i])
        end
        acc.uniq
      end

      # Un groupe rythmique (syntagme) se termine à la frontière suivante :
      # avant une conjonction, un auxiliaire, une préposition (sauf complément
      # « de + nom nu »), ou un déterminant ouvrant un nouveau syntagme ; et
      # après chaque signe de ponctuation. L'accent ira sur la dernière syllabe
      # portant un noyau du groupe.
      def build_groups(tokens, contemporain: false)
        groups = []
        current = []
        tokens.each_with_index do |tok, i|
          if tok.kind == :punct
            unless current.empty?
              groups << Group.new(current, nil)
              current = []
            end
          else
            if !current.empty? && boundary_before?(tokens, i, contemporain: contemporain)
              groups << Group.new(current, nil)
              current = []
            end
            current << tok
          end
        end
        groups << Group.new(current, nil) unless current.empty?
        groups
      end

      # Un groupe composé UNIQUEMENT de mots fonctionnels (et, qui, sans, le…)
      # ne porte pas d'accent : on le fusionne dans le groupe suivant.
      def merge_function_groups(groups)
        out = groups.dup
        i = 0
        while i < out.size - 1
          if all_function?(out[i])
            out[i + 1] = Group.new(out[i].tokens + out[i + 1].tokens, nil)
            out.delete_at(i)
          else
            i += 1
          end
        end
        out
      end

      def all_function?(group)
        group.tokens.all? do |t|
          # « d'or » (de + nom) n'est PAS fonctionnel : « or » est ici le nom,
          # pas la conjonction — sinon le groupe « d'or » collerait au suivant
          next false if t.kind == :word && t.surface.match?(/\Ad['’]/i)

          t.kind == :punct || pieces(t).all? { |p| MOTS_FONCTIONNELS.key?(p.downcase) }
        end
      end

      # Force a group boundary at the caesura (6//6 alexandrine, 4//4 octosyllable)
      # when no punctuation already marks it: the boundary falls on the last
      # accent-bearing syllable at or before the caesura index (0-based).
      def split_caesura(groups, syls)
        n = syls.size
        c = if n == 12
              5
            else
              (n == 8 ? 3 : nil)
            end
        return groups if c.nil?

        s = c
        s -= 1 while s.positive? && (syls[s].nil? || !accent_bearing?(syls[s]))
        # une frontière de groupe (mot plein ou ponctuation) avant la cesure suffit
        return groups if groups.any? { |g| g.tokens.last&.fin && g.tokens.last.fin <= c }

        out = []
        groups.each do |g|
          cover = g.tokens.index { |t| t.debut && t.fin && t.debut <= s && t.fin >= s }
          cover = nil if cover == g.tokens.size - 1 && g.tokens.last.fin == s
          if cover && cover < g.tokens.size - 1
            out << Group.new(g.tokens[0..cover], nil)
            out << Group.new(g.tokens[(cover + 1)..], nil)
          else
            out << g
          end
        end
        out
      end

      # ---- accent placement ----------------------------------------------------

      # Rule 2: walk back from the group's last syllable to the first
      # accent-bearing one. Group boundaries come from punctuation + caesura
      # (rule 3).
      def place_accent(group, syls)
        return nil if group.tokens.empty?

        lo = group.tokens.map(&:debut).compact.min
        hi = group.tokens.map(&:fin).compact.max
        return nil if lo.nil? || hi.nil?

        lo = [lo, 0].max
        hi = [hi, syls.size - 1].min
        return nil if lo > hi

        i = hi
        i -= 1 while i > lo && !accent_bearing?(syls[i])
        i
      end

      # noyau effectif d'une syllabe : ses caractères voyelles, mais un y/ɥ
      # initial suivi d'une autre voyelle est un glide, pas un noyau
      # ("yi" -> i ; "ty" (tu) -> y reste un noyau)
      def nucleus(syl)
        return '' if syl.nil?

        chars = syl.chars.select { |c| VOYELLES.include?(c) }
        chars.shift if chars.size > 1 && GLIDES.include?(chars.first.to_s)
        chars.join
      end

      # une syllabe porte l'accent si son noyau est une vraie voyelle
      # (ni schwa, ni glide seul)
      def accent_bearing?(syl)
        n = nucleus(syl)
        !n.empty? && n != SCHWA
      end

      # ---- validation ----------------------------------------------------------
      #
      # Alexandrines and octosyllables give a free gold standard: the last
      # syllable (rhyme) must be the accent of the last group, and a group
      # boundary near the caesura (syllable 6 of 12, 4 of 8) must carry that
      # group's accent.

      def validate(a)
        w = []
        n = a.syllables.size
        return w unless [8, 12].include?(n)

        last = a.groups.last
        if last.nil? || last.accent != n - 1
          w << "verse #{n}: rhyme (syllable #{n}) is not the last group's accent"
        elsif !accent_bearing?(a.syllables[n - 1])
          w << "verse #{n}: rhyme syllable has no accent-bearing nucleus — suspicious elision at line end"
        end

        c = n == 12 ? 5 : 3 # index 0-based de la cesure
        unless a.groups.any? { |g| g.tokens.last&.fin && g.tokens.last.fin <= c }
          w << "verse #{n}: no group boundary at the caesura (syllable #{c + 1})"
        end
        w
      end
    end
  end
end

# ---- démo -------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  corpus = [
    'Au coin du feu, dans la langueur des rêveries!',
    "Le jour n'est pas plus pur que le fond de ma nuit",
    'Dites, sans l’accuser de chercher un esclave,'
  ]
  Scansion::Accents.analyze_lines(corpus).each do |a|
    puts a.text
    puts "  #{a.render}   (#{a.syllables.size} syll.)"
    puts "  accents (phrase): #{a.accents.map { |i| i + 1 }.join(', ')}"
    puts "  accents (mot):    #{a.word_accents.map { |i| i + 1 }.join(', ')}"
    a.warnings.each { |w| puts "  ⚠ #{w}" }
    puts
  end
end
