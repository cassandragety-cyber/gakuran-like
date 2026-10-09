const { SlashCommandBuilder, PermissionFlagsBits, ModalBuilder, TextInputBuilder, TextInputStyle, ActionRowBuilder, EmbedBuilder, ChannelType } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('embed')
    .setDescription('Crée un embed personnalisé via un formulaire')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageMessages)
    .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement)),
  async run(interaction) {
    const ch = interaction.options.getChannel('salon') ?? interaction.channel;
    const field = (id, label, style, required = false, max = 4000) => new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(style).setRequired(required).setMaxLength(max));
    await interaction.showModal(new ModalBuilder().setCustomId(`embed:${ch.id}`).setTitle('Créer un embed').addComponents(
      field('title', 'Titre', TextInputStyle.Short, false, 256),
      field('description', 'Description', TextInputStyle.Paragraph, true),
      field('color', 'Couleur (hex, ex : #8b5cf6)', TextInputStyle.Short, false, 7),
      field('image', 'URL d’image (facultatif)', TextInputStyle.Short, false, 500),
      field('footer', 'Pied de page (facultatif)', TextInputStyle.Short, false, 200),
    ));
  },
  components: {
    async embed(interaction) {
      const ch = interaction.guild.channels.cache.get(interaction.customId.split(':')[1]);
      const v = (k) => interaction.fields.getTextInputValue(k)?.trim();
      const e = new EmbedBuilder().setDescription(v('description')).setColor(parseInt((v('color') || '').replace('#', ''), 16) || ui.colorFor(interaction.guild));
      if (v('title')) e.setTitle(v('title'));
      if (/^https?:\/\//.test(v('image'))) e.setImage(v('image'));
      if (v('footer')) e.setFooter({ text: v('footer') });
      await ch.send({ embeds: [e] });
      await interaction.reply({ embeds: [ui.success(`Embed envoyé dans ${ch}.`)], flags: 64 });
    },
  },
};
