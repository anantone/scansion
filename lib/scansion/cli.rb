# frozen_string_literal: true

#
# cli.rb — point d'entrée CLI du gem scansion (Scansion.main), invoqué
# seulement quand ce fichier est exécuté comme script, ou appelé
# explicitement via bin/scansion. Le require de "scansion" reste sans effet
# de bord : pas d'OptionParser sur l'ARGV de l'hôte.

require 'optparse'
require_relative 'syllabification'

# Module Scansion rouvert ici pour y loger le point d'entrée CLI
# (Scansion.main) ; voir scansion/syllabification pour le cœur du gem.
module Scansion
  class << self
    # -- CLI -------------------------------------------------------------

    # Point d'entrée, invoqué seulement quand le fichier est exécuté comme
    # script ($PROGRAM_NAME == __FILE__), afin que le require de ce fichier
    # reste sans effet de bord : pas d'OptionParser qui consommerait l'ARGV de
    # l'hôte, pas de mutation d'encodage global.
    #
    # @param argv [Array<String>] arguments de la ligne de commande
    #   (options --no-dierese, -s/--syllables, -h/--help, puis FILE ou « - »
    #   pour lire l'entrée standard)
    # @return [void]
    def main(argv = ARGV)
      options = { syllables_only: false, dierese: :auto }
      OptionParser.new do |opts|
        opts.banner = "Utilisation : #{File.basename($PROGRAM_NAME)} [options] [FILE|-]"
        opts.on('--no-dierese', 'Désactiver la diérèse contextuelle (corpus contemporain)') do
          options[:dierese] = false
        end
        opts.on('-s', '--syllables', 'Afficher seulement le décompte des syllabes') do
          options[:syllables_only] = true
        end
        opts.on('-h', '--help', 'Afficher cette aide') do
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
        if arg == '-' || File.exist?(arg)
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
          puts format('%3d  %s', res.syllables, res.text.to_s.strip)
        else
          puts res.text.to_s.rstrip
          puts format('  %s %s   (%d syll.)', res.aligned ? '⇒' : '~', res.phones, res.syllables)
          puts "    (espeak seul : #{res.raw})" unless res.aligned
          puts ''
        end

        fallbacks += 1 unless res.aligned
      end

      warn "scansion : #{fallbacks} vers non alignés (sortie espeak brute)" if fallbacks.positive?
    end
  end
end

Scansion.main if $PROGRAM_NAME == __FILE__
