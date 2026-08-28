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

## ADR-007 — Le nom d'affichage peut changer, les clés de stockage non

**Statut :** accepté (Phase 0) · **Impact :** irréversible après le lancement

**Contexte.** Le jeu s'appelle Banchou aujourd'hui. Un nom d'expérience Roblox
se change en deux clics et se change souvent — après un test de marché, un
conflit de marque, un changement de positionnement. Un nom de DataStore, lui, ne
se change pas : il n'y a pas de « renommer », seulement « repartir de zéro ».

**Décision.** Toutes les clés de stockage vivent dans `Config/DataStores.luau` au
format `Banchou_<Nom>_v<N>` — préfixe figé, version explicite. La convention est
**vérifiée au boot** par `Systems/ConfigValidator` : une clé mal formée empêche
le serveur de démarrer. La version de schéma du profil (`ProfileSchemaVersion`)
est un champ distinct du suffixe de clé, parce que migrer un schéma à
l'intérieur d'un même DataStore et changer de DataStore sont deux opérations
différentes.

**Alternative écartée.** Dériver les noms du nom de l'expérience, ou les écrire
au fil de l'eau là où on en a besoin.

**Pourquoi.** Les deux mènent au même accident, à des dates différentes : le
jour où quelqu'un renomme le jeu ou recopie une clé avec une faute de frappe,
tous les joueurs se réveillent avec un profil vide. Une constante centralisée et
validée à chaque démarrage rend cet accident impossible plutôt qu'improbable.

---

## ADR-008 — La Phase 0 ne dépend d'aucun paquet Wally

**Statut :** accepté (Phase 0) · **Impact :** faible, temporaire

**Contexte.** `wally.toml` déclare Trove, Signal, Promise et ProfileStore, qui
entrent en jeu à partir de la Phase 1. Mais le livrable de la Phase 0 est « ça
se synchronise dans Studio et ça log OK », et cette promesse ne doit dépendre ni
du réseau, ni de la résolution du registre Wally.

**Décision.** Aucun module de la Phase 0 ne fait de `require` dans `Packages/`.
Le dossier existe (vide, avec un `.gitkeep`) pour que le mapping Rojo soit
valide. Les deux seules connexions du code Phase 0 — `PlayerAdded` /
`PlayerRemoving` dans `SessionService`, `Heartbeat` dans
`DiagnosticsController` — sont gérées explicitement : la première paire vit
aussi longtemps que le serveur, la seconde se déconnecte elle-même une fois ses
échantillons collectés.

**Alternative écartée.** Introduire Trove dès maintenant pour respecter à la
lettre la règle « toute connexion vit dans un Trove ».

**Pourquoi.** La règle du Trove existe pour les connexions dont la durée de vie
suit celle d'un objet créé dynamiquement (un personnage, une hitbox, un écran
d'UI). En Phase 0, il n'existe aucun objet de ce type. Ajouter une dépendance
externe pour envelopper deux connexions au cycle de vie trivial aurait rendu
`rojo serve` dépendant d'un `wally install` réussi, en échange de zéro sécurité
réelle. **La règle reprend pleinement ses droits en Phase 1**, dès le premier
personnage qui apparaît.

---

## ADR-009 — Les animations sont des données, avec un fallback procédural par défaut

**Statut :** accepté (Phase 0) · **Impact :** structurant pour le planning

**Contexte.** Le combat a besoin d'animations pour être lisible, et les
animations sont produites par un humain sur un calendrier qui n'est pas celui du
code. Attendre les animations pour développer le combat, ou développer le combat
en codant des identifiants d'animation en dur, sont deux façons de bloquer.

**Décision.** `Config/Animations.luau` associe une clé (`M1_1`, `ParrySuccess`…)
à `{ id, priorité, boucle, durée cible }`. `id = 0` signifie « pas encore
uploadé » : le client joue alors un mouvement procédural de la **même durée**.
Brancher une vraie animation consiste à remplacer un `0` par un identifiant.
Surtout, `ConfigValidator` **impose** au boot que chaque `targetDuration`
corresponde à la somme des phases dans `Balance` — un désaccord fait échouer le
démarrage.

**Alternative écartée.** Charger les animations depuis un dossier d'instances
`Animation` dans `ReplicatedStorage`, à la mode Roblox habituelle.

