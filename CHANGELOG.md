# Journal des modifications

## 0.1.3 - 2026-11-21

- `lib/phonemizer_ffi.rb` n'est plus embarqué : le backend FFI est le gem [`phonemizer_ffi`](https://rubygems.org/gems/phonemizer_ffi) publié sur rubygems.org, déclaré en dépendance (`add_dependency 'phonemizer_ffi', '~> 0.1'`) et chargé par `require "phonemizer_ffi"` ; le gem `ffi` et libespeak-ng restent ses prérequis transitifs. Replis inchangés (gem phonemizer, CLI `phonemize`, espeak-ng direct)
- README, commentaires et spec (`backend phonemizer_ffi` require maintenant le gem) mis à jour ; 99 exemples RSpec, 0 échec

## 0.1.2 - 2026-11-21

- règle 1.5d restreinte au mode contemporain : en contexte classique (`dierese` actif, donc aussi en `:auto` quand le re-scan atteint un mètre 6/8/10/12), le e final des mots en -Cre est compté (nouveau prédicat `cluster_re_pronounced?` : notre -> no-tʁə, vivre -> vi-vʁə, âpre -> â-pʁə, spectre -> spɛk-tʁə, meurtre -> mœʁ-tʁə, pauvre -> po-vʁə, ivre -> i-vʁə, sombre -> sɔ̃-bʁə, pluriel en -s accepté). Bilan sur chatiments.txt : 12: 3914→4085, 8: 891→928, 6: 469→481, 11: 813→647, 7: 163→126, 5: 84→72
- règle 1.4b : un e final prononcé (CR_E_PRONOUNCED, ou -Cre en classique) n'est plus élagué devant une pause (« ivre, complice » -> i-vʁə, 2 syllabes)
- 8 nouveaux exemples RSpec (99 au total, 0 échec) ; `docs/scansion_rules.txt` mis à jour (1.4b, 1.5d)

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
