const { SlashCommandBuilder, PermissionFlagsBits, EmbedBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { addSanction } = require('../../util/sanctions');
const { modLog } = require('../../util/logs');
const { buildAnnounce } = require('../../util/announce');
const { parseDuration, formatDuration } = require('../../util/time');

const MAX = 28 * 24 * 3600e3; // limite Discord du timeout

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('mute')
    .setDescription('Rend un membre muet (timeout Discord)')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers)
    .addUserOption((o) => o.setName('membre').setDescription('Membre à rendre muet').setRequired(true))
    .addStringOption((o) => o.setName('duree').setDescription('Ex : 10m, 1h, 3j (28j max). Vide = 28 jours'))
    .addStringOption((o) => o.setName('raison').setDescription('Raison').setMaxLength(400)),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    const reason = interaction.options.getString('raison');
    const raw = interaction.options.getString('duree');
    if (!member) return interaction.reply({ embeds: [ui.error('Ce membre n’est pas sur le serveur.')], flags: 64 });
    const duration = raw ? parseDuration(raw) : MAX;
    if (!duration) return interaction.reply({ embeds: [ui.error('Durée invalide. Exemples : `10m`, `1h`, `3j`.')], flags: 64 });
    if (duration > MAX) return interaction.reply({ embeds: [ui.error('Discord limite le mute à **28 jours**.')], flags: 64 });
    const err = checkHierarchy(interaction, member, 'mute');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    if (member.permissions.has(PermissionFlagsBits.Administrator)) return interaction.reply({ embeds: [ui.error('Impossible de mute un administrateur (Discord ne le permet pas).')], flags: 64 });
    await interaction.deferReply();
    await member.timeout(duration, `${interaction.user.tag} : ${reason || 'Aucune raison'}`);
    await member.send({ embeds: [new EmbedBuilder().setColor(ui.COLORS.mute).setTitle(`${ui.E.mute} Tu as été rendu muet sur ${interaction.guild.name}`).setDescription(`**Durée :** ${formatDuration(duration)}\n**Raison :** ${reason || 'Aucune'}`)] }).catch(() => {});
    const id = addSanction(interaction.guild.id, member.id, { type: 'mute', reason, modId: interaction.user.id, duration });
    await modLog(interaction.guild, { action: 'mute', target: member.user, moderator: interaction.user, reason, duration, id });
    await interaction.editReply(await buildAnnounce(interaction.guild, { action: 'mute', user: member.user, moderator: interaction.user, reason, duration, id }));
  },
};
