// Construit un serveur complet en une commande : rôles, catégories, salons, logs,
// tickets, vocaux temporaires, bienvenue, suggestions et antiraid.
const { SlashCommandBuilder, PermissionFlagsBits, ChannelType, PermissionsBitField, ActionRowBuilder, ButtonBuilder, ButtonStyle } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { createLogs } = require('../logs/logs');
const tickets = require('../../modules/tickets');
const { setAll } = require('../securite/secur');

const P = PermissionsBitField.Flags;

const ROLES = [
  { key: 'admin', name: '👑 Administrateur', color: 0xef4444, hoist: true, permissions: [P.Administrator] },
  { key: 'mod', name: '🛡️ Modérateur', color: 0x8b5cf6, hoist: true, permissions: [P.KickMembers, P.BanMembers, P.ModerateMembers, P.ManageMessages, P.ManageNicknames, P.MoveMembers, P.MuteMembers, P.ViewAuditLog] },
  { key: 'support', name: '🎫 Support', color: 0x3b82f6, hoist: true, permissions: [P.ManageMessages] },
  { key: 'vip', name: '💎 VIP', color: 0xf472b6, hoist: true, permissions: [] },
  { key: 'member', name: '✨ Membre', color: 0x22c55e, hoist: false, permissions: [] },
  { key: 'bots', name: '🤖 Bots', color: 0x64748b, hoist: true, permissions: [] },
];

const RULES = [
  '**1.** Respect de tous les membres : pas d’insultes, de harcèlement ni de discrimination.',
  '**2.** Pas de spam, de flood ni de mentions abusives.',
  '**3.** Pas de pub (serveurs, réseaux) sans autorisation du staff.',
  '**4.** Contenu NSFW, choquant ou illégal interdit.',
  '**5.** Pas de pseudo ou d’avatar inapproprié.',
  '**6.** Les décisions du staff sont à respecter ; un souci ? ouvre un ticket.',
  '**7.** Respect des [conditions d’utilisation de Discord](https://discord.com/terms).',
].join('\n');

async function build(guild, { antiraid, progress }) {
  const g = db.guild(guild.id);
  const everyone = guild.roles.everyone.id;
  const roles = {};
  await progress('🎭 Création des rôles…');
  for (const r of ROLES) roles[r.key] = await guild.roles.create({ name: r.name, color: r.color, hoist: r.hoist, permissions: r.permissions, reason: 'Setup serveur' });
  const readOnly = [{ id: everyone, deny: [P.SendMessages, P.AddReactions, P.CreatePublicThreads] }, { id: guild.members.me.id, allow: [P.SendMessages, P.EmbedLinks, P.AttachFiles] }];
  const staffOnly = [{ id: everyone, deny: [P.ViewChannel] }, { id: roles.mod.id, allow: [P.ViewChannel] }, { id: roles.support.id, allow: [P.ViewChannel] }, { id: guild.members.me.id, allow: [P.ViewChannel] }];
  const create = (name, type, parent, extra = {}) => guild.channels.create({ name, type, parent, reason: 'Setup serveur', ...extra });

  await progress('📁 Création des salons…');
  const info = await create('📌 INFORMATIONS', ChannelType.GuildCategory, null, { permissionOverwrites: readOnly });
  const rules = await create('📜・règlement', ChannelType.GuildText, info.id);
  const annonces = await create('📢・annonces', ChannelType.GuildText, info.id);
  const bienvenue = await create('👋・bienvenue', ChannelType.GuildText, info.id);
  const departs = await create('🚪・départs', ChannelType.GuildText, info.id);
  await create('🎉・giveaways', ChannelType.GuildText, info.id);

  const commu = await create('💬 COMMUNAUTÉ', ChannelType.GuildCategory);
  const general = await create('💬・général', ChannelType.GuildText, commu.id);
  await create('📸・médias', ChannelType.GuildText, commu.id);
  await create('🤖・commandes', ChannelType.GuildText, commu.id);
  await create('🎵・musique', ChannelType.GuildText, commu.id);
  const sugg = await create('💡・suggestions', ChannelType.GuildText, commu.id, { rateLimitPerUser: 60 });

  const voc = await create('🔊 VOCAUX', ChannelType.GuildCategory);
  await create('🔊 Général', ChannelType.GuildVoice, voc.id);
  await create('🎮 Gaming', ChannelType.GuildVoice, voc.id);
  await create('🎵 Musique', ChannelType.GuildVoice, voc.id);
  const hub = await create('➕ Créer ton vocal', ChannelType.GuildVoice, voc.id);

  const support = await create('🎫 SUPPORT', ChannelType.GuildCategory);
  const ticketPanel = await create('🎫・ouvrir-un-ticket', ChannelType.GuildText, support.id, { permissionOverwrites: readOnly });
  const ticketsCat = await create('🎫 TICKETS', ChannelType.GuildCategory, null, { permissionOverwrites: staffOnly });

  const staff = await create('🛡️ STAFF', ChannelType.GuildCategory, null, { permissionOverwrites: staffOnly });
  await create('💼・staff-chat', ChannelType.GuildText, staff.id);
  await create('📋・sanctions', ChannelType.GuildText, staff.id);
  await create('🔊 Staff', ChannelType.GuildVoice, staff.id);

  await progress('📜 Création des logs…');
  await createLogs(guild, roles.mod);

  await progress('⚙️ Configuration du bot…');
  g.welcome = { ...g.welcome, channel: bienvenue.id, card: true, autoroles: [roles.member.id] };
  g.leave = { ...g.leave, channel: departs.id };
  g.suggestions.channel = sugg.id;
  g.tempvoc.hub = hub.id;
  g.tickets.staffRole = roles.support.id;
  g.tickets.category = ticketsCat.id;
  g.security.noderank = [...new Set([...g.security.noderank, roles.member.id])];
  if (antiraid) setAll(guild, 'recommended');
  db.save();

  // Messages d'accueil des salons
  await rules.send({ embeds: [ui.embed(guild).setTitle(`📜 Règlement de ${guild.name}`).setDescription(RULES).setFooter({ text: 'En restant sur le serveur, tu acceptes ce règlement.' })] });
  await ticketPanel.send(tickets.panelPayload(guild));
  await annonces.send({ embeds: [ui.embed(guild).setTitle('📢 Bienvenue !').setDescription('Le serveur vient d’être installé. Les annonces arriveront ici.')] });

  // Tous les membres actuels reçoivent le rôle Membre, les bots le rôle Bots
  await progress('👥 Attribution des rôles aux membres…');
  const members = await guild.members.fetch();
  for (const m of members.values()) await m.roles.add(m.user.bot ? roles.bots : roles.member).catch(() => {});
  return { general, roles };
}

