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

  def process(line)
    described_class.process_line(line)
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

  describe "exceptions -Cr- (astre, entendre, entre, ventre)" do
    it "compte le e final de « entendre » devant une consonne (alexandrine à 12)" do
      stub_espeak("Pour t'entendre sonner, je monte sur ma tour," =>
                  "puʁtɑ̃tɑ̃dʁsɔneʒəmɔ̃tsyʁmatuʁ")
      r = process("Pour t'entendre sonner, je monte sur ma tour,")
      expect(r).to have_attributes(aligned: true, syllables: 12)
      expect(r.phones).to eq("puʁ-tɑ̃-tɑ̃-dʁə-sɔ-ne-ʒə-mɔ̃-tə-syʁ-ma-tuʁ")
    end

    it "ne compte pas le e de « entendre » en fin de vers" do
      stub_espeak("entendre" => "ɑ̃tɑ̃dʁ")
      r = process("entendre")
      expect(r).to have_attributes(aligned: true, phones: "ɑ̃-tɑ̃dʁ", syllables: 2)
    end

    it "élide le e de « entendre » devant une voyelle" do
      stub_espeak("entendre ami" => "ɑ̃tɑ̃dʁami")
      r = process("entendre ami")
      expect(r).to have_attributes(aligned: true, phones: "ɑ̃-tɑ̃dʁ-a-mi", syllables: 4)
    end

    it "compte le e final de « astre » devant une consonne (as-tʁə, 2 syllabes)" do
      stub_espeak("L'astre n'est encor qu'étincelle ;" => "lastʁnɛtɑ̃kɔʁketɛ̃sɛl")
      r = process("L'astre n'est encor qu'étincelle ;")
      expect(r).to have_attributes(aligned: true, syllables: 8)
      expect(r.phones).to eq("la-stʁə-nɛt-ɑ̃-kɔʁ-ke-tɛ̃-sɛl")
    end

    it "ne compte pas le e de « astre » en fin de vers" do
      stub_espeak("l'astre" => "lastʁ")
      r = process("l'astre")
      expect(r).to have_attributes(aligned: true, phones: "lastʁ", syllables: 1)
    end

    it "élide le e de « astre » devant une voyelle (comme un mot normal)" do
      stub_espeak("l'astre ami" => "lastʁami")
      r = process("l'astre ami")
      expect(r).to have_attributes(aligned: true, phones: "lastʁ-a-mi", syllables: 3)
    end

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

    it "compte le e final de « être » (peut-être) devant une consonne (pø-ɛ-tʁə)" do
      stub_espeak("Ô lâche ! Et peut-être demain," => "olaʃepøɛtʁdəmɛ̃")
      r = process("Ô lâche ! Et peut-être demain,")
      expect(r).to have_attributes(aligned: true, syllables: 8)
      expect(r.phones).to eq("o-laʃ-e-pø-ɛ-tʁə-də-mɛ̃")
    end

    it "ne compte pas le e de « être » en fin de vers (peut-être -> pø-ɛtʁ)" do
      stub_espeak("peut-être" => "pøɛtʁ")
      r = process("peut-être")
      expect(r).to have_attributes(aligned: true, phones: "pø-ɛtʁ", syllables: 2)
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
      r = described_class.process_line("un violent héros", dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 6)
      expect(r.phones).to eq("œ̃-vi-jo-lɑ̃-e-ʁo")
    end

    it "ne s'applique pas avec dierese: false" do
      stub_espeak("un violent héros" => "œ̃vjolɑ̃eʁo")
      r = process("un violent héros")
      expect(r.dierese).to eq(0)
      expect(r.phones).to eq("œ̃-vjo-lɑ̃-e-ʁo")
    end

    it "coupe un u-glide en deux syllabes avec dierese: true (nuées -> nu-ées)" do
      stub_espeak("Vous surgissez ! voici qu'à travers les nuées" =>
                  "vusyʁʒisevwasikatʁavɛʁlenye")
      r = described_class.process_line("Vous surgissez ! voici qu'à travers les nuées",
                                       dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 12)
      expect(r.phones).to eq("vu-syʁ-ʒi-se-vwa-si-ka-tʁa-vɛʁ-le-nu-e")
    end

    it "coupe le u de « exténuées » (ex-té-nu-ée, alexandrine à 12)" do
      stub_espeak("Liberté, qu'invoquaient nos voix exténuées," =>
                  "libɛʁtekɛ̃vokɛnovwaɛkstenye")
      r = described_class.process_line("Liberté, qu'invoquaient nos voix exténuées,",
                                       dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 12)
      expect(r.phones).to eq("li-bɛʁ-te-kɛ̃-vo-kɛ-no-vwa-ɛk-ste-nu-e")
    end

    it "garde « nuées » à 1 syllabe sans diérèse (contemporain)" do
      stub_espeak("Vous surgissez ! voici qu'à travers les nuées" =>
                  "vusyʁʒisevwasikatʁavɛʁlenye")
      r = process("Vous surgissez ! voici qu'à travers les nuées")
      expect(r).to have_attributes(dierese: 0, syllables: 11)
      expect(r.phones).to eq("vu-syʁ-ʒi-se-vwa-si-ka-tʁa-vɛʁ-le-nye")
    end

    it "ne scinde pas le « ue » inaccentué même avec dierese: true (ruelle -> ʁyɛl)" do
      stub_espeak("une ruelle" => "ynʁyɛl")
      r = described_class.process_line("une ruelle", dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 0, syllables: 3)
      expect(r.phones).to eq("y-nə-ʁyɛl")
    end

    it "coupe le « ua » final en deux syllabes avec dierese: true (ruas -> ru-as)" do
      stub_espeak("Toi qui, le front levé, te ruas dans le crime," =>
                  "twakiləfʁɔ̃ləvetəʁyadɑ̃ləkʁim")
      r = described_class.process_line("Toi qui, le front levé, te ruas dans le crime,",
                                       dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 12)
      expect(r.phones).to eq("twa-ki-lə-fʁɔ̃-lə-ve-tə-ʁu-a-dɑ̃-lə-kʁim")
    end

    it "garde « ruas » à 1 syllabe sans diérèse (contemporain)" do
      stub_espeak("Toi qui, le front levé, te ruas dans le crime," =>
                  "twakiləfʁɔ̃ləvetəʁyadɑ̃ləkʁim")
      r = process("Toi qui, le front levé, te ruas dans le crime,")
      expect(r).to have_attributes(dierese: 0, syllables: 11)
      expect(r.phones).to eq("twa-ki-lə-fʁɔ̃-lə-ve-tə-ʁya-dɑ̃-lə-kʁim")
    end

    it "ne scinde pas le « ua » interne (nuage -> nyaʒ, 1 syllabe) même avec dierese: true" do
      stub_espeak("un nuage" => "œ̃nyaʒ")
      r = described_class.process_line("un nuage", dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 0, syllables: 2)
      expect(r.phones).to eq("œ̃-nyaʒ")
    end

    it "coupe le « ou » devant « a » avec dierese: true (couardise -> cou-ar-dise)" do
      stub_espeak("Malgré ta couardise, il faut combattre, allons !" =>
                  "malgʁetakwaʁdizilfokɔ̃batʁalɔ̃")
      r = described_class.process_line("Malgré ta couardise, il faut combattre, allons !",
                                       dierese: true)
      expect(r).to have_attributes(aligned: true, dierese: 1, syllables: 12)
      expect(r.phones).to eq("mal-gʁe-ta-ku-aʁ-diz-il-fo-kɔ̃-batʁ-a-lɔ̃")
    end

    it "garde « couardise » à 2 syllabes sans diérèse (contemporain)" do
      stub_espeak("Malgré ta couardise, il faut combattre, allons !" =>
                  "malgʁetakwaʁdizilfokɔ̃batʁalɔ̃")
      r = process("Malgré ta couardise, il faut combattre, allons !")
      expect(r).to have_attributes(dierese: 0, syllables: 11)
      expect(r.phones).to eq("mal-gʁe-ta-kwaʁ-diz-il-fo-kɔ̃-batʁ-a-lɔ̃")
    end
  end

