const { SlashCommandBuilder, PermissionFlagsBits, EmbedBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { addSanction } = require('../../util/sanctions');
const { modLog } = require('../../util/logs');
const { buildAnnounce } = require('../../util/announce');
const antiraid = require('../../modules/antiraid');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('kick')
    .setDescription('Expulse un membre du serveur')
    .setDefaultMemberPermissions(PermissionFlagsBits.KickMembers)
    .addUserOption((o) => o.setName('membre').setDescription('Membre à expulser').setRequired(true))
    .addStringOption((o) => o.setName('raison').setDescription('Raison').setMaxLength(400)),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    const reason = interaction.options.getString('raison');
    if (!member) return interaction.reply({ embeds: [ui.error('Ce membre n’est pas sur le serveur.')], flags: 64 });
    const err = checkHierarchy(interaction, member, 'expulser');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    if (!(await antiraid.trackModAction(interaction.member, 'antikick')))
      return interaction.reply({ embeds: [ui.error('Limite d’expulsions atteinte : action bloquée par l’antiraid.')], flags: 64 });
    await interaction.deferReply();
    await member.send({ embeds: [new EmbedBuilder().setColor(ui.COLORS.kick).setTitle(`${ui.E.kick} Tu as été expulsé de ${interaction.guild.name}`).setDescription(`**Raison :** ${reason || 'Aucune'}`)] }).catch(() => {});
    await member.kick(`${interaction.user.tag} : ${reason || 'Aucune raison'}`);
    const id = addSanction(interaction.guild.id, member.id, { type: 'kick', reason, modId: interaction.user.id });
    await modLog(interaction.guild, { action: 'kick', target: member.user, moderator: interaction.user, reason, id });
    await interaction.editReply(await buildAnnounce(interaction.guild, { action: 'kick', user: member.user, moderator: interaction.user, reason, id }));
  },
};
