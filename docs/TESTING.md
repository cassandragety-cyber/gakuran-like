# TESTING — procédures de test dans Studio

Une section par phase. Chaque test indique les étapes exactes, ce qu'on doit
observer, et ce que ça prouve.

---

## Phase 0 — Outillage, chargeur, réseau typé, validation de configuration

### Préparation (une seule fois)

```bash
rokit install
selene generate-roblox-std
rojo serve
```

Dans Roblox Studio : nouvelle place vide → onglet **Plugins → Rojo → Connect**.
`ReplicatedStorage.Shared`, `ReplicatedStorage.Config`, `ReplicatedStorage.Net`,
`ServerScriptService.Server` et `StarterPlayer.StarterPlayerScripts.Client`
apparaissent dans l'Explorer.

> Si le bouton Connect refuse : vérifier que `rojo serve` tourne toujours et que
> le port affiché dans le terminal correspond à celui du plugin.

---

### T0.1 — Le serveur démarre et le dit

1. **Play** (F5).
2. Ouvrir la fenêtre **Output**, filtrer sur **Server**.

Attendu, dans cet ordre :

```
[Boot/Server] configuration validée
[Net] 2 remotes publiés
[Boot/Server] 2 modules chargés : SessionService, DiagnosticsService
[Boot/Server] OK — serveur prêt en 3.4 ms
```

**Ce que ça prouve.** La configuration est cohérente, les remotes existent tous
avec une limite de cadence, et le tri des dépendances fonctionne : remarquer que
`SessionService` est initialisé **avant** `DiagnosticsService`, alors que
l'ordre alphabétique est l'inverse — c'est la déclaration
`Dependencies = { "SessionService" }` qui l'a imposé.

---

### T0.2 — Le client démarre et mesure sa latence

Toujours en Play, filtrer l'Output sur **Client**.

```
[Boot/Client] 1 modules chargés : DiagnosticsController
[Boot/Client] OK — client prêt en 1.8 ms
[DiagnosticsController] mesure 0 : RTT 2 ms, écart 1 ms
[DiagnosticsController] mesure 1 : RTT 1 ms, écart 0 ms
[DiagnosticsController] mesure 2 : RTT 2 ms, écart 1 ms
[DiagnosticsController] RTT médian à la connexion : 2 ms
```

En Studio, client et serveur sont sur la même machine : des RTT de 1 à 5 ms sont
normaux. Le test vérifie le mécanisme, pas la valeur.

**Ce que ça prouve.** L'aller-retour réseau complet fonctionne de bout en bout :
définition typée → middleware → service → réponse → parsing client.

---

### T0.3 — La latence mesurée côté serveur est accessible

Dans l'onglet **Test**, basculer la console sur **Server**, puis dans la barre
de commande :

```lua
local svc = require(game.ServerScriptService.Server.Services.DiagnosticsService)
print(svc.oneWayLatency(game.Players:GetPlayers()[1]))
print(svc.exceedsRewindBudget(game.Players:GetPlayers()[1]))
```

Attendu : un petit nombre décimal (secondes, typiquement < 0.005) puis `false`.

**Ce que ça prouve.** Le serveur mesure le délai aller par joueur — la quantité
dont `HitValidator` aura besoin en Phase 1 pour décider du rembobinage. Le
`false` confirme que la latence tient dans le budget de 0,25 s d'ADR-001.

---

### T0.4 — Le rate limiting fonctionne et sanctionne

Basculer la console sur **Client**, puis :

```lua
local ctrl = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.DiagnosticsController)
for _ = 1, 20 do ctrl.measure() end
```

Attendu côté **Server** :

```
[Net] infraction 1/12 — <votre pseudo> : cadence dépassée sur System.PingRequest
[Net] infraction 2/12 — ...
...
[Net] infraction 12/12 — ...
[Net] kick de <votre pseudo> après 12 infractions
```

Le client est déconnecté avec le message « Connexion interrompue : trop de
requêtes envoyées. »

Détail des chiffres : le bucket `SystemPing` autorise 6 appels en rafale et se
recharge à 0,5/s. Sur 20 appels immédiats, 6 passent et 14 sont refusés ; le
kick tombe au 12e refus, donc au 18e appel.

**Ce que ça prouve.** Aucun remote n'est ouvert en cadence libre, et l'escalade
log → kick est effective. C'est la contre-mesure (a) de `System.PingRequest`
dans [THREAT_MODEL.md](THREAT_MODEL.md).

---

### T0.5 — Un payload malformé n'atteint jamais un service

Console sur **Client** :

```lua
local net = game.ReplicatedStorage:WaitForChild("BanchouNet")
local remote = net:WaitForChild("System.PingRequest")
remote:FireServer({ seq = 0/0, clientTime = 0 })          -- NaN
remote:FireServer({ seq = 1.5, clientTime = 0 })          -- non entier
remote:FireServer("pas une table")                        -- mauvais type
remote:FireServer({ seq = 2, clientTime = 0, extra = 1 }) -- champ en trop
```

