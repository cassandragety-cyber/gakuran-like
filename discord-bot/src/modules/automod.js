// Filtres sur les messages : mots interdits, @everyone, liens, spam.
const { EmbedBuilder } = require('discord.js');
const db = require('../db');
const { bypass, exceeded, punish } = require('./antiraid');
const { sendLog } = require('../util/logs');
const { COLORS } = require('../util/ui');

const INVITE_RE = /(discord\.(gg|io|me|li)|discord(app)?\.com\/invite|dsc\.gg)\/[\w-]+/i;
const URL_RE = /(https?:\/\/|www\.)\S+|\b[\w-]+\.(com|net|org|fr|gg|io|xyz|ru|be|ly|me|tk|co|app|dev|link|site|shop)\b(\/\S*)?/i;

const normalize = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/[0@]/g, 'o').replace(/[1!|]/g, 'i').replace(/3/g, 'e').replace(/4/g, 'a').replace(/[5$]/g, 's');

async function notice(message, text) {
  const m = await message.channel.send({ content: `${message.author}`, embeds: [new EmbedBuilder().setColor(COLORS.warn).setDescription(text)] }).catch(() => null);
  if (m) setTimeout(() => m.delete().catch(() => {}), 6000);
}

function moduleOn(guild, module) {
  return db.guild(guild.id).security.modules[module] !== 'off';
}

async function onMessage(message, edited = false) {
  if (!message.guild || message.author.bot || !message.member) return;
  const { guild, member } = message;
  const sec = db.guild(guild.id).security;
  const content = message.content || '';

  // Mots interdits
  if (sec.badwords.enabled && sec.badwords.words.length && !bypass(guild, member.id, 'antispam')) {
    const text = ` ${normalize(content).replace(/[^a-z0-9]+/g, ' ')} `;
    const hit = sec.badwords.words.find((w) => text.includes(` ${normalize(w)} `));
    if (hit) {
      await message.delete().catch(() => {});
      await notice(message, '🤬 Ce mot est interdit sur ce serveur.');
      return sendLog(guild, 'message', new EmbedBuilder().setColor(COLORS.warn).setDescription(`🤬 Mot interdit (\`${hit}\`) de ${message.author} dans ${message.channel} supprimé.`));
    }
  }

  // @everyone / @here
  if (message.mentions.everyone && moduleOn(guild, 'antieveryone') && !bypass(guild, member.id, 'antieveryone')) {
    await message.delete().catch(() => {});
    if (exceeded(guild, member.id, 'antieveryone')) await punish(guild, member.id, 'antieveryone', `a mentionné @everyone/@here dans ${message.channel}`);
    return;
  }

  // Liens
  if (moduleOn(guild, 'antilink') && !sec.ignored.antilink.includes(message.channelId) && !sec.ignored.antilink.includes(message.channel.parentId) && !bypass(guild, member.id, 'antilink')) {
    const all = sec.antilinkMode === 'all';
    const allowed = sec.antilinkAllow ?? [];
    let bad = INVITE_RE.test(content);
    if (!bad && all) {
      const urls = content.match(new RegExp(URL_RE.source, 'gi')) ?? [];
      bad = urls.some((u) => !allowed.some((d) => u.toLowerCase().includes(d)));
    }
    if (bad) {
      await message.delete().catch(() => {});
      await notice(message, `🔗 Les ${all ? 'liens' : 'invitations Discord'} sont interdits ici.`);
      return sendLog(guild, 'raid', new EmbedBuilder().setColor(COLORS.warn).setDescription(`🔗 Lien supprimé de ${message.author} dans ${message.channel} :\n\`\`\`${content.slice(0, 500)}\`\`\``));
    }
  }

  // Spam (trop de messages d'affilée) et mentions de masse
  if (!edited && moduleOn(guild, 'antispam') && !sec.ignored.antispam.includes(message.channelId) && !bypass(guild, member.id, 'antispam')) {
    const massMention = message.mentions.users.size >= 5;
    if (exceeded(guild, member.id, 'antispam') || massMention) {
      if (member.moderatable) await member.timeout(10 * 60e3, '[Antispam]').catch(() => {});
      const recent = (await message.channel.messages.fetch({ limit: 30 }).catch(() => null))?.filter((m) => m.author.id === member.id && Date.now() - m.createdTimestamp < 30e3);
      if (recent?.size) await message.channel.bulkDelete(recent, true).catch(() => {});
      await notice(message, `🔇 ${massMention ? 'Mentions de masse' : 'Spam'} détecté : tu es muet pendant 10 minutes.`);
      await sendLog(guild, 'raid', new EmbedBuilder().setColor(COLORS.warn).setDescription(`🔇 ${message.author} muet 10 min pour ${massMention ? 'mentions de masse' : 'spam'} dans ${message.channel}.`));
    }
  }
}

module.exports = {
  setup(client) {
    client.on('messageCreate', (m) => onMessage(m).catch((e) => console.error('[automod]', e)));
    // Un message modifié pour y glisser un lien est aussi vérifié
    client.on('messageUpdate', (oldM, newM) => {
      if (newM.partial || oldM.content === newM.content) return;
      onMessage(newM, true).catch(() => {});
    });
  },
};
