# COMBAT — spécification

Document de référence du combat. Écrit en Phase 0, implémenté en Phase 1 ; il
fait autorité sur le comportement attendu, y compris dans les cas de désaccord
entre client et serveur.

Toutes les valeurs chiffrées citées ici viennent de
`src/ReplicatedStorage/Config/Balance.luau` et n'y sont recopiées que pour la
lisibilité. **En cas de divergence, c'est le fichier de configuration qui a
raison**, et ce document qui doit être corrigé.

---

## 1. Machine à états

### 1.1 Les huit états

Un joueur est à tout instant dans exactement un état. La parade n'en est
délibérément **pas** un : c'est une fenêtre à l'intérieur de `Blocking`. En
faire un état séparé obligerait à décider de son entrée au moment de l'appui,
donc côté client — exactement ce qu'ADR-002 interdit.

| État | Durée | Peut attaquer | Peut garder | Peut dasher | Dégâts subis |
|---|---|---|---|---|---|
| `Idle` | — | oui | oui | oui | pleins |
| `Attacking` | armé + actif + récup. | seulement en enchaînement | non | en récup. si `cancelable` | pleins |
| `Blocking` | tant que maintenu | non | — | oui | × 0,35, ou **0 dans la fenêtre de parade** |
| `Dashing` | 0,20 s | non | non | non | 0 pendant 0,12 s, puis pleins |
| `Stunned` | 1,2 s (paré) / 1,6 s (garde brisée) | non | non | non | pleins |
| `Knocked` | 1,1 s | non | non | non | pleins |
| `GettingUp` | 0,60 s | non | non | non | 0 pendant 0,35 s |
| `Downed` | jusqu'au respawn | non | non | non | — |

`GettingUp` est séparé de `Knocked` parce que les deux n'ont ni la même
vulnérabilité ni la même animation : c'est l'invulnérabilité de relevage qui
empêche le viol de knockdown en boucle.

### 1.2 Le modèle temporel : des échéances, pas des minuteurs

Chaque état porte trois champs de temps, tous sur l'horloge serveur commune :

```
enteredAt      -- instant d'entrée
expiresAt      -- instant de sortie automatique (nil si l'état est maintenu)
windowUntil    -- fin de la sous-fenêtre de l'état (parade, i-frames, invuln.)
chainIndex     -- coup courant de la chaîne, 0 hors chaîne
chainDeadline  -- instant au-delà duquel la chaîne repart au premier coup
```

`chainDeadline` remplace l'idée initiale d'un « instant du dernier impact ». Il
est posé quand un coup se **résout** : à `impact + ComboWindow` s'il a touché, à
`fin du coup + WhiffResetDelay` s'il est parti dans le vide. Il reste `nil`
pendant le coup en cours, ce qui autorise volontairement le joueur à enchaîner en
anticipant l'impact — c'est ce qui donne au chain sa fluidité au doigt sur
mobile. Un seul champ décrit ainsi les deux règles (fenêtre de combo et reset sur
coup manqué) au lieu de deux à tenir cohérents.

Un unique `Heartbeat` dans `StateService` parcourt les joueurs et fait expirer
ce qui doit l'être. **Aucun `task.delay` par joueur ni par action** : un
minuteur ne s'annule pas proprement quand un joueur se fait interrompre ou
quitte la partie, et 30 joueurs en combat produiraient des centaines de tâches
en vol dont plus personne ne sait à quel état elles se rapportent.

Corollaire utile : l'état est entièrement décrit par des données sérialisables.
On peut donc l'afficher tel quel dans le panneau F2, le répliquer, et le
comparer entre client et serveur pour détecter une divergence.

### 1.3 Table de transitions

Les transitions **demandées par le client** doivent satisfaire cette table.

| Depuis | Vers | Déclencheur | Gardes |
|---|---|---|---|
| `Idle` | `Attacking` | `Combat.Attack` | endurance suffisante, chaîne à l'index 1 |
| `Attacking` | `Attacking` | `Combat.Attack` | phase ≠ armé, dans les 0,55 s suivant l'impact précédent, index < longueur de chaîne |
| `Attacking` | `Idle` | expiration | — |
| `Attacking` | `Dashing` | `Combat.Dash` | phase == récupération **et** coup `cancelable`, endurance ≥ 18, cooldown écoulé |
| `Idle` | `Blocking` | `Combat.BlockState{open}` | cooldown de parade (0,55 s) écoulé, endurance ≥ 10 |
| `Blocking` | `Idle` | `Combat.BlockState{close}` | — |
| `Blocking` | `Dashing` | `Combat.Dash` | endurance ≥ 18, cooldown écoulé |
| `Idle` | `Dashing` | `Combat.Dash` | endurance ≥ 18, cooldown écoulé |
| `Dashing` | `Idle` | expiration | — |
| `Knocked` | `GettingUp` | expiration | — |
| `GettingUp` | `Idle` | expiration | — |
| `Downed` | `Idle` | respawn | — |

