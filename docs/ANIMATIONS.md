# ANIMATIONS — brief pour l'animateur

Ce document est autonome : il ne suppose aucune connaissance du code. Il décrit
chaque animation à produire, sa durée exacte, et ce qui doit se passer à quel
moment.

---

## 1. Le jeu, en trois phrases

**Banchou** se passe dans une ville japonaise en 2007. On y incarne un lycéen,
et l'essentiel du temps de jeu se passe à se battre à mains nues, en un contre
un, dans la rue ou dans la cour du lycée.

La sensation recherchée est celle d'une bagarre de rue lourde et lisible :
peu de coups, mais chacun se voit et se sent. Ce n'est ni un jeu d'arts
martiaux acrobatique, ni un beat'em up cartoon. Référence de ton : les scènes de
bagarre des films de lycée japonais des années 2000 — postures nonchalantes,
frappes larges, beaucoup de poids dans les épaules.

---

## 2. Contraintes techniques (à respecter à la lettre)

| Point | Valeur |
|---|---|
| Rig | **R15** (Roblox standard), rig de base sans accessoire |
| Éditeur | Roblox Animation Editor, ou export FBX importé dans l'éditeur |
| Cadence | **60 fps** dans l'éditeur |
| Livraison | Animations publiées sur Roblox, **détenues par le groupe** propriétaire du jeu, pas par un compte personnel |
| Retour attendu | un tableau `nom d'animation → asset ID` (voir §7) |

**La cadence à 60 fps n'est pas une préférence esthétique.** Toutes les durées
de ce document sont des multiples de 0,05 s, soit exactement 3 frames à 60 fps.
En travaillant à 60, chaque moment clé tombe sur une frame entière ; à 30, la
moitié tomberait entre deux images.

### La règle des trois temps

Chaque animation d'attaque se découpe en trois phases, et le code du jeu se
cale dessus au centième de seconde près :

```
|<---- ARMÉ ---->|<-- ACTIF -->|<-------- RÉCUPÉRATION -------->|
0                ^ IMPACT                                        fin
                 |
        le coup touche EXACTEMENT ici
```

- **Armé** : la préparation. L'adversaire doit pouvoir lire l'attaque et
  réagir — c'est pendant cette phase qu'il déclenche sa parade. Une animation
  dont l'armé est invisible rend le jeu injouable.
- **Actif** : la partie du geste qui peut toucher. Le poing (ou le pied) doit
  visiblement occuper l'espace devant le personnage pendant toute cette durée.
- **Récupération** : le retour en garde. Le personnage est vulnérable ; on doit
  le sentir.

**L'impact tombe à la fin de l'armé, pas au milieu de l'actif.** Si l'animation
frappe visuellement 0,1 s après le moment où le jeu applique les dégâts, les
joueurs verront des coups qui touchent avant de partir. C'est le défaut le plus
grave possible sur ce projet.

Les durées ci-dessous sont **fermes**. Si une durée rend un geste impossible à
poser correctement, le dire — on ajustera le chiffre côté code et on mettra ce
document à jour. Ne jamais l'ajuster silencieusement dans l'animation.

---

## 3. Locomotion

Ces animations remplacent le pack de marche par défaut de Roblox. Elles portent
la silhouette du personnage : épaules basses, dos légèrement voûté, mains
souvent dans les poches. Un lycéen qui traîne, pas un héros.

| Nom | Durée | Boucle | Description |
|---|---|---|---|
| `Idle` | 2,00 s | oui | Debout, poids sur une jambe, léger balancement. Une respiration lente sur la durée complète. Aucun geste marqué : elle tourne en permanence, tout tic devient agaçant. |
| `Walk` | 1,00 s | oui | Un cycle complet (deux pas). Démarche nonchalante, bras peu amples, tête légèrement basse. |
| `Run` | 0,70 s | oui | Un cycle complet. Course de rue, pas de sprint athlétique : buste en avant, bras relâchés. |
| `Jump` | 0,40 s | non | Impulsion vers le haut, jambes qui se replient. Se joue une fois au décollage. |
| `Fall` | 1,00 s | oui | Chute, bras qui cherchent l'équilibre. Boucle tant que le personnage est en l'air. |
| `Land` | 0,30 s | non | Réception, flexion des genoux, retour debout. |
| `CombatStance` | 2,00 s | oui | **Remplace `Idle` dès qu'un combat commence.** Garde haute mais pas fermée, poids réparti, regard vers l'avant. C'est le premier signal visuel qu'une bagarre a commencé : elle doit se distinguer d'`Idle` au premier coup d'œil, même de loin. |

