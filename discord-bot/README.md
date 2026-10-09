# Bot Discord — modération, antiraid, musique

Bot tout-en-un en français, **100 % commandes `/`** :

- 🔨 **Modération** avec annonces stylées : chaque ban / kick / mute / warn / unban fait apparaître un **GIF animé** dans le salon (GIF anime façon *domain expansion*, Gojo, Sukuna… ou une carte animée générée avec l'avatar de la cible)
- 🛡️ **Antiraid** sur 17 modules, qui annule l'action et punit son auteur (salons, rôles, webhooks, bots, bans/kicks en masse, @everyone, liens, spam, vagues d'arrivées…)
- 🎵 **Musique** intégrée (YouTube, SoundCloud, liens Spotify, playlists) avec lecteur à boutons et filtres audio
- 🎮 **Mini-jeux** : morpion, puissance 4, pierre-feuille-ciseaux (contre un membre ou le bot), pendu, démineur, snake, mémoire, rapido, nombre mystère, avec classements
- 📜 Logs complets, 🎫 tickets, 🎉 giveaways, 👋 bienvenue avec carte image, 📨 suivi des invitations, 🏆 niveaux, 🔊 vocaux temporaires, 💾 sauvegardes du serveur
- 🏗️ **`/setup-serveur`** : construit tout un serveur (rôles, catégories, salons, logs, tickets…) en une commande

---

## Installation sur ton PC (Windows)

### 1. Créer le bot sur Discord
1. Va sur <https://discord.com/developers/applications> → **New Application** → donne un nom.
2. Onglet **Bot** :
   - **Reset Token** → copie le token (garde-le secret).
   - Active **Server Members Intent** et **Message Content Intent** (section *Privileged Gateway Intents*), puis **Save**.
3. Onglet **OAuth2 → URL Generator** : coche `bot` et `applications.commands`, puis la permission **Administrator**. Ouvre le lien généré et invite le bot sur ton serveur.
   *(Le lien d'invitation s'affiche aussi dans la console au démarrage du bot.)*

### 2. Installer Node.js
Télécharge la version **LTS** sur <https://nodejs.org> et installe-la (options par défaut).

