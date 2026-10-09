const { SlashCommandBuilder, PermissionFlagsBits, ChannelType, AttachmentBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { VARS_HELP } = require('../../modules/welcome');
const { welcomeCard } = require('../../util/cards');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('bienvenue')
    .setDescription('Messages d’arrivée, de départ et rôles automatiques')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('arrivee').setDescription('Configure le message d’arrivée')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = désactiver)').addChannelTypes(ChannelType.GuildText))
      .addStringOption((o) => o.setName('message').setDescription('Message (variables : {user} {server} {count} {inviter} {invites})').setMaxLength(1500))
      .addBooleanOption((o) => o.setName('carte').setDescription('Afficher la carte de bienvenue (image)'))
      .addStringOption((o) => o.setName('mp').setDescription('Message privé envoyé à l’arrivée (« off » pour désactiver)').setMaxLength(1500)))
    .addSubcommand((s) => s.setName('depart').setDescription('Configure le message de départ')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = désactiver)').addChannelTypes(ChannelType.GuildText))
      .addStringOption((o) => o.setName('message').setDescription('Message').setMaxLength(1500)))
    .addSubcommand((s) => s.setName('autorole').setDescription('Ajoute/retire un rôle donné automatiquement à l’arrivée')
      .addRoleOption((o) => o.setName('role').setDescription('Rôle').setRequired(true)))
    .addSubcommand((s) => s.setName('test').setDescription('Aperçu du message d’arrivée'))
    .addSubcommand((s) => s.setName('voir').setDescription('Configuration actuelle')),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'arrivee' || sub === 'depart') {
      const cfg = sub === 'arrivee' ? g.welcome : g.leave;
      cfg.channel = interaction.options.getChannel('salon')?.id ?? null;
      const msg = interaction.options.getString('message');
      if (msg) cfg.message = msg;
      if (sub === 'arrivee') {
        const card = interaction.options.getBoolean('carte');
        if (card !== null) cfg.card = card;
        const dm = interaction.options.getString('mp');
        if (dm) cfg.dm = dm.toLowerCase() === 'off' ? null : dm;
      }
      db.save();
      return interaction.reply({ embeds: [ui.success(`Message ${sub === 'arrivee' ? 'd’arrivée' : 'de départ'} : ${cfg.channel ? `<#${cfg.channel}>` : 'désactivé'}.\nVariables : ${VARS_HELP}`)] });
    }
    if (sub === 'autorole') {
      const role = interaction.options.getRole('role', true);
      const i = g.welcome.autoroles.indexOf(role.id);
      if (i === -1) {
        const { roleError } = require('../moderation/role');
        const err = roleError(interaction, role);
        if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
        g.welcome.autoroles.push(role.id);
      } else g.welcome.autoroles.splice(i, 1);
      db.save();
      return interaction.reply({ embeds: [ui.success(`Rôles automatiques : ${g.welcome.autoroles.map((r) => `<@&${r}>`).join(', ') || 'aucun'}`)] });
    }
    if (sub === 'test') {
      await interaction.deferReply();
      const buf = await welcomeCard({ avatarURL: interaction.user.displayAvatarURL({ extension: 'png', size: 256 }), username: interaction.user.username, guildName: interaction.guild.name, memberCount: interaction.guild.memberCount, color: ui.colorFor(interaction.guild) });
      return interaction.editReply({ embeds: [ui.embed(interaction.guild).setDescription('Aperçu de la carte de bienvenue :').setImage('attachment://bienvenue.png')], files: [new AttachmentBuilder(buf, { name: 'bienvenue.png' })] });
    }
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('👋 Bienvenue / départ').addFields(
      { name: 'Arrivée', value: `${g.welcome.channel ? `<#${g.welcome.channel}>` : 'désactivée'}\n${g.welcome.message ?? '*message par défaut*'}`.slice(0, 1024) },
      { name: 'Carte', value: g.welcome.card ? 'oui' : 'non', inline: true },
      { name: 'MP', value: g.welcome.dm ? 'oui' : 'non', inline: true },
      { name: 'Autorôles', value: g.welcome.autoroles.map((r) => `<@&${r}>`).join(', ') || 'aucun', inline: true },
      { name: 'Départ', value: `${g.leave.channel ? `<#${g.leave.channel}>` : 'désactivé'}\n${g.leave.message ?? '*message par défaut*'}`.slice(0, 1024) },
    )] });
  },
};
