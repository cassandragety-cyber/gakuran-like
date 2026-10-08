const db = require('../db');

function addSanction(guildId, userId, { type, reason, modId, duration }) {
  const g = db.guild(guildId);
  const id = ++g.sanctionCounter;
  (g.sanctions[userId] ??= []).push({ id, type, reason: reason || null, modId, duration: duration ?? null, date: Date.now() });
  db.save();
  return id;
}

function addTimer(guildId, timer) {
  const g = db.guild(guildId);
  // Un seul timer du même type par cible (un nouveau tempban remplace l'ancien)
  g.timers = g.timers.filter((t) => !(t.type === timer.type && t.userId === timer.userId && t.roleId === timer.roleId));
  g.timers.push(timer);
  db.save();
}

function removeTimer(guildId, predicate) {
  const g = db.guild(guildId);
  const before = g.timers.length;
  g.timers = g.timers.filter((t) => !predicate(t));
  if (g.timers.length !== before) db.save();
}

module.exports = { addSanction, addTimer, removeTimer };