**Pourquoi.** Ce contrat de durée vérifié par la machine est ce qui empêche la
classe de bugs la plus coûteuse du projet : l'animation qui frappe visuellement
à un instant différent de celui où le serveur applique les dégâts. C'est
exactement le « hit fantôme » que le brief interdit, et aucune relecture humaine
ne l'attrape de façon fiable. Un dossier d'instances ne permet pas ce contrôle,
puisque la durée n'y est connue qu'après chargement de l'asset.

**Conséquence de planning assumée.** Le combat de la Phase 1 sera jouable et
testable avec des mouvements procéduraux, donc laid. C'est voulu : on valide la
sensation et le réseau avant d'investir dans les assets. `docs/ANIMATIONS.md` est
le brief que reçoit l'animateur, et il est dérivé de `Config/Balance` — les
deux fichiers se modifient dans le même commit.

---

## ADR-010 — Pity à 150 sur Epic, jamais sur Mythic

**Statut :** accepté (Phase 0, décision produit) · **Impact :** moyen, réversible

**Décision.** `PITY_THRESHOLD = 150`, `PITY_TARGET_RARITY = "Epic"`. Le compteur
vit dans le profil du joueur et suit le versionnage du schéma. Mettre le seuil à
`0` désactive le système. `ConfigValidator` **refuse de démarrer** si quelqu'un
positionne un jour la cible sur `Mythic`.

**Alternative écartée.** Pity sur Mythic, ou pas de pity du tout.

**Pourquoi.** Sans pity, un joueur peut enchaîner 300 tirages sans rien voir de
notable et s'en aller ; le pity Epic borne cette frustration. Avec un pity
Mythic, le Mythic devient une question de patience et cesse d'être une histoire
qu'on raconte à ses amis — c'est précisément cette histoire qui fait revenir les
joueurs et vendre les rerolls. Le garde-fou est dans le code plutôt que dans un
document parce que c'est le genre d'arbitrage qu'un futur pic de monétisation
rendra tentant.

---

## ADR-011 — La table d'équilibrage est injectée en argument, pas require

**Statut :** accepté (Phase 1, conception) · **Impact :** structurant pour tout le combat

**Contexte.** Trois besoins arrivent en même temps et semblent se contredire.
`Config/` est gelé depuis la Phase 0, et cette garantie a de la valeur. Le
produit demande un panneau de réglage à chaud pour ne pas éditer un fichier
entre deux essais sur le mannequin. Et la parade doit être testable
exhaustivement, ce qui suppose de pouvoir lui fournir des valeurs fabriquées.

**Décision.** Aucun module de `Shared/Combat/` ni de `Systems/` ne fait de
`require` sur `Config.Balance`. Chaque fonction pure reçoit la table
d'équilibrage **en argument**. `TuningService` détient une copie unique, créée au
boot, que le panneau F2 modifie en place ; `Config.Balance` reste gelé et sert de
référence pour la réinitialisation. En production, la copie est regelée après
création, donc l'immuabilité tient aussi.

**Alternative écartée.** Dégeler `Config/` et laisser le panneau écrire dedans.
Variante écartée aussi : un accesseur `Tuning.get("Parry.Window")` appelé partout.

**Pourquoi.** Dégeler `Config/` aurait rendu possible en production la classe de
bug que le gel élimine — une valeur d'équilibrage modifiée par erreur depuis un
script de gameplay, invisible jusqu'à ce qu'un joueur le remarque. L'accesseur
par chaîne de caractères, lui, transforme chaque lecture en recherche
textuelle non vérifiée par le typage : une faute de frappe dans `"Parry.Windo"`
renverrait `nil` à l'exécution, au milieu d'un combat. L'injection donne les
trois bénéfices d'un coup et ne coûte qu'un paramètre de plus par fonction.

**Effet de bord accepté.** Les signatures sont plus verbeuses. C'est le prix, et
il est visible dans le bon sens : lire `resolve(step, defender, now, balance)`
dit immédiatement de quoi le résultat dépend.

---

## ADR-012 — Le client n'annonce jamais où il en est dans sa chaîne

**Statut :** accepté (Phase 1, conception) · **Impact :** fort

**Contexte.** Le quatrième coup de la chaîne envoie l'adversaire au sol. Il faut
bien décider quel coup est joué à chaque appui.

**Décision.** La demande `Combat.Attack` contient un numéro de séquence et un
horodatage, **rien d'autre**. Le serveur dérive l'index de chaîne de l'état qu'il
détient, via `Frames.nextChainIndex`. Même logique ailleurs : la direction du
dash est un entier de 1 à 4, jamais un `Vector3`.

**Alternative écartée.** Laisser le client envoyer `chainIndex`, ce que le
serveur validerait ensuite.

