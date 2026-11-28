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

  describe '.analyze_lines (mode contemporain, mode: :contemporain)' do
    it '« mes pères criaient dessous mes pieds » -> 8 syllabes ; frontière entre mots pleins (pères | criaient)' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁiɛdəsumepje')
      a = described_class.analyze_lines(['mes pères criaient dessous mes pieds'],
                                        mode: :contemporain).first
      expect(a.syllables.size).to eq(8)
      expect(a.accents).to eq([1, 3, 7]) # pères | criaient | (dessous) mes pieds
      expect(a.word_accents).to eq([1, 7]) # « criaient » (verbe fini) sans ˌ
      expect(a.render).to eq('me-ˈpɛʁ |-kʁi-ˈɛ |-də-su-me-ˈpje')
    end

    # « font un reflet » reste un seul groupe (verbe fini + COD), mais
    # « peau | d'ange » se coupe (« d' + mot » soudé coupe en contemporain)
    it '« font un reflet sur ta peau d’ange » -> groupes 4/3/1' do
      stub_espeak('font un reflet sur ta peau d’ange' => 'fɔ̃tœ̃ʁəflɛsyʁtapodɑ̃ʒ')
      a = described_class.analyze_lines(['font un reflet sur ta peau d’ange'],
                                        mode: :contemporain).first
      expect(a.syllables.size).to eq(8)
      expect(a.accents).to eq([3, 6, 7])
      expect(a.render).to eq('fɔ̃t-œ̃-ʁə-ˈflɛ |-syʁ-ta-ˈpo |-ˈdɑ̃ʒ')
    end

    it '« qui sans qu’amer aucun s’efface » -> seuls amer et efface sont accentués' do
      stub_espeak('qui sans qu’amer aucun s’efface' => 'kisɑ̃kameokœ̃sefas')
      a = described_class.analyze_lines(['qui sans qu’amer aucun s’efface'],
                                        mode: :contemporain).first
      expect(a.accents).to eq([3, 7])
      expect(a.word_accents).to eq([3, 7])
    end

    it 'frontière entre deux mots pleins en contemporain (« de bile noire » -> de bile | noire)' do
      stub_espeak('de bile noire qui s’écoule' => 'dəbilnwaʁkisekul')
      a = described_class.analyze_lines(['de bile noire qui s’écoule'], mode: :contemporain).first
      expect(a.render).to eq('də-ˈbil |-ˈnwaʁ |-ki-se-ˈkul')
    end

    it '« alors » ouvre un groupe mais « alors que » ne se coupe pas après (contemporain)' do
      stub_espeak('dans mon cerveau alors que rien' => 'dɑ̃mɔ̃sɛʁvoalɔʁkəʁjɛ̃')
      a = described_class.analyze_lines(['dans mon cerveau alors que rien'], mode: :contemporain).first
      expect(a.render).to eq('dɑ̃-mɔ̃-sɛʁ-ˈvo |-a-ˈlɔʁ |-kə-ˈʁjɛ̃')
    end

    it 'mot plein suivi d’une préposition (hors de) : frontière en contemporain (« d’or | en ta chair »)' do
      stub_espeak('vide truffé d’or en ta chair absente' => 'vidə tʁyfe dɔʁ ɑ̃ ta ʃɛʁ absɑ̃t')
      a = described_class.analyze_lines(['vide truffé d’or en ta chair absente'],
                                        mode: :contemporain).first
      expect(a.render).to include('|-ɑ̃-ta-ˈʃɛʁ') # frontière d’or | en
    end

    it '« de + nom nu » complément ne coupe PAS, même en contemporain (« l’absence de sens » = un groupe)' do
      stub_espeak('de l’absence de sens' => 'dəlabsɑ̃sdəsɑ̃s')
      a = described_class.analyze_lines(['de l’absence de sens'], mode: :contemporain).first
      expect(a.render).to eq('də-lab-ˌsɑ̃s-də-ˈsɑ̃s')
    end

    it '« d’ange » soudé coupe en contemporain, collé en classique (« peau d’ange »)' do
      stub_espeak('font un reflet sur ta peau d’ange' => 'fɔ̃tœ̃ʁəflɛsyʁtapodɑ̃ʒ')
      a = described_class.analyze_lines(['font un reflet sur ta peau d’ange'],
                                        mode: :contemporain).first
      expect(a.render).to eq('fɔ̃t-œ̃-ʁə-ˈflɛ |-syʁ-ta-ˈpo |-ˈdɑ̃ʒ')
      a = described_class.analyze_lines(['font un reflet sur ta peau d’ange'],
                                        mode: :classique).first
      expect(a.render).to eq('fɔ̃t-œ̃-ʁə-ˈflɛ |-syʁ-ta-ˌpo-ˈdɑ̃ʒ')
    end

    it '« en » après un mot plein coupe en contemporain (« je prie | en silence »)' do
      stub_espeak('Surtout que je prie en silence' => 'syʁtukəʒəpʁiɑ̃silɑ̃s')
      a = described_class.analyze_lines(['Surtout que je prie en silence'], mode: :contemporain).first
      expect(a.render).to include('pʁi |-ɑ̃-si')
    end

    it 'la négation « pas » ne coupe pas le groupe verbal (« ne meurt pas »)' do
      stub_espeak('L’écrivain ne meurt pas :' => 'lekʁivɛ̃nəmœʁpa')
      a = described_class.analyze_lines(['L’écrivain ne meurt pas :'], mode: :contemporain).first
      expect(a.render).to include('mœʁ-ˈpa')
    end

    it 'pas de frontière de groupe à l’intérieur d’un mot (span cerveau | alors)' do
      stub_espeak('dans mon cerveau alors que rien' => 'dɑ̃mɔ̃sɛʁvoalɔʁkəʁjɛ̃')
      a = described_class.analyze_lines(['dans mon cerveau alors que rien'], mode: :contemporain).first
      spans = a.tokens.select { |t| t.kind == :word }.map { |t| [t.surface, t.debut, t.fin] }
      expect(spans).to eq([['dans', 0, 0], ['mon', 1, 1], ['cerveau', 2, 3],
                           ['alors', 4, 5], ['que', 6, 6], ['rien', 7, 7]])
    end
  end

  describe '.analyze_line' do
    it 'analyse une ligne seule (mode classique par défaut, e muet compté)' do
      stub_espeak('la belle table ronde' => 'labɛltablʁɔ̃d')
      a = described_class.analyze_line('la belle table ronde')
      expect(a.text).to eq('la belle table ronde')
      expect(a.syllables.size).to eq(6) # la-bɛ-lə-ta-blə-ʁɔ̃d
      expect(a.accents).to eq([5])
      expect(a.word_accents).to eq([1, 3, 5])
      expect(a.warnings).to be_empty
    end

    it 'deux régimes explicites : e muet compté en classique, tirage 2.6 seul en contemporain' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁijɛdəsumepje')
      classique = described_class.analyze_line('mes pères criaient dessous mes pieds', mode: :classique)
      contemporain = described_class.analyze_line('mes pères criaient dessous mes pieds', mode: :contemporain)
      expect(classique.syllables.size).to eq(10)   # e de « pères » compté + diérèse pi-je vers le mètre pair 10
      expect(contemporain.syllables.size).to eq(8) # e caduc non compté, aucun tirage 2.6
    end

    it 'lève ArgumentError avec un mode inconnu' do
      expect { described_class.analyze_line('la belle table ronde', mode: :foo) }
        .to raise_error(ArgumentError, /mode inconnu/)
    end

    it ':auto (défaut) détecte :classique sur un vers de 12 syllabes' do
      stub_espeak('C’est la date choisie au fond de ta pensée,' => 'sɛladatʃwaziofɔ̃dətapɑ̃se')
      a = described_class.analyze_line('C’est la date choisie au fond de ta pensée,')
      expect(a.syllables.size).to eq(12)
      expect(a.render).to eq('ˌsɛ-la-ˈda-tə |-ʃwa-ˈzi |-o-ˈfɔ̃ |-də-ta-pɑ̃-ˈse')
    end

    it ':auto (défaut) détecte :contemporain sur un vers de compte impair' do
      stub_espeak('mes pères criaient dessous mes pieds' => 'mepɛʁkʁijɛdəsumepje')
      a = described_class.analyze_line('mes pères criaient dessous mes pieds')
      expect(a.syllables.size).to eq(8) # e caduc non compté, comme en :contemporain
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
    a = described_class.analyze_line('C’est la date choisie au fond de ta pensée,', mode: :classique)
    expect(a.syllables.size).to eq(12)
    expect(a.render).to eq('ˌsɛ-la-ˈda-tə |-ʃwa-ˈzi |-o-ˈfɔ̃ |-də-ta-pɑ̃-ˈse')
  end

  it '« Le dogue Liberté gronde… » : 12 syllabes en classique, frontière à la césure' do
    stub_espeak('Le dogue Liberté gronde et montre ses crocs ;' => 'lədoglibɛʁtegʁɔ̃demɔ̃tʁsekʁo')
    a = described_class.analyze_line('Le dogue Liberté gronde et montre ses crocs ;', mode: :classique)
    expect(a.syllables.size).to eq(12)
    expect(a.render).to eq('lə-ˌdo-gə-li-bɛʁ-ˈte |-ˈgʁɔ̃d |-e-ˈmɔ̃-tʁə |-se-ˈkʁo')
  end

  it '« Viens, lève-toi ! Flairant dans l’ombre les escrocs, » : PP puis COD séparés' do
    stub_espeak('Viens, lève-toi ! Flairant dans l’ombre les escrocs,' => 'vjɛ̃lɛvtwaflɛʁɑ̃dɑ̃lɔ̃bʁlezɛskʁo')
    a = described_class.analyze_line('Viens, lève-toi ! Flairant dans l’ombre les escrocs,', mode: :classique)
    expect(a.render).to eq('ˈvjɛ̃ |-lɛ-və-ˈtwa |-flɛ-ˈʁɑ̃ |-dɑ̃-ˈlɔ̃-bʁə |-le-zɛ-ˈskʁo')
  end
