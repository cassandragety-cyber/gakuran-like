// Petits automatismes : snipe, anciens pseudos, pseudos verrouillés, autoreact, menus de rôles, suggestions.
const db = require('../db');
const ui = require('../util/ui');
const { isDangerousRole } = require('../util/perms');

const snipes = new Map(); // channelId → derniers messages supprimés

function pushPrevname(userId, name) {
  if (!name) return;
  const list = (db.global.prevnames[userId] ??= []);
  if (list[0]?.name === name) return;
  list.unshift({ name, date: Date.now() });
  list.length = Math.min(list.length, 20);
  db.save();
}

module.exports = {
  snipes,
  setup(client) {
    client.on('messageDelete', (m) => {
      if (!m.guild || m.author?.bot || (!m.content && !m.attachments?.size)) return;
      const list = snipes.get(m.channelId) ?? [];
      list.unshift({ content: m.content, author: m.author, attachments: m.attachments?.map((a) => a.url) ?? [], date: Date.now() });
      snipes.set(m.channelId, list.slice(0, 10));
    });

    client.on('userUpdate', (o, n) => {
      if (o.username !== n.username) pushPrevname(n.id, o.username);
      if (o.globalName && o.globalName !== n.globalName) pushPrevname(n.id, o.globalName);
    });

    client.on('guildMemberUpdate', async (o, n) => {
      if (!o.partial && o.nickname && o.nickname !== n.nickname) pushPrevname(n.id, o.nickname);
      const locked = db.guild(n.guild.id).locknames[n.id];
      if (locked && n.nickname !== locked) await n.setNickname(locked, 'Pseudo verrouillé').catch(() => {});
    });

    client.on('messageCreate', async (m) => {
      if (!m.guild || m.author.bot) return;
      const emojis = db.guild(m.guild.id).autoreact[m.channelId];
      if (emojis?.length) for (const e of emojis) await m.react(e).catch(() => {});
    });
  },
  components: {
    // Bouton d'un menu de rôles : rolemenu:<roleId>
    async rolemenu(interaction) {
      const roleIds = interaction.isStringSelectMenu() ? interaction.values : [interaction.customId.split(':')[1]];
      const added = [];
      const removed = [];
      // Un menu déroulant remplace la sélection : on retire les rôles du menu non choisis
      const all = interaction.isStringSelectMenu() ? interaction.component.options.map((o) => o.value) : roleIds;
      for (const id of all) {
        const role = interaction.guild.roles.cache.get(id);
        if (!role || isDangerousRole(role) || role.position >= interaction.guild.members.me.roles.highest.position) continue;
        const has = interaction.member.roles.cache.has(id);
        const want = interaction.isStringSelectMenu() ? roleIds.includes(id) : !has;
        if (want && !has) { await interaction.member.roles.add(role, 'Menu de rôles'); added.push(role); }
        if (!want && has) { await interaction.member.roles.remove(role, 'Menu de rôles'); removed.push(role); }
      }
      const text = [added.length && `➕ ${added.join(', ')}`, removed.length && `➖ ${removed.join(', ')}`].filter(Boolean).join('\n') || 'Aucun changement.';
      await interaction.reply({ embeds: [ui.info(text, interaction.guild)], flags: 64 });
    },
  },
};
