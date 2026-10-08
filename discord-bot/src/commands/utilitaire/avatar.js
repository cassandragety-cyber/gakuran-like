const { SlashCommandBuilder, ActionRowBuilder, ButtonBuilder, ButtonStyle } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('avatar').setDescription('Photo de profil ou bannière d’un membre')
    .addUserOption((o) => o.setName('membre').setDescription('Membre'))
    .addStringOption((o) => o.setName('type').setDescription('Quoi afficher').addChoices({ name: 'Avatar', value: 'avatar' }, { name: 'Avatar du serveur', value: 'server' }, { name: 'Bannière', value: 'banner' })),
  async run(interaction) {
    const user = await (interaction.options.getUser('membre') ?? interaction.user).fetch();
    const type = interaction.options.getString('type') ?? 'avatar';
    let url;
    if (type === 'banner') url = user.bannerURL({ size: 4096 });
    else if (type === 'server') url = (await interaction.guild.members.fetch(user.id).catch(() => null))?.avatarURL({ size: 4096 });
    else url = user.displayAvatarURL({ size: 4096 });
    if (!url) return interaction.reply({ embeds: [ui.error(type === 'banner' ? 'Ce membre n’a pas de bannière.' : 'Pas d’avatar de serveur.')], flags: 64 });
    await interaction.reply({
      embeds: [ui.embed(interaction.guild).setTitle(`${type === 'banner' ? 'Bannière' : 'Avatar'} de ${user.username}`).setImage(url)],
      components: [new ActionRowBuilder().addComponents(new ButtonBuilder().setLabel('Ouvrir').setStyle(ButtonStyle.Link).setURL(url))],
    });
  },
};
