const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Sécurité',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('whitelist')
    .setDescription('Membres et rôles ignorés par l’antiraid (sauf modules en « max »)')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute à la whitelist')
      .addUserOption((o) => o.setName('membre').setDescription('Membre'))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle')))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire de la whitelist')
      .addUserOption((o) => o.setName('membre').setDescription('Membre'))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle')))
    .addSubcommand((s) => s.setName('liste').setDescription('Affiche la whitelist')),
  async run(interaction) {
    const wl = db.guild(interaction.guild.id).security.whitelist;
    const sub = interaction.options.getSubcommand();
    if (sub === 'liste') {
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('🤍 Whitelist')
        .addFields(
          { name: `Membres (${wl.users.length})`, value: wl.users.map((id) => `<@${id}>`).join('\n').slice(0, 1024) || 'Aucun' },
          { name: `Rôles (${wl.roles.length})`, value: wl.roles.map((id) => `<@&${id}>`).join('\n').slice(0, 1024) || 'Aucun' },
        )] });
    }
    const user = interaction.options.getUser('membre');
    const role = interaction.options.getRole('role');
    if (!user && !role) return interaction.reply({ embeds: [ui.error('Précise un membre et/ou un rôle.')], flags: 64 });
    const add = sub === 'ajouter';
    const edit = (list, id) => {
      const i = list.indexOf(id);
      if (add && i === -1) list.push(id);
      if (!add && i !== -1) list.splice(i, 1);
    };
    if (user) edit(wl.users, user.id);
    if (role) edit(wl.roles, role.id);
    db.save();
    await interaction.reply({ embeds: [ui.success(`${[user, role].filter(Boolean).join(' et ')} ${add ? 'ajouté(s) à' : 'retiré(s) de'} la whitelist.`)] });
  },
};