module.exports = {
  category: 'Serveur',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('setup-serveur')
    .setDescription('Construit automatiquement un serveur complet (rôles, salons, logs, tickets…)')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addBooleanOption((o) => o.setName('antiraid').setDescription('Activer aussi la protection antiraid recommandée (défaut : oui)'))
    .addBooleanOption((o) => o.setName('reinitialiser').setDescription('⚠️ Supprimer d’abord TOUS les salons et rôles existants')),
  async run(interaction) {
    const reset = interaction.options.getBoolean('reinitialiser') ?? false;
    const antiraid = interaction.options.getBoolean('antiraid') ?? true;
    const row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId('ok').setLabel('Construire le serveur').setEmoji('🏗️').setStyle(reset ? ButtonStyle.Danger : ButtonStyle.Success),
      new ButtonBuilder().setCustomId('no').setLabel('Annuler').setStyle(ButtonStyle.Secondary),
    );
    const res = await interaction.reply({
      embeds: [ui.embed(interaction.guild).setTitle('🏗️ Setup du serveur').setDescription([
        'Je vais créer :',
        '• **Rôles** : Administrateur, Modérateur, Support, VIP, Membre, Bots',
        '• **Catégories** : Informations, Communauté, Vocaux, Support, Tickets, Staff, Logs',
        '• **Systèmes** : règlement, bienvenue + carte, départs, suggestions, tickets, vocaux temporaires, logs complets',
        antiraid ? '• **Antiraid** : configuration recommandée activée' : null,
        reset ? `\n${ui.E.warn} **Tous les salons et rôles actuels seront SUPPRIMÉS avant.**` : '\nLes salons existants sont conservés.',
      ].filter(Boolean).join('\n'))],
      components: [row],
      withResponse: true,
    });
    const click = await res.resource.message.awaitMessageComponent({ filter: (i) => i.user.id === interaction.user.id, time: 60e3 }).catch(() => null);
    if (click?.customId !== 'ok') return interaction.editReply({ embeds: [ui.info('Annulé.', interaction.guild)], components: [] });
    await click.update({ embeds: [ui.info(`${ui.E.load} Construction en cours…`, interaction.guild)], components: [] });
    const { guild } = interaction;
    let alive = !reset;
    const progress = async (text) => { if (alive) await interaction.editReply({ embeds: [ui.info(`${ui.E.load} ${text}`, guild)] }).catch(() => { alive = false; }); };
    if (reset) {
      for (const c of guild.channels.cache.values()) await c.delete('Setup serveur : réinitialisation').catch(() => {});
      for (const r of guild.roles.cache.values()) {
        if (r.managed || r.id === guild.id || r.position >= guild.members.me.roles.highest.position) continue;
        await r.delete('Setup serveur : réinitialisation').catch(() => {});
      }
    }
    const { general } = await build(guild, { antiraid, progress });
    const done = ui.embed(guild).setTitle('✅ Serveur prêt !').setDescription([
      `Tout est en place, ${interaction.user}.`,
      '',
      '**Ensuite :**',
      '• Monte le rôle du bot **tout en haut** de la liste des rôles (Paramètres → Rôles)',
      '• `/secur` pour voir et ajuster les protections',
      '• `/whitelist ajouter` pour tes modérateurs de confiance',
      '• `/style gifs` pour choisir les GIF des sanctions',
    ].join('\n'));
    if (alive) await interaction.editReply({ embeds: [done] }).catch(() => {});
    else await general.send({ embeds: [done] });
  },
};
