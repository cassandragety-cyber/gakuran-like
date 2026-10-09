const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { snipes } = require('../../modules/misc');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('snipe').setDescription('Affiche un message supprimé récemment dans ce salon')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageMessages)
    .addIntegerOption((o) => o.setName('numero').setDescription('1 = le plus récent').setMinValue(1).setMaxValue(10)),
  async run(interaction) {
    const s = snipes.get(interaction.channelId)?.[(interaction.options.getInteger('numero') ?? 1) - 1];
    if (!s) return interaction.reply({ embeds: [ui.error('Aucun message supprimé récemment ici.')], flags: 64 });
    const e = ui.embed(interaction.guild).setAuthor({ name: s.author.username, iconURL: s.author.displayAvatarURL() }).setDescription(`${s.content || '*sans texte*'}\n\nSupprimé ${ts(s.date)}`);
    if (s.attachments[0]) e.setImage(s.attachments[0]);
    await interaction.reply({ embeds: [e] });
  },
};
