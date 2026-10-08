// Antiraid : surveille le journal d'audit en temps réel, annule les actions
// non autorisées (salons, rôles, webhooks, bans en masse…) et punit leur auteur.
const { AuditLogEvent, EmbedBuilder, Routes, PermissionFlagsBits } = require('discord.js');
const db = require('../db');
const { isOwner, isWhitelisted, isDangerousRole } = require('../util/perms');
const { sendLog } = require('../util/logs');
const { COLORS } = require('../util/ui');

const LABELS = {
  antibot: 'Ajout de bot', antichannel: 'Salons', antirole: 'Rôles', antiwebhook: 'Webhooks',
  antiban: 'Bans en masse', antikick: 'Kicks en masse', antiunban: 'Unbans en masse', antirank: 'Ajout de rôles dangereux',
  antiupdate: 'Modification du serveur', antiemote: 'Émojis', antithread: 'Fils', antideco: 'Déconnexions vocales',
  antiautomod: 'Règles AutoMod', antieveryone: '@everyone / @here', antilink: 'Liens / invitations',
  antispam: 'Spam', antitoken: 'Arrivées massives (raid)',
};

const PUNISHMENTS = ['derank', 'derank_timeout', 'kick', 'ban'];

const mode = (guild, module) => db.guild(guild.id).security.modules[module] ?? 'off';

// Est-ce que cet utilisateur échappe au module ?
function bypass(guild, userId, module) {
  if (userId === guild.client.user.id) return true;
  if (isOwner(userId) || userId === guild.ownerId) return true;
  if (mode(guild, module) === 'max') return false;
  return isWhitelisted(guild, guild.members.cache.get(userId) ?? userId);
}

// Compteurs glissants pour les modules à limite (antiban 3/10s, antispam 6/4s…)
const counters = new Map();
function exceeded(guild, userId, module) {
  const lim = db.guild(guild.id).security.limits[module];
  if (!lim) return true; // module sans limite : tolérance zéro
  const key = `${guild.id}:${userId}:${module}`;
  const now = Date.now();
  const list = (counters.get(key) ?? []).filter((t) => now - t < lim.window * 1000);
  list.push(now);
  counters.set(key, list);
  return list.length > lim.count;
}
setInterval(() => {
  const now = Date.now();
  for (const [k, list] of counters) if (!list.some((t) => now - t < 120e3)) counters.delete(k);
}, 60e3).unref();

const recentlyPunished = new Map();

async function punish(guild, userId, module, what) {
  const key = `${guild.id}:${userId}`;
  const first = !recentlyPunished.has(key) || Date.now() - recentlyPunished.get(key) > 15e3;
  recentlyPunished.set(key, Date.now());
  const sec = db.guild(guild.id).security;
  let kind = sec.punish[module] ?? sec.punish.default;
  let result = 'aucune (déjà puni il y a moins de 15 s)';
  if (first) {
    const member = await guild.members.fetch(userId).catch(() => null);
    const reason = `[Antiraid] ${LABELS[module]} : ${what}`;
    try {
      if (member?.user.bot) kind = 'ban'; // un bot malveillant est toujours banni
      if (kind === 'ban') await guild.members.ban(userId, { reason });
      else if (!member) result = 'membre introuvable';
      else if (kind === 'kick') await member.kick(reason);
      else {
        const { derank } = require('../commands/moderation/derank');
        await derank(member, reason);
        if (kind === 'derank_timeout' && !member.permissions.has(PermissionFlagsBits.Administrator)) await member.timeout(3600e3, reason);
      }
      if (result.startsWith('aucune')) result = { ban: 'banni', kick: 'expulsé', derank: 'derank', derank_timeout: 'derank + mute 1h' }[kind];
    } catch (err) {
      result = `échec (${err.message}) — mon rôle est-il tout en haut ?`;
    }
  }
  const e = new EmbedBuilder()
    .setColor(COLORS.ban)
    .setTitle(`🛡️ Antiraid • ${LABELS[module]}`)
    .setDescription(`**Auteur :** <@${userId}> (\`${userId}\`)\n**Action détectée :** ${what}\n**Sanction :** ${result}`)
    .setTimestamp();
  const ping = sec.pingraid;
  await sendLog(guild, 'raid', { content: first && ping ? (ping === 'everyone' ? '@everyone' : `<@&${ping}>`) : undefined, embeds: [e], allowedMentions: { parse: ['everyone', 'roles'] } });
}

