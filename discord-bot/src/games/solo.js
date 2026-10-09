// Jeux en solo (démineur, snake, mémoire) et jeux de salon (pendu, rapido, nombre mystère).
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, ComponentType, AttachmentBuilder } = require('discord.js');
const { createCanvas } = require('@napi-rs/canvas');
const ui = require('../util/ui');
const { record, notYours } = require('./common');

const rand = (n) => Math.floor(Math.random() * n);
const shuffle = (a) => { for (let i = a.length - 1; i > 0; i--) { const j = rand(i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const norm = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
const reply = (interaction, payload) => interaction.reply({ ...payload, withResponse: true }).then((r) => r.resource.message);

// ─── Démineur ─────────────────────────────────────────────────
const MR = 4;
const MC = 5;
const MINES = 4;
const NUM = ['​', '1', '2', '3', '4', '5', '6', '7', '8'];

async function demineur(interaction) {
  const cells = Array.from({ length: MR * MC }, () => ({ mine: false, open: false, flag: false, n: 0 }));
  let placed = false;
  let flagMode = false;
  let over = null; // 'win' | 'loss'
  const started = Date.now();
  const around = (i) => {
    const r = Math.floor(i / MC);
    const c = i % MC;
    const out = [];
    for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
      const rr = r + dr;
      const cc = c + dc;
      if ((dr || dc) && rr >= 0 && rr < MR && cc >= 0 && cc < MC) out.push(rr * MC + cc);
    }
    return out;
  };
  // Les mines sont posées après le premier clic : il ne tombe jamais sur une mine
  const place = (safe) => {
    const forbidden = new Set([safe, ...around(safe)]);
    const spots = shuffle([...cells.keys()].filter((i) => !forbidden.has(i))).slice(0, MINES);
    for (const i of spots) cells[i].mine = true;
    cells.forEach((cell, i) => (cell.n = around(i).filter((j) => cells[j].mine).length));
    placed = true;
  };
  const reveal = (i) => {
    const stack = [i];
    while (stack.length) {
      const j = stack.pop();
      if (cells[j].open || cells[j].flag) continue;
      cells[j].open = true;
      if (cells[j].n === 0 && !cells[j].mine) stack.push(...around(j));
    }
  };
  const view = (text) => ({
    embeds: [ui.embed(interaction.guild).setTitle('💣 Démineur').setDescription(`${MINES} mines cachées. ${flagMode ? '🚩 **Mode drapeau**' : '⛏️ **Mode creuser**'}\n\n${text}`)],
    components: [
      ...[...Array(MR).keys()].map((r) => new ActionRowBuilder().addComponents([...Array(MC).keys()].map((c) => {
        const i = r * MC + c;
        const cell = cells[i];
        const show = cell.open || over;
        const b = new ButtonBuilder().setCustomId(`mine_${i}`).setDisabled(!!over || cell.open);
        if (show && cell.mine) return b.setEmoji(cell.flag ? '🚩' : '💥').setStyle(ButtonStyle.Danger);
        if (cell.flag) return b.setEmoji('🚩').setStyle(ButtonStyle.Primary);
        if (cell.open) return b.setLabel(NUM[cell.n]).setStyle(ButtonStyle.Success);
        return b.setLabel('​').setStyle(ButtonStyle.Secondary);
      }))),
      new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId('mine_flag').setEmoji(flagMode ? '⛏️' : '🚩').setLabel(flagMode ? 'Creuser' : 'Drapeau').setStyle(ButtonStyle.Primary).setDisabled(!!over),
        new ButtonBuilder().setCustomId('mine_quit').setLabel('Abandonner').setStyle(ButtonStyle.Danger).setDisabled(!!over),
      ),
    ],
  });
  const msg = await reply(interaction, view('Clique sur une case pour commencer.'));
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, idle: 120e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== interaction.user.id) return notYours(i);
    const id = i.customId.split('_')[1];
    if (id === 'flag') flagMode = !flagMode;
    else if (id === 'quit') over = 'loss';
    else {
      const n = Number(id);
      if (flagMode) cells[n].flag = !cells[n].flag;
      else if (!cells[n].flag) {
        if (!placed) place(n);
        if (cells[n].mine) over = 'loss';
        else reveal(n);
        if (!over && cells.every((c) => c.mine || c.open)) over = 'win';
      }
    }
    if (over) collector.stop('fin');
    const secs = Math.round((Date.now() - started) / 1000);
    await i.update(view(over === 'win' ? `🏆 **Gagné en ${secs} s !**` : over === 'loss' ? '💥 **BOUM ! Perdu.**' : 'Continue…'));
    if (over) record(interaction.guild.id, 'demineur', interaction.user.id, over, over === 'win' ? secs : null);
  });
  collector.on('end', (_, reason) => reason !== 'fin' && interaction.editReply({ components: [] }).catch(() => {}));
}