describe "CR_E_PRONOUNCED étendu (guerre, maître, œuvre, battre, entendre, croître, hydre, tonnerre + pluriels)" do
it "astre compte 2 syllabes (as-tre) : 8 syllabes au lieu de 7" do
  stub_espeak("L'astre n'est encor qu'étincelle ;" => "lastʁnɛtɑ̃kɔʁketɛ̃sɛl")
  r = process("L'astre n'est encor qu'étincelle ;")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("la-stʁə-nɛt-ɑ̃-kɔʁ-ke-tɛ̃-sɛl")
end
it "pluriel en -s : astres -> za-stʁə (8 syllabes)" do
  stub_espeak("Mener tous les astres la nuit ;" => "mənetulezastʁlanyi")
  r = process("Mener tous les astres la nuit ;")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("mə-ne-tu-le-za-stʁə-la-nyi")
end
it "pluriel en -s : hydres -> zi-dʁə (12 syllabes)" do
  stub_espeak("Ne voit-il pas ramper les hydres sur leurs ventres ?" => "nəvwailpaʁɑ̃pelezidʁsyʁlœʁvɑ̃tʁ")
  r = process("Ne voit-il pas ramper les hydres sur leurs ventres ?")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("nə-vwa-il-pa-ʁɑ̃-pe-le-zi-dʁə-syʁ-lœʁ-vɑ̃tʁ")
