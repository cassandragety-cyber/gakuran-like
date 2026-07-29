# DECISIONS — journal des décisions techniques

Format : contexte → décision → alternative écartée → pourquoi → coût si on
change d'avis. Fichier **append-only** : on ne réécrit pas une décision passée,
on en ajoute une nouvelle qui la remplace explicitement.

---

## ADR-001 — Combat : détection client + validation serveur avec lag compensation bornée

**Statut :** accepté (Phase 0) · **Impact :** irréversible en pratique après Phase 1

**Contexte.** Cible 60 % mobile, ping réel 100-200 ms, et le critère d'acceptation
du brief est « deux joueurs à 150 ms doivent pouvoir parry de façon fiable, sans
hit fantôme ». Ces deux exigences tirent dans des directions opposées.

**Décision.** Le client détecte le contact (`GetPartBoundsInBox` + `OverlapParams`)
et envoie une **demande** contenant `{skillId, seq, clientTime, targets}`. Le
serveur conserve un historique de positions par joueur (`RingBuffer`, 250 ms) et
**rejoue la scène à `clientTime`** pour valider distance, angle et ligne de vue.
Le serveur est seul à écrire HP, dégâts, KO, stamina, monnaie.

**Alternative écartée.** Hitbox entièrement serveur, calculée à l'instant de
réception. C'est la solution la plus simple à sécuriser.

**Pourquoi.** À 150 ms, une hitbox serveur non compensée oblige le joueur à viser
~1,5 m devant sa cible : le combat devient illisible, et la fenêtre de parry de
0.2 s devient un pur jeu de hasard — c'est-à-dire que la mécanique de skill
principale du jeu meurt. La lag comp bornée à 250 ms est le compromis standard
(« favor the shooter »), et le rewind borné limite le gain d'un exploiteur qui
mentirait sur `clientTime` à un demi-mètre, pas à une téléportation.

**Coût de revirement.** Élevé : `StateService` (historique), `HitValidator`
(rewind) et le protocole `Net` sont construits autour. À décider maintenant, pas
en Phase 3.

---

## ADR-002 — Le parry est arbitré par le serveur sur une horloge commune

**Statut :** accepté (Phase 0) · **Impact :** fort

**Contexte.** Le parry renvoie un stun long à l'attaquant. C'est donc la
mécanique la plus rentable à tricher du jeu : un exploiteur qui peut déclarer
« j'ai parry » gagne tous les duels.

**Décision.** Le client n'envoie **jamais** « parry réussi ». Il envoie
l'ouverture et la fermeture de son état de block, horodatées via
`workspace:GetServerTimeNow()` (module `Shared/Clock`). Le serveur, lors d'un hit
validé, regarde si l'instant d'impact tombe dans les 0.2 s suivant l'ouverture du
block. Le résultat (parry / block / guard break / hit) est calculé côté serveur
et répliqué aux deux joueurs.

**Alternative écartée.** Faire confiance à un remote `Combat.Parry` déclaratif du
défenseur, validé seulement par cooldown.

**Pourquoi.** Un timestamp d'ouverture de block est falsifiable de quelques
dizaines de millisecondes (bornées par la tolérance RTT) ; une déclaration de
parry est falsifiable à 100 %. La différence entre les deux, c'est la survie du
PvP à trois mois.

**Conséquence UX assumée.** Le client joue immédiatement un feedback *provisoire*
de parry pour la réactivité, que le serveur confirme ou corrige en ~1 RTT. Le
`FeedbackController` doit donc rendre la correction gracieuse (pas de flash
contradictoire) — c'est un travail de Phase 1, pas un détail.

---

## ADR-003 — Les styles sont des données interprétées par une grammaire d'effets, jamais du code

**Statut :** accepté (Phase 0) · **Impact :** structurant pour tout le contenu

**Contexte.** 15 styles minimum, 4 skills chacun = 60+ capacités, avec l'exigence
explicite qu'un 16e style soit « un simple fichier de config, zéro modif du
CombatService ».

**Décision.** `CombatService` interprète un `SkillSpec` déclaratif (phases
windup/active/recovery, `HitboxSpec`, listes d'`EffectSpec` typées en union :
`Damage`, `Knockback`, `Knockdown`, `Stun`, `Status`, `Move`, `Heal`). Un style
est un fichier de `Config/Styles/` validé contre ce schéma au boot, qui **crash
explicitement** si malformé plutôt que de partir en production silencieusement.

**Alternative écartée.** Un module Luau par style exposant
`OnSkill1(caster, target)` — l'approche la plus courante sur Roblox, et de loin
la plus flexible.

**Pourquoi.** Du code par style, c'est : 60 chemins d'exécution non testés, la
possibilité qu'un style buggé fasse tomber le combat de tout le serveur, aucune
garantie que les règles anti-triche s'appliquent uniformément (chaque style
pourrait « oublier » de vérifier la stamina), et un rééquilibrage impossible sans
relire du code. La grammaire coûte plus cher à écrire une fois et rend les 15
styles suivants quasi gratuits — exactement la forme du projet.

**Limite reconnue.** Un effet d'un *genre* nouveau (projectile, téléportation,
zone persistante) demande d'étendre la grammaire et son interpréteur. C'est un
coût par *genre* (≈ 3 prévus sur toute la vie du projet), pas par style. On
refusera l'ajout d'un `kind` fourre-tout du type `RunCustomFunction`, qui
annulerait le bénéfice de l'ADR.

