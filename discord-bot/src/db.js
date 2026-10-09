// Base de données JSON : un seul fichier, écrit de façon atomique et groupée.
// Suffisant pour un bot hébergé sur un PC (quelques serveurs), aucune installation requise.
const fs = require('node:fs');
const path = require('node:path');
const { dataDir } = require('./config');

const FILE = path.join(dataDir, 'db.json');

const ANTIRAID_MODULES = [
  'antibot', 'antichannel', 'antirole', 'antiwebhook', 'antiban', 'antikick', 'antiunban',
  'antirank', 'antiupdate', 'antiemote', 'antithread', 'antideco', 'antiautomod',
  'antieveryone', 'antilink', 'antispam', 'antitoken',
];

function guildDefaults() {
  return {
    color: null,
    logs: { mod: null, message: null, raid: null, role: null, voice: null, boost: null, member: null },
    security: {
      modules: Object.fromEntries(ANTIRAID_MODULES.map((m) => [m, 'off'])),
      limits: {
        antiban: { count: 3, window: 10 },
        antikick: { count: 3, window: 10 },
        antiunban: { count: 3, window: 10 },
        antideco: { count: 5, window: 10 },
        antieveryone: { count: 1, window: 10 },
        antispam: { count: 6, window: 4 },
        antitoken: { count: 8, window: 10 },
      },
      punish: { default: 'derank' },
      whitelist: { users: [], roles: [] },
      blacklist: {},
      badwords: { enabled: false, words: [] },
      createlimit: 0,
      raidmode: false,
      raidmodeUntil: 0,
      antilinkMode: 'invites',
      ignored: { antilink: [], antispam: [] },
      noderank: [],
      pingraid: null,
      antirankType: 'danger',
      antirankIgnore: [],
    },
    style: { gifs: true, mode: 'anime', customGifs: {} },
    sanctions: {},
    sanctionCounter: 0,
    notes: {},
    locknames: {},
    cmutes: {},
    timers: [],
    tickets: { category: null, staffRole: null, counter: 0, open: {} },
    tempvoc: { hub: null, category: null, channels: {} },
    giveaways: {},
    suggestions: { channel: null },
    autoreact: {},
    welcome: { channel: null, message: null, card: true, dm: null, autoroles: [] },
    leave: { channel: null, message: null },
    invites: {},
    joinedBy: {},
    leveling: { enabled: false, channel: null, rewards: {}, users: {} },
    games: {},
  };
}

function globalDefaults() {
  return { owners: [], blbot: [], prevnames: {}, presence: { status: 'online', activities: [], type: 'playing' } };
}

// Complète un objet avec les valeurs par défaut manquantes, sans écraser l'existant.
function fill(target, defaults) {
  for (const [k, v] of Object.entries(defaults)) {
    if (!(k in target)) target[k] = structuredClone(v);
    else if (v && typeof v === 'object' && !Array.isArray(v) && target[k] && typeof target[k] === 'object') fill(target[k], v);
  }
  return target;
}

let data = { global: {}, guilds: {} };
try {
  if (fs.existsSync(FILE)) data = JSON.parse(fs.readFileSync(FILE, 'utf8'));
} catch (err) {
  console.error('[db] fichier illisible, sauvegarde en .corrupt et repart de zéro :', err.message);
  fs.copyFileSync(FILE, `${FILE}.corrupt-${Date.now()}`);
}
data.guilds ??= {};
fill((data.global ??= {}), globalDefaults());

let timer = null;
function writeNow() {
  timer = null;
  fs.mkdirSync(dataDir, { recursive: true });
  const tmp = `${FILE}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, FILE);
}

const db = {
  ANTIRAID_MODULES,
  guild(id) {
    const g = (data.guilds[id] ??= {});
    return fill(g, guildDefaults());
  },
  get global() {
    return data.global;
  },
  allGuilds() {
    return Object.entries(data.guilds);
  },
  save() {
    if (!timer) timer = setTimeout(writeNow, 1000);
  },
  flush() {
    if (timer) clearTimeout(timer);
    writeNow();
  },
};

process.on('exit', () => timer && writeNow());

module.exports = db;
