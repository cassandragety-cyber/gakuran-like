# Banchou

Jeu Roblox de vie lycéenne et de combat mêlée PvP dans une ville japonaise de
2007. Le cœur du jeu est un combat au corps-à-corps basé sur le skill (chain,
garde, parry, dash) doublé d'un style de combat tiré au sort à la création du
personnage.

Documentation : [PLAN](docs/PLAN.md) · [DÉCISIONS](docs/DECISIONS.md) ·
[COMBAT](docs/COMBAT.md) · [ANIMATIONS](docs/ANIMATIONS.md) ·
[MODÈLE DE MENACE](docs/THREAT_MODEL.md) · [TESTS](docs/TESTING.md)

**État : tranche 1.1 terminée** — état de combat autoritatif, machine à états à
huit états, sprint, réglage à chaud et panneau de debug F2. Le chain d'attaque
arrive en tranche 1.2. Découpage complet dans [PHASE1.md](docs/PHASE1.md).

---

## Prérequis

- **Roblox Studio**
- **[Rokit](https://github.com/rojo-rbx/rokit)** — gestionnaire d'outils. Il
  installe Rojo, Wally, Selene et StyLua aux versions épinglées dans
  `rokit.toml`, ce qui évite le grand classique « ça lint chez moi ».
- **Plugin Rojo pour Studio** — installable depuis Studio, onglet Plugins, ou
  via `rojo plugin install`.

## Installation

```bash
rokit install          # rojo, wally, selene, stylua aux versions épinglées
wally install          # dépendances -> Packages/ (facultatif en Phase 0)
selene generate-roblox-std   # génère roblox.toml, le std de lint (non commité)
rojo sourcemap default.project.json -o sourcemap.json   # types dans l'éditeur
```

`wally install` est **nécessaire** depuis la tranche 1.1 : le nettoyage des
connexions de personnage passe par Trove. Le serveur refuse de démarrer avec un
message explicite si les dépendances manquent, plutôt que d'échouer sur une erreur
de `require` illisible.

## Développer

```bash
rojo serve
```

Puis, dans Roblox Studio : ouvrir une place vide, onglet **Plugins → Rojo →
Connect**. Le contenu de `src/` apparaît dans l'arbre et se synchronise à chaque
sauvegarde de fichier. On édite dans son éditeur, jamais dans Studio : les
scripts de l'arbre synchronisé sont écrasés à la prochaine sauvegarde.

Pour produire une place complète à partir de zéro :

```bash
rojo build default.project.json -o Banchou.rbxlx
```

## Activer la persistance des données en Studio

Les DataStores sont inaccessibles depuis Studio tant que l'accès aux API n'est
pas autorisé. À faire avant la Phase 2, sans avoir besoin de publier le jeu au
public :

1. Créer l'expérience sous le **groupe** propriétaire (Creator Hub → Create →
   Experience → choisir le groupe comme créateur). Elle peut rester en privé.
2. Dans Studio, ouvrir cette place (**File → Open from Roblox**), sinon Studio
   ne sait pas à quelle expérience rattacher les données.
3. **File → Game Settings → Security** → activer **Enable Studio Access to API
   Services**, puis Save.
4. Toujours dans Security, activer **Allow HTTP Requests** si l'on veut tester
   l'envoi d'analytics.

Sans l'étape 1, l'option de l'étape 3 existe mais n'a aucun effet utile : les
données seraient écrites sur une expérience personnelle et non sur celle du
groupe.

## Contrôle qualité

```bash
./scripts/check.sh
```

Le script enchaîne : format StyLua, lint Selene, absence de boucle d'attente
active, limite de 300 lignes par module, présence de `--!strict` partout. Il
doit passer avant chaque commit.

Formater automatiquement : `stylua src/`.

## Structure

```
src/
├── ReplicatedStorage/
│   ├── Shared/   modules purs, réutilisables des deux côtés
│   │   └── Combat/  règles appliquées à l'identique par le client et le serveur
│   ├── Config/   données d'équilibrage — aucune logique
│   └── Net/      contrat réseau typé + middleware
├── ServerScriptService/
│   ├── Services/ services avec état, connaissent l'API Roblox
│   └── Systems/  logique pure, testable
├── StarterPlayer/StarterPlayerScripts/
│   └── Controllers/
└── ServerStorage/
```

## Règles du projet

- `--!strict` en tête de chaque module, interfaces publiques typées.
- **300 lignes maximum par module**, une responsabilité par module.
- **Toute valeur d'équilibrage vit dans `Config/`.** Un nombre de gameplay codé
  en dur dans un service est un bug : on doit pouvoir rééquilibrer le jeu sans
  ouvrir un script de gameplay.
- **Aucun remote hors de `Net/Definitions`.** Chaque remote a une limite de
  cadence et une ligne dans [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).
- Pas de `while true do wait()` : `RunService` avec accumulateur, ou `task.delay`.
- **Aucun module de combat ne lit `Config` au runtime** : la table d'équilibrage
  arrive en argument (ADR-011). C'est ce qui rend la logique testable avec des
  valeurs fabriquées et réglable à chaud sans invalidation à propager.
- Les commentaires expliquent *pourquoi*, jamais *quoi*.
