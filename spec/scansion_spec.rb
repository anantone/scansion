# frozen_string_literal: true

# Tests RSpec pour lib/scansion.rb (le gem scansion).
#
# La couche espeak-ng (Scansion.espeak) est bouchonnée partout, donc les
# specs sont déterministes et tournent sans espeak-ng ni le gem phonemizer.
# Les bouchons enregistrent ce que le vrai espeak-ng produit pour chaque
# ligne (élisions comprises), ce qui est exactement ce que l'alignement
# doit gérer.
# Note : Result#phones porte les séparateurs de syllabes (« - »), pas les
# bouchons espeak bruts.

require_relative "../lib/scansion"

RSpec.describe Scansion do
  def stub_espeak(mapping)
    allow(described_class).to receive(:espeak) do |line|
      mapping.fetch(line) { raise KeyError, "espeak non stubbé : #{line.inspect}" }
    end
  end

  def process(line, keep_line_end_e: false)
    described_class.process_line(line, keep_line_end_e: keep_line_end_e)
  end

  describe ".segments" do
    it "découpe l'IPA en segments voyelle/consonne" do
      expect(described_class.segments("ʃəval")).to eq(%w[ʃ ə v a l])
    end

    it "attache les diacritiques nasaux à leur voyelle" do
      expect(described_class.segments("vɑ̃dʁ")).to eq(["v", "ɑ̃", "d", "ʁ"])
    end
  end

  describe ".mark_syllables" do
    it "insère un - entre les syllabes (attaque maximale)" do
      expect(described_class.mark_syllables(%w[t a b l ə ʁ ɔ̃ d]))
        .to eq("ta-blə-ʁɔ̃d")
    end

    it "garde la coda finale sans tiret" do
      expect(described_class.mark_syllables(%w[l a t a b l])).to eq("la-tabl")
    end

    it "garde le glide dans le noyau (mi-ʁwaʁ)" do
      expect(described_class.mark_syllables(%w[m i ʁ w a ʁ])).to eq("mi-ʁwaʁ")
    end

    it "sépare les hiatus (ə-e)" do
      expect(described_class.mark_syllables(%w[ə e ʁ o])).to eq("ə-e-ʁo")
    end
  end

  describe ".vowel_initial?" do
    it "reconnaît les initiales vocaliques" do
      expect(described_class.vowel_initial?("orange")).to be true
      expect(described_class.vowel_initial?("homme")).to be true # h muet
    end

    it "rejette les consonnes (h aspiré reste vocaliquement initial, voir elides_before?)" do
      expect(described_class.vowel_initial?("rouge")).to be false
      expect(described_class.vowel_initial?("chien")).to be false
      expect(described_class.vowel_initial?("haie")).to be true  # h aspiré: /ɛz/ commence par une voyelle
      expect(described_class.elides_before?("haie")).to be false # mais bloque l'élision
    end
  end

  describe "comptes de l'e muet" do
    it "compte l'e muet final devant consonne" do
      stub_espeak("table ronde" => "tablʁɔ̃d")
      r = process("table ronde")
      expect(r).to have_attributes(aligned: true, phones: "ta-blə-ʁɔ̃d",
                                   syllables: 3)
    end

    it "ne compte pas l'e muet en fin de vers" do
      stub_espeak("la table" => "latabl")
      r = process("la table")
      expect(r).to have_attributes(phones: "la-tabl", syllables: 2)
    end

    it "le compte si demandé (--keep-line-end-e)" do
      stub_espeak("la table" => "latabl")
      r = process("la table", keep_line_end_e: true)
      expect(r).to have_attributes(phones: "la-ta-blə", syllables: 3)
    end

    it "élide l'e final devant un mot à initiale vocalique" do
      stub_espeak("table orange" => "tablɔʁɑ̃ʒ")
      r = process("table orange")
      expect(r.phones).to eq("tabl-ɔ-ʁɑ̃ʒ")
    end

    it "restaure l'e final devant un s muet" do
      stub_espeak("tables blanches" => "tablblɑ̃ʃ")
      r = process("tables blanches")
      expect(r.phones).to eq("ta-blə-blɑ̃ʃ")
    end

    it "ne compte pas l'e final devant une pause graphique (, ; : ! ? …)" do
      stub_espeak("la table, ronde" => "latablʁɔ̃d") # espeak nettoie la virgule
      r = process("la table, ronde")
      expect(r).to have_attributes(aligned: true, phones: "la-tabl-ʁɔ̃d",
                                   syllables: 3)
    end

    it "compte l'e final devant une consonne sans pause (contraste)" do
      stub_espeak("la table ronde" => "latablʁɔ̃d") # idem, sans virgule
      r = process("la table ronde")
      expect(r.phones).to eq("la-ta-blə-ʁɔ̃d")
    end
  end

  describe "restauration interne et terminaisons" do
    it "restaure les e muets internes" do
      stub_espeak("redemande encore" => "ʁdmɑ̃dɑ̃kɔʁ")
      r = process("redemande encore")
      expect(r.phones).to eq("ʁə-də-mɑ̃d-ɑ̃-kɔʁ")
      expect(r.syllables).to eq(5)
    end

    it "laisse les schwas qu'espeak prononce déjà" do
      stub_espeak("cheval" => "ʃəval")
      r = process("cheval")
      expect(r.phones).to eq("ʃə-val")
      expect(r.syllables).to eq(2)
    end

    it "ne compte pas la terminaison -ent en fin de vers" do
      stub_espeak("ils chantent" => "ilʃɑ̃t")
      r = process("ils chantent")
      expect(r.phones).to eq("il-ʃɑ̃t")
      expect(r.syllables).to eq(2)
    end

    it "prononce le -ent devant une consonne dans le vers" do
      stub_espeak("ils chantent bien" => "ilʃɑ̃tbjɛ̃")
      r = process("ils chantent bien")
      expect(r).to have_attributes(aligned: true, phones: "il-ʃɑ̃-tə-bjɛ̃",
                                   syllables: 4)
    end

    it "prononce le -ent devant un h aspiré" do
      stub_espeak("ils chantent héros" => "ilʃɑ̃teʁo")
      r = process("ils chantent héros")
      expect(r).to have_attributes(aligned: true, phones: "il-ʃɑ̃-tə-e-ʁo",
                                   syllables: 5)
    end

    it "ne prononce pas le -ent devant une voyelle, mais lie en t" do
      stub_espeak("ils chantent ici" => "ilʃɑ̃ttisi")
      r = process("ils chantent ici")
      expect(r).to have_attributes(aligned: true, phones: "il-ʃɑ̃tt-i-si",
                                   syllables: 4)
    end

    it "gère la liaison en t du -ent devant une voyelle" do
      stub_espeak("ils peuplent à peine" => "ilpøpltapɛn")
      r = process("ils peuplent à peine")
      expect(r).to have_attributes(aligned: true, phones: "il-pøplt-a-pɛn",
                                   syllables: 4)
    end

    it "ne restaure pas le e nasal de -ent (violent -> vjolɑ̃)" do
      stub_espeak("un violent héros" => "œ̃vjolɑ̃eʁo")
      r = process("un violent héros")
      expect(r).to have_attributes(aligned: true, phones: "œ̃-vjo-lɑ̃-e-ʁo")
    end

    it "ne prononce pas le -ent après une voyelle (-uent, -ient)" do
      stub_espeak("qui perpétuent le souvenir" => "kipɛʁpetyləsuvniʁ")
      r = process("qui perpétuent le souvenir")
      expect(r).to have_attributes(aligned: true,
                                   phones: "ki-pɛʁ-pe-ty-lə-su-və-niʁ",
                                   syllables: 8)
    end
  end

  describe "cas phonologiques" do
    it "respecte la liaison des pluriels" do
      stub_espeak("les amis" => "lɛzami")
      r = process("les amis")
      expect(r.phones).to eq("lɛ-za-mi")
    end

    it "traite un vers complet" do
      stub_espeak("Je chante, à voix basse, la belle table" =>
                  "ʒəʃɑ̃tavwabaslabɛltabl")
      r = process("Je chante, à voix basse, la belle table")
      # chante, / basse, perdent leur e muet devant les virgules
      expect(r).to have_attributes(aligned: true, syllables: 9)
      expect(r.phones).to eq("ʒə-ʃɑ̃t-a-vwa-bas-la-bɛ-lə-tabl")
    end
  end

  describe "robustesse" do
    it "retombe sur la sortie espeak brute en cas d'échec d'alignement" do
      stub_espeak("chuchote" => "fʁø") # incompatible avec l'orthographe
      r = process("chuchote")
      expect(r).to have_attributes(aligned: false, raw: "fʁø", phones: "fʁø")
    end

    it "traite les lignes vides" do
      r = process("")
      expect(r).to have_attributes(aligned: true, phones: "", syllables: 0)
    end
  end

  describe ".clean_ipa" do
    it "supprime marqueurs de langue, ponctuation et accents de stress" do
      expect(described_class.clean_ipa("(en)kwhˈiə(fr), ")).to eq("kwhiə")
    end

    it "dé-anglicise les phones anglais d'espeak-ng et le U+0261" do
      expect(described_class.clean_ipa("ɡʁɑ̃θð")).to eq("gʁɑ̃td")
    end
  end

  describe "SILENT_TAILS" do
    it "reconnaît les terminaisons silencieuses" do
      expect("ent").to match(described_class::SILENT_TAILS)
      expect("ufs").to match(described_class::SILENT_TAILS)
      expect("aux").to match(described_class::SILENT_TAILS)
      expect("xyz").not_to match(described_class::SILENT_TAILS)
      expect("eta").not_to match(described_class::SILENT_TAILS)
    end
  end

  describe ".words_of / .pause_flags" do
    it "extrait les mots en ignorant apostrophes et ponctuation" do
      expect(described_class.words_of("L'été, c'est l'île !")).to eq(%w[l été c est l île])
    end

    it "détecte les pauses graphiques après chaque mot" do
      expect(described_class.pause_flags("la table, ronde", %w[la table ronde]))
        .to eq([false, true, false])
    end
  end

  describe ".count_syllables" do
    it "ne compte pas un y-glide devant une voyelle comme une syllabe" do
      expect(described_class.count_syllables(%w[f y i j ɛ])).to eq(2)
    end

    it "compte chaque voyelle sinon" do
      expect(described_class.count_syllables(%w[ʒ ə ʃ ɑ̃ t ə])).to eq(3)
    end
  end

  describe ".classical_context?" do
    it "vrai quand les voisins sont dans la bande alexandrine (10-13)" do
      expect(described_class.classical_context?([12, 12, 12, 12, 12], 2)).to be true
    end

    it "faux en vers libre contemporain" do
      expect(described_class.classical_context?([7, 5, 9, 4, 6, 8], 2)).to be false
    end

    it "faux sans voisin exploitable" do
      expect(described_class.classical_context?([12], 0)).to be false
    end
  end

  describe "exceptions -Cr- (entre, ventre)" do
    it "compte le e final de « entre » devant une consonne (ɑ̃-tʁə)" do
      stub_espeak("l'amour est mort entre tes bras" => "lamuʁɛmɔʁɑ̃tʁtebʁa")
      r = process("l'amour est mort entre tes bras")
      expect(r).to have_attributes(aligned: true, syllables: 8)
      expect(r.phones).to eq("la-muʁ-ɛ-mɔʁ-ɑ̃-tʁə-te-bʁa")
    end

    it "elide le e de « entre » devant une voyelle (comme un mot normal)" do
      stub_espeak("entre amis" => "ɑ̃tʁami")
      r = process("entre amis")
      expect(r.phones).to eq("ɑ̃tʁ-a-mi")
      expect(r.syllables).to eq(3)
    end

    it "ne compte pas le e de « entre » en fin de vers" do
      stub_espeak("dans mon ventre" => "dɑ̃mɔ̃vɑ̃tʁ")
      r = process("dans mon ventre")
      expect(r.phones).to eq("dɑ̃-mɔ̃-vɑ̃tʁ")
      expect(r.syllables).to eq(3)
    end

    it "garde le e muet des autres mots en -Cr- (arbre -> aʁbʁ)" do
      stub_espeak("un grand arbre" => "œ̃ɡʁɑ̃taʁbʁ")
      r = process("un grand arbre")
      expect(r.phones).to eq("œ̃ɡ-ʁɑ̃-taʁbʁ")
      expect(r.syllables).to eq(3)
    end
  end

  describe "alignement : m fusionné entre deux mots (nom, miroir)" do
    it "aligne « étrangères à ton nom, miroir » (espeak ne rend qu'un m)" do
      stub_espeak("étrangères à ton nom, miroir" => "etʁɑ̃ʒɛʁzatɔ̃nɔ̃miʁwaʁ")
      r = process("étrangères à ton nom, miroir")
      # le e de « étrangers(-ères) » est restauré devant le s muet (règle 1.5),
      # le s fait liaison en z devant « à » ; le m de « nom, miroir » est
      # rendu à « miroir » (un seul segment m)
      expect(r).to have_attributes(aligned: true, syllables: 9)
      expect(r.phones).to eq("e-tʁɑ̃-ʒɛ-ʁə-za-tɔ̃-nɔ̃-mi-ʁwaʁ")
    end
  end

  describe "h aspiré : hisser" do
    it "ne élide pas le e de « se » devant « hisser » (h aspiré, 3 syllabes)" do
      stub_espeak("mais se hisser plutôt vers le connu," =>
                  "mɛsəiseplytovɛʁləkɔny")
      r = process("mais se hisser plutôt vers le connu,")
      expect(r).to have_attributes(aligned: true, syllables: 10)
      expect(r.phones).to eq("mɛ-sə-i-se-ply-to-vɛʁ-lə-kɔ-ny")
    end

    it "h aspiré (hisser, hasard) bloque l'élision ; h muet (homme) élide" do
      expect(described_class.h_aspiré?("hisser")).to be true
      expect(described_class.h_aspiré?("hasard")).to be true
      expect(described_class.h_aspiré?("homme")).to be false
      # phonétiquement, tout h est muet : le mot commence par une voyelle
      expect(described_class.vowel_initial?("hasard")).to be true
      expect(described_class.elides_before?("hasard")).to be false # « le hasard » ne élide PAS
      expect(described_class.elides_before?("homme")).to be true
      stub_espeak("le hasard" => "ləazaʁ", "l'homme" => "lɔm", "le hisser" => "ləise",
                  "au hasard" => "oazaʁ")
      # h muet: elision (« l'homme » -> lɔm) ; h aspiré: e compté, voyelle pleine
      expect(process("l'homme")).to have_attributes(aligned: true, phones: "lɔm", syllables: 1)
      expect(process("le hasard")).to have_attributes(aligned: true, phones: "lə-a-zaʁ", syllables: 3)
      expect(process("le hisser")).to have_attributes(aligned: true, phones: "lə-i-se", syllables: 3)
      expect(process("au hasard")).to have_attributes(aligned: true, phones: "o-a-zaʁ", syllables: 3)
    end
  end

  describe "diérèse" do
    it "coupe un i-glide en deux syllabes avec dierese: true (violent -> vi-jɔ...)" do
      stub_espeak("un violent héros" => "œ̃vjolɑ̃eʁo")
      r = described_class.process_line("un violent héros",
                                       keep_line_end_e: false, dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 6)
      expect(r.phones).to eq("œ̃-vi-jo-lɑ̃-e-ʁo")
    end

    it "ne s'applique pas avec dierese: false" do
      stub_espeak("un violent héros" => "œ̃vjolɑ̃eʁo")
      r = process("un violent héros")
      expect(r.dierese).to eq(0)
      expect(r.phones).to eq("œ̃-vjo-lɑ̃-e-ʁo")
    end
  end

  describe "bibliothèque sans effets de bord" do
    it "se require sans toucher à ARGV (Scansion.main n'est appelé que as script)" do
      # si le CLI tournait au require, l OptionParser lèverait InvalidOption
      expect(defined?(Scansion.main)).to eq("method")
    end
  end

  describe "backend phonemizer_ffi" do
    BACKEND_LINES = [
      "Je chante, à voix basse, la belle table",
      "l'amour est mort entre tes bras",
      "aujourd'hui, l'héroïne & son ami — 31 ans !",
      "étrangères à ton nom, miroir"
    ].freeze

    # Les deux backends définissent le module Phonemizer : on les exécute
    # chacun dans un sous-processus et on compare leurs sorties brutes.
    def backend_output(which)
      req = which == :ffi ? File.expand_path("../lib/phonemizer_ffi.rb", __dir__) : "phonemizer"
      prog = <<~RUBY
        require #{req.inspect}
        ARGF.each_line do |l|
          l = l.chomp
          next if l.strip.empty?
          puts Phonemizer.phonemize(l, language: "fr").inspect
        end
      RUBY
      out, _err, st = Open3.capture3("ruby", "-e", prog, stdin_data: BACKEND_LINES.join("\n"))
      st.success? ? out : nil
    end

    it "donne exactement la même IPA que le gem phonemizer (drop-in)" do
      ffi = backend_output(:ffi)
      gem = backend_output(:gem)
      skip "ffi/libespeak-ng indisponible" if ffi.nil?
      skip "gem phonemizer indisponible" if gem.nil?
      expect(ffi).to eq(gem)
    end

    it "Scansion.espeak utilise le backend FFI quand disponible et nettoie l'IPA" do
      skip "ffi/libespeak-ng indisponible" if backend_output(:ffi).nil?
      expect(described_class.espeak("la belle table")).to eq("labɛltabl")
      expect(described_class.instance_variable_get(:@ffi_unavailable)).to be_nil
    end
  end
end
