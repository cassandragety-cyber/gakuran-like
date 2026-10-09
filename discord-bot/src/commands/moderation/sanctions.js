const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { isTrusted } = require('../../util/perms');
const { paginate, chunk } = require('../../util/paginate');
const { ts, formatDuration } = require('../../util/time');

const LABEL = { ban: '🔨 Ban', tempban: '⏳ Tempban', kick: '👢 Kick', mute: '🔇 Mute', warn: '⚠️ Warn', derank: '📉 Derank', cmute: '🔇 Mute salon' };

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('sanctions')
    .setDescription('Historique des sanctions')
    .setDefaultMemberPermissions(PermissionFlagsBits.ModerateMembers)
    .addSubcommand((s) => s.setName('liste').setDescription('Affiche les sanctions d’un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('supprimer').setDescription('Supprime une sanction par son numéro')
      .addIntegerOption((o) => o.setName('numero').setDescription('Numéro de la sanction (#)').setRequired(true)))
    .addSubcommand((s) => s.setName('effacer').setDescription('Supprime toutes les sanctions d’un membre')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('tout-effacer').setDescription('Supprime TOUTES les sanctions du serveur')),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'liste') {
      const user = interaction.options.getUser('membre', true);
      const list = [...(g.sanctions[user.id] ?? [])].reverse();
      const pages = chunk(list, 8);
      const counts = Object.entries(list.reduce((a, s) => ({ ...a, [s.type]: (a[s.type] ?? 0) + 1 }), {})).map(([t, n]) => `${LABEL[t] ?? t} : **${n}**`).join(' • ');
      return paginate(interaction, Math.max(1, pages.length), (p) => ui.embed(interaction.guild)
        .setAuthor({ name: `Sanctions de ${user.username}`, iconURL: user.displayAvatarURL() })
        .setDescription(list.length ? `${counts}\n\n${pages[p].map((s) => `**#${s.id}** ${LABEL[s.type] ?? s.type} — ${ts(s.date)}\n> par <@${s.modId}>${s.duration ? ` • ${formatDuration(s.duration)}` : ''}\n> ${ui.truncate(s.reason || 'Aucune raison', 150)}`).join('\n')}` : `${ui.E.ok} Aucune sanction.`));
    }
    if (sub === 'supprimer') {
      const n = interaction.options.getInteger('numero', true);
      for (const [uid, list] of Object.entries(g.sanctions)) {
        const i = list.findIndex((s) => s.id === n);
        if (i !== -1) {
          list.splice(i, 1);
          db.save();
          return interaction.reply({ embeds: [ui.success(`Sanction **#${n}** de <@${uid}> supprimée.`)] });
        }
      }
      return interaction.reply({ embeds: [ui.error(`Aucune sanction #${n}.`)], flags: 64 });
    }
    if (sub === 'effacer') {
      const user = interaction.options.getUser('membre', true);
      const n = g.sanctions[user.id]?.length ?? 0;
      delete g.sanctions[user.id];
      db.save();
      return interaction.reply({ embeds: [ui.success(`**${n}** sanction(s) de ${user} supprimée(s).`)] });
    }
    if (!isTrusted(interaction.guild, interaction.user.id)) return interaction.reply({ embeds: [ui.error('Réservé au propriétaire du serveur.')], flags: 64 });
    g.sanctions = {};
    db.save();
    await interaction.reply({ embeds: [ui.success('Toutes les sanctions du serveur ont été supprimées.')] });
  },
};
