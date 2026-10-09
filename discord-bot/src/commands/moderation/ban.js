const { SlashCommandBuilder, PermissionFlagsBits, EmbedBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { addSanction, addTimer } = require('../../util/sanctions');
const { modLog } = require('../../util/logs');
const { buildAnnounce } = require('../../util/announce');
const { formatDuration } = require('../../util/time');
const antiraid = require('../../modules/antiraid');

// Partagé par /ban et /tempban
async function doBan(interaction, { user, reason, duration, deleteSeconds }) {
  const { guild } = interaction;
  const member = await guild.members.fetch(user.id).catch(() => null);
  const err = checkHierarchy(interaction, member, 'bannir');
  if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
  if (await guild.bans.fetch(user.id).catch(() => null)) return interaction.reply({ embeds: [ui.error(`${user} est déjà banni.`)], flags: 64 });
  if (!(await antiraid.trackModAction(interaction.member, 'antiban')))
    return interaction.reply({ embeds: [ui.error('Limite de bannissements atteinte : action bloquée par l’antiraid.')], flags: 64 });

  await interaction.deferReply();
  // On prévient la cible en MP avant de la bannir (après, on ne peut plus)
  await user.send({
    embeds: [new EmbedBuilder().setColor(ui.COLORS.ban)
      .setTitle(`${ui.E.ban} Tu as été banni de ${guild.name}`)
      .setDescription(`**Raison :** ${reason || 'Aucune'}${duration ? `\n**Durée :** ${formatDuration(duration)}` : ''}`)],
  }).catch(() => {});
  await guild.members.ban(user.id, { reason: `${interaction.user.tag} : ${reason || 'Aucune raison'}`, deleteMessageSeconds: deleteSeconds ?? 0 });

  const action = duration ? 'tempban' : 'ban';
  const id = addSanction(guild.id, user.id, { type: action, reason, modId: interaction.user.id, duration });
  if (duration) addTimer(guild.id, { type: 'unban', userId: user.id, at: Date.now() + duration });
  await modLog(guild, { action, target: user, moderator: interaction.user, reason, duration: duration ?? undefined, id });
  await interaction.editReply(await buildAnnounce(guild, { action, user, moderator: interaction.user, reason, duration: duration ?? undefined, id }));
}

module.exports = {
  category: 'Modération',
  doBan,
  data: new SlashCommandBuilder()
    .setName('ban')
    .setDescription('Bannit un membre (ou un utilisateur par ID) du serveur')
    .setDefaultMemberPermissions(PermissionFlagsBits.BanMembers)
    .addUserOption((o) => o.setName('membre').setDescription('Membre ou ID à bannir').setRequired(true))
    .addStringOption((o) => o.setName('raison').setDescription('Raison du ban').setMaxLength(400))
    .addStringOption((o) => o.setName('supprimer').setDescription('Supprimer ses messages récents').addChoices(
      { name: 'Ne rien supprimer', value: '0' }, { name: 'Dernière heure', value: '3600' },
      { name: '24 dernières heures', value: '86400' }, { name: '7 derniers jours', value: '604800' },
    )),
  async run(interaction) {
    await doBan(interaction, {
      user: interaction.options.getUser('membre', true),
      reason: interaction.options.getString('raison'),
      deleteSeconds: Number(interaction.options.getString('supprimer') ?? 0),
    });
  },
};
