// Jeux à deux : morpion, puissance 4, pierre-feuille-ciseaux. Contre un membre ou contre le bot.
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, ComponentType } = require('discord.js');
const ui = require('../util/ui');
const { record, challenge, notYours, mention } = require('./common');

// Lance la partie : défi si adversaire humain, puis renvoie le message à animer
async function start(interaction, opponent, gameName) {
  if (opponent && opponent.bot && opponent.id !== interaction.client.user.id) {
    await interaction.reply({ embeds: [ui.error('Tu ne peux pas défier un autre bot.')], flags: 64 });
    return null;
  }
  if (opponent?.id === interaction.user.id) {
    await interaction.reply({ embeds: [ui.error('Tu ne peux pas jouer contre toi-même.')], flags: 64 });
    return null;
  }
  const vsBot = !opponent || opponent.id === interaction.client.user.id;
  if (vsBot) {
    const msg = await interaction.reply({ content: '…', withResponse: true }).then((r) => r.resource.message);
    return { msg, players: [interaction.user.id, 'bot'] };
  }
  const msg = await challenge(interaction, opponent, gameName);
  if (!msg) return null;
  // Celui qui commence est tiré au sort
  const players = Math.random() < 0.5 ? [interaction.user.id, opponent.id] : [opponent.id, interaction.user.id];
  return { msg, players };
}

function finish(interaction, game, players, winnerIdx) {
  players.forEach((p, i) => record(interaction.guild.id, game, p, winnerIdx === null ? 'draw' : i === winnerIdx ? 'win' : 'loss'));
}

// ─── Morpion ──────────────────────────────────────────────────
const LINES = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]];
const tttWinner = (b) => {
  for (const [a, c, d] of LINES) if (b[a] !== null && b[a] === b[c] && b[a] === b[d]) return b[a];
  return b.every((x) => x !== null) ? 'draw' : null;
};

// Minimax : le bot est imbattable au morpion (il fait au mieux match nul)
function minimax(b, turn, me) {
  const w = tttWinner(b);
  if (w === 'draw') return { score: 0 };
  if (w !== null) return { score: w === me ? 10 : -10 };
  let best = { score: turn === me ? -Infinity : Infinity };
  for (let i = 0; i < 9; i++) {
    if (b[i] !== null) continue;
    b[i] = turn;
    const { score } = minimax(b, 1 - turn, me);
    b[i] = null;
    const s = score - Math.sign(score); // préfère gagner vite
    if (turn === me ? s > best.score : s < best.score) best = { score: s, move: i };
  }
  return best;
}

async function morpion(interaction, opponent) {
  const game = await start(interaction, opponent, 'Morpion');
  if (!game) return;
  const { msg, players } = game;
  const board = Array(9).fill(null);
  const SYM = ['❌', '⭕'];
  let turn = 0;
  let result = null;

  const view = (text) => ({
    content: null,
    embeds: [ui.embed(interaction.guild).setTitle('❌ Morpion ⭕').setDescription(`${SYM[0]} ${mention(players[0])}  vs  ${SYM[1]} ${mention(players[1])}\n\n${text}`)],
    components: [0, 1, 2].map((r) => new ActionRowBuilder().addComponents([0, 1, 2].map((c) => {
      const i = r * 3 + c;
      const b = new ButtonBuilder().setCustomId(`ttt_${i}`).setStyle(board[i] === null ? ButtonStyle.Secondary : board[i] === 0 ? ButtonStyle.Danger : ButtonStyle.Primary).setDisabled(board[i] !== null || result !== null);
      return board[i] === null ? b.setLabel('​') : b.setEmoji(SYM[board[i]]);
    }))),
  });
  const turnText = () => `Au tour de ${SYM[turn]} ${mention(players[turn])}`;
  const play = (i) => {
    board[i] = turn;
    const w = tttWinner(board);
    if (w !== null) result = w;
    else turn = 1 - turn;
  };
  const endText = () => (result === 'draw' ? '🤝 **Match nul !**' : `🏆 **${mention(players[result])} gagne !**`);

  if (players[turn] === 'bot') play(4);
  await interaction.editReply(view(turnText()));
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, idle: 60e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== players[turn]) return notYours(i);
    play(Number(i.customId.split('_')[1]));
    if (result === null && players[turn] === 'bot') play(minimax(board, turn, turn).move);
    if (result !== null) collector.stop('fin');
    await i.update(view(result === null ? turnText() : endText()));
  });
  collector.on('end', async (_, reason) => {
    if (reason === 'fin') return finish(interaction, 'morpion', players, result === 'draw' ? null : result);
    // Inactivité : celui qui devait jouer perd
    result = 1 - turn;
    finish(interaction, 'morpion', players, result);
    await interaction.editReply(view(`⏰ ${mention(players[turn])} n’a pas joué à temps. ${endText()}`)).catch(() => {});
  });
}