// ─── Snake ────────────────────────────────────────────────────
const SN = 9;

async function snake(interaction) {
  let body = [[4, 2], [4, 1]]; // [ligne, colonne], tête en premier
  let dir = [0, 1];
  let apple;
  let score = 0;
  let dead = false;
  const newApple = () => {
    const free = [];
    for (let r = 0; r < SN; r++) for (let c = 0; c < SN; c++) if (!body.some(([br, bc]) => br === r && bc === c)) free.push([r, c]);
    apple = free[rand(free.length)];
  };
  newApple();
  const render = () => {
    const rows = [];
    for (let r = 0; r < SN; r++) {
      let line = '';
      for (let c = 0; c < SN; c++) {
        const k = body.findIndex(([br, bc]) => br === r && bc === c);
        line += k === 0 ? (dead ? '💀' : '🐲') : k > 0 ? '🟩' : apple[0] === r && apple[1] === c ? '🍎' : '⬛';
      }
      rows.push(line);
    }
    return rows.join('\n');
  };
  const btn = (id, emoji, disabled = false) => new ButtonBuilder().setCustomId(`snake_${id}`).setEmoji(emoji).setStyle(ButtonStyle.Secondary).setDisabled(disabled || dead);
  const view = (text) => ({
    embeds: [ui.embed(interaction.guild).setTitle(`🐍 Snake — score ${score}`).setDescription(`${render()}\n\n${text}`)],
    components: [
      new ActionRowBuilder().addComponents(btn('x1', '⬛', true), btn('up', '⬆️'), btn('x2', '⬛', true)),
      new ActionRowBuilder().addComponents(btn('left', '⬅️'), btn('down', '⬇️'), btn('right', '➡️')),
      new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId('snake_stop').setLabel('Arrêter').setStyle(ButtonStyle.Danger).setDisabled(dead)),
    ],
  });
  const DIRS = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] };
  const msg = await reply(interaction, view('Chaque clic avance le serpent d’une case. Mange les 🍎 !'));
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, idle: 60e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== interaction.user.id) return notYours(i);
    const key = i.customId.split('_')[1];
    if (key === 'stop') dead = true;
    else {
      const d = DIRS[key];
      // Pas de demi-tour sur soi-même
      if (!(d[0] === -dir[0] && d[1] === -dir[1])) dir = d;
      const head = [body[0][0] + dir[0], body[0][1] + dir[1]];
      const eats = head[0] === apple[0] && head[1] === apple[1];
      const tail = eats ? body : body.slice(0, -1);
      if (head[0] < 0 || head[0] >= SN || head[1] < 0 || head[1] >= SN || tail.some(([r, c]) => r === head[0] && c === head[1])) dead = true;
      else {
        body = [head, ...tail];
        if (eats) {
          score++;
          if (body.length >= SN * SN) dead = true;
          else newApple();
        }
      }
    }
    if (dead) collector.stop('fin');
    await i.update(view(dead ? `💀 **Partie terminée — ${score} pomme(s) !**` : 'Continue !'));
    if (dead) record(interaction.guild.id, 'snake', interaction.user.id, null, score);
  });
  collector.on('end', async (_, reason) => {
    if (reason === 'fin') return;
    dead = true;
    record(interaction.guild.id, 'snake', interaction.user.id, null, score);
    await interaction.editReply(view(`⏰ Temps écoulé — **${score} pomme(s)**.`)).catch(() => {});
  });
}

// ─── Mémoire (paires) ─────────────────────────────────────────
const EMOJIS = ['🍎', '🍌', '🍇', '🍒', '🥝', '🍑', '🍍', '🥥', '🍉', '🍓', '🐶', '🐱', '🦊', '🐸', '🐼', '🐙', '🦄', '🐝', '⚽', '🎮'];

