const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { voiceCheck } = require('../../modules/music');
const { paginate, chunk } = require('../../util/paginate');
const { clock } = require('../../util/time');

module.exports = {
  category: 'Musique',
  data: new SlashCommandBuilder().setName('queue').setDescription('Affiche la file d’attente'),
  async run(interaction) {
    const [q, err] = voiceCheck(interaction);
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    const pages = chunk(q.tracks, 10);
    const total = q.tracks.reduce((a, t) => a + (t.duration ?? 0), 0);
    await paginate(interaction, Math.max(1, pages.length), (p) => ui.embed(interaction.guild)
      .setTitle(`📜 File d’attente — ${q.tracks.length} titre(s) • ${clock(total)}`)
      .setDescription(`**En cours :** [${ui.truncate(q.current.title, 80)}](${q.current.url})\n\n${pages[p]?.map((t, i) => `\`${p * 10 + i + 1}.\` [${ui.truncate(t.title, 60)}](${t.url}) — ${clock(t.duration)} • ${t.requester}`).join('\n') ?? '*La file est vide.*'}`));
  },
};
