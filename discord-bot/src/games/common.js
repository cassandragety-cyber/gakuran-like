// Outils partagés par les mini-jeux : statistiques, défis entre membres, boutons.
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, ComponentType } = require('discord.js');
const db = require('../db');
const ui = require('../util/ui');

// Pour chaque jeu : ce qui compte dans le classement
const GAMES = {
  morpion: { name: '❌ Morpion', rank: 'wins' },
  puissance4: { name: '🔴 Puissance 4', rank: 'wins' },
  pfc: { name: '✂️ Pierre-feuille-ciseaux', rank: 'wins' },
  pendu: { name: '🪢 Pendu', rank: 'wins' },
  demineur: { name: '💣 Démineur', rank: 'best', lower: true, unit: 's' },
  snake: { name: '🐍 Snake', rank: 'best', unit: ' pts' },
  memoire: { name: '🧠 Mémoire', rank: 'best', lower: true, unit: ' coups' },
  rapido: { name: '⚡ Rapido', rank: 'wins' },
  nombre: { name: '🔢 Nombre mystère', rank: 'wins' },
};

function stats(guildId, game, userId) {
  const g = db.guild(guildId);
  const table = (g.games[game] ??= {});
  return (table[userId] ??= { wins: 0, losses: 0, draws: 0, played: 0, best: null });
}

/** result : 'win' | 'loss' | 'draw' | null ; score : meilleur score éventuel */
function record(guildId, game, userId, result, score) {
  if (!userId || userId === 'bot') return;
  const s = stats(guildId, game, userId);
  s.played++;
  if (result === 'win') s.wins++;
  if (result === 'loss') s.losses++;
  if (result === 'draw') s.draws++;
  if (score != null) {
    const lower = GAMES[game].lower;
    if (s.best == null || (lower ? score < s.best : score > s.best)) s.best = score;
  }
  db.save();
}

function leaderboard(guildId, game) {
  const def = GAMES[game];
  const rows = Object.entries(db.guild(guildId).games[game] ?? {});
  if (def.rank === 'best') {
    return rows.filter(([, s]) => s.best != null).sort((a, b) => (def.lower ? a[1].best - b[1].best : b[1].best - a[1].best))
      .map(([id, s]) => [id, `**${s.best}${def.unit}** (${s.played} parties)`]);
  }
  return rows.filter(([, s]) => s.wins).sort((a, b) => b[1].wins - a[1].wins || a[1].losses - b[1].losses)
    .map(([id, s]) => [id, `**${s.wins}** victoires • ${s.losses} défaites${s.draws ? ` • ${s.draws} nuls` : ''}`]);
}

// Demande à un membre d'accepter un duel. Renvoie true s'il accepte.
async function challenge(interaction, opponent, gameName) {
  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('duel_ok').setLabel('Accepter').setEmoji('⚔️').setStyle(ButtonStyle.Success),
    new ButtonBuilder().setCustomId('duel_no').setLabel('Refuser').setStyle(ButtonStyle.Secondary),
  );
  const msg = await interaction.reply({
    content: `${opponent}`,
    embeds: [ui.embed(interaction.guild).setDescription(`⚔️ ${interaction.user} te défie au **${gameName}** ! Tu as 60 secondes pour accepter.`)],
    components: [row],
    withResponse: true,
  }).then((r) => r.resource.message);
  const click = await msg.awaitMessageComponent({ componentType: ComponentType.Button, filter: (i) => i.user.id === opponent.id, time: 60e3 }).catch(() => null);
  if (click?.customId !== 'duel_ok') {
    await interaction.editReply({ content: null, embeds: [ui.info(click ? `${opponent} a refusé le duel.` : `${opponent} n’a pas répondu.`, interaction.guild)], components: [] });
    return null;
  }
  await click.deferUpdate();
  return msg;
}

// Empêche un joueur de cliquer sur la partie d'un autre
const notYours = (i) => i.reply({ content: 'Ce n’est pas ta partie (ou pas ton tour) !', flags: 64 }).catch(() => {});

const mention = (p) => (p === 'bot' ? '🤖 le bot' : `<@${p}>`);

module.exports = { GAMES, stats, record, leaderboard, challenge, notYours, mention };
