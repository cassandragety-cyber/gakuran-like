const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('wiki').setDescription('Recherche sur Wikipédia')
    .addStringOption((o) => o.setName('recherche').setDescription('Mot-clé').setRequired(true).setMaxLength(200)),
  async run(interaction) {
    await interaction.deferReply();
    const q = interaction.options.getString('recherche', true);
    const headers = { 'User-Agent': 'DiscordBot (wiki command)' };
    const search = await fetch(`https://fr.wikipedia.org/w/api.php?action=opensearch&limit=5&namespace=0&format=json&search=${encodeURIComponent(q)}`, { headers }).then((r) => r.json()).catch(() => null);
    const title = search?.[1]?.[0];
    if (!title) return interaction.editReply({ embeds: [ui.error('Aucun article trouvé.')] });
    const page = await fetch(`https://fr.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`, { headers }).then((r) => r.json()).catch(() => null);
    const e = ui.embed(interaction.guild).setTitle(page?.title ?? title).setURL(page?.content_urls?.desktop?.page ?? search[3][0])
      .setDescription(ui.truncate(page?.extract ?? 'Pas de résumé.', 1500))
      .setFooter({ text: 'Wikipédia' });
    if (page?.thumbnail?.source) e.setThumbnail(page.thumbnail.source);
    if (search[1].length > 1) e.addFields({ name: 'Voir aussi', value: search[1].slice(1).map((t, i) => `[${t}](${search[3][i + 1]})`).join(' • ').slice(0, 1024) });
    await interaction.editReply({ embeds: [e] });
  },
};
