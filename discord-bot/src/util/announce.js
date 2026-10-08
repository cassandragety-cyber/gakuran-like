// Message stylé envoyé dans le salon lors d'une sanction : embed + GIF qui pop.
const { AttachmentBuilder, EmbedBuilder } = require('discord.js');
const { findGif } = require('./gifs');
const { renderActionGif } = require('./gifcard');
const { COLORS, E, truncate } = require('./ui');
const { formatDuration } = require('./time');

const TITLES = {
  ban: [`${E.ban} Bannissement`, COLORS.ban, 'a été **banni** du serveur'],
  tempban: [`${E.ban} Bannissement temporaire`, COLORS.ban, 'a été **banni temporairement**'],
  kick: [`${E.kick} Expulsion`, COLORS.kick, 'a été **expulsé** du serveur'],
  mute: [`${E.mute} Mute`, COLORS.mute, 'a été **réduit au silence**'],
  warn: [`${E.warn} Avertissement`, COLORS.warnAction, 'a reçu un **avertissement**'],
  unban: [`${E.unlock} Débannissement`, COLORS.unban, 'a été **débanni**'],
};

/**
 * @param {import('discord.js').Guild} guild
 * @param {{ action: string, user: import('discord.js').User, moderator: import('discord.js').User, reason?: string, duration?: number|null, id?: number, extra?: string }} o
 * @returns {Promise<{ embeds: EmbedBuilder[], files: AttachmentBuilder[] }>}
 */
async function buildAnnounce(guild, o) {
  const [title, color, verb] = TITLES[o.action] ?? TITLES.warn;
  const e = new EmbedBuilder()
    .setColor(color)
    .setAuthor({ name: title, iconURL: o.user.displayAvatarURL() })
    .setDescription([
      `**${o.user}** ${verb}.`,
      '',
      `> ${E.arrow} **Modérateur :** ${o.moderator}`,
      o.duration !== undefined ? `> ${E.arrow} **Durée :** ${formatDuration(o.duration)}` : null,
      `> ${E.arrow} **Raison :** ${truncate(o.reason || 'Aucune raison fournie', 500)}`,
      o.extra ? `> ${E.arrow} ${o.extra}` : null,
    ].filter((l) => l !== null).join('\n'))
    .setThumbnail(o.user.displayAvatarURL({ size: 256 }))
    .setTimestamp();
  if (o.id) e.setFooter({ text: `Sanction #${o.id} • ${o.user.id}` });

  const files = [];
  const url = await findGif(guild.id, o.action).catch(() => null);
  if (url) e.setImage(url);
  else if (require('../db').guild(guild.id).style.gifs !== false) {
    // Pas de GIF externe : carte animée générée avec l'avatar de la cible
    try {
      const gifAction = o.action === 'tempban' ? 'ban' : o.action;
      const buf = await renderActionGif(gifAction, {
        avatarURL: o.user.displayAvatarURL({ extension: 'png', size: 256 }),
        username: o.user.username,
        moderator: o.moderator.username,
        reason: o.reason,
        duration: o.duration ? formatDuration(o.duration) : undefined,
      });
      files.push(new AttachmentBuilder(buf, { name: `${gifAction}.gif` }));
      e.setImage(`attachment://${gifAction}.gif`);
    } catch (err) {
      console.warn('[announce] carte animée :', err.message);
    }
  }
  return { embeds: [e], files };
}

module.exports = { buildAnnounce };
