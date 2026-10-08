const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { checkHierarchy, isDangerousRole, isTrusted } = require('../../util/perms');
const { modLog } = require('../../util/logs');
const { addTimer, removeTimer } = require('../../util/sanctions');
const { parseDuration, formatDuration, ts } = require('../../util/time');
const db = require('../../db');

// Contrôles communs : le rôle doit être sous le modérateur et sous le bot
function roleError(interaction, role) {
  const me = interaction.guild.members.me;
  if (role.managed || role.id === interaction.guild.id) return 'Ce rôle ne peut pas être attribué manuellement.';
  if (role.position >= me.roles.highest.position) return 'Ce rôle est au-dessus du mien.';
  if (interaction.user.id !== interaction.guild.ownerId && role.position >= interaction.member.roles.highest.position) return 'Ce rôle est au-dessus (ou égal) de ton rôle le plus haut.';
  if (isDangerousRole(role) && !isTrusted(interaction.guild, interaction.user.id)) return 'Ce rôle a des permissions dangereuses : seul le propriétaire ou un owner du bot peut le donner.';
  return null;
}

module.exports = {
  category: 'Modération',
  roleError,
  data: new SlashCommandBuilder()
    .setName('role')
    .setDescription('Ajoute ou retire des rôles')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute un rôle à un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle').setRequired(true))
      .addStringOption((o) => o.setName('duree').setDescription('Rôle temporaire : ex 1h, 7j'))
      .addStringOption((o) => o.setName('raison').setDescription('Raison')))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire un rôle à un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle').setRequired(true))
      .addStringOption((o) => o.setName('raison').setDescription('Raison')))
    .addSubcommand((s) => s.setName('temporaires').setDescription('Liste des rôles temporaires actifs'))
    .addSubcommand((s) => s.setName('masse').setDescription('Ajoute/retire un rôle à tous les membres')
      .addStringOption((o) => o.setName('action').setDescription('Ajouter ou retirer').setRequired(true).addChoices({ name: 'Ajouter', value: 'add' }, { name: 'Retirer', value: 'remove' }))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle à donner/retirer').setRequired(true))
      .addRoleOption((o) => o.setName('requis').setDescription('Seulement les membres ayant ce rôle'))),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    const g = db.guild(interaction.guild.id);
    if (sub === 'temporaires') {
      const list = g.timers.filter((t) => t.type === 'unrole');
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('⏳ Rôles temporaires').setDescription(list.map((t) => `${ui.E.dot} <@${t.userId}> — <@&${t.roleId}> — fin ${ts(t.at)}`).join('\n').slice(0, 4000) || 'Aucun.')] });
    }
    const role = interaction.options.getRole('role', true);
    const rErr = roleError(interaction, role);
    if (rErr) return interaction.reply({ embeds: [ui.error(rErr)], flags: 64 });

    if (sub === 'masse') {
      const add = interaction.options.getString('action', true) === 'add';
      const required = interaction.options.getRole('requis');
      await interaction.deferReply();
      const members = await interaction.guild.members.fetch();
      const targets = members.filter((m) => !m.user.bot && (!required || m.roles.cache.has(required.id)) && m.roles.cache.has(role.id) !== add);
      await interaction.editReply({ embeds: [ui.info(`${ui.E.load} Traitement de **${targets.size}** membre(s)… (environ ${Math.ceil(targets.size / 2)}s)`, interaction.guild)] });
      let ok = 0;
      for (const m of targets.values()) {
        try { await (add ? m.roles.add(role, `masse par ${interaction.user.tag}`) : m.roles.remove(role, `masse par ${interaction.user.tag}`)); ok++; } catch {}
      }
      await modLog(interaction.guild, { action: 'role', moderator: interaction.user, extra: `${role} ${add ? 'ajouté à' : 'retiré de'} **${ok}** membre(s)` });
      return interaction.editReply({ embeds: [ui.success(`${role} ${add ? 'ajouté à' : 'retiré de'} **${ok}** membre(s).`)] });
    }

    const member = interaction.options.getMember('membre');
    if (!member) return interaction.reply({ embeds: [ui.error('Membre introuvable.')], flags: 64 });
    if (member.id !== interaction.user.id) {
      const err = checkHierarchy(interaction, member, 'modifier');
      if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    }
    const reason = `${interaction.user.tag} : ${interaction.options.getString('raison') || 'aucune raison'}`;
    if (sub === 'ajouter') {
      const raw = interaction.options.getString('duree');
      const duration = raw ? parseDuration(raw) : null;
      if (raw && !duration) return interaction.reply({ embeds: [ui.error('Durée invalide.')], flags: 64 });
      await member.roles.add(role, reason);
      if (duration) addTimer(interaction.guild.id, { type: 'unrole', userId: member.id, roleId: role.id, at: Date.now() + duration });
      await modLog(interaction.guild, { action: 'role', target: member.user, moderator: interaction.user, extra: `**+** ${role}${duration ? ` pendant ${formatDuration(duration)}` : ''}` });
      return interaction.reply({ embeds: [ui.success(`${role} ajouté à ${member}${duration ? ` pour **${formatDuration(duration)}**` : ''}.`)] });
    }
    await member.roles.remove(role, reason);
    removeTimer(interaction.guild.id, (t) => t.type === 'unrole' && t.userId === member.id && t.roleId === role.id);
    await modLog(interaction.guild, { action: 'role', target: member.user, moderator: interaction.user, extra: `**−** ${role}` });
    await interaction.reply({ embeds: [ui.success(`${role} retiré à ${member}.`)] });
  },
};
