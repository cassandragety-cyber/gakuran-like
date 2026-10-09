// Branche la musique sur Discord : boutons du lecteur, départ automatique, vérifications vocales.
const { queues } = require('../music/queue');
const ui = require('../util/ui');
const { ytdlp } = require('../music/source');

// Le membre doit être dans le même vocal que le bot
function voiceCheck(interaction, { needQueue = true } = {}) {
  const q = queues.get(interaction.guild.id);
  const vc = interaction.member.voice.channel;
  if (needQueue && !q?.current) return [null, 'Aucune musique en cours.'];
  if (!vc) return [null, 'Rejoins un salon vocal d’abord.'];
  if (q && q.channelId !== vc.id) return [null, `Je suis déjà utilisé dans <#${q.channelId}>.`];
  return [q, null];
}

const ACTIONS = {
  pause: (q) => (q.paused ? q.player.unpause() : q.player.pause()),
  skip: (q) => q.skip(),
  stop: (q) => q.destroy(),
  loop: (q) => { q.loop = { off: 'queue', queue: 'track', track: 'off' }[q.loop]; },
  shuffle: (q) => q.shuffle(),
  voldown: (q) => q.setVolume(q.volume - 10),
  volup: (q) => q.setVolume(q.volume + 10),
  rewind: (q) => q.restart(q.position - 10),
  forward: (q) => q.restart(q.position + 10),
  refresh: () => {},
};

module.exports = {
  voiceCheck,
  setup(client) {
    // Prépare yt-dlp en avance pour que la première musique démarre vite
    client.on('botReady', () => ytdlp().catch((e) => console.warn('[musique]', e.message)));
    // Seul dans le vocal pendant 2 minutes → on s'en va
    client.on('voiceStateUpdate', (o) => {
      const q = queues.get(o.guild.id);
      if (!q || o.channelId !== q.channelId) return;
      const ch = o.guild.channels.cache.get(q.channelId);
      if (ch && ch.members.filter((m) => !m.user.bot).size === 0) {
        clearTimeout(q.aloneTimer);
        q.aloneTimer = setTimeout(() => {
          const still = o.guild.channels.cache.get(q.channelId);
          if (queues.get(o.guild.id) === q && still?.members.filter((m) => !m.user.bot).size === 0) {
            q.send(ui.info('👋 Plus personne dans le vocal, je m’en vais.', o.guild));
            q.destroy();
          }
        }, 2 * 60e3);
      }
    });
    client.on('voiceStateUpdate', (o, n) => {
      // Le bot a été déconnecté manuellement
      if (n.id === client.user.id && o.channelId && !n.channelId) queues.get(n.guild.id)?.destroy();
    });
  },
  components: {
    async music(interaction) {
      const [q, err] = voiceCheck(interaction);
      if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
      const action = interaction.customId.split(':')[1];
      await ACTIONS[action]?.(q);
      if (action === 'stop') return interaction.update({ embeds: [ui.info('⏹️ Musique arrêtée.', interaction.guild)], components: [] });
      if (action === 'skip') return interaction.reply({ embeds: [ui.info(`⏭️ Titre passé par ${interaction.user}.`, interaction.guild)] });
      if (!q.current) return interaction.deferUpdate();
      // Laisse le temps à la lecture de reprendre avant d'afficher la position
      if (action === 'rewind' || action === 'forward') await new Promise((r) => setTimeout(r, 300));
      await interaction.update({ embeds: [q.nowPlayingEmbed()], components: q.controls() });
    },
  },
};