Attendu côté **Server** : trois lignes `payload malformé sur
System.PingRequest`, et **aucune erreur Luau**. Le quatrième appel passe (il est
bien formé), mais le champ `extra` n'existe pas dans ce que reçoit le service :
`parse` reconstruit le payload au lieu de transmettre la table reçue.

**Ce que ça prouve.** `NaN`, les flottants là où un entier est attendu, les
mauvais types et les champs supplémentaires sont arrêtés au middleware.

---

### T0.6 — Une configuration incohérente empêche le démarrage

Ce test est le plus important de la Phase 0 : il vérifie que le contrat entre
l'équilibrage et les animations est réellement tenu par la machine, et pas
seulement écrit dans un document.

1. Ouvrir `src/ReplicatedStorage/Config/Balance.luau`, dans `Melee`, premier
   coup : remplacer `recovery = 0.25` par `recovery = 0.30`. Sauvegarder.
2. **Play**.

Attendu — le serveur refuse de démarrer avec :

```
[Boot/Server] configuration invalide : ConfigInvalid — 1 problème(s) :
  - Animations.M1_1.targetDuration = 0.45 mais Balance.Melee[1] totalise 0.5
```

3. Essayer aussi, une modification à la fois :
   - `Config/Styles/Rarity.luau` : `Common = 61` → *« la somme des poids de
     rareté vaut 101 »* ;
   - `Config/Styles/Rarity.luau` : `PITY_TARGET_RARITY = "Mythic"` → *« ne peut
     pas être Mythic : aucun pity sur Mythic »* ;
   - `Config/Monetization.luau` : un `grantsCombatAdvantage = true` → *« vend un
     avantage de combat — interdit par la règle produit »* ;
   - `Config/DataStores.luau` : `PlayerData = "BanchouPlayerData"` → *« ne suit
     pas la convention Banchou_<Nom>_v<N> »*.
4. **Rétablir toutes les valeurs d'origine** et vérifier que T0.1 repasse.

**Ce que ça prouve.** L'équilibrage est modifiable sans lire de code, mais pas
incohérent en silence. Le point 3 montre aussi que trois décisions produit
(pas de pity sur Mythic, rien qui vende du combat, clés de stockage
versionnées) sont appliquées par le programme et pas seulement documentées.

---

### T0.7 — Le profiler mesure

Console sur **Server** :

```lua
local Profiler = require(game.ReplicatedStorage.Shared.Profiler)
for _ = 1, 300 do
    local t0 = os.clock()
    local _ = workspace:GetPartBoundsInBox(CFrame.new(), Vector3.new(5, 5, 7))
    Profiler.record("hitbox", os.clock() - t0)
end
require(game.ServerScriptService.Server.Services.DiagnosticsService).dumpProfiler()
```

Attendu :

```
[DiagnosticsService] hitbox            n=300  min=0.004ms moy=0.011ms p95=0.021ms max=0.180ms
```

**Ce que ça prouve.** L'instrument exigé au §6 du brief existe et donne un p95,
pas seulement une moyenne — c'est le p95 qui provoque les chutes de framerate
perçues. Le budget à tenir en Phase 1 est **p95 < 0,15 ms par ouverture de
hitbox**.

---

### T0.8 — Aucune fuite de connexion entre sessions

1. Play, puis Stop, puis Play à nouveau, trois fois de suite.
2. Console **Server** :

```lua
print(require(game.ServerScriptService.Server.Services.SessionService).count())
```

Attendu : `1` à chaque fois, jamais un compteur qui grimpe.

**Ce que ça prouve.** Les sessions et les buckets de rate-limit sont libérés au
départ du joueur.

---

### T0.9 — Le contrôle qualité passe

```bash
./scripts/check.sh
```

Attendu : `Tous les contrôles passent.` — format StyLua, lint Selene, absence de
boucle d'attente active, aucun module au-dessus de 300 lignes, `--!strict`
partout.

---

## Phase 1 — Combat

### Tranche 1.1 — État, machine à états, sprint, panneau F2

Prérequis nouveau depuis la Phase 0 : `wally install` est désormais **nécessaire**
(le nettoyage des connexions de personnage passe par Trove). Le serveur refuse de
démarrer avec un message explicite si les dépendances manquent.

---

#### T1.1.1 — Le boot charge les six services dans le bon ordre

**Play**, Output filtré sur **Server** :

```
[Boot/Server] configuration validée
[Net] 6 remotes publiés
[TuningService] réglage à chaud ACTIF sur ce serveur
[Boot/Server] 6 modules chargés : TuningService, CharacterService, SessionService,
              DiagnosticsService, StateService, MovementService
[Boot/Server] OK — serveur prêt en 4.2 ms
```

Puis sur **Client** :

