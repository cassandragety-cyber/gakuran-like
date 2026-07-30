# PHASE 1 — Conception : structure des modules et ordre de construction

Document de conception, écrit **avant** toute logique de combat. La machine à
états elle-même est spécifiée dans [COMBAT.md §1](COMBAT.md). Ici : quels
modules existent, ce qu'ils reçoivent, ce qu'ils rendent, et dans quel ordre on
les construit.

Rappel de priorité produit : **la parade est la mécanique signature.** Elle ne
peut pas être la première tranche livrée — il faut un coup et une garde pour
avoir quelque chose à parer — mais les tranches 1.1 à 1.3 sont volontairement
réduites au minimum utile pour l'atteindre vite, et la tranche 1.4 reçoit la
plus grosse part du temps de la phase. Aucune tranche ultérieure ne démarre
avant que la 1.4 ne soit jugée irréprochable.

---

## 1. L'idée structurante : la balance est un paramètre, pas une variable globale

Chaque fonction pure de combat reçoit la table d'équilibrage **en argument** :

```luau
CombatResolver.resolve(step, defender, now, balance)
HitValidator.check(claim, balance)
StateMachine.canRequest(state, target, context)  -- context.balance
```

Aucun module de `Shared/Combat/` ni de `Systems/` ne fait de `require` sur
`Config.Balance`. Une seule décision, trois bénéfices qui sont exactement les
trois besoins de cette phase :

1. **Tests.** On peut appeler `CombatResolver.resolve` avec une fenêtre de
   parade fabriquée à 0,001 s ou à 10 s pour balayer les cas limites, sans
   toucher au jeu ni à un fichier de config.
2. **Réglage à chaud.** Le panneau F2 modifie la table passée en argument. Aucun
   code de gameplay n'a besoin de savoir qu'un réglage a changé.
3. **Le gel de `Config/` survit.** `Config.Balance` reste `table.freeze`é comme
   en Phase 0 : c'est la référence immuable et la source du bouton « réinitialiser ».
   Ce qui circule dans le combat est une copie, gérée par `TuningService`.

Sans cette injection, le réglage à chaud aurait exigé de dégeler `Config/`, ce
qui aurait supprimé la garantie posée en Phase 0. Détail dans ADR-011.

---

## 2. Modules — ce qui bouge par rapport au PLAN

### 2.1 Nouveau : `Shared/Combat/` (pur, partagé client **et** serveur)

C'est le changement de structure important de cette phase. Le client doit
prédire avec **exactement** les mêmes règles que celles que le serveur arbitre ;
deux implémentations des mêmes règles divergent toujours finalement sur un cas
limite, et cette divergence se manifeste au joueur comme une injustice.

| Module | Responsabilité | Signatures principales |
|---|---|---|
| `StateMachine.luau` | Les huit états, la table de transitions, les priorités. Ne connaît ni le réseau ni les personnages. | `phaseOf(state, now, balance): Phase?`<br>`canRequest(state, target, context): Result<true>`<br>`enter(state, target, context): CombatState`<br>`impose(state, target, duration, now): CombatState`<br>`expire(state, now): CombatState?`<br>`priorityOf(name): number` |
| `Frames.luau` | Lecture du frame data et progression de la chaîne. Séparé de `StateMachine` parce que ce sont deux questions : la machine décide de la *légalité* d'une transition, `Frames` décide d'*où on en est* dans un coup. | `phaseOf(state, now, balance): Phase?`<br>`stepFor(index, balance): MeleeStep?`<br>`nextChainIndex(state, now, balance): number`<br>`canChain(state, context): Result<true>` |
| `StaminaModel.luau` | Consommation et régénération selon le tag de combat. | `step(stamina, now, dt, drainPerSecond, balance): number`<br>`canAfford(stamina, cost): boolean`<br>`spend(stamina, cost): number`<br>`canSprint(stamina, balance): boolean` |

`CombatState` est **entièrement sérialisable** — pas de référence d'instance, pas
de closure :

```luau
export type CombatState = {
    name: StateName,        -- "Idle" | "Attacking" | ...
    enteredAt: number,      -- horloge serveur commune
    expiresAt: number?,     -- nil si l'état est maintenu (Blocking)
    windowUntil: number?,   -- fin de fenêtre de parade / i-frames / invulnérabilité
    chainIndex: number,     -- 0 hors chaîne
    chainDeadline: number?, -- instant au-delà duquel la chaîne repart au coup 1
}
```

Conséquence directement exploitable : cet état s'affiche tel quel dans le
panneau F2, se réplique tel quel, et se **compare** entre client et serveur pour
détecter une divergence de prédiction. Le débogage de la parade repose là-dessus.

