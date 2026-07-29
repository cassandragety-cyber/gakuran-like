# COMBAT — spécification

Document de référence du combat. Écrit en Phase 0, implémenté en Phase 1 ; il
fait autorité sur le comportement attendu, y compris dans les cas de désaccord
entre client et serveur.

Toutes les valeurs chiffrées citées ici viennent de
`src/ReplicatedStorage/Config/Balance.luau` et n'y sont recopiées que pour la
lisibilité. **En cas de divergence, c'est le fichier de configuration qui a
raison**, et ce document qui doit être corrigé.

---

## 1. États du personnage

Un joueur est à tout instant dans exactement un de ces états, côté serveur :

| État | Peut attaquer | Peut garder | Peut dasher | Subit les dégâts |
|---|---|---|---|---|
| `Neutral` | oui | oui | oui | pleins |
| `Attacking` | non (sauf enchaînement) | non | pendant la récup. si `cancelable` | pleins |
| `Blocking` | non | — | oui | × 0,35 |
| `Parrying` (0,20 s) | non | — | non | annulés |
| `Dashing` (0,20 s) | non | non | non | annulés pendant 0,12 s |
| `Stunned` | non | non | non | pleins |
| `Knocked` | non | non | non | pleins |
| `Downed` (KO) | non | non | non | — |

Le client tient une copie de cet état pour l'affichage et la prédiction. **Il
n'en est jamais la source de vérité** : quand les deux divergent, celui du
serveur gagne, selon les règles de réconciliation du §5.

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