// Appelé par /ban, /kick, /unban : un modérateur non whitelisté ne peut pas dépasser les limites via le bot.
async function trackModAction(member, module) {
  const guild = member.guild;
  if (mode(guild, module) === 'off' || bypass(guild, member.id, module)) return true;
  if (!exceeded(guild, member.id, module)) return true;
  await punish(guild, member.id, module, 'limite dépassée via les commandes du bot');
  return false;
}

// ─── Instantanés pour pouvoir recréer ce qui est supprimé ───────
const deletedChannels = new Map();
const deletedEmojis = new Map();

function snapshotChannel(ch) {
  return {
    name: ch.name, type: ch.type, topic: ch.topic ?? undefined, nsfw: ch.nsfw, bitrate: ch.bitrate ?? undefined,
    userLimit: ch.userLimit ?? undefined, rateLimitPerUser: ch.rateLimitPerUser ?? undefined, parent: ch.parentId,
    position: ch.rawPosition,
    permissionOverwrites: ch.permissionOverwrites?.cache.map((o) => ({ id: o.id, type: o.type, allow: o.allow.bitfield, deny: o.deny.bitfield })) ?? [],
  };
}

async function waitFor(map, id, ms = 2500) {
  for (let t = 0; t < ms; t += 250) {
    if (map.has(id)) return map.get(id);
    await new Promise((r) => setTimeout(r, 250));
  }
  return null;
}

const CHANNEL_KEYS = { name: 'name', topic: 'topic', nsfw: 'nsfw', bitrate: 'bitrate', user_limit: 'userLimit', rate_limit_per_user: 'rateLimitPerUser' };
const ROLE_KEYS = { name: 'name', color: 'color', hoist: 'hoist', mentionable: 'mentionable', permissions: 'permissions' };
const GUILD_KEYS = { name: 'name', description: 'description', verification_level: 'verificationLevel', explicit_content_filter: 'explicitContentFilter', default_message_notifications: 'defaultMessageNotifications' };

function oldValues(changes, map) {
  const out = {};
  for (const c of changes) if (map[c.key] && c.old !== undefined) out[map[c.key]] = c.key === 'permissions' ? BigInt(c.old) : c.old;
  return out;
}

