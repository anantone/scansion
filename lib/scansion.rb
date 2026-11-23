#!/usr/bin/env ruby
# frozen_string_literal: true
#
# scansion.rb — phonétise des vers français en restaurant le e muet
# (e caduc) selon les règles de la scansion classique.
#
# Règles implémentées :
#   * un e muet interne suivi d'une consonne est prononcé (compté)
#   * un e muet final est prononcé devant un mot à initiale consonantique
#     EN CONTEXTE CLASSIQUE (diérèse active, donc aussi :auto) ; en mode
#     contemporain (plain / --no-dierese) il n'est jamais compté devant une
#     consonne (« mes pères criaient » -> pɛʁ). Élidé devant un mot à
#     initiale vocalique (élision / h muet)
#   * le e muet en fin de vers n'est pas compté, ni devant une pause
#     graphique (, ; : ! ? … —) : rêche, -> ʁɛʃ
#   * la terminaison -ent est prononcée devant une consonne ou un h aspiré
#     à l'intérieur d'un vers, élidée devant une voyelle / un h muet / en fin
#     de vers (avec liaison du t devant une voyelle : peuplent à -> pœplt-a) ;
#     mais après une lettre voyelle (-uent, -ient) le e n'est jamais restauré
#     (perpétuent le -> pɛʁpetylə, 8 syll.)
#   * un e muet final devant un s muet est restauré en contexte classique
#     (tables blanches -> ta-blə-blɑ̃ʃ ; 2 syllabes en contemporain)
#
# La liste complète des règles, avec exemples travaillés, est dans
# docs/scansion_rules.txt.
#
# Note de conception : la restauration passe par l'alignement des lettres
# orthographiques sur les segments phonétiques d'espeak-ng (voir Aligner).
# Si l'alignement échoue pour un mot, le vers entier retombe sur la sortie
# brute d'espeak-ng (préfixe de ligne « ~ ») : le script préfère manquer des
# schwas plutôt que d'en inventer.
# Limites : petite liste de h aspiré (les autres mots en h élident), pas de
# dictionnaire d'exceptions, consonnes finales muettes approximatives.
#
# Dépendances : le gem phonemizer_ffi (backend FFI préféré, dépendance
# déclarée du gem — il tire lui-même le gem `ffi` et appelle libespeak-ng
# directement, donc aussi espeak-ng/libespeak-ng installé :
#   apt install libespeak-ng1   # ou brew install espeak-ng
# ; sur macOS avec un espeak-ng Homebrew « keg-only », définir
# PHONEMIZER_ESPEAK_LIB).
# Replis, dans l'ordre : l'API du gem phonemizer (`gem install phonemizer`),
# le CLI `phonemize` qu'il fournit, puis espeak-ng directement sur le $PATH.
# Le backend FFI produit une IPA identique octet par octet au gem pour notre
# usage (asserté dans spec/scansion_spec.rb).
#
# Structure : le module Scansion est une bibliothèque pure (le require de ce
# fichier est sans effet de bord — pas d'OptionParser sur l'ARGV de l'hôte) ;
# le CLI vit dans Scansion.main et ne tourne que si le fichier est exécuté
# comme script. process_lines mémoïse scan_line par (ligne, options) pour ne
# pas relancer espeak-ng à chaque vers lors de la détection de diérèse en
# deux passes.
#
# Utilisation :
#   scansion [--no-dierese] [-s|--syllables] [FILE|-]
#
# Exemple (un alexandrin de 12 syllabes — e muet interne restauré dans
# « langueur » -> lɑ̃-gœʁ et « rêveries » -> ʁɛ-və-ʁi ; le -e final de
# « rêveries » n'est pas compté car il suit une voyelle, comme « gravée ») :
#   $ echo "Au coin du feu, dans la langueur des rêveries!" | scansion
#   Au coin du feu, dans la langueur des rêveries!
#     ⇒ o-kwɛ̃-dy-fø-dɑ̃-la-lɑ̃-gœʁ-de-ʁɛ-və-ʁi   (12 syll.)

require "optparse"
require "open3"
require_relative "scansion/version"