### 2.2 Nouveau : `Systems/` (pur, serveur uniquement)

Ces trois modules n'ont rien à faire côté client : ils constituent l'autorité.

| Module | Responsabilité | Signature |
|---|---|---|
| `Rewind.luau` | Interpole l'historique de positions à un instant passé, borné. | `sampleAt(history, t, maxRewind): Snapshot?` |
| `HitValidator.luau` | Un coup rapporté est-il plausible ? | `check(claim, balance): Result<true>` — codes : `TooFar`, `BehindAttacker`, `NoLineOfSight`, `StaleTimestamp`, `WrongPhase`, `AlreadyHitThisSwing`, `RewindExceeded` |
| `CombatResolver.luau` | **L'arbitre de la parade.** Décide parade / blocage / coup et produit la liste d'effets. | `resolve(step, defender, now, balance): Outcome` |
| `TuningGuard.luau` | Un réglage à chaud est-il autorisé et dans les bornes ? | `check(path, value): Result<number>`<br>`resolvePath(balance, path): (table, key)?` |

```luau
export type DefenderView = {
    state: CombatState,
    guard: number,
    invulnerableUntil: number?,
}

export type Outcome = {
    verdict: "Parried" | "Blocked" | "Hit" | "Ignored",
    damage: number,
    effects: { EffectSpec },
    attackerStun: number?,
    guardRemaining: number,
}
```

**C'est ici que se gagne l'irréprochabilité de la parade.** `resolve` est une
fonction pure de (instant d'impact, instant d'ouverture de garde, équilibrage)
vers un verdict. Elle se teste exhaustivement, sans partie lancée, sans réseau,
sans deux clients : on peut balayer l'impact milliseconde par milliseconde
autour de la fenêtre et vérifier que la frontière tombe exactement où elle doit.
Aucune autre organisation du code ne permet ça.

### 2.3 Services (avec état, API Roblox)

| Service | Responsabilité | Dépend de |
|---|---|---|
| `CharacterService` | Spawn, `Humanoid`, `Animator`, ragdoll, application des `statMods`. Émet `onCharacterAdded` / `onCharacterRemoving`. | SessionService |
| `StateService` | **Détient l'état autoritatif** : `CombatState`, endurance, jauge de garde, PV, et l'historique de positions par joueur. Un unique `Heartbeat` fait expirer les états échus. | CharacterService |
| `CombatService` | Orchestre : reçoit les demandes, appelle `StateMachine` → `Rewind` → `HitValidator` → `CombatResolver`, applique les effets, réplique les verdicts. Ne contient **aucune** valeur numérique. | StateService, TuningService |
| `DummyService` | Mannequin d'entraînement : spawn, encaissement, remise à zéro, et affichage du dernier verdict reçu au-dessus de sa tête. | StateService, CombatService |
| `TuningService` | La copie vivante de l'équilibrage, le remote de réglage, la diffusion aux clients, la réinitialisation. | — |

### 2.4 Controllers

| Controller | Responsabilité |
|---|---|
| `InputController` | Clavier / gamepad / tactile → actions nommées (`Attack`, `Block`, `Dash`, `ToggleDebug`). Seul module qui connaît `UserInputService`. |
| `CombatController` | Prédiction locale via `Shared/Combat`, détection de contact, envoi des demandes, réconciliation. |
| `HitboxDetector` | `GetPartBoundsInBox` + `OverlapParams`, filtrage du personnage propre, mesure via `Profiler.record("hitbox", …)`. |
| `AnimationController` | Joue une entrée de `Config/Animations` ; si `id == 0`, joue le mouvement procédural de même durée. Le reste du code demande `"M1_3"`, jamais un asset id. |
| `FeedbackController` | Hitstop, éclats, sons, et **le retour en deux temps de la parade** (COMBAT.md §5). |
| `DebugPanelController` | Le panneau F2 (§4). |

### 2.5 Graphe de dépendances

```
Controllers ─────┐
                 ├──▶ Net ──▶ Config
Services ────────┤
                 ├──▶ Shared/Combat ◀──── Controllers   (les MÊMES règles)
Systems ─────────┘            │
                              └──▶ Shared (Clock, Result, RingBuffer, MathUtil)
```

Règles inchangées, une ajoutée : **`Shared/Combat/` ne require ni `Config`, ni
`Net`, ni un service.** Il ne reçoit que des arguments. C'est ce qui garantit
qu'il est réellement testable et réellement partagé.

---

## 3. Remotes à ajouter

