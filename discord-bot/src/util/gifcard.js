// Générateur de GIF animés pour les sanctions (ban, kick, mute, warn, unban).
// Tout est dessiné image par image avec @napi-rs/canvas puis encodé avec gifenc :
// aucune dépendance à un site externe, et l'avatar de la cible est dans l'animation.
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const { GIFEncoder, quantize, applyPalette } = require('gifenc');

const W = 560;
const H = 220;
const FONT = '"Segoe UI", "Inter", "Liberation Sans", "DejaVu Sans", Arial, sans-serif';

const THEMES = {
  ban: { accent: '#ef4444', dark: '#2a0a0e', stamp: 'BANNI', frames: 34 },
  kick: { accent: '#f97316', dark: '#2a1406', stamp: 'EXPULSÉ', frames: 32 },
  mute: { accent: '#818cf8', dark: '#12122e', stamp: 'MUET', frames: 32 },
  warn: { accent: '#facc15', dark: '#2a2306', stamp: 'AVERTI', frames: 30 },
  unban: { accent: '#34d399', dark: '#06261c', stamp: 'DÉBANNI', frames: 32 },
};

// ─── Petits outils ────────────────────────────────────────────
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const easeIn = (t) => t * t * t;
const easeOut = (t) => 1 - (1 - t) ** 3;
const easeOutBack = (t) => 1 + 2.7 * (t - 1) ** 3 + 1.7 * (t - 1) ** 2;
const phase = (f, start, end) => clamp((f - start) / (end - start));

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}

async function fetchAvatar(url) {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(String(res.status));
    return await loadImage(Buffer.from(await res.arrayBuffer()));
  } catch {
    return null;
  }
}

// Avatar découpé en cercle (version couleur + version grise), réutilisé à chaque image.
function prepareAvatar(img, size, fallbackLetter, accent) {
  const make = (gray) => {
    const c = createCanvas(size, size);
    const x = c.getContext('2d');
    x.beginPath();
    x.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
    x.clip();
    if (img) x.drawImage(img, 0, 0, size, size);
    else {
      x.fillStyle = accent;
      x.fillRect(0, 0, size, size);
      x.fillStyle = '#fff';
      x.font = `bold ${size * 0.5}px ${FONT}`;
      x.textAlign = 'center';
      x.textBaseline = 'middle';
      x.fillText(fallbackLetter, size / 2, size / 2 + 4);
    }
    if (gray) {
      const d = x.getImageData(0, 0, size, size);
      for (let i = 0; i < d.data.length; i += 4) {
        const l = d.data[i] * 0.3 + d.data[i + 1] * 0.59 + d.data[i + 2] * 0.11;
        d.data[i] = d.data[i + 1] = d.data[i + 2] = l * 0.8;
      }
      x.putImageData(d, 0, 0);
    }
    return c;
  };
  return { color: make(false), gray: make(true) };
}

function background(ctx, theme, f) {
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, '#0b0b12');
  g.addColorStop(1, theme.dark);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  // Rayures diagonales qui défilent doucement
  ctx.save();
  ctx.globalAlpha = 0.06;
  ctx.strokeStyle = theme.accent;
  ctx.lineWidth = 10;
  const off = (f * 3) % 40;
  for (let x = -H + off; x < W + H; x += 40) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x - H, H);
    ctx.stroke();
  }
  ctx.restore();
  // Liseré lumineux
  ctx.fillStyle = theme.accent;
  ctx.fillRect(0, 0, 6, H);
}

function drawAvatar(ctx, av, { x, y, r, rot = 0, scale = 1, gray = 0, alpha = 1, ring }) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(x, y);
  ctx.rotate(rot);
  ctx.scale(scale, scale);
  ctx.drawImage(av.color, -r, -r, r * 2, r * 2);
  if (gray > 0) {
    ctx.globalAlpha = alpha * gray;
    ctx.drawImage(av.gray, -r, -r, r * 2, r * 2);
    ctx.globalAlpha = alpha;
  }
  if (ring) {
    ctx.beginPath();
    ctx.arc(0, 0, r + 4, 0, Math.PI * 2);
    ctx.lineWidth = 5;
    ctx.strokeStyle = ring;
    ctx.stroke();
  }
  ctx.restore();
}

