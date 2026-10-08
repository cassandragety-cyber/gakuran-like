// Bienvenue / départ, rôles automatiques et suivi des invitations.
const { AttachmentBuilder, EmbedBuilder } = require('discord.js');
const db = require('../db');
const { colorFor } = require('../util/ui');
const { welcomeCard } = require('../util/cards');

const inviteCache = new Map(); // guildId → Map(code → uses)

async function cacheInvites(guild) {
  const invites = await guild.invites.fetch().catch(() => null);
  if (invites) inviteCache.set(guild.id, new Map(invites.map((i) => [i.code, { uses: i.uses, inviter: i.inviterId }])));
}

function inviteStats(g, userId) {
  const s = g.invites[userId] ?? { regular: 0, left: 0, fake: 0, bonus: 0 };
  return { ...s, total: s.regular - s.left - s.fake + s.bonus };
}

// Trouve l'invitation utilisée en comparant les compteurs avant/après l'arrivée
async function findInviter(member) {
  const before = inviteCache.get(member.guild.id) ?? new Map();
  const now = await member.guild.invites.fetch().catch(() => null);
  if (!now) return { type: 'unknown' };
  inviteCache.set(member.guild.id, new Map(now.map((i) => [i.code, { uses: i.uses, inviter: i.inviterId }])));
  const used = now.find((i) => (before.get(i.code)?.uses ?? 0) < i.uses);
  if (used) return { type: 'invite', inviterId: used.inviterId, code: used.code };
  if (member.guild.vanityURLCode) return { type: 'vanity' };
  return { type: 'unknown' };
}

function format(text, vars) {
  return text.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));
}

const VARS_HELP = '`{user}` mention • `{username}` nom • `{server}` serveur • `{count}` nombre de membres • `{inviter}` qui a invité • `{invites}` ses invitations';

async function onJoin(member) {
  const { guild } = member;
  const g = db.guild(guild.id);
  // Invitations
  const inv = await findInviter(member);
  let inviterText = inv.type === 'vanity' ? 'l’URL personnalisée' : 'une invitation inconnue';
  let invitesCount = 0;
  if (inv.type === 'invite' && inv.inviterId) {
    const s = (g.invites[inv.inviterId] ??= { regular: 0, left: 0, fake: 0, bonus: 0 });
    // Compte de moins de 7 jours = invitation « fake »
    if (Date.now() - member.user.createdTimestamp < 7 * 864e5) s.fake++;
    else s.regular++;
    g.joinedBy[member.id] = inv.inviterId;
    inviterText = `<@${inv.inviterId}>`;
    invitesCount = inviteStats(g, inv.inviterId).total;
    db.save();
  }
  if (member.user.bot) return;

  // Rôles automatiques
  for (const id of g.welcome.autoroles) await member.roles.add(id, 'Rôle automatique').catch(() => {});

  const vars = { user: `${member}`, username: member.user.username, server: guild.name, count: guild.memberCount, inviter: inviterText, invites: invitesCount };
  const ch = g.welcome.channel && guild.channels.cache.get(g.welcome.channel);
  if (ch) {
    const text = format(g.welcome.message || 'Bienvenue {user} sur **{server}** ! Invité par {inviter} ({invites} invitations).', vars);
    const embed = new EmbedBuilder().setColor(colorFor(guild)).setDescription(text).setTimestamp();
    const files = [];
    if (g.welcome.card) {
      const buf = await welcomeCard({ avatarURL: member.user.displayAvatarURL({ extension: 'png', size: 256 }), username: member.user.username, guildName: guild.name, memberCount: guild.memberCount, color: colorFor(guild) }).catch(() => null);
      if (buf) {
        files.push(new AttachmentBuilder(buf, { name: 'bienvenue.png' }));
        embed.setImage('attachment://bienvenue.png');
      }
    }
    await ch.send({ content: `${member}`, embeds: [embed], files }).catch(() => {});
  }
  if (g.welcome.dm) await member.send(format(g.welcome.dm, vars)).catch(() => {});
}

async function onLeave(member) {
  const { guild } = member;
  const g = db.guild(guild.id);
  const inviter = g.joinedBy[member.id];
  if (inviter && g.invites[inviter]) {
    g.invites[inviter].left++;
    delete g.joinedBy[member.id];
    db.save();
  }
  const ch = g.leave.channel && guild.channels.cache.get(g.leave.channel);
  if (!ch || member.user.bot) return;
  const vars = { user: `${member.user}`, username: member.user.username, server: guild.name, count: guild.memberCount, inviter: inviter ? `<@${inviter}>` : 'inconnu', invites: inviter ? inviteStats(g, inviter).total : 0 };
  await ch.send({ embeds: [new EmbedBuilder().setColor(0x71717a).setDescription(format(g.leave.message || '👋 **{username}** a quitté le serveur. Nous sommes maintenant **{count}**.', vars)).setThumbnail(member.user.displayAvatarURL())] }).catch(() => {});
}

module.exports = {
  inviteStats,
  VARS_HELP,
  format,
  setup(client) {
    client.on('botReady', () => client.guilds.cache.forEach(cacheInvites));
    client.on('guildCreate', cacheInvites);
    client.on('inviteCreate', (i) => i.guild && cacheInvites(i.guild));
    client.on('inviteDelete', (i) => i.guild && cacheInvites(i.guild));
    client.on('guildMemberAdd', (m) => onJoin(m).catch((e) => console.error('[bienvenue]', e)));
    client.on('guildMemberRemove', (m) => onLeave(m).catch((e) => console.error('[départ]', e)));
  },
};