**Pourquoi.** Un client qui peut annoncer « je frappe le coup 4 » possède un
knockdown à la demande, et la seule défense serait de recalculer l'index côté
serveur — c'est-à-dire de ne pas utiliser la valeur envoyée. Autant ne pas la
demander : un champ qu'on n'accepte pas est un champ qu'on n'a pas à valider.
Généralisation retenue pour toute la phase : **si le serveur peut dériver une
valeur, le client ne l'envoie pas.** Un `Vector3` de direction libre est le même
piège sous un autre nom, en pire — c'est un vecteur de téléportation.

---

## ADR-013 — Les remotes de développement n'existent pas en production

**Statut :** accepté (Phase 1, conception) · **Impact :** moyen

**Contexte.** Le panneau F2 doit pouvoir réécrire des valeurs d'équilibrage.
C'est, de loin, le remote le plus dangereux du projet : il touche directement
aux dégâts et aux fenêtres de parade.

**Décision.** `Net/Definitions` gagne un champ `devOnly`. `Net.initServer()`
**ne crée pas** l'instance `RemoteEvent` quand le serveur n'est ni en Studio ni
autorisé par `Config/Debug.AdminUserIds`. En plus de ça, `TuningGuard` applique
une liste blanche de chemins avec bornes : une valeur absente de la liste est
refusée même en Studio.

**Alternative écartée.** Déclarer le remote partout et rejeter les appels non
autorisés dans le handler.

**Pourquoi.** Un handler qui rejette est une ligne de code qu'une erreur future
peut affaiblir — un test d'autorisation inversé, une condition de debug laissée
à `true` avant un déploiement. Un remote qui n'a pas été instancié n'offre
aucune surface : il n'apparaît pas dans l'arbre, un outil d'exploration ne le
trouve pas, et aucune régression de logique ne peut le rouvrir. La liste blanche
de `TuningGuard` est la deuxième couche, pour le cas où un compte administrateur
serait compromis : elle borne les dégâts possibles au lieu de faire confiance à
l'identité.

**Note.** Les durées d'animation sont volontairement absentes de la liste
blanche. Les modifier à chaud casserait le contrat vérifié au boot en Phase 0
(ADR-009) ; il faut passer par les fichiers et redémarrer, ce qui est
exactement l'intention.

---

## ADR-014 — Les combattants sont indexés par `Model`, pas par `Player`

**Statut :** accepté (tranche 1.2) · **Impact :** structurant pour tout le combat

**Contexte.** La tranche 1.1 tenait l'état de combat dans un registre indexé par
`Player`. La 1.2 introduit le mannequin d'entraînement, qui n'est pas un joueur,
et les tranches 1.3 et 1.4 ont besoin qu'il **garde** et qu'il **pare** pour être
testables : on ne règle pas une fenêtre de parade contre une cible qui ne pare
jamais.

**Décision.** Le registre est indexé par `Model`. Chaque enregistrement porte un
champ `player: Player?`, nil pour un mannequin. Un index secondaire par joueur
conserve l'accès direct là où il est naturel (`ofPlayer`). Tout le reste du code
de combat — validation, résolution, dégâts, knockdown — ne fait pas la
différence.

**Alternative écartée.** Garder le registre par joueur et donner aux mannequins
leur propre petit système de dégâts, plus simple à écrire.

**Pourquoi.** Deux registres, c'est deux chemins de dégâts, donc deux endroits où
la règle peut diverger. Et la divergence tomberait précisément là où elle coûte le
plus cher : on réglerait la parade contre un mannequin qui l'applique un peu
différemment des joueurs, on serait satisfait, et le premier duel réel révélerait
l'écart. Une cible d'entraînement ne vaut que si elle se comporte exactement comme
un adversaire.

**Coût payé.** `StateService` a été découpé en quatre modules (registre, types,
transitions, pas de temps) pour tenir la limite de 300 lignes. Le découpage était
de toute façon dû.

---

## ADR-015 — La phase d'un coup est validée à l'instant revendiqué, pas à la réception

**Statut :** accepté (tranche 1.2) · **Impact :** fort

**Contexte.** La hitbox n'est ouverte que pendant la phase active d'un coup, qui
dure entre 0,10 et 0,15 s. Un rapport de contact met un demi-RTT à remonter : à
150 ms de latence, l'attaquant est déjà en récupération quand son rapport arrive.

