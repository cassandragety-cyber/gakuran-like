const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { inviteStats } = require('../../modules/welcome');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('invites')
    .setDescription('Suivi des invitations')
    .addSubcommand((s) => s.setName('voir').setDescription('Invitations d’un membre').addUserOption((o) => o.setName('membre').setDescription('Membre')))
    .addSubcommand((s) => s.setName('classement').setDescription('Classement des invitations'))
    .addSubcommand((s) => s.setName('bonus').setDescription('Ajoute/retire des invitations bonus (admin)')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addIntegerOption((o) => o.setName('nombre').setDescription('Nombre (négatif pour retirer)').setRequired(true)))
    .addSubcommand((s) => s.setName('reset').setDescription('Remet à zéro (admin)').addUserOption((o) => o.setName('membre').setDescription('Membre (vide = tout le serveur)'))),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    const admin = interaction.member.permissions.has(PermissionFlagsBits.ManageGuild);
    if ((sub === 'bonus' || sub === 'reset') && !admin) return interaction.reply({ embeds: [ui.error('Permission « Gérer le serveur » requise.')], flags: 64 });
    if (sub === 'voir') {
      const user = interaction.options.getUser('membre') ?? interaction.user;
      const s = inviteStats(g, user.id);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setAuthor({ name: user.username, iconURL: user.displayAvatarURL() })
        .setDescription(`📨 **${s.total}** invitation(s)\n\n✅ ${s.regular} arrivées • ❌ ${s.left} parties • 💩 ${s.fake} fake • ✨ ${s.bonus} bonus${g.joinedBy[user.id] ? `\n\nInvité par <@${g.joinedBy[user.id]}>` : ''}`)] });
    }
    if (sub === 'classement') {
      const top = Object.keys(g.invites).map((id) => [id, inviteStats(g, id).total]).sort((a, b) => b[1] - a[1]).slice(0, 15);
      const medals = ['🥇', '🥈', '🥉'];
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('📨 Classement des invitations').setDescription(top.map(([id, n], i) => `${medals[i] ?? `\`${i + 1}.\``} <@${id}> — **${n}**`).join('\n') || 'Aucune donnée.')] });
    }
    if (sub === 'bonus') {
      const user = interaction.options.getUser('membre', true);
      (g.invites[user.id] ??= { regular: 0, left: 0, fake: 0, bonus: 0 }).bonus += interaction.options.getInteger('nombre', true);
      db.save();
      return interaction.reply({ embeds: [ui.success(`${user} a maintenant **${inviteStats(g, user.id).total}** invitation(s).`)] });
    }
    const user = interaction.options.getUser('membre');
    if (user) delete g.invites[user.id];
    else g.invites = {};
    db.save();
    await interaction.reply({ embeds: [ui.success(user ? `Invitations de ${user} remises à zéro.` : 'Toutes les invitations ont été remises à zéro.')] });
  },
};
