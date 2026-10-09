const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { GAMES, leaderboard, stats } = require('../../games/common');
const duels = require('../../games/duels');
const solo = require('../../games/solo');

// Un seul jeu de salon (pendu, rapido, nombre) à la fois par salon
const busy = new Set();

const vs = (s) => s.addUserOption((o) => o.setName('adversaire').setDescription('Membre à défier (vide = contre le bot)'));

module.exports = {
  category: 'Jeux',
  data: new SlashCommandBuilder()
    .setName('jeu')
    .setDescription('Mini-jeux')
    .addSubcommand((s) => vs(s.setName('morpion').setDescription('❌⭕ Morpion contre un membre ou le bot')))
    .addSubcommand((s) => vs(s.setName('puissance4').setDescription('🔴🟡 Puissance 4 contre un membre ou le bot')))
    .addSubcommand((s) => vs(s.setName('pfc').setDescription('🪨📄✂️ Pierre-feuille-ciseaux')))
    .addSubcommand((s) => s.setName('pendu').setDescription('🪢 Pendu : tout le salon devine le mot'))
    .addSubcommand((s) => s.setName('demineur').setDescription('💣 Démineur'))
    .addSubcommand((s) => s.setName('snake').setDescription('🐍 Snake'))
    .addSubcommand((s) => s.setName('memoire').setDescription('🧠 Retrouve les paires'))
    .addSubcommand((s) => s.setName('rapido').setDescription('⚡ Le premier qui recopie la phrase gagne'))
    .addSubcommand((s) => s.setName('nombre').setDescription('🔢 Devine le nombre mystère')
      .addIntegerOption((o) => o.setName('max').setDescription('Nombre maximum (défaut 100)').setMinValue(10).setMaxValue(10000)))
    .addSubcommand((s) => s.setName('classement').setDescription('🏆 Classement d’un jeu')
      .addStringOption((o) => o.setName('jeu').setDescription('Jeu').setRequired(true).addChoices(...Object.entries(GAMES).map(([v, g]) => ({ name: g.name, value: v })))))
    .addSubcommand((s) => s.setName('stats').setDescription('📊 Statistiques de jeu d’un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre'))),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    const opponent = interaction.options.getUser('adversaire');
    if (sub === 'classement') {
      const game = interaction.options.getString('jeu', true);
      const rows = leaderboard(interaction.guild.id, game).slice(0, 15);
      const medals = ['🥇', '🥈', '🥉'];
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`🏆 ${GAMES[game].name}`).setDescription(rows.map(([id, t], i) => `${medals[i] ?? `\`${i + 1}.\``} <@${id}> — ${t}`).join('\n') || 'Personne n’a encore joué.')] });
    }
    if (sub === 'stats') {
      const user = interaction.options.getUser('membre') ?? interaction.user;
      const lines = Object.entries(GAMES).map(([k, g]) => {
        const s = stats(interaction.guild.id, k, user.id);
        if (!s.played) return null;
        return `${g.name} — ${s.played} partie(s)${s.wins ? ` • ${s.wins} V` : ''}${s.losses ? ` • ${s.losses} D` : ''}${s.draws ? ` • ${s.draws} N` : ''}${s.best != null ? ` • record **${s.best}${g.unit}**` : ''}`;
      }).filter(Boolean);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setAuthor({ name: `Jeux de ${user.username}`, iconURL: user.displayAvatarURL() }).setDescription(lines.join('\n') || 'Aucune partie jouée.')] });
    }
    if (['pendu', 'rapido', 'nombre'].includes(sub)) {
      if (busy.has(interaction.channelId)) return interaction.reply({ embeds: [ui.error('Une partie est déjà en cours dans ce salon.')], flags: 64 });
      busy.add(interaction.channelId);
      try {
        return await solo[sub](interaction, interaction.options.getInteger('max') ?? 100);
      } finally {
        busy.delete(interaction.channelId);
      }
    }
    if (duels[sub]) return duels[sub](interaction, opponent);
    return solo[sub](interaction);
  },
};