```
[Boot/Client] 6 modules chargés : InputController, StateMirrorController,
              TuningController, DiagnosticsController, DebugPanelController,
              MovementController
[Boot/Client] OK — client prêt en 2.1 ms
```

**Ce que ça prouve.** `TuningService` est initialisé avant `CharacterService`, qui
lui-même précède `StateService` — l'ordre vient des `Dependencies`, pas de
l'alphabet. Et l'avertissement de `TuningService` est volontairement bruyant : un
serveur où l'équilibrage est réinscriptible ne doit jamais passer inaperçu.

---

#### T1.1.2 — Le panneau s'ouvre et montre un état vivant

Appuyer sur **F2**. Le panneau apparaît à droite avec les sections État,
Ressources, Parade, Réseau, Entrées, Réglages.

Attendu au repos : `État = Idle`, `Phase = —`, `PV = 100 / 100`,
`Endurance = 100 / 100`, `Fenêtre ouverte = non`, `Fraîcheur de l'état` autour de
50-100 ms (la cadence de réplication est de 10 Hz).

Appuyer sur **F2** à nouveau : le panneau se masque. Vérifier dans le Script
Performance de Studio que rien ne remonte quand il est fermé — le rafraîchissement
sort immédiatement tant que le panneau est invisible.

---

#### T1.1.3 — Le sprint coûte de l'endurance, et le serveur seul décide

