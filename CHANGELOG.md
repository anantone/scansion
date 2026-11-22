# Journal des modifications

## 0.1.5 - 2026-11-22

- `cluster_re_pronounced?` étendu aux finales -ce/-ge/-que/-gue (pluriel -s/-x accepté) : en contexte classique, leur e final est COMPTÉ — Pâques -> pâ-ques, algue -> al-gue, vagues -> va-gues, jonque -> jon-que, Cantique -> can-ti-que, calices -> ca-li-ces, rouges -> rou-ges, douce -> du-sə, grâce -> grâ-sə, ombrage -> om-bra-gə (la branche « curseur épuisé » restaure aussi le schwa quand espeak l’a avalé)
- nouveau ciblage `ent_words` : en re-scan ciblé mot à mot, le -ent de 3e personne du pluriel est prononcé ɑ̃ (t'arrivent -> ta-ʁi-vɑ̃, surgissent -> syʁ-ʒi-sɑ̃, marquent -> maʁ-kɑ̃), sans liaison du t ; jamais en passe globale
- diérèses ciblées supplémentaires (uniquement via `dierese_words`, jamais en diérèse globale — « nuage » reste 1 syllabe) : « u+a » interne (suaves -> su-a-ves, muaient -> mu-a-ient, mortuaires -> mor-tu-aires) et « ou+i » (épanoui -> é-pa-nou-i, épanouit -> é-pa-nou-it) ; `DIERESE_WORD` élargi (`ua`, `oui` n’importe où)
- « y » suivi d’une voyelle = glide /j/ : nouveaux prédicats `y_glide?`/`liaison_initial?` — il BLOQUE l’élision du mot précédent (peintre Yosen -> pein-tʁə, 2 syllabes) mais la liaison d’une consonne finale a bien lieu (les yeux -> lez-jø)
- réparation de deux regex `/s\z/` (double backslash, ne matche jamais) en `/s\z/`
- Bilan sonnets_oupoco.txt : 12: 48398→51067, 11: 5838→3181, 8: 7018→7280, 7: 1197→934, 10: 3702→3764, 9: 494→420, 5: 162→150 ; chatiments.txt : 12: 4205→4432, 11: 527→304. Replis (~) : 2539 (3,7 %). Liste « 11 syllabes à e muet final » : 2251→1053 lignes (rapports/…_v2…v4)
- règle 1.5 : devant un mot à initiale vocalique, le e muet d’un pluriel en -es/-eux est prononcé avec liaison du s (nouveau prédicat `plural_mute_e?` : « nouvelles amours » -> nu-vɛ-lə-za-muʁ, « des âmes hautaines » -> de-za-mə-o-tɛn) ; le singulier élide toujours (« la table amie » -> la-tabl-a-mi). Bilan racine_txt (17 plays) : 12: 21368→22644 (76,6 %→81,2 %), 11: 2530→1255 ; oupoco : 12: 51067→51270, 11: 3181→3022 ; chatiments : 12: 4432→4460, 11: 304→281
- règle 1.4b (exception alexandrine) : en mode `:auto`, un e muet devant une pause graphique (, ; : ! ? … —) est compté quand cela mène le vers exactement à 12 syllabes (nouveau paramètre `pause_e` des passes de re-scan) — « Dites, sans l’accuser de chercher un esclave, » -> 12 (di-tə). Jamais en mode plain/`--no-dierese`, et un octosyllabe n’est pas forcé à 12. Bilan racine_txt : 12: 22644→23114 (82,8 %), 11: 1255→787 ; oupoco : 12: 51270→52626, 11: 3022→1676 ; chatiments : 12: 4460→4578, 11: 281→164
- `Result#word_spans` : nouveaux spans mot -> indices de syllabes exposés par le gem (même règle de comptage que `count_syllables`), pour les outils en aval (accent_de_phrase les consomme directement, sans re-phonétiser les mots isolés)
- 27 nouveaux exemples RSpec (130 au total, 0 échec) ; `docs/scansion_rules.txt` mis à jour (1.4c, 1.5c bis, 1.5d, y-glide)
- `cluster_re_pronounced?` étendu aux finales -ce/-ge/-que/-gue (pluriel -s/-x accepté) : en contexte classique, leur e final est COMPTÉ — Pâques -> pâ-ques, algue -> al-gue, vagues -> va-gues, jonque -> jon-que, Cantique -> can-ti-que, calices -> ca-li-ces, rouges -> rou-ges, douce -> du-sə, grâce -> grâ-sə, ombrage -> om-bra-gə (la branche « curseur épuisé » restaure aussi le schwa quand espeak l’a avalé)
- nouveau ciblage `ent_words` : en re-scan ciblé mot à mot, le -ent de 3e personne du pluriel est prononcé ɑ̃ (t'arrivent -> ta-ʁi-vɑ̃, surgissent -> syʁ-ʒi-sɑ̃, marquent -> maʁ-kɑ̃), sans liaison du t ; jamais en passe globale
- diérèses ciblées supplémentaires (uniquement via `dierese_words`, jamais en diérèse globale — « nuage » reste 1 syllabe) : « u+a » interne (suaves -> su-a-ves, muaient -> mu-a-ient, mortuaires -> mor-tu-aires) et « ou+i » (épanoui -> é-pa-nou-i, épanouit -> é-pa-nou-it) ; `DIERESE_WORD` élargi (`ua`, `oui` n’importe où)
- « y » suivi d’une voyelle = glide /j/ : nouveaux prédicats `y_glide?`/`liaison_initial?` — il BLOQUE l’élision du mot précédent (peintre Yosen -> pein-tʁə, 2 syllabes) mais la liaison d’une consonne finale a bien lieu (les yeux -> lez-jø)
- réparation de deux regex `/s\z/` (double backslash, ne matche jamais) en `/s\z/`
- Bilan sonnets_oupoco.txt : 12: 48398→51067, 11: 5838→3181, 8: 7018→7280, 7: 1197→934, 10: 3702→3764, 9: 494→420, 5: 162→150 ; chatiments.txt : 12: 4205→4432, 11: 527→304. Replis (~) : 2539 (3,7 %). Liste « 11 syllabes à e muet final » : 2251→1053 lignes (rapports/…_v2…v4)
- 16 nouveaux exemples RSpec (119 au total, 0 échec) ; `docs/scansion_rules.txt` mis à jour (1.4c, 1.5c bis, 1.5d, y-glide)

## 0.1.4 - 2026-11-21

- diérèse : le « ou » devant « é/è » compte double aussi (dénoué -> dé-nu-é) et le « i » devant « u » (médium -> mé-di-um)
- `cluster_re_pronounced?` généralisé à tous les mots en -re (aussi -ère/-oire/-ire : mère -> mè-re, gloire -> gloi-re, terre -> ter-re, encore -> ɑ̃-kɔʁə), toujours uniquement en contexte classique
- mode `:auto` : quand le re-scan global (diérèse + e des -re) ne tombe pas sur un mètre, re-scan ciblé mot à mot (`fix_candidate_words`, `dierese_words`/`cluster_words`) retenu dès qu'il atteint 6/8/10/12 — évite les sur-comptages des faux amis (vieux, dieu…)
- Bilan sonnets_oupoco.txt : 12: 47180→48398, 11: 7052→5838, 8: 6945→7018, 7: 1270→1197 ; chatiments.txt : 12: 4085→4205, 11: 647→527. Replis (~) : 2531 (3,7 %)
- 4 nouveaux exemples RSpec (103 au total, 0 échec) ; `docs/scansion_rules.txt` mis à jour (1.4c, 1.5d)

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