Le client envoie une **intention**, jamais un résultat. Deux points méritent
d'être explicites :

- **Aucune demande d'attaque ne porte l'index de chaîne.** Le serveur le dérive
  de l'état qu'il détient. Un client qui pourrait annoncer « je frappe le coup 4 »
  aurait un knockdown à la demande (ADR-012).
- **La direction du dash est un entier de 1 à 4**, pas un `Vector3`. Un vecteur
  libre est un vecteur de téléportation.

| Remote | Sens | Payload | Cadence |
|---|---|---|---|
| `Move.SprintState` | C→S | `{ active: boolean, clientTime }` | 6 rafale, 3/s |
| `Combat.Attack` | C→S | `{ seq, clientTime }` | 8 rafale, 4/s |
| `Combat.HitReport` | C→S | `{ seq, clientTime, targets: {Player} }` (≤ `MaxTargetsPerSwing`) | 8 rafale, 4/s |
| `Combat.BlockState` | C→S | `{ open: boolean, clientTime }` | 6 rafale, 3/s |
| `Combat.Dash` | C→S | `{ direction: 1..4, clientTime }` | 3 rafale, 1/s |
| `Combat.StateSync` | S→C | `{ userId, state: CombatState, stamina, guard, health }` | — |
| `Combat.HitResult` | S→C | `{ seq, verdict, damage, attackerUserId, defenderUserId }` | — |
| `Debug.SetTuning` | C→S | `{ path: string, value: number }` — **`devOnly`** | 20 rafale, 10/s |
| `Debug.TuningSync` | S→C | `{ path: string, value: number }` — **`devOnly`** | — |

Chacun reçoit sa ligne dans [THREAT_MODEL.md](THREAT_MODEL.md) au moment de son
implémentation, pas après.

### `devOnly` : le remote n'existe pas en production

`Net/Definitions` gagne un champ `devOnly: boolean?`. `Net.initServer()`
**ne crée pas l'instance** `RemoteEvent` correspondante quand le serveur n'est
ni en Studio ni autorisé par `Config/Debug.AdminUserIds`. Un remote qui peut
réécrire l'équilibrage ne doit pas simplement refuser les appels en
production : il ne doit pas être là pour être trouvé (ADR-013).

---

## 4. Le panneau de debug (F2)

Objectif : passer des heures sur le mannequin sans jamais éditer un `.luau` ni
relancer.

### Affichage — colonne de gauche, temps réel

- **État** : nom, phase (`armé` / `actif` / `récup.`), temps restant sur
  l'échéance, index de chaîne, temps restant de fenêtre de combo.
- **Ressources** : PV, endurance, jauge de garde, poise, i-frames actives.
- **Parade** : fenêtre ouverte oui/non, temps restant, cooldown restant.
- **Réseau** : RTT médian, délai aller mesuré par le serveur, verdict du dernier
  coup, et **écart de prédiction** — l'état prédit par le client à côté de
  l'état autoritatif reçu, surligné quand les deux diffèrent. C'est l'instrument
  du cas 2 de COMBAT.md §5.
- **Performance** : p95 du coût d'ouverture de hitbox, issu du `Profiler`.

### Réglage — colonne de droite

Une ligne par valeur réglable, avec curseur et saisie numérique. La liste des
valeurs et leurs bornes vivent dans `Config/Debug.luau` :

```luau
Tunables = {
    ["Parry.Window"]          = { min = 0.05, max = 0.60 },
    ["Parry.AttackerStun"]    = { min = 0.20, max = 3.00 },
    ["Parry.Cooldown"]        = { min = 0.00, max = 2.00 },
    ["Combat.ComboWindow"]    = { min = 0.20, max = 1.20 },
    ["Block.DamageMultiplier"]= { min = 0.00, max = 1.00 },
    ["Block.GuardHealth"]     = { min = 10,   max = 200  },
    ["Dash.Distance"]         = { min = 4,    max = 40   },
    ["Dash.InvulnerabilityDuration"] = { min = 0, max = 0.50 },
    ["Melee.1.windup"]        = { min = 0.05, max = 0.60 },
    -- … une entrée par valeur qu'on accepte de bouger à chaud
}
```

Une valeur absente de cette table est **refusée** par `TuningGuard`, même en
Studio : c'est une liste blanche, pas une liste noire. Les durées d'animation
n'y figurent pas, parce que les modifier à chaud casserait le contrat vérifié au
boot en Phase 0 — les toucher exige de passer par les fichiers et un
redémarrage, ce qui est exactement l'intention.

### Interrupteurs de développement