end

RSpec.describe Scansion::Accents, 'affinage contemporain (locutions, frontières)' do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line.strip) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  def groupe_de(a, mot)
    a.groups.find { |g| g.tokens.any? { |t| t.surface == mot } }
  end

  it 'locution soudée : « nulle part » dans un seul groupe' do
    stub_espeak('beaucoup nulle part exprès' => 'bokunylpaʁɛkspʁɛ')
    a = described_class.analyze_line('beaucoup nulle part exprès', mode: :contemporain)
    expect(groupe_de(a, 'nulle').tokens.map(&:surface)).to include('part')
  end

  it 'locution soudée : « peu partout » dans un seul groupe' do
    stub_espeak('un peu partout au hasard' => 'œ̃pøpaʁtuoazaʁ')
    a = described_class.analyze_line('un peu partout au hasard', mode: :contemporain)
    expect(groupe_de(a, 'peu').tokens.map(&:surface)).to include('partout')
  end

  it '« levé comme » : en contemporain, « comme » ouvre un groupe après un participe (« levé | comme un enfant »)' do
    stub_espeak('lors s’est levé comme un enfant' => 'lɔʁsɛləvekɔmœ̃nɑ̃fɑ̃')
    a = described_class.analyze_line('lors s’est levé comme un enfant', mode: :contemporain)
    expect(groupe_de(a, 'levé').tokens.map(&:surface)).not_to include('comme')
  end

  it '« laissée | frotter » : en contemporain, un infinitif après un participe ouvre un groupe' do
    stub_espeak('tu t’es laissée frotter, pousser, déchirer' => 'tytɛlɛsefʁɔtepusedeʃiʁe')
    a = described_class.analyze_line('tu t’es laissée frotter, pousser, déchirer', mode: :contemporain)
    expect(groupe_de(a, 'laissée').tokens.map(&:surface)).not_to include('frotter')
  end
