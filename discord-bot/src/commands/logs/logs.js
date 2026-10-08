const { SlashCommandBuilder, PermissionFlagsBits, ChannelType, PermissionsBitField } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

const TYPES = {
  mod: ['🔨', 'mod-logs', 'Sanctions (ban, kick, mute, warn…)'],
  raid: ['🛡️', 'raid-logs', 'Antiraid et filtres'],
  message: ['💬', 'message-logs', 'Messages supprimés / modifiés'],
  role: ['🎭', 'role-logs', 'Rôles donnés / retirés'],
  voice: ['🔊', 'voice-logs', 'Activité vocale'],
  boost: ['💎', 'boost-logs', 'Boosts'],
  member: ['👋', 'member-logs', 'Arrivées / départs'],
};

// Crée la catégorie et les salons de logs, visibles seulement par le bot et les admins
async function createLogs(guild, staffRole) {
  const overwrites = [
    { id: guild.roles.everyone.id, deny: [PermissionsBitField.Flags.ViewChannel] },
    { id: guild.members.me.id, allow: [PermissionsBitField.Flags.ViewChannel, PermissionsBitField.Flags.SendMessages, PermissionsBitField.Flags.EmbedLinks, PermissionsBitField.Flags.AttachFiles] },
  ];
  if (staffRole) overwrites.push({ id: staffRole.id, allow: [PermissionsBitField.Flags.ViewChannel], deny: [PermissionsBitField.Flags.SendMessages] });
  const cat = await guild.channels.create({ name: '📜 LOGS', type: ChannelType.GuildCategory, permissionOverwrites: overwrites });
  const g = db.guild(guild.id);
  for (const [type, [emoji, name]] of Object.entries(TYPES)) {
    const ch = await guild.channels.create({ name: `${emoji}・${name}`, parent: cat.id, permissionOverwrites: overwrites });
    g.logs[type] = ch.id;
  }
  db.save();
  return cat;
}

module.exports = {
  category: 'Logs',
  createLogs,
  data: new SlashCommandBuilder()
    .setName('logs')
    .setDescription('Configure les salons de logs')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('auto').setDescription('Crée automatiquement tous les salons de logs')
      .addRoleOption((o) => o.setName('staff').setDescription('Rôle staff qui pourra lire les logs')))
    .addSubcommand((s) => s.setName('set').setDescription('Définit le salon d’un type de logs')
      .addStringOption((o) => o.setName('type').setDescription('Type').setRequired(true).addChoices(...Object.entries(TYPES).map(([v, [e, , d]]) => ({ name: `${e} ${v} — ${d}`, value: v }))))
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = désactiver)').addChannelTypes(ChannelType.GuildText)))
    .addSubcommand((s) => s.setName('voir').setDescription('Affiche la configuration des logs')),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'auto') {
      await interaction.deferReply();
      const cat = await createLogs(interaction.guild, interaction.options.getRole('staff'));
      return interaction.editReply({ embeds: [ui.success(`Salons de logs créés dans **${cat.name}**.`)] });
    }
    if (sub === 'set') {
      const type = interaction.options.getString('type', true);
      const ch = interaction.options.getChannel('salon');
      g.logs[type] = ch?.id ?? null;
      db.save();
      return interaction.reply({ embeds: [ui.success(`Logs **${type}** : ${ch ?? 'désactivés'}.`)] });
    }
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('📜 Logs')
      .setDescription(Object.entries(TYPES).map(([t, [e, , d]]) => `${e} **${t}** — ${g.logs[t] ? `<#${g.logs[t]}>` : '*désactivé*'}\n> ${d}`).join('\n'))] });
  },
};