1. Panneau ouvert, maintenir **Maj gauche** et courir.
2. Observer `Endurance` descendre de **8 points par seconde** : tant qu'une
   dépense continue est en cours, la régénération est suspendue (sinon les 22/s
   hors combat dépasseraient les 8/s du sprint et courir rechargerait
   l'endurance).
3. Relâcher : l'endurance remonte à **22/s** hors combat.
4. Maintenir jusqu'à passer sous 10 : le sprint se coupe **de lui-même**, la
   vitesse retombe, la ligne `Endurance` passe en orange. Cela laisse environ
   11 secondes de course à pleine endurance.

Puis vérifier l'autorité, console sur **Server** :

```lua
local S = require(game.ServerScriptService.Server.Services.StateService)
print(S.isSprinting(game.Players:GetPlayers()[1]))
print(game.Players:GetPlayers()[1].Character.Humanoid.WalkSpeed)
```

Attendu : `true` puis `24` pendant le sprint ; `false` puis `16` sinon.

**Ce que ça prouve.** Le client n'envoie qu'une intention (`Move.SprintState`), le
serveur écrit `WalkSpeed` et coupe le sprint quand l'endurance ne suit plus. C'est
la première boucle complète intention → autorité → réplication → affichage.

---

#### T1.1.4 — Régler l'équilibrage à chaud, sans relancer

1. Panneau ouvert, section **Réglages**, faire glisser **« Distance de dash »**
   de 14 à 25.
2. Attendu côté **Server** :

```
[TuningService] <votre pseudo> a réglé Dash.Distance = 25
```

3. Saisir `0.33` dans le champ de **« Fenêtre de parade »** et valider. Le curseur
   se replace sur **0.33**.
4. Saisir `0.337` : le serveur aligne sur le pas de 0,01 et le champ affiche
   **0.34**. C'est le point important — l'interface montre ce que le serveur a
   retenu, pas ce qui a été demandé.
5. Saisir `99` : la valeur est bornée à **0.6** (maximum déclaré).
6. Cliquer **« Réinitialiser l'équilibrage »** : tous les curseurs reprennent les
   valeurs de `Config/Balance`.

**Ce que ça prouve.** Le réglage vit dans une copie mutée en place, `Config/Balance`
reste gelé et sert de référence, et les bornes de `Config/Debug` sont appliquées
côté serveur — pas par l'interface.

---

#### T1.1.5 — La machine à états expire toute seule

Console sur **Server** :

```lua
local S = require(game.ServerScriptService.Server.Services.StateService)
local p = game.Players:GetPlayers()[1]
S.impose(p, "Stunned", 3)
```

Attendu dans le panneau : `État = Stunned`, `Échéance` qui décompte de 3,00 s à 0,
puis retour automatique à `Idle`. Le personnage est immobilisé pendant toute la
durée (vitesse 0), et remarche ensuite.

Puis la chaîne de knockdown :

```lua
S.impose(p, "Knocked", 1.1)
```

Attendu : `Knocked` pendant 1,1 s → **`GettingUp`** pendant 0,60 s → `Idle`. Le
passage par `GettingUp` est automatique, personne ne l'a demandé.

**Ce que ça prouve.** Les échéances sont avancées par un unique `Heartbeat`, sans
minuteur par joueur, et `Knocked` enchaîne sur `GettingUp` comme spécifié.

---

#### T1.1.6 — Les gardes de transition refusent, avec un motif

Console sur **Server** :

```lua
local S = require(game.ServerScriptService.Server.Services.StateService)
local p = game.Players:GetPlayers()[1]

print(S.requestTransition(p, "Blocking"))       -- ok
print(S.requestTransition(p, "Idle"))           -- ok (relâchement)
print(S.requestTransition(p, "Blocking"))       -- refusé : ParryCooldown

S.impose(p, "Stunned", 5)
print(S.requestTransition(p, "Attacking"))      -- refusé : TransitionForbidden
print(S.requestTransition(p, "Dashing"))        -- refusé : TransitionForbidden
```

Attendu : les trois premiers appels renvoient `ok = true` puis un refus
`code = "ParryCooldown"`, et les deux derniers `code = "TransitionForbidden"`.

Vider l'endurance puis retenter un dash :

```lua
S.get(p).stamina.current = 5
print(S.requestTransition(p, "Dashing"))        -- refusé : NotEnoughStamina
```

**Ce que ça prouve.** Le cooldown de parade court depuis l'**ouverture** de la
garde ; aucune demande client ne sort d'un `Stunned` ; et un refus est une
information exploitable, pas une erreur silencieuse.

---

#### T1.1.7 — Latence simulée, en préparation de la recette à 150 ms

1. Panneau ouvert, régler **« Latence simulée »** à **150**.
2. Console **Client** : `require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.DiagnosticsController).measure()`
3. Observer la ligne `RTT médian` monter vers **150 ms**, et
   `Fraîcheur de l'état` monter d'environ 75 ms (la moitié du trajet).
4. Remettre à **0** : les deux lignes redescendent.

**Ce que ça prouve.** Le délai est appliqué symétriquement, en deux moitiés, par
une file **FIFO** (`Net/LatencySim`) : les paquets ne se réordonnent pas. C'est ce
qui rendra la recette de la tranche 1.7 crédible sur une seule machine — un
simulateur qui inverse des paquets fabriquerait des bugs qui n'existent pas.

---

#### T1.1.8 — Les remotes de développement ne devraient pas exister en production

En Studio, vérifier dans l'Explorer : `ReplicatedStorage → BanchouNet` contient
six remotes, dont `Debug.SetTuning` et `Debug.TuningSync`.

Pour observer le comportement de production sans publier : ouvrir
`src/ReplicatedStorage/Shared/DevAccess.luau` et remplacer temporairement
`RunService:IsStudio()` par `false` dans `isEnabled`. Relancer.

Attendu :

```
[Net] 4 remotes publiés
[Net] 2 remotes de développement non instanciés : Debug.SetTuning, Debug.TuningSync
[TuningService] aucun accès de développement, équilibrage vivant gelé
[DebugPanelController] réglage à chaud indisponible sur ce serveur, panneau désactivé
```

F2 ne fait plus rien, et les deux remotes sont **absents de l'arbre**. Rétablir
ensuite le fichier.

**Ce que ça prouve.** ADR-013 : le remote le plus dangereux du projet n'est pas
« protégé par un test », il n'existe pas. Et la table d'équilibrage redevient
gelée, donc la garantie de la Phase 0 tient aussi en production.

---

#### T1.1.9 — Une liste blanche incohérente empêche le démarrage

1. Dans `src/ReplicatedStorage/Config/Debug.luau`, remplacer
   `["Parry.Window"]` par `["Parry.Windo"]`. **Play**.

```
[Boot/Server] configuration invalide : ConfigInvalid — 1 problème(s) :
  - Config/Debug.Tunables["Parry.Windo"] : le chemin ne résout pas dans Config/Balance
```

2. Rétablir, puis essayer `tunable(0.05, 0.10, 0.01, "Fenêtre de parade")` — un
   maximum sous la valeur réelle de 0,20 :

```
  - Config/Debug.Tunables["Parry.Window"] : la valeur courante 0.2 est hors bornes [0.05, 0.1]
```

3. Rétablir et vérifier que T1.1.1 repasse.

**Ce que ça prouve.** Un curseur inerte est un bug qu'on ne remarque qu'en
cherchant pourquoi « le réglage ne marche pas ». Le boot l'attrape à la place.

---

#### T1.1.10 — Le contrôle qualité passe

```bash
./scripts/check.sh
```

---

### Tranche 1.2 — Chaîne M1, hitbox, rembobinage, validation, mannequins

Un **terrain d'entraînement provisoire** apparaît au démarrage : une plateforme,
trois mannequins de face, un mur et un quatrième mannequin derrière. La Phase 3 le
remplacera par la carte générée ; il existe parce qu'une place Studio vide n'a pas
de sol.

---

#### T1.2.1 — Le boot charge huit services

```
[Boot/Server] configuration validée
[Net] 10 remotes publiés
[TuningService] réglage à chaud ACTIF sur ce serveur
[TrainingService] terrain d'entraînement monté avec 4 mannequins
[Boot/Server] 8 modules chargés : TuningService, CharacterService, SessionService,
              StateService, CombatService, DiagnosticsService, MovementService,
              TrainingService
[Boot/Server] OK — serveur prêt en 12.4 ms
```

Côté **Client**, neuf controllers, dont l'ordre reflète encore les dépendances :
`InputController, TuningController, StateMirrorController, HitboxVisualizer,
CombatController, DiagnosticsController, DebugPanelController, HitboxDetector,
MovementController`.

---

#### T1.2.2 — La chaîne de quatre coups, et son knockdown

1. Se placer devant `Dummy_Face`, ouvrir **F2**.
2. Cliquer quatre fois, sans traîner. Observer sur le panneau du mannequin :
   `Hit −8`, `Hit −8`, `Hit −9`, `Hit −14`.
3. Le quatrième coup fait passer le mannequin en **`Knocked`**, puis
   **`GettingUp`**, puis `Idle` — la chaîne d'états spécifiée en 1.1, déclenchée
   cette fois par un vrai coup.
4. Sur le panneau F2, `Index de chaîne` monte de 1 à 4 et
   `Chaîne expire dans` se recharge à chaque impact.
5. Attendre plus de 0,55 s entre deux clics : l'index **repart à 1**.

**Ce que ça prouve.** Le frame data de `Balance.Melee` est appliqué tel quel, la
fenêtre de combo court depuis l'impact, et seul le dernier coup envoie au sol.

---

#### T1.2.3 — Le serveur refuse, et dit pourquoi

Chaque refus s'affiche sur la ligne **`Dernier refus`** du panneau.

| Manœuvre | Code attendu |
|---|---|
| Frapper `Dummy_Behind`, de l'autre côté du mur | `NoLineOfSight` |
| Se placer dos à un mannequin et frapper | `BehindAttacker` |
| Frapper à une dizaine de studs | *aucun rapport envoyé* — la hitbox est vide, rien ne part |
| Marteler le clic pendant l'armé | `local:StillInWindup` (refusé **avant** l'envoi) |
| Cliquer pendant un `Stunned` imposé par la console | `local:TransitionForbidden` |

