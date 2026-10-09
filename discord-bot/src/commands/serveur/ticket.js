const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const tickets = require('../../modules/tickets');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('ticket')
    .setDescription('Système de tickets')
    .addSubcommand((s) => s.setName('setup').setDescription('Envoie le panneau de tickets')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon du panneau (vide = actuel)').addChannelTypes(ChannelType.GuildText))
      .addRoleOption((o) => o.setName('staff').setDescription('Rôle staff qui voit les tickets'))
      .addChannelOption((o) => o.setName('categorie').setDescription('Catégorie où créer les tickets').addChannelTypes(ChannelType.GuildCategory))
      .addStringOption((o) => o.setName('titre').setDescription('Titre du panneau'))
      .addStringOption((o) => o.setName('description').setDescription('Texte du panneau')))
    .addSubcommand((s) => s.setName('fermer').setDescription('Ferme le ticket actuel').addStringOption((o) => o.setName('raison').setDescription('Raison')))
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute un membre au ticket').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire un membre du ticket').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('renommer').setDescription('Renomme le ticket').addStringOption((o) => o.setName('nom').setDescription('Nouveau nom').setRequired(true).setMaxLength(90)))
    .addSubcommand((s) => s.setName('claim').setDescription('Prend en charge le ticket')),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    const t = db.guild(interaction.guild.id).tickets;
    if (sub === 'setup') {
      if (!interaction.member.permissions.has(PermissionFlagsBits.ManageGuild)) return interaction.reply({ embeds: [ui.error('Permission « Gérer le serveur » requise.')], flags: 64 });
      const ch = interaction.options.getChannel('salon') ?? interaction.channel;
      t.staffRole = interaction.options.getRole('staff')?.id ?? t.staffRole;
      t.category = interaction.options.getChannel('categorie')?.id ?? t.category;
      db.save();
      await ch.send(tickets.panelPayload(interaction.guild, { title: interaction.options.getString('titre'), description: interaction.options.getString('description') }));
      return interaction.reply({ embeds: [ui.success(`Panneau de tickets envoyé dans ${ch}.`)], flags: 64 });
    }
    const info = t.open[interaction.channelId];
    if (!info) return interaction.reply({ embeds: [ui.error('Cette commande s’utilise dans un ticket.')], flags: 64 });
    if (sub === 'fermer') {
      if (!tickets.isStaff(interaction.member, t) && interaction.user.id !== info.owner) return interaction.reply({ embeds: [ui.error('Tu ne peux pas fermer ce ticket.')], flags: 64 });
      return tickets.close(interaction, interaction.options.getString('raison'));
    }
    if (!tickets.isStaff(interaction.member, t)) return interaction.reply({ embeds: [ui.error('Réservé au staff.')], flags: 64 });
    if (sub === 'claim') {
      info.claimedBy = interaction.user.id;
      db.save();
      return interaction.reply({ embeds: [ui.info(`🙋 ${interaction.user} prend en charge ce ticket.`, interaction.guild)] });
    }
    if (sub === 'renommer') {
      await interaction.channel.setName(`🎫・${interaction.options.getString('nom', true)}`);
      return interaction.reply({ embeds: [ui.success('Ticket renommé.')] });
    }
    const user = interaction.options.getUser('membre', true);
    if (sub === 'ajouter') await interaction.channel.permissionOverwrites.edit(user, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true });
    else await interaction.channel.permissionOverwrites.delete(user);
    await interaction.reply({ embeds: [ui.success(`${user} ${sub === 'ajouter' ? 'ajouté au' : 'retiré du'} ticket.`)] });
  },
};