**Ce qui est absent de cette table est interdit**, et deux absences sont des
décisions de design, pas des oublis :

- `Attacking → Blocking` n'existe pas. Si l'on pouvait garder pendant sa
  récupération, rater un coup ne coûterait rien et la lecture de l'adversaire
  n'aurait plus de valeur. La récupération est la punition du coup dans le vide.
- `Blocking → Attacking` n'existe pas directement. Il faut relâcher la garde
  (`Blocking → Idle → Attacking`), ce qui coûte une frame d'input et empêche le
  « garde permanente, je lâche uniquement pour frapper » sans aucun risque.

### 1.4 Transitions imposées par le serveur

Elles ne consultent pas la table ci-dessus mais une **priorité**. Une
transition imposée l'emporte sur l'état courant si sa priorité est strictement
supérieure :

```
Downed (5) > Knocked (4) > Stunned (3) > Dashing (2) > Attacking (1) = Blocking (1) > Idle (0)
```

| Événement serveur | État imposé | Priorité |
|---|---|---|
| PV ≤ 0 | `Downed` | 5 |
| dernier coup de la chaîne encaissé | `Knocked` | 4 |
| attaque parée par l'adversaire | `Stunned` (1,2 s) | 3 |
| jauge de garde épuisée | `Stunned` (1,6 s) | 3 |

C'est la règle qui rend la machine sûre : le client ne peut jamais *sortir* d'un
`Stunned` en demandant une transition, puisque toute demande client passe par la
table du §1.3, où aucune ligne ne part de `Stunned`.

### 1.5 Diagramme

```
                        ┌──────────────────────────────────┐
                        │              Idle                │◀──────────┐
                        └──┬────────────┬──────────────┬───┘           │
             Combat.Attack │   BlockState│      Combat.Dash            │
                           ▼            ▼              ▼               │
                  ┌────────────┐  ┌──────────┐  ┌────────────┐         │
       enchaîne   │ Attacking  │  │ Blocking │  │  Dashing   │         │
      ┌──────────▶│  armé      │  │ ┌──────┐ │  │ i-frames   │         │
      │           │  actif     │  │ │parade│ │  │  0,12 s    │         │
      └───────────│  récup. ───┼──┼─┘0,20 s└─┼─▶│            │─────────┤
                  └─────┬──────┘  └────┬─────┘  └────────────┘         │
                        │              │                              │
      ┌─────────────────┴──────────────┴──────────────────────────────┐│
      │        transitions imposées par le serveur (par priorité)     ││
      └───┬──────────────────┬──────────────────────┬─────────────────┘│
          ▼                  ▼                      ▼                  │
    ┌───────────┐      ┌───────────┐          ┌──────────┐             │
    │  Stunned  │      │  Knocked  │─────────▶│ GettingUp│─────────────┤
    │ 1,2/1,6 s │      │   1,1 s   │  expire  │  0,60 s  │   expire    │
    └─────┬─────┘      └───────────┘          └──────────┘             │
          │ expire                                                     │
          └────────────────────────────────────────────────────────────┘
                                    ┌──────────┐
              PV ≤ 0 ──────────────▶│  Downed  │──── respawn ──────────▶ Idle
                                    └──────────┘
```

### 1.6 La même machine des deux côtés

