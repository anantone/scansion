# frozen_string_literal: true

# Tests RSpec pour lib/scansion.rb + lib/scansion/cli.rb (point d'entrée et
# CLI du gem scansion).

require 'tempfile'
require_relative '../lib/scansion'

RSpec.describe Scansion do
  describe 'bibliothèque sans effets de bord' do
    it "se require sans toucher à ARGV (Scansion.main n'est appelé que as script)" do
      # si le CLI tournait au require, l OptionParser lèverait InvalidOption
      expect(defined?(Scansion.main)).to eq('method')
    end
  end

  describe '.main (CLI)' do
    let(:vers) { 'la belle table ronde' }

    before do
      allow(described_class).to receive(:espeak) do |line|
        { vers => 'labɛltablʁɔ̃d' }.fetch(line) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
      end
    end

    it 'scande du texte passé en argument (-s : décompte seul)' do
      expect { described_class.main(['--classique', '-s', vers]) }.to output("  6  #{vers}\n").to_stdout
    end

    it 'lit un fichier en UTF-8' do
      Tempfile.create(['vers', '.txt']) do |f|
        f.write("#{vers}\n")
        f.flush
        expect { described_class.main(['--classique', '-s', f.path]) }.to output("  6  #{vers}\n").to_stdout
      end
    end

    it 'lit l’entrée standard sans argument' do
      allow($stdin).to receive(:each_line).and_return(["#{vers}\n"].each)
      expect { described_class.main(['--classique', '-s']) }.to output("  6  #{vers}\n").to_stdout
    end

    it 'ne modifie ni l’argv reçu ni ARGV' do
      argv = ['-s', vers]
      argv_global = ARGV.dup
      expect { described_class.main(argv) }.to output.to_stdout
      expect(argv).to eq(['-s', vers])
      expect(ARGV).to eq(argv_global)
    end

    it '-h affiche l’aide sans appeler exit' do
      expect { described_class.main(['-h']) }.to output(/Utilisation/).to_stdout
    end
  end
end