// ─── Réactions à chaque type d'entrée du journal d'audit ────────
const HANDLERS = {
  [AuditLogEvent.BotAdd]: ['antibot', 'a ajouté un bot', async (g, e) => g.members.ban(e.targetId, { reason: '[Antiraid] bot non autorisé' })],
  [AuditLogEvent.ChannelCreate]: ['antichannel', 'a créé un salon', async (g, e) => g.channels.cache.get(e.targetId)?.delete('[Antiraid] création non autorisée')],
  [AuditLogEvent.ChannelDelete]: ['antichannel', 'a supprimé un salon', async (g, e) => {
    const snap = await waitFor(deletedChannels, e.targetId);
    if (snap) await g.channels.create({ ...snap, reason: '[Antiraid] restauration' });
  }],
  [AuditLogEvent.ChannelUpdate]: ['antichannel', 'a modifié un salon', async (g, e) => {
    const vals = oldValues(e.changes, CHANNEL_KEYS);
    if (Object.keys(vals).length) await g.channels.cache.get(e.targetId)?.edit({ ...vals, reason: '[Antiraid] restauration' });
  }],
  [AuditLogEvent.ChannelOverwriteCreate]: ['antichannel', 'a ajouté une permission de salon', async (g, e) => g.channels.cache.get(e.targetId)?.permissionOverwrites.delete(e.extra.id, '[Antiraid]')],
  [AuditLogEvent.ChannelOverwriteUpdate]: ['antichannel', 'a modifié une permission de salon', (g, e) => restoreOverwrite(g, e)],
  [AuditLogEvent.ChannelOverwriteDelete]: ['antichannel', 'a supprimé une permission de salon', (g, e) => restoreOverwrite(g, e)],
  [AuditLogEvent.RoleCreate]: ['antirole', 'a créé un rôle', async (g, e) => g.roles.cache.get(e.targetId)?.delete('[Antiraid] création non autorisée')],
  [AuditLogEvent.RoleDelete]: ['antirole', 'a supprimé un rôle', async (g, e) => g.roles.create({ ...oldValues(e.changes, ROLE_KEYS), reason: '[Antiraid] restauration' })],
  [AuditLogEvent.RoleUpdate]: ['antirole', 'a modifié un rôle', async (g, e) => {
    const vals = oldValues(e.changes, ROLE_KEYS);
    if (Object.keys(vals).length) await g.roles.cache.get(e.targetId)?.edit({ ...vals, reason: '[Antiraid] restauration' });
  }],
  [AuditLogEvent.WebhookCreate]: ['antiwebhook', 'a créé un webhook', async (g, e) => (await g.client.fetchWebhook(e.targetId).catch(() => null))?.delete('[Antiraid]')],
  [AuditLogEvent.MemberBanAdd]: ['antiban', 'a banni des membres', async (g, e) => g.members.unban(e.targetId, '[Antiraid] ban annulé').catch(() => {})],
  [AuditLogEvent.MemberKick]: ['antikick', 'a expulsé des membres', null],
  [AuditLogEvent.MemberBanRemove]: ['antiunban', 'a débanni des membres', async (g, e) => g.members.ban(e.targetId, { reason: '[Antiraid] unban annulé' })],
  [AuditLogEvent.MemberDisconnect]: ['antideco', 'a déconnecté des membres du vocal', null],
  [AuditLogEvent.MemberMove]: ['antideco', 'a déplacé des membres en vocal', null],
  [AuditLogEvent.GuildUpdate]: ['antiupdate', 'a modifié le serveur', async (g, e) => {
    const vals = oldValues(e.changes, GUILD_KEYS);
    if (Object.keys(vals).length) await g.edit({ ...vals, reason: '[Antiraid] restauration' });
  }],
  [AuditLogEvent.EmojiCreate]: ['antiemote', 'a ajouté un émoji', async (g, e) => g.emojis.cache.get(e.targetId)?.delete('[Antiraid]')],
  [AuditLogEvent.EmojiDelete]: ['antiemote', 'a supprimé un émoji', async (g, e) => {
    const snap = await waitFor(deletedEmojis, e.targetId);
    if (snap) await g.emojis.create({ ...snap, reason: '[Antiraid] restauration' });
  }],
  [AuditLogEvent.EmojiUpdate]: ['antiemote', 'a renommé un émoji', async (g, e) => {
    const old = e.changes.find((c) => c.key === 'name')?.old;
    if (old) await g.emojis.cache.get(e.targetId)?.edit({ name: old });
  }],
  [AuditLogEvent.ThreadCreate]: ['antithread', 'a créé un fil', async (g, e) => g.channels.cache.get(e.targetId)?.delete('[Antiraid]')],
  [AuditLogEvent.AutoModerationRuleCreate]: ['antiautomod', 'a créé une règle AutoMod', async (g, e) => (await g.autoModerationRules.fetch(e.targetId).catch(() => null))?.delete('[Antiraid]')],
  [AuditLogEvent.AutoModerationRuleUpdate]: ['antiautomod', 'a modifié une règle AutoMod', null],
  [AuditLogEvent.AutoModerationRuleDelete]: ['antiautomod', 'a supprimé une règle AutoMod', null],
};

async function restoreOverwrite(guild, entry) {
  const get = (k) => entry.changes.find((c) => c.key === k)?.old;
  const allow = get('allow');
  const deny = get('deny');
  if (allow === undefined && deny === undefined) return;
  await guild.client.rest.put(Routes.channelPermission(entry.targetId, entry.extra.id), {
    body: { allow: String(allow ?? 0), deny: String(deny ?? 0), type: guild.roles.cache.has(entry.extra.id) ? 0 : 1 },
    reason: '[Antiraid] restauration',
  });
}

const LIMITED = new Set(['antiban', 'antikick', 'antiunban', 'antideco']);

async function onAudit(entry, guild) {
  if (entry.action === AuditLogEvent.MemberRoleUpdate) return antirank(entry, guild);
  const h = HANDLERS[entry.action];
  if (!h) return;
  const [module, what, revert] = h;
  const executor = entry.executorId;
  if (!executor || mode(guild, module) === 'off' || bypass(guild, executor, module)) return;
  if (LIMITED.has(module)) {
    // MemberDisconnect/MemberMove regroupent plusieurs actions dans une même entrée
    const times = Math.max(1, Number(entry.extra?.count ?? 1));
    let over = false;
    for (let i = 0; i < times; i++) over = exceeded(guild, executor, module) || over;
    if (!over) return;
  }
  try {
    if (revert) await revert(guild, entry);
  } catch (err) {
    console.warn(`[antiraid] annulation ${module} :`, err.message);
  }
  await punish(guild, executor, module, what);
}

