const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { modLog } = require('../../util/logs');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('unmute')
    .setDescription('Retire le mute d’un membre, ou de tout le monde')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers)
    .addUserOption((o) => o.setName('membre').setDescription('Membre à unmute (vide + tous = tout le serveur)'))
    .addBooleanOption((o) => o.setName('tous').setDescription('Retirer TOUS les mutes en cours')),
  async run(interaction) {
    if (interaction.options.getBoolean('tous')) {
      await interaction.deferReply();
      const members = await interaction.guild.members.fetch();
      const muted = members.filter((m) => m.isCommunicationDisabled());
      for (const m of muted.values()) await m.timeout(null, `unmute général par ${interaction.user.tag}`).catch(() => {});
      await modLog(interaction.guild, { action: 'unmute', moderator: interaction.user, extra: `**${muted.size}** membres unmute (unmute général)` });
      return interaction.editReply({ embeds: [ui.success(`**${muted.size}** membre(s) ne sont plus muets.`)] });
    }
    const member = interaction.options.getMember('membre');
    if (!member) return interaction.reply({ embeds: [ui.error('Précise un membre, ou active l’option `tous`.')], flags: 64 });
    if (!member.isCommunicationDisabled()) return interaction.reply({ embeds: [ui.error(`${member} n’est pas muet.`)], flags: 64 });
    await member.timeout(null, `Unmute par ${interaction.user.tag}`);
    await modLog(interaction.guild, { action: 'unmute', target: member.user, moderator: interaction.user });
    await interaction.reply({ embeds: [ui.success(`${ui.E.unmute} ${member} peut de nouveau parler.`)] });
  },
};
