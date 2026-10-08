// Pagination par boutons ◀ ▶ pour les longues listes.
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, ComponentType, MessageFlags } = require('discord.js');

/**
 * @param interaction interaction déjà « deferred » ou non
 * @param {(page:number, pages:number) => import('discord.js').EmbedBuilder} build
 */
async function paginate(interaction, pages, build, { ephemeral = false } = {}) {
  let page = 0;
  const row = () => new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('pg_prev').setEmoji('◀️').setStyle(ButtonStyle.Secondary).setDisabled(page === 0),
    new ButtonBuilder().setCustomId('pg_info').setLabel(`${page + 1}/${pages}`).setStyle(ButtonStyle.Secondary).setDisabled(true),
    new ButtonBuilder().setCustomId('pg_next').setEmoji('▶️').setStyle(ButtonStyle.Secondary).setDisabled(page >= pages - 1),
  );
  const payload = () => ({ embeds: [build(page, pages)], components: pages > 1 ? [row()] : [] });
  const send = interaction.deferred || interaction.replied ? interaction.editReply.bind(interaction) : (p) => interaction.reply({ ...p, flags: ephemeral ? MessageFlags.Ephemeral : undefined });
  const msg = await send(payload());
  if (pages <= 1) return;
  const message = msg?.createMessageComponentCollector ? msg : await interaction.fetchReply();
  const collector = message.createMessageComponentCollector({ componentType: ComponentType.Button, time: 5 * 60e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== interaction.user.id) return i.reply({ content: 'Ce menu ne t’appartient pas.', flags: MessageFlags.Ephemeral });
    page += i.customId === 'pg_next' ? 1 : -1;
    await i.update(payload());
  });
  collector.on('end', () => interaction.editReply({ components: [] }).catch(() => {}));
}

const chunk = (arr, n) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

module.exports = { paginate, chunk };
