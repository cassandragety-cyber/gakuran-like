// File d'attente musicale d'un serveur : connexion vocale, lecteur, lecture en boucle, panneau de contrôle.
const {
  joinVoiceChannel, createAudioPlayer, createAudioResource, AudioPlayerStatus, StreamType,
  VoiceConnectionStatus, entersState, NoSubscriberBehavior,
} = require('@discordjs/voice');
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, EmbedBuilder } = require('discord.js');
const { stream, FILTERS } = require('./source');
const ui = require('../util/ui');
const { clock } = require('../util/time');

const queues = new Map();
const LOOP_LABEL = { off: 'désactivée', track: '🔂 titre', queue: '🔁 file' };

class GuildQueue {
  constructor(guild, voiceChannel, textChannel) {
    this.guild = guild;
    this.textChannel = textChannel;
    this.tracks = [];
    this.current = null;
    this.loop = 'off';
    this.volume = 80;
    this.filter = 'off';
    this.seekBase = 0;
    this.nowMessage = null;
    this.proc = null;
    this.idleTimer = null;
    this.restarting = false;

    this.connection = joinVoiceChannel({ channelId: voiceChannel.id, guildId: guild.id, adapterCreator: guild.voiceAdapterCreator, selfDeaf: true });
    this.player = createAudioPlayer({ behaviors: { noSubscriber: NoSubscriberBehavior.Pause } });
    this.connection.subscribe(this.player);

    this.player.on(AudioPlayerStatus.Idle, () => {
      if (this.restarting) return;
      this.next().catch((e) => console.error('[musique]', e));
    });
    this.player.on('error', (err) => {
      console.warn('[musique] erreur de lecture :', err.message);
      this.send(ui.error(`Lecture impossible de **${ui.truncate(this.current?.title, 80)}** : ${ui.truncate(this.proc?.errors().split('\n').find((l) => l.includes('ERROR')) || err.message, 200)}`));
    });
    this.connection.on(VoiceConnectionStatus.Disconnected, async () => {
      try {
        // Déplacé dans un autre salon : Discord reconnecte tout seul
        await Promise.race([entersState(this.connection, VoiceConnectionStatus.Signalling, 5e3), entersState(this.connection, VoiceConnectionStatus.Connecting, 5e3)]);
      } catch {
        this.destroy();
      }
    });
    queues.set(guild.id, this);
  }

  get channelId() {
    return this.connection.joinConfig.channelId;
  }

  get position() {
    const res = this.player.state.resource;
    return this.seekBase + (res ? res.playbackDuration / 1000 : 0);
  }

  get paused() {
    return this.player.state.status === AudioPlayerStatus.Paused;
  }

  async send(embed, components) {
    return this.textChannel.send({ embeds: [embed], components }).catch(() => null);
  }

  add(tracks, { next = false } = {}) {
    if (next) this.tracks.unshift(...tracks);
    else this.tracks.push(...tracks);
    clearTimeout(this.idleTimer);
    if (!this.current) return this.next(true);
  }

  async next(fresh = false) {
    if (!fresh && this.current) {
      if (this.loop === 'track') this.tracks.unshift(this.current);
      else if (this.loop === 'queue') this.tracks.push(this.current);
    }
    this.proc?.kill();
    this.current = this.tracks.shift() ?? null;
    await this.nowMessage?.edit({ components: [] }).catch(() => {});
    this.nowMessage = null;
    if (!this.current) {
      // File vide : on part au bout de 3 minutes sans nouvelle musique
      this.idleTimer = setTimeout(() => this.destroy(), 3 * 60e3);
      await this.send(ui.info(`${ui.E.music} File d’attente terminée. Ajoute des titres avec \`/play\` !`, this.guild));
      return;
    }
    this.start(0);
    this.nowMessage = await this.send(this.nowPlayingEmbed(), this.controls());
  }