- **Latence simulée (ms)** — retarde symétriquement le traitement des demandes
  entrantes et l'envoi des verdicts, côté serveur. C'est ce qui permet de tenir
  le critère d'acceptation à 150 ms sans deux machines distantes.
- **Forcer la prédiction de parade** — le client prédit une parade sur *tout*
  coup entrant pendant sa garde. Chaque échange devient alors une occurrence du
  cas 2 (« le client a cru parer, le serveur dit non »), qui est trop rare pour
  être observé au hasard mais doit être irréprochable à l'écran.
- **Forcer le refus serveur** — le serveur renvoie systématiquement `Blocked` au
  lieu de `Parried`. Le pendant du précédent, vu depuis l'autorité.
- **Afficher les hitbox** — volumes rendus, avec leur fenêtre d'ouverture.
- **Réinitialiser l'équilibrage** — recopie `Config.Balance` dans la table
  vivante et rediffuse. Un après-midi de réglages se jette en un clic.

### Diffusion

Un réglage modifié est appliqué côté serveur puis diffusé par
`Debug.TuningSync`. **Cette diffusion n'est pas un confort : elle est
nécessaire.** Le client prédit avec sa propre copie de l'équilibrage ; si les
deux copies divergent, la prédiction diverge, et on passerait des heures à
déboguer une désynchronisation qu'on aurait soi-même introduite en bougeant un
curseur.

---

## 5. Ordre de construction

Chaque tranche est jouable et testable à sa livraison, avec sa procédure ajoutée
à `docs/TESTING.md`.

| # | Contenu | Critère d'acceptation |
|---|---|---|
| **1.1** ✅ | `CharacterService`, `StateService`, `MovementService`, `StateMachine`, `Frames`, `StaminaModel`, `TuningService`, sprint, panneau F2 complet, latence simulée | Livré. Voir `docs/TESTING.md` §1.1. **Le panneau arrive en premier parce que tout le reste se règle avec.** |
| **1.2** | `Combat.Attack` + `HitReport`, `HitboxDetector`, `Rewind`, `HitValidator`, `DummyService` | La chaîne de 4 coups s'enchaîne dans la fenêtre de 0,55 s ; le mannequin perd les PV de `Balance.Melee` ; un coup à travers un mur ou dans le dos est refusé avec son code d'erreur. |
| **1.3** | Garde, jauge, guard break, `CombatResolver` (branches `Blocked` / `Hit`) | 35 % des dégâts en garde ; la jauge se vide, le guard break impose 1,6 s de `Stunned` ; la garde ne s'ouvre pas depuis la récupération d'une attaque. |
| **1.4** | **Parade** : branche `Parried`, arbitrage horodaté, retour en deux temps, les quatre cas de réconciliation, les interrupteurs de dev | Les quatre cas de COMBAT.md §5 se déclenchent à volonté et **aucun** ne produit d'animation contredite en cours de lecture. Tests exhaustifs de `CombatResolver.resolve` sur la frontière de fenêtre. **Tranche la plus longue de la phase.** |
| **1.5** | Dash, i-frames, annulation de récupération, coûts d'endurance | Le dash annule une récupération `cancelable` mais jamais un armé ; les i-frames couvrent 0,12 s à partir du départ ; à moins de 10 d'endurance, refus. |
| **1.6** | Knockdown, ragdoll, `GettingUp`, KO, respawn | Le 4e coup envoie au sol ; l'invulnérabilité de relevage empêche l'enchaînement infini ; le KO déclenche un respawn propre. |
| **1.7** | Recette réseau et performance | Critère du brief : deux clients à 150 ms de latence simulée, 100 échanges, 100 % des parades dans la fenêtre reconnues, zéro hit fantôme. Coût de hitbox p95 < 0,15 ms. |

Rien de la Phase 2 ne commence avant que 1.4 et 1.7 ne soient tous les deux
verts.

---

## 6. Ce que cette conception ne tranche pas encore

| Question | Quand | Pourquoi on attend |
|---|---|---|
| Ragdoll : `PhysicsService` dédié ou contraintes sur R15 | 1.6 | Le choix dépend du coût mesuré sur mobile avec 20 personnages ; on mesurera avec le `Profiler` avant de choisir |
| Caméra de combat (lock-on souple) | fin de Phase 1 ou Phase 3 | À juger une fois la parade réglée : si viser reste confortable sans, on n'ajoute pas de système |
| Interpolation ou extrapolation dans `Rewind` | 1.2 | Deux lignes de code d'écart ; on tranchera avec des mesures réelles plutôt qu'en théorie |