---

## ADR-004 — Service loader maison (~80 lignes) plutôt que Knit ou Flamework

**Statut :** accepté (Phase 0) · **Impact :** moyen, réversible

**Contexte.** Le brief interdit les frameworks lourds sauf justification, et
demande un loader lisible d'environ 80 lignes.

**Décision.** `Shared/Loader.luau` : découvre les `ModuleScript` d'un dossier,
lit un champ optionnel `Dependencies: {string}`, effectue un tri topologique
(échec bruyant sur cycle ou dépendance manquante), puis appelle `Init()` sur tous
les services avant d'appeler `Start()` sur tous. Le même loader sert aux
`Services` serveur et aux `Controllers` client.

**Alternative écartée.** Knit (le standard de fait) et Flamework.

**Pourquoi.** Ce projet n'a besoin que de deux choses d'un framework : un ordre
d'initialisation déterministe et un accès inter-services. Knit apporte en plus
une couche réseau implicite (`Knit.CreateService` + `Client` table) qui entre en
conflit direct avec ADR-005 : elle génère des remotes non déclarés, donc non
rate-limités et absents du modèle de menace. Flamework impose une transformation
à la compilation et roblox-ts. Dans les deux cas on paierait une dépendance
majeure pour remplacer 80 lignes que l'on veut auditer soi-même — sur un jeu dont
le principal risque est l'exploit, l'auditabilité prime.

**Coût de revirement.** Faible : passer à Knit plus tard demanderait de réécrire
les points d'entrée des services, pas leur logique.

---

## ADR-005 — Réseau : remotes déclarés dans un fichier unique, avec middleware obligatoire

**Statut :** accepté (Phase 0) · **Impact :** fort

**Contexte.** Exigence anti-exploit : rate-limit par joueur sur *chaque* remote,
et un `THREAT_MODEL.md` listant chaque remote avec sa contre-mesure. Ces deux
exigences ne survivent pas si n'importe quel script peut créer un `RemoteEvent`.

**Décision.** `Net/Definitions.luau` est le **seul** endroit où un remote peut
naître : id, direction, type de payload, validateur de forme, bucket de
rate-limit. `Net/init.luau` instancie les objets Roblox à partir de cette table
et impose la chaîne `rate-limit → validation de forme → handler`. Créer un
`RemoteEvent` à la main ailleurs dans `src/` est interdit (règle de revue, et
test de boot qui compare les remotes existants à la déclaration). Corollaire déjà
inscrit dans le brief : aucun remote n'accepte de montant, de dégât ou d'id
d'item libre.

**Alternative écartée.** Zap (codegen réseau typé, sérialisation en `buffer`,
nettement plus performant sur le fil).

**Pourquoi.** Zap ajoute un binaire Rust et une étape de génération au workflow
Rojo+Wally, pour un gain qui ne devient décisif qu'à un volume de paquets que ce
jeu n'atteint pas (< 25 paquets/s/joueur en combat, cf. budgets). On garde
l'option ouverte : le `SkillSpec` et les payloads sont conçus comme des structs
plats, donc migrables vers du `buffer` packé sans toucher aux services si le
profiling l'exige en Phase 7.

---

## ADR-006 — Échec de chargement de données = kick, jamais de profil neuf

**Statut :** accepté (Phase 0) · **Impact :** fort, non négociable

**Contexte.** Le brief l'exige, et c'est la première cause de mort d'un jeu
Roblox à rétention : un joueur qui perd son style Mythic ne revient pas.

**Décision.** `DataService` utilise ProfileStore avec session locking et schéma
versionné. Si le chargement échoue, si le lock ne peut pas être pris, ou si une
migration échoue, le joueur est **kické avec un message explicite** ; aucun
profil par défaut n'est créé pour un joueur existant. Autosave 60-120 s (jitter
pour étaler la charge), save sur `PlayerRemoving`, `BindToClose` attendant la
fin des écritures. Les migrations vivent dans `Systems/SchemaMigrations.luau`,
pures, testées sur des fixtures de chaque version antérieure.

**Alternative écartée.** Mode dégradé : laisser jouer avec un profil temporaire
non sauvegardé, bannière d'avertissement à l'écran.

**Pourquoi.** Le mode dégradé transforme un incident visible (un kick, un ticket
support) en corruption invisible : un joueur qui joue 40 minutes sur un profil
fantôme perd sa session *et* fait perdre confiance. Un kick est frustrant une
fois ; une perte de progression est définitive.

---

## Décisions différées (à trancher au moment dit, notées ici pour ne pas être oubliées)

| Sujet | Phase | Pourquoi on attend |
|---|---|---|
| Ragdoll : `PhysicsService` custom vs contraintes sur R15 | 1 | Dépend du coût mesuré sur mobile avec 20 joueurs |
| Pity system du gacha : activé ou non, et à quel N | 2 | Dépend de la courbe de rétention visée, à discuter |
| Territoire de gang (fonctionnalité optionnelle du brief) | 5 | Cross-server MemoryStore : à cadrer une fois les gangs de base jouables |
| Packing `buffer` des payloads de combat | 7 | Uniquement si le budget paquets est dépassé |