Le préfixe `local:` distingue un refus prédit par le client d'un refus renvoyé par
le serveur. Un refus prédit n'a coûté aucun paquet — c'est le bénéfice direct du
partage de `StateMachine` entre les deux côtés.

**Ce que ça prouve.** La validation géométrique et temporelle est réelle, et
chaque rejet est explicable au joueur au lieu de ressembler à un coup perdu.

---

#### T1.2.4 — Voir le volume qui a été interrogé

1. Panneau F2 → **« Afficher les hitbox »** → 1.
2. Frapper. Une boîte rouge translucide apparaît un quart de seconde, à la
   position et aux dimensions **réellement** interrogées.
3. Régler **« Marge serveur de portée »** à 0, puis frapper à la limite : les
   coups commencent à être refusés en `TooFar`. Remonter à 2.5 : ils repassent.

**Ce que ça prouve.** Le client et le serveur parlent du même volume, et la marge
serveur est bien ce qui absorbe l'écart d'interpolation.

---

#### T1.2.5 — Un même coup ne touche jamais deux fois

Console sur **Client** :

```lua
local net = game.ReplicatedStorage.BanchouNet
-- Frapper un mannequin d'abord, puis renvoyer le même rapport plusieurs fois :
local report = net["Combat.HitReport"]
local dummy = workspace.TrainingGround.Dummy_Face
for _ = 1, 5 do
    report:FireServer({ seq = 999, clientTime = workspace:GetServerTimeNow(), targets = { dummy } })
end
```

