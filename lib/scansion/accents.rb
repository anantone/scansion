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

    # Participes passés / adjectifs verbaux (terminaisons) — « la date choisie »,
    # « pris ».
    PARTICIPES = /(?:é|ée|és|ées|i|ie|is|ies|u|ue|us|ues|it|ît)s?\z/
    # Infinitif (heuristique orthographique) — « laissée frotter ».
    # -er/-ir seulement : -re entre en collision avec prêtre, frère, mère…
    INFINITIF = /\A[[:alpha:]-]+(?:er|ir)\z/
    # Locutions soudées en un seul groupe accentuel (mode contemporain) :
    # « nulle part », « peu partout », « en tout ».
    LOCUTIONS_SANS_FRONTIERE = [%w[nulle part], %w[peu partout], %w[en tout]].freeze

    # Fragments clitiques (l', j', n', c', d', m', t', s') : la « vraie » tête
    # du mot est la première partie qui n'est pas un fragment — « c'est » ->
    # est (auxiliaire, fonctionnel), « l'ombre » -> ombre (nom, PAS le
    # déterminant « l »), « n'est » -> est.
    FRAGMENTS_CLITIQUES = %w[c d j l m n s t].freeze

    # Fin de verbe fini (heuristique sans POS) : -ont, -ez, -ons, -ais, -ait,
    # -ai/-as/-a, -is/-it/-ît. Un déterminant après un verbe fini reste
    # dans le groupe verbal (« font un reflet », « fondra la mer ») ; après
    # un participe ou un nom, il ouvre un nouveau syntagme (« ciselant | le
    # cristal », « l'ombre | les escrocs »).
    TERMINAISONS_VERBE_FINI = /(?:ont|ez|ons|ais|aient|ait|ai|as|a|is|it|ît)\z/

    # Indice 0-based de la syllabe de césure selon la longueur du vers :
    # 6//6 pour l'alexandrin, 4//4 pour l'octosyllabe.
    CESURES = { 12 => 5, 8 => 3 }.freeze

    # Contexte d'une décision de frontière (voir Accents.boundary_before?) :
    # le mot courant, ses pièces, sa tête, et les têtes des voisins.
    ContexteFrontiere = Struct.new(:tok, :pcs, :head, :last, :nxt_head, :prev, :prev_head,
                                   :prev2_head, :contemporain, keyword_init: true)

    # Règles de frontière de groupe, dans l'ordre où elles sont essayées.
    REGLES_FRONTIERE = %i[
      frontiere_indefini frontiere_conjonction_auxiliaire frontiere_en
      frontiere_preposition frontiere_de_soude frontiere_determinant
      frontiere_participe frontiere_mots_pleins
    ].freeze

    # Word token: Unicode word chars plus apostrophes (elisions: l'amour) and
    # internal hyphens (porte-parapluie).
    REGEXP_MOTS = /[\p{Word}'’-]+|[,;:.!?…—–«»"]/

    # keyword_init structs take keyword arguments only.
    Token = Struct.new(:surface, :kind, :debut, :fin, keyword_init: true) # kind: :word | :punct
    # hard = true : la frontière après ce groupe vient d'une ponctuation
    # (mode contemporain : la ponctuation est une frontière dure, on ne
    # recolle pas un groupe fonctionnel au suivant — « Après tout, | l'autre »)
    Group = Struct.new(:tokens, :accent, :hard)

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
        # régime résolu UNE fois, puis transmis : syllabification et accents
        # travaillent ainsi sous le même régime
        mode = Scansion.detect_mode(lines, cache: cache) if mode == :auto
        results = Scansion.process_lines(lines, mode: mode, cache: cache)
        contemporain = (mode == :contemporain)
        # cible du tirage 2.6 : mètre dominant du poème (vers contemporain) —
        # ex. un poème en octosyllabes tire les vers courts vers 8
        cible = nil
        counts = results.map(&:syllables).select(&:positive?)
        if contemporain && counts.size >= 3
          top, n = counts.tally.max_by { |_, c| c }
          # seuls les mètres pairs classiques (6, 8, 10, 12) servent de cible :
          # un vers libre tiré vers un compte impair dominant serait suspect
          cible = top if n >= 2 && n * 2 >= counts.size && (6..12).cover?(top) && top.even?
        end
        results.zip(lines).map do |res, text|
          # règle 2.6 (Scansion::Rythme) : tirage accentuel, mode contemporain
          res = Scansion::Rythme.accent_pull(text, res, cache: cache, target: cible) if contemporain
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
      # (voir TERMINAISONS_VERBE_FINI pour l'heuristique de verbe fini)
      def finite_verb_head?(head)
        !head.nil? && head.match?(TERMINAISONS_VERBE_FINI)
      end

      # Une frontière de groupe AVANT tokens[i] (mot) ? Les règles
      # REGLES_FRONTIERE sont essayées dans l'ordre : chacune renvoie true
      # (frontière), false (pas de frontière, décision finale) ou nil (ne
      # s'applique pas). Aucune ne s'applique : pas de frontière.
      def boundary_before?(tokens, i, contemporain: false)
        tok = tokens[i]
        return false unless tok.kind == :word
        return false if i.zero?

        ctx = boundary_context(tokens, i, contemporain)
        REGLES_FRONTIERE.each do |regle|
          decision = send(regle, ctx)
          return decision unless decision.nil?
        end
        false
      end

      def boundary_context(tokens, i, contemporain)
        tok = tokens[i]
        pcs = pieces(tok)
        nxt = tokens[i + 1]
        prev = tokens[i - 1]
        prev2 = i >= 2 ? tokens[i - 2] : nil # pas d'index négatif !
        ContexteFrontiere.new(
          tok: tok, pcs: pcs,
          head: head_of(tok).to_s, # saute les fragments clitiques (c'est -> est)
          last: pcs.last.to_s.downcase,
          nxt_head: nxt ? head_of(nxt) : nil,
          prev: prev, prev_head: prev ? head_of(prev) : nil,
          prev2_head: prev2 ? head_of(prev2) : nil,
          contemporain: contemporain
        )
      end

      # le mot précédent est PLEIN (mode contemporain : qui/jamais/rien/leur(s)
      # comptent comme pleins côté précédent)
      def prev_plein?(ctx)
        ctx.prev.kind == :word && ctx.prev_head &&
          (!MOTS_FONCTIONNELS.key?(ctx.prev_head) || CONTEMP_PRONOMS_PLEINS.include?(ctx.prev_head))
      end

      # aucun, tout, autre… seuls ouvrent un groupe — sauf locution soudée
      # (« donc en tout » ne coupe pas avant « tout »)
      def frontiere_indefini(ctx)
        true if ctx.pcs.size == 1 && INDEFINIS.key?(ctx.head) &&
                !LOCUTIONS_SANS_FRONTIERE.include?([ctx.prev_head.to_s, ctx.head])
      end

      # conjonction (que, et…), « alors » en contemporain, auxiliaire (n'est, est, a…)
      def frontiere_conjonction_auxiliaire(ctx)
        true if CONJONCTIONS.key?(ctx.head) || CONJONCTIONS.key?(ctx.last) ||
                (ctx.contemporain && CONTEMP_CONJONCTIONS.key?(ctx.head)) ||
                AUXILIAIRES.key?(ctx.last)
      end

      # « en » : pronom devant un verbe à l'infinitif ou un nom (« en finir »
      # ne coupe pas), préposition devant un déterminant (« en ta toison »
      # coupe) ; en contemporain, un mot plein suivi de « en » coupe
      # (« je prie | en silence »)
      def frontiere_en(ctx)
        return unless ctx.head == 'en'
        return true if ctx.contemporain && prev_plein?(ctx)

        ctx.nxt_head && DETERMINANTS.key?(ctx.nxt_head) ? true : false
      end

      # préposition en tête de mot : coupe, sauf « de/d' » devant un nom nu
      # (« l'absence de sens ») ou soudé à un nom (« d'ange »)
      def frontiere_preposition(ctx)
        return unless PREPOSITIONS.key?(ctx.head)

        if %w[de d].include?(ctx.head)
          # « d'ange » (de + nom nu soudé) : pas de frontière — mais « d'honorer »
          # (de + infinitif soudé) coupe en contemporain (« convenu | d'honorer »)
          return false if ctx.pcs.size > 1 && !(ctx.contemporain && ctx.pcs.last.to_s.downcase.match?(INFINITIF))
          # « de + nom nu » complément ne coupe pas, même en contemporain :
          # « l'absence de sens », « nue de chair », « peur de mourir »
          return false if ctx.nxt_head && !DETERMINANTS.key?(ctx.nxt_head)
        end
        # toute autre préposition coupe (en contemporain notamment après un
        # mot plein : « d'or | en ta chair »)
        true
      end

      # « d' + mot » soudé (pièces > 1 commençant par de/d) : coupe en
      # contemporain (« peau | d'ange », « enrubannés | d'espoir »,
      # « convenu | d'honorer ») ; collé en classique
      def frontiere_de_soude(ctx)
        return unless ctx.pcs.size > 1 && %w[de d].include?(ctx.pcs.first.to_s.downcase)

        ctx.contemporain ? true : false
      end

      def frontiere_determinant(ctx)
        return unless DETERMINANTS.key?(ctx.head)

        # le déterminant appartient au syntagme précédent (« que le fond »,
        # « sans l'accuser ») si le mot d'avant est fonctionnel — SAUF après
        # « tout » pronominal (« Après tout, | l'autre langage » : tout après
        # une préposition est un pronom, pas un déterminant)
        if ctx.prev_head && MOTS_FONCTIONNELS.key?(ctx.prev_head) &&
           !(ctx.prev_head == 'tout' && ctx.prev2_head && PREPOSITIONS.key?(ctx.prev2_head.to_s))
          return false
        end
        # après un verbe fini, le COD reste dans le groupe verbal
        # (« font un reflet », « fondra la mer », « ne naît la nuit »)
        # — sauf après « pas » : « pas appris | l'histoire » (participe)
        return false if ctx.prev.kind == :word && finite_verb_head?(ctx.prev_head) && ctx.prev2_head.to_s != 'pas'
        # « du/des » (génitif) collé à une PP (« à partir du col ») : pas de
        # frontière ; un article plein (« les escrocs » après « l’ombre ») ouvre
        # bien un nouveau syntagme
        return false if %w[du des].include?(ctx.head) && ctx.prev2_head && PREPOSITIONS.key?(ctx.prev2_head.to_s)

        true
      end

      # participe passé / adjectif verbal en -é/-i/-u après un mot PLEIN :
      # il ouvre un nouveau groupe (« la date | choisie »), sauf nom propre
      # capitalisé (« le dogue Liberté »). Les verbes finis restent avec leur
      # sujet (« mes pères criaient » -> un seul groupe).
      def frontiere_participe(ctx)
        true if ctx.prev_head && ctx.prev.kind == :word && !MOTS_FONCTIONNELS.key?(ctx.prev_head) &&
                !finite_verb_head?(ctx.prev_head) &&
                ctx.tok.surface[0] == ctx.tok.surface[0].downcase &&
                ctx.head.match?(PARTICIPES)
      end

      # Mode contemporain : frontière entre deux mots PLEINS (« bile | noire »,
      # « reflets | dérisoires », « reins | l'épaule », « pères | criaient »).
      # Les déterminants après un verbe fini restent dans le groupe verbal
      # (frontiere_determinant : « font un reflet »).
      def frontiere_mots_pleins(ctx)
        return unless ctx.contemporain && ctx.prev.kind == :word && ctx.prev_head

        head = ctx.head
        prev_head = ctx.prev_head
        # la négation « pas » reste dans le groupe verbal (« ne meurt pas »
        # ne coupe pas)
        plein = (!MOTS_FONCTIONNELS.key?(head) || head == 'qui' || PRONOMS.key?(head)) && head != 'pas'
        # locutions soudées : « nulle part », « peu partout » -> un seul groupe
        return false if LOCUTIONS_SANS_FRONTIERE.include?([prev_head.to_s, head])

        # pronom réfléchi (se/me/te) collé à un pronom sujet (« lorsqu'il se
        # tait » : dernière partie de « lorsqu'il » = il) ; après un nom, il
        # ouvre un groupe (« l'autre langage | te ressemble »)
        prev_pcs = pieces(ctx.prev)
        prev_pronom = PRONOMS.key?(prev_head) || CONTEMP_PRONOMS_PLEINS.include?(prev_head.to_s) ||
                      (prev_pcs.size > 1 && PRONOMS.key?(prev_pcs.last.to_s.downcase))
        return false if %w[se me te].include?(head) && prev_pronom
        # verbe fini après un pronom sujet ou une conjonction : « je | vais »,
        # « et | croit » (mais « nous | battre » : infinitif ; « se | tait » :
        # réfléchi ; « ne | naît », « s'en | va » : négation/pronom collés)
        if finite_verb_head?(head) &&
           ((prev_pronom && !%w[se me te ne en y].include?(prev_head.to_s)) ||
            CONJONCTIONS.key?(prev_head.to_s))
          return true
        end

        # deux mots pleins se séparent (« livre | comme », « lois | anciennes »,
        # « fais | tourner », « lait | clair »)
        true if prev_plein?(ctx) && plein
      end
      private(*REGLES_FRONTIERE, :boundary_context, :prev_plein?)

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

      # indice 0-based de la syllabe de césure (voir CESURES), nil sinon
      def caesura_index(n)
        CESURES[n]
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
      # point d'entrée documenté (voir l'en-tête du module) : public, bien que
      # défini parmi les méthodes privées
      public :word_accents

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
              groups << Group.new(current, nil, contemporain ? true : nil)
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
          # un groupe fonctionnel fermé par une ponctuation (hard) n'est
          # recollé au suivant que s'il est d'un seul mot (« mais, de toute
          # évidence ») — « Après tout, | l'autre » reste coupé
          if all_function?(out[i]) && !(out[i].hard && out[i].tokens.size > 1)
            out[i + 1] = Group.new(out[i].tokens + out[i + 1].tokens, nil, out[i + 1].hard)
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
        c = caesura_index(syls.size)
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
            out << Group.new(g.tokens[0..cover], nil, nil)
            out << Group.new(g.tokens[(cover + 1)..], nil, g.hard)
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
        c = caesura_index(n)
        return w if c.nil?

        last = a.groups.last
        if last.nil? || last.accent != n - 1
          w << "verse #{n}: rhyme (syllable #{n}) is not the last group's accent"
        elsif !accent_bearing?(a.syllables[n - 1])
          w << "verse #{n}: rhyme syllable has no accent-bearing nucleus — suspicious elision at line end"
        end

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
