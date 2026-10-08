const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('ping').setDescription('Latence du bot'),
  async run(interaction, client) {
    const start = Date.now();
    await interaction.deferReply();
    const api = Date.now() - start;
    const up = Math.floor(client.uptime / 1000);
    await interaction.editReply({ embeds: [ui.embed(interaction.guild).setTitle('🏓 Pong !').setDescription(
      `**WebSocket :** ${client.ws.ping} ms\n**Réponse :** ${api} ms\n**En ligne depuis :** <t:${Math.floor(Date.now() / 1000) - up}:R>\n**Mémoire :** ${(process.memoryUsage().rss / 1e6).toFixed(0)} Mo`)] });
  },
};