**Décision.** Le serveur conserve `Combatant.lastSwing` — index et instant de
départ du dernier coup — qui **survit au retour à `Idle`**. La phase est
recalculée à `clientTime` depuis cette trace, jamais lue depuis l'état courant.
Le client, symétriquement, horodate son rapport à l'instant d'impact **prédit**,
pas à la frame où le paquet part.

**Alternative écartée.** Valider contre l'état courant de l'attaquant, en
élargissant la fenêtre acceptée pour absorber la latence.

**Pourquoi.** Élargir la fenêtre revient à accorder à tout le monde la tolérance
du joueur le plus lent, donc à autoriser des coups portés bien après la fin de la
phase active — exactement le « hit fantôme » que le brief interdit. Valider contre
un instant reconstruit garde la fenêtre à sa vraie durée pour tous, quelle que
soit la latence. C'est le même raisonnement qu'ADR-001, appliqué au temps plutôt
qu'à l'espace.

---

## ADR-016 — L'analyse de types entre dans le contrôle qualité

**Statut :** accepté (tranche 1.2, après incident) · **Impact :** process

**Contexte.** Un découpage mécanique de `Net/Parsers` en trois modules a laissé
un appel `Parsers.parseCombatState` alors que la fonction avait déménagé dans
`Session`. Résultat : `attempt to call a nil value` dix fois par seconde côté
client, aucun état de combat parsé, et un clic sans effet. Le contrôle qualité
est passé au vert sur ce commit.

Il ne pouvait pas faire autrement. StyLua formate. Selene lint **dans** un
fichier. `luau-compile` vérifie la syntaxe. **Aucun des trois ne sait qu'un
module n'expose pas la fonction qu'un autre appelle.** Le trou n'était pas un
oubli de rigueur, c'était un angle mort de l'outillage.

**Décision.** `luau-lsp analyze` devient une étape de `scripts/check.sh`, avec le
sourcemap Rojo et les définitions de l'API Roblox. La version est épinglée dans
`rokit.toml` et doit rester alignée avec celle des définitions téléchargées — un
binaire ne sait lire que la syntaxe de types de sa propre version.

**Alternative écartée.** Écrire un vérificateur maison qui compare les
références `Module.fonction` aux définitions trouvées dans les fichiers.

**Pourquoi.** Le vérificateur maison n'aurait couvert que ce cas précis. L'analyse
de types couvre la même classe **et** tout le reste : sur son premier passage,
elle a trouvé 29 problèmes, dont deux autres bugs d'exécution que personne
n'avait vus — `MovementService` passait encore un `Player` au registre indexé par
`Model` depuis ADR-014, ce qui cassait silencieusement le sprint, et
`HitboxVisualizer` écrivait `Shape` sur un `BasePart`, ce qui aurait planté à la
première hitbox affichée.

**Coût payé.** Une passe de nettoyage : `Result<true>` remplacé par
`Result.Verdict` (le littéral `true` s'élargit en `boolean` et les deux types ne
se convertissent pas), arité uniformisée des lectures du panneau, comparaisons
`~= nil` sur des types Instance remplacées par des tests de vérité. Le dépôt est
à zéro erreur de type, ce qui rend l'étape exigible plutôt qu'informative.

**Ce que ça ne couvre pas.** L'analyse ne voit pas les erreurs de câblage à
l'exécution : un handler enregistré sur le mauvais événement, un ordre
d'initialisation erroné. Pour celles-là, la réponse reste ce que la tranche 1.2 a
ajouté — aucun chemin de code qui échoue en silence.

---

## ADR-017 — Un coup est daté sur l'horloge du client, sa légalité jugée sur celle du serveur

**Statut :** acceptée (correctif de tranche 1.2)

**Contexte.** Après la correction du crash `Parsers.Session`, les coups partaient
enfin — et **tous** étaient refusés en `WrongPhase`, même à latence simulée nulle,
mannequins figés à 100/100.

La cause est une incohérence d'horloge entre deux moitiés du même mécanisme, et
elle était invisible à la lecture de chaque moitié prise séparément :

