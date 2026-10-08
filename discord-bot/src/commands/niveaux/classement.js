const { SlashCommandBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { inviteStats } = require('../../modules/welcome');

const medals = ['🥇', '🥈', '🥉'];

module.exports = {
  category: 'Niveaux',
  data: new SlashCommandBuilder()
    .setName('classement')
    .setDescription('Classements du serveur')
    .addStringOption((o) => o.setName('type').setDescription('Type').addChoices({ name: 'Niveaux', value: 'level' }, { name: 'Invitations', value: 'invites' })),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const type = interaction.options.getString('type') ?? 'level';
    let rows;
    if (type === 'level') {
      rows = Object.entries(g.leveling.users).sort((a, b) => b[1].level - a[1].level || b[1].xp - a[1].xp).slice(0, 15)
        .map(([id, u], i) => `${medals[i] ?? `\`${i + 1}.\``} <@${id}> — niveau **${u.level}** (${u.xp} xp)`);
    } else {
      rows = Object.keys(g.invites).map((id) => [id, inviteStats(g, id).total]).sort((a, b) => b[1] - a[1]).slice(0, 15)
        .map(([id, n], i) => `${medals[i] ?? `\`${i + 1}.\``} <@${id}> — **${n}** invitation(s)`);
    }
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(type === 'level' ? '🏆 Classement des niveaux' : '📨 Classement des invitations').setDescription(rows.join('\n') || 'Aucune donnée.')] });
  },
};
