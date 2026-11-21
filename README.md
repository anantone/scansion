scansion
========

[![Licence MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Phonétise des vers français avec [espeak-ng](https://github.com/espeak-ng/espeak-ng) et restaure le e muet (*e caduc*) selon les règles de la scansion classique, puis marque les frontières de syllabes et compte les syllabes (alexandrins, etc.).

La liste complète des règles, avec exemples travaillés, est dans [`docs/scansion_rules.txt`](docs/scansion_rules.txt).


Prérequis
----------------------------------------------------------------

- Ruby 3.1+
- **espeak-ng** sur le `$PATH` (backend de dernier recours) :
  ```bash
  apt install espeak-ng     # Debian/Ubuntu
  brew install espeak-ng    # macOS
  ```
- Backend préféré (optionnel, en processus, sans fork/exec par mot) : le gem `ffi` plus `libespeak-ng` — `gem install ffi && apt install libespeak-ng-dev` (sur macOS avec un espeak-ng Homebrew « keg-only », définir `PHONEMIZER_ESPEAK_LIB`).
- Replis, dans l'ordre : l'API du gem [`phonemizer`](https://rubygems.org/gems/phonemizer), le CLI `phonemize` qu'il fournit, puis espeak-ng directement.


Installation
----------------------------------------------------------------

Ajoutez au Gemfile :

```ruby
gem "scansion"
```

Ou installez depuis ce répertoire :

```bash
gem build scansion.gemspec && gem install ./scansion-0.1.0.gem
```


Utilisation
----------------------------------------------------------------

```
scansion [--keep-line-end-e] [--no-dierese] [-s|--syllables] [FILE|-]
```

```console
$ echo "Au coin du feu, dans la langueur des rêveries!" | scansion
Au coin du feu, dans la langueur des rêveries!
  ⇒ o-kwɛ̃-dy-fø-dɑ̃-la-lɑ̃-gœʁ-de-ʁɛ-və-ʁi   (12 syll.)
```

Options :

- `--keep-line-end-e` — compter le e muet en fin de vers (p. ex. rimes féminines)
- `--no-dierese` — désactiver la diérèse contextuelle (corpus contemporain)
- `-s`, `--syllables` — n'afficher que le décompte des syllabes

Les arguments peuvent être des chemins de fichiers, `-` (stdin), ou du texte de vers en ligne.


Utilisation comme bibliothèque
----------------------------------------------------------------

`require "scansion"` est sans effet de bord (pas d'OptionParser sur l'ARGV de l'hôte) ; le CLI vit dans `Scansion.main` et ne tourne que si `lib/scansion.rb` est exécuté comme script :

```ruby
require "scansion"

Scansion::VERSION                      # => "0.1.0"
res = Scansion.process_line("la belle table ronde")
res.phones                             # => "la-bɛl-ta-blə-ʁɔ̃d"
res.syllables                          # => 4
res.aligned                            # => true

Scansion.process_lines(lines, keep_line_end_e: false, dierese: :auto)
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
├── bin/scansion              exécutable (scansion [options] [FILE|-])
├── lib/scansion.rb           bibliothèque + point d'entrée CLI Scansion.main
├── lib/scansion/version.rb   Scansion::VERSION
├── lib/phonemizer_ffi.rb     backend FFI optionnel en processus pour espeak-ng
├── spec/                     suite RSpec
└── docs/scansion_rules.txt   règles de scansion avec exemples travaillés
```