function fitText(ctx, text, maxWidth) {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let t = text;
  while (t.length > 1 && ctx.measureText(`${t}…`).width > maxWidth) t = t.slice(0, -1);
  return `${t}…`;
}

function drawInfo(ctx, theme, info, t) {
  if (t <= 0) return;
  const x = lerp(W + 40, 222, easeOut(t));
  ctx.save();
  ctx.globalAlpha = clamp(t * 1.5);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = '#ffffff';
  ctx.font = `bold 27px ${FONT}`;
  ctx.fillText(fitText(ctx, info.username, W - 240), x, 138);
  ctx.fillStyle = '#a1a1aa';
  ctx.font = `17px ${FONT}`;
  ctx.fillText(fitText(ctx, `par ${info.moderator}${info.duration ? `  •  ${info.duration}` : ''}`, W - 240), x, 164);
  if (info.reason) {
    ctx.fillStyle = theme.accent;
    ctx.font = `italic 16px ${FONT}`;
    ctx.fillText(fitText(ctx, `« ${info.reason} »`, W - 240), x, 192);
  }
  ctx.restore();
}

// Tampon façon « cachet » qui s'écrase sur la carte
function drawStamp(ctx, theme, t) {
  if (t <= 0) return;
  const s = lerp(2.6, 1, easeOutBack(clamp(t)));
  ctx.save();
  ctx.globalAlpha = clamp(t * 2.5);
  ctx.translate(340, 70);
  ctx.rotate(-0.09);
  ctx.scale(s, s);
  ctx.font = `900 50px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const w = ctx.measureText(theme.stamp).width + 36;
  ctx.lineWidth = 5;
  ctx.strokeStyle = theme.accent;
  ctx.shadowColor = theme.accent;
  ctx.shadowBlur = 18;
  roundRect(ctx, -w / 2, -34, w, 68, 12);
  ctx.stroke();
  ctx.fillStyle = theme.accent;
  ctx.fillText(theme.stamp, 0, 3);
  ctx.restore();
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function particles(ctx, seed, cx, cy, t, color, count = 26, dist = 150) {
  if (t <= 0 || t >= 1) return;
  const rand = rng(seed);
  ctx.save();
  for (let i = 0; i < count; i++) {
    const a = rand() * Math.PI * 2;
    const sp = 0.4 + rand() * 0.6;
    const d = easeOut(t) * dist * sp;
    const size = (1 - t) * (3 + rand() * 5);
    ctx.globalAlpha = 1 - t;
    ctx.fillStyle = rand() > 0.3 ? color : '#ffffff';
    ctx.beginPath();
    ctx.arc(cx + Math.cos(a) * d, cy + Math.sin(a) * d, size, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function flash(ctx, t, color = '#ffffff') {
  if (t <= 0 || t >= 1) return;
  ctx.save();
  ctx.globalAlpha = (1 - t) * 0.75;
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, W, H);
  ctx.restore();
}

// ─── Accessoires dessinés ─────────────────────────────────────
function drawHammer(ctx, px, py, angle, alpha = 1) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(px, py);
  ctx.rotate(angle);
  // manche
  const handle = ctx.createLinearGradient(0, -6, 0, 6);
  handle.addColorStop(0, '#a16207');
  handle.addColorStop(1, '#713f12');
  ctx.fillStyle = handle;
  roundRect(ctx, 0, -6, 128, 12, 5);
  ctx.fill();
  // tête
  const head = ctx.createLinearGradient(0, -34, 0, 34);
  head.addColorStop(0, '#e4e4e7');
  head.addColorStop(0.5, '#71717a');
  head.addColorStop(1, '#3f3f46');
  ctx.fillStyle = head;
  roundRect(ctx, 112, -34, 48, 68, 8);
  ctx.fill();
  ctx.strokeStyle = '#18181b';
  ctx.lineWidth = 3;
  ctx.stroke();
  ctx.restore();
}

function drawCracks(ctx, cx, cy, r, t, seed) {
  if (t <= 0) return;
  const rand = rng(seed);
  ctx.save();
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 2.5;
  ctx.globalAlpha = 0.85;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.clip();
  const ox = cx + r * 0.35;
  const oy = cy - r * 0.35;
  for (let i = 0; i < 7; i++) {
    let a = rand() * Math.PI * 2;
    let x = ox;
    let y = oy;
    ctx.beginPath();
    ctx.moveTo(x, y);
    const len = r * 1.6 * t;
    for (let d = 0; d < len; d += 12) {
      a += (rand() - 0.5) * 0.8;
      x += Math.cos(a) * 12;
      y += Math.sin(a) * 12;
      ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.restore();
}

function drawBoot(ctx, x, y, angle) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.fillStyle = '#78350f';
  ctx.strokeStyle = '#1c1917';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(-20, -70);
  ctx.lineTo(18, -70);
  ctx.lineTo(18, -10);
  ctx.quadraticCurveTo(70, -8, 74, 16);
  ctx.lineTo(74, 26);
  ctx.lineTo(-24, 26);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = '#292524';
  ctx.fillRect(-24, 18, 98, 9);
  ctx.restore();
}

function drawMuteSign(ctx, cx, cy, r, scale, alpha) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(cx, cy);
  ctx.scale(scale, scale);
  ctx.lineWidth = 12;
  ctx.strokeStyle = '#ef4444';
  ctx.shadowColor = '#ef4444';
  ctx.shadowBlur = 20;
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(-r * 0.7, -r * 0.7);
  ctx.lineTo(r * 0.7, r * 0.7);
  ctx.stroke();
  ctx.restore();
}

function drawWaves(ctx, cx, cy, f, alpha) {
  if (alpha <= 0) return;
  ctx.save();
  ctx.strokeStyle = '#c7d2fe';
  ctx.lineWidth = 4;
  for (let i = 0; i < 3; i++) {
    const rr = 20 + ((f * 4 + i * 18) % 54);
    ctx.globalAlpha = alpha * (1 - (rr - 20) / 54);
    ctx.beginPath();
    ctx.arc(cx, cy, rr, -0.6, 0.6);
    ctx.stroke();
  }
  ctx.restore();
}

function drawWarning(ctx, cx, cy, s, alpha) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(cx, cy);
  ctx.scale(s, s);
  ctx.fillStyle = '#facc15';
  ctx.strokeStyle = '#1c1917';
  ctx.lineWidth = 4;
  ctx.shadowColor = '#facc15';
  ctx.shadowBlur = 16;
  ctx.beginPath();
  ctx.moveTo(0, -36);
  ctx.lineTo(38, 30);
  ctx.lineTo(-38, 30);
  ctx.closePath();
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.stroke();
  ctx.fillStyle = '#1c1917';
  ctx.font = `900 40px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('!', 0, 8);
  ctx.restore();
}

