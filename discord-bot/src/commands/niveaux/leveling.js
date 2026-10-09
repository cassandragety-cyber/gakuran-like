const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { addXp, applyRewards } = require('../../modules/leveling');

module.exports = {
  category: 'Niveaux',
  data: new SlashCommandBuilder()
    .setName('leveling')
    .setDescription('Configuration des niveaux')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('on').setDescription('Active les niveaux'))
    .addSubcommand((s) => s.setName('off').setDescription('Désactive les niveaux'))
    .addSubcommand((s) => s.setName('salon').setDescription('Salon des annonces de niveau (vide = salon du message)')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon').addChannelTypes(ChannelType.GuildText)))
    .addSubcommand((s) => s.setName('recompense').setDescription('Rôle donné à un niveau (re-faire pour retirer)')
      .addIntegerOption((o) => o.setName('niveau').setDescription('Niveau').setRequired(true).setMinValue(1).setMaxValue(500))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle').setRequired(true)))
    .addSubcommand((s) => s.setName('recompenses').setDescription('Liste des rôles récompenses'))
    .addSubcommand((s) => s.setName('xp').setDescription('Ajoute ou retire de l’XP')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addIntegerOption((o) => o.setName('nombre').setDescription('Nombre (négatif pour retirer)').setRequired(true)))
    .addSubcommand((s) => s.setName('reset').setDescription('Remet l’XP à zéro')
      .addUserOption((o) => o.setName('membre').setDescription('Membre (vide = tout le serveur)'))),
  async run(interaction) {
    const lv = db.guild(interaction.guild.id).leveling;
    const sub = interaction.options.getSubcommand();
    const ok = (t) => { db.save(); return interaction.reply({ embeds: [ui.success(t)] }); };
    if (sub === 'on' || sub === 'off') { lv.enabled = sub === 'on'; return ok(`Niveaux **${sub === 'on' ? 'activés' : 'désactivés'}**.`); }
    if (sub === 'salon') { lv.channel = interaction.options.getChannel('salon')?.id ?? null; return ok(`Annonces de niveau : ${lv.channel ? `<#${lv.channel}>` : 'dans le salon du message'}.`); }
    if (sub === 'recompense') {
      const n = interaction.options.getInteger('niveau', true);
      const role = interaction.options.getRole('role', true);
      if (lv.rewards[n] === role.id) { delete lv.rewards[n]; return ok(`Récompense du niveau ${n} retirée.`); }
      lv.rewards[n] = role.id;
      return ok(`${role} sera donné au niveau **${n}**.`);
    }
    if (sub === 'recompenses') return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('🎁 Récompenses').setDescription(Object.entries(lv.rewards).sort((a, b) => a[0] - b[0]).map(([n, r]) => `Niveau **${n}** → <@&${r}>`).join('\n') || 'Aucune.')] });
    if (sub === 'xp') {
      const member = interaction.options.getMember('membre');
      const { u } = addXp(db.guild(interaction.guild.id), member.id, interaction.options.getInteger('nombre', true));
      if (member) await applyRewards(member, u.level);
      return ok(`${member} est maintenant niveau **${u.level}** (${u.xp} xp).`);
    }
    const user = interaction.options.getUser('membre');
    if (user) delete lv.users[user.id];
    else lv.users = {};
    return ok(user ? `XP de ${user} remise à zéro.` : 'XP de tout le serveur remise à zéro.');
  },
};
