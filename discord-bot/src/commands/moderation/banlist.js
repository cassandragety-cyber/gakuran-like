const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { paginate, chunk } = require('../../util/paginate');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('banlist')
    .setDescription('Affiche la liste des bannis')
    .setDefaultMemberPermissions(PermissionFlagsBits.BanMembers),
  async run(interaction) {
    await interaction.deferReply();
    const bans = [...(await interaction.guild.bans.fetch()).values()];
    const pages = chunk(bans, 15);
    await paginate(interaction, Math.max(1, pages.length), (p) => ui.embed(interaction.guild)
      .setTitle(`${ui.E.ban} Bannis (${bans.length})`)
      .setDescription(bans.length ? pages[p].map((b) => `${ui.E.dot} **${b.user.username}** \`${b.user.id}\` — ${ui.truncate(b.reason || 'aucune raison', 60)}`).join('\n') : 'Aucun banni.'));
  },
};
