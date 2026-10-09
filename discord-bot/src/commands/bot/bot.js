const { SlashCommandBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Bot',
  access: 'owner',
  data: new SlashCommandBuilder()
    .setName('bot')
    .setDescription('Contrôle du bot (owners)')
    .addSubcommand((s) => s.setName('statut').setDescription('Statut du bot').addStringOption((o) => o.setName('statut').setDescription('Statut').setRequired(true).addChoices(
      { name: '🟢 En ligne', value: 'online' }, { name: '🌙 Inactif', value: 'idle' }, { name: '⛔ Ne pas déranger', value: 'dnd' }, { name: '⚫ Invisible', value: 'invisible' })))
    .addSubcommand((s) => s.setName('activite').setDescription('Activité du bot (textes séparés par ,, pour alterner)')
      .addStringOption((o) => o.setName('type').setDescription('Type').setRequired(true).addChoices(
        { name: 'Joue à', value: 'playing' }, { name: 'Regarde', value: 'watching' }, { name: 'Écoute', value: 'listening' },
        { name: 'Stream', value: 'streaming' }, { name: 'Participe à', value: 'competing' }, { name: 'Statut perso', value: 'custom' }))
      .addStringOption((o) => o.setName('texte').setDescription('Texte (vide = retirer)').setMaxLength(300)))
    .addSubcommand((s) => s.setName('nom').setDescription('Nom global du bot').addStringOption((o) => o.setName('nom').setDescription('Nom').setRequired(true).setMinLength(2).setMaxLength(32)))
    .addSubcommand((s) => s.setName('avatar').setDescription('Avatar du bot')
      .addAttachmentOption((o) => o.setName('image').setDescription('Image'))
      .addStringOption((o) => o.setName('lien').setDescription('Ou un lien d’image')))
    .addSubcommand((s) => s.setName('serveurs').setDescription('Serveurs où se trouve le bot'))
    .addSubcommand((s) => s.setName('quitter').setDescription('Fait quitter un serveur au bot').addStringOption((o) => o.setName('id').setDescription('ID du serveur').setRequired(true))),
  async run(interaction, client) {
    const sub = interaction.options.getSubcommand();
    const p = db.global.presence;
    if (sub === 'statut') {
      p.status = interaction.options.getString('statut', true);
      db.save();
      client.applyPresence();
      return interaction.reply({ embeds: [ui.success(`Statut : **${p.status}**.`)], flags: 64 });
    }
    if (sub === 'activite') {
      p.type = interaction.options.getString('type', true);
      p.activities = (interaction.options.getString('texte') ?? '').split(',,').map((s) => s.trim()).filter(Boolean);
      db.save();
      client.applyPresence();
      return interaction.reply({ embeds: [ui.success(`Activité mise à jour (${p.activities.length || 'par défaut'}).`)], flags: 64 });
    }
    if (sub === 'nom') {
      await client.user.setUsername(interaction.options.getString('nom', true));
      return interaction.reply({ embeds: [ui.success('Nom modifié (Discord limite à 2 changements par heure).')], flags: 64 });
    }
    if (sub === 'avatar') {
      const url = interaction.options.getAttachment('image')?.url ?? interaction.options.getString('lien');
      if (!url) return interaction.reply({ embeds: [ui.error('Donne une image ou un lien.')], flags: 64 });
      await interaction.deferReply({ flags: 64 });
      await client.user.setAvatar(url);
      return interaction.editReply({ embeds: [ui.success('Avatar modifié.')] });
    }
    if (sub === 'serveurs') {
      const list = client.guilds.cache.map((g) => `${ui.E.dot} **${g.name}** \`${g.id}\` — ${g.memberCount} membres`);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`🌐 ${client.guilds.cache.size} serveur(s)`).setDescription(list.join('\n').slice(0, 4000))], flags: 64 });
    }
    const g = client.guilds.cache.get(interaction.options.getString('id', true));
    if (!g) return interaction.reply({ embeds: [ui.error('Serveur introuvable.')], flags: 64 });
    await interaction.reply({ embeds: [ui.success(`Je quitte **${g.name}**.`)], flags: 64 });
    await g.leave();
  },
};
