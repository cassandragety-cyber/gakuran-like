# PLAN — Architecture technique

> Nom de travail : `<NOM_DU_JEU>` (à figer — voir questions bloquantes).
> Document vivant : mis à jour à chaque fin de phase. Toute divergence entre ce
> fichier et le code est un bug de documentation à corriger immédiatement.

---

## 1. Principes structurants

1. **Data / logique / présentation sont trois couches étanches.**
   `Config/` ne contient aucune fonction. `Systems/` ne contient aucun appel à
   l'API Roblox (sauf types). `Services/` orchestre. `Controllers/` affiche et
   capture l'input.
2. **Le serveur est la seule source de vérité** sur : HP, dégâts, KO, monnaie,
   inventaire, style possédé, XP, stats. Le client *propose*, le serveur *dispose*.
3. **Un module = une responsabilité, 300 lignes max.** Au-delà, on découpe.
4. **Zéro connexion orpheline.** Toute `RBXScriptConnection`, tâche, instance
   créée dynamiquement vit dans un `Trove` détenu par l'objet qui l'a créée, et
   est détruite avec lui.
5. **Ajouter du contenu ≠ modifier du code.** Un style, un job, un item, une
   recette d'économie = un fichier dans `Config/`. Ce plan est conçu autour de
   cette contrainte (voir §5, grammaire de skills).

---

## 2. Arborescence

```
.
├── default.project.json          # mapping Rojo 7
├── wally.toml / wally.lock
├── selene.toml / .stylua.toml / roblox.yml (std selene généré)
├── docs/
│   ├── PLAN.md  DECISIONS.md  THREAT_MODEL.md  TESTING.md  RELEASE_CHECKLIST.md
└── src/
    ├── ReplicatedStorage/
    │   ├── Shared/               # pur, testable, zéro état global
    │   ├── Config/               # data only
    │   ├── Net/                  # déclaration + runtime des remotes
    │   └── Packages/             # wally (git-ignored)
    ├── ServerScriptService/
    │   ├── init.server.luau
    │   ├── Services/             # stateful, connaissent l'API Roblox
    │   └── Systems/              # pur, testable hors Roblox
    ├── StarterPlayer/StarterPlayerScripts/
    │   ├── init.client.luau
    │   ├── Controllers/
    │   └── UI/
    └── ServerStorage/            # assets serveur, dummies, prefabs
```

---

## 3. Modules — responsabilité en une ligne

### 3.1 `Shared/` (pur, aucun état global, importable des deux côtés)

| Module | Responsabilité |
|---|---|
| `Types.luau` | Toutes les types publiques partagées (profil, style, skill, paquets réseau). Aucun runtime. |
| `Enums.luau` | Unions de littéraux figées (`CombatState`, `Rarity`, `DamageKind`, `JobId`) + tables gelées associées. |
| `Loader.luau` | Chargeur générique ~80 lignes : découvre les modules d'un dossier, résout les dépendances déclarées, appelle `Init` puis `Start` en ordre topologique. Utilisé par le serveur (Services) **et** le client (Controllers). |
| `Trove.luau` (wally) | Nettoyage déterministe. Réexporté via `Shared/Cleanup.luau` pour figer l'API utilisée. |
| `Signal.luau` (wally) | Événements internes typés côté serveur/client. Jamais utilisé pour traverser le réseau. |
| `MathUtil.luau` | `lerp`, `clamp`, `approach`, `diminishing(value, k)` — courbe unique de rendements décroissants réutilisée par la progression. |
| `TableUtil.luau` | `deepFreeze`, `deepCopy`, `mergeInto`, `count`. Utilisé pour geler `Config/` au boot. |
| `RingBuffer.luau` | Buffer circulaire à taille fixe, générique. Support de l'historique de positions (lag comp) et du profiler. |
| `TokenBucket.luau` | Rate limiter pur (capacité, refill/s, `tryConsume(now, n)`). Aucune dépendance Roblox → testable. |
| `Clock.luau` | Temps de référence unique (`workspace:GetServerTimeNow()`), même API sur client et serveur. **Toute logique temporelle de combat passe par ici.** |
| `Profiler.luau` | Micro-profiler maison : `Profiler.scope("hitbox")`, agrège min/moy/p95/max sur fenêtre glissante, dump via commande admin. Coût nul quand désactivé. |
| `Result.luau` | `Ok(v)` / `Err(code, detail)` — type de retour de toutes les validations serveur, pour ne jamais confondre « refusé » et « erreur ». |
| `Log.luau` | Logging à niveaux avec préfixe de module, silencieux en prod sauf `warn`/`error`. |

### 3.2 `Config/` (data pure, gelée au boot, **zéro logique**)

