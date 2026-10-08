const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { modLog } = require('../../util/logs');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('nick')
    .setDescription('Gère le pseudo d’un membre')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageNicknames)
    .addSubcommand((s) => s.setName('set').setDescription('Définit le pseudo d’un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addStringOption((o) => o.setName('pseudo').setDescription('Nouveau pseudo').setRequired(true).setMaxLength(32)))
    .addSubcommand((s) => s.setName('reset').setDescription('Réinitialise le pseudo d’un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    if (!member) return interaction.reply({ embeds: [ui.error('Membre introuvable.')], flags: 64 });
    const err = member.id === interaction.user.id ? null : checkHierarchy(interaction, member, 'renommer');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    const nick = interaction.options.getSubcommand() === 'set' ? interaction.options.getString('pseudo', true) : null;
    await member.setNickname(nick, `par ${interaction.user.tag}`);
    await modLog(interaction.guild, { action: 'nick', target: member.user, moderator: interaction.user, extra: `**Nouveau pseudo :** ${nick ?? '*(réinitialisé)*'}` });
    await interaction.reply({ embeds: [ui.success(nick ? `${member} s’appelle maintenant **${nick}**.` : `Pseudo de ${member} réinitialisé.`)] });
  },
};