end

RSpec.describe Scansion::Accents, 'affinage guidé, round 2 (nom-de-je, ou-presque)' do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line.strip) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  def groupe_de(a, mot)
    a.groups.find { |g| g.tokens.any? { |t| t.surface == mot } }
  end

  it '« Après tout, | l’autre langage | te ressemble » : la virgule est une frontière dure (contemporain)' do
    stub_espeak('Après tout, l’autre langage te ressemble —' => 'apʁɛtulotʁlɑ̃gaʒtəʁəsɑ̃bl')
    a = described_class.analyze_line('Après tout, l’autre langage te ressemble —', mode: :contemporain)
    expect(groupe_de(a, 'l’autre').tokens.map(&:surface)).not_to include('tout')
    # « te » (COD, après un nom) ouvre un nouveau groupe
    expect(groupe_de(a, 'te').tokens.map(&:surface)).not_to include('langage')
  end

  it '« prend | soin | du temple » : « prend » (-d) n’est pas reconnu verbe fini, chaque mot plein ouvre un groupe' do
    stub_espeak('(prend soin du temple en silence et emploie,' => 'pʁɑ̃swɛ̃dytɑ̃plɑ̃silɑ̃seɑ̃plwa')
    a = described_class.analyze_line('(prend soin du temple en silence et emploie,', mode: :contemporain)
    expect(groupe_de(a, 'prend').tokens.map(&:surface)).not_to include('soin')
    expect(groupe_de(a, 'du').tokens.map(&:surface)).to include('temple')
  end

  it '« l’esprit | prêtre » : nom + nom en apposition se séparent (INFINITIF ne vise plus -re)' do
    stub_espeak('l’esprit prêtre, à son meilleur lorsqu’il se tait' => 'lɛspʁipʁɛtʁasɔ̃mɛjœʁloʁskilsətɛ')
    a = described_class.analyze_line('l’esprit prêtre, à son meilleur lorsqu’il se tait', mode: :contemporain)
    expect(groupe_de(a, 'l’esprit').tokens.map(&:surface)).not_to include('prêtre')
  end

  it '« lorsqu’il se tait » : le réfléchi « se » reste collé au groupe précédent' do
    stub_espeak('l’esprit prêtre, à son meilleur lorsqu’il se tait' => 'lɛspʁipʁɛtʁasɔ̃mɛjœʁloʁskilsətɛ')
    a = described_class.analyze_line('l’esprit prêtre, à son meilleur lorsqu’il se tait', mode: :contemporain)
    expect(groupe_de(a, 'lorsqu’il').tokens.map(&:surface)).to include('se')
  end

  it '« pas appris | l’histoire » : après ne/pas, un mot en -is est un participe (frontière avant le COD)' do
    stub_espeak('Je n’avais pas appris l’histoire de l’art.' => 'ʒənavɛpazapʁilistwaʁdəlaʁ')
    a = described_class.analyze_line('Je n’avais pas appris l’histoire de l’art.', mode: :contemporain)
    expect(groupe_de(a, 'appris').tokens.map(&:surface)).not_to include('l’histoire')
  end
