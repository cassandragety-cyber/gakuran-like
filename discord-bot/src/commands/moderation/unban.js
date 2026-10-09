const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const db = require('../../db');
const { removeTimer } = require('../../util/sanctions');
const { modLog } = require('../../util/logs');
const { buildAnnounce } = require('../../util/announce');
const antiraid = require('../../modules/antiraid');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('unban')
    .setDescription('Débannit un utilisateur')
    .setDefaultMemberPermissions(PermissionFlagsBits.BanMembers)
    .addStringOption((o) => o.setName('utilisateur').setDescription('ID ou nom de l’utilisateur banni').setRequired(true).setAutocomplete(true))
    .addStringOption((o) => o.setName('raison').setDescription('Raison').setMaxLength(400)),
  async autocomplete(interaction) {
    const q = interaction.options.getFocused().toLowerCase();
    const bans = await interaction.guild.bans.fetch({ limit: 1000 }).catch(() => null);
    if (!bans) return interaction.respond([]);
    await interaction.respond(bans.filter((b) => !q || b.user.username.toLowerCase().includes(q) || b.user.id.startsWith(q))
      .first(25).map((b) => ({ name: `${b.user.username} (${b.user.id})`.slice(0, 100), value: b.user.id })));
  },
  async run(interaction) {
    const id = interaction.options.getString('utilisateur', true).replace(/\D/g, '');
    const reason = interaction.options.getString('raison');
    const ban = await interaction.guild.bans.fetch(id).catch(() => null);
    if (!ban) return interaction.reply({ embeds: [ui.error('Cet utilisateur n’est pas banni.')], flags: 64 });
    if (db.guild(interaction.guild.id).security.blacklist[id])
      return interaction.reply({ embeds: [ui.error('Cet utilisateur est dans la **blacklist** : retire-le avec `/blacklist retirer` d’abord.')], flags: 64 });
    if (!(await antiraid.trackModAction(interaction.member, 'antiunban')))
      return interaction.reply({ embeds: [ui.error('Limite de débannissements atteinte : action bloquée par l’antiraid.')], flags: 64 });
    await interaction.deferReply();
    await interaction.guild.members.unban(id, `${interaction.user.tag} : ${reason || 'Aucune raison'}`);
    removeTimer(interaction.guild.id, (t) => t.type === 'unban' && t.userId === id);
    await modLog(interaction.guild, { action: 'unban', target: ban.user, moderator: interaction.user, reason });
    await interaction.editReply(await buildAnnounce(interaction.guild, { action: 'unban', user: ban.user, moderator: interaction.user, reason }));
  },
};
