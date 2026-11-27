# frozen_string_literal: true

#
# rythme.rb — caractéristiques rythmiques du vers et tirage accentuel (2.6).
#
# La régularité rythmique n'est pas un jugement : c'est une caractéristique
# mesurable du vers. Ce module la produit :
#   - signature d'un vers = tailles de ses groupes rythmiques en syllabes ;
#   - score de régularité de cette signature (tailles >= 2 RÉPÉTÉES, +1 par
#     répétition, et paires ADJACENTES de même taille >= 2, +1) :
#       [3,3,3,3] -> 6 ; [2,2,3,3] -> 4 ; [2,4,4,2] -> 3 ; [6,3,3] -> 2 ;
#       [1,1,3] -> 0 (taille 1 ignorée) ; [8,3] -> 0.
#   - tirage accentuel (règle 2.6, vers contemporain uniquement) : compare la
#     scansion plain aux variantes « e caduc compté » (+e, global ou mot à
#     mot) et « diérèse » ; si l'une a un score strictement supérieur, elle
#     tire le vers. Appliqué dans Scansion::Accents.analyze_line(s) en mode
#     contemporain.
#
# La QUANTIFICATION de ces caractéristiques (modéliser des aspects du poème
# à partir de ces outils analytiques) n'est pas du ressort de scansion : elle
# vit dans le gem claudel, au-dessus de ce module. L'interprétation de lecture
# (règles dures ou personnelles) reste côté scansion.
#
#   require "scansion/rythme"

require_relative 'syllabification'
require_relative 'accents'

