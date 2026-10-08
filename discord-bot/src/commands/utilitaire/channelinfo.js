const { SlashCommandBuilder, ChannelType } = require('discord.js');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('channelinfo').setDescription('Informations sur un salon')
    .addChannelOption((o) => o.setName('salon').setDescription('Salon')),
  async run(interaction) {
    const c = interaction.options.getChannel('salon') ?? interaction.channel;
    const e = ui.embed(interaction.guild).setTitle(`# ${c.name}`).addFields(
      { name: 'ID', value: `\`${c.id}\``, inline: true },
      { name: 'Type', value: ChannelType[c.type] ?? String(c.type), inline: true },
      { name: 'Créé', value: ts(c.createdAt, 'D'), inline: true },
      { name: 'Catégorie', value: c.parent?.name ?? 'aucune', inline: true },
    );
    if (c.topic) e.addFields({ name: 'Sujet', value: c.topic.slice(0, 1024) });
    if (c.rateLimitPerUser) e.addFields({ name: 'Mode lent', value: `${c.rateLimitPerUser}s`, inline: true });
    if (c.isVoiceBased?.()) e.addFields({ name: 'En vocal', value: String(c.members.size), inline: true });
    await interaction.reply({ embeds: [e] });
  },
};
