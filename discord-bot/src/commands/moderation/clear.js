const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { modLog } = require('../../util/logs');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('clear')
    .setDescription('Supprime des messages dans le salon')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageMessages)
    .addIntegerOption((o) => o.setName('nombre').setDescription('Nombre de messages (1-1000)').setMinValue(1).setMaxValue(1000).setRequired(true))
    .addUserOption((o) => o.setName('membre').setDescription('Ne supprimer que les messages de ce membre'))
    .addBooleanOption((o) => o.setName('bots').setDescription('Ne supprimer que les messages de bots')),
  async run(interaction) {
    const amount = interaction.options.getInteger('nombre', true);
    const user = interaction.options.getUser('membre');
    const botsOnly = interaction.options.getBoolean('bots');
    await interaction.deferReply({ flags: 64 });
    let deleted = 0;
    let before;
    let scanned = 0;
    // Discord ne supprime en masse que les messages de moins de 14 jours, par paquets de 100
    while (deleted < amount && scanned < 5000) {
      const batch = await interaction.channel.messages.fetch({ limit: 100, before });
      if (!batch.size) break;
      scanned += batch.size;
      before = batch.last().id;
      const young = batch.filter((m) => Date.now() - m.createdTimestamp < 14 * 864e5 && !m.pinned);
      let pick = young.filter((m) => (!user || m.author.id === user.id) && (!botsOnly || m.author.bot));
      pick = pick.first(amount - deleted);
      if (pick.length) deleted += (await interaction.channel.bulkDelete(pick, true)).size;
      if (young.size < batch.size) break; // on a atteint les messages trop vieux
    }
    await modLog(interaction.guild, { action: 'clear', moderator: interaction.user, extra: `🧹 **${deleted}** message(s) supprimé(s) dans ${interaction.channel}${user ? ` (de ${user})` : ''}` });
    await interaction.editReply({ embeds: [ui.success(`🧹 **${deleted}** message(s) supprimé(s).`)] });
  },
};
