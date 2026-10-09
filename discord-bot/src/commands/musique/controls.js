// Commandes simples du lecteur : skip, stop, pause, nowplaying, volume, loop, shuffle, remove, seek, filtre.
const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { voiceCheck } = require('../../modules/music');
const { FILTERS } = require('../../music/source');
const { LOOP_LABEL } = require('../../music/queue');
const { parseDuration, clock } = require('../../util/time');

function cmd(builder, run) {
  return {
    category: 'Musique',
    data: builder,
    async run(interaction) {
      const [q, err] = voiceCheck(interaction);
      if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
      const out = await run(q, interaction);
      if (out) await interaction.reply(out.data ? { embeds: [out] } : out);
    },
  };
}

const b = (name, desc) => new SlashCommandBuilder().setName(name).setDescription(desc);
const say = (text, g) => ui.info(text, g);

module.exports = [
  cmd(b('skip', 'Passe au titre suivant').addIntegerOption((o) => o.setName('jusqua').setDescription('Sauter directement à la position N de la file').setMinValue(1)), (q, i) => {
    const to = i.options.getInteger('jusqua');
    if (to) q.tracks.splice(0, Math.min(to - 1, q.tracks.length));
    q.skip();
    return say(`⏭️ ${to ? `Saut à la position ${to}` : 'Titre passé'}.`, i.guild);
  }),
  cmd(b('stop', 'Arrête la musique et quitte le vocal'), (q, i) => { q.destroy(); return say('⏹️ Musique arrêtée, à plus !', i.guild); }),
  cmd(b('pause', 'Met en pause / reprend la musique'), (q, i) => {
    if (q.paused) q.player.unpause();
    else q.player.pause();
    return say(q.paused ? '⏸️ En pause.' : '▶️ Reprise.', i.guild);
  }),
  cmd(b('nowplaying', 'Affiche le titre en cours'), (q) => ({ embeds: [q.nowPlayingEmbed()], components: q.controls() })),
  cmd(b('volume', 'Change le volume').addIntegerOption((o) => o.setName('valeur').setDescription('0 à 200').setRequired(true).setMinValue(0).setMaxValue(200)), (q, i) => {
    q.setVolume(i.options.getInteger('valeur', true));
    return say(`🔊 Volume : **${q.volume}%**`, i.guild);
  }),
  cmd(b('loop', 'Répétition').addStringOption((o) => o.setName('mode').setDescription('Mode').setRequired(true).addChoices({ name: 'Désactivée', value: 'off' }, { name: 'Titre', value: 'track' }, { name: 'File entière', value: 'queue' })), (q, i) => {
    q.loop = i.options.getString('mode', true);
    return say(`🔁 Boucle : **${LOOP_LABEL[q.loop]}**`, i.guild);
  }),
  cmd(b('shuffle', 'Mélange la file d’attente'), (q, i) => { q.shuffle(); return say(`🔀 ${q.tracks.length} titres mélangés.`, i.guild); }),
  cmd(b('remove', 'Retire un titre de la file').addIntegerOption((o) => o.setName('position').setDescription('Position dans la file').setRequired(true).setMinValue(1)), (q, i) => {
    const [t] = q.tracks.splice(i.options.getInteger('position', true) - 1, 1);
    return t ? say(`🗑️ **${ui.truncate(t.title, 80)}** retiré.`, i.guild) : ui.error('Position invalide.');
  }),
  cmd(b('seek', 'Avance ou recule dans le titre').addStringOption((o) => o.setName('position').setDescription('Ex : 1:30, 90s, 2m').setRequired(true)), (q, i) => {
    const raw = i.options.getString('position', true);
    const m = raw.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/);
    const sec = m ? (m[3] ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) : Number(m[1]) * 60 + Number(m[2])) : (parseDuration(/^\d+$/.test(raw) ? `${raw}s` : raw) ?? NaN) / 1000;
    if (!Number.isFinite(sec) || (q.current.duration && sec >= q.current.duration)) return ui.error('Position invalide.');
    q.restart(sec);
    return say(`⏩ Position : **${clock(sec)}**`, i.guild);
  }),
  cmd(b('filtre', 'Applique un effet audio').addStringOption((o) => o.setName('effet').setDescription('Effet').setRequired(true).addChoices(...Object.entries(FILTERS).map(([v, f]) => ({ name: f.label, value: v })))), (q, i) => {
    q.filter = i.options.getString('effet', true);
    q.restart();
    return say(`🎛️ Filtre : **${FILTERS[q.filter].label}**`, i.guild);
  }),
];
