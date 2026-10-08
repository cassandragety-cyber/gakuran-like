const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('suggestion')
    .setDescription('Suggestions')
    .addSubcommand((s) => s.setName('envoyer').setDescription('Poste une suggestion').addStringOption((o) => o.setName('texte').setDescription('Ta suggestion').setRequired(true).setMaxLength(1500)))
    .addSubcommand((s) => s.setName('salon').setDescription('Définit le salon des suggestions (admin)').addChannelOption((o) => o.setName('salon').setDescription('Salon').setRequired(true).addChannelTypes(ChannelType.GuildText))),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    if (interaction.options.getSubcommand() === 'salon') {
      if (!interaction.member.permissions.has(PermissionFlagsBits.ManageGuild)) return interaction.reply({ embeds: [ui.error('Permission « Gérer le serveur » requise.')], flags: 64 });
      g.suggestions.channel = interaction.options.getChannel('salon', true).id;
      db.save();
      return interaction.reply({ embeds: [ui.success(`Salon des suggestions : <#${g.suggestions.channel}>`)] });
    }
    const ch = interaction.guild.channels.cache.get(g.suggestions.channel);
    if (!ch) return interaction.reply({ embeds: [ui.error('Aucun salon de suggestions configuré (`/suggestion salon`).')], flags: 64 });
    const msg = await ch.send({ embeds: [ui.embed(interaction.guild).setAuthor({ name: `Suggestion de ${interaction.user.username}`, iconURL: interaction.user.displayAvatarURL() }).setDescription(interaction.options.getString('texte', true)).setTimestamp()] });
    await msg.react('✅');
    await msg.react('❌');
    await msg.startThread({ name: `Discussion — ${interaction.user.username}` }).catch(() => {});
    await interaction.reply({ embeds: [ui.success(`Suggestion envoyée dans ${ch} !`)], flags: 64 });
  },
};
