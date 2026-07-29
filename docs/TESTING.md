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

## Phase 1 — Combat (à venir)

Les interrupteurs de développement suivants seront livrés avec la Phase 1 pour
rendre reproductibles les cas décrits au §5 de [COMBAT.md](COMBAT.md) :

- **latence simulée** configurable côté serveur, pour tenir le critère
  d'acceptation à 150 ms sans deux machines distantes ;
- **forçage de la prédiction de parade** côté client, pour provoquer à volonté
  le cas 2 (« le client a cru parer, le serveur dit non »), qui est trop rare
  pour être observé au hasard mais doit être irréprochable à l'écran ;
- **affichage des hitbox** et branchement du profiler sur leur coût.