end

RSpec.describe Scansion::Accents, 'régressions (revue de code)' do
  it 'word_accents est public, comme le documente l’en-tête du module' do
    expect(described_class).to respond_to(:word_accents)
  end

  it 'les constantes de tête de mot sont accessibles sur le module' do
    expect(described_class::FRAGMENTS_CLITIQUES).to include('l')
    expect('criaient').to match(described_class::TERMINAISONS_VERBE_FINI)
  end

  it 'analyze_lines ne masque plus un mode invalide' do
    expect { described_class.analyze_lines(['un vers'], mode: :inconnu) }
      .to raise_error(ArgumentError, /mode inconnu/)
  end

  it 'analyze_lines en :auto résout le régime une seule fois et le transmet à process_lines' do
    line = 'la belle table ronde'
    allow(Scansion).to receive(:espeak) { |l| l == line ? 'labɛltablʁɔ̃d' : raise(KeyError, l) }
    expect(Scansion).to receive(:process_lines)
      .with(anything, hash_including(mode: :classique)).and_call_original
    described_class.analyze_lines([line] * 3)
  end
end

RSpec.describe Scansion::Accents, 'positions des tokens dans le texte (char_debut / char_fin)' do
  def stub_espeak(mapping)
    allow(Scansion).to receive(:espeak) do |line|
      mapping.fetch(line) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  def positions(analysis)
    analysis.tokens.map { |t| [t.surface, t.char_debut, t.char_fin] }
  end

  it 'repère mots et ponctuation dans le texte d’origine, espaces de tête comprises' do
    texte = '  l’ombre, et le soleil !'
    stub_espeak(texte => 'lɔ̃bʁeləsolɛj')
    a = described_class.analyze_line(texte, mode: :contemporain)
    expect(positions(a)).to eq([['l’ombre', 2, 8], [',', 9, 9], ['et', 11, 12], ['le', 14, 15],
                                ['soleil', 17, 22], ['!', 24, 24]])
    a.tokens.each { |t| expect(a.text[t.char_debut..t.char_fin]).to eq(t.surface) }
  end

  it 'garde les positions d’origine malgré la normalisation (chiffres, entités HTML)' do
    texte = 'le 13 mai &amp; les nœuds-coulants'
    stub_espeak('le   mai   les nœuds-coulants' => 'ləmɛlenøkulɑ̃')
    a = described_class.analyze_line(texte, mode: :contemporain)
    expect(positions(a)).to eq([['le', 0, 1], ['mai', 6, 8], ['les', 16, 18], ['nœuds-coulants', 20, 33]])
    expect(a.tokens.map(&:surface)).to eq(Scansion.normalize_input(texte).scan(described_class::REGEXP_MOTS))
  end
end
