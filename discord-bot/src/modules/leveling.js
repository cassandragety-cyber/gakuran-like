// Niveaux : XP par message (cooldown 60 s), rôles récompenses.
const db = require('../db');
const ui = require('../util/ui');

const cooldown = new Map();
const xpFor = (level) => 5 * level ** 2 + 50 * level + 100; // XP nécessaire pour passer au niveau suivant

function rankOf(g, userId) {
  const sorted = Object.entries(g.leveling.users).sort((a, b) => b[1].level - a[1].level || b[1].xp - a[1].xp);
  return sorted.findIndex(([id]) => id === userId) + 1 || sorted.length + 1;
}

async function applyRewards(member, level) {
  const rewards = db.guild(member.guild.id).leveling.rewards;
  for (const [lvl, roleId] of Object.entries(rewards)) {
    if (level >= Number(lvl) && !member.roles.cache.has(roleId)) await member.roles.add(roleId, `Niveau ${lvl}`).catch(() => {});
  }
}

function addXp(g, userId, amount) {
  const u = (g.leveling.users[userId] ??= { xp: 0, level: 0 });
  u.xp += amount;
  let up = false;
  while (u.xp >= xpFor(u.level)) { u.xp -= xpFor(u.level); u.level++; up = true; }
  while (u.xp < 0 && u.level > 0) { u.level--; u.xp += xpFor(u.level); }
  if (u.xp < 0) u.xp = 0;
  return { u, up };
}

module.exports = {
  xpFor,
  rankOf,
  addXp,
  applyRewards,
  setup(client) {
    client.on('messageCreate', async (m) => {
      if (!m.guild || m.author.bot || !m.member) return;
      const g = db.guild(m.guild.id);
      if (!g.leveling.enabled) return;
      const key = `${m.guild.id}:${m.author.id}`;
      if (Date.now() - (cooldown.get(key) ?? 0) < 60e3) return;
      cooldown.set(key, Date.now());
      const { u, up } = addXp(g, m.author.id, 15 + Math.floor(Math.random() * 11));
      db.save();
      if (!up) return;
      await applyRewards(m.member, u.level);
      const ch = (g.leveling.channel && m.guild.channels.cache.get(g.leveling.channel)) || m.channel;
      await ch.send({ embeds: [ui.embed(m.guild).setDescription(`🎉 ${m.author} passe au **niveau ${u.level}** !`).setThumbnail(m.author.displayAvatarURL())] }).catch(() => {});
    });
  },
};