| Module | Responsabilité |
|---|---|
| `Balance.luau` | Constantes de combat globales : fenêtre de combo, fenêtre de parry, durées de stun, poise, hitstop, régen d'endurance, seuils de garde. |
| `Progression.luau` | Courbe d'XP, gains de stats par entraînement, coefficients de rendements décroissants, plafonds. |
| `Economy.luau` | Prix, paies des jobs, plafonds/cooldowns de virement, coût de reroll en Yen. |
| `Monetization.luau` | Table des gamepasses et dev products (id, nom, effet déclaratif). |
| `RateLimits.luau` | Un bucket (capacité, refill) par remote, indexé par le même id que `Net/Definitions`. |
| `Styles/init.luau` | Agrège et gèle tous les styles ; valide le schéma au boot (crash explicite si un style est malformé). |
| `Styles/Rarity.luau` | Table de raretés (poids 60/25/10/4/1) + configuration du pity. |
| `Styles/<Id>.luau` | Un fichier par style : `{ id, name, rarity, weight, statMods, skills, animPack, vfxPack }`. |
| `Jobs/<Id>.luau` | Un fichier par métier : étapes, timers, paie, conditions d'échec. |
| `Items/<Id>.luau` | Cosmétiques et consommables (id, slot, rareté, prix, source). |
| `World.luau` | Points de spawn, zones (école, konbini, terrain de basket), rayons de streaming persistants. |

### 3.3 `Net/`