// ─── Puissance 4 ──────────────────────────────────────────────
const ROWS = 6;
const COLS = 7;
const DISC = ['🔴', '🟡'];

function drop(grid, col, p) {
  for (let r = ROWS - 1; r >= 0; r--) if (grid[r][col] === null) { grid[r][col] = p; return r; }
  return -1;
}
function undrop(grid, col) {
  for (let r = 0; r < ROWS; r++) if (grid[r][col] !== null) { grid[r][col] = null; return; }
}
function p4Winner(grid) {
  const dirs = [[0, 1], [1, 0], [1, 1], [1, -1]];
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    const p = grid[r][c];
    if (p === null) continue;
    for (const [dr, dc] of dirs) {
      let k = 1;
      while (k < 4 && grid[r + dr * k]?.[c + dc * k] === p) k++;
      if (k === 4) return p;
    }
  }
  return grid[0].every((x) => x !== null) ? 'draw' : null;
}

// IA simple : gagner si possible, sinon bloquer, sinon éviter d'offrir la victoire, en privilégiant le centre
function p4Bot(grid, me) {
  const open = [...Array(COLS).keys()].filter((c) => grid[0][c] === null);
  for (const who of [me, 1 - me]) {
    for (const c of open) {
      drop(grid, c, who);
      const w = p4Winner(grid) === who;
      undrop(grid, c);
      if (w) return c;
    }
  }
  const safe = open.filter((c) => {
    drop(grid, c, me);
    let bad = false;
    for (const c2 of open) {
      if (grid[0][c2] !== null) continue;
      drop(grid, c2, 1 - me);
      if (p4Winner(grid) === 1 - me) bad = true;
      undrop(grid, c2);
    }
    undrop(grid, c);
    return !bad;
  });
  const pool = safe.length ? safe : open;
  const weight = (c) => 4 - Math.abs(3 - c) + Math.random() * 2.5;
  return pool.sort((a, b) => weight(b) - weight(a))[0];
}

async function puissance4(interaction, opponent) {
  const game = await start(interaction, opponent, 'Puissance 4');
  if (!game) return;
  const { msg, players } = game;
  const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
  let turn = 0;
  let result = null;
  let last = null;

  const render = () => grid.map((row, r) => row.map((x, c) => (x === null ? '⚫' : r === last?.[0] && c === last?.[1] ? (x === 0 ? '❤️' : '💛') : DISC[x])).join('')).join('\n') + '\n1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣';
  const view = (text) => ({
    content: null,
    embeds: [ui.embed(interaction.guild).setTitle('🔴 Puissance 4 🟡').setDescription(`${DISC[0]} ${mention(players[0])}  vs  ${DISC[1]} ${mention(players[1])}\n\n${render()}\n\n${text}`)],
    components: [[0, 1, 2, 3], [4, 5, 6]].map((cols) => new ActionRowBuilder().addComponents(cols.map((c) => new ButtonBuilder()
      .setCustomId(`p4_${c}`).setLabel(String(c + 1)).setStyle(ButtonStyle.Secondary).setDisabled(grid[0][c] !== null || result !== null)))),
  });
  const play = (c) => {
    const r = drop(grid, c, turn);
    last = [r, c];
    const w = p4Winner(grid);
    if (w !== null) result = w;
    else turn = 1 - turn;
  };
  const turnText = () => `Au tour de ${DISC[turn]} ${mention(players[turn])}`;
  const endText = () => (result === 'draw' ? '🤝 **Match nul !**' : `🏆 **${mention(players[result])} gagne !**`);

  if (players[turn] === 'bot') play(3);
  await interaction.editReply(view(turnText()));
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, idle: 90e3 });
  collector.on('collect', async (i) => {
    if (i.user.id !== players[turn]) return notYours(i);
    play(Number(i.customId.split('_')[1]));
    if (result === null && players[turn] === 'bot') play(p4Bot(grid, turn));
    if (result !== null) collector.stop('fin');
    await i.update(view(result === null ? turnText() : endText()));
  });
  collector.on('end', async (_, reason) => {
    if (reason === 'fin') return finish(interaction, 'puissance4', players, result === 'draw' ? null : result);
    result = 1 - turn;
    finish(interaction, 'puissance4', players, result);
    await interaction.editReply(view(`⏰ ${mention(players[turn])} n’a pas joué à temps. ${endText()}`)).catch(() => {});
  });
}

