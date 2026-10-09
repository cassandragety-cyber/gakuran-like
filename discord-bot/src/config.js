const path = require('node:path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

function parseColor(hex, fallback) {
  const n = parseInt(String(hex || '').replace('#', ''), 16);
  return Number.isFinite(n) ? n : fallback;
}

const config = {
  token: process.env.TOKEN?.trim(),
  ownerIds: (process.env.OWNER_IDS || '').split(',').map((s) => s.trim()).filter(Boolean),
  botName: process.env.BOT_NAME?.trim() || 'Gakuran',
  color: parseColor(process.env.EMBED_COLOR, 0x8b5cf6),
  ytCookies: process.env.YT_COOKIES?.trim() || null,
  dataDir: path.join(__dirname, '..', 'data'),
};

module.exports = config;