async function antirank(entry, guild) {
  const executor = entry.executorId;
  if (!executor || mode(guild, 'antirank') === 'off' || bypass(guild, executor, 'antirank')) return;
  const added = entry.changes.find((c) => c.key === '$add')?.new ?? [];
  const all = db.guild(guild.id).security.antirankType === 'all';
  const ignored = db.guild(guild.id).security.antirankIgnore ?? [];
  const roles = added.map((r) => guild.roles.cache.get(r.id)).filter((r) => r && !ignored.includes(r.id) && (all || isDangerousRole(r)));
  if (!roles.length) return;
  const target = await guild.members.fetch(entry.targetId).catch(() => null);
  await target?.roles.remove(roles, '[Antiraid] ajout de rôle non autorisé').catch(() => {});
  await punish(guild, executor, 'antirank', `a donné ${roles.map((r) => `**${r.name}**`).join(', ')} à <@${entry.targetId}>`);
}

// ─── Arrivées : blacklist, âge minimum du compte, raid ─────────
const joins = new Map();
async function onJoin(member) {
  const { guild } = member;
  const sec = db.guild(guild.id).security;
  const bl = sec.blacklist[member.id];
  if (bl) return member.ban({ reason: `[Blacklist] ${bl.reason || 'aucune raison'}` }).catch(() => {});

  if (sec.createlimit && Date.now() - member.user.createdTimestamp < sec.createlimit && !member.user.bot) {
    await member.send(`🛡️ Ton compte est trop récent pour rejoindre **${guild.name}**.`).catch(() => {});
    await member.kick('[Antiraid] compte trop récent').catch(() => {});
    return sendLog(guild, 'raid', new EmbedBuilder().setColor(COLORS.warn).setDescription(`🛡️ ${member.user} expulsé : compte créé <t:${Math.floor(member.user.createdTimestamp / 1000)}:R>.`));
  }

  if (sec.raidmode && (!sec.raidmodeUntil || Date.now() < sec.raidmodeUntil)) {
    await member.send(`🛡️ **${guild.name}** est actuellement en mode anti-raid, réessaie plus tard.`).catch(() => {});
    return member.kick('[Antiraid] mode raid actif').catch(() => {});
  }
  if (sec.raidmode && sec.raidmodeUntil && Date.now() >= sec.raidmodeUntil) {
    sec.raidmode = false;
    db.save();
  }

  if (mode(guild, 'antitoken') !== 'off' && !member.user.bot) {
    const lim = sec.limits.antitoken;
    const list = (joins.get(guild.id) ?? []).filter((j) => Date.now() - j.t < lim.window * 1000);
    list.push({ t: Date.now(), id: member.id });
    joins.set(guild.id, list);
    if (list.length > lim.count && !sec.raidmode) {
      sec.raidmode = true;
      sec.raidmodeUntil = Date.now() + 10 * 60e3;
      db.save();
      // On expulse la vague d'arrivées qui a déclenché l'alerte
      for (const j of list) await guild.members.cache.get(j.id)?.kick('[Antiraid] raid détecté').catch(() => {});
      const e = new EmbedBuilder().setColor(COLORS.ban).setTitle('🚨 RAID DÉTECTÉ')
        .setDescription(`**${list.length}** arrivées en ${lim.window}s.\nMode raid activé pour **10 minutes** : toute nouvelle arrivée est expulsée.\nDésactiver : \`/securite raidmode etat:off\``);
      await sendLog(guild, 'raid', { content: sec.pingraid ? (sec.pingraid === 'everyone' ? '@everyone' : `<@&${sec.pingraid}>`) : undefined, embeds: [e], allowedMentions: { parse: ['everyone', 'roles'] } });
    }
  }
}

module.exports = {
  LABELS,
  PUNISHMENTS,
  bypass,
  exceeded,
  punish,
  trackModAction,
  setup(client) {
    client.on('guildAuditLogEntryCreate', (entry, guild) => onAudit(entry, guild).catch((e) => console.error('[antiraid]', e)));
    client.on('guildMemberAdd', (m) => onJoin(m).catch((e) => console.error('[antiraid join]', e)));
    client.on('channelDelete', (ch) => {
      if (!ch.guild) return;
      deletedChannels.set(ch.id, snapshotChannel(ch));
      setTimeout(() => deletedChannels.delete(ch.id), 30e3);
    });
    client.on('emojiDelete', (emoji) => {
      deletedEmojis.set(emoji.id, { attachment: emoji.imageURL(), name: emoji.name });
      setTimeout(() => deletedEmojis.delete(emoji.id), 30e3);
    });
  },
};
