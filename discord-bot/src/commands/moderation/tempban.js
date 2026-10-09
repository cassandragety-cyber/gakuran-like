const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { parseDuration, ts } = require('../../util/time');
const { doBan } = require('./ban');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('tempban')
    .setDescription('Bannissement temporaire')
    .setDefaultMemberPermissions(PermissionFlagsBits.BanMembers)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Bannit temporairement un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre à bannir').setRequired(true))
      .addStringOption((o) => o.setName('duree').setDescription('Ex : 30m, 2h, 7j').setRequired(true))
      .addStringOption((o) => o.setName('raison').setDescription('Raison').setMaxLength(400)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste des tempbans actifs')),
  async run(interaction) {
    if (interaction.options.getSubcommand() === 'liste') {
      const list = db.guild(interaction.guild.id).timers.filter((t) => t.type === 'unban');
      const e = ui.embed(interaction.guild).setTitle(`${ui.E.ban} Tempbans actifs`)
        .setDescription(list.length ? list.map((t) => `${ui.E.dot} <@${t.userId}> (\`${t.userId}\`) — fin ${ts(t.at)}`).join('\n').slice(0, 4000) : 'Aucun tempban actif.');
      return interaction.reply({ embeds: [e] });
    }
    const duration = parseDuration(interaction.options.getString('duree', true));
    if (!duration) return interaction.reply({ embeds: [ui.error('Durée invalide. Exemples : `30m`, `2h`, `7j`, `1h30`.')], flags: 64 });
    await doBan(interaction, {
      user: interaction.options.getUser('membre', true),
      reason: interaction.options.getString('raison'),
      duration,
    });
  },
};