async function memoire(interaction) {
  const pick = shuffle([...EMOJIS]).slice(0, 10);
  const cards = shuffle([...pick, ...pick]).map((e) => ({ e, found: false }));
  let shown = [];
  let moves = 0;
  let locked = false;
  let done = false;
  const view = (text) => ({
    embeds: [ui.embed(interaction.guild).setTitle('🧠 Mémoire').setDescription(`Retrouve les 10 paires !\n**Coups :** ${moves}\n\n${text}`)],
    components: [...Array(4).keys()].map((r) => new ActionRowBuilder().addComponents([...Array(5).keys()].map((c) => {
      const i = r * 5 + c;
      const card = cards[i];
      const visible = card.found || shown.includes(i) || done;
      const b = new ButtonBuilder().setCustomId(`mem_${i}`).setStyle(card.found ? ButtonStyle.Success : shown.includes(i) ? ButtonStyle.Primary : ButtonStyle.Secondary).setDisabled(card.found || shown.includes(i) || done);
      return visible ? b.setEmoji(card.e) : b.setLabel('?');
    }))),
  });
  const msg = await reply(interaction, view('Clique sur deux cartes.'));
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, idle: 120e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== interaction.user.id) return notYours(i);
    if (locked) return i.deferUpdate();
    shown.push(Number(i.customId.split('_')[1]));
    if (shown.length < 2) return i.update(view('Encore une…'));
    moves++;
    const [a, b] = shown;
    if (cards[a].e === cards[b].e) {
      cards[a].found = cards[b].found = true;
      shown = [];
      if (cards.every((c) => c.found)) {
        done = true;
        collector.stop('fin');
        record(interaction.guild.id, 'memoire', interaction.user.id, 'win', moves);
        return i.update(view(`🏆 **Bravo, terminé en ${moves} coups !**`));
      }
      return i.update(view('✅ Paire trouvée !'));
    }
    // Mauvaise paire : on la montre 1,5 s puis on la recache
    locked = true;
    await i.update(view('❌ Raté…'));
    setTimeout(async () => {
      shown = [];
      locked = false;
      await interaction.editReply(view('Clique sur deux cartes.')).catch(() => {});
    }, 1500);
  });
  collector.on('end', (_, reason) => {
    if (reason === 'fin') return;
    done = true;
    interaction.editReply(view('⏰ Partie abandonnée.')).catch(() => {});
  });
}

// ─── Pendu (tout le salon peut proposer) ─────────────────────
const WORDS = ['ordinateur', 'discord', 'moderation', 'galaxie', 'pyramide', 'chocolat', 'dragon', 'montagne', 'telephone', 'aventure',
  'papillon', 'baleine', 'guitare', 'horizon', 'labyrinthe', 'mystere', 'parapluie', 'tempete', 'volcan', 'zebre', 'crocodile',
  'bibliotheque', 'astronaute', 'chevalier', 'framboise', 'kangourou', 'pingouin', 'renard', 'serpent', 'tornade', 'vampire',
  'cerise', 'domaine', 'expansion', 'samourai', 'ninja', 'pirate', 'tresor', 'boussole', 'citrouille', 'fantome', 'licorne',
  'manette', 'musique', 'requin', 'soleil', 'trompette', 'univers', 'voyage', 'jongleur', 'hamburger', 'pizzeria', 'football',
  'basketball', 'clavier', 'souris', 'ecran', 'internet', 'serveur', 'robotique', 'satellite', 'meteorite', 'cascade', 'desert'];
const GALLOWS = [
  '```\n  +---+\n      |\n      |\n      |\n     ===```', '```\n  +---+\n  O   |\n      |\n      |\n     ===```',
  '```\n  +---+\n  O   |\n  |   |\n      |\n     ===```', '```\n  +---+\n  O   |\n /|   |\n      |\n     ===```',
  '```\n  +---+\n  O   |\n /|\\  |\n      |\n     ===```', '```\n  +---+\n  O   |\n /|\\  |\n /    |\n     ===```',
  '```\n  +---+\n  O   |\n /|\\  |\n / \\  |\n     ===```',
];

async function pendu(interaction) {
  const word = WORDS[rand(WORDS.length)];
  const guessed = new Set();
  const wrong = [];
  const masked = () => [...word].map((l) => (guessed.has(l) ? l.toUpperCase() : '＿')).join(' ');
  const view = (text) => ({ embeds: [ui.embed(interaction.guild).setTitle('🪢 Pendu').setDescription(`${GALLOWS[wrong.length]}\n**${masked()}**\n\n❌ Lettres ratées : ${wrong.join(' ').toUpperCase() || '—'}\n\n${text}`)] });
  await interaction.reply(view('Tout le monde peut jouer ! Écris **une lettre** ou **le mot entier** dans le salon. (3 minutes)'));
  const collector = interaction.channel.createMessageCollector({ filter: (m) => !m.author.bot && /^[a-zà-ÿ]+$/i.test(m.content.trim()), time: 180e3 });
  collector.on('collect', async (m) => {
    const g = norm(m.content);
    let winner = null;
    if (g.length === 1) {
      if (guessed.has(g) || wrong.includes(g)) return;
      if (word.includes(g)) guessed.add(g);
      else wrong.push(g);
      if ([...word].every((l) => guessed.has(l))) winner = m.author;
    } else if (g === word) {
      [...word].forEach((l) => guessed.add(l));
      winner = m.author;
    } else if (g.length === word.length) wrong.push(`(${g})`);
    else return;
    await m.react(winner || word.includes(g) ? '✅' : '❌').catch(() => {});
    if (winner) {
      collector.stop('fin');
      record(interaction.guild.id, 'pendu', winner.id, 'win');
      return interaction.editReply(view(`🏆 **${winner} a trouvé : ${word.toUpperCase()} !**`));
    }
    if (wrong.length >= GALLOWS.length - 1) {
      collector.stop('fin');
      return interaction.editReply(view(`💀 **Pendu ! Le mot était ${word.toUpperCase()}.**`));
    }
    await interaction.editReply(view('Continuez !'));
  });
  collector.on('end', (_, reason) => reason !== 'fin' && interaction.editReply(view(`⏰ Temps écoulé ! Le mot était **${word.toUpperCase()}**.`)).catch(() => {}));
  // La promesse se termine avec la partie (libère le salon)
  return new Promise((done) => collector.on('end', done));
}

