// Giveaways avec bouton de participation.
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, EmbedBuilder } = require('discord.js');
const db = require('../db');
const ui = require('../util/ui');
const { ts } = require('../util/time');

function giveawayEmbed(guild, gw) {
  const ended = gw.ended;
  return new EmbedBuilder()
    .setColor(ended ? 0x52525b : ui.colorFor(guild))
    .setTitle(`🎉 ${gw.prize}`)
    .setDescription([
      ended ? `**Terminé** ${ts(gw.end)}` : `Fin ${ts(gw.end)} (${ts(gw.end, 'f')})`,
      `**Gagnant(s) :** ${ended ? (gw.winners?.length ? gw.winners.map((w) => `<@${w}>`).join(', ') : 'personne') : gw.count}`,
      `**Organisé par :** <@${gw.host}>`,
      gw.requiredRole ? `**Rôle requis :** <@&${gw.requiredRole}>` : null,
      `**Participants :** ${gw.entries.length}`,
    ].filter(Boolean).join('\n'))
    .setTimestamp(gw.end);
}

function giveawayRow(gw) {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('giveaway:join').setLabel(`Participer (${gw.entries.length})`).setEmoji('🎉').setStyle(ButtonStyle.Primary).setDisabled(!!gw.ended),
  );
}

function draw(entries, n) {
  const pool = [...entries];
  const out = [];
  while (pool.length && out.length < n) out.push(pool.splice(Math.floor(Math.random() * pool.length), 1)[0]);
  return out;
}

async function end(client, guildId, messageId, reroll = false) {
  const g = db.guild(guildId);
  const gw = g.giveaways[messageId];
  if (!gw) return null;
  const guild = client.guilds.cache.get(guildId);
  const channel = guild?.channels.cache.get(gw.channelId);
  gw.ended = true;
  gw.winners = draw(gw.entries, gw.count);
  db.save();
  const msg = await channel?.messages.fetch(messageId).catch(() => null);
  await msg?.edit({ embeds: [giveawayEmbed(guild, gw)], components: [giveawayRow(gw)] }).catch(() => {});
  await channel?.send({
    content: gw.winners.length ? `🎉 ${reroll ? 'Nouveau tirage ! ' : ''}Félicitations ${gw.winners.map((w) => `<@${w}>`).join(', ')}, vous gagnez **${gw.prize}** !` : `😢 Personne n’a participé au giveaway **${gw.prize}**.`,
    allowedMentions: { users: gw.winners },
    reply: msg ? { messageReference: messageId, failIfNotExists: false } : undefined,
  }).catch(() => {});
  return gw;
}

async function tick(client) {
  const now = Date.now();
  for (const [guildId, g] of db.allGuilds()) {
    for (const [id, gw] of Object.entries(g.giveaways ?? {})) {
      if (!gw.ended && gw.end <= now) await end(client, guildId, id);
      // On garde les giveaways terminés 7 jours pour pouvoir relancer un tirage
      if (gw.ended && now - gw.end > 7 * 864e5) delete g.giveaways[id];
    }
  }
}

module.exports = {
  giveawayEmbed,
  giveawayRow,
  end,
  tick,
  components: {
    async giveaway(interaction) {
      const gw = db.guild(interaction.guild.id).giveaways[interaction.message.id];
      if (!gw || gw.ended) return interaction.reply({ embeds: [ui.error('Ce giveaway est terminé.')], flags: 64 });
      if (gw.requiredRole && !interaction.member.roles.cache.has(gw.requiredRole))
        return interaction.reply({ embeds: [ui.error(`Il faut le rôle <@&${gw.requiredRole}> pour participer.`)], flags: 64 });
      const i = gw.entries.indexOf(interaction.user.id);
      if (i === -1) gw.entries.push(interaction.user.id);
      else gw.entries.splice(i, 1);
      db.save();
      await interaction.update({ embeds: [giveawayEmbed(interaction.guild, gw)], components: [giveawayRow(gw)] });
      await interaction.followUp({ embeds: [ui.info(i === -1 ? '🎉 Participation enregistrée, bonne chance !' : 'Tu ne participes plus.', interaction.guild)], flags: 64 });
    },
  },
};
