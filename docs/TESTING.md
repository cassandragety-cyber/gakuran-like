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

### Tranches suivantes

Les interrupteurs de développement restants sont livrés avec la tranche qui leur
donne quelque chose à faire, et pas avant : **forçage de la prédiction de parade**
et **forçage du refus serveur** en 1.4, **affichage des hitbox** en 1.2. Le
panneau n'affiche aujourd'hui que des valeurs qui existent réellement — l'écart de
prédiction apparaîtra en 1.2 avec la prédiction elle-même, le p95 du coût de
hitbox en 1.2 avec les hitbox.