Attendu : **aucun** dégât supplémentaire. Selon l'instant, le serveur répond
`ClaimTooLate` (le dernier coup est sorti de sa fenêtre active), `NoSwing`
(aucun coup n'a été lancé) ou ignore silencieusement le doublon si un coup est en
cours et que la cible est déjà dans `swingHits`.

Essayer aussi les rejets de forme, qui n'atteignent jamais le combat :

```lua
report:FireServer({ seq = 1, clientTime = 0, targets = { dummy, dummy } })  -- doublon
report:FireServer({ seq = 1, clientTime = 0, targets = {} })                -- liste vide
report:FireServer({ seq = 1, clientTime = 0, targets = { workspace } })     -- pas un Model combattant
```

Attendu côté **Server** : `payload malformé sur Combat.HitReport` pour les deux
premiers, `UnknownTarget` pour le troisième.

**Ce que ça prouve.** Le plafond de cibles, le refus des doublons et la
vérification du registre s'appliquent **avant** tout rembobinage — un rapport
abusif ne coûte pas un raycast.

---

#### T1.2.6 — Le rembobinage tient à 150 ms

1. Panneau F2 → **« Latence simulée »** → 150.
2. Frapper un mannequin en marchant latéralement.
3. Attendu : les coups **portent toujours**. La ligne `Hitbox p95` reste sous
   0,15 ms, `Écarts` de prédiction reste à 0 ou très bas.
4. Pousser la latence à **400** : les coups commencent à être refusés en
   `RewindExceeded` ou `StaleTimestamp` — le rembobinage est borné à 0,25 s et
   refuse d'aller plus loin, même pour un client honnête.

**Ce que ça prouve.** La compensation fonctionne dans la plage visée et **s'arrête
net** à sa borne, exactement comme ADR-001 le prévoit. Le refus à 400 ms n'est pas
un bug : c'est la borne qui fait son travail.

---

#### T1.2.7 — La prédiction locale et son écart

Section **Prédiction** du panneau : `État prédit` change **immédiatement** au
clic, avant toute réponse du serveur. `Écarts` compte les fois où l'autorité a
contredit la prédiction.

À latence simulée nulle, `Écarts` doit rester à **0** après plusieurs dizaines de
coups. Avec 150 ms, il peut monter de quelques unités — chaque écart y est
affiché sous la forme `prédit -> autorité`.

**Ce que ça prouve.** Le client et le serveur appliquent les mêmes règles. Ce
compteur est l'instrument du réglage de la parade en 1.4 : il transformera « ça a
l'air bizarre » en un nombre.

---

#### T1.2.8 — Le coût des hitbox tient le budget

Frapper une centaine de fois, puis console **Server** :

```lua
require(game.ServerScriptService.Server.Services.DiagnosticsService).dumpProfiler()
```

Attendu : une ligne `hit_validate` (coût de la validation serveur). Le coût
client des hitbox se lit directement sur la ligne `Hitbox p95` du panneau.
Budget : **p95 < 0,15 ms**.

---

### Correctif 1.2b — ancrage d'horloge et bouclage de la chaîne (ADR-017)

À rejouer après le correctif du refus systématique. **T1.2b.1 est le test qui
tranche** : si celui-là passe, la tranche 1.2 est réellement finie.

#### T1.2b.1 — Les coups portent enfin

1. Panneau **F2** → « Latence simulée » à **0**.
2. Se placer devant un mannequin, à portée, face à lui.
3. Cliquer **quatre fois** au rythme de l'animation (sans marteler).

Attendu, dans l'Output **Client** :

```
[CombatController] coup N envoyé, index 1, impact dans 100 ms
[CombatController] coup N : Hit sur Dummy_Face, cible à 92 PV
[CombatController] coup N+1 envoyé, index 2, ...
```

- la vie du mannequin descend **100 → 92 → 84 → 75 → 61** ;
- l'index de chaîne monte **1, 2, 3, 4** puis **repart à 1** ;
- le 4ᵉ coup envoie le mannequin **au sol** (`Knocked`) ;
- **aucun** `ClaimTooEarly` dans l'Output.

Si `ClaimTooEarly` réapparaît, la chronologie est de nouveau désancrée : c'est le
symptôme exact d'ADR-017, et il est systématique — pas un coup sur dix.

#### T1.2b.2 — Le correctif tient à 150 ms, qui est l'objectif du brief

Même manipulation avec la latence simulée à **150**. Attendu : **identique**. Les
dégâts tombent, les mêmes index défilent. C'est tout l'intérêt d'ancrer la trace
du coup sur l'horloge du client — la latence ne doit rien changer au fait qu'un
coup honnête porte.

Pousser ensuite à **400** : les refus reviennent, mais en `RewindExceeded` ou
`StaleTimestamp` — jamais en `ClaimTooEarly`. La distinction est le diagnostic :
la borne du rembobinage est un refus **assumé** (ADR-001), un décalage d'horloge
est un **bug**.

#### T1.2b.3 — La chaîne boucle, le finisher ne se répète pas

1. Latence à 0, se placer **hors de portée** de tout mannequin.
2. Frapper quatre fois dans le vide, au rythme (moins de 0,8 s entre deux coups).
3. Frapper une **cinquième** fois.

Attendu : le cinquième coup repart à l'**index 1**, pas à l'index 4.

C'était le bug caché sous le symptôme : `nextChainIndex` plafonnait au lieu de
boucler, donc rater le finisher permettait de rejouer le finisher — 14 dégâts et
un knockdown à volonté, tant que courait la fenêtre de coup manqué.

Vérifier ensuite l'inverse : frapper une fois dans le vide, **attendre plus de
0,8 s** (`WhiffResetDelay`), refrapper. Le coup repart à l'index 1 — la fenêtre de
reset a expiré.

#### T1.2b.4 — La tolérance de fin de fenêtre ne s'applique qu'à la fin

Console **Client**, en frappant un mannequin puis en rapportant hors fenêtre :

```lua
local net = game.ReplicatedStorage.BanchouNet
local dummy = workspace.TrainingGround.Dummy_Face
-- Revendiquer un contact bien avant la fin de l'armé du coup en cours :
net["Combat.HitReport"]:FireServer({
    seq = 4242,
    clientTime = workspace:GetServerTimeNow() - 0.20,
    targets = { dummy },
})
```

Attendu : `ClaimTooEarly` ou `NoSwing` selon l'instant — **jamais** un `Hit`.

**Ce que ça prouve.** La borne de début est stricte. Un attaquant ne peut pas
faire tomber son impact avant la fin de son armé, donc l'impact réel ne précède
jamais l'impact visible — c'est la condition pour que la parade de la tranche 1.4
soit lisible par le défenseur.

---

## Tranche 1.3 — garde, jauge, guard break, animations

Un mannequin de plus sur le terrain : **`Dummy_Guard`**, à droite (+16 X). Il tient
sa garde en permanence et la relève dès qu'il la perd. Son panneau affiche
`vie / max  ▌jauge`.

Il passe par le même chemin qu'un joueur — `requestTransition("Blocking")`,
cooldown de parade compris. Un mannequin dont l'état serait écrit à la main ne
prouverait rien sur les règles réelles.

#### T1.3.1 — La garde monte, et elle se lit

1. Appuyer sur **F** (maintenu).
2. Attendu **immédiatement**, sans attendre le serveur : les avant-bras montent
   devant le visage, le buste se replie légèrement.
3. Panneau **F2**, section **Garde** → « Demandée / accordée » passe à `oui / oui`
   en un aller-retour. Section **État** → `Blocking`.
4. Se déplacer : la vitesse tombe à 55 % (marche nettement plus lente).
5. Relâcher **F** : la pose redescend, l'état revient à `Idle`.

**Ce que ça prouve.** La prédiction locale monte la pose dans la frame de l'appui.
C'est la condition de la parade en 1.4 : à 150 ms de latence, attendre le serveur
ferait apparaître la garde après la fermeture de la fenêtre de 200 ms.

Vérifier la lisibilité, qui est le critère de la tranche : la pose doit être
reconnaissable **avant** 0,10 s. Régler la latence simulée à 300 dans F2 et
réappuyer — la pose doit monter **exactement aussi vite**. Si elle attend, la
prédiction ne fonctionne pas.

#### T1.3.2 — 35 % des dégâts en garde

Frapper **`Dummy_Guard`** une fois.

Attendu :
- panneau du mannequin : `Blocked −2` (8 × 0,35 = 2,8, affiché tronqué) ;
- la jauge passe de **60 à 52** — huit points, soit les dégâts **bruts**.

L'écart entre les deux nombres est le cœur de l'équilibrage : la vie ne prend que
la fraction réduite, la jauge prend le coup entier. Une garde ne devient pas plus
solide parce qu'elle protège bien.

Comparer avec `Dummy_Face` (sans garde) : `Hit −8`, jauge intacte.

#### T1.3.3 — La jauge se vide et la garde casse

Enchaîner sur `Dummy_Guard` sans laisser la jauge se régénérer.

Attendu, jauge de 60 : `−8, −8, −9, −14` sur la première chaîne, soit **21
restants**. La deuxième chaîne casse au deuxième ou troisième coup.

Pour aller plus vite, F2 → **« Jauge de garde »** à `20` : la rupture tombe alors
au troisième coup. C'est exactement l'usage prévu du panneau — régler en frappant,
sans rien recompiler. **« Régén. de la garde »**, **« Délai avant régén. de
garde »** et **« Vitesse en garde »** sont réglables de la même façon.

À la rupture :
- panneau du mannequin : `Blocked` puis l'état passe à **`Stunned`** ;
- les bras s'ouvrent en grand, le buste part en arrière — la pose la plus ample
  du jeu, elle annonce l'ouverture ;
- la jauge est **repartie à 60**, pas à 0 ;
- 1,6 s plus tard, l'état revient à `Idle` et le mannequin **remonte sa garde**.

**Ce que ça prouve.** La punition est l'étourdissement, pas des dégâts doublés.
Et la jauge restaurée empêche le guard break de devenir un verrou : sans elle, le
coup suivant recasserait immédiatement.

Frapper pendant les 1,6 s : les coups passent en `Hit` à dégâts pleins — c'est
l'ouverture, et c'est ce qui rend le guard break rentable.

#### T1.3.4 — La régénération, et son délai

1. Entamer la jauge de `Dummy_Guard` (deux ou trois coups).
2. **Ne plus frapper** et regarder le panneau.

Attendu : rien pendant **1,5 s**, puis remontée à **12 points par seconde**
jusqu'à 60. Un compte à rebours qui repart à chaque coup encaissé : frapper une
fois par seconde empêche toute régénération.

#### T1.3.5 — La garde ne s'ouvre pas n'importe quand

Trois refus à provoquer, tous lisibles dans **F2 → Garde → « Dernier refus »** :

1. **Pendant la récupération d'une attaque** — cliquer, puis appuyer sur F
   aussitôt. Attendu : `local:TransitionForbidden`. Rater un coup doit coûter ;
   la récupération n'est pas annulable par la garde (COMBAT.md §1.3).
2. **Trop tôt après une ouverture** — appuyer/relâcher F rapidement deux fois.
   Attendu : `local:ParryCooldown` sur la seconde (0,55 s).
3. **À endurance insuffisante** — dans F2, monter **« Seuil d'action »** à `50`,
   puis sprinter jusqu'à passer sous 50 et appuyer sur F. Attendu :
   `local:NotEnoughStamina`. Remettre le seuil à 10 ensuite.

   Passer par le réglage plutôt que par la valeur nominale n'est pas un
   contournement : à 10, le sprint s'arrête lui-même au seuil et l'endurance
   remonte dans la frame suivante, si bien que la fenêtre de refus dure quelques
   dizaines de millisecondes et ne s'observe pas de façon fiable.

Ces trois refus sont **prédits localement** : rien ne part sur le réseau. La ligne
« Demandée / accordée » reste à `non / non`.

#### T1.3.6 — Le repli procédural couvre tout ce qui est atteignable

**À regarder en premier : F2 → Performance → « Rig posable ».** Elle affiche
`R15 · 10/10 jointures` sur un rig complet.

| Ce qu'elle affiche | Ce que ça veut dire |
|---|---|
| `R15 · 10/10` (vert) | Tout est posable. |
| `R6 · 5/10` (orange) | Place réglée en R6. Les poses se jouent, mais **sans coudes ni taille** : les bras montent sans se replier. Lisible, moins expressif. Pour repasser en R15 : **Game Settings → Avatar → Avatar Type → R15**. |
| `… · 0/10` (rouge) | Aucune jointure ne résout — rien ne bougera. L'Output porte alors **le contenu du personnage** (nom et classe de chaque enfant) et la liste des classes de jointure acceptées : de quoi trancher entre un mauvais modèle, un modèle vide et une classe de jointure inconnue. |
| `moteur de pose non démarré` | `BindToRenderStep` n'a pas été posé : la panne est dans le chargement du contrôleur, pas dans le rig. |

Ces situations donnent le **même** symptôme à l'écran — un personnage immobile —
et ne se corrigent pas au même endroit. C'est ce qui a coûté deux recettes de
cette tranche.

Une ligne `[Rig]` apparaît dans l'Output **une fois par personnage**, au moment
où le rig atteint son compte complet, ou au plus tard 5 s après la liaison. Son
absence est en soi un signal : la liaison n'a jamais eu lieu.

Ensuite, **F2 → Performance → « Animations »** : affiche `0 asset(s) · N pose(s)
active(s)`. Zéro asset est l'état **normal** aujourd'hui — `Config/Animations` ne
contient que des `0`. Si cette ligne compte des poses actives alors que rien ne
bouge à l'écran, la panne est dans « Rig posable », pas dans le déclenchement.

Vérifier que chaque état atteignable produit quelque chose :

| Provoquer | Attendu à l'écran |
|---|---|
| Cliquer (chaîne de 4) | Quatre poses distinctes, d'amplitude croissante |
| Maintenir F | Garde levée, tenue |
| Se faire casser la garde *(sur le mannequin)* | Bras grand ouverts |
| Frapper 4 coups sur `Dummy_Face` | Le mannequin n'a pas de rig : pas de pose, seulement son panneau |

**Le boot est le vrai test de couverture.** `ConfigValidator` exige que chaque clé
d'animation soit servie par un asset, une pose, ou une déclaration `Pending`.
Pour le vérifier, supprimer temporairement l'entrée `ParrySuccess` de
`Poses.Pending` : le serveur doit **refuser de démarrer** avec
`Animations.ParrySuccess n'a ni asset (id = 0), ni pose procédurale, ni entrée
dans Poses.Pending`. Remettre l'entrée ensuite.

#### T1.3.7 — Ce qui n'est PAS encore visible

En test à deux clients Studio : **la garde de l'autre joueur ne se voit pas**.

Ce n'est pas un défaut de la tranche, c'est une dette datée et documentée
(PHASE1.md §5, ADR-018). `Motor6D.Transform` n'est pas répliqué, donc chaque
client doit poser lui-même les personnages qu'il affiche, et il lui faut leur état
— que le serveur n'envoie aujourd'hui qu'au propriétaire. C'est le **premier point
de la tranche 1.4**, avant la parade, parce que lire la garde adverse est
précisément ce sur quoi la parade se joue.

Ce qui est visible à deux dès maintenant : les dégâts, les verdicts, les états
dans F2, et le ralentissement en garde.

---

### Tranches suivantes


Les interrupteurs de développement restants sont livrés avec la tranche qui leur
donne quelque chose à faire, et pas avant : **forçage de la prédiction de parade**
et **forçage du refus serveur** en 1.4, **affichage des hitbox** en 1.2. Le
panneau n'affiche aujourd'hui que des valeurs qui existent réellement — l'écart de
prédiction apparaîtra en 1.2 avec la prédiction elle-même, le p95 du coût de
hitbox en 1.2 avec les hitbox.
