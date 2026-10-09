const { Client, GatewayIntentBits, Partials, ActivityType } = require('discord.js');
const config = require('./config');
const db = require('./db');
const { loadCommands, loadModules, registerGuild } = require('./handlers/commands');

if (!config.token || config.token === 'colle_ton_token_ici') {
  console.error('\n❌ Aucun token trouvé. Copie .env.example en .env et colle le token de ton bot dedans.\n');
  process.exit(1);
}
if (!config.ownerIds.length) console.warn('⚠️  OWNER_IDS est vide dans .env : personne n’aura les droits « buyer » sur le bot.');

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildModeration,
    GatewayIntentBits.GuildExpressions,
    GatewayIntentBits.GuildWebhooks,
    GatewayIntentBits.GuildInvites,
    GatewayIntentBits.GuildVoiceStates,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.GuildMessageReactions,
    GatewayIntentBits.MessageContent,
  ],
  partials: [Partials.Message, Partials.Channel, Partials.GuildMember, Partials.User, Partials.Reaction],
  allowedMentions: { parse: ['users'], repliedUser: false },
});

const { commands, components } = loadCommands();
client.commands = commands;
client.components = components;
require('./handlers/interactions')(client);
loadModules(client, components);

const ACTIVITY_TYPES = {
  playing: ActivityType.Playing, streaming: ActivityType.Streaming, listening: ActivityType.Listening,
  watching: ActivityType.Watching, competing: ActivityType.Competing, custom: ActivityType.Custom,
};

// Statut du bot (configurable via /bot activite) avec rotation des textes séparés par ,,
let rotation = 0;
client.applyPresence = () => {
  const p = db.global.presence;
  const texts = p.activities.length ? p.activities : [`/help • ${config.botName}`];
  const name = texts[rotation++ % texts.length];
  const type = ACTIVITY_TYPES[p.type] ?? ActivityType.Playing;
  client.user.setPresence({
    status: p.status,
    activities: [{ name, type, state: type === ActivityType.Custom ? name : undefined, url: type === ActivityType.Streaming ? 'https://twitch.tv/discord' : undefined }],
  });
};

client.once('clientReady', async () => {
  console.log(`\n✅ Connecté en tant que ${client.user.tag} sur ${client.guilds.cache.size} serveur(s).`);
  console.log(`🔗 Invitation : https://discord.com/oauth2/authorize?client_id=${client.user.id}&permissions=8&scope=bot%20applications.commands\n`);
  client.applyPresence();
  setInterval(client.applyPresence, 20_000);
  for (const guild of client.guilds.cache.values()) await registerGuild(guild, commands);
  console.log(`📜 ${commands.size} commandes / enregistrées.`);
  client.emit('botReady');
});

client.on('guildCreate', (guild) => registerGuild(guild, commands));

process.on('unhandledRejection', (err) => console.error('[erreur non gérée]', err));
process.on('SIGINT', () => {
  db.flush();
  process.exit(0);
});

client.login(config.token).catch((err) => {
  console.error(`\n❌ Connexion à Discord impossible : ${err.message}`);
  if (/token/i.test(err.message) || err.code === 'TokenInvalid') console.error('   → Vérifie le TOKEN dans le fichier .env (Developer Portal → Bot → Reset Token).');
  if (/disallowed intents/i.test(err.message)) console.error('   → Active « Server Members Intent » et « Message Content Intent » dans Developer Portal → Bot.');
  process.exit(1);
});
