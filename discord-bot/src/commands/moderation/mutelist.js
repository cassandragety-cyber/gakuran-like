const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('mutelist')
    .setDescription('Liste des membres actuellement muets')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers),
  async run(interaction) {
    await interaction.deferReply();
    const muted = (await interaction.guild.members.fetch()).filter((m) => m.isCommunicationDisabled());
    await interaction.editReply({ embeds: [ui.embed(interaction.guild).setTitle(`${ui.E.mute} Membres muets (${muted.size})`)
      .setDescription(muted.map((m) => `${ui.E.dot} ${m} — fin ${ts(m.communicationDisabledUntil)}`).join('\n').slice(0, 4000) || 'Personne n’est muet.')] });
  },
};
