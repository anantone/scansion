# Journal des modifications

## 0.1.0 - 2026-11-21

- scansion.rb devient un vrai gem : `lib/scansion.rb` (bibliothèque sans effet de bord au require) avec `Scansion::VERSION`, exécutable `bin/scansion` enregistré via `spec.executables`, suite RSpec sous `spec/`, et liste complète des règles dans `docs/scansion_rules.txt`
- `lib/phonemizer_ffi.rb` est embarqué à côté pour que le backend FFI en processus se résolve via `require_relative` à l'intérieur du gem
- Ajout du gemspec, du Gemfile, du Rakefile, du README, de la LICENSE
- Documentation et commentaires en français
