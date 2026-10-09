// Style commun des embeds : couleurs, emojis, raccourcis.
const { EmbedBuilder } = require('discord.js');
const config = require('../config');
const db = require('../db');

const E = {
  ok: '✅', no: '❌', warn: '⚠️', info: 'ℹ️', load: '⏳', lock: '🔒', unlock: '🔓',
  ban: '🔨', kick: '👢', mute: '🔇', unmute: '🔊', shield: '🛡️', crown: '👑', star: '✨',
  music: '🎵', note: '📝', ticket: '🎫', gift: '🎉', dot: '•', arrow: '➜',
};

const COLORS = {
  success: 0x22c55e, error: 0xef4444, warn: 0xf59e0b,
  ban: 0xdc2626, kick: 0xf97316, mute: 0x6366f1, warnAction: 0xeab308, unban: 0x10b981,
};

function colorFor(guild) {
  return (guild && db.guild(guild.id).color) || config.color;
}

function embed(guild) {
  return new EmbedBuilder().setColor(colorFor(guild));
}

function success(text, guild) {
  return new EmbedBuilder().setColor(COLORS.success).setDescription(`${E.ok} ${text}`);
}
function error(text) {
  return new EmbedBuilder().setColor(COLORS.error).setDescription(`${E.no} ${text}`);
}
function info(text, guild) {
  return embed(guild).setDescription(text);
}

function footer(e, client) {
  return e.setFooter({ text: config.botName, iconURL: client?.user?.displayAvatarURL() }).setTimestamp();
}

// Barre de progression façon lecteur : ▬▬▬🔘▬▬▬▬
function progressBar(current, total, size = 16) {
  if (!total) return '🔴 EN DIRECT';
  const pos = Math.min(size - 1, Math.floor((current / total) * size));
  return '▬'.repeat(pos) + '🔘' + '▬'.repeat(size - pos - 1);
}

function truncate(str, n) {
  str = String(str ?? '');
  return str.length > n ? `${str.slice(0, n - 1)}…` : str;
}

module.exports = { E, COLORS, colorFor, embed, success, error, info, footer, progressBar, truncate };
