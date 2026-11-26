# frozen_string_literal: true

# Tests RSpec pour lib/scansion/rythme.rb (Scansion::Rythme) — caractéristiques
# rythmiques du vers (signature, score) et tirage accentuel (règle 2.6).
#
# La couche espeak-ng (Scansion.espeak) est bouchonnée : la suite est
# déterministe et tourne sans espeak-ng.

require 'spec_helper'

RSpec.describe Scansion::Rythme do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line) { raise "espeak non bouchonné pour: #{line.inspect}" }
    end
  end

  describe '.score (régularité d\'une signature de groupes)' do
    it 'pondère les tailles répétées >= 2, les paires adjacentes en plus' do
      expect(described_class.score([3, 3, 3, 3])).to eq(6) # base 3 + bonus 3
      expect(described_class.score([2, 2, 3, 3])).to eq(4) # base 2 + bonus 2
      expect(described_class.score([2, 4, 4, 2])).to eq(3) # base 2 + bonus 1
      expect(described_class.score([6, 3, 3])).to eq(2)    # base 1 + bonus 1
      expect(described_class.score([8, 3])).to eq(0)
      expect(described_class.score([1, 1, 3])).to eq(0)    # taille 1 ignorée
    end
  end

  describe '.accent_pull (règle 2.6)' do
    it 'tire « la substance de mort s’additionne au vécu » vers 12 (+e : [6,3,3] bat [8,3])' do
      stub_espeak('la substance de mort s’additionne au vécu' => 'lasybstɑ̃sdəmɔʁsaditjɔnoveky')
      plain = Scansion.process_line('la substance de mort s’additionne au vécu', mode: :contemporain)
      expect(plain.syllables).to eq(11)
      pulled = described_class.accent_pull('la substance de mort s’additionne au vécu', plain)
      expect(pulled.syllables).to eq(12)
      expect(pulled.phones).to include('stɑ̃-sə')
    end

    it 'ne tire pas quand aucune variante ne bat le plain' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁijɛdəsumepje')
      plain = Scansion.process_line('mes pères criaient dessous mes pieds', mode: :contemporain)
      expect(plain.syllables).to eq(8)
      pulled = described_class.accent_pull('mes pères criaient dessous mes pieds', plain)
      expect(pulled.syllables).to eq(8)
    end

    it 'un tirage n’ajoute qu’une syllabe au plus (« derrière la tête le passé jouit » reste à 8)' do
      stub_espeak('derrière la tête le passé jouit' => 'dɛʁjɛʁlatɛtləpaseʒwi')
      plain = Scansion.process_line('derrière la tête le passé jouit', mode: :contemporain)
      expect(plain.syllables).to eq(8)
      pulled = described_class.accent_pull('derrière la tête le passé jouit', plain)
      expect(pulled.syllables).to eq(8) # la variante +e ferait 10 : refusée (MAX_PULL_SYLLABES)
    end

    it 'jamais de diérèse restaurée sur « dieu/dieux » (« des dieux » reste à djø)' do
      stub_espeak('la fureur des dieux et la folie des hommes' => 'lafyʁœʁdedjøzelafolidezɔm')
      plain = Scansion.process_line('la fureur des dieux et la folie des hommes', mode: :contemporain)
      pulled = described_class.accent_pull('la fureur des dieux et la folie des hommes', plain)
      expect(pulled.syllables).to eq(11)
      expect(pulled.phones).to include('de-djø')
    end
  end

  describe '.signature' do
    it 'calcule les tailles de groupes depuis une analyse scansion' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁijɛdəsumepje')
      a = Scansion::Accents.analyze_line('mes pères criaient dessous mes pieds', mode: :contemporain)
      expect(described_class.signature(a)).to eq([2, 2, 4])
    end
  end

  describe 'intégration dans Accents.analyze_line (tirage 2.6 en mode contemporain)' do
    it 'applique le tirage dans analyze_line quand mode: :contemporain' do
      stub_espeak('la substance de mort s’additionne au vécu' => 'lasybstɑ̃sdəmɔʁsaditjɔnoveky')
      a = Scansion::Accents.analyze_line('la substance de mort s’additionne au vécu', mode: :contemporain)
      expect(a.syllables.size).to eq(12)
    end

    it 'ne tire jamais en mode classique (mode: :classique)' do
      stub_espeak('la substance de mort s’additionne au vécu' => 'lasybstɑ̃sdəmɔʁsaditjɔnoveky')
      a = Scansion::Accents.analyze_line('la substance de mort s’additionne au vécu', mode: :classique)
      r = Scansion.process_line('la substance de mort s’additionne au vécu', mode: :classique)
      expect(a.syllables.size).to eq(r.syllables) # aucun tirage 2.6 ajouté
    end
  end
end
