const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('lockname')
    .setDescription('Verrouille le pseudo d’un membre (il est remis automatiquement)')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageNicknames)
    .addSubcommand((s) => s.setName('set').setDescription('Verrouille le pseudo')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addStringOption((o) => o.setName('pseudo').setDescription('Pseudo imposé').setRequired(true).setMaxLength(32)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Déverrouille le pseudo')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('liste').setDescription('Membres dont le pseudo est verrouillé')),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'liste') {
      const lines = Object.entries(g.locknames).map(([id, n]) => `${ui.E.lock} <@${id}> → **${n}**`);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('Pseudos verrouillés').setDescription(lines.join('\n').slice(0, 4000) || 'Aucun.')] });
    }
    const member = interaction.options.getMember('membre');
    if (!member) return interaction.reply({ embeds: [ui.error('Membre introuvable.')], flags: 64 });
    if (sub === 'retirer') {
      delete g.locknames[member.id];
      db.save();
      return interaction.reply({ embeds: [ui.success(`Pseudo de ${member} déverrouillé.`)] });
    }
    const err = checkHierarchy(interaction, member, 'renommer');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    const nick = interaction.options.getString('pseudo', true);
    g.locknames[member.id] = nick;
    db.save();
    await member.setNickname(nick, `lockname par ${interaction.user.tag}`).catch(() => {});
    await interaction.reply({ embeds: [ui.success(`${ui.E.lock} Pseudo de ${member} verrouillé sur **${nick}**.`)] });
  },
};
