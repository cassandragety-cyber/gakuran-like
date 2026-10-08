const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('autoreact')
    .setDescription('Réactions automatiques sur chaque message d’un salon')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageChannels)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute des réactions')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon').setRequired(true).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
      .addStringOption((o) => o.setName('emojis').setDescription('Un ou plusieurs émojis').setRequired(true)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire toutes les réactions d’un salon')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon').setRequired(true)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste des autoreacts')),
  async run(interaction) {
    const ar = db.guild(interaction.guild.id).autoreact;
    const sub = interaction.options.getSubcommand();
    if (sub === 'liste') return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('Autoreacts').setDescription(Object.entries(ar).map(([c, e]) => `<#${c}> : ${e.join(' ')}`).join('\n') || 'Aucun.')] });
    const ch = interaction.options.getChannel('salon', true);
    if (sub === 'retirer') {
      delete ar[ch.id];
      db.save();
      return interaction.reply({ embeds: [ui.success(`Autoreact retiré de ${ch}.`)] });
    }
    const raw = interaction.options.getString('emojis', true);
    const emojis = [...raw.matchAll(/<a?:\w+:(\d+)>|\p{Extended_Pictographic}(‍\p{Extended_Pictographic}|️)*/gu)].map((m) => m[1] ?? m[0]);
    if (!emojis.length) return interaction.reply({ embeds: [ui.error('Aucun émoji reconnu.')], flags: 64 });
    ar[ch.id] = [...new Set([...(ar[ch.id] ?? []), ...emojis])].slice(0, 10);
    db.save();
    await interaction.reply({ embeds: [ui.success(`Autoreact sur ${ch} : ${raw}`)] });
  },
};
