# frozen_string_literal: true

#
# classique.rb — couche de règles CLASSIQUES du gem scansion (vers mesurés :
# alexandrins, octosyllabes…). Le cœur partagé (espeak-ng, alignement,
# compte de syllabes) reste dans syllabification.rb ; ce fichier regroupe
# uniquement les règles de tirage propres au vers classique :
#   - detect_mode : détection du régime d'un texte (mode :auto) —
#     :classique si une écrasante majorité de vers (1re passe, e muet
#     compté) tombent sur un mètre PAIR [6, 8, 10, 12] (signature du vers
#     classique : répétition de longueurs paires) ET sur des RIMES STRICTES
#     de fin de vers (les vers classiques riment ; un poème d'octosyllabes
#     sans rimes de fin de vers est du contemporain) ; :contemporain sinon ;
#   - rhyme_key : clé de rime stricte de fin de vers (utilisée par detect_mode) ;
#   - context_meter : mètre dominant chez les vers voisins ;
#   - auto_line : re-scan d'un vers hors mètre pair en mode classique
#     (diérèse globale, e des -re comptés, pause_e alexandrine, ciblage
#     mot à mot) ;
#   - pull_to_meter : tirage d'un vers contemporain régulier vers le mètre
#     dominant du poème (règle 2.5, mode contemporain seulement).
# Aucune règle de vers libre ne vit ici.