---

## 4. Chaîne d'attaque de base

Quatre coups qui s'enchaînent si le joueur continue de frapper. Chaque coup est
plus engagé que le précédent ; le quatrième envoie l'adversaire au sol.

Le personnage frappe **face à lui**, à environ 3,5 studs devant son torse
(un peu plus qu'une longueur de bras). Les coups doivent rester dans ce volume :
un geste qui balaie sur les côtés promet une portée que le jeu ne donne pas.

| Nom | Armé | Actif | Récup. | **Durée totale** | Description |
|---|---|---|---|---|---|
| `M1_1` | 0,10 s | 0,10 s | 0,25 s | **0,45 s** | Direct du bras avant. Sec, court, peu d'engagement du buste. Le coup d'ouverture, celui qu'on lance pour tester. |
| `M1_2` | 0,10 s | 0,10 s | 0,25 s | **0,45 s** | Enchaîne sur l'autre bras. Même énergie, épaule opposée. Doit visuellement se lire comme la suite de `M1_1`, pas comme un nouveau départ : la position de fin de `M1_1` est la position de départ de `M1_2`. |
| `M1_3` | 0,15 s | 0,10 s | 0,30 s | **0,55 s** | Crochet. Rotation nette des hanches, l'armé est plus long et plus visible — c'est là que l'adversaire a sa meilleure fenêtre de parade. Le poids passe sur la jambe avant. |
| `M1_4` | 0,20 s | 0,15 s | 0,40 s | **0,75 s** | Le coup final. Un grand geste engagé (crochet remontant ou coup d'épaule), armé long et lisible, tout le corps derrière. Il envoie l'adversaire au sol : le geste doit avoir une direction ascendante ou latérale marquée, cohérente avec un corps qui part en arrière. Récupération longue et lourde — le personnage est à découvert. |

**Continuité de la chaîne** : les quatre poses de fin doivent enchaîner sans
saut visible sur la pose de départ suivante, et `M1_4` doit revenir à la pose de
`CombatStance`.

---

## 5. Défense

C'est la partie la plus importante du document. La parade est la mécanique
centrale du jeu : deux joueurs doivent pouvoir la lire à l'écran, en pleine
action, sur un écran de téléphone.

| Nom | Durée | Boucle | Description |
|---|---|---|---|
| `BlockStart` | **0,10 s** | non | Passage en garde : les avant-bras remontent devant le visage. **Cette durée est un plafond absolu.** Le jeu ouvre une fenêtre de parade de 0,20 s à cet instant précis ; si la garde n'est pas visible en 0,10 s, le joueur d'en face ne peut pas comprendre ce qui vient de se passer. Geste sec, aucune anticipation. |
| `BlockHold` | 1,00 s | oui | Garde maintenue. Micro-tension, respiration courte. Boucle tant que le joueur maintient. |
| `BlockHitReact` | 0,25 s | non | Coup encaissé **dans la garde**. Les bras absorbent, le corps recule très légèrement. Le personnage ne baisse jamais sa garde : il tient. |
| `ParrySuccess` | 0,40 s | non | **La parade réussie.** Un geste de déviation net et large — l'avant-bras chasse le coup adverse sur le côté — suivi d'un retour en garde. Elle doit être la plus lisible de tout le jeu : c'est le moment de gloire du joueur, il sera capturé en vidéo. Contraste fort avec `BlockHitReact` (subir) : ici on renvoie. |
| `GuardBreak` | 1,60 s | non | **La garde cède.** Les bras sont écartés vers l'extérieur, le personnage est déséquilibré vers l'arrière, à découvert, et met du temps à se remettre. Longue et pénible à regarder — c'est une punition, elle doit se voir comme telle. Se termine debout, en position neutre. |

**Distinction non négociable** : `ParrySuccess` et `BlockHitReact` doivent être
reconnaissables l'une de l'autre en un dixième de seconde, y compris de dos et
de loin. Silhouettes différentes, directions différentes.

---

## 6. Esquive et réactions

### Esquive

Quatre directions. Un dash arrière qui jouerait l'animation avant se lit comme
un bug par l'adversaire — c'est lui qui a le plus besoin de savoir où va le
personnage.

| Nom | Durée | Boucle | Description |
|---|---|---|---|
| `DashForward` | 0,20 s | non | Bond court vers l'avant, corps bas, épaule en avant. Le personnage parcourt 14 studs : le geste doit être explosif, pas glissé. |
| `DashBackward` | 0,20 s | non | Bond en arrière, buste qui recule en premier, garde qui reste haute. |
| `DashLeft` | 0,20 s | non | Pas chassé latéral, appui sur la jambe droite. |
| `DashRight` | 0,20 s | non | Miroir de `DashLeft`. |

### Réactions

| Nom | Durée | Boucle | Description |
|---|---|---|---|
| `HitLight` | 0,30 s | non | Coup encaissé sans garde, impact léger. La tête part, le corps suit à peine. Retour rapide en garde. |
| `HitHeavy` | 0,45 s | non | Coup lourd encaissé. Le buste part, un pas de recul involontaire. Utilisée sur `M1_3` et sur les coups spéciaux. |
| `Stun` | 1,20 s | non | **Étourdissement après avoir été paré.** Le personnage est ouvert, bras ballants, tête basse, il titube sur place. Longue et clairement lisible : l'adversaire a gagné le droit de frapper librement pendant tout ce temps. |
| `KnockdownFall` | 0,50 s | non | La chute vers le sol après le quatrième coup. Le corps part en arrière et touche le sol. Doit finir exactement sur la pose de départ de `KnockdownIdle`. |
| `KnockdownIdle` | 1,00 s | oui | Au sol, sur le dos ou le flanc. Respiration lourde, léger mouvement. Boucle pendant environ 1,1 s. |
| `GetUp` | 0,60 s | non | Relevage. Un appui sur une main, remise sur les jambes, retour en `CombatStance`. Ni acrobatique ni lent : le personnage se relève parce qu'il n'a pas le choix. |
| `KO` | 1,00 s | non | Mise hors de combat. Le personnage s'effondre et ne se relève pas. Reste figé sur la dernière frame. |

---

## 7. Livraison

1. Publier chaque animation sur Roblox **sous le groupe** propriétaire du jeu
   (Animation Editor → Publish to Roblox → sélectionner le groupe). Une
   animation publiée sur un compte personnel ne pourra pas être jouée par le
   jeu.
2. Nommer chaque animation **exactement** comme dans les tableaux ci-dessus
   (`M1_1`, `ParrySuccess`, `DashBackward`…). Ces noms sont des clés dans le
   code, une faute de frappe casse le branchement.
3. Renvoyer un tableau à deux colonnes : nom d'animation, asset ID.

Exemple du format attendu :

```
M1_1            18234567890
M1_2            18234567891
ParrySuccess    18234567892
```

Le branchement côté code consiste alors à recopier ces identifiants dans un
fichier de configuration. Aucune animation n'est codée en dur : tant qu'un ID
vaut `0`, le jeu joue un mouvement de substitution généré par le code, de la
même durée. Le jeu est donc jouable et testable avant, pendant et après la
production des animations, et les animations peuvent arriver par lots.

---

## 8. Hors périmètre pour l'instant

Ces animations seront commandées plus tard, une fois le combat validé. Elles
sont listées ici pour donner une idée du volume total, pas pour être produites
maintenant.

- **Compétences de style** (Phase 6) : 4 par style de combat, 15 styles. Chacune
  suivra la même règle des trois temps, avec des durées fournies au cas par cas.
- **Vie sociale** (Phase 5) : s'asseoir sur un banc, emotes, instruments de
  musique, tirs au panier de basket.
- **Métiers** (Phase 4) : distribuer des prospectus, porter un carton.
