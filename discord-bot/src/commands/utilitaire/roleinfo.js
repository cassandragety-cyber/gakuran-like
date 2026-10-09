const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');
const { isDangerousRole } = require('../../util/perms');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('roleinfo').setDescription('Informations et membres d’un rôle')
    .addRoleOption((o) => o.setName('role').setDescription('Rôle').setRequired(true)),
  async run(interaction) {
    await interaction.guild.members.fetch().catch(() => {});
    const r = interaction.options.getRole('role', true);
    const members = r.members.map((m) => `${m}`);
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setColor(r.color || ui.colorFor(interaction.guild)).setTitle(`🎭 ${r.name}`)
      .addFields(
        { name: 'ID', value: `\`${r.id}\``, inline: true },
        { name: 'Couleur', value: r.hexColor, inline: true },
        { name: 'Position', value: String(r.position), inline: true },
        { name: 'Créé', value: ts(r.createdAt, 'D'), inline: true },
        { name: 'Affiché à part', value: r.hoist ? 'oui' : 'non', inline: true },
        { name: 'Dangereux', value: isDangerousRole(r) ? '⚠️ oui' : 'non', inline: true },
        { name: 'Permissions', value: r.permissions.toArray().join(', ').slice(0, 1024) || 'aucune' },
        { name: `Membres (${members.length})`, value: members.join(' ').slice(0, 1024) || 'aucun' },
      )] });
  },
};
