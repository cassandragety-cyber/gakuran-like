const { SlashCommandBuilder, PermissionFlagsBits, ActionRowBuilder, ButtonBuilder, ButtonStyle } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { modLog } = require('../../util/logs');

module.exports = {
  category: 'Modération',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('unbanall')
    .setDescription('Débannit TOUT le monde (sauf la blacklist)')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator),
  async run(interaction) {
    const row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId('ok').setLabel('Oui, tout débannir').setStyle(ButtonStyle.Danger),
      new ButtonBuilder().setCustomId('no').setLabel('Annuler').setStyle(ButtonStyle.Secondary),
    );
    const msg = await interaction.reply({ embeds: [ui.info(`${ui.E.warn} Débannir **tous** les membres bannis ?`, interaction.guild)], components: [row], withResponse: true });
    const click = await msg.resource.message.awaitMessageComponent({ filter: (i) => i.user.id === interaction.user.id, time: 30e3 }).catch(() => null);
    if (click?.customId !== 'ok') return interaction.editReply({ embeds: [ui.info('Annulé.', interaction.guild)], components: [] });
    await click.update({ embeds: [ui.info(`${ui.E.load} Débannissement en cours…`, interaction.guild)], components: [] });
    const bl = db.guild(interaction.guild.id).security.blacklist;
    const bans = await interaction.guild.bans.fetch();
    let n = 0;
    for (const b of bans.values()) {
      if (bl[b.user.id]) continue;
      await interaction.guild.members.unban(b.user.id, `unbanall par ${interaction.user.tag}`).then(() => n++).catch(() => {});
    }
    await modLog(interaction.guild, { action: 'unban', moderator: interaction.user, extra: `**${n}** utilisateurs débannis (unbanall)` });
    await interaction.editReply({ embeds: [ui.success(`**${n}** utilisateur(s) débanni(s).`)] });
  },
};
