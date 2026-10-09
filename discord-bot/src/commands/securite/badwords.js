const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Sécurité',
  data: new SlashCommandBuilder()
    .setName('badwords')
    .setDescription('Mots interdits (supprimés automatiquement)')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('on').setDescription('Active le filtre'))
    .addSubcommand((s) => s.setName('off').setDescription('Désactive le filtre'))
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute des mots (séparés par des virgules)')
      .addStringOption((o) => o.setName('mots').setDescription('mot1, mot2…').setRequired(true)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire un mot')
      .addStringOption((o) => o.setName('mot').setDescription('Mot').setRequired(true)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste des mots interdits')),
  async run(interaction) {
    const bw = db.guild(interaction.guild.id).security.badwords;
    const sub = interaction.options.getSubcommand();
    if (sub === 'on' || sub === 'off') bw.enabled = sub === 'on';
    if (sub === 'ajouter') for (const w of interaction.options.getString('mots', true).split(',').map((s) => s.trim().toLowerCase()).filter(Boolean)) if (!bw.words.includes(w)) bw.words.push(w);
    if (sub === 'retirer') bw.words = bw.words.filter((w) => w !== interaction.options.getString('mot', true).toLowerCase());
    db.save();
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('🤬 Mots interdits')
      .setDescription(`Filtre : **${bw.enabled ? 'activé' : 'désactivé'}**\n\n${bw.words.length ? `||${bw.words.join(', ')}||` : 'Aucun mot.'}`.slice(0, 4000))], flags: 64 });
  },
};