end
it "pluriel en -s : tonnerres -> tɔ-nɛ-ʁə (8 syllabes)" do
  stub_espeak("Et les tonnerres dans la nue," => "eletɔnɛʁdɑ̃lany")
  r = process("Et les tonnerres dans la nue,")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("e-le-tɔ-nɛ-ʁə-dɑ̃-la-ny")
end
it "guerre -> gɛ-ʁə (12 syllabes)" do
  stub_espeak("La guerre s'est dressée, et j'ai vu, moi rêveur," => "lagɛʁsɛdʁɛseeʒevymwaʁɛvœʁ")
  r = process("La guerre s'est dressée, et j'ai vu, moi rêveur,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("la-gɛ-ʁə-sɛ-dʁɛ-se-e-ʒe-vy-mwa-ʁɛ-vœʁ")
end
it "maître -> mɛ-tʁə (12 syllabes)" do
  stub_espeak("Comme un maître qui rentre en sa maison déserte," => "kɔmœ̃mɛtʁkiʁɑ̃tʁɑ̃samɛzɔ̃dezɛʁt")
  r = process("Comme un maître qui rentre en sa maison déserte,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("kɔm-œ̃-mɛ-tʁə-ki-ʁɑ̃tʁ-ɑ̃-sa-mɛ-zɔ̃-de-zɛʁt")
end
it "œuvre -> nœ-vʁə (12 syllabes)" do
  stub_espeak("Parce qu'il ne fait pas son œuvre tout de suite," => "paʁskilnəfɛpasɔ̃nœvʁtudəsyit")
  r = process("Parce qu'il ne fait pas son œuvre tout de suite,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("paʁ-sə-kil-nə-fɛ-pa-sɔ̃-nœ-vʁə-tu-də-syit")
end
it "entendre -> tɑ̃-dʁə (12 syllabes)" do
  stub_espeak("Pour t'entendre sonner, je monte sur ma tour," => "puʁtɑ̃tɑ̃dʁsɔneʒəmɔ̃tsyʁmatuʁ")
  r = process("Pour t'entendre sonner, je monte sur ma tour,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("puʁ-tɑ̃-tɑ̃-dʁə-sɔ-ne-ʒə-mɔ̃-tə-syʁ-ma-tuʁ")
end
it "combattre -> kɔ̃-batʁ (12 syllabes avec la diérèse de couardise)" do
  stub_espeak("Malgré ta couardise, il faut combattre, allons !" => "malgʁetakwaʁdizilfokɔ̃batʁalɔ̃")
  r = described_class.process_line("Malgré ta couardise, il faut combattre, allons !", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("mal-gʁe-ta-ku-aʁ-diz-il-fo-kɔ̃-batʁ-a-lɔ̃")
end
it "diérèse u+eu : majestueux -> ma-jes-tu-eux (6 syllabes)" do
  stub_espeak("Majestueux amour !" => "maʒɛstyøzamuʁ")
  r = described_class.process_line("Majestueux amour !", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 6)
  expect(r.phones).to eq("ma-ʒɛs-tu-ø-za-muʁ")
end
it "sans diérèse : ma-ʒɛs-tyø (5 syllabes)" do
  stub_espeak("Majestueux amour !" => "maʒɛstyøzamuʁ")
  r = process("Majestueux amour !")
  expect(r).to have_attributes(aligned: true, syllables: 5)
  expect(r.phones).to eq("ma-ʒɛst-yø-za-muʁ")
end
it "le n de « quand » est l'initiale de « nous » (kɑ̃-nu) et « ombre » garde son e (l'om-bʁə) : 12 syllabes" do
  stub_espeak("Quand nous marchons, courbés, dans l'ombre du martyre," => "kɑ̃numaʁʃɔ̃kuʁbedɑ̃lɔ̃bʁdymaʁtiʁ")
  r = process("Quand nous marchons, courbés, dans l'ombre du martyre,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("kɑ̃-nu-maʁ-ʃɔ̃-kuʁ-be-dɑ̃-lɔ̃-bʁə-dy-maʁ-tiʁ")
end
it "idem : aligné à 12 syllabes" do
  stub_espeak("Mais, quand nous étendons les bras dans cette brume," => "mɛkɑ̃nuzetɑ̃dɔ̃lebʁadɑ̃sɛtbʁym")
  r = process("Mais, quand nous étendons les bras dans cette brume,")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("mɛ-kɑ̃-nu-ze-tɑ̃-dɔ̃-le-bʁa-dɑ̃-sɛ-tə-bʁym")
end
it "« nous nous » : le n initial de « nous » n'est PAS légué (régression)" do
  stub_espeak("Nous entendons quelqu'un derrière nous nous dire :" => "nuzɑ̃tɑ̃dɔ̃kɛlkœ̃dɛʁjɛʁnunudiʁ")
  r = process("Nous entendons quelqu'un derrière nous nous dire :")
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("nu-zɑ̃-tɑ̃-dɔ̃-kɛlk-œ̃-dɛ-ʁjɛ-ʁə-nu-nu-diʁ")
end
it "suite nasale « ɑ̃i » scindée à la frontière : comment-il = 3 syllabes (8 au total)" do
  stub_espeak("Comment il fait tout ce qu'il fait." => "kɔmɑ̃ilfɛtusəkilfɛ")
  r = process("Comment il fait tout ce qu'il fait.")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("kɔ-mɑ̃-il-fɛ-tu-sə-kil-fɛ")
end
it "idem (8 syllabes)" do
  stub_espeak("Je sais comment il a fait l'homme," => "ʒəsɛkɔmɑ̃ilafɛlɔm")
  r = process("Je sais comment il a fait l'homme,")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("ʒə-sɛ-kɔ-mɑ̃-il-a-fɛ-lɔm")
end
it "hiatus étendue-où : le y de « dyu » est un noyau /y/ compté (8 syllabes)" do
  stub_espeak("Et l'étendue où l'esprit passe ?" => "eletɑ̃dyulɛspʁipas")
  r = process("Et l'étendue où l'esprit passe ?")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("e-le-tɑ̃dy-u-lɛ-spʁi-pas")
end
it "le « j » de appuyer (a-p-yi-j-e) est consommé et « ombre » garde son e : 8 syllabes" do
  stub_espeak("Appuyer dans l'ombre du vide" => "apyijedɑ̃lɔ̃bʁdyvid")
  r = process("Appuyer dans l'ombre du vide")
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("ap-yi-je-dɑ̃-lɔ̃-bʁə-dy-vid")
end
it "« ombre » garde son e prononcé devant une consonne (ombres du soir -> zɔ̃-bʁə)" do
  stub_espeak("les ombres du soir" => "lezɔ̃bʁdyswaʁ")
  r = process("les ombres du soir")
  expect(r).to have_attributes(aligned: true, syllables: 5)
  expect(r.phones).to eq("le-zɔ̃-bʁə-dy-swaʁ")
end
it "« l'ombre » s'élide devant une voyelle (ombre = 1 syllabe)" do
  stub_espeak("Dans l'ombre où sont les morts !" => "dɑ̃lɔ̃bʁusɔ̃lemɔʁ")
  r = process("Dans l'ombre où sont les morts !")
  expect(r).to have_attributes(aligned: true, syllables: 6)
  expect(r.phones).to eq("dɑ̃-lɔ̃bʁ-u-sɔ̃-le-mɔʁ")
end
it "« ombres » en fin de vers : e non compté (pluriel CR_E_PRONOUNCED)" do
  stub_espeak("suivie d'ombres" => "syividɔ̃bʁ")
  r = process("suivie d'ombres")
  expect(r).to have_attributes(aligned: true, syllables: 3)
  expect(r.phones).to eq("syi-vi-dɔ̃bʁ")
end
  end

describe "contexte classique : bande octosyllabe 6-9" do
  it "accepte une fenêtre majoritairement en 6-9" do
    expect(described_class.classical_context?([8, 8, 7, 8, 8], 2)).to be true
    expect(described_class.classical_context?([6, 7, 8, 9, 6], 2)).to be true
  end

  it "rejette une fenêtre hors bandes (contemporain)" do
    expect(described_class.classical_context?([5, 4, 3, 2, 4], 2)).to be false
  end
end

describe "hiatus entre deux mots (count_syllables avec barrières)" do
  it "ne traite pas le y d'un hiatus inter-mot comme un glide (dy-u = 2)" do
    expect(described_class.count_syllables(%w[d y u], [[2, "étendue", false]])).to eq(2)
  end

  it "garde la règle du glide à l'intérieur d'un mot (f-yi-jɛ = 2)" do
    expect(described_class.count_syllables(%w[f y i j ɛ])).to eq(2)
    expect(described_class.count_syllables(%w[d y u])).to eq(1)
  end
end

describe "e final des mots en -Cre en contexte classique (cluster_re_pronounced?)" do
it "contexte classique : « sombre » compte son e final (sɔ̃-bʁə, 8 syllabes)" do
  stub_espeak("O sombre mer, que me veux-tu ?" => "osɔ̃bʁmɛʁkəməvøty")
  r = described_class.process_line("O sombre mer, que me veux-tu ?", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 8)
  expect(r.phones).to eq("o-sɔ̃-bʁə-mɛʁ-kə-mə-vø-ty")
end
it "mode contemporain : « sombre » reste 1 syllabe (sɔ̃bʁ, 7 syllabes)" do
  stub_espeak("O sombre mer, que me veux-tu ?" => "osɔ̃bʁmɛʁkəməvøty")
  r = process("O sombre mer, que me veux-tu ?")
  expect(r).to have_attributes(aligned: true, syllables: 7)
  expect(r.phones).to eq("o-sɔ̃bʁ-mɛʁ-kə-mə-vø-ty")
end
it "contexte classique : « notre » -> no-tʁə (6 syllabes)" do
  stub_espeak("Qui vole à Notre-Dame." => "kivɔlanotʁdam")
  r = described_class.process_line("Qui vole à Notre-Dame.", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 6)
  expect(r.phones).to eq("ki-vɔl-a-no-tʁə-dam")
end
it "mode contemporain : « notre » -> notʁ (5 syllabes)" do
  stub_espeak("Qui vole à Notre-Dame." => "kivɔlanotʁdam")
  r = process("Qui vole à Notre-Dame.")
  expect(r).to have_attributes(aligned: true, syllables: 5)
  expect(r.phones).to eq("ki-vɔl-a-notʁ-dam")
end
it "« ivre, » devant une pause garde son e compté en classique (i-vʁə, 12 syllabes)" do
  stub_espeak("Le soldat, gai, féroce, ivre, complice obscur," => "ləsɔldagefeʁɔsivʁkɔ̃plisɔbskyʁ")
  r = described_class.process_line("Le soldat, gai, féroce, ivre, complice obscur,", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 12)
  expect(r.phones).to eq("lə-sɔl-da-ge-fe-ʁɔs-i-vʁə-kɔ̃-plis-ɔb-skyʁ")
end
it "mode contemporain : « ivre, » -> ivʁ devant la virgule (11 syllabes)" do
  stub_espeak("Le soldat, gai, féroce, ivre, complice obscur," => "ləsɔldagefeʁɔsivʁkɔ̃plisɔbskyʁ")
  r = process("Le soldat, gai, féroce, ivre, complice obscur,")
  expect(r).to have_attributes(aligned: true, syllables: 11)
  expect(r.phones).to eq("lə-sɔl-da-ge-fe-ʁɔs-ivʁ-kɔ̃-plis-ɔb-skyʁ")
end
it "CR_E_PRONOUNCED devant une pause : le e restauré de « astre » n'est pas élagué (as-tʁə)" do
  stub_espeak("l'astre, brillant" => "lastʁbʁijɑ̃")
  r = process("l'astre, brillant")
  expect(r).to have_attributes(aligned: true, syllables: 4)
  expect(r.phones).to eq("la-stʁə-bʁi-jɑ̃")
end
it "pluriel en -s d'un mot en -vre : « pauvres » -> po-vʁə (6 syllabes)" do
  stub_espeak("Pauvres petits oiseaux !" => "povʁpətizwazo")
  r = described_class.process_line("Pauvres petits oiseaux !", dierese: true)
  expect(r).to have_attributes(aligned: true, syllables: 6)
  expect(r.phones).to eq("po-vʁə-pə-tiz-wa-zo")
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
      req = which == :ffi ? "phonemizer_ffi" : "phonemizer"
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
