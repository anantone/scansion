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
# L'évaluation SUBJECTIVE de ces caractéristiques (pondération de critères
# de jugement -> score global du vers) n'est pas du ressort de scansion :
# elle vivra dans le gem claudel, au-dessus de ce module.
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

    # Mots sur lesquels le tirage ne restaure jamais de diérèse (« des dieux »
    # -> de-djø, pas de-di-jø).
    SANS_DIERESE = %w[dieu dieux].freeze

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
    # @return [Scansion::Result] le Result retenu
    def accent_pull(line, plain_res, cache: nil)
      return plain_res unless plain_res.aligned

      variants = [['plain', plain_res, score_of(plain_res, line)]]
      e = Scansion.scan_line(line, dierese: false, count_mute_e: true, cache: cache)
      if e.aligned && e.syllables > plain_res.syllables &&
         e.syllables - plain_res.syllables <= MAX_PULL_SYLLABES
        variants << ['+e', e, score_of(e, line)]
      end
      unless Scansion.words_of(line).intersect?(SANS_DIERESE)
        d = Scansion.scan_line(line, dierese: true, cache: cache)
        if d.aligned && d.syllables > plain_res.syllables &&
           d.syllables - plain_res.syllables <= MAX_PULL_SYLLABES
          variants << ['+diérèse', d, score_of(d, line)]
        end
      end
      # variantes MOT À MOT : ne compter l'e caduc que d'un seul mot candidat
      mute_e_candidates(line).each do |w|
        v = Scansion.scan_line(line, dierese: false, mute_e_words: [w], cache: cache)
        next unless v.aligned && v.syllables == plain_res.syllables + 1

        variants << ["+e:#{w}", v, score_of(v, line)]
      end

      best = variants.max_by { |_, _, s| s }
      best[1][0] == 'plain' || best[2] <= variants[0][2] ? plain_res : best[1]
    end

    # Score rythmique d'un Result : signature des groupes de son analyse
    # accentuelle (Scansion::Accents.analyze_result).
    def score_of(res, line)
      score(signature(Scansion::Accents.analyze_result(res, line)))
    end

    # Mots candidats à un « +e » ciblé : terminaison en -e/-es/-x avec un
    # schwa non fixe (pas les monosyllabes grammaticaux le/de/me…).
    def mute_e_candidates(line)
      Scansion.words_of(Scansion.normalize_input(line)).select do |w|
        w.match?(/e[sx]?\z/i) && !Scansion::SCHWA_STABLE.include?(w)
      end
    end
  end
end
