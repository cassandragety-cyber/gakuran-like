// Recherche et lecture audio via yt-dlp (YouTube, SoundCloud, Bandcamp, Twitch, liens directs…) + ffmpeg.
const { spawn } = require('node:child_process');
const config = require('../config');
const { ensureYtDlp, binaryPath } = require('../../scripts/ytdlp');

// ffmpeg-static télécharge ffmpeg à l'installation ; sinon on utilise celui du système
let ffmpegPath = 'ffmpeg';
try {
  const p = require('ffmpeg-static');
  if (p && require('node:fs').existsSync(p)) ffmpegPath = p;
} catch {}

function baseArgs() {
  const args = ['--no-warnings', '--no-check-certificates', '--js-runtimes', `node:${process.execPath}`];
  if (config.ytCookies) args.push('--cookies', config.ytCookies);
  return args;
}

let ready = null;
function ytdlp() {
  ready ??= ensureYtDlp({ quiet: true }).catch((err) => {
    ready = null;
    throw new Error(`yt-dlp indisponible : ${err.message}`);
  });
  return ready;
}

function run(args, timeout = 30e3) {
  return new Promise((resolve, reject) => {
    const p = spawn(binaryPath(), [...baseArgs(), ...args], { windowsHide: true });
    let out = '';
    let err = '';
    const timer = setTimeout(() => { p.kill(); reject(new Error('délai dépassé')); }, timeout);
    p.stdout.on('data', (d) => (out += d));
    p.stderr.on('data', (d) => (err += d));
    p.on('error', (e) => { clearTimeout(timer); reject(e); });
    p.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(out);
      else reject(new Error(err.trim().split('\n').filter((l) => l.startsWith('ERROR')).pop()?.replace(/^ERROR:\s*/, '') || `yt-dlp a échoué (code ${code})`));
    });
  });
}

function toTrack(e, requester) {
  const id = e.id;
  const url = e.webpage_url || (e.url?.startsWith('http') ? e.url : null) || (id ? `https://www.youtube.com/watch?v=${id}` : null);
  return {
    title: e.title || 'Titre inconnu',
    url,
    duration: Number.isFinite(e.duration) ? e.duration : null,
    author: e.uploader || e.channel || e.artist || null,
    thumbnail: e.thumbnail || e.thumbnails?.at(-1)?.url || (e.ie_key === 'Youtube' || /youtu/.test(url ?? '') ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : null),
    live: !!e.is_live || e.live_status === 'is_live',
    requester,
  };
}

// Spotify n'est pas lisible directement : on récupère le titre et l'artiste puis on cherche sur YouTube
async function spotifyQuery(url) {
  const html = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: AbortSignal.timeout(8000) }).then((r) => r.text());
  const title = html.match(/<meta property="og:title" content="([^"]+)"/)?.[1];
  const desc = html.match(/<meta property="og:description" content="([^"]+)"/)?.[1];
  if (!title) throw new Error('lien Spotify illisible');
  const artist = desc?.split('·')[0]?.trim();
  return `${title} ${artist ?? ''}`.trim();
}

/** @returns {Promise<{ tracks: object[], playlist?: string }>} */
async function resolve(query, requester, { results = 1 } = {}) {
  await ytdlp();
  query = query.trim();
  if (/open\.spotify\.com\/(intl-\w+\/)?track\//.test(query)) query = await spotifyQuery(query);
  else if (/open\.spotify\.com\/(playlist|album)/.test(query)) throw new Error('les playlists Spotify ne sont pas supportées : utilise une playlist YouTube ou SoundCloud');
  const isUrl = /^https?:\/\//.test(query);
  const target = isUrl ? query : `ytsearch${results}:${query}`;
  const json = JSON.parse(await run(['-J', '--flat-playlist', '--playlist-end', '300', target]));
  if (json._type === 'playlist') {
    const tracks = (json.entries ?? []).filter(Boolean).map((e) => toTrack(e, requester)).filter((t) => t.url);
    if (!tracks.length) throw new Error('aucun résultat');
    return { tracks, playlist: isUrl ? json.title : null };
  }
  return { tracks: [toTrack(json, requester)] };
}

const FILTERS = {
  off: { label: 'Aucun', af: null },
  bassboost: { label: '🔊 Bass boost', af: 'bass=g=12,dynaudnorm=f=200' },
  nightcore: { label: '🌸 Nightcore', af: 'asetrate=48000*1.25,aresample=48000' },
  vaporwave: { label: '🌊 Vaporwave', af: 'asetrate=48000*0.8,aresample=48000' },
  '8d': { label: '🎧 8D', af: 'apulsator=hz=0.08' },
  speed: { label: '⏩ Vitesse x1.25', af: 'atempo=1.25' },
  slowed: { label: '🐢 Slowed + reverb', af: 'atempo=0.85,aecho=0.8:0.88:60:0.4' },
  treble: { label: '✨ Aigus', af: 'treble=g=6' },
};

/** Lance la lecture : yt-dlp télécharge le flux, ffmpeg le convertit en PCM 48 kHz stéréo. */
function stream(track, { seek = 0, filter = 'off' } = {}) {
  const dl = spawn(binaryPath(), [...baseArgs(), '-f', 'bestaudio[acodec=opus]/bestaudio/best', '--no-playlist', '-q', '-o', '-', track.url], { windowsHide: true });
  const af = FILTERS[filter]?.af;
  const ff = spawn(ffmpegPath, [
    '-hide_banner', '-loglevel', 'error', '-i', 'pipe:0',
    ...(seek > 0 ? ['-ss', String(seek)] : []),
    ...(af ? ['-af', af] : []),
    '-f', 's16le', '-ar', '48000', '-ac', '2', 'pipe:1',
  ], { windowsHide: true });
  let errText = '';
  dl.stderr.on('data', (d) => (errText += d));
  dl.stdout.pipe(ff.stdin);
  // Erreurs de « tuyau cassé » quand on passe à la suite : normales
  ff.stdin.on('error', () => {});
  dl.stdout.on('error', () => {});
  ff.stdout.on('error', () => {});
  dl.on('error', (e) => (errText += `ERROR: yt-dlp introuvable (${e.message})\n`));
  ff.on('error', (e) => (errText += `ERROR: ffmpeg introuvable (${e.message}) — relance « npm install »\n`));
  ff.stderr.on('data', (d) => (errText += `ffmpeg: ${d}`));
  const kill = () => {
    dl.kill('SIGKILL');
    ff.kill('SIGKILL');
  };
  return { stream: ff.stdout, kill, process: dl, errors: () => errText };
}

module.exports = { resolve, stream, FILTERS, ytdlp };