| Module | Responsabilité |
|---|---|
| `Definitions.luau` | **Le contrat réseau.** Pour chaque remote : id, direction, type du payload, validateur de forme, bucket de rate-limit, et si l'appel est autorisé hors combat. |
| `init.luau` | Runtime : crée les `RemoteEvent`/`RemoteFunction` d'après `Definitions`, expose une API typée (`Net.Server.CombatHit:OnRequest(fn)`, `Net.Client.CombatHit:Fire(payload)`), applique la chaîne middleware **rate-limit → validation de forme → handler**. Un payload invalide n'atteint jamais un service. |
| `Middleware.luau` | Les middlewares eux-mêmes (bucket, shape check, journalisation d'abus, kick soft). |

Remotes prévus (liste figée en Phase 0, complétée par phase — chaque ajout
implique une entrée dans `THREAT_MODEL.md`) :
`Combat.Attack`, `Combat.HitReport`, `Combat.BlockState`, `Combat.Parry`,
`Combat.Dash`, `Combat.Skill`, `Style.Reroll`, `Stats.TrainInput`,
`Economy.JobAction`, `Economy.Transfer`, `Phone.Open`, `Gang.Action`,
`Emote.Play`, `Customization.Apply`, `Shop.Purchase`.

### 3.4 `ServerScriptService/Systems/` (pur — testable sans Roblox)

| Module | Responsabilité |
|---|---|
| `ComboMachine.luau` | Machine à états du chain M1 : index de coup, fenêtre de combo, reset, éligibilité du coup suivant. |
| `CombatResolver.luau` | Applique un `SkillSpec` résolu à une cible : ordre block → parry → i-frames → dégâts → poise → statuts. Retourne une liste d'effets, n'écrit rien. |
| `HitValidator.luau` | Décide si un hit rapporté est plausible : distance, angle, cohérence d'état, fraîcheur du timestamp, cooldown. Retourne `Result`. |
| `StaminaModel.luau` | Consommation/régen d'endurance en fonction de l'état (sprint, dash, skill, hors combat). |
| `RollTable.luau` | Tirage pondéré déterministe (seed injectée) + pity. Testable exhaustivement. |
| `ProgressionMath.luau` | XP → niveau, gains de stats avec rendements décroissants, bornes. |
| `TransferGuard.luau` | Règles anti-farm des virements : plafond glissant, cooldown, détection d'aller-retour. |
| `SchemaMigrations.luau` | Chaîne de migrations de profil `v(n) → v(n+1)`, pure et testable sur des fixtures. |

### 3.5 `ServerScriptService/Services/` (stateful, API Roblox)

| Service | Responsabilité | Dépend de |
|---|---|---|
| `DataService` | ProfileStore : session lock, chargement, migration, autosave, `BindToClose`, kick propre si échec. **Aucun autre service ne touche au datastore.** | — |
| `CharacterService` | Cycle de vie du personnage : spawn, humanoïde, `Animator`, application des statMods, ragdoll. | DataService |
| `StateService` | État de combat autoritatif par joueur (HP, endurance, poise, i-frames, état d'anim) + historique de positions (`RingBuffer`) pour la lag comp. | CharacterService |
| `CombatService` | Orchestre attaques/skills : reçoit les demandes, appelle `HitValidator` + `CombatResolver`, applique les effets, réplique le feedback. Ne connaît **aucun** style nommément. | StateService, StyleService |
| `StyleService` | Possession et roll/reroll de style, résolution `styleId → SkillSpec`, application des statMods. | DataService, EconomyService |
| `StatsService` | Entraînement (mini-jeu de timing), gains de stats, niveau/XP. | DataService, StateService |
| `EconomyService` | Yen : crédit/débit, virements (via `TransferGuard`), paies de jobs. Seule porte d'entrée de la monnaie. | DataService |
| `JobService` | Boucles de métiers (livraison, konbini, flyers) : état de mission, validation des étapes, paiement via EconomyService. | EconomyService, DataService |
| `GangService` | Crews : création, invitations, rôles ; partage cross-server léger via `MemoryStoreService`. | DataService |
| `MonetizationService` | Gamepasses et dev products : `ProcessReceipt` idempotent, application des effets déclarés dans `Config/Monetization`. | DataService, StyleService |
| `AnalyticsService` | Événements maison bufferisés puis flush (`session_start`, `first_fight`, `style_rolled`, `purchase`, D1). | DataService |
| `AntiCheatService` | Surveillance transverse : vitesse, téléportation, abus de remotes signalés par le middleware ; escalade log → throttle → kick. | StateService |
| `AdminService` | Commandes de debug (dump profiler, spawn dummy, set stats) — **restreintes par liste d'UserId, désactivées en prod par un flag.** | tous |

### 3.6 Client — `Controllers/`

| Controller | Responsabilité |
|---|---|
| `InputController` | Abstraction clavier/gamepad/tactile → actions nommées (`Attack`, `Block`, `Dash`, `Skill1..4`). Seul endroit qui connaît `UserInputService`. |
| `CombatController` | Prédiction locale : joue l'anim, détecte le hit (`GetPartBoundsInBox` + `OverlapParams`), envoie la demande, réconcilie avec la réponse serveur. |
| `HitboxDebugController` | Visualisation des hitbox + branchement du `Profiler` (activable en Studio uniquement). |
| `FeedbackController` | Hitstop, shake, VFX, SFX, indicateurs de parry/guard break — la « lisibilité » du combat vit ici. |
| `CameraController` | Caméra de combat (léger lock-on souple), sensibilité paramétrable. |
| `UIController` | Monte/démonte les écrans, gère la pile et le focus (important sur mobile). |
| `PhoneController` | Le téléphone : navigation entre apps, état, appels réseau des jobs/banque. |
| `PreloadController` | `ContentProvider:PreloadAsync` des anims/SFX/VFX de combat au join, avec écran de chargement non bloquant. |
| `EmoteController` | Emotes, `/me`, assises (bancs). |
| `SettingsController` | Sensibilité, qualité, keybinds — persistés côté profil. |

### 3.7 Client — `UI/`

Un dossier par écran (`HUD/`, `Phone/`, `StyleRoll/`, `Training/`, `Shop/`,
`Gang/`), plus `UI/Components/` (bouton, liste, modale, jauge) et
`UI/Theme.luau` (couleurs, marges, tailles tactiles minimales 44px).

---

## 4. Graphe de dépendances (sens des flèches = « dépend de »)

```
Controllers ─────┐
                 ├──▶ Net ──▶ Config ──▶ Shared
Services ────────┘            ▲
   │                          │
   └──▶ Systems ──────────────┘        (Systems ne connaît que Shared + Config)
```

Règles vérifiées par revue (et à terme par un test de lint) :
- `Shared` ne dépend de rien du projet.
- `Config` ne dépend que de `Shared/Types`.
- `Systems` ne dépend que de `Shared` + `Config`. **Aucun `game:GetService`.**
- `Services` peut dépendre de tout, mais jamais d'un `Controller`.
- Aucune dépendance circulaire entre services : le `Loader` échoue au boot si le
  tri topologique en détecte une.

---

## 5. La pièce maîtresse : grammaire de skills (pourquoi un 16e style = 1 fichier)

`CombatService` n'interprète pas des styles, il interprète une **grammaire
d'effets**. Un style est une donnée décrivant des phases et des effets :

```luau
type HitboxSpec = {
    shape: "Box" | "Sphere",
    size: Vector3,
    offset: CFrame,          -- relatif au HumanoidRootPart de l'attaquant
    maxTargets: number,
}

type EffectSpec =
      { kind: "Damage", amount: number, poise: number, hitstop: number }
    | { kind: "Knockback", speed: number, vertical: number }
    | { kind: "Knockdown", ragdollTime: number }
    | { kind: "Stun", duration: number }
    | { kind: "Status", id: string, duration: number, stacks: number }
    | { kind: "Move", distance: number, iframes: number }
    | { kind: "Heal", amount: number }

type SkillSpec = {
    id: string,
    slot: "M1" | "Z" | "X" | "C" | "V",
    windup: number, active: number, recovery: number,
    cooldown: number, staminaCost: number,
    hitbox: HitboxSpec?,
    onCast: { EffectSpec },   -- appliqué au lanceur
    onHit: { EffectSpec },    -- appliqué aux cibles touchées
    cancelable: boolean,
    anim: string, vfx: string?, sfx: string?,
}
```

Conséquence assumée et **testée** : ajouter un style = créer
`Config/Styles/<Id>.luau`. Le style de test `Debug_Dummy` sera livré en Phase 2
comme preuve, avec le diff à l'appui (0 ligne modifiée dans `CombatService`).

**Limite honnête :** si un style requiert un effet d'un *genre nouveau*
(ex. `Projectile`, `Teleport`), il faut ajouter ce `kind` à la grammaire et son
interpréteur — c'est du code, une fois, pas par style. La Phase 1 livre le jeu
d'effets ci-dessus ; la Phase 6 ajoutera au plus 2-3 `kind` supplémentaires.

---

## 6. Modèle réseau du combat (résumé — détail en Phase 1)

1. Client : input → vérifie localement cooldown/endurance (pour le *feel*), joue
   l'anim, ouvre la hitbox à la frame d'impact, collecte les cibles.
2. Client → serveur : `{ skillId, seq, clientTime, targets: {Player} }`.
   **Aucun montant de dégât, aucun id de dégât, jamais.**
3. Serveur : rate-limit → forme → `HitValidator` :
   - `clientTime` dans une fenêtre de tolérance (± RTT/2 + marge),
   - position de la cible **au moment `clientTime`** relue dans le `RingBuffer`
     (lag compensation, rewind borné à 250 ms),
   - distance ≤ portée de la hitbox × marge, ligne de vue, cooldown écoulé,
     endurance suffisante, état d'animation cohérent.
4. Serveur : `CombatResolver` → effets → réplication du feedback à tous.

Le **parry** est arbitré serveur : le client envoie l'*ouverture* de sa fenêtre
de block avec un timestamp `Clock` ; le serveur compare la fenêtre de 0.2 s à
l'instant d'impact validé. Le client ne déclare jamais « j'ai parry ».

Critère d'acceptation Phase 1 : deux clients simulés à 150 ms (Studio, throttling
réseau) parry de façon fiable, zéro hit fantôme sur 100 échanges.

---

## 7. Budgets à tenir (mesurés, pas espérés)

| Budget | Cible | Comment on le mesure |
|---|---|---|
| Frame client | 16.6 ms sur mobile milieu de gamme, 20 joueurs visibles | `Profiler` + MicroProfiler Studio |
| Coût hitbox | < 0.15 ms par ouverture de hitbox | scope `Profiler.scope("hitbox")` (exigence §6 du brief) |
| Remotes | < 25 paquets/s/joueur en combat | compteur dans `Net/Middleware` |
| Mémoire | plateau stable après 30 min, ± 5 % | Developer Console, `Trove` obligatoire |
| Boucles | 0 occurrence de `while true do wait()` | règle Selene custom |

---

## 8. Découpage en phases (livrables testables, validation entre chaque)

| Phase | Livrable jouable | Sortie |
|---|---|---|
| 0 | Rojo sync, Loader, Net typé, lint/format, README | log `[Boot] OK` serveur + client |
| 1 | M1 chain, block, parry, dash, endurance, dummy d'entraînement | duel testable à 2 clients Studio |
| 2 | ProfileStore + migrations, roll/reroll, 3 styles + `Debug_Dummy` | données persistantes, gacha jouable |
| 3 | Map bloc-out, streaming, spawns, salle de sport + mini-jeu de stats | monde parcourable |
| 4 | Téléphone, banque, 3 jobs, économie | boucle Yen complète |
| 5 | Gangs, emotes, `/me`, basket, musique, assises | vie sociale |
| 6 | 12 styles restants + passe d'équilibrage | 15+ styles |
| 7 | Monétisation, analytics, optimisation mobile, checklist de publication | build publiable |

---

## 9. Fichiers de documentation maintenus en continu

- `docs/DECISIONS.md` — journal des décisions structurantes (append-only).
- `docs/THREAT_MODEL.md` — un remote = une ligne = une contre-mesure (dès Phase 0).
- `docs/TESTING.md` — procédure de test dans Studio, par phase.
- `docs/RELEASE_CHECKLIST.md` — créé en Phase 7.
