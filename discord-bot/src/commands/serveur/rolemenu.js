const { SlashCommandBuilder, PermissionFlagsBits, ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { roleError } = require('../moderation/role');

const builder = new SlashCommandBuilder()
  .setName('rolemenu')
  .setDescription('Crée un menu de rôles (boutons ou menu déroulant)')
  .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles)
  .addStringOption((o) => o.setName('titre').setDescription('Titre').setRequired(true).setMaxLength(200))
  .addRoleOption((o) => o.setName('role1').setDescription('Rôle 1').setRequired(true));
for (let i = 2; i <= 10; i++) builder.addRoleOption((o) => o.setName(`role${i}`).setDescription(`Rôle ${i}`));
builder
  .addStringOption((o) => o.setName('description').setDescription('Texte du menu').setMaxLength(1500))
  .addStringOption((o) => o.setName('style').setDescription('Boutons ou menu déroulant').addChoices({ name: 'Boutons', value: 'buttons' }, { name: 'Menu déroulant', value: 'select' }));

module.exports = {
  category: 'Serveur',
  data: builder,
  async run(interaction) {
    const roles = [];
    for (let i = 1; i <= 10; i++) {
      const r = interaction.options.getRole(`role${i}`);
      if (!r || roles.some((x) => x.id === r.id)) continue;
      const err = roleError(interaction, r);
      if (err) return interaction.reply({ embeds: [ui.error(`${r} : ${err}`)], flags: 64 });
      roles.push(r);
    }
    const style = interaction.options.getString('style') ?? 'buttons';
    const embed = ui.embed(interaction.guild).setTitle(interaction.options.getString('titre', true))
      .setDescription(`${interaction.options.getString('description') ?? 'Clique pour obtenir ou retirer un rôle.'}\n\n${roles.map((r) => `${ui.E.dot} ${r}`).join('\n')}`);
    let components;
    if (style === 'select') {
      components = [new ActionRowBuilder().addComponents(new StringSelectMenuBuilder().setCustomId('rolemenu:select').setPlaceholder('Choisis tes rôles…')
        .setMinValues(0).setMaxValues(roles.length).addOptions(roles.map((r) => ({ label: r.name, value: r.id }))))];
    } else {
      components = [];
      for (let i = 0; i < roles.length; i += 5) {
        components.push(new ActionRowBuilder().addComponents(roles.slice(i, i + 5).map((r) => new ButtonBuilder().setCustomId(`rolemenu:${r.id}`).setLabel(r.name.slice(0, 80)).setStyle(ButtonStyle.Secondary))));
      }
    }
    await interaction.channel.send({ embeds: [embed], components });
    await interaction.reply({ embeds: [ui.success('Menu de rôles créé.')], flags: 64 });
  },
};