// ─── Pierre-feuille-ciseaux ───────────────────────────────────
const PFC = { pierre: '🪨', feuille: '📄', ciseaux: '✂️' };
const BEATS = { pierre: 'ciseaux', feuille: 'pierre', ciseaux: 'feuille' };

async function pfc(interaction, opponent) {
  const game = await start(interaction, opponent, 'Pierre-feuille-ciseaux');
  if (!game) return;
  const { msg, players } = game;
  const choice = {};
  if (players.includes('bot')) choice.bot = Object.keys(PFC)[Math.floor(Math.random() * 3)];
  const row = (disabled) => new ActionRowBuilder().addComponents(Object.entries(PFC).map(([k, e]) => new ButtonBuilder().setCustomId(`pfc_${k}`).setEmoji(e).setLabel(k).setStyle(ButtonStyle.Primary).setDisabled(disabled)));
  const waiting = () => players.map((p) => `${choice[p] ? '✅' : '⏳'} ${mention(p)}`).join('\n');
  await interaction.editReply({ content: null, embeds: [ui.embed(interaction.guild).setTitle('🪨 📄 ✂️').setDescription(`Faites votre choix (en secret) !\n\n${waiting()}`)], components: [row(false)] });
  const result = () => {
    const [a, b] = players.map((p) => choice[p]);
    const winner = a === b ? null : BEATS[a] === b ? 0 : 1;
    finish(interaction, 'pfc', players, winner);
    return {
      embeds: [ui.embed(interaction.guild).setTitle('🪨 📄 ✂️ Résultat').setDescription(`${mention(players[0])} : ${PFC[a]} **${a}**\n${mention(players[1])} : ${PFC[b]} **${b}**\n\n${winner === null ? '🤝 **Égalité !**' : `🏆 **${mention(players[winner])} gagne !**`}`)],
      components: [row(true)],
    };
  };
  const collector = msg.createMessageComponentCollector({ componentType: ComponentType.Button, time: 60e3 });
  collector.on('collect', async (i) => {
    if (!players.includes(i.user.id)) return notYours(i);
    if (choice[i.user.id]) return i.reply({ content: 'Tu as déjà choisi.', flags: 64 });
    choice[i.user.id] = i.customId.split('_')[1];
    if (players.every((p) => choice[p])) {
      collector.stop('fin');
      return i.update(result());
    }
    await i.update({ embeds: [ui.embed(interaction.guild).setTitle('🪨 📄 ✂️').setDescription(`Faites votre choix (en secret) !\n\n${waiting()}`)] });
  });
  collector.on('end', (_, reason) => {
    if (reason !== 'fin') interaction.editReply({ embeds: [ui.info('⏰ Partie annulée : tout le monde n’a pas joué.', interaction.guild)], components: [] }).catch(() => {});
  });
}

module.exports = { morpion, puissance4, pfc, tttWinner, minimax, p4Winner, p4Bot };
