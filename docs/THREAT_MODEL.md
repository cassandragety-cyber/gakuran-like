# THREAT MODEL

Un remote = une ligne. Ce document est mis à jour **dans le même commit** que
toute modification de `src/ReplicatedStorage/Net/Definitions.luau` ; un remote
sans ligne ici est un remote non revu.

---

## 1. Principes appliqués à tous les remotes

| Principe | Mise en œuvre |
|---|---|
| Aucun remote ne naît hors du contrat | `Net/Definitions.luau` est la seule source ; `Net.initServer()` refuse de démarrer si un identifiant est dupliqué ou si une limite de cadence manque. Un remote ajouté au dossier réseau après coup est journalisé en erreur. |
| Aucun montant libre | Aucun payload ne contient de dégât, de prix, de somme d'argent, ni d'identifiant d'objet choisi par le client. Le client décrit une intention, le serveur calcule le résultat. |
| Cadence bornée | Token bucket par joueur **et** par remote (`Config/RateLimits`). Un refus ne consomme pas de jeton, pour qu'un joueur bloqué se débloque. |
| Forme validée par reconstruction | Chaque définition porte un `parse` qui **reconstruit** un payload propre au lieu de laisser passer la table reçue. Champs supplémentaires, métatables et pièges `__index` n'atteignent jamais un service. |
| Rejet des nombres pathologiques | `NaN`, `±inf` et les flottants là où un entier est attendu sont refusés à l'entrée. `NaN` est le vecteur classique : il traverse toutes les comparaisons `<` et `>` sans jamais les satisfaire. |
| Escalade graduée | Dépassement de cadence et payload malformé alimentent le même compteur ; à 12 infractions, kick. Un client honnête ne produit jamais de payload malformé, même sous une latence extrême. |
| Nettoyage | Les compteurs et buckets sont détruits au `PlayerRemoving` — sinon un serveur de longue durée fuit une table par joueur passé. |
| Le serveur ne demande pas ce qu'il peut déduire | Un champ que le client n'envoie pas est un champ qu'on n'a pas à valider. L'index de chaîne d'attaque est dérivé de l'état serveur, pas reçu ; la direction d'un dash est un entier de 1 à 4, pas un `Vector3` (ADR-012). |
| Les remotes de développement n'existent pas en production | Un remote marqué `devOnly` n'est **pas instancié** hors Studio et hors liste d'administrateurs : il n'apparaît pas dans l'arbre, aucune régression de logique ne peut le rouvrir (ADR-013). |