module Scansion
  # Caractéristiques rythmiques d'un vers scansionné (voir l'en-tête).
  module Rythme
    module_function

    # Un tirage ne peut ajouter qu'UNE syllabe au vers : au-delà, la variante
    # change le mètre du vers plus qu'elle ne l'accorde (« derrière la tête le
    # passé jouit » -> 8, pas 10).
    MAX_PULL_SYLLABES = 1

    # EXPÉRIMENTAL (tirage 2.6, vers contemporain) : le tirage peut combiner
    # plusieurs e caducs et une diérèse, notés avec les groupes contemporains.
    # Voir score_of(res, line, contemporain: true).
    PULL_CONTEMPORAIN = false

    # Mots sur lesquels le tirage ne restaure jamais de diérèse (« des dieux »
    # -> de-djø, pas de-di-jø).
    SANS_DIERESE = %w[dieu dieux].freeze

    # Marqueurs d'oralité (registre parlé) : après eux, un mot à e caduc
    # optionnel perd son e (« c'est une promesse » -> sɛt-yn, pas sɛt-yn-ə),
    # même sous la pression du tirage vers le mètre. N figurent ici que les
    # marqueurs attestés dans les samples : « c'est » (45 occ.), « ya »
    # (2015-6-6-philosophie.txt), « t'es » (id.).
    MARQUEURS_ORALITE = /(?:c['’]est|ya|t['’]es)\s+/i

    # Signature d'un vers = tailles des groupes rythmiques en syllabes
    # (ex. [6, 3, 3]).
    # @param analysis [Scansion::Accents::Analysis] analyse du vers
    # @return [Array<Integer>]
    def signature(analysis)
      analysis.groups.map do |g|
        g.tokens.sum { |t| t.debut && t.fin ? t.fin - t.debut + 1 : 0 }
      end
    end

    # Score de régularité rythmique d'une signature (voir en-tête).
    # @param sig [Array<Integer>] signature (voir .signature)
    # @return [Integer]
    def score(sig)
      base = sig.tally.sum { |s, c| s >= 2 && c >= 2 ? c - 1 : 0 }
      bonus = sig.each_cons(2).count { |a, b| a == b && a >= 2 }
      base + bonus
    end

    # Règle 2.6 — tirage accentuel d'un vers contemporain, sur le seul vers
    # (pas de contexte voisin). Compare la scansion plain aux variantes
    # « e caduc compté » et « diérèse » (globales ou mot à mot) ; si l'une a
    # un score strictement supérieur au plain, elle tire le vers.
    # @param line [String] le vers d'origine
    # @param plain_res [Scansion::Result] scansion plain (mode :contemporain)
    # @param cache [Hash, nil] cache partagé optionnel (voir Scansion.scan_line)
    # @param target [Integer, nil] nombre de syllabes cible (mètre dominant du
    #   poème, transmis par analyze_lines) : variantes qui atteignent la cible
    # @return [Scansion::Result] le Result retenu
    def accent_pull(line, plain_res, cache: nil, target: nil)
      return plain_res unless plain_res.aligned

      # tirage vers la cible (mètre dominant du poème) : prioritaire
      return pull_vers_cible(line, plain_res, target, cache: cache) if target && target > plain_res.syllables

      # PULL_CONTEMPORAIN (expérimental) : variantes notées avec les groupes
      # contemporains, tirage multi-e et combiné +e/diérèse autorisés
      contemp = PULL_CONTEMPORAIN
      max = contemp ? [MAX_PULL_SYLLABES, 3].max : MAX_PULL_SYLLABES
      best = plain_res
      best_score = score_of(plain_res, line, contemporain: contemp)
      variantes(line, cache, combinee: contemp).each do |label, v|
        next unless v.aligned

        extra = v.syllables - plain_res.syllables
        # mot à mot : exactement une syllabe de plus ; global : 1..max
        next unless label.start_with?('+e:') ? extra == 1 : extra.between?(1, max)

        s = score_of(v, line, contemporain: contemp)
        next unless s > best_score # strictement meilleur que le plain

        best = v
        best_score = s
      end
      best
    end

    # Tirage vers un nombre de syllabes cible (mètre dominant du poème) :
    # on essaie les variantes « +e global », « +diérèse », combinée, et mot à
    # mot, mais seules celles qui ATTEIGNENT la cible sont retenues.
    def pull_vers_cible(line, plain_res, target, cache: nil)
      candidats = variantes(line, cache).map(&:last).select { |v| v.aligned && v.syllables == target }
      # atteindre la cible (mètre dominant du poème) est en soi la
      # justification rythmique : parmi les variantes qui l'atteignent,
      # on prend la mieux notée, même si son score de groupes est inférieur
      # au plain (ex. « une caresse qui produit » -> 8, pas 6 en 3-3)
      candidats.max_by { |v| score_of(v, line, contemporain: true) } || plain_res
    end

    # Variantes de tirage d'un vers, dans l'ordre : globales (« +e »,
    # « +diérèse », puis combinée si +combinee+), puis « +e » mot à mot sur
    # chaque candidat. Pas de diérèse sur SANS_DIERESE (« des dieux »).
    # @return [Array<(String, Scansion::Result)>] paires [étiquette, Result]
    def variantes(line, cache, combinee: true)
      sans_dierese = Scansion.words_of(line).intersect?(SANS_DIERESE)
      globales = [[false, true], [true, false], [true, true]]
      globales = globales.first(2) unless combinee
      out = globales.filter_map do |dier, ce|
        next if dier && sans_dierese

        ["#{'+diérèse' if dier}#{'+e' if ce}",
         Scansion.scan_line(line, dierese: dier, count_mute_e: ce, cache: cache)]
      end
      out + mute_e_candidates(line).map do |w|
        ["+e:#{w}", Scansion.scan_line(line, dierese: false, mute_e_words: [w], cache: cache)]
      end
    end

    # Score rythmique d'un Result : signature des groupes de son analyse
    # accentuelle (Scansion::Accents.analyze_result). `contemporain: true`
    # note les groupes avec les règles du vers contemporain (expérimental,
    # voir PULL_CONTEMPORAIN).
    def score_of(res, line, contemporain: false)
      score(signature(Scansion::Accents.analyze_result(res, line, contemporain: contemporain)))
    end

    # Mots candidats à un « +e » ciblé : terminaison en -e/-es/-x avec un
    # schwa non fixe (pas les monosyllabes grammaticaux le/de/me…) — et pas
    # de « +e » après un marqueur d'oralité (« c'est une » -> sɛt-yn).
    def mute_e_candidates(line)
      norm = Scansion.normalize_input(line)
      Scansion.words_of(norm).select do |w|
        next false unless w.match?(/e[sx]?\z/i) && !Scansion::SCHWA_STABLE.include?(w)

        !norm.match?(/#{MARQUEURS_ORALITE.source}#{Regexp.escape(w.downcase)}\b/i)
      end
    end
  end
end
