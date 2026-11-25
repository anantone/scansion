# frozen_string_literal: true

# Tests RSpec pour lib/scansion/accents.rb (Scansion::Accents).
#
# La couche espeak-ng (Scansion.espeak) est bouchonnée comme dans
# scansion_spec.rb : la suite est déterministe et tourne sans espeak-ng.
# Les bouchons enregistrent ce que le vrai espeak-ng produit pour chaque
# ligne ; les résultats alignés portent des word_spans, donc le repli sur
# mot isolé (Phonemizer.phonemize) n'est jamais appelé ici.

require_relative '../lib/scansion/accents'

RSpec.describe Scansion::Accents do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  describe '.analyze_lines (mode contemporain, dierese: false)' do
    it '« mes pères criaient dessous mes pieds » -> 8 syllabes, phrase 4/8, mot 2/4/8' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁiɛdəsumepje')
      a = described_class.analyze_lines(['mes pères criaient dessous mes pieds'],
                                        dierese: false).first
      expect(a.syllables.size).to eq(8)
      expect(a.accents).to eq([3, 7]) # indices 0-based : syllabes 4 et 8
      expect(a.word_accents).to eq([1, 7]) # « criaient » (verbe fini) sans ˌ
      expect(a.render).to eq('me-ˌpɛʁ-kʁi-ˈɛ |-də-su-me-ˈpje')
    end

    it '« font un reflet sur ta peau d’ange » -> « font un reflet » = un seul groupe (verbe fini + COD)' do
      stub_espeak('font un reflet sur ta peau d’ange' => 'fɔ̃tœ̃ʁəflɛsyʁtapodɑ̃ʒ')
      a = described_class.analyze_lines(['font un reflet sur ta peau d’ange'],
                                        dierese: false).first
      expect(a.syllables.size).to eq(8)
      expect(a.accents).to eq([3, 7])
      expect(a.render).to eq('fɔ̃t-œ̃-ʁə-ˈflɛ |-syʁ-ta-ˌpo-ˈdɑ̃ʒ')
    end

    it '« qui sans qu’amer aucun s’efface » -> seuls amer et efface sont accentués' do
      stub_espeak('qui sans qu’amer aucun s’efface' => 'kisɑ̃kameokœ̃sefas')
      a = described_class.analyze_lines(['qui sans qu’amer aucun s’efface'],
                                        dierese: false).first
      expect(a.accents).to eq([3, 7])
      expect(a.word_accents).to eq([3, 7])
    end
  end

  describe '.analyze_line' do
    it 'analyse une ligne seule (diérèse :auto par défaut, e muet compté)' do
      stub_espeak('la belle table ronde' => 'labɛltablʁɔ̃d')
      a = described_class.analyze_line('la belle table ronde')
      expect(a.text).to eq('la belle table ronde')
      expect(a.syllables.size).to eq(6) # la-bɛ-lə-ta-blə-ʁɔ̃d
      expect(a.accents).to eq([5])
      expect(a.word_accents).to eq([1, 3, 5])
      expect(a.warnings).to be_empty
    end
  end
end

RSpec.describe Scansion::Accents, 'règles de groupement (édition manuelle)' do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  it '« C’est la date choisie… » : c’est est fonctionnel, le participe ouvre un groupe' do
    stub_espeak('C’est la date choisie au fond de ta pensée,' => 'sɛladatʃwaziofɔ̃dətapɑ̃se')
    a = described_class.analyze_line('C’est la date choisie au fond de ta pensée,', dierese: :auto)
    expect(a.syllables.size).to eq(12)
    expect(a.render).to eq('ˌsɛ-la-ˈda-tə |-ʃwa-ˈzi |-o-ˈfɔ̃ |-də-ta-pɑ̃-ˈse')
  end

  it '« Le dogue Liberté gronde… » : 12 syllabes en classique, frontière à la césure' do
    stub_espeak('Le dogue Liberté gronde et montre ses crocs ;' => 'lədoglibɛʁtegʁɔ̃demɔ̃tʁsekʁo')
    a = described_class.analyze_line('Le dogue Liberté gronde et montre ses crocs ;', dierese: :auto)
    expect(a.syllables.size).to eq(12)
    expect(a.render).to eq('lə-ˌdo-gə-li-bɛʁ-ˈte |-ˈgʁɔ̃d |-e-ˈmɔ̃-tʁə |-se-ˈkʁo')
  end

  it '« Viens, lève-toi ! Flairant dans l’ombre les escrocs, » : PP puis COD séparés' do
    stub_espeak('Viens, lève-toi ! Flairant dans l’ombre les escrocs,' => 'vjɛ̃lɛvtwaflɛʁɑ̃dɑ̃lɔ̃bʁlezɛskʁo')
    a = described_class.analyze_line('Viens, lève-toi ! Flairant dans l’ombre les escrocs,', dierese: :auto)
    expect(a.render).to eq('ˈvjɛ̃ |-lɛ-və-ˈtwa |-flɛ-ˈʁɑ̃ |-dɑ̃-ˈlɔ̃-bʁə |-le-zɛ-ˈskʁo')
  end
end
