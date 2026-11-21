# Journal des modifications

## 0.1.1 - 2026-11-21

- `CR_E_PRONOUNCED` étendu (guerre, battre, croître, hydre, maître, moindre, œuvre, ombre, peindre, tonnerre) avec pluriels en -s/-x acceptés via le nouveau prédicat `cr_e_pronounced?` : « astres », « hydres », « tonnerres », « ombres » gardent leur e final prononcé (règle 1.5d) — « Appuyer dans l’ombre du vide » -> 8 syllabes, « Quand nous marchons… dans l’ombre du martyre, » -> 12 syllabes, et « l’ombre où… » s’élide normalement (1 syllabe)
- diérèse du « u » étendue au « eu » (majestueux -> ma-jes-tu-eux) et bande de contexte classique élargie : 10-13 ∪ 6-9 (`classical_context?`)
- alignement : une nasale en coda peut être léguée au mot suivant (« quand nous » -> kɑ̃-nu) sans jamais céder l'initiale d'un mot (« nous nous » -> nu-nu)
- alignement : les runs nasale/glide chevauchant une frontière de mot sont scindés quand le mot suivant commence par une voyelle (« comment il » -> kɔ-mɑ̃-il, « étendue où » -> …-dy-u)
- `count_syllables` reçoit les barrières de mots : le « y » d'un hiatus inter-mot est un noyau /y/ compté
- alignement : le « j » d'un e après y prononcé est consommé avec le e (« appuyer » -> ap-yi-je, la ligne ne tombe plus en repli)
- 25 nouveaux exemples RSpec (91 au total, 0 échec) ; `docs/scansion_rules.txt` mis à jour (règles 1.4c, 1.5d, 2.1h-2.1l)

## 0.1.0 - 2026-11-21

- scansion.rb devient un vrai gem : `lib/scansion.rb` (bibliothèque sans effet de bord au require) avec `Scansion::VERSION`, exécutable `bin/scansion` enregistré via `spec.executables`, suite RSpec sous `spec/`, et liste complète des règles dans `docs/scansion_rules.txt`
- `lib/phonemizer_ffi.rb` est embarqué à côté pour que le backend FFI en processus se résolve via `require_relative` à l'intérieur du gem
- Ajout du gemspec, du Gemfile, du Rakefile, du README, de la LICENSE
- Documentation et commentaires en français
