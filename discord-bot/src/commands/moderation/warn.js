const { SlashCommandBuilder, PermissionFlagsBits, EmbedBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { addSanction } = require('../../util/sanctions');
const { modLog } = require('../../util/logs');
const { buildAnnounce } = require('../../util/announce');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('warn')
    .setDescription('Donne un avertissement à un membre')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers)
    .addUserOption((o) => o.setName('membre').setDescription('Membre à avertir').setRequired(true))
    .addStringOption((o) => o.setName('raison').setDescription('Raison').setRequired(true).setMaxLength(400)),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    const reason = interaction.options.getString('raison', true);
    if (!member) return interaction.reply({ embeds: [ui.error('Ce membre n’est pas sur le serveur.')], flags: 64 });
    const err = checkHierarchy(interaction, member, 'avertir');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    await interaction.deferReply();
    const id = addSanction(interaction.guild.id, member.id, { type: 'warn', reason, modId: interaction.user.id });
    const warns = db.guild(interaction.guild.id).sanctions[member.id].filter((s) => s.type === 'warn').length;
    await member.send({ embeds: [new EmbedBuilder().setColor(ui.COLORS.warnAction).setTitle(`${ui.E.warn} Avertissement sur ${interaction.guild.name}`).setDescription(`**Raison :** ${reason}\nC’est ton **${warns}ᵉ** avertissement.`)] }).catch(() => {});
    await modLog(interaction.guild, { action: 'warn', target: member.user, moderator: interaction.user, reason, id, extra: `**Total warns :** ${warns}` });
    await interaction.editReply(await buildAnnounce(interaction.guild, { action: 'warn', user: member.user, moderator: interaction.user, reason, id, extra: `**Avertissements :** ${warns}` }));
  },
};
