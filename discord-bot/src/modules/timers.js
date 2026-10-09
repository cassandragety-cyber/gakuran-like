// Tâches planifiées : fin des tempbans, rôles temporaires, giveaways.
const db = require('../db');
const { modLog } = require('../util/logs');

async function tick(client) {
  const now = Date.now();
  for (const [guildId, g] of db.allGuilds()) {
    const guild = client.guilds.cache.get(guildId);
    if (!guild || !g.timers?.length) continue;
    const due = g.timers.filter((t) => t.at <= now);
    if (!due.length) continue;
    g.timers = g.timers.filter((t) => t.at > now);
    db.save();
    for (const t of due) {
      try {
        if (t.type === 'unban') {
          if (g.security?.blacklist?.[t.userId]) continue;
          await guild.members.unban(t.userId, 'Fin du tempban');
          await modLog(guild, { action: 'unban', target: await client.users.fetch(t.userId).catch(() => null), reason: 'Fin du bannissement temporaire' });
        } else if (t.type === 'unrole') {
          const m = await guild.members.fetch(t.userId).catch(() => null);
          await m?.roles.remove(t.roleId, 'Fin du rôle temporaire');
        }
      } catch (err) {
        console.warn(`[timers] ${t.type} ${t.userId} :`, err.message);
      }
    }
  }
  await require('./giveaways').tick(client).catch((e) => console.error('[giveaways]', e));
}

module.exports = {
  setup(client) {
    client.on('botReady', () => {
      tick(client);
      setInterval(() => tick(client), 15e3);
    });
  },
};