  start(seek) {
    this.proc?.kill();
    this.seekBase = seek;
    this.proc = stream(this.current, { seek, filter: this.filter });
    const proc = this.proc;
    const track = this.current;
    proc.process.on('close', (code) => {
      // code > 0 : yt-dlp a vraiment échoué (un arrêt volontaire donne code null)
      if (code > 0 && this.proc === proc) {
        const line = proc.errors().split('\n').find((l) => l.includes('ERROR'))?.replace(/^ERROR:\s*/, '') ?? `code ${code}`;
        this.send(ui.error(`Impossible de lire **${ui.truncate(track.title, 80)}** : ${ui.truncate(line, 300)}`));
      }
    });
    const resource = createAudioResource(this.proc.stream, { inputType: StreamType.Raw, inlineVolume: true });
    resource.volume.setVolume(this.volume / 100);
    this.restarting = true;
    this.player.play(resource);
    this.restarting = false;
  }

  // Relance le titre en cours à une position donnée (seek, changement de filtre)
  restart(seek = this.position) {
    if (!this.current) return;
    this.start(Math.max(0, seek));
  }

  setVolume(v) {
    this.volume = Math.max(0, Math.min(200, v));
    this.player.state.resource?.volume?.setVolume(this.volume / 100);
  }

  shuffle() {
    for (let i = this.tracks.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [this.tracks[i], this.tracks[j]] = [this.tracks[j], this.tracks[i]];
    }
  }

  skip() {
    this.player.stop(true);
  }

  destroy() {
    clearTimeout(this.idleTimer);
    this.tracks = [];
    this.loop = 'off';
    this.proc?.kill();
    this.nowMessage?.edit({ components: [] }).catch(() => {});
    this.player.removeAllListeners();
    this.player.stop(true);
    if (this.connection.state.status !== VoiceConnectionStatus.Destroyed) this.connection.destroy();
    queues.delete(this.guild.id);
  }

  nowPlayingEmbed() {
    const t = this.current;
    const e = new EmbedBuilder()
      .setColor(ui.colorFor(this.guild))
      .setAuthor({ name: this.paused ? '⏸️ En pause' : '🎶 Lecture en cours' })
      .setTitle(ui.truncate(t.title, 250))
      .setURL(t.url)
      .setDescription([
        `${clock(this.position)} ${ui.progressBar(this.position, t.duration)} ${t.live ? '🔴 LIVE' : clock(t.duration)}`,
        '',
        `👤 **Artiste :** ${t.author ?? 'inconnu'}`,
        `🙋 **Demandé par :** ${t.requester ?? 'inconnu'}`,
        `🔊 **Volume :** ${this.volume}% • 🔁 **Boucle :** ${LOOP_LABEL[this.loop]} • 🎛️ **Filtre :** ${FILTERS[this.filter].label}`,
        this.tracks.length ? `📜 **À suivre :** ${ui.truncate(this.tracks[0].title, 80)} *(+${this.tracks.length - 1})*` : null,
      ].filter((l) => l !== null).join('\n'));
    if (t.thumbnail) e.setThumbnail(t.thumbnail);
    return e;
  }

  controls() {
    return [
      new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId('music:pause').setEmoji(this.paused ? '▶️' : '⏸️').setStyle(ButtonStyle.Primary),
        new ButtonBuilder().setCustomId('music:skip').setEmoji('⏭️').setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId('music:stop').setEmoji('⏹️').setStyle(ButtonStyle.Danger),
        new ButtonBuilder().setCustomId('music:loop').setEmoji(this.loop === 'track' ? '🔂' : '🔁').setStyle(this.loop === 'off' ? ButtonStyle.Secondary : ButtonStyle.Success),
        new ButtonBuilder().setCustomId('music:shuffle').setEmoji('🔀').setStyle(ButtonStyle.Secondary),
      ),
      new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId('music:voldown').setEmoji('🔉').setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId('music:volup').setEmoji('🔊').setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId('music:rewind').setEmoji('⏪').setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId('music:forward').setEmoji('⏩').setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId('music:refresh').setEmoji('🔄').setStyle(ButtonStyle.Secondary),
      ),
    ];
  }
}

module.exports = { GuildQueue, queues, LOOP_LABEL };