// ─── Rapido : le premier qui recopie la phrase gagne ─────────
const RAPIDO = ['gojo', 'sukuna', 'domaine', 'extension', 'pizza', 'clavier', 'discord', 'rapide', 'tornade', 'banane', 'licorne', 'dragon', 'serveur', 'musique', 'pirate', 'chocolat', 'fusée', 'étoile', 'soleil', 'nuage', 'requin', 'ninja', 'manette', 'volcan'];

function textImage(text, color) {
  const c = createCanvas(700, 140);
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#111118';
  ctx.fillRect(0, 0, 700, 140);
  // Un peu de bruit pour empêcher la copie par reconnaissance de texte facile
  for (let k = 0; k < 40; k++) {
    ctx.strokeStyle = `rgba(255,255,255,${Math.random() * 0.12})`;
    ctx.beginPath();
    ctx.moveTo(Math.random() * 700, Math.random() * 140);
    ctx.lineTo(Math.random() * 700, Math.random() * 140);
    ctx.stroke();
  }
  ctx.fillStyle = `#${color.toString(16).padStart(6, '0')}`;
  ctx.font = 'bold 46px "Segoe UI", "Liberation Sans", Arial, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, 350, 72);
  return c.toBuffer('image/png');
}

async function rapido(interaction) {
  const phrase = shuffle([...RAPIDO]).slice(0, 3).join(' ');
  await interaction.reply({ embeds: [ui.info('⚡ **Rapido** : prépare-toi… la phrase arrive dans 3 secondes !', interaction.guild)] });
  await new Promise((r) => setTimeout(r, 3000));
  const shownAt = Date.now();
  await interaction.editReply({
    embeds: [ui.embed(interaction.guild).setTitle('⚡ Rapido !').setDescription('Le premier qui **recopie** cette phrase gagne (30 s) :').setImage('attachment://rapido.png')],
    files: [new AttachmentBuilder(textImage(phrase, ui.colorFor(interaction.guild)), { name: 'rapido.png' })],
  });
  const m = await interaction.channel.awaitMessages({ filter: (x) => !x.author.bot && norm(x.content) === norm(phrase), max: 1, time: 30e3 }).then((c) => c.first());
  if (!m) return interaction.followUp({ embeds: [ui.info(`⏰ Personne n’a été assez rapide ! C’était : **${phrase}**`, interaction.guild)] });
  const ms = Date.now() - shownAt;
  record(interaction.guild.id, 'rapido', m.author.id, 'win');
  await m.react('⚡').catch(() => {});
  await interaction.followUp({ embeds: [ui.embed(interaction.guild).setDescription(`🏆 **${m.author}** gagne en **${(ms / 1000).toFixed(2)} s** !`)] });
}

// ─── Nombre mystère ───────────────────────────────────────────
async function nombre(interaction, max = 100) {
  const target = 1 + rand(max);
  let tries = 0;
  await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('🔢 Nombre mystère').setDescription(`J’ai choisi un nombre entre **1 et ${max}**.\nÉcrivez vos propositions dans le salon (2 minutes) !`)] });
  const collector = interaction.channel.createMessageCollector({ filter: (m) => !m.author.bot && /^\d+$/.test(m.content.trim()), time: 120e3 });
  collector.on('collect', async (m) => {
    const n = Number(m.content.trim());
    tries++;
    if (n === target) {
      collector.stop('fin');
      record(interaction.guild.id, 'nombre', m.author.id, 'win');
      await m.react('🎉').catch(() => {});
      return interaction.followUp({ embeds: [ui.embed(interaction.guild).setDescription(`🏆 **${m.author}** a trouvé **${target}** après ${tries} essai(s) !`)] });
    }
    await m.react(n < target ? '⬆️' : '⬇️').catch(() => {});
  });
  collector.on('end', (_, reason) => reason !== 'fin' && interaction.followUp({ embeds: [ui.info(`⏰ Temps écoulé ! Le nombre était **${target}**.`, interaction.guild)] }).catch(() => {}));
  return new Promise((done) => collector.on('end', done));
}

module.exports = { demineur, snake, memoire, pendu, rapido, nombre };
