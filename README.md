scansion
========

[![Gem Version](https://badge.fury.io/rb/scansion.svg)](https://badge.fury.io/rb/scansion)
[![Licence MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/scansion)

Phonétise des vers français avec [espeak-ng](https://github.com/espeak-ng/espeak-ng), puis accentue et compte les syllabes — en détectant automatiquement le régime du texte (vers classique rimé à mètres pairs, ou vers contemporain).

ATTENTION: PROJET EN DÉVELOPPEMENT - ne pas utiliser sans vérification

La liste complète des règles, avec exemples travaillés, est dans [`docs/scansion_rules.txt`](docs/scansion_rules.txt).


Prérequis
----------------------------------------------------------------

- Ruby 3.1+
- **espeak-ng** sur le `$PATH` (backend de dernier recours) :
  ```bash
  apt install espeak-ng     # Debian/Ubuntu
  brew install espeak-ng    # macOS
  ```
- Backend préféré (en processus, sans fork/exec par mot) : le gem [`phonemizer_ffi`](https://rubygems.org/gems/phonemizer_ffi), dépendance déclarée de `scansion` — il tire lui-même le gem `ffi` et a besoin de `libespeak-ng` (`apt install libespeak-ng-dev` ; sur macOS avec un espeak-ng Homebrew « keg-only », définir `PHONEMIZER_ESPEAK_LIB`).
- Replis, dans l'ordre : l'API du gem [`phonemizer`](https://rubygems.org/gems/phonemizer), le CLI `phonemize` qu'il fournit, puis espeak-ng directement.


Installation
----------------------------------------------------------------

Ajoutez au Gemfile :

```ruby
gem "scansion"
```

Ou installez depuis ce répertoire :

```bash
gem build scansion.gemspec && gem install ./scansion-3.0.0.gem
```


Utilisation
----------------------------------------------------------------

```
scansion [--classique|--contemporain] [-s|--syllables] [FILE|-]   # sans option : détection auto du régime
```

```console
$ echo "Au coin du feu, dans la langueur des rêveries!" | scansion
Au coin du feu, dans la langueur des rêveries!
  ⇒ o-kwɛ̃-dy-fø-dɑ̃-la-lɑ̃-gœʁ-de-ʁɛ-və-ʁi   (12 syll.)
```

Options :

- **par défaut (`:auto`)** — le régime est **détecté automatiquement** sur une 1re passe du texte (`Scansion.detect_mode`) : si au moins 70 % des vers (e muet compté) tombent sur un mètre pair [6, 8, 10, 12] **et** participent à des rimes strictes de fin de vers (`Classique.rhyme_key`) — la signature du vers classique rimé — tout le texte est traité en mode classique ; sinon en mode contemporain (comptes impairs, irrégularité de vers en vers). La décision est prise **une fois pour tout le poème/corpus**, jamais ligne à ligne.
- `--classique` — force le **mode classique** : tout e muet est compté devant une consonne (« la table ronde » -> 3 syllabes) ; un vers hors mètre pair [6, 8, 10, 12] est re-scanné vers ce mètre (diérèses, e des -re, pause_e alexandrine, ciblage mot à mot) ; priorité aux longueurs de vers classiques paires, à la césure et aux accents de groupe. Aucun tirage 2.6.
- `--contemporain` — force le **mode contemporain** : pas de diérèse, et l'e caduc n'est pas compté devant une consonne (« mes pères criaient dessous mes pieds » -> 8 syllabes) ; le « e fixe » des monosyllabes grammaticaux (le, de, me, te, se, que, ne, je, ce) reste toujours compté (« le passé » -> lə-pa-se). Tirage contextuel vers le mètre — si les vers voisins sont unanimes sur un mètre (6/8/10/12), un vers hors mètre y est tiré en comptant l'e caduc (« les gouttes du dernier envol » -> 8 dans un poème d'octosyllabes) — puis tirage accentuel 2.6 (`Scansion::Rythme`) selon la régularité des groupes rythmiques du vers. (Les deux options ne servent que dans les cas limites ; par défaut, `:auto` suffit.)
- `-s`, `--syllables` — n'afficher que le décompte des syllabes

Les arguments peuvent être des chemins de fichiers, `-` (stdin), ou du texte de vers en ligne.


Utilisation comme bibliothèque
----------------------------------------------------------------

`require "scansion"` est sans effet de bord (pas d'OptionParser sur l'ARGV de l'hôte) ; le CLI vit dans `Scansion.main` et ne tourne que si `lib/scansion.rb` est exécuté comme script :

```ruby
require "scansion"

Scansion::VERSION                      # => "3.0.0"
res = Scansion.process_line("la belle table ronde")                    # mode :auto -> classique (6, pair)
res.phones                             # => "la-bɛ-lə-ta-blə-ʁɔ̃d"
res.syllables                          # => 6
res = Scansion.process_line("la belle table ronde", mode: :contemporain)
res.phones                             # => "la-bɛl-tabl-ʁɔ̃d"
res.syllables                          # => 4
res.aligned                            # => true

Scansion.process_lines(lines)                    # mode :auto (détection automatique)
Scansion.process_lines(lines, mode: :classique)   # ou :contemporain pour forcer
```

Accents de phrase et accents secondaires
----------------------------------------

`require "scansion/accents"` ajoute `Scansion::Accents`, qui calcule deux
couches d'accentuation sur une scansion (règles de Delattre) :

- **accent de phrase** (ˈ) : un par groupe rythmique (syntagme), posé sur la
  dernière syllabe accentuable du groupe — l'accent du dernier groupe est la rime ;
- **accent secondaire de mot** (ˌ) : un par mot plein, sur sa propre dernière
  syllabe accentuable.

Une syllabe au noyau schwa (e caduc restauré) ne porte jamais l'accent.
L'alignement mot -> syllabe consomme `Scansion::Result#word_spans` (calculé
par le gem lui-même, donc sans dérive).

```ruby
require "scansion/accents"

a = Scansion::Accents.analyze_line("mes pères criaient dessous mes pieds", mode: :contemporain)
a.render        # => "me-ˈpɛʁ |-kʁi-ˈɛ |-də-su-me-ˈpje   (8 syll.)"
a.accents       # => [1, 3, 7]  (accents de phrase : pères | criaient | pieds)
a.word_accents  # => [1, 7]     (accents secondaires des mots pères, pieds)

Scansion::Accents.analyze_lines(File.readlines("corpus.txt", chomp: true)) # :auto ; mode: :contemporain force le tirage 2.6
```

Le gem produit aussi les **caractéristiques rythmiques** du vers
(`Scansion::Rythme` : signature de groupes, score de régularité) et applique
le **tirage accentuel 2.6** en vers contemporain — la régularité rythmique y
est une caractéristique mesurable, pas un jugement. La **quantification**
de ces caractéristiques — modéliser des aspects du poème à partir des outils
analytiques de scansion — vit dans le gem [**claudel**](https://rubygems.org/gems/claudel),
construit au-dessus de scansion. L'interprétation de lecture (règle dure ou
personnelle) reste côté scansion.


Développement
----------------------------------------------------------------

```bash
bundle install
bundle exec rspec     # ou : rake
```

La couche espeak-ng (`Scansion.espeak`) est bouchonnée dans les specs : la suite est déterministe et tourne sans espeak-ng.

### Affinage guidé par les lectures corrigées (golden)

```bash
# 1. générer le rapport auto et le garder tel quel
ruby -I lib ../gen_accent_report.rb contemporain /tmp/auto.txt samples/*.txt   # (depuis ruby/)
# 2. corriger à la main une copie (marqueurs == ou | pour une frontière de groupe ajoutée ;
#    les accents ˈ/ˌ DÉRIVENT des groupes : ne pas les corriger à la main, l'outil les
#    recalcule — le diff et les golden ignorent les différences de ˈ/ˌ seules)
# 3. diff auto vs manuel, groupé par catégorie (compte / frontières / phones)
ruby -I lib dev/diff_report.rb /tmp/auto.txt /tmp/manuel.txt
# 4. générer les golden specs des poèmes corrigés (espeak bouchonné, déterministe)
ruby -I lib dev/gen_golden.rb /tmp/auto.txt /tmp/manuel.txt :contemporain
# 5. la file d'attente d'affinage : les golden rouges
rspec --tag golden          # la suite normale les exclut (--tag ~golden dans .rspec)
```


Structure
----------------------------------------------------------------

```
├── bin/scansion                  exécutable (scansion [options] [FILE|-])
├── lib/scansion.rb               point d'entrée du gem (require "scansion")
├── lib/scansion/syllabification.rb  cœur : alignement + e muet + compte des syllabes
├── lib/scansion/classique.rb     Scansion::Classique — détection du régime, re-scan classique
├── lib/scansion/rythme.rb        Scansion::Rythme — signature/score + tirage accentuel 2.6
├── lib/scansion/accents.rb       Scansion::Accents — accents de phrase (ˈ) et de mot (ˌ)
├── lib/scansion/cli.rb           Scansion.main (ligne de commande)
├── lib/scansion/version.rb       Scansion::VERSION
├── spec/                         suite RSpec (syllabification_spec.rb, rythme_spec.rb, accents_spec.rb, cli_spec.rb)
└── docs/scansion_rules.txt       règles de scansion avec exemples travaillés
```

`require "scansion"` charge tout le gem sans effet de bord ; on peut aussi ne
charger que le cœur (`require "scansion/syllabification"`, sans charger
`phonemizer_ffi` au require) ou seulement les accents
(`require "scansion/accents"`).
