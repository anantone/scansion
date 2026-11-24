scansion
========

[![Gem Version](https://badge.fury.io/rb/scansion.svg)](https://badge.fury.io/rb/scansion)
[![Licence MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Phonétise des vers français avec [espeak-ng](https://github.com/espeak-ng/espeak-ng), puis marque les frontières de syllabes et compte les syllabes.

Depuis la 1.0.0, le gem embarque aussi `Scansion::Accents` (`require "scansion/accents"`) : il calcule les **accents de phrase** (ˈ, un par groupe rythmique) et les **accents secondaires de mot** (ˌ) sur chaque vers scansionné — voir la section « Accents de phrase et accents secondaires » ci-dessous.

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
gem build scansion.gemspec && gem install ./scansion-1.0.0.gem
```


Utilisation
----------------------------------------------------------------

```
scansion [--no-dierese] [-s|--syllables] [FILE|-]
```

```console
$ echo "Au coin du feu, dans la langueur des rêveries!" | scansion
Au coin du feu, dans la langueur des rêveries!
  ⇒ o-kwɛ̃-dy-fø-dɑ̃-la-lɑ̃-gœʁ-de-ʁɛ-və-ʁi   (12 syll.)
```

Options :

- `--no-dierese` — mode contemporain : pas de diérèse contextuelle, et l'e caduc n'est pas compté devant une consonne (« mes pères criaient dessous mes pieds » -> 8 syllabes) ; le « e fixe » des monosyllabes grammaticaux (le, de, me, te, se, que, ne, je, ce) reste toujours compté (« le passé » -> lə-pa-se). Exception : tirage contextuel — si les vers voisins sont unanimes sur un mètre (6/8/10/12), un vers hors mètre y est tiré en comptant l'e caduc (« les gouttes du dernier envol » -> 8 dans un poème d'octosyllabes). En contexte classique (`:auto`), tout e muet reste compté (« la table ronde » -> 3 syllabes)
- `-s`, `--syllables` — n'afficher que le décompte des syllabes

Les arguments peuvent être des chemins de fichiers, `-` (stdin), ou du texte de vers en ligne.


Utilisation comme bibliothèque
----------------------------------------------------------------

`require "scansion"` est sans effet de bord (pas d'OptionParser sur l'ARGV de l'hôte) ; le CLI vit dans `Scansion.main` et ne tourne que si `lib/scansion.rb` est exécuté comme script :

```ruby
require "scansion"

Scansion::VERSION                      # => "1.0.0"
res = Scansion.process_line("la belle table ronde")
res.phones                             # => "la-bɛl-ta-blə-ʁɔ̃d"
res.syllables                          # => 4
res.aligned                            # => true

Scansion.process_lines(lines, dierese: :auto)
```

Accents de phrase et accents secondaires (depuis la 1.0.0)
----------------------------------------------------------------

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

a = Scansion::Accents.analyze_line("mes pères criaient dessous mes pieds")
a.render        # => "me-ˌpɛʁ-kʁi-ˈɛ |-də-su-me-ˈpje   (8 syll.)"
a.accents       # => [3, 7]   (indices 0-based : syllabes 4 et 8, accents de phrase)
a.word_accents  # => [1, 3, 7] (accents secondaires des mots pères, criaient, pieds)

Scansion::Accents.analyze_lines(File.readlines("corpus.txt", chomp: true), dierese: :auto)
```


Développement
----------------------------------------------------------------

```bash
bundle install
bundle exec rspec     # ou : rake
```

La couche espeak-ng (`Scansion.espeak`) est bouchonnée dans les specs : la suite est déterministe et tourne sans espeak-ng.


Structure
----------------------------------------------------------------

```
├── bin/scansion                  exécutable (scansion [options] [FILE|-])
├── lib/scansion.rb               point d'entrée du gem (require "scansion")
├── lib/scansion/syllabification.rb  cœur : alignement + e muet + compte des syllabes
├── lib/scansion/accents.rb       Scansion::Accents — accents de phrase (ˈ) et de mot (ˌ)
├── lib/scansion/cli.rb           Scansion.main (ligne de commande)
├── lib/scansion/version.rb       Scansion::VERSION
├── spec/                         suite RSpec (syllabification_spec.rb, accents_spec.rb, cli_spec.rb)
└── docs/scansion_rules.txt       règles de scansion avec exemples travaillés
```

`require "scansion"` charge tout le gem sans effet de bord ; on peut aussi ne
charger que le cœur (`require "scansion/syllabification"`, sans charger
`phonemizer_ffi` au require) ou seulement les accents
(`require "scansion/accents"`).
