#!/usr/bin/env ruby
# frozen_string_literal: true
#
# scansion.rb — point d'entrée du gem scansion : phonétise des vers français
# (espeak-ng) en restaurant le e muet selon les règles de la scansion
# classique, marque les frontières de syllabes et compte les syllabes.
#
# Le gem est organisé en plusieurs fichiers sous lib/scansion/ :
#   syllabification.rb   cœur : alignement + restauration du e muet + compte
#   accents.rb           Scansion::Accents — accents de phrase (ˈ) et de mot (ˌ)
#   cli.rb               Scansion.main (ligne de commande, via bin/scansion)
#   version.rb           Scansion::VERSION
#
# `require "scansion"` charge tout ceci sans effet de bord. Voir
# docs/scansion_rules.txt pour la liste complète des règles.

require_relative "scansion/version"
require_relative "scansion/syllabification"
require_relative "scansion/accents"
require_relative "scansion/cli"