### 3. Installer et lancer le bot
1. Télécharge ce dossier `discord-bot` (bouton **Code → Download ZIP** sur GitHub, puis dézippe).
2. Double-clique sur **`INSTALLER.bat`**. Il installe tout et ouvre le fichier `.env` dans le Bloc-notes.
3. Dans `.env`, remplis :
   - `TOKEN=` ton token
   - `OWNER_IDS=` ton ID Discord (Paramètres Discord → Avancés → active le **Mode développeur**, puis clic droit sur ton profil → **Copier l'identifiant**)
4. Double-clique sur **`DEMARRER.bat`**. Quand tu vois `✅ Connecté en tant que…`, le bot est en ligne.

> Le bot tourne **tant que la fenêtre est ouverte et que le PC est allumé**. `DEMARRER.bat` le relance tout seul s'il plante.
> Sur Linux / macOS : `./demarrer.sh`.

### 4. Configurer le serveur
1. Dans **Paramètres du serveur → Rôles**, glisse le rôle du bot **tout en haut** (sinon il ne peut ni sanctionner ni protéger).
2. Tape **`/setup-serveur`** : le bot crée les rôles, les catégories, le règlement, la bienvenue, les tickets, les vocaux temporaires, les logs, et active l'antiraid recommandé.
   (Option `reinitialiser:True` pour repartir d'un serveur vide — **supprime tout l'existant**.)
3. **`/secur`** pour voir et régler les protections, **`/whitelist ajouter`** pour tes modérateurs de confiance.

---

## GIF des sanctions

Quand tu bannis, kick, mute, warn ou débannis quelqu'un, un embed apparaît dans le salon avec un GIF :

| Mode (`/style gifs`) | Ce qui s'affiche |
|---|---|
| **anime** (défaut) | GIF anime trouvés automatiquement : *domain expansion*, Gojo, Sukuna, hollow purple, black flash… + tes GIF perso |
| **perso** | Uniquement les GIF que tu as ajoutés |
| **carte** | Une carte animée générée avec l'avatar de la cible (marteau qui frappe, botte qui éjecte, tampon « BANNI »…) |
| **off** | Pas de GIF |

- **Ajouter tes GIF** : `/style gif-ajouter action:ban lien:https://klipy.com/gifs/domain-expansion-gojo-4`. Les liens de page Klipy, Tenor et Giphy sont acceptés, le bot en extrait le GIF. Tu peux en mettre plusieurs par sanction, il en tire un au hasard.
- **Plus de GIF anime** : crée une clé API gratuite sur <https://partner.klipy.com> et mets-la dans `.env` (`KLIPY_API_KEY=`). Sans clé, le bot utilise des API anime publiques (nekos.best, waifu.pics).
- Si aucun site ne répond, le bot affiche la carte animée à la place.
- **Aperçu** : `/style apercu action:ban`.

---

## Commandes

`<obligatoire>` `[facultatif]` — détail de chaque commande : `/help commande:<nom>`.

**🔨 Modération** — `/ban` `/tempban ajouter|liste` `/unban` `/kick` `/mute [durée]` `/unmute [tous]` `/warn` `/sanctions liste|supprimer|effacer|tout-effacer` `/clear <nombre> [membre] [bots]` `/lock` `/unlock` `/hide` `/unhide` (salon, catégorie ou `tout`) `/slowmode` `/nick set|reset` `/lockname set|retirer|liste` `/role ajouter [durée]|retirer|temporaires|masse` `/derank` `/cmute ajouter|retirer` `/note ajouter|retirer|liste` `/banlist` `/mutelist` `/unbanall` `/renew`

**🛡️ Sécurité** — `/secur [etat]` (panneau interactif) `/antiraid module <module> <on|max|off> [nombre] [secondes]` `/antiraid punition <module|tous> <derank|derank_timeout|kick|ban>` `/whitelist ajouter|retirer|liste` `/blacklist ajouter [partout]|retirer|info|liste` `/securite raidmode|createlimit|pingraid|noderank|antilink|ignorer|antirank` `/badwords on|off|ajouter|retirer|liste`

**📜 Logs** — `/logs auto [staff]` `/logs set <type> [salon]` `/logs voir`

**⚙️ Serveur** — `/setup-serveur` `/ticket setup|fermer|ajouter|retirer|renommer|claim` `/tempvoc setup|nom|limite|prive|public|invisible|visible|ajouter|retirer|expulser` `/giveaway lancer|terminer|reroll|participants` `/suggestion envoyer|salon` `/rolemenu` `/embed` `/say` `/autoreact` `/bienvenue arrivee|depart|autorole|test|voir` `/invites voir|classement|bonus|reset` `/vocal kick|deplacer|rassembler|vider` `/backup creer|liste|info|charger|supprimer` `/style couleur|gifs|gif-ajouter|gif-retirer|gif-liste|apercu`

**🎵 Musique** — `/play <titre ou lien> [ensuite]` `/recherche` `/skip [jusqua]` `/stop` `/pause` `/nowplaying` `/queue` `/volume` `/loop` `/shuffle` `/remove` `/seek` `/filtre` (bassboost, nightcore, vaporwave, 8D, slowed + reverb…)

**🎮 Jeux** — `/jeu morpion [adversaire]` `/jeu puissance4 [adversaire]` `/jeu pfc [adversaire]` (sans adversaire = contre le bot) `/jeu pendu` `/jeu rapido` `/jeu nombre [max]` (tout le salon joue) `/jeu demineur` `/jeu snake` `/jeu memoire` `/jeu classement <jeu>` `/jeu stats [membre]`

**🏆 Niveaux** — `/level` `/classement [niveaux|invitations]` `/leveling on|off|salon|recompense|recompenses|xp|reset`

**🧰 Utilitaire** — `/help` `/userinfo` `/serverinfo` `/avatar [avatar|serveur|bannière]` `/roleinfo` `/channelinfo` `/ping` `/snipe` `/liste admins|bots|boosters|botadmins|vocal` `/calc` `/emoji image|voler` `/wiki` `/prevname`

**🤖 Bot** (owners) — `/bot statut|activite|nom|avatar|serveurs|quitter` `/owner ajouter|retirer|liste|blbot`

---

## Hiérarchie des droits

| Grade | Qui | Peut |
|---|---|---|
| **Buyer** | IDs dans `OWNER_IDS` (.env) | Tout, y compris gérer les owners |
| **Owner** | Ajoutés via `/owner ajouter` | Sécurité et contrôle du bot sur tous les serveurs |
| **Propriétaire du serveur** | — | Sécurité, backups, setup sur son serveur |
| **Whitelist** | `/whitelist` | Ignorés par l'antiraid, sauf modules en mode **max** |

Les commandes de modération utilisent les permissions Discord (Bannir, Expulser, Exclure temporairement…). Le bot vérifie aussi la hiérarchie des rôles : on ne peut pas sanctionner quelqu'un de plus haut que soi.

## Comment l'antiraid protège

Le bot lit le journal d'audit en direct. Si quelqu'un qui n'est pas whitelisté crée, supprime ou modifie un salon ou un rôle, ajoute un bot ou un webhook, donne un rôle dangereux, etc., l'action est **annulée** (salon ou rôle recréé, bot banni, webhook supprimé…) et l'auteur est **puni** (derank par défaut, réglable avec `/antiraid punition`). Les bans, kicks et unbans sont limités (3 en 10 s par défaut), y compris quand ils passent par les commandes du bot. Tout est envoyé dans le salon `raid-logs`.

## Dépannage

- **Les commandes `/` n'apparaissent pas** : attends quelques secondes après le démarrage, puis recharge Discord (Ctrl+R).
- **« Disallowed intents »** : active les deux intents de l'étape 1.
- **« Mon rôle est trop bas »** : monte le rôle du bot tout en haut.
- **La musique ne joue pas** : le bot télécharge `yt-dlp` au premier lancement (dossier `bin`). Si YouTube bloque, mets à jour avec `node scripts/ytdlp.js --force`, ou exporte tes cookies YouTube (extension « Get cookies.txt LOCALLY ») et indique le chemin du fichier dans `YT_COOKIES=` du `.env`.
- **Vérifier l'installation** : `npm run check` contrôle toutes les commandes sans se connecter à Discord.

Les données (sanctions, réglages, sauvegardes) sont stockées dans le dossier `data/`.