module Scansion
  SCHWA = "ə"

  VOWEL_PHONE  = /[aeiouyɛɔəɑøœæɒʌɪ]/
  VOWEL_LETTER = /[aeiouyàâäéèêëîïoôöùûüœ]/
  # lettres voyelles par lesquelles un mot SUIVANT peut commencer, pour le
  # test du « e oral » dans elidable_final_e? (remet à -> ʁəmɛta n'est pas
  # une élision)
  NEXT_VOWELISH = /\A[àaâäiîïoôöuùûüywœ]/u
  GLIDE_PHONE  = /\A[jɥw]/
  SOFT_NEXT    = %w[e i y é è ê].freeze # lettres qui adoucissent c/g

  CONSONANT_DIGRAPHS = {
    "ch" => "ʃ", "ph" => "f", "th" => "t",
    "qu" => "k", "ss" => "s", "ck" => "k", "gn" => "ɲ",
  }.freeze

  CONSONANT_LETTERS = {
    "b" => "b", "d" => "d", "f" => "f", "j" => "ʒ", "k" => "k",
    "l" => "l", "m" => "m", "n" => "n", "p" => "p", "q" => "k",
    "r" => "ʁ", "s" => "s", "t" => "t", "v" => "v", "w" => "w",
    "z" => "z", "h" => nil, # h est muet
  }.freeze

  # Suites de lettres finales qui peuvent rester non prononcées une fois tous
  # les segments phonétiques consommés. Toute autre chose fait échouer
  # l'alignement (repli sur la sortie brute). Liste littérale (SILENT_TAIL_LIST)
  # pour rester lisible ; l'expression régulière en est déduite. Ancrage aux
  # deux extrémités, donc l'ordre des alternatives est sans importance.
  SILENT_TAIL_LIST = %w[
    ent ents nt nts nte ntes ns nc ms cs gts ct s t ts d x z p ps g gt
    st ut ôt u au aux eau eaux eux ux ous r n it ds rs c f ufs oeufs m
  ].freeze
  SILENT_TAILS = /\A(?:#{SILENT_TAIL_LIST.map { |t| Regexp.escape(t) }.join("|")})\z/

  # ce qui peut suivre un e muet quasi final avant la terminaison muette :
  # « s » (tables), « ts » (sifflets), « ps », « x » (silex), ou rien (Philippe)
  E_MUET_TAIL = /\A(?:s|ts?|ps|x)?\z/
  # la terminaison après le e de la désinence verbale -ent : « nt » / « nts »
  ENT_TAIL = /\A(?:nts?)\z/

  # digrammes qu'espeak-ng peut rendre par un phone alternatif
  DIGRAPH_ALT = { "gn" => "n" }.freeze

  # digrammes de voyelles prononcés comme un seul noyau syllabique, associés
  # au nombre de voyelles (lettres) qu'espeak-ng émet pour eux (absorber la
  # 2e lettre ; ne pas la laisser manger la voyelle du mot suivant :
  # ou entendre ; ui -> yi)
  DIGRAPH_ONE_PHONE = { "ai" => 1, "au" => 1, "ou" => 1, "eu" => 1,
                         "ei" => 1, "ay" => 1, "ey" => 1, "ui" => 2,
                         "ue" => 1, "oe" => 2 }.freeze # boeufs -> b-øo

  # lettres dont la consonne finale fait liaison devant un mot à initiale
  # vocalique (elle reste donc l'ATTAQUE de la syllabe suivante :
  # les amis -> lɛ-za-mi)
  LIAISON_LETTERS = %w[s x z d g b n m].freeze

  # consonne finale prononcée avec sa valeur de liaison devant une voyelle
  # (les amis -> lɛzami, quand il -> kɑ̃til, grand ami -> gʁɑ̃tami...)
  LIAISON_FINAL = { "s" => "z", "z" => "s", "d" => "t", "g" => "k", "b" => "p" }.freeze

  # dévoisement final tel que le rend espeak-ng (Austerlitz -> ...lits)
  FINAL_DEVOICE = { "z" => "s", "d" => "t", "b" => "p", "g" => "k", "v" => "f" }.freeze

  # Petite liste de mots fréquents à h aspiré (correspondance par préfixe :
  # « hisser » couvre aussi hissera, hissons, hissé...). Un mot à h aspiré
  # est PHONÉTIQUEMENT à initiale vocalique (le h est muet : « hasard » ->
  # /a-zaʁ/) mais BLOQUE l'élision/la liaison du mot précédent :
  # « le hasard » -> lə-a-zaʁ, jamais *la-zaʁ ; « se hisser » -> sə-i-se,
  # jamais *sise. À contraster avec le h muet : « l'homme » -> lɔm (élision).
  # Voir h_aspiré? / elides_before?.
  H_ASPIRE = %w[haie haine hache honte héros hérisson harpe halle
                hurler heaume hocher hibou hisser hasard].freeze

  # Exceptions à la règle « -Cr- + e muet » (docs/scansion_rules.txt 1.5d) :
  # dans ces mots, le e final EST prononcé devant une consonne
  # (astre -> as-tʁə, entendre -> ɑ̃-tɑ̃-dʁə, entre -> ɑ̃-tʁə,
  # être -> ɛ-tʁə, guerre -> gɛ-ʁə, maître -> mɛ-tʁə, moindre -> mwɛ̃-dʁə,
  # œuvre -> œ-vʁə, ventre -> vɑ̃-tʁə...), contrairement à arbre -> aʁbʁ,
  # mettre -> mɛtʁ, fièvre -> fjɛvʁ. Devant une voyelle ou en fin de vers,
  # l'élagage normal s'applique toujours (élision / non compté).
  CR_E_PRONOUNCED = %w[astre battre croître entendre entre être guerre hydre
                      maître moindre œuvre ombre peindre tonnerre ventre].freeze

  Result = Struct.new(:text, :raw, :phones, :syllables, :aligned, :dierese,
                      :word_spans, keyword_init: true) do
    # true si le vers est retombé sur la sortie brute d'espeak-ng (pas d'alignement)
    def fallback? = !aligned
  end

  # État mutable de l'alignement d'UN mot orthographique sur les segments
  # phonétiques (voir align_word). Un Struct pour que les méthodes step
  # partagent et modifient l'index de lettre / le curseur de segments sans
  # longue liste de paramètres. step renvoie true (lettre consommée, on
  # continue), :done (arrêt : alignement réussi tôt — terminaison muette alors
  # que les segments sont épuisés) ou false (alignement impossible → le vers
  # entier retombe sur espeak brut).
  Aligner = Struct.new(
    :word, :segs, :out, :i, :cursor, :n,
    :prev_cons, :prev_vowel_phone, :run_split,
    :next_vowel_initial, :next_word, :prev_fragment, :dierese,
    :dierese_words, :cluster_words, :ent_words,
    keyword_init: true
  ) do
    # Diérèse active pour le mot courant : en mode ciblé (dierese_words
    # renseigné — nil = diérèse globale, [] = aucune), seuls les mots listés
    # sont coupés en deux syllabes.
    def dierese_on?
      dierese_words ? dierese_words.include?(word) : dierese
    end

    # e final d'un mot en -re compté (contexte classique) : même ciblage
    # que la diérèse via cluster_words.
    def cluster_on?
      cluster_words ? cluster_words.include?(word) : dierese
    end

    # -ent prononcé (3e personne du pluriel : t'arrivent, surgissent, marquent)
    # : ciblage mot à mot uniquement (ent_words), jamais en passe globale.
    def ent_on?
      ent_words ? ent_words.include?(word) : false
    end

    def run
      while i < n
        r = step
        return false if r == false
        break if r == :done
      end
      true
    end

    # Consomme une lettre du mot. Aiguille vers step_vowel / step_consonant.
    def step
      ch = word[i]
      two = word[i, 2]

      if cursor >= segs.size
        rest = word[i..]
        if rest.match?(/\Aents?\z/)
          out << ["ɑ̃", true] if ent_on? # -ent prononcé (3e pl.) : ɑ̃ restauré
          self.i = n # désinence -ent : sinon jamais restaurée
        elsif rest.match?(SILENT_TAILS)
          return :done
        elsif i.positive? && rest[0] == word[i - 1]
          self.i += 1 # lettre redoublée en toute fin (pierre -> pjɛʁ)
        elsif rest.match?(/\Aes?\z/)
          if i.positive? && word[i - 1].match?(VOWEL_LETTER) &&
             !Scansion.cluster_re_pronounced?(word, cluster_on?)
            self.i += 1 # e après une lettre voyelle : jamais restauré (gravée)
          else
            out << [SCHWA, true] # e muet final : on le restaure
            self.i += 1
          end
        else
          # plus de phones : les lettres restantes ne peuvent être que muettes
          # (fin de vers) ; on les absorbe plutôt que de faire échouer tout
          # le vers
          self.i = n
        end
        return true
      end

      head = segs[cursor]
      head_vowel = head[0].match?(VOWEL_PHONE)

      # digrammes de consonnes
      if CONSONANT_DIGRAPHS[two] &&
         (head[0] == CONSONANT_DIGRAPHS[two] ||
          (DIGRAPH_ALT[two] && head[0] == DIGRAPH_ALT[two]))
        out << [head, false]
        self.cursor += 1
        # espeak-ng peut rendre ɲ par n+j (éteignent -> etɛnj...)
        if two == "gn" && head[0] == "n" && segs[cursor] &&
           segs[cursor][0] == "j"
          out << [segs[cursor], false]
          self.cursor += 1
        end
        self.i += 2
        self.prev_cons = two
        return true
      end

      ch.match?(VOWEL_LETTER) ? step_vowel(ch, head, head_vowel)
                             : step_consonant(ch, head, head_vowel)
    end

    # Une lettre voyelle face à la tête de segment courante.
    def step_vowel(ch, head, head_vowel)
      # pluriel en -es devant un mot à initiale vocalique : le e muet est
      # PRONONCÉ avec liaison du s (« nouvelles amours » -> nu-vɛ-lə-za-muʁ)
      if ch == "e" && word[i..].to_s == "es" && next_vowel_initial &&
         !head_vowel && Scansion.plural_mute_e?(word)
        out << [SCHWA, true]
        self.i += 1
        self.prev_vowel_phone = true
        return true
      end

      # une lettre voyelle qui amorce une terminaison muette de plusieurs
      # lettres devant un phone consonne n'est pas prononcée du tout
      # (boeufs -> bø, le « ufs » est muet ; les terminaisons d'une seule
      # lettre, comme le u de « tu », sont laissées à la branche glide)
      if !head_vowel && !head.match?(GLIDE_PHONE) &&
         word[i..].to_s.length >= 2 &&
         Scansion.silent_tail_from?(word, i) &&
         !word[i..].to_s.end_with?("x") && # le x de -aux/-eux peut faire liaison (beaux yeux)
         !Scansion.ent_tail?(word, i) # -ent a sa propre règle
        # pluriel en -es devant une voyelle : le e muet est prononcé avec
        # liaison du s (« nouvelles amours » -> nu-vɛ-lə-za-muʁ)
        if word[i..].to_s == "es" && next_vowel_initial &&
           Scansion.plural_mute_e?(word)
          out << [SCHWA, true]
        end
        self.i = n
        return true
      end

      # u muet après g/q suivi d'une voyelle (guerre, qui)
      if ch == "u" && %w[g q].include?(prev_cons) &&
         Scansion.vowel_letter?(word[i + 1])
        self.i += 1
        self.prev_cons = nil
        return true
      end

      # e muet final devant un mot suivant à initiale vocalique : espeak-ng
      # l'a élidé, donc on restaure un schwa SANS consommer la tête de segment
      # (conditions exactes dans elidable_final_e?) ; l'élagage de scansion
      # ci-dessous retire à nouveau ce schwa restauré (élision).
      if Scansion.elidable_final_e?(word, i, head, out, next_vowel_initial, next_word, dierese)
        out << [SCHWA, true]
        self.i += 1
        return true
      end

      # terminaison -ent (chantent, mélangent...) : le e muet avant -nt EST
      # prononcé quand le mot suivant commence par une consonne ou un h
      # aspiré, à l'intérieur d'un vers — MAIS seulement si le e suit une
      # consonne. Après une lettre voyelle, il appartient au groupe voyelle
      # et n'est jamais restauré (-uent, -ient : perpétuent -> pɛʁpety,
      # criaient -> kʁiɛ). On restaure le schwa et on laisse l'élagage de
      # scansion le supprimer devant une voyelle / un h muet / en fin de vers.
      # Devant une voyelle, espeak-ng peut garder la liaison t
      # (peuplent à -> pœplt-a). Une voyelle nasale en tête signifie que le e
      # n'est pas muet (violent -> vjolɑ̃) : on laisse alors la branche voyelle.
      if ch == "e" && Scansion.ent_tail?(word, i) &&
         head[0] != SCHWA && !head.match?(/̃/)
        if ent_on?
          # -ent prononcé (3e pers. pl.) : on abandonne le t de liaison
          # éventuel et on émet la nasale (celle d'espeak si présente, ɑ̃ sinon)
          self.cursor += 1 if head[0] == "t"
          if segs[cursor] && segs[cursor][0].match?(/̃/)
            out << [segs[cursor], true]
            self.cursor += 1
          else
            out << ["ɑ̃", true]
          end
          self.i = n
        elsif next_vowel_initial && head[0] == "t"
          out << [head, false] # liaison du t
          self.cursor += 1
          self.i = n
        elsif i.positive? && word[i - 1].match?(VOWEL_LETTER)
          self.i += 1 # -uent/-ient : le e fait partie du groupe voyelle précédent
        else
          out << [SCHWA, true]
          self.i = n
        end
        return true
      end

      # e après un g/c adouci est muet (vengeance -> vɑ̃ʒɑ̃s, le « ge » ne
      # vaut que ʒ ; pages -> paʒ) — quand il est suivi d'une voyelle, ou
      # d'un s/x final après une voyelle (mais c'est garde son e : c initial)
      if ch == "e" && i >= 1 && %w[c g].include?(word[i - 1]) &&
         !Scansion.cluster_re_pronounced?(word, cluster_on?) &&
         (Scansion.vowel_letter?(word[i + 1]) ||
          (i >= 2 && word[i - 2].match?(VOWEL_LETTER) &&
           Scansion.e_muet_tail?(word, i)))
        self.i += 1
        self.prev_vowel_phone = true
        return true
      end

      # « muet/muette/muets/muettes » : le « ue » vaut /y.ɛ/ (hiatus), même hors
      # diérèse — mu-ɛ-tə fait 3 syllabes (et non myɛ-tə, 2). On émet le « u »
      # comme noyau /y/ et on laisse le « ɛ » dans le segment courant.
      if ch == "u" && word.start_with?("muet") && word[i + 1] == "e" &&
         head[0].match?(/[yɥ]/) &&
         head.each_char.count { |c| c.match?(VOWEL_PHONE) } >= 2
        out << ["u", true]
        segs[cursor] = head[1..] # garder le « ɛ », absorber le glide
        self.i += 1
        self.prev_vowel_phone = true
        return true
      end

      # DIÉRÈSE du « u » : un « u » suivi d'un « é/è », d'un « eu » (majestueux
      # -> ma-jes-tu-eux), ou d'un « a » final (± s/x), que espeak-ng a rendu
      # par le glide « y/ɥ » compte DOUBLE en vers classique (nuée -> nu-ée,
      # exténuée -> ex-té-nu-ée, majestueux -> ma-jes-tu-eux, et passé simple
      # en -ua : ruas -> ru-as). Limité à ces cas pour ne pas scinder les
      # « ue »/« ua » internes (ruelle -> ʁɥɛl, nuage -> nyaʒ, 1 syllabe).
      # Le glide est absorbé sans être émis : la voyelle restaurée « u » tient
      # lieu de noyau, et la suite de la voyelle (le « e » de « é », le « a »
      # de « rua ») reste dans le segment courant.
      # le glide peut aussi être « w » (dénoué -> de-nwe : le « ou » vaut /u/
      # et le « é » qui suit forme hiatus dé-nu-é en vers classique)
      if dierese_on? && ch == "u" &&
         (word[i + 1].to_s.match?(/[éè]/) ||
          word[(i + 1)..].to_s.match?(/\Aa(?:[sx])?\z/) ||
          word[(i + 1)..].to_s.start_with?("eu") ||
          (dierese_words && word[i + 1] == "a")) && # u+a en mode ciblé (suaves)
         head[0].match?(/[yɥw]/) &&
         (head.each_char.count { |c| c.match?(VOWEL_PHONE) } >= 2 ||
          (segs[cursor + 1] && segs[cursor + 1][0].match?(VOWEL_PHONE)))
        out << ["u", true] # voyelle restaurée : diérèse
        if head.length > 1
          segs[cursor] = head[1..] # garder le noyau (le e de é), absorber le glide
        else
          self.cursor += 1 # glide isolé (ɥ) : le consommer
        end
        self.i += 1
        self.prev_vowel_phone = true
        return true
      end

      # DIÉRÈSE du « ou » devant « a » (et « é/è » : dénoué -> dé-nu-é) : un
      # « ou » suivi d'un « a »/« é »/« è » que espeak-ng a rendu par le glide
      # « w » compte DOUBLE en vers classique
      # (couardise -> cou-ar-dise, joua -> jou-a, dénoué -> dé-nu-é).
      # Le glide « w » est absorbé sans être émis, la voyelle restaurée « u »
      # tient lieu de noyau, et le « a »/« e » reste dans le segment courant.
      if dierese_on? && ch == "o" && word[i + 1] == "u" &&
         (word[i + 2].to_s.match?(/[aéè]/) ||
          (dierese_words && word[i + 2] == "i")) && # ou+i ciblé (épanoui)
         head[0] == "w" &&
         (head.length > 1 ||
          (segs[cursor + 1] && segs[cursor + 1][0].match?(VOWEL_PHONE)))
        out << ["u", true] # voyelle restaurée : diérèse (le « ou » vaut u)
        if head.length > 1
          segs[cursor] = head[1..] # garder le « a », absorber le « w »
        else
          self.cursor += 1 # glide isolé : le consommer
        end
        self.i += 2 # consommer « o » et « u »
        self.prev_vowel_phone = true
        return true
      end

      if head_vowel &&
         !Scansion.final_e_before_vowel?(word, i, head, out, next_vowel_initial)
        # (un e quasi final devant un mot SUIVANT à initiale vocalique ne
        # consomme jamais de segment voyelle : si la tête est une voyelle
        # autre que le schwa, elle appartient au mot suivant — la branche
        # elidable_final_e? ci-dessus restaure sans consommer (ou la branche
        # ch == "e" ci-dessous le fait, quand la tête est une consonne).
        # Devant un mot à initiale consonantique, une tête voyelle est celle
        # de ce mot (bouquet de -> bu-kɛ) et doit être consommée.)
        # digramme de voyelles en une syllabe (ou, ai, ui -> yi...) :
        # consommer toute la suite et absorber la deuxième lettre — sauf si
        # la suite chevauche une frontière de mot (ou entendre -> suite
        # « uɑ̃ » : ne garder que 'u')
        # un digramme ne se déclenche que si la lettre n'est pas déjà la
        # deuxième lettre d'un digramme précédent (alouettes : ou+e -> le e
        # compte encore)
        digraph = DIGRAPH_ONE_PHONE[ch + word[i + 1].to_s]
        run_vowels = head.each_char.count { |c| c.match?(VOWEL_PHONE) }
        # supprimé quand la lettre courante est déjà la 2e lettre d'un
        # digramme avec la précédente (alouettes : ou+e -> le e compte
        # encore ; mais yeux : y est le glide j, donc eu EST un digramme)
        # — SAUF si la suite contient 2 voyelles (aiguille -> ɛ-g-yi-j :
        # le « ui » EST ici un digramme à 2 voyelles, contrairement à alouettes)
        digraph = nil if i.positive? &&
                        DIGRAPH_ONE_PHONE.key?(word[i - 1].to_s + ch) &&
                        run_vowels <= 1
        # la lettre courante est la 2e d'un digramme ET la suite contient
        # 2 voyelles : le digramme est la paire PRÉCÉDENTE (aiguille ->
        # ɛ-g-yi-j, le « ui » = 2 lettres u+i rendues par la suite « yi »)
        if digraph.nil? && i.positive? && run_vowels > 1 &&
           DIGRAPH_ONE_PHONE.key?(word[i - 1].to_s + ch)
          digraph = DIGRAPH_ONE_PHONE[word[i - 1].to_s + ch]
        end
        # un digramme dont la suite est une paire glide+voyelle (muette -> yɛ,
        # tuer -> ye) est prononcé comme la suite ENTIÈRE, pas coupée en deux
        glide_run = run_vowels == 2 && head[0].match?(/[ɥyjw]/)
        # un digramme à 2 voyelles (oe -> øo : Noël) dont la suite contient
        # exactement 2 voyelles devant un mot suivant à initiale vocalique
        # est ambigu : la suite peut chevaucher la frontière de mot
        # (boeufs au -> ø+o). Dans ce cas, ne prendre qu'UNE voyelle et
        # laisser le reste au mot suivant.
        boundary_run = next_vowel_initial && digraph.to_i > 1 &&
                       run_vowels == digraph && !glide_run
        # une suite glide+voyelle de 2 noyaux devant un mot suivant à initiale
        # vocalique ne peut pas être avalée entière : la 2e voyelle appartient
        # au mot suivant (étendue où -> « yu » = y de étendue + u de où)
        swallow_run = next_vowel_initial && run_vowels > digraph.to_i
        if digraph && !boundary_run && !swallow_run &&
           (run_vowels <= digraph || glide_run)
          out << [head, false]
          self.cursor += 1
          eat = 2
          # la 2e lettre du digramme peut encore être prononcée comme un
          # glide dans son propre segment (ay -> ɛ+j : rayonner -> ʁɛ-jɔn)
          # — seulement en milieu de mot, donc un digramme final (fou, tout)
          # ne vole jamais le glide initial du mot suivant
          if i + 2 < n && word[i + 1] == "y" && word[i + 2] != "l" &&
             segs[cursor] && segs[cursor][0].match?(GLIDE_PHONE)
            out << [segs[cursor], false]
            self.cursor += 1
          end
        else
          # consommer la part du digramme dans la suite (ou UNE voyelle quand
          # il n'y a pas de digramme) : une suite peut chevaucher une frontière
          # de mot (violent héros -> segment « ɑ̃e » = ɑ̃ + é de héros ;
          #  nuit est -> segment « yiɛ » = yi de nuit + ɛ de est)
          take = digraph ? [run_vowels, digraph].min : 1
          take = 1 if boundary_run
          units = head.scan(/#{VOWEL_PHONE.source}\p{Mn}*/)
          consumed = units.first(take).join
          rest = head[consumed.length..].to_s
          # espeak-ng fait parfois écho à la 2e lettre du digramme
          # (pays -> p-ɛ-i, paysage -> p-ɛ-i-zaʒ) : on avale cet écho quand
          # le mot se termine juste après le digramme, ou en milieu de mot
          # avant une consonne (mais ou entendre garde la voyelle du mot
          # suivant : mot suivant à initiale vocalique)
          if digraph && rest.length == 1 && rest.match?(VOWEL_PHONE) &&
             (word[(i + 2)..].to_s.match?(/\A(?:s|x)?\z/) ||
              (!Scansion.vowel_letter?(word[i + 2]) && word[i + 2])) &&
             !next_vowel_initial
            rest = ""
          end
          if rest.empty?
            out << [head, false]
            self.cursor += 1
          else
            out << [consumed, false]
            segs[cursor] = rest
            self.run_split = true
          end
          eat = 1
          eat += 1 if digraph
        end
        # absorber un n/m fermé, éventuellement à travers un digramme de
        # voyelles (maintenant : a+i+n -> ɛ̃) — mais pas le e muet de -ent
        absorbed_nasal = false
        j = i + eat
        nxt = segs[cursor].to_s[0]
        if word[j].to_s.match?(/[nm]/) &&
           !Scansion.vowel_letter?(word[j + 1]) &&
           !(nxt == word[j] && %w[n m].include?(nxt)) # hymne : le phone m est encore en attente
          eat = j - i + 1
          absorbed_nasal = true
        end
        self.i += eat
        # quand une suite chevauchant une frontière a été coupée
        # (boeufs au -> ø+o), les lettres restantes après le digramme peuvent
        # former une terminaison muette (boeufs -> bø, le « ufs » est muet)
        self.i = n if boundary_run && Scansion.silent_tail_from?(word, i)
        # liaison de ce n/m devant une voyelle (un art -> œ̃naʁt)
        # — seulement quand le nasal est la dernière lettre du mot, pas une
        # lettre interne (montmartre ne doit pas faire liaison avec son propre m)
        if absorbed_nasal && next_vowel_initial && j == n - 1 &&
           segs[cursor] && segs[cursor][0].match?(/[nm]/)
          out << [segs[cursor], false]
          self.cursor += 1
        end
        self.prev_cons = nil
        self.prev_vowel_phone = true
        return true
      elsif head.match?(GLIDE_PHONE) &&
            (%w[i u o y].include?(ch) ||
             (ch == "a" && i.positive? && word[i - 1].match?(VOWEL_LETTER)) ||
             # e de eu/ei rendu comme un glide (joyeuse -> ʒwa-jøz)
             (ch == "e" && DIGRAPH_ONE_PHONE.key?("e" + word[i + 1].to_s)))
        # glide devant une voyelle (vieux, huit, oi...)
        # DIÉRÈSE : un « i » devant une voyelle pleine qu'espeak-ng a rendu
        # comme un glide compte pour DEUX syllabes en vers (lion -> li-jɔ̃,
        # violent -> vi-jɔ-lɑ̃, dieu -> di-jø) — sauf « hier » [jɛʁ]
        if dierese_on? && ch == "i" && word != "hier" &&
           word[i + 1].to_s.match?(/[aàâäeéèêoôöœu]/) &&
           segs[cursor + 1] && segs[cursor + 1][0].match?(VOWEL_PHONE)
          out << ["i", true] # voyelle restaurée : diérèse
        end
        out << [head, false]
        self.cursor += 1
        self.i += 1
        # -il/-ill fait partie du glide (œil, soleil, jaillisse...) ;
        # idem pour une voyelle avalée quand aucun phone voyelle ne suit
        # (feuilles)
        self.i += 1 while word[i] == "l" ||
                       (Scansion.vowel_letter?(word[i]) && word[i] != "e" &&
                        !(segs[cursor] && segs[cursor][0].match?(VOWEL_PHONE)))
        # un segment voyelle juste après le glide, en milieu de mot, est le
        # noyau de la lettre courante (a -> j+a : effroyable, voyage)
        # — mais jamais une voyelle NASALE : elle appartient à un n/m suivant
        # (voyant -> vwa-jɑ̃-t, pas vwa-ja-nt)
        if i < n && segs[cursor] && segs[cursor][0].match?(VOWEL_PHONE) &&
           !segs[cursor].match?(/̃/) &&
           word[i] != "l" && !word[i].match?(VOWEL_LETTER)
          out << [segs[cursor], false]
          self.cursor += 1
        end
        self.prev_cons = nil
        self.prev_vowel_phone = false
        return true
      elsif ch == "e"
        if i.positive? && word[i - 1].match?(VOWEL_LETTER) &&
           Scansion.e_muet_tail?(word, i) &&
           !Scansion.cluster_re_pronounced?(word, cluster_on?)
          # le e FINAL après une lettre voyelle appartient au groupe voyelle
          # et n'est jamais compté (gravée -> gʁav, suivie -> syi-vi) ; un e
          # interne avant une consonne est compté (alouettes -> a-lou-e-tte)
          self.i += 1
          self.prev_vowel_phone = true
          return true
        end
        if i >= 2 && word[i - 1] == "r" &&
           !word[i - 2].match?(VOWEL_LETTER) &&
           Scansion.e_muet_tail?(word, i) &&
           !Scansion.cr_e_pronounced?(word) &&
           !Scansion.cluster_re_pronounced?(word, cluster_on?)
          # e muet après un cluster -Cr- est MUET même devant une consonne :
          # sombre -> sɔ̃bʁ, nombre -> nɔ̃bʁ, mettre -> mɛtʁ, fièvre -> fjɛvʁ
          # (mais tables -> tablə : le -l- est conservé).
          # SAUF les exceptions CR_E_PRONOUNCED (voir cr_e_pronounced?) et,
          # en contexte classique (dierese), les mots en -Cre dont le e final
          # est compté (voir cluster_re_pronounced? : notre -> no-tʁə) :
          # on laisse alors passer à la restauration normale ci-dessous.
          self.i += 1
          self.prev_vowel_phone = true
          return true
        end
        # e après un y prononcé comme glide (appuyer -> a-p-yi-j-e) : le « j »
        # et la voyelle qui suivent appartiennent à ce « e » (le r final reste
        # muet) — sinon le « j » bloquerait l'alignement du mot suivant
        if head[0] == "j" && i.positive? && word[i - 1] == "y"
          out << [head, false]
          self.cursor += 1
          if segs[cursor] && segs[cursor][0].match?(VOWEL_PHONE)
            out << [segs[cursor], false]
            self.cursor += 1
          end
          self.i += 1
          self.prev_vowel_phone = true
          return true
        end
        # e muet : c'est ici la restauration
        out << [SCHWA, true]
        self.i += 1
        self.prev_vowel_phone = true
        return true
      elsif i.positive? && (word[i - 1].match?(VOWEL_LETTER) || word[i - 1] == "h")
        # deuxième lettre d'un digramme de voyelles (ai, au, ou, ui, eu...) :
        # un phone pour deux lettres, absorbée en silence ; aussi la voyelle
        # d'un mot à h muet après élision (l'homme -> lɔm)
        self.i += 1
        self.prev_cons = nil
        self.prev_vowel_phone = true
        return true
      elsif i.zero?
        # voyelle initiale muette (alors -> lɔʁ)
        self.i += 1
        self.prev_cons = nil
        self.prev_vowel_phone = false
        return true
      else
        return false
      end
    end

    # Une lettre consonne face à la tête de segment courante.
    def step_consonant(ch, head, head_vowel)
      self.prev_vowel_phone = false
      exp = Scansion.expected_consonant(ch, word[i + 1].to_s)
      # s intervocalique sonorisé en z (gueuse, désormais... ; aussi devant
      # un h muet : déshonneur -> de-zɔ-nœʁ)
      exp = "z" if ch == "s" && i.positive? &&
                   word[i - 1].match?(VOWEL_LETTER) &&
                   (Scansion.vowel_letter?(word[i + 1]) || word[i + 1] == "h")
      # s initial sonorisé en z devant une consonne voisée quand espeak-ng
      # l'a fait (sveltesse -> zvɛltɛs)
      exp = "z" if ch == "s" && i.zero? && head[0] == "z"
      # le mot c' devant une voyelle -> s (c'est, c'était...)
      exp = "s" if ch == "c" && word == "c" && next_vowel_initial
      # c muet dans sc- devant une voyelle douce (scellé -> sɛle, scintille)
      if ch == "c" && i.positive? && word[i - 1] == "s" &&
         SOFT_NEXT.include?(word[i + 1].to_s)
        self.i += 1
        return true
      end
      # -tion/-tieux -> sjon (dilatation, captieux), mais question -> kɛstjɔ̃
      # et -tié/-tier gardent leur t (pitié -> pitje, sentier -> sɑ̃tje) :
      # ne se déclenche que si espeak-ng a réellement supprimé le t pour un s
      exp = "s" if ch == "t" && word[i + 1] == "i" &&
                   Scansion.vowel_letter?(word[i + 2]) &&
                   word[i - 1] != "s" && head[0] == "s"
      # second(e) se prononce avec un g dur (seconde -> səgɔ̃d)
      exp = "g" if ch == "c" && word.start_with?("second")

      if exp.nil? && ch != "x" # h muet (x traité plus bas)
        if ch == "h" && head[0] == "h"
          # h qu'espeak-ng a réellement prononcé (hier -> hiəʁ)
          out << [head, false]
          self.cursor += 1
        end
        self.i += 1
        self.prev_cons = "h"
        return true
      end

      if Scansion.silent_tail_from?(word, i) && next_word &&
         Scansion.expected_consonant(next_word[0].to_s, next_word[1].to_s) == head[0] &&
         !(segs[cursor + 1] && segs[cursor + 1][0] == head[0])
        # terminaison muette : le segment unique est le phone initial du mot
        # suivant (noms célestes -> nɔ̃selɛst, est son -> ɛsɔ̃, nœud de ->
        # nødə, vieux sperme -> vjøspɛʁm). Mais quand espeak-ng a dupliqué le
        # phone (cher raison -> ʁʁɛz), chaque mot prend le sien.
        self.i = n
        return true
      end

      # g muet après n devant une consonne (longtemps -> lɔ̃tɑ̃)
      if ch == "g" && i.positive? && word[i - 1] == "n" &&
         !%w[ɲ n g ʒ].include?(head[0])
        self.i += 1
        return true
      end

      # p muet après m (compte -> kɔ̃t)
      if ch == "p" && i.positive? && word[i - 1] == "m" && head[0] != "p"
        self.i += 1
        return true
      end

      # p muet devant t (sept -> sɛt)
      if ch == "p" && word[i + 1] == "t" && head[0] == "t"
        self.i += 1
        return true
      end

      # t muet devant m (montmartre -> mɔ̃-maʁ-tʁ)
      if ch == "t" && word[i + 1] == "m" && head[0] != "t"
        self.i += 1
        return true
      end

      # r muet devant l quand espeak l'a supprimé (waterloo -> wɔ-tə-lu)
      if ch == "r" && word[i + 1] == "l" && head[0] == "l"
        self.i += 1
        return true
      end

      # l muet devant un s final que espeak A bien sonorisé
      # (fils -> fis, mais ils -> il)
      if ch == "l" && word[i + 1] == "s" && i + 2 == n && head[0] == "s"
        out << [head, false]
        self.cursor += 1
        self.i = n
        self.prev_cons = "s"
        return true
      end

      if ch == "x" && (head[0] == "k" || %w[s z g].include?(head[0]))
        if head[0] == "k" # x -> ks
          out << [head, false]
          self.cursor += 1
          if segs[cursor] && segs[cursor][0] == "s"
            out << [segs[cursor], false]
            self.cursor += 1
          end
        else # six, dix, existe -> gz...
          out << [head, false]
          self.cursor += 1
          if head[0] == "g" && segs[cursor] && segs[cursor][0] == "z"
            out << [segs[cursor], false]
            self.cursor += 1
          end
        end
        self.i += 1
        return true
      end

      # -ll- après une voyelle se rend par j (aiguille -> ɛgij)
      if ch == "l" && i.positive? && word[i - 1].match?(VOWEL_LETTER) &&
         head[0] == "j"
        out << [head, false]
        self.cursor += 1
        self.i += 1 while word[i] == "l"
        self.prev_cons = "l"
        return true
      end

      # t initial fondu dans la liaison du mot précédent
      # (et toi -> etwa : le t est celui de et)
      if i.zero? && ch == "t" && head[0] != "t" &&
         (head_vowel || head.match?(GLIDE_PHONE))
        self.i += 1
        return true
      end

      # une nasale en coda que le mot suivant commence aussi par cette nasale
      # peut être l'initiale du mot suivant (quand nous -> kɑ̃-nu : le n
      # appartient à « nous ») : si la nasale suit une voyelle, que le reste du
      # mot courant est une terminaison muette et que la tête est suivie d'une
      # voyelle, ne pas consommer ici (sinon « nous nous » perdrait son n)
      if next_word && next_word[0] == ch && head[0] == exp &&
         ch.match?(/[nm]/) && i.positive? && word[i - 1].match?(VOWEL_LETTER) &&
         word[(i + 1)..].to_s.match?(SILENT_TAILS) &&
         segs[cursor + 1] && segs[cursor + 1][0].match?(VOWEL_PHONE)
        self.i = n
        return true
      end

      if head[0] == exp || (ch == "w" && head[0] == "v") || # wagon -> vagɔ̃
         (i == n - 1 && FINAL_DEVOICE[ch] == head[0]) # dévoisement final (Austerlitz -> ...lits)
        out << [head, false]
        self.cursor += 1
        self.i += 1
        self.prev_cons = ch
      elsif next_vowel_initial && word[i..].to_s.match?(/[sdzgb]\z/) &&
            head[0] == LIAISON_FINAL[word[i..][-1].to_s]
        # liaison d'une consonne finale devant une voyelle (les amis -> lɛzami,
        # fronts étoilés -> fʁɔ̃zetwal, quand il -> kɑ̃til, grand ami...)
        # pluriel en -es : le e muet est prononcé avant la liaison
        # (« nouvelles amours » -> nu-vɛ-lə-za-muʁ)
        if word[i..].to_s.end_with?("es") && Scansion.plural_mute_e?(word)
          out << [SCHWA, true]
        end
        out << [head, false]
        self.cursor += 1
        self.i = n
        self.prev_cons = ch
      elsif next_vowel_initial && word[i..].to_s.match?(/\A(?:n?sts?|x)\z/) &&
            head[0] == "t"
        # liaison d'un -st / -x final devant une voyelle (est autre -> ɛtotʁ)
        out << [head, false]
        self.cursor += 1
        self.i = n
        self.prev_cons = ch
      elsif i == n - 1 && ch == "r" && next_vowel_initial && head[0] != "ʁ"
        # liaison r supprimée par espeak-ng (qu'amer aucun -> ka-meʁ-o)
        out << ["ʁ", true]
        self.i += 1
      elsif prev_fragment && run_split && word[i..].to_s.size >= 2 &&
            head[0].match?(VOWEL_PHONE) &&
            Scansion.silent_tail_from?(word, i) &&
            segs[cursor + 1] &&
            !segs[cursor + 1][0].match?(VOWEL_PHONE) &&
            Scansion.expected_consonant(word[i..][-1], nil) == segs[cursor + 1][0]
        # le reste de la suite voyelle appartient au mot précédent
        # (fragment d'apostrophe : c' est -> se|ɛ) : on l'émet ici pour que
        # le curseur avance au-delà de la suite et que la terminaison muette
        # puisse correspondre
        out << [head, false]
        self.cursor += 1
        self.prev_vowel_phone = true
      elsif %w[n m].include?(ch) && head.match?(/̃/) &&
            head[0].match?(/[ɑɛɔœ]/) &&
            word[(i + 1)..].to_s.match?(SILENT_TAILS) # NB : depuis i+1, pas i (soyons, diligently...)

        # n/m fermé par une terminaison muette, rendu comme une voyelle nasale
        # (soyons -> swa-jɔ̃, le s final est muet). Avancer seulement après la
        # lettre nasale : un -t final devant un mot à initiale vocalique est une
        # liaison et doit encore être consommé (voyant à -> vwa-jɑ̃-ta).
        # Si la suite nasale contient une voyelle de plus et que le mot suivant
        # commence par une voyelle, cette voyelle appartient au mot suivant
        # (comment il -> « ɑ̃i » = ɑ̃ de comment + i de il) : on ne garde que la
        # nasale et on laisse le reste dans le segment courant.
        units = head.scan(/#{VOWEL_PHONE.source}\p{Mn}*/)
        if next_vowel_initial && units.size > 1
          out << [units.first, false]
          segs[cursor] = units[1..].join
          self.run_split = true
          self.i = n
        else
          out << [head, false]
          self.cursor += 1
          self.i += 1
        end
      elsif Scansion.silent_tail_from?(word, i)
        # terminaison muette quel que soit le segment suivant (et, tables,
        # dont, fronts, coups...) : les lettres restantes ne sont pas prononcées
        self.i = n
      elsif i.positive? && word[i - 1] == ch
        # consonne redoublée prononcée une seule fois (belle, bonne, mettra...)
        self.i += 1
        self.prev_cons = ch
      else
        return false
      end
      true
    end
  end

  class << self
    # -- petits prédicats sur les lettres (partagés avec Aligner) ------

    def vowel_letter?(ch) = ch.to_s.match?(VOWEL_LETTER)
    def silent_tail_from?(word, i) = word[i..].to_s.match?(SILENT_TAILS)
    def e_muet_tail?(word, i) = word[(i + 1)..].to_s.match?(E_MUET_TAIL)
    def ent_tail?(word, i) = word[(i + 1)..].to_s.match?(ENT_TAIL)

    # Forme courte : word[i] est un e muet quasi final devant un mot suivant
    # à initiale vocalique, la tête n'est pas un schwa prononcé, et le mot a
    # déjà une voyelle à lui. Sert à empêcher un tel e de consommer le segment
    # voyelle de tête (la voyelle appartient au mot suivant).
    def final_e_before_vowel?(word, i, head, out, next_vowel_initial)
      word[i] == "e" && next_vowel_initial && head[0] != SCHWA &&
        e_muet_tail?(word, i) &&
        out.any? { |ph, _| ph[0].match?(VOWEL_PHONE) }
    end

    # Forme longue (ajoute la garde du « e oral ») : le e muet est vraiment
    # élidé par espeak-ng parce que le mot suivant est à initiale vocalique,
    # donc on restaure un schwa ici (l'élagage de scansion le retire ensuite).
    # PAS une élision quand la tête est un e/ɛ ORAL que le mot suivant ne peut
    # pas produire : c'est la voyelle propre de ce mot (remet à -> ʁəmɛta) ;
    # un ɛ̃ nasal appartient au mot suivant (encore informe -> ...kɔʁɛ̃f...).
    # PAS non plus une élision pour les mots en -Cr- à e muet (sombre,
    # mettre) : leur e est muet de toute façon, même devant un h aspiré
    # (sombre héros -> sɔ̃-bʁe-ʁo, pas sɔ̃-bʁə-...) ; CR_E_PRONOUNCED
    # (voir cr_e_pronounced?) est exempté.
    def elidable_final_e?(word, i, head, out, next_vowel_initial, next_word, dierese = false)
      return false unless final_e_before_vowel?(word, i, head, out, next_vowel_initial)
      return false if next_word && y_glide?(next_word) # pas d'élision devant /j/
      # un e FINAL en -Cr- (sombre, mettre — terminaison vide/x, PAS avant un
      # s muet) est muet même devant un h aspiré (sombre héros ->
      # sɔ̃-bʁe-ʁo), donc ne jamais le restaurer comme élision ; la branche
      # -Cr- de step_vowel s'en charge. Les mots en -es (propres airs ->
      # pʁɔ-pʁə-zɛʁ) gardent leur e via la règle 1.5. CR_E_PRONOUNCED
      # (voir cr_e_pronounced?) exempté.
      return false if cr_mute_final_e?(word, i, dierese)
      return false if %w[e ɛ].include?(head[0]) && !head.match?(/̃/) &&
                      next_word.to_s.match?(NEXT_VOWELISH)
      true
    end

    # CR_E_PRONOUNCED avec tolérance pour le pluriel en -s/-x (astres, hydres,
    # tonnerres, maîtres…)
    # e muet + s/x final (pluriel : « âmes », « nouvelles », « tables ») :
    # devant un mot à initiale vocalique, le e est PRONONCÉ avec liaison
    # du s (« âmes hautaines » -> â-mə-zɔ-tɛn) — l'élagage ne le retire pas.
    def plural_mute_e?(word)
      w = word.to_s.downcase
      return false unless w.match?(/e[sx]\z/)
      stem = w[0...-2]
      l = stem[-1].to_s
      l.match?(/[bcdfghjklmnpqrstvwxz]/) || stem.end_with?("qu", "gu")
    end

    def cr_e_pronounced?(word)
      CR_E_PRONOUNCED.any? { |w| word == w || word == "#{w}s" || word == "#{w}x" }
    end

    # En contexte classique (dierese actif), le e final d'un mot en -Cre
    # (consonne + r + e : notre, vivre, âpre, spectre, meurtre, centre,
    # pauvre, ivre, ombre, sombre, décembre…) est COMPTÉ — no-tre, vi-vre,
    # â-pʁə, mœʁ-tʁə… La règle 1.5d (e muet après -Cr- jamais compté) est une
    # règle de prononciation moderne : elle ne s'applique qu'en mode
    # contemporain (dierese: false / --no-dierese).
    # En contexte classique, le e final de tout mot en -re est COMPTÉ
    # (notre -> no-tʁə, vivre -> vi-vʁə, mais aussi -ère/-oire/-ire :
    # mère -> mè-re, chère -> chè-re, gloire -> gloi-re, terre -> ter-re…).
    # `on` = false en mode contemporain, true sinon (ou ciblage cluster_words).
    def cluster_re_pronounced?(word, on)
      w = word.sub(/s\z/, "") # tolérance pour le pluriel en -s (pauvres, gloires…)
      on && (w.end_with?("re") || w.match?(/[cgq]u?e\z/))
    end

    # word[i] est un e strictement final (terminaison vide ou x) après un
    # cluster -Cr- dont le e est muet (sombre -> sɔ̃bʁ, mettre -> mɛtʁ) —
    # SAUF CR_E_PRONOUNCED (astre -> as-tʁə, entendre -> ɑ̃-tɑ̃-dʁə, …) et,
    # en contexte classique, sauf les mots en -Cre comptés
    # (voir cluster_re_pronounced? : notre -> no-tʁə en vers classique).
    def cr_mute_final_e?(word, i, dierese = false)
      i >= 2 && word[i - 1] == "r" && !word[i - 2].match?(VOWEL_LETTER) &&
        word[(i + 1)..].to_s.match?(/\A(?:x)?\z/) && !cr_e_pronounced?(word) &&
        !cluster_re_pronounced?(word, dierese)
    end

    # -- phonétisation -------------------------------------------------

    # Normalise la ligne d'entrée pour words_of ET espeak, afin que lettres et
    # phones restent cohérents : entités HTML (&nbsp; etc.) et chiffres
    # (espeak lit « 31 » comme « trente et un », words_of les ignore).
    # Idempotent : scan_line normalise une fois et passe la ligne nettoyée en
    # aval ; espeak normalise à nouveau seulement pour rester sûr comme point
    # d'entrée autonome.
    def normalize_input(line)
      line.gsub(/&[a-zA-Z#0-9]+;/, " ").gsub(/\d+/, " ")
    end

    # Phonétise, en essayant dans l'ordre : le backend FFI en processus
    # (gem phonemizer_ffi, appelle libespeak-ng directement — pas de
    # fork/exec par mot, sortie identique octet par octet au gem, voir
    # spec/scansion_spec), puis l'API du gem phonemizer (son nom de require),
    # puis le CLI `phonemize` qu'il fournit, puis espeak-ng directement.
    # Chaque stratégie renvoie nil en cas d'échec (LoadError compris), sauf le
    # dernier recours qui laisse l'erreur d'espeak-ng se propager.
    def espeak(line)
      line = normalize_input(line)
      raw = phonemizer_ffi(line)
      raw = phonemizer_gem(line) if raw.nil?
      raw = cli_phonemize_safe(line) if raw.nil?
      raw = espeak_ng(line) if raw.nil?
      clean_ipa(raw.to_s)
    end

    # Le backend FFI, fourni par le gem phonemizer_ffi (dépendance du gem
    # scansion) : même API Phonemizer.phonemize, mais en processus, appelant
    # libespeak-ng directement. Mémoïsé comme indisponible après le premier
    # échec (gem ffi ou libespeak-ng manquants) pour ne pas retenter toute la
    # chaîne de repli à chaque mot.
    def phonemizer_ffi(line)
      return nil if @ffi_unavailable
      require "phonemizer_ffi"
      Phonemizer.phonemize(line, language: "fr")
    rescue StandardError, LoadError
      @ffi_unavailable = true
      nil
    end

    # L'API du gem phonemizer.
    def phonemizer_gem(line)
      require "phonemizer"
      begin
        Phonemizer.phonemize(line, language: "fr")
      rescue ArgumentError, NoMethodError
        Phonemizer.phonemize(line, "fr")
      end
    rescue StandardError, LoadError
      nil
    end

    def cli_phonemize_safe(line)
      cli_phonemize(line)
    rescue StandardError
      nil
    end

    # espeak-ng directement (dernier recours).
    def espeak_ng(line)
      Open3.capture3("espeak-ng", "-q", "--ipa", "-v", "fr",
                     stdin_data: line)[0]
    end

    # L'exécutable `phonemize` fourni par le gem phonemizer.
    # Les flags exacts du CLI peuvent varier, donc on essaie les formes
    # plausibles à tour de rôle.
    def cli_phonemize(line)
      [["--lang", "fr"], ["-l", "fr"], []].each do |flags|
        out, _err, status = Open3.capture3("phonemize", *flags, stdin_data: line)
        return out if status.success? && !out.strip.empty?
      end
      raise "la commande `phonemize` n'a pas fonctionné"
    end

    # Nettoie le flux IPA brut : supprime les marqueurs de changement de langue
    # d'espeak-ng « (en) »/« (fr) » EN ENTIER — ne retirer que les parenthèses
    # laisserait des segments parasites « en »/« fr » qui cassent l'alignement
    # (qu'hier -> (en)kwhˈiə(fr)). Puis supprime espaces, accents de stress,
    # marques de liaison ET ponctuation : espeak-ng garde « , » (et parfois
    # « . ») dans le flux IPA, alors que words_of() la supprime, donc un
    # segment « , » parasite casserait l'alignement. Supprime aussi les
    # caractères de largeur nulle/BOM, normalise U+0261 en g ASCII, et
    # « dé-anglicise » l'API anglaise d'espeak (ɹ→ʁ, θ→t, ð→d, ɪ→i, ʌ→a,
    # æ→a, ɒ→ɔ : rythme, macbeth, punch).
    def clean_ipa(raw)
      raw.to_s.gsub(/\([a-z]{2,3}\)/i, "")
               .gsub(/[\uFEFF\u200B-\u200D\u00AD]/, "")
               .gsub(/[\s\"()_ˈˌ‿ːˑ|[[:punct:]]]/, "")
               .tr("ɡɹθðɪʌæɒ", "gʁtdiaaɔ")
    end

    # Ce cluster de consonnes est-il une attaque de syllabe française valide ?
    # consonne seule ; obstruente+liquide(+glide) ; obstruente+glide ;
    # liquide+glide ; nasale+glide ; s+obstruente seulement dans les clusters
    # de 3+ (respiration -> ʁɛs-pi..., mais abstinente -> ab-sti...)
    def valid_onset?(chars, big = false)
      return false if chars.empty?
      return true if chars.size == 1
      ob = "ptkbdgvfʃzʒ"
      li = "lʁ"
      gl = "jɥw"
      na = "mn"
      chars.match?(/\A[#{ob}][#{li}][#{gl}]?\z/) ||
        chars.match?(/\A[#{ob}][#{gl}]\z/) ||
        chars.match?(/\A[#{li}][#{gl}]\z/) ||
        chars.match?(/\A[#{na}][#{gl}]\z/) ||
        chars.match?(/\As[#{gl}]\z/) || # -sion -> sjɔ̃
        (big && chars.match?(/\As[#{ob}][#{li}]?[#{gl}]?\z/))
    end

    # Insère un séparateur « - » à chaque frontière de syllabe dans une liste
    # de segments phonétiques. barriers = [index, mot_précédent, pause_précédente]
    # pour chaque début de mot. Règles :
    #  - un cluster de consonnes chevauchant une frontière de mot est coupé
    #    À la première frontière (la consonne finale du mot précédent devient
    #    coda : mer en -> mɛʁ-ɑ̃, par moi -> paʁ-mwa, l'envol est -> vɔl-ɛ...);
    #  - exception : une lettre de liaison devant un mot à initiale vocalique
    #    reste l'attaque (les amis -> lɛ-za-mi), sauf si une pause la bloque
    #    (inutiles, enfant -> til-ɑ̃), et les articles élidés l'/j' fusionnent
    #    (l'abstinente -> lab-sti...);
    #  - sinon, le tiret va devant le plus long cluster d'attaque VALIDE
    #    (per-clus -> pɛʁ-kly, re-tourne -> ʁə-tuʁn).
    # Une coda finale ne reçoit pas de séparateur ; un hiatus (pas de
    # consonne) est coupé.
    def mark_syllables(phones, barriers = [])
      cuts = {}
      prev_vowel = nil
      phones.each_with_index do |ph, k|
        next unless ph[0].match?(VOWEL_PHONE)
        # un glide y/ɥ suivi d'une voyelle n'est pas un noyau (même règle que
        # count_syllables) : il ne déclenche aucune coupure de syllabe
        # glide seul (segment d"une seule lettre) suivi d"une voyelle : pas un noyau
        # (un segment comme « yi » a son noyau dans la voyelle qui suit le glide)
        next if ph.length == 1 && (ph[0] == "y" || ph[0] == "ɥ") &&
                phones[k + 1] && phones[k + 1][0].match?(VOWEL_PHONE)
        if prev_vowel
          cut = nil
          inside = barriers.select { |b, _| b > prev_vowel && b < k }
          if inside.any?
            cut = inside.first[0]
          elsif (info = barriers.find { |b, _| b == k })
            prev_word, prev_paused = info[1].to_s, info[2]
            unless %w[l j].include?(prev_word) ||
                   (!prev_paused && LIAISON_LETTERS.include?(prev_word[-1].to_s))
              cut = k # coda du mot précédent, coupure à la frontière
            end
          end
          if cut.nil?
            cluster = phones[(prev_vowel + 1)...k].map { |p| p[0] }.join
            onset = cluster.size.downto(1).find do |len|
              valid_onset?(cluster[-len..], cluster.size >= 3)
            end || 0
            cut = k - onset
          end
          cuts[cut] = true
        end
        prev_vowel = k
      end
      out = +""
      phones.each_with_index do |ph, k|
        out << "-" if cuts[k] && !out.empty?
        out << ph
      end
      out
    end

    # Découpe l'IPA brute en segments suite-de-voyelles / consonne.
    def segments(phones)
      segs = []
      vowel = false
      phones.each_char do |ch|
        if ch.match?(/\p{Mn}/u)
          segs.last << ch unless segs.empty?
        elsif ch.match?(VOWEL_PHONE)
          if vowel && segs.any?
            segs.last << ch
          else
            segs << ch.dup
          end
          vowel = true
        else
          segs << ch.dup
          vowel = false
        end
      end
      segs
    end

    # -- alignement lettres/phones --------------------------------------

    def expected_consonant(ch, nxt)
      case ch
      when "c" then SOFT_NEXT.include?(nxt) ? "s" : "k"
      when "g" then SOFT_NEXT.include?(nxt) ? "ʒ" : "g"
      when "ç" then "s"
      when "h" then nil
      else CONSONANT_LETTERS[ch]
      end
    end

    # Aligne un mot orthographique sur segs à partir de cursor.
    # next_vowel_initial : si le mot suivant commence par une voyelle (ou un
    # h muet), ce qui indique qu'espeak-ng a élidé un schwa final.
    # Renvoie [pairs, new_cursor] avec des paires [phone, restauré ?],
    # ou nil quand le mot ne peut pas être aligné sûrement.
    def align_word(word, segs, cursor, next_vowel_initial: false, next_word: nil,
                   prev_fragment: false, dierese: false, dierese_words: nil,
                   cluster_words: nil, ent_words: nil)
      a = Aligner.new(word: word, segs: segs, out: [], i: 0, cursor: cursor,
                      n: word.size, prev_cons: nil, prev_vowel_phone: false,
                      run_split: false, next_vowel_initial: next_vowel_initial,
                      next_word: next_word, prev_fragment: prev_fragment,
                      dierese: dierese, dierese_words: dierese_words,
                      cluster_words: cluster_words, ent_words: ent_words)
      a.run ? [a.out, a.cursor] : nil
    end

    # -- scansion ------------------------------------------------------

    # Initial voyelle phonétique : commence par une lettre voyelle, ou par h
    # suivi d'une voyelle (le h est toujours muet en français, muet ou aspiré,
    # donc le mot commence quand même par un SON voyelle : hasard -> /azaʁ/).
    # Sert au découpage des suites / aux frontières (au hasard -> o-a-zaʁ).
    # « y » suivi d'une voyelle = glide /j/ (Yosen, yeux) : initiale
    # CONSONANTIQUE pour l'élision (peintre Yosen -> pein-tʁə, pas d'élision),
    # mais la liaison d'une consonne finale du mot précédent a bien lieu
    # (les yeux ->lez-jø, des yachts -> de-zjat).
    def y_glide?(word)
      w = word.to_s.downcase
      w[0] == "y" && w[1].to_s.match?(VOWEL_LETTER)
    end

    # Initiale prenant la liaison (voyelle, h muet, ou y-glide).
    def liaison_initial?(word)
      vowel_initial?(word) || y_glide?(word)
    end

    def vowel_initial?(word)
      first = word[0].to_s
      # « y » suivi d'une voyelle est le glide /j/ (CONSONNE) : Yosen, yacht,
      # yeux commencent par un son consonantique — pas d'élision devant eux
      return false if first == "y" && word[1].to_s.match?(VOWEL_LETTER)
      return true if first.match?(VOWEL_LETTER)
      first == "h" && word[1].to_s.match?(VOWEL_LETTER)
    end

    # h aspiré (petite liste, familles par préfixe) : bloque élision/liaison.
    def h_aspiré?(word)
      return false unless word[0].to_s == "h" && word[1].to_s.match?(VOWEL_LETTER)
      H_ASPIRE.any? { |h| word == h || word.start_with?(h) }
    end

    # L'élision/la liaison a lieu devant une voyelle ou un h MUET — jamais
    # devant un h aspiré (« le hasard » n'élide pas, « l'homme » élide).
    def elides_before?(word) = vowel_initial?(word) && !h_aspiré?(word)

    def words_of(line)
      line.downcase.gsub(/&[a-zA-Z#0-9]+;/, " ").gsub(/['’-]/, " ")
          .scan(/[a-zà-ÿœ]+/u)
    end

    # Pour chaque mot de la ligne, indique s'il est directement suivi d'une
    # pause graphique (, ; : ! ? … —). Le e muet d'un tel mot n'est pas
    # compté (rêche, -> ʁɛʃ), comme en fin de vers.
    def pause_flags(line, words)
      toks = line.downcase.gsub(/&[a-zA-Z#0-9]+;/, " ")
                 .scan(/([a-zà-ÿœ]+)([^a-zà-ÿœ\s]*)/u)
      flags = toks.map { |_w, tail| tail.match?(/[.,;:!?…—]/) }
      flags.fill(false, words.size...flags.size) if flags.size < words.size
      flags.first(words.size)
    end

    # Mètres de vers attendus (utilisés par dierese: :auto)
    METER = [6, 8, 10, 12].freeze

    # Décompte des syllabes : chaque phone voyelle compte, SAUF un glide
    # rendu « y » (ɥ) directement suivi d'une voyelle — fuyait -> f-yi-jɛ fait
    # 2 syllabes, pas 3 (le y est le glide de « ui », pas un noyau)
    # barriers = débuts de mots dans phones (voir mark_syllables) : un glide
    # y/ɥ suivi d'une voyelle n'est un glide (non compté) que si la voyelle
    # appartient AU MÊME mot (fuyait -> f-yi-jɛ = 2) ; entre deux mots c'est
    # un hiatus et le y est le noyau /y/ compté (étendue où -> ...-dy-u = 2)
    def count_syllables(phones, barriers = [])
      word_starts = barriers.map { |b| b[0] }
      count = 0
      phones.each_with_index do |ph, k|
        next unless ph[0].match?(VOWEL_PHONE)
        if (ph[0] == "y" || ph[0] == "ɥ") && phones[k + 1] &&
           phones[k + 1][0].match?(VOWEL_PHONE) &&
           !word_starts.include?(k + 1)
          next
        end
        count += 1
      end
      count
    end

    # Détection de contexte de poésie classique : true quand les lignes
    # voisines (fenêtre autour de idx) tombent majoritairement dans la bande
    # alexandrine 10-13 ou la bande octosyllabe 6-9 (11/13 et 7 y sont des
    # candidats diérèse/surcompte, donc ils appartiennent à la bande). La
    # diérèse ne peut être inférée que
    # dans un contexte aussi régulier — JAMAIS en poésie contemporaine
    # (samples/), où elle ne peut pas être déduite d'un nombre de syllabes
    # cible. counts : décomptes de syllabes par ligne (nil pour les lignes
    # vides ou non alignées).
    def classical_context?(counts, idx, window: 5, threshold: 0.7)
      lo = [idx - window, 0].max
      hi = [idx + window, counts.size - 1].min
      neigh = counts[lo..hi].compact
      neigh.delete_at(idx - lo) if idx >= lo && idx <= hi
      return false if neigh.empty?
      # bande alexandrine 10-13 (11/13 = candidats diérèse) OU bande
      # octosyllabe 6-9 (les 7 y sont des candidats diérèse)
      neigh.count { |c| (10..13).cover?(c) || (6..9).cover?(c) }.to_f / neigh.size >= threshold
    end

    # Point d'entrée public. dierese: :auto re-scanne avec des diérèses quand
    # le compte brut ne tombe pas sur un mètre de vers (11 -> 12, etc.).
    # cache : Hash optionnel partagé entre appels (utilisé par process_lines)
    # pour que chaque paire (ligne, options) ne soit scannée — et espeak-ng
    # relancé — qu'une fois.
    # Mots d'une ligne potentiellement soumis à diérèse (règles 1.4c) :
    # « i » suivi d'une voyelle (sauf hier), « u » suivi de é/è/eu ou d'un a
    # final, « ou » suivi de a. Servent au re-scan ciblé de process_line(:auto).
    DIERESE_WORD = /i[aàâäeéèêoôöœu]|u[éè]|ueu|ua|oui|oua/.freeze

    # Mots d’une ligne candidats à un « +1 » en contexte classique : diérèse
    # (règles 1.4c) OU e final compté d’un mot en -re (cluster_re_pronounced?).
    def fix_candidate_words(line)
      words_of(normalize_input(line)).select do |w|
        next false if w == "hier"
        w.match?(DIERESE_WORD) || w.sub(/s\z/, "").end_with?("re") ||
          w.match?(/[cgq]u?e[sx]?\z/) || w.end_with?("ent")
      end
    end

    # Point d'entrée public. dierese: :auto re-scanne avec des diérèses quand
    # le compte brut ne tombe pas sur un mètre de vers (11 -> 12, etc.) :
    # d'abord diérèse globale + e des -Cre compté (contexte classique) ;
    # si le résultat n'atteint pas un mètre, re-scan ciblé — e des -Cre compté
    # mais diérèse appliquée à UN seul mot candidat à la fois — et on retient
    # la première variante qui tombe sur un mètre.
    # cache : Hash optionnel partagé entre appels (utilisé par process_lines)
    # pour que chaque paire (ligne, options) ne soit scannée — et espeak-ng
    # relancé — qu'une fois.
    def process_line(line, dierese: false, cache: nil)
      # en mode :auto, la 1re passe garde le comptage classique de l'e muet
      # devant consonne (sinon elle pourrait tomber sur 10 et arrêter là) ;
      # en mode plain direct (--no-dierese), l'e muet n'est pas compté.
      r = scan_line(line, dierese: false, cache: cache,
                    count_mute_e: dierese != false)
      if dierese == true
        r = scan_line(line, dierese: true, cache: cache)
      elsif dierese == :auto && r.aligned && !METER.include?(r.syllables)
        # 1) diérèse globale + e des -re comptés (contexte classique)
        r2 = scan_line(line, dierese: true, cache: cache)
        r = r2 if r2.aligned && METER.include?(r2.syllables)
        # 1b) e muet prononcé devant une pause graphique (, ; : ! ? …),
        #     UNIQUEMENT si le vers devient alexandrin (12) : en vers
        #     irrégulier ou contemporain, la pause silencie le e muet
        if !METER.include?(r.syllables)
          r2b = scan_line(line, dierese: false, pause_e: true, cache: cache)
          r = r2b if r2b.aligned && r2b.syllables == 12
        end
        if !METER.include?(r.syllables)
          r2c = scan_line(line, dierese: true, pause_e: true, cache: cache)
          r = r2c if r2c.aligned && r2c.syllables == 12
        end
        # 2) e des -re comptés, aucune diérèse
        if !METER.include?(r.syllables)
          r3 = scan_line(line, dierese: true, dierese_words: [], cache: cache)
          r = r3 if r3.aligned && METER.include?(r3.syllables)
        end
        # 3) ciblage mot à mot : diérèse sur w seul (e des -re tous comptés),
        #    puis diérèse + e de -re sur w seul
        if !METER.include?(r.syllables)
          fix_candidate_words(line).each do |w|
            combos = [[w, nil, nil], [w, [w], nil]]
            combos << [w, nil, [w]] if w.end_with?("ent")
            combos.each do |dw, cw, ew|
              r4 = scan_line(line, dierese: true, dierese_words: dw,
                             cluster_words: cw, ent_words: ew, cache: cache)
              if r4.aligned && METER.include?(r4.syllables)
                r = r4
                break
              end
            end
            break if METER.include?(r.syllables)
          end
        end
      end
      r
    end

    # Point d'entrée par lot (deux passes). Avec dierese: :auto, la diérèse
    # n'est appliquée que là où le contexte alentour est classique
    # (classical_context?) — jamais en poésie contemporaine.
    def process_lines(lines, dierese: :auto)
      cache = {}
      counts = lines.map do |l|
        next nil if l.strip.empty?
        r = scan_line(l, dierese: false, cache: cache, count_mute_e: true)
        r.aligned ? r.syllables : nil
      end
      lines.each_with_index.map do |l, i|
        d = case dierese
            when :auto then (classical_context?(counts, i) ? :auto : false)
            else dierese
            end
        process_line(l, dierese: d, cache: cache)
      end
    end

    # Enveloppe mémoïsante autour de compute_scan_line : avec un cache partagé
    # (voir process_lines), chaque paire (ligne, dierese)
    # n'est calculée — et espeak-ng relancé — qu'une fois.
    def scan_line(line, dierese: false, cache: nil, dierese_words: nil, cluster_words: nil,
                  ent_words: nil, pause_e: false, count_mute_e: false)
      if cache
        key = [line, dierese, dierese_words, cluster_words, ent_words, pause_e, count_mute_e]
        return cache[key] if cache.key?(key)
        return cache[key] = compute_scan_line(line, dierese: dierese,
                                               dierese_words: dierese_words,
                                               cluster_words: cluster_words,
                                               ent_words: ent_words, pause_e: pause_e,
                                               count_mute_e: count_mute_e)
      end
      compute_scan_line(line, dierese: dierese, dierese_words: dierese_words,
                       cluster_words: cluster_words, ent_words: ent_words, pause_e: pause_e,
                       count_mute_e: count_mute_e)
    end

    def compute_scan_line(line, dierese: false, dierese_words: nil, cluster_words: nil,
                          ent_words: nil, pause_e: false, count_mute_e: false)
      # normalise une fois pour que words_of et espeak voient les mêmes lettres
      clean = normalize_input(line)
      words = words_of(clean)
      if words.empty?
        return Result.new(text: line, raw: "", phones: "",
                          syllables: 0, aligned: true, dierese: 0)
      end

      raw = espeak(clean)
      segs = segments(raw)

      words_out = []
      cursor = 0
      aligned = true

      words.each_with_index do |w, k|
        res = align_word(w, segs, cursor,
                         next_vowel_initial: liaison_initial?(words[k + 1].to_s),
                         next_word: words[k + 1],
                         prev_fragment: k.positive? &&
                           %w[c j l d n s t m qu].include?(words[k - 1]),
                         dierese: dierese, dierese_words: dierese_words,
                         cluster_words: cluster_words, ent_words: ent_words)
        if res.nil?
          aligned = false
          break
        end
        words_out << { word: w, pairs: res[0] }
        cursor = res[1]
      end
      aligned &&= (cursor == segs.size)

      unless aligned
        # repli sûr : sortie brute d'espeak, sans restauration
        syll = count_syllables(segs)
        return Result.new(text: line, raw: raw, phones: mark_syllables(segs),
                          syllables: syll, aligned: false, dierese: 0)
      end

      # élagage de scansion des schwas finaux restaurés
      paused = pause_flags(clean, words)
      words_out.each_with_index do |w, k|
        pairs = w[:pairs]
        next unless pairs.last && pairs.last[0] == SCHWA

        next_word = (words_out[k + 1] || {})[:word]
        # un e final PRONONCÉ (CR_E_PRONOUNCED, ou -Cre en contexte classique)
        # reste compté même devant une pause : « ivre, complice » -> i-vʁə (2)
        pronounced = cr_e_pronounced?(w[:word]) ||
                     cluster_re_pronounced?(w[:word],
                                            cluster_words ? cluster_words.include?(w[:word]) : dierese)
        if next_word.nil?                # fin de vers : e muet non compté
          pairs.pop
        elsif elides_before?(next_word) && !plural_mute_e?(w[:word])
          pairs.pop # élision devant une voyelle / un h muet (sauf pluriel -es/-eux : e prononcé)
        elsif paused[k] && !pronounced && !pause_e
          pairs.pop # devant une pause (, ; : ! ? …) ; pause_e : e compté (alexandrine)
        elsif !dierese && !pause_e && !count_mute_e && !pronounced
          # mode contemporain (--no-dierese) : l'e muet n'est JAMAIS compté
          # devant une consonne (« mes pères criaient » -> pɛʁ, 8 syllabes) ;
          # en contexte classique (dierese/:auto, pause_e) il reste compté
          pairs.pop
        end
      end

      flat = []
      barriers = []
      words_out.each_with_index do |w, k|
        barriers << [flat.size, words[k - 1], paused[k - 1]]
        w[:pairs].each { |ph, _| flat << ph }
      end
      phones = mark_syllables(flat, barriers)
      syllables = count_syllables(flat, barriers)

      dier = words_out.sum do |w|
        w[:pairs].count { |ph, restored| restored && %w[i u].include?(ph) }
      end

      # spans mot -> indices de syllabes (pour les outils en aval, ex.
      # scansion/accents) : même règle de comptage que count_syllables
      # (un glide y/ɥ suivi d'une voyelle n'est pas un noyau, sauf si la
      # voyelle ouvre le mot suivant)
      word_spans = []
      syl = 0
      words.each_with_index do |w, k|
        start = barriers[k][0]
        fin = k + 1 < barriers.size ? barriers[k + 1][0] : flat.size
        first = syl
        (start...fin).each do |fk|
          ph = flat[fk]
          next unless ph[0].match?(VOWEL_PHONE)
          nxt = flat[fk + 1]
          if (ph[0] == "y" || ph[0] == "ɥ") && nxt && nxt[0].match?(VOWEL_PHONE) &&
             !(k + 1 < barriers.size && barriers[k + 1][0] == fk + 1)
            next
          end
          syl += 1
        end
        word_spans << { word: w, first: first, last: syl - 1 }
      end
      Result.new(text: line, raw: raw, phones: phones,
                 syllables: syllables, aligned: aligned, dierese: dier,
                 word_spans: word_spans)
    end

    # -- CLI -------------------------------------------------------------

    # Point d'entrée, invoqué seulement quand le fichier est exécuté comme
    # script ($PROGRAM_NAME == __FILE__), afin que le require de ce fichier
    # reste sans effet de bord : pas d'OptionParser qui consommerait l'ARGV de
    # l'hôte, pas de mutation d'encodage global.
    def main(argv = ARGV)
      options = { syllables_only: false, dierese: :auto }
      OptionParser.new do |opts|
        opts.banner = "Utilisation : #{File.basename($PROGRAM_NAME)} [options] [FILE|-]"
        opts.on("--no-dierese", "Désactiver la diérèse contextuelle (corpus contemporain)") do
          options[:dierese] = false
        end
        opts.on("-s", "--syllables", "Afficher seulement le décompte des syllabes") do
          options[:syllables_only] = true
        end
        opts.on("-h", "--help", "Afficher cette aide") do
          puts opts
          exit
        end
      end.parse!(argv)

      Encoding.default_external = Encoding::UTF_8

      fallbacks = 0

      # Accepte des chemins de fichiers ou du texte de vers en argument :
      #   scansion poeme.txt
      #   scansion "Au coin du feu, dans la langueur des rêveries!"
      inline = []
      ARGV.replace(argv.flat_map do |arg|
        if arg == "-" || File.exist?(arg)
          arg
        else
          inline.concat(arg.split(/[\r\n]+/))
          nil
        end
      end.compact)

      lines =
        if inline.any? && ARGV.empty?
          inline.each
        elsif inline.any?
          # mélange de texte en ligne et de chemins de fichiers : traiter
          # d'abord les lignes passées en ligne
          Enumerator.new do |y|
            inline.each { |l| y << l }
            ARGF.each_line { |l| y << l }
          end
        else
          ARGF.each_line
        end

      lines = lines.to_a.map(&:chomp)
      process_lines(lines, dierese: options[:dierese]).each do |res|
        next if res.text.strip.empty?

        if options[:syllables_only]
          puts format("%3d  %s", res.syllables, res.text.to_s.strip)
        else
          puts res.text.to_s.rstrip
          puts format("  %s %s   (%d syll.)", res.aligned ? "⇒" : "~", res.phones, res.syllables)
          puts "    (espeak seul : #{res.raw})" unless res.aligned
          puts ""
        end

        fallbacks += 1 unless res.aligned
      end

      warn "scansion : #{fallbacks} vers non alignés (sortie espeak brute)" if fallbacks.positive?
    end
  end
end

Scansion.main if $PROGRAM_NAME == __FILE__
