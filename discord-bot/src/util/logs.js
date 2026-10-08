// Envoi dans les salons de logs configurés via /logs.
const { EmbedBuilder } = require('discord.js');
const db = require('../db');
const { COLORS, E, truncate } = require('./ui');
const { formatDuration } = require('./time');

async function sendLog(guild, type, payload) {
  const id = db.guild(guild.id).logs[type];
  if (!id) return;
  const channel = guild.channels.cache.get(id);
  if (!channel?.isTextBased()) return;
  const body = payload instanceof EmbedBuilder ? { embeds: [payload] } : payload;
  await channel.send({ ...body, allowedMentions: { parse: [] } }).catch(() => {});
}

const ACTIONS = {
  ban: ['Bannissement', COLORS.ban, E.ban],
  tempban: ['Bannissement temporaire', COLORS.ban, E.ban],
  unban: ['Débannissement', COLORS.unban, E.unlock],
  kick: ['Expulsion', COLORS.kick, E.kick],
  mute: ['Mute', COLORS.mute, E.mute],
  unmute: ['Unmute', COLORS.unban, E.unmute],
  cmute: ['Mute salon', COLORS.mute, E.mute],
  warn: ['Avertissement', COLORS.warnAction, E.warn],
  derank: ['Derank', COLORS.kick, '📉'],
  clear: ['Suppression de messages', COLORS.warn, '🧹'],
  lock: ['Verrouillage', COLORS.warn, E.lock],
  unlock: ['Déverrouillage', COLORS.success, E.unlock],
  hide: ['Salon caché', COLORS.warn, '🙈'],
  unhide: ['Salon affiché', COLORS.success, '👁️'],
  role: ['Modification de rôles', COLORS.warn, '🎭'],
  nick: ['Pseudo modifié', COLORS.warn, '✏️'],
};

async function modLog(guild, { action, target, moderator, reason, duration, extra, id }) {
  const [title, color, emoji] = ACTIONS[action] ?? [action, COLORS.warn, E.info];
  const e = new EmbedBuilder()
    .setColor(color)
    .setAuthor({ name: `${emoji} ${title}`, iconURL: target?.displayAvatarURL?.() })
    .setTimestamp();
  const lines = [];
  if (target) lines.push(`**Cible :** ${target} \`${target.tag ?? target.user?.tag ?? ''}\` (\`${target.id}\`)`);
  if (moderator) lines.push(`**Modérateur :** ${moderator} (\`${moderator.id}\`)`);
  if (duration !== undefined) lines.push(`**Durée :** ${formatDuration(duration)}`);
  if (reason) lines.push(`**Raison :** ${truncate(reason, 900)}`);
  if (extra) lines.push(extra);
  e.setDescription(lines.join('\n'));
  if (id) e.setFooter({ text: `Sanction #${id}` });
  await sendLog(guild, 'mod', e);
}

module.exports = { sendLog, modLog };
