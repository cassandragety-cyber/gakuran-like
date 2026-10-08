const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { isOwner } = require('../../util/perms');
const { ts } = require('../../util/time');
const { paginate, chunk } = require('../../util/paginate');

module.exports = {
  category: 'Sécurité',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('blacklist')
    .setDescription('Utilisateurs bannis automatiquement, même s’ils reviennent')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Blacklist un utilisateur (ban immédiat)')
      .addUserOption((o) => o.setName('utilisateur').setDescription('Utilisateur ou ID').setRequired(true))
      .addStringOption((o) => o.setName('raison').setDescription('Raison'))
      .addBooleanOption((o) => o.setName('partout').setDescription('Owners du bot : blacklister sur TOUS les serveurs du bot')))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire de la blacklist (et débannit)')
      .addUserOption((o) => o.setName('utilisateur').setDescription('Utilisateur ou ID').setRequired(true)))
    .addSubcommand((s) => s.setName('info').setDescription('Infos blacklist d’un utilisateur')
      .addUserOption((o) => o.setName('utilisateur').setDescription('Utilisateur ou ID').setRequired(true)))
    .addSubcommand((s) => s.setName('liste').setDescription('Affiche la blacklist')),
  async run(interaction, client) {
    const sub = interaction.options.getSubcommand();
    const sec = db.guild(interaction.guild.id).security;
    if (sub === 'liste') {
      const list = Object.entries(sec.blacklist);
      const pages = chunk(list, 12);
      return paginate(interaction, Math.max(1, pages.length), (p) => ui.embed(interaction.guild).setTitle(`⛔ Blacklist (${list.length})`)
        .setDescription(list.length ? pages[p].map(([id, b]) => `${ui.E.dot} <@${id}> \`${id}\` — ${ui.truncate(b.reason || 'aucune raison', 60)}`).join('\n') : 'Vide.'));
    }
    const user = interaction.options.getUser('utilisateur', true);
    if (sub === 'info') {
      const b = sec.blacklist[user.id];
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setAuthor({ name: user.username, iconURL: user.displayAvatarURL() })
        .setDescription(b ? `⛔ **Blacklisté** ${ts(b.date)} par <@${b.by}>\n**Raison :** ${b.reason || 'aucune'}` : `${ui.E.ok} Pas blacklisté.`)] });
    }
    if (sub === 'retirer') {
      delete sec.blacklist[user.id];
      db.save();
      await interaction.guild.members.unban(user.id, `retrait blacklist par ${interaction.user.tag}`).catch(() => {});
      return interaction.reply({ embeds: [ui.success(`${user} retiré de la blacklist et débanni.`)] });
    }
    if (isOwner(user.id) || user.id === interaction.guild.ownerId || user.id === client.user.id) return interaction.reply({ embeds: [ui.error('Impossible de blacklister cet utilisateur.')], flags: 64 });
    const reason = interaction.options.getString('raison');
    const everywhere = interaction.options.getBoolean('partout') && isOwner(interaction.user.id);
    const guilds = everywhere ? [...client.guilds.cache.values()] : [interaction.guild];
    await interaction.deferReply();
    let n = 0;
    for (const g of guilds) {
      db.guild(g.id).security.blacklist[user.id] = { reason, by: interaction.user.id, date: Date.now() };
      await g.members.ban(user.id, { reason: `[Blacklist] ${reason || 'aucune raison'}` }).then(() => n++).catch(() => {});
    }
    db.save();
    await interaction.editReply({ embeds: [ui.embed(interaction.guild).setDescription(`⛔ ${user} est **blacklisté**${everywhere ? ` sur **${n}** serveur(s)` : ''}. Il sera banni à chaque retour.`)] });
  },
};
