const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('say')
    .setDescription('Fait parler le bot')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageMessages)
    .addStringOption((o) => o.setName('message').setDescription('Message').setRequired(true).setMaxLength(2000))
    .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement)),
  async run(interaction) {
    const ch = interaction.options.getChannel('salon') ?? interaction.channel;
    // Pas de @everyone ni de rôles mentionnés via le bot
    await ch.send({ content: interaction.options.getString('message', true).replace(/\\n/g, '\n'), allowedMentions: { parse: ['users'] } });
    await interaction.reply({ embeds: [ui.success('Message envoyé.')], flags: 64 });
  },
};
