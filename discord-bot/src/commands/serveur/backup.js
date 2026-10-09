const fs = require('node:fs');
const path = require('node:path');
const { SlashCommandBuilder, PermissionFlagsBits, ChannelType, ActionRowBuilder, ButtonBuilder, ButtonStyle, OverwriteType } = require('discord.js');
const ui = require('../../util/ui');
const config = require('../../config');
const { isOwner } = require('../../util/perms');
const { ts } = require('../../util/time');

const DIR = path.join(config.dataDir, 'backups');
const file = (name) => path.join(DIR, `${name.replace(/[^\w-]/g, '_').slice(0, 50)}.json`);
const readBackup = (name) => (fs.existsSync(file(name)) ? JSON.parse(fs.readFileSync(file(name), 'utf8')) : null);

function snapshot(guild) {
  const everyone = guild.roles.everyone.id;
  const roles = guild.roles.cache.filter((r) => !r.managed && r.id !== everyone).sort((a, b) => b.position - a.position)
    .map((r) => ({ id: r.id, name: r.name, color: r.color, hoist: r.hoist, mentionable: r.mentionable, permissions: r.permissions.bitfield.toString() }));
  const ow = (c) => c.permissionOverwrites.cache.filter((o) => o.type === OverwriteType.Role)
    .map((o) => ({ id: o.id === everyone ? 'everyone' : o.id, allow: o.allow.bitfield.toString(), deny: o.deny.bitfield.toString() }));
  const chan = (c) => ({ name: c.name, type: c.type, topic: c.topic ?? null, nsfw: !!c.nsfw, rateLimitPerUser: c.rateLimitPerUser ?? 0, bitrate: c.bitrate ?? null, userLimit: c.userLimit ?? 0, overwrites: ow(c) });
  const cats = guild.channels.cache.filter((c) => c.type === ChannelType.GuildCategory).sort((a, b) => a.position - b.position);
  return {
    name: guild.name,
    created: Date.now(),
    everyone: guild.roles.everyone.permissions.bitfield.toString(),
    roles,
    orphans: guild.channels.cache.filter((c) => !c.parentId && c.type !== ChannelType.GuildCategory && !c.isThread()).sort((a, b) => a.position - b.position).map(chan),
    categories: cats.map((cat) => ({
      ...chan(cat),
      children: cat.children.cache.filter((c) => !c.isThread()).sort((a, b) => a.position - b.position).map(chan),
    })),
  };
}

async function load(guild, data, progress) {
  const me = guild.members.me;
  await progress('🧨 Suppression des salons…');
  for (const c of guild.channels.cache.values()) await c.delete('Chargement de backup').catch(() => {});
  await progress('🧨 Suppression des rôles…');
  for (const r of guild.roles.cache.values()) {
    if (r.managed || r.id === guild.id || r.position >= me.roles.highest.position) continue;
    await r.delete('Chargement de backup').catch(() => {});
  }
  await guild.roles.everyone.setPermissions(BigInt(data.everyone)).catch(() => {});
  await progress('🎭 Création des rôles…');
  const map = { everyone: guild.roles.everyone.id };
  for (const r of data.roles) {
    const role = await guild.roles.create({ name: r.name, color: r.color, hoist: r.hoist, mentionable: r.mentionable, permissions: BigInt(r.permissions), reason: 'Backup' }).catch(() => null);
    if (role) map[r.id] = role.id;
  }
  // Les rôles sont créés juste sous le rôle du bot : on les ordonne comme dans la sauvegarde
  const positions = data.roles.map((r, i) => map[r.id] && { role: map[r.id], position: Math.max(1, me.roles.highest.position - 1 - i) }).filter(Boolean);
  await guild.roles.setPositions(positions).catch(() => {});
  const overwrites = (list) => list.filter((o) => map[o.id]).map((o) => ({ id: map[o.id], allow: BigInt(o.allow), deny: BigInt(o.deny), type: OverwriteType.Role }));
  const make = (c, parent) => guild.channels.create({
    name: c.name, type: c.type, topic: c.topic ?? undefined, nsfw: c.nsfw, rateLimitPerUser: c.rateLimitPerUser || undefined,
    bitrate: c.bitrate ? Math.min(c.bitrate, guild.maximumBitrate) : undefined, userLimit: c.userLimit || undefined, parent, permissionOverwrites: overwrites(c.overwrites),
  }).catch(() => null);
  await progress('📁 Création des salons…');
  let first = null;
  for (const c of data.orphans) { const ch = await make(c); if (!first && ch?.isTextBased()) first = ch; }
  for (const cat of data.categories) {
    const parent = await make(cat);
    for (const c of cat.children) { const ch = await make(c, parent?.id); if (!first && ch?.isTextBased()) first = ch; }
  }
  return first;
}