**Ce que ces principes ne couvrent pas, et qui est traité ailleurs :** la
cohérence de gameplay (distance, ligne de vue, cooldown, endurance, état
d'animation) est validée par `Systems/HitValidator` en Phase 1, pas par le
middleware réseau. Le middleware garantit qu'un paquet est *bien formé et pas
trop fréquent*, jamais qu'il est *légitime*.

---

## 2. Remotes déclarés

### `System.PingRequest` — client → serveur

| | |
|---|---|
| **Payload** | `{ seq: entier [0, 10^6], clientTime: nombre fini }` |
| **Cadence** | 6 en rafale, 0,5/s soutenu |
| **Ce que tenterait un exploiteur** | (a) inonder le serveur pour le saturer ; (b) mentir sur `clientTime` pour se faire passer pour un joueur à très faible ou très forte latence, dans l'espoir d'influencer le rembobinage de la Phase 1 ; (c) envoyer `NaN` ou un `seq` non entier pour provoquer une erreur dans un chemin de calcul. |
| **Contre-mesure** | (a) token bucket, puis kick à 12 infractions ; (b) le serveur ne fait que **mesurer** avec cette valeur, il n'accorde aucun privilège sur sa base ; un écart implausible (avance supérieure à la tolérance de 0,12 s, ou retard supérieur à 2 s) est journalisé et **exclu des statistiques** au lieu d'être moyenné ; (c) `parse` rejette `NaN`, l'infini et les non-entiers avant tout calcul. |
| **Risque résiduel** | Un exploiteur peut fausser sa propre mesure de latence. Conséquence maximale : les diagnostics le concernant sont faux. Aucune décision de gameplay ne s'appuie sur cette valeur — et le jour où la Phase 1 voudra s'en servir pour dimensionner un rembobinage, ce sera à `HitValidator` de revalider indépendamment, jamais à cette mesure de faire foi. |

### `System.PingReply` — serveur → client

| | |
|---|---|
| **Payload** | `{ seq: entier, serverTime: nombre fini }` |
| **Surface d'attaque** | Nulle dans ce sens : un client ne peut pas déclencher un remote serveur → client. Le payload est tout de même reparsé côté client, non par méfiance envers le serveur mais pour que le handler reçoive un type garanti. |
| **Ce qui est délibérément absent** | Aucune donnée d'un autre joueur n'y transite. Règle générale : ce qu'on n'envoie pas au client ne peut pas être lu par un exploiteur. |

---

## 3. Remotes prévus et leur risque anticipé

Ces entrées ne sont pas encore implémentées. Elles figurent ici pour que la
contre-mesure soit conçue avant le remote, et non ajoutée après.

| Remote | Phase | Risque principal | Contre-mesure prévue |
|---|---|---|---|
| `Combat.Attack` `{seq, clientTime}` | 1 | Rafale d'attaques sans respecter cooldowns ni endurance ; réclamer directement le 4e coup pour un knockdown à la demande | Cadence 8/4-s ; l'index de chaîne est **dérivé** par `ComboMachine` de l'état serveur et n'est pas dans le payload ; endurance et transition validées par `StateMachine.canRequest` |
| `Combat.HitReport` `{seq, clientTime, targets}` | 1 | Déclarer des cibles hors de portée, à travers un mur, dans le dos, ou tout le serveur d'un coup ; rejouer le même swing | `Rewind` borné à 0,25 s puis `HitValidator` : distance, `FacingDot`, ligne de vue, fraîcheur d'horodatage, phase active cohérente, `AlreadyHitThisSwing` ; liste plafonnée à `MaxTargetsPerSwing` |
| `Combat.BlockState` `{open, clientTime}` | 1 | Antidater l'ouverture de garde pour parer rétroactivement ; maintenir une fenêtre de parade ouverte en permanence | Horodatage comparé à l'horloge serveur, tolérance 0,12 s ; fenêtre de 0,20 s calculée serveur ; cooldown de 0,55 s entre deux ouvertures ; le client ne déclare jamais « j'ai paré » (ADR-002) |
| `Combat.Dash` `{direction 1..4, clientTime}` | 1 | Dash sans coût, i-frames permanentes, ou déplacement arbitraire | Direction bornée à un entier de 1 à 4 — jamais un vecteur ; cooldown et endurance serveur ; l'invulnérabilité est une propriété d'état serveur, pas un message |
| `Debug.SetTuning` `{path, value}` | 1 | **Réécrire l'équilibrage** : dégâts, fenêtres de parade | `devOnly` — le remote n'existe pas en production ; `TuningGuard` applique une liste blanche de chemins avec bornes, donc même un compte administrateur compromis reste borné ; les durées d'animation sont hors liste blanche pour ne pas casser le contrat du boot (ADR-009) |
| `Style.Reroll` | 2 | Rerouler sans payer, ou rejouer un tirage jusqu'au Mythic | Le tirage est effectué serveur, le débit précède le tirage, le résultat n'est communiqué qu'une fois écrit dans le profil |
| `Economy.Transfer` | 4 | Duplication de monnaie, blanchiment entre comptes complices | Débit et crédit dans la même transaction serveur ; `Systems/TransferGuard` applique plafond glissant, cooldown et détection d'aller-retour |
| `Economy.JobAction` | 4 | Valider les étapes d'un métier sans les accomplir | Chaque étape a une condition vérifiable serveur (position, temps écoulé, ordre) ; la paie est calculée serveur |
| `Shop.Purchase` | 7 | Acheter à un prix choisi par le client | Le payload ne contient qu'un identifiant d'article ; le prix vient de `Config/Economy` |
| `Gang.Action` | 5 | Usurper un rôle, inviter en masse | Vérification du rôle appelant serveur, cadence stricte sur les invitations |

---

## 4. Journal des révisions

| Date | Phase | Modification |
|---|---|---|
| Phase 0 | 0 | Création. Deux remotes de diagnostic déclarés ; principes généraux et surface anticipée posés. |
| Phase 1 (conception) | 1 | Ajout de deux principes (ne pas demander ce qu'on peut déduire, `devOnly` non instancié en production). Payloads de combat figés et contre-mesures détaillées avant implémentation. |
