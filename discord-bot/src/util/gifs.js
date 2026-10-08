// GIF « qui pop » dans le chat lors des sanctions.
// Ordre de priorité pour chaque action :
//   1. GIF ajoutés par le serveur via /style gif ajouter (liens Klipy, Tenor, Giphy, .gif…)
//   2. Recherche Klipy (si KLIPY_API_KEY est défini) : domain expansion, Gojo, Sukuna…
//   3. API anime sans clé (nekos.best, waifu.pics)
//   4. sinon : carte animée générée localement (gifcard.js)
const db = require('../db');

const KLIPY_KEY = process.env.KLIPY_API_KEY?.trim();

// Ambiance « full flow » Jujutsu Kaisen / anime
const QUERIES = {
  ban: ['domain expansion', 'gojo domain expansion', 'sukuna domain expansion', 'hollow purple', 'malevolent shrine', 'anime ban hammer'],
  tempban: ['domain expansion', 'gojo hollow purple', 'sukuna domain expansion'],
  kick: ['anime kick', 'sukuna punch', 'black flash', 'anime yeet', 'todo boogie woogie'],
  mute: ['gojo blindfold', 'anime shush', 'infinite void', 'be quiet anime'],
  warn: ['gojo stare', 'sukuna stare', 'anime warning', 'anime angry stare', 'gojo eyes'],
  unban: ['gojo smile', 'anime welcome back', 'yuji happy', 'anime thumbs up'],
};

// Catégories des API sans clé
const KEYLESS = {
  ban: [['nekos', 'shoot'], ['waifu', 'kill'], ['nekos', 'punch']],
  tempban: [['nekos', 'shoot'], ['waifu', 'kill']],
  kick: [['nekos', 'kick'], ['waifu', 'kick'], ['nekos', 'yeet'], ['waifu', 'yeet']],
  mute: [['nekos', 'nope'], ['waifu', 'bonk'], ['nekos', 'facepalm']],
  warn: [['nekos', 'stare'], ['nekos', 'angry'], ['nekos', 'baka'], ['waifu', 'bonk']],
  unban: [['nekos', 'happy'], ['nekos', 'thumbsup'], ['waifu', 'dance'], ['nekos', 'wave']],
};

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const cache = new Map(); // requête Klipy → { at, urls }

async function getJSON(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(5000), headers: { 'User-Agent': 'Mozilla/5.0 DiscordBot' } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

// Cherche toutes les URLs de GIF dans un objet JSON, quelle que soit sa forme
// (l'API Klipy imbrique les fichiers par taille : hd/md/sm → gif/webp/mp4).
function collectGifUrls(node, out = []) {
  if (typeof node === 'string') {
    if (/^https?:\/\/\S+\.gif(\?|$)/i.test(node)) out.push(node);
  } else if (Array.isArray(node)) node.forEach((n) => collectGifUrls(n, out));
  else if (node && typeof node === 'object') Object.values(node).forEach((n) => collectGifUrls(n, out));
  return out;
}

async function klipy(query) {
  const hit = cache.get(query);
  if (hit && Date.now() - hit.at < 3600e3) return pick(hit.urls);
  const url = `https://api.klipy.com/api/v1/${encodeURIComponent(KLIPY_KEY)}/gifs/search?q=${encodeURIComponent(query)}&per_page=24&page=1&content_filter=medium`;
  const json = await getJSON(url);
  const items = json?.data?.data ?? json?.data ?? json?.results ?? [];
  // Une URL par GIF, en préférant la taille moyenne (plus légère que la HD)
  const urls = (Array.isArray(items) ? items : []).map((item) => {
    const all = collectGifUrls(item);
    return all.find((u) => /\/md\/|medium/i.test(u)) ?? all[0];
  }).filter(Boolean);
  if (!urls.length) throw new Error('aucun résultat');
  cache.set(query, { at: Date.now(), urls });
  return pick(urls);
}

async function keyless(action) {
  const [api, cat] = pick(KEYLESS[action] ?? KEYLESS.ban);
  if (api === 'nekos') {
    const json = await getJSON(`https://nekos.best/api/v2/${cat}`);
    return json?.results?.[0]?.url;
  }
  const json = await getJSON(`https://api.waifu.pics/sfw/${cat}`);
  return json?.url;
}

/** Renvoie l'URL d'un GIF pour l'action, ou null (→ carte générée). */
async function findGif(guildId, action) {
  const style = db.guild(guildId).style;
  if (style.gifs === false || style.mode === 'carte') return null;
  const custom = style.customGifs?.[action] ?? (action === 'tempban' ? style.customGifs?.ban : undefined);
  // Si le serveur a ajouté ses propres GIF, on les utilise en priorité (et seuls si mode « perso »)
  if (custom?.length && (style.mode === 'perso' || Math.random() < 0.6)) return pick(custom);
  try {
    if (KLIPY_KEY) return await klipy(pick(QUERIES[action] ?? QUERIES.ban));
  } catch (err) {
    console.warn('[gifs] Klipy :', err.message);
  }
  try {
    const url = await keyless(action);
    if (url) return url;
  } catch (err) {
    console.warn('[gifs] API anime :', err.message);
  }
  return custom?.length ? pick(custom) : null;
}

// Transforme un lien de page (klipy.com/gifs/…, tenor.com/view/…, giphy.com/gifs/…) en lien direct vers le GIF.
async function resolveGifLink(link) {
  const url = new URL(link);
  if (/\.(gif|webp)$/i.test(url.pathname)) return url.href;
  const res = await fetch(url, { signal: AbortSignal.timeout(8000), headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } });
  if (!res.ok) throw new Error(`la page a répondu ${res.status}`);
  const html = await res.text();
  const metas = [...html.matchAll(/<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image|og:image:url)["'][^>]+content=["']([^"']+)["']/gi)].map((m) => m[1]);
  const metasRev = [...html.matchAll(/<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["'](?:og:image|twitter:image)["']/gi)].map((m) => m[1]);
  const inline = html.match(/https?:\/\/[^"'\s<>]+\.gif/gi) ?? [];
  const found = [...metas, ...metasRev, ...inline].map((u) => u.replace(/&amp;/g, '&')).find((u) => /\.gif(\?|$)/i.test(u));
  if (!found) throw new Error('aucun GIF trouvé sur cette page');
  return found;
}

module.exports = { findGif, resolveGifLink, QUERIES };
