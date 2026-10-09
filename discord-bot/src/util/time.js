// Durées en français : « 10m », « 1h30 », « 2j », « 1sem »…
const UNITS = {
  s: 1e3, sec: 1e3, seconde: 1e3, secondes: 1e3,
  m: 60e3, min: 60e3, minute: 60e3, minutes: 60e3,
  h: 3600e3, heure: 3600e3, heures: 3600e3,
  j: 86400e3, d: 86400e3, jour: 86400e3, jours: 86400e3,
  sem: 604800e3, w: 604800e3, semaine: 604800e3, semaines: 604800e3,
  mois: 2592000e3, mo: 2592000e3,
  a: 31536000e3, y: 31536000e3, an: 31536000e3, ans: 31536000e3,
};

function parseDuration(input) {
  if (!input) return null;
  const str = String(input).toLowerCase().replace(/\s+/g, '');
  const re = /(\d+(?:[.,]\d+)?)([a-zé]*)/g;
  let total = 0;
  let matched = '';
  let m;
  while ((m = re.exec(str))) {
    if (!m[0]) break;
    matched += m[0];
    const n = parseFloat(m[1].replace(',', '.'));
    // Un nombre sans unité compte en minutes (« 10 », ou le « 30 » de « 1h30 »)
    const unit = m[2] || 'm';
    if (!(unit in UNITS)) return null;
    total += n * UNITS[unit];
  }
  if (matched !== str || total <= 0) return null;
  return Math.round(total);
}

function formatDuration(ms) {
  if (ms == null) return 'définitive';
  const parts = [];
  const add = (v, s, p) => v && parts.push(`${v} ${v > 1 ? p : s}`);
  let rest = Math.round(ms / 1000);
  const j = Math.floor(rest / 86400); rest %= 86400;
  const h = Math.floor(rest / 3600); rest %= 3600;
  const m = Math.floor(rest / 60); const s = rest % 60;
  add(j, 'jour', 'jours'); add(h, 'heure', 'heures'); add(m, 'minute', 'minutes'); add(s, 'seconde', 'secondes');
  return parts.slice(0, 2).join(' ') || '0 seconde';
}

// 3:07 / 1:02:44
function clock(sec) {
  if (!Number.isFinite(sec)) return '∞';
  sec = Math.floor(sec);
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = String(sec % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

const ts = (date, style = 'R') => `<t:${Math.floor(new Date(date).getTime() / 1000)}:${style}>`;

module.exports = { parseDuration, formatDuration, clock, ts };