function drawChainLink(ctx, x, y, angle, alpha) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.strokeStyle = '#a1a1aa';
  ctx.lineWidth = 6;
  roundRect(ctx, -16, -9, 32, 18, 9);
  ctx.stroke();
  ctx.restore();
}

// ─── Scénarios ────────────────────────────────────────────────
const AV = { x: 112, y: 110, r: 72 };

const SCENES = {
  ban(ctx, f, av, theme, info) {
    const IMPACT = 11;
    const shake = f >= IMPACT ? (1 - phase(f, IMPACT, IMPACT + 10)) * 9 : 0;
    const rand = rng(f + 7);
    ctx.save();
    ctx.translate((rand() - 0.5) * shake * 2, (rand() - 0.5) * shake * 2);
    const hit = phase(f, IMPACT, IMPACT + 6);
    drawAvatar(ctx, av, { ...AV, scale: f >= IMPACT ? lerp(0.9, 1, easeOut(hit)) : 1, gray: phase(f, IMPACT, IMPACT + 8), ring: theme.accent });
    drawCracks(ctx, AV.x, AV.y, AV.r, phase(f, IMPACT, IMPACT + 5), 42);
    // Le marteau s'abat puis rebondit et disparaît
    const swing = f < IMPACT ? easeIn(phase(f, 0, IMPACT)) : 1 - Math.sin(phase(f, IMPACT, IMPACT + 8) * Math.PI) * 0.12;
    const angle = lerp(-2.1, -3.62, swing);
    drawHammer(ctx, 262, 30, angle, 1 - phase(f, IMPACT + 9, IMPACT + 15));
    ctx.restore();
    flash(ctx, phase(f, IMPACT, IMPACT + 5));
    particles(ctx, 3, AV.x + 40, AV.y - 40, phase(f, IMPACT, IMPACT + 14), theme.accent);
    drawStamp(ctx, theme, phase(f, IMPACT + 3, IMPACT + 10));
    drawInfo(ctx, theme, info, phase(f, IMPACT + 6, IMPACT + 16));
  },

  kick(ctx, f, av, theme, info) {
    const IMPACT = 9;
    const fly = phase(f, IMPACT, IMPACT + 12);
    // Silhouette fantôme à la place d'origine
    ctx.save();
    ctx.globalAlpha = 0.35 * fly;
    ctx.setLineDash([8, 8]);
    ctx.strokeStyle = theme.accent;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(AV.x, AV.y, AV.r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
    // Traînée
    for (let k = 3; k >= 1; k--) {
      const tt = clamp(fly - k * 0.06);
      if (tt > 0 && fly < 1) drawAvatar(ctx, av, { x: lerp(AV.x, W + 120, easeIn(tt)), y: lerp(AV.y, -40, easeIn(tt)), r: AV.r, rot: tt * 7, scale: 1 - tt * 0.5, alpha: 0.18 });
    }
    if (fly < 1) drawAvatar(ctx, av, { x: lerp(AV.x, W + 120, easeIn(fly)), y: lerp(AV.y, -40, easeIn(fly)), r: AV.r, rot: fly * 7, scale: 1 - fly * 0.5, ring: theme.accent });
    const bootIn = easeIn(phase(f, 0, IMPACT));
    const bootOut = phase(f, IMPACT + 2, IMPACT + 9);
    drawBoot(ctx, lerp(-120, AV.x - 70, bootIn) - bootOut * 150, AV.y + 30, lerp(0.5, -0.25, bootIn));
    particles(ctx, 9, AV.x - 20, AV.y + 20, phase(f, IMPACT, IMPACT + 12), theme.accent, 20, 120);
    flash(ctx, phase(f, IMPACT, IMPACT + 4), theme.accent);
    drawStamp(ctx, theme, phase(f, IMPACT + 4, IMPACT + 11));
    drawInfo(ctx, theme, info, phase(f, IMPACT + 7, IMPACT + 17));
  },

  mute(ctx, f, av, theme, info) {
    const SLAM = 10;
    const dim = phase(f, SLAM, SLAM + 6);
    drawAvatar(ctx, av, { ...AV, gray: dim * 0.8, ring: theme.accent });
    drawWaves(ctx, AV.x + AV.r + 4, AV.y, f, 1 - phase(f, SLAM - 2, SLAM + 2));
    const slam = phase(f, SLAM - 3, SLAM + 3);
    if (slam > 0) drawMuteSign(ctx, AV.x, AV.y, AV.r - 6, lerp(2.2, 1, easeOutBack(slam)), clamp(slam * 2));
    flash(ctx, phase(f, SLAM, SLAM + 4), '#818cf8');
    drawStamp(ctx, theme, phase(f, SLAM + 3, SLAM + 10));
    drawInfo(ctx, theme, info, phase(f, SLAM + 6, SLAM + 16));
  },

  warn(ctx, f, av, theme, info) {
    const POP = 6;
    const shake = Math.sin(f * 2.2) * 6 * (1 - phase(f, POP, POP + 14));
    drawAvatar(ctx, av, { ...AV, x: AV.x + (f >= POP ? shake : 0), ring: theme.accent });
    const pop = phase(f, 0, POP);
    const pulse = 1 + Math.sin(f * 0.6) * 0.06;
    drawWarning(ctx, AV.x + 54, AV.y - 50, lerp(0.2, 1, easeOutBack(pop)) * pulse, clamp(pop * 2));
    particles(ctx, 5, AV.x + 54, AV.y - 50, phase(f, POP, POP + 12), theme.accent, 16, 90);
    drawStamp(ctx, theme, phase(f, POP + 3, POP + 10));
    drawInfo(ctx, theme, info, phase(f, POP + 6, POP + 16));
  },

  unban(ctx, f, av, theme, info) {
    const BREAK = 10;
    const color = phase(f, BREAK, BREAK + 8);
    drawAvatar(ctx, av, { ...AV, gray: 1 - color, ring: theme.accent, scale: 1 + Math.sin(phase(f, BREAK, BREAK + 8) * Math.PI) * 0.06 });
    const brk = phase(f, BREAK, BREAK + 12);
    const tremble = f < BREAK ? Math.sin(f * 3) * (f / BREAK) * 3 : 0;
    for (let i = -3; i <= 3; i++) {
      const bx = AV.x + i * 30;
      const by = AV.y + i * 12;
      const dir = i < 0 ? -1 : 1;
      drawChainLink(ctx, bx + dir * brk * 140 + tremble, by + easeIn(brk) * 120, (i % 2 ? Math.PI / 2 : 0.4) + brk * dir * 3, 1 - brk);
    }
    flash(ctx, phase(f, BREAK, BREAK + 4), '#34d399');
    particles(ctx, 11, AV.x, AV.y, phase(f, BREAK, BREAK + 14), theme.accent);
    drawStamp(ctx, theme, phase(f, BREAK + 3, BREAK + 10));
    drawInfo(ctx, theme, info, phase(f, BREAK + 6, BREAK + 16));
  },
};

/**
 * @param {'ban'|'kick'|'mute'|'warn'|'unban'} action
 * @param {{ avatarURL?: string, username: string, moderator: string, reason?: string, duration?: string }} info
 * @returns {Promise<Buffer>} le GIF
 */
async function renderActionGif(action, info) {
  const theme = THEMES[action];
  if (!theme) throw new Error(`action inconnue : ${action}`);
  const img = info.avatarURL ? await fetchAvatar(info.avatarURL) : null;
  const av = prepareAvatar(img, AV.r * 2, (info.username || '?')[0].toUpperCase(), theme.accent);
  const canvas = createCanvas(W, H);
  const ctx = canvas.getContext('2d');
  const gif = GIFEncoder();
  for (let f = 0; f < theme.frames; f++) {
    background(ctx, theme, f);
    SCENES[action](ctx, f, av, theme, info);
    const { data } = ctx.getImageData(0, 0, W, H);
    const palette = quantize(data, 256);
    const index = applyPalette(data, palette);
    const last = f === theme.frames - 1;
    gif.writeFrame(index, W, H, { palette, delay: last ? 4000 : 45, repeat: 0 });
  }
  gif.finish();
  return Buffer.from(gif.bytes());
}

module.exports = { renderActionGif, THEMES };