`Shared/Combat/StateMachine.luau` est **pur et partagé** : le client l'utilise
pour prédire, le serveur pour arbitrer. Ce n'est pas une commodité, c'est une
condition de correction — deux implémentations des mêmes règles finissent
toujours par diverger sur un cas limite, et cette divergence se manifeste comme
une injustice ressentie par le joueur (« j'ai bien appuyé »).

Le client applique donc les mêmes gardes, avec **une seule différence** : il
n'applique jamais de transition imposée de sa propre initiative. Un `Stunned`,
un `Knocked` ou un `Downed` ne peuvent lui arriver que par un message du
serveur. Quand sa prédiction et l'autorité divergent, c'est le serveur qui
gagne, selon les règles de réconciliation du §5.

---

## 2. Chaîne d'attaque

Quatre coups, décrits par `Balance.Melee`. Le joueur enchaîne tant qu'il
réattaque dans les 0,55 s suivant l'impact précédent ; sinon la chaîne repart à
zéro. Un coup dans le vide remet la chaîne à zéro après 0,80 s.

Chaque coup se déroule en trois phases : armé, actif, récupération. La hitbox
s'ouvre à la fin de l'armé et se ferme à la fin de la phase active. Le
quatrième coup envoie au sol (ragdoll 1,1 s, relevage 0,60 s dont 0,35 s
d'invulnérabilité, pour qu'un knockdown ne s'enchaîne pas indéfiniment).

Détection : le client ouvre la hitbox avec `GetPartBoundsInBox` et
`OverlapParams`, en filtrant son propre personnage. Il envoie la liste des
cibles touchées, jamais un montant de dégâts.

La hitbox est ouverte **une seule fois**, à l'instant d'impact prédit, et non à
chaque frame de la phase active. Le serveur valide le contact à un instant
précis ; balayer toute la phase produirait des contacts qu'il refuserait pour
cause de phase, et le joueur verrait des coups disparaître sans raison lisible.

Le serveur, lui, recalcule la phase **à l'instant revendiqué** depuis la trace du
coup (`lastSwing`), et non depuis l'état courant de l'attaquant : à 150 ms de
latence, celui-ci est déjà passé en récupération quand le rapport arrive
(ADR-015).

---

## 3. Garde et guard break

Maintenir la garde réduit les dégâts à 35 % et alimente une jauge de garde de
60 points, consommée par les dégâts bruts encaissés. À zéro : **guard break**,
1,6 s d'étourdissement, garde impossible pendant ce temps. La jauge se régénère
de 12 points par seconde après 1,5 s sans coup reçu.

La garde ralentit le déplacement à 55 % : elle protège, elle ne permet pas de
fuir en protégeant.

---

## 4. Parade

C'est la mécanique de skill principale du jeu, et donc la plus rentable à
tricher. D'où la règle posée en ADR-002 : **le client ne déclare jamais avoir
paré**.

### Ce que le client envoie

À l'activation de la garde, le client envoie l'instant d'ouverture, horodaté sur
l'horloge serveur commune (`workspace:GetServerTimeNow()` via `Shared/Clock`).
C'est tout. Il n'existe aucun message « j'ai paré ».

### Ce que le serveur décide

Lorsqu'un coup est validé contre ce joueur, le serveur compare l'instant
d'impact à la fenêtre `[ouverture, ouverture + 0,20 s]` :

- dans la fenêtre → **parade** : dégâts annulés, l'attaquant subit 1,2 s
  d'étourdissement, le défenseur récupère 15 points d'endurance ;
- après la fenêtre, garde toujours active → **coup bloqué** : 35 % des dégâts,
  jauge de garde entamée ;
- garde inactive → **coup encaissé** : dégâts pleins.

Une fenêtre de parade ne peut se rouvrir qu'après 0,55 s, ce qui interdit le
maintien-relâche en boucle.

---

## 5. Réconciliation : quand le client et le serveur ne sont pas d'accord

**C'est la section qui compte.** ADR-002 crée nécessairement un décalage :
le joueur appuie, et le verdict arrive un aller-retour réseau plus tard. À
150 ms de latence, cela fait environ 300 ms d'incertitude. Le jeu doit rester
lisible pendant ces 300 ms, et ne jamais se contredire à l'écran.

### Le principe : ne rien afficher qu'il faudrait ensuite annuler

Le retour visuel est découpé en deux temps, et le premier est **délibérément
ambigu**.

**Temps 1 — immédiat (0 ms), sur détection locale d'un coup entrant pendant la
garde.** Le client joue uniquement ce qui est vrai dans *tous* les cas où un
coup rencontre une garde :

- arrêt sur image (hitstop) de 0,08 s ;
- éclat blanc bref sur les avant-bras ;
- un son d'impact **identique** pour la parade et le blocage.

Aucune de ces trois choses ne devient fausse si le verdict tombe dans l'autre
sens. Le joueur reçoit un retour instantané, et rien n'est engagé.

**Temps 2 — à réception du verdict serveur (~1 RTT).** Le client *ajoute* la
couche distinctive :

| Verdict | Ce qui s'ajoute |
|---|---|
| Parade | animation `ParrySuccess`, gerbe d'étincelles, son de parade en surcouche, l'adversaire part en `Stun` |
| Blocage | animation `BlockHitReact`, jauge de garde qui descend |
| Coup encaissé | animation `HitLight` / `HitHeavy`, dégâts affichés |

Il n'y a donc **jamais d'animation à rembobiner** : le temps 1 n'annonce pas de
résultat, le temps 2 le révèle.

### Les quatre cas, explicitement

| # | Ce que croit le client | Ce que dit le serveur | Comportement visuel |
|---|---|---|---|
| 1 | parade | parade | Cas nominal. Hitstop, puis `ParrySuccess` et VFX à la confirmation. |
| 2 | **parade** | **blocage** | Le hitstop et l'éclat ont déjà joué et restent valides. `BlockHitReact` démarre à la confirmation, la jauge de garde descend. **Le joueur ne voit aucune parade avortée** : il voit un coup encaissé dans la garde, ce qui est exactement ce qui s'est passé. |
| 3 | blocage | parade | Le hitstop a joué. `ParrySuccess` démarre à la confirmation, avec un léger retard perceptible mais aucun conflit. |
| 4 | garde active | **aucune garde** (paquet d'ouverture perdu ou arrivé trop tard) | Le seul cas réellement discordant. Le client passe en `HitLight` / `HitHeavy` et referme le retour de garde immédiatement. Les 0,08 s d'éclat déjà joués se lisent comme une partie de l'impact. La garde est reposée localement dès la frame suivante si le joueur maintient toujours la touche. |

### Délai de résolution

Si aucun verdict n'arrive dans les **0,50 s** suivant l'impact détecté
localement, le client résout au cas le plus conservateur (coup bloqué) et
reprend la main. Un verdict arrivé après ce délai n'est plus joué visuellement :
les points de vie affichés sont de toute façon ceux du serveur, qui les a
répliqués séparément. Mieux vaut un retour visuel manquant qu'un retour visuel
en retard d'une demi-seconde sur l'action.

### Côté attaquant

L'attaquant ne prédit rien. Il joue sa récupération normalement ; si le verdict
est « paré », l'animation `Stun` (priorité `Action4`) prend le dessus à la
confirmation. La récupération d'un coup dure entre 0,25 s et 0,40 s, ce qui
couvre l'essentiel du délai à latence normale. Au-delà, la transition reste
propre parce que `Stun` interrompt par priorité, sans fondu ambigu.

---

## 6. Esquive et endurance

Le dash parcourt 14 studs en 0,20 s, coûte 18 points d'endurance, se recharge en
1,2 s et accorde 0,12 s d'invulnérabilité à partir de son départ — jamais avant,
sinon il devient un bouton d'annulation universel.

L'endurance (100 points) se vide sur le sprint (8/s), le dash et les
compétences. Elle remonte de 6 points par seconde en combat et de 22 hors
combat, le tag de combat retombant 4 s après le dernier coup donné ou reçu. En
dessous de 10 points, sprint et dash sont refusés.

---

## 7. Modèle réseau

```
CLIENT                                     SERVEUR
  |                                           |
  |  ouverture de garde (horodatée) --------->|  mémorise l'instant
  |                                           |
  |  coup détecté localement                  |
  |  { skillId, seq, clientTime, cibles } --->|  1. cadence (token bucket)
  |                                           |  2. forme du paquet (parse)
  |  hitstop + éclat (temps 1)                |  3. rembobinage <= 0,25 s
  |                                           |  4. distance, angle, vue
  |                                           |  5. cooldown, endurance, état
  |                                           |  6. parade / blocage / coup
  |<---------------- verdict + effets --------|  applique PV, stun, KO
  |  temps 2 : couche distinctive             |
```

Le serveur conserve un historique de positions par joueur, échantillonné 20 fois
par seconde, et rejoue la scène à `clientTime` pour valider. Le rembobinage est
borné à 0,25 s : au-delà, le coup est refusé même si le client est honnête. Un
joueur dont la latence dépasse durablement cette borne est détectable via
`DiagnosticsService.exceedsRewindBudget`, ce qui permet de le lui dire plutôt
que de le laisser croire à un bug.

---

## 8. Critère d'acceptation de la Phase 1

Deux clients à 150 ms de latence simulée échangent 100 coups :

- 100 % des parades exécutées dans la fenêtre sont reconnues comme telles ;
- aucun coup n'inflige de dégâts sans qu'une animation d'attaque
  correspondante ait été jouée (aucun « hit fantôme ») ;
- aucun des quatre cas du §5 ne produit d'animation interrompue en cours de
  lecture par une animation contradictoire.

La procédure exacte de ce test est dans [TESTING.md](TESTING.md), avec les
interrupteurs de développement qui permettent de forcer chaque cas — le cas 2
(le client croit avoir paré, le serveur refuse) est le plus important à
provoquer volontairement, car il ne se produit pas de lui-même assez souvent
pour être observé au hasard.