module.exports = {
  category: 'Serveur',
  access: 'trusted',
  snapshot,
  data: new SlashCommandBuilder()
    .setName('backup')
    .setDescription('Sauvegarde et restauration du serveur (rôles, salons, permissions)')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((s) => s.setName('creer').setDescription('Crée une sauvegarde').addStringOption((o) => o.setName('nom').setDescription('Nom de la sauvegarde').setRequired(true).setMaxLength(50)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste des sauvegardes'))
    .addSubcommand((s) => s.setName('info').setDescription('Contenu d’une sauvegarde').addStringOption((o) => o.setName('nom').setDescription('Nom').setRequired(true).setAutocomplete(true)))
    .addSubcommand((s) => s.setName('charger').setDescription('⚠️ Remplace TOUT le serveur par la sauvegarde').addStringOption((o) => o.setName('nom').setDescription('Nom').setRequired(true).setAutocomplete(true)))
    .addSubcommand((s) => s.setName('supprimer').setDescription('Supprime une sauvegarde').addStringOption((o) => o.setName('nom').setDescription('Nom').setRequired(true).setAutocomplete(true))),
  async autocomplete(interaction) {
    const q = interaction.options.getFocused().toLowerCase();
    const names = fs.existsSync(DIR) ? fs.readdirSync(DIR).map((f) => f.replace(/\.json$/, '')) : [];
    await interaction.respond(names.filter((n) => n.toLowerCase().includes(q)).slice(0, 25).map((n) => ({ name: n, value: n })));
  },
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    fs.mkdirSync(DIR, { recursive: true });
    if (sub === 'liste') {
      const list = fs.readdirSync(DIR).map((f) => { const d = JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8')); return `${ui.E.dot} **${f.replace(/\.json$/, '')}** — ${d.name} ${ts(d.created)}`; });
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('💾 Sauvegardes').setDescription(list.join('\n').slice(0, 4000) || 'Aucune.')], flags: 64 });
    }
    const name = interaction.options.getString('nom', true);
    if (sub === 'creer') {
      const data = snapshot(interaction.guild);
      data.by = interaction.user.id;
      fs.writeFileSync(file(name), JSON.stringify(data));
      const n = data.orphans.length + data.categories.reduce((a, c) => a + 1 + c.children.length, 0);
      return interaction.reply({ embeds: [ui.success(`💾 Sauvegarde **${name}** créée : ${data.roles.length} rôles, ${n} salons.`)], flags: 64 });
    }
    const data = readBackup(name);
    if (!data) return interaction.reply({ embeds: [ui.error('Sauvegarde introuvable.')], flags: 64 });
    if (data.by && data.by !== interaction.user.id && !isOwner(interaction.user.id)) return interaction.reply({ embeds: [ui.error('Cette sauvegarde ne t’appartient pas.')], flags: 64 });
    if (sub === 'supprimer') {
      fs.unlinkSync(file(name));
      return interaction.reply({ embeds: [ui.success('Sauvegarde supprimée.')], flags: 64 });
    }
    if (sub === 'info') {
      const tree = [...data.orphans.map((c) => `# ${c.name}`), ...data.categories.map((c) => `📁 ${c.name}\n${c.children.map((x) => `   # ${x.name}`).join('\n')}`)].join('\n');
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`💾 ${name}`).setDescription(`Serveur : **${data.name}** • ${ts(data.created)}\n**Rôles (${data.roles.length}) :** ${data.roles.map((r) => r.name).join(', ').slice(0, 800)}\n\`\`\`${tree.slice(0, 2800)}\`\`\``)], flags: 64 });
    }
    const row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId('ok').setLabel('Oui, tout remplacer').setStyle(ButtonStyle.Danger),
      new ButtonBuilder().setCustomId('no').setLabel('Annuler').setStyle(ButtonStyle.Secondary),
    );
    const res = await interaction.reply({ embeds: [ui.info(`${ui.E.warn} **Tous les salons et rôles actuels seront supprimés** puis remplacés par la sauvegarde **${name}**. Continuer ?`, interaction.guild)], components: [row], withResponse: true });
    const click = await res.resource.message.awaitMessageComponent({ filter: (i) => i.user.id === interaction.user.id, time: 30e3 }).catch(() => null);
    if (click?.customId !== 'ok') return interaction.editReply({ embeds: [ui.info('Annulé.', interaction.guild)], components: [] });
    await click.update({ embeds: [ui.info(`${ui.E.load} Chargement… le salon actuel va disparaître.`, interaction.guild)], components: [] });
    const first = await load(interaction.guild, data, async () => {});
    await first?.send({ embeds: [ui.success(`💾 Sauvegarde **${name}** chargée par ${interaction.user}.`)] });
  },
};
