// Cartes PNG : bienvenue et niveau.
const { createCanvas, loadImage } = require('@napi-rs/canvas');

const FONT = '"Segoe UI", "Inter", "Liberation Sans", "DejaVu Sans", Arial, sans-serif';

async function avatarImage(url) {
  try {
    const res = await fetch(url);
    return await loadImage(Buffer.from(await res.arrayBuffer()));
  } catch {
    return null;
  }
}

function hex(color) {
  return `#${color.toString(16).padStart(6, '0')}`;
}

function circleAvatar(ctx, img, x, y, r, ring) {
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, r + 6, 0, Math.PI * 2);
  ctx.fillStyle = ring;
  ctx.shadowColor = ring;
  ctx.shadowBlur = 25;
  ctx.fill();
  ctx.restore();
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.clip();
  if (img) ctx.drawImage(img, x - r, y - r, r * 2, r * 2);
  else {
    ctx.fillStyle = '#27272a';
    ctx.fillRect(x - r, y - r, r * 2, r * 2);
  }
  ctx.restore();
}

function fit(ctx, text, max) {
  if (ctx.measureText(text).width <= max) return text;
  while (text.length > 1 && ctx.measureText(`${text}…`).width > max) text = text.slice(0, -1);
  return `${text}…`;
}

async function welcomeCard({ avatarURL, username, guildName, memberCount, color, title = 'BIENVENUE' }) {
  const W = 900;
  const H = 300;
  const accent = hex(color);
  const c = createCanvas(W, H);
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, '#09090b');
  g.addColorStop(1, '#1e1b2e');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  // halos
  for (const [x, y, r] of [[780, 40, 180], [120, 300, 160]]) {
    const rg = ctx.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, `${accent}55`);
    rg.addColorStop(1, `${accent}00`);
    ctx.fillStyle = rg;
    ctx.fillRect(0, 0, W, H);
  }
  ctx.fillStyle = accent;
  ctx.fillRect(0, H - 8, W, 8);
  circleAvatar(ctx, await avatarImage(avatarURL), 160, 150, 95, accent);
  ctx.fillStyle = accent;
  ctx.font = `900 54px ${FONT}`;
  ctx.fillText(title, 300, 115);
  ctx.fillStyle = '#ffffff';
  ctx.font = `bold 38px ${FONT}`;
  ctx.fillText(fit(ctx, username, 560), 300, 168);
  ctx.fillStyle = '#a1a1aa';
  ctx.font = `24px ${FONT}`;
  ctx.fillText(fit(ctx, `sur ${guildName} • membre n°${memberCount}`, 560), 300, 215);
  return c.toBuffer('image/png');
}

async function rankCard({ avatarURL, username, level, xp, needed, rank, color }) {
  const W = 900;
  const H = 260;
  const accent = hex(color);
  const c = createCanvas(W, H);
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, '#0b0b12');
  g.addColorStop(1, '#18142a');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  circleAvatar(ctx, await avatarImage(avatarURL), 130, 130, 85, accent);
  ctx.fillStyle = '#ffffff';
  ctx.font = `bold 36px ${FONT}`;
  ctx.fillText(fit(ctx, username, 380), 250, 100);
  ctx.textAlign = 'right';
  ctx.fillStyle = '#a1a1aa';
  ctx.font = `24px ${FONT}`;
  ctx.fillText('RANG', 700, 60);
  ctx.fillText('NIVEAU', 820, 60);
  ctx.fillStyle = '#ffffff';
  ctx.font = `bold 44px ${FONT}`;
  ctx.fillText(`#${rank}`, 700, 105);
  ctx.fillStyle = accent;
  ctx.fillText(String(level), 860, 105);
  ctx.textAlign = 'left';
  // barre d'xp
  const x = 250;
  const y = 150;
  const w = 610;
  const h = 34;
  ctx.fillStyle = '#27272a';
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, h / 2);
  ctx.fill();
  const pct = Math.max(0.04, Math.min(1, xp / needed));
  const bar = ctx.createLinearGradient(x, 0, x + w, 0);
  bar.addColorStop(0, accent);
  bar.addColorStop(1, '#f0abfc');
  ctx.fillStyle = bar;
  ctx.beginPath();
  ctx.roundRect(x, y, w * pct, h, h / 2);
  ctx.fill();
  ctx.fillStyle = '#d4d4d8';
  ctx.font = `22px ${FONT}`;
  ctx.textAlign = 'right';
  ctx.fillText(`${xp.toLocaleString('fr-FR')} / ${needed.toLocaleString('fr-FR')} XP`, x + w, y + 70);
  return c.toBuffer('image/png');
}

module.exports = { welcomeCard, rankCard };
