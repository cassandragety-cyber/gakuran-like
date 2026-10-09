// Télécharge (ou met à jour) le binaire autonome de yt-dlp dans ./bin.
// yt-dlp sert à lire YouTube, SoundCloud, etc. pour la musique.
const fs = require('node:fs');
const path = require('node:path');

const BIN_DIR = path.join(__dirname, '..', 'bin');
const MAX_AGE_MS = 3 * 24 * 60 * 60 * 1000; // YouTube change souvent : on rafraîchit tous les 3 jours

function assetName() {
  const { platform, arch } = process;
  if (platform === 'win32') return arch === 'ia32' ? 'yt-dlp_x86.exe' : 'yt-dlp.exe';
  if (platform === 'darwin') return 'yt-dlp_macos';
  if (platform === 'linux') return arch === 'arm64' ? 'yt-dlp_linux_aarch64' : arch === 'arm' ? 'yt-dlp_linux_armv7l' : 'yt-dlp_linux';
  return null;
}

function binaryPath() {
  return path.join(BIN_DIR, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp');
}

async function ensureYtDlp({ force = false, quiet = false } = {}) {
  const target = binaryPath();
  const log = (...a) => !quiet && console.log('[yt-dlp]', ...a);
  if (!force && fs.existsSync(target)) {
    const age = Date.now() - fs.statSync(target).mtimeMs;
    if (age < MAX_AGE_MS) return target;
    log('binaire vieux de plus de 3 jours, mise à jour…');
  }
  const asset = assetName();
  if (!asset) throw new Error(`plateforme non supportée : ${process.platform}/${process.arch}`);
  const url = `https://github.com/yt-dlp/yt-dlp/releases/latest/download/${asset}`;
  log('téléchargement de', url);
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`téléchargement impossible (HTTP ${res.status})`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.mkdirSync(BIN_DIR, { recursive: true });
  const tmp = `${target}.part`;
  fs.writeFileSync(tmp, buf);
  fs.chmodSync(tmp, 0o755);
  fs.renameSync(tmp, target);
  log(`installé (${(buf.length / 1e6).toFixed(1)} Mo) →`, target);
  return target;
}

module.exports = { ensureYtDlp, binaryPath };

if (require.main === module) {
  ensureYtDlp({ force: process.argv.includes('--force') }).catch((err) => {
    // Pas bloquant : le bot retentera au démarrage.
    console.warn('[yt-dlp] échec :', err.message, '— nouvel essai au démarrage du bot.');
  });
}