module Scansion
  # Règles propres au vers classique/mesuré (voir l'en-tête du fichier) :
  # tirage vers le mètre, diérèses, e des -re comptés.
  # Les règles du vers contemporain (e caduc, groupement, tirage 2.6) vivent
  # dans syllabification.rb, accents.rb et rythme.rb.
  module Classique
    module_function

    # Table des voyelles nasales précomposées -> voyelle orale.
    NASALES = { 'ã' => 'a', 'ẽ' => 'e', 'ĩ' => 'i', 'õ' => 'o', 'ũ' => 'u' }.freeze

    # Clé de rime STRICTE de fin de vers : depuis la voyelle de la dernière
    # syllabe jusqu'à la fin du vers. Normalisations : tilde combinant
    # retiré (ɑ̃ -> ɑ), a/ɑ unifiés, voyelles nasales précomposées aplaties,
    # m/n final ignoré — « âme » -> a, « ame » -> a, « carrée » -> e,
    # « arrêté » -> e, « port » -> ɔʁ.
    # @param res [Scansion::Result] résultat de scan_line (aligné)
    # @return [String, nil]
    def rhyme_key(res)
      syl = res.phones.split('-').last.to_s
      voy = /[#{Scansion::PHONEME_VOYELLE.source.delete('[]')}]/
      i = syl.index(voy)
      return nil unless i

      k = syl[i..].gsub(/̃/, '') # tilde combinant -> voyelle orale
      k = k.tr('ɑ', 'a')         # a et ɑ : même phonème
      k = k.gsub(/[ãẽĩõũ]/) { |m| NASALES[m] }
      k.sub(/[mn]\z/, '')        # -am/-an final == voyelle nasale
    end

    # Détection du régime d'un texte (mode :auto). counts : décomptes de
    # syllabes par ligne (1re passe, e muet compté ; nil pour les lignes
    # vides ou non alignées). keys : clés de rime de fin de vers (voir
    # .rhyme_key). :classique si au moins `meter_threshold` des vers tombent
    # sur un mètre pair [6, 8, 10, 12] — la signature du vers classique est la
    # RÉPÉTITION de longueurs paires — ET si au moins `rhyme_threshold` des
    # vers participent à une rime de fin de vers (critère appliqué seulement
    # à partir de 4 vers) ; :contemporain sinon (comptes impairs, irrégularité
    # de vers en vers, absence de rimes).
    def detect_mode(counts, keys: nil, meter_threshold: 0.7, rhyme_threshold: 0.7)
      cs = counts.compact
      return :contemporain if cs.empty?

      evens = cs.count { |c| Scansion::METRES.include?(c) }
      return :contemporain if evens.to_f / cs.size < meter_threshold

      if keys && keys.compact.size >= 4
        ks = keys.compact
        tally = ks.tally
        rhymed = ks.count { |k| tally[k] >= 2 }
        return :contemporain if rhymed.to_f / ks.size < rhyme_threshold
      end
      :classique
    end

    # Mètre dominant du contexte (vers voisins) : la valeur de METRES la plus
    # fréquente parmi les voisins, si elle est majoritaire (>= 70 %).
    # Sert à « tirer » un vers contemporain régulier vers le mètre du poème
    # (ex. octosyllabe : un vers de 7 tire l'e caduc pour faire 8).
    def context_meter(counts, idx, window: 5, threshold: 0.7)
      lo = [idx - window, 0].max
      hi = [idx + window, counts.size - 1].min
      neigh = counts[lo..hi].compact
      neigh.delete_at(idx - lo) if idx >= lo && idx <= hi
      return nil if neigh.empty?

      meters = neigh.select { |c| Scansion::METRES.include?(c) }
      return nil if meters.size.to_f / neigh.size < threshold

      meters.tally.max_by { |_k, v| v }&.first
    end

    # Mots d’une ligne candidats à un « +1 » en contexte classique : diérèse
    # (règles 1.4c) OU e final compté d’un mot en -re (cluster_re_pronounced?).
    def fix_candidate_words(line)
      Scansion.words_of(Scansion.normalize_input(line)).select do |w|
        next false if w == 'hier'

        w.match?(Scansion::MOT_DIERESE) || w.sub(/s\z/, '').end_with?('re') ||
          w.match?(/[cgq]u?e[sx]?\z/) || w.end_with?('ent')
      end
    end

    # Re-scan (mode classique) d'un vers dont le compte brut (1re passe) ne
    # tombe pas sur un mètre pair : diérèse globale + e des -re comptés,
    # pause_e alexandrine,
    # e des -re seuls, puis ciblage mot à mot. On retient la première variante
    # alignée qui tombe sur un mètre.
    def auto_line(line, first_pass, cache: nil)
      r = first_pass
      return r unless r.aligned && !Scansion::METRES.include?(r.syllables)

      # 1) diérèse globale + e des -re comptés (contexte classique)
      r2 = Scansion.scan_line(line, dierese: true, cache: cache)
      r = r2 if r2.aligned && Scansion::METRES.include?(r2.syllables)
      # 1b) e muet prononcé devant une pause graphique (, ; : ! ? …),
      #     UNIQUEMENT si le vers devient alexandrin (12) : en vers
      #     irrégulier ou contemporain, la pause silencie le e muet
      unless Scansion::METRES.include?(r.syllables)
        r2b = Scansion.scan_line(line, dierese: false, pause_e: true, cache: cache)
        r = r2b if r2b.aligned && r2b.syllables == 12
      end
      unless Scansion::METRES.include?(r.syllables)
        r2c = Scansion.scan_line(line, dierese: true, pause_e: true, cache: cache)
        r = r2c if r2c.aligned && r2c.syllables == 12
      end
      # 2) e des -re comptés, aucune diérèse
      unless Scansion::METRES.include?(r.syllables)
        r3 = Scansion.scan_line(line, dierese: true, dierese_words: [], cache: cache)
        r = r3 if r3.aligned && Scansion::METRES.include?(r3.syllables)
      end
      # 3) ciblage mot à mot : diérèse sur w seul (e des -re tous comptés),
      #    puis diérèse + e de -re sur w seul
      unless Scansion::METRES.include?(r.syllables)
        fix_candidate_words(line).each do |w|
          combos = [[w, nil, nil], [w, [w], nil]]
          combos << [w, nil, [w]] if w.end_with?('ent')
          combos.each do |dw, cw, ew|
            r4 = Scansion.scan_line(line, dierese: true, dierese_words: dw,
                                          cluster_words: cw, ent_words: ew, cache: cache)
            if r4.aligned && Scansion::METRES.include?(r4.syllables)
              r = r4
              break
            end
          end
          break if Scansion::METRES.include?(r.syllables)
        end
      end
      r
    end

    # Règle 2.5 — tirage contextuel vers le mètre : en mode plain, un vers hors
    # mètre est re-scanné avec l'e caduc compté (sans diérèse) quand les vers
    # voisins sont unanimes (>= 70 %) sur un mètre M ; retenu si le résultat
    # fait exactement M (« les gouttes du dernier envol » -> 8).
    # Retourne le Result tiré, ou nil.
    def pull_to_meter(line, counts, idx, cache: nil)
      m = context_meter(counts, idx)
      return nil unless m

      r2 = Scansion.scan_line(line, dierese: false, cache: cache, count_mute_e: true)
      r2 if r2.aligned && r2.syllables == m
    end
  end
end
