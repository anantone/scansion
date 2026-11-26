#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scansion.rb — point d'entrée du gem scansion : phonétise des vers français
# (espeak-ng), compte les syllabes et accentue. Le régime se règle par `mode:`
# (:auto par défaut — détection automatique du régime, :classique, :contemporain).
#
# Le gem est organisé en plusieurs fichiers sous lib/scansion/ :
#   syllabification.rb   cœur partagé : alignement + restauration du e muet + compte
#                        (points d'entrée : process_line(s) avec mode:, detect_mode)
#   classique.rb         Scansion::Classique — détection du régime (:auto), règles du
#                        vers mesuré (re-scan vers un mètre pair, diérèses, e des -re)
#   rythme.rb            Scansion::Rythme — caractéristiques rythmiques du vers
#                        (signature, score de régularité) et tirage accentuel 2.6
#   accents.rb           Scansion::Accents — accents de phrase (ˈ) et de mot (ˌ)
#   cli.rb               Scansion.main (ligne de commande, via bin/scansion)
#   version.rb           Scansion::VERSION
#
# `require "scansion"` charge tout ceci sans effet de bord. Voir
# docs/scansion_rules.txt pour la liste complète des règles. L'évaluation
# subjective de ces caractéristiques (score global du vers) vit dans le gem
# claudel, au-dessus de celui-ci.

require_relative 'scansion/version'
require_relative 'scansion/syllabification'
require_relative 'scansion/classique'
require_relative 'scansion/rythme'
require_relative 'scansion/accents'
require_relative 'scansion/cli'
