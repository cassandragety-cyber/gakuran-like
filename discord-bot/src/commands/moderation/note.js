const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('note')
    .setDescription('Notes privées du staff sur les membres')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute une note')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addStringOption((o) => o.setName('note').setDescription('Contenu').setRequired(true).setMaxLength(500)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Supprime une note (ou toutes)')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addIntegerOption((o) => o.setName('numero').setDescription('Numéro de la note (vide = toutes)').setMinValue(1)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste les notes')
      .addUserOption((o) => o.setName('membre').setDescription('Membre (vide = tout le serveur)'))),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    const user = interaction.options.getUser('membre');
    if (sub === 'ajouter') {
      (g.notes[user.id] ??= []).push({ text: interaction.options.getString('note', true), by: interaction.user.id, date: Date.now() });
      db.save();
      return interaction.reply({ embeds: [ui.success(`${ui.E.note} Note ajoutée pour ${user} (${g.notes[user.id].length} au total).`)], flags: 64 });
    }
    if (sub === 'retirer') {
      const n = interaction.options.getInteger('numero');
      if (!n) delete g.notes[user.id];
      else if (!g.notes[user.id]?.[n - 1]) return interaction.reply({ embeds: [ui.error('Note introuvable.')], flags: 64 });
      else g.notes[user.id].splice(n - 1, 1);
      db.save();
      return interaction.reply({ embeds: [ui.success(n ? `Note n°${n} supprimée.` : `Toutes les notes de ${user} supprimées.`)], flags: 64 });
    }
    const entries = user ? [[user.id, g.notes[user.id] ?? []]] : Object.entries(g.notes);
    const text = entries.filter(([, l]) => l.length).map(([id, list]) => `**<@${id}>**\n${list.map((n, i) => `\`${i + 1}.\` ${n.text} — <@${n.by}> ${ts(n.date)}`).join('\n')}`).join('\n\n');
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`${ui.E.note} Notes`).setDescription(text.slice(0, 4000) || 'Aucune note.')], flags: 64 });
  },
};