- le client prédit sa transition, retient `enteredAt` (son instant d'appui), et
  rapporte le contact à `enteredAt + windup` ;
- le serveur, lui, datait la trace du coup (`Combatant.lastSwing.startedAt`) à
  l'instant de **réception** du paquet.

Le serveur calculait donc `elapsed = (enteredAt + windup) − (enteredAt + latence)`,
soit `windup − latence`. Strictement inférieur à `windup` pour toute latence
positive, donc phase `Windup`, donc refus — **à chaque coup, pour tout le monde**.
Studio à « latence nulle » n'y échappe pas : il reste le RTT réel, la file de
`LatencySim` et la granularité du Heartbeat.

L'ironie du dossier : `CombatService` et `Types.luau` documentaient déjà, en
toutes lettres, que la phase devait être évaluée à l'instant revendiqué (c'est la
raison d'être de `lastSwing`). Le commentaire était juste, le code datait la trace
sur l'autre horloge. Une intention correcte n'est pas une garantie.

**Décision.** Séparer explicitement les deux usages d'un instant, et ne plus
jamais les confondre :

| | Horloge | Pourquoi |
|---|---|---|
| **Légalité** d'une transition — cooldowns, endurance, transitions permises | serveur (`Clock.now()` à la réception) | Un instant fourni par le client ne doit jamais pouvoir avancer un cooldown. C'est une ressource que le serveur possède. |
| **Chronologie** du coup accepté — `lastSwing.startedAt` | client (`payload.clientTime`, borné) | C'est contre elle que le rapport de contact sera validé, et ce rapport est daté sur l'horloge du client. |

`Clock` est `GetServerTimeNow()` des deux côtés : les deux instants sont sur la
même base de temps, seul le transit les sépare. L'instant revendiqué passe par
`HitValidator.checkTimestamp`, la **même** borne `[−ClockTolerance, +MaxRewind]`
que celle d'un rapport de contact — un client qui antidate son coup ne gagne que
ce que le rembobinage lui accordait déjà, et le paie en expiration anticipée.

**Deuxième correctif, même dossier : la fenêtre active a une marge, d'un seul
côté.** La hitbox client s'ouvre sur `Heartbeat`, donc au plus une frame après
l'instant d'impact prévu : à 30 fps, 33 ms de retard qui coûteraient des coups
honnêtes. D'où `Balance.Network.ActivePhaseGrace`, ajoutée à la **fin** de la
fenêtre.

Rien n'est ajouté au **début**, et c'est un arbitrage de design, pas un oubli :
accepter un contact revendiqué avant la fin de l'armé donnerait à l'attaquant un
coup plus rapide que son animation. Le défenseur cale sa parade sur ce qu'il voit
— si l'impact réel peut précéder l'impact visuel, la parade devient illisible, et
c'est la mécanique signature du jeu. **Entre l'indulgence envers l'attaquant et la
lisibilité pour le défenseur, on tranche toujours pour le défenseur.**

Les deux refus portent désormais des codes distincts, `ClaimTooEarly` et
`ClaimTooLate`, là où `WrongPhase` couvrait les deux. Ce n'est pas cosmétique :
`ClaimTooEarly` systématique dénonce une chronologie mal ancrée, `ClaimTooLate`
sporadique un framerate bas. Le code de refus est l'outil de diagnostic à
distance ; le confondre, c'était s'interdire de lire ce bug-ci sans instrumenter.

**Troisième correctif, trouvé en tirant le fil : la chaîne ne bouclait pas.**
`Frames.nextChainIndex` faisait `math.min(chainIndex + 1, #Melee)`. Après le
finisher, elle retournait donc le finisher. Tant que courait la fenêtre de reset
de coup manqué (`WhiffResetDelay`, 0,8 s), un joueur qui ratait le 4ᵉ coup
**rejouait le 4ᵉ coup** — 14 dégâts et knockdown — au lieu de repartir à 8. Le
coup le plus punitif de la chaîne était aussi le plus facile à répéter, et les
trois premiers ne servaient à rien. La chaîne boucle maintenant sur 1.

C'est ce qui produisait l'index bloqué à 4 et les rafales de `ChainComplete` : le
symptôme visible venait du refus systématique (aucun impact, donc `markImpact`
jamais appelé, donc que des coups manqués), mais il a mis au jour une règle
d'équilibrage réellement fausse en dessous.

**Conséquences acceptées.** L'état serveur (`state.enteredAt`) reste, lui, daté à
la réception : seule la trace du coup est ancrée côté client. Le décalage
résiduel — l'état serveur court une latence en retard sur celui du client — n'est
visible que sur `canChain`, qui ne refuse que pendant l'armé ; il faudrait
enchaîner à moins d'une latence de la fin de l'armé pour le sentir. Si la tranche
1.4 montre que la parade y est sensible, ancrer aussi `enteredAt` est le geste
suivant — il se discutera à ce moment-là, avec la mesure sous les yeux.

**Ce que ça dit sur la méthode.** Trois bugs, un seul symptôme. Le premier était
une incohérence entre deux fichiers qu'aucun outil de la chaîne ne relie —
l'analyse de types (ADR-016) voit les signatures, pas les unités. La leçon est la
même qu'en ADR-016 mais d'un cran plus haut : **quand deux modules échangent un
nombre, le type ne suffit pas — il faut nommer l'horloge.** D'où les paramètres
`startedAt` / `at` / `now` distingués dans les signatures plutôt qu'un `time`
générique.

---

## ADR-018 — Un état atteignable a un visuel, et « pas encore » se déclare

**Statut :** acceptée (tranche 1.3)

**Contexte.** ADR-009 promet qu'on développe sans assets d'animation et qu'on les
branche plus tard en remplaçant un `0` par un asset id. La promesse tenait sur le
plan du code ; elle ne disait rien de ce qui se passe **pendant** — c'est-à-dire
pendant toute la Phase 1. Le retour du joueur après la tranche 1.2 a été net :
« sans animation, VFX ni SFX, il n'y a rien à ressentir ». Un combat sans retour
visuel n'est pas seulement moins agréable, il n'est pas **testable** : on ne sait
ni si on a paré, ni ce qu'on a encaissé.

**Décision.** Un `id = 0` joue une **pose procédurale** de même durée, décrite en
données dans `Config/Poses`. La durée vient de la même source que le frame data,
donc l'impact visuel ne peut pas dériver de l'impact réel.

Et surtout, la règle qui empêche ce dispositif de pourrir : **toute clé
d'animation doit être servie par exactement un des trois cas** — asset réel, pose
procédurale, ou déclaration explicite dans `Poses.Pending` avec ce qui la
fournira. `ConfigValidator` le vérifie au boot ; un oubli fait échouer le
démarrage au lieu de produire un personnage figé au milieu d'un combat.

Le corollaire qui a le plus changé le contenu de la tranche : **un état
atteignable a un visuel**. `Knocked` est atteignable depuis la 1.2 — le finisher
envoie au sol — donc ses poses sont écrites maintenant, pas « en 1.6 avec le
ragdoll ». Ce qui reste dans `Pending` n'y est que parce qu'aucun code ne sait
encore l'atteindre : la parade (1.4), les dashes (1.5). La locomotion y figure
définitivement, servie par le script `Animate` de Roblox — la doubler ferait
lutter deux systèmes sur les mêmes jointures.

**Deux détails techniques qui portent tout le module.**

L'**ordre d'exécution** : l'`Animator` réécrit `Motor6D.Transform` à chaque frame
pendant l'étape « Character ». Écrire avant elle ne produit rien de visible. On
s'accroche donc à `RenderPriority.Character.Value + 1`, ce qui superpose les poses
à la locomotion au lieu de lutter contre elle.

Le **mélange en moyenne pondérée**, et non en accumulation. `BlockStart` et
`BlockHold` visent les mêmes jointures avec la même cible ; les additionner
produirait une double rotation — bras traversant la tête pendant le recouvrement
des deux lectures. La moyenne rend le relais invisible, et permet à une réaction
d'encaissement de se mélanger à la garde au lieu de l'écraser : le défenseur
encaisse sans jamais paraître baisser les bras.

**Ce que ça ne couvre pas, et c'est daté.** `Motor6D.Transform` n'est pas
répliqué : chaque client pose lui-même les personnages qu'il affiche, et il lui
faut donc leur état. `CombatStateSync` ne part aujourd'hui qu'au propriétaire,
donc **la garde d'un adversaire est invisible pour lui**. Sans effet en 1.3, dont
la surface testable est en solo contre des mannequins sans rig ; bloquant en 1.4,
où lire la garde adverse *est* la mécanique. C'est le premier point de la 1.4,
détaillé dans PHASE1.md §5 — déclaré plutôt que découvert.

---

## Décisions différées (à trancher au moment dit, notées ici pour ne pas être oubliées)

| Sujet | Phase | Pourquoi on attend |
|---|---|---|
| Ragdoll : `PhysicsService` custom vs contraintes sur R15 | 1 | Dépend du coût mesuré sur mobile avec 20 joueurs |
| Territoire de gang (fonctionnalité optionnelle du brief) | 5 | Cross-server MemoryStore : à cadrer une fois les gangs de base jouables |
| Packing `buffer` des payloads de combat | 7 | Uniquement si le budget paquets est dépassé |

*Tranchées depuis : pity du gacha (ADR-010), production des animations
(ADR-009), génération de la map depuis `Config/World` (confirmée avec le
produit, mise en œuvre en Phase 3).*
