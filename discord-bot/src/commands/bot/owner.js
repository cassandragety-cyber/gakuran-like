const { SlashCommandBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const config = require('../../config');
const { isBuyer } = require('../../util/perms');

module.exports = {
  category: 'Bot',
  access: 'owner',
  data: new SlashCommandBuilder()
    .setName('owner')
    .setDescription('Owners du bot (accès à la sécurité sur tous les serveurs)')
    .addSubcommand((s) => s.setName('ajouter').setDescription('Ajoute un owner (buyers uniquement)').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire un owner (buyers uniquement)').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('liste').setDescription('Liste des buyers et owners'))
    .addSubcommand((s) => s.setName('blbot').setDescription('Empêche/autorise un utilisateur à utiliser le bot').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    const g = db.global;
    if (sub === 'liste') {
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`${ui.E.crown} Hiérarchie du bot`).addFields(
        { name: 'Buyers (.env)', value: config.ownerIds.map((id) => `<@${id}>`).join('\n') || 'aucun' },
        { name: 'Owners', value: g.owners.map((id) => `<@${id}>`).join('\n') || 'aucun' },
        { name: 'Blacklist bot', value: g.blbot.map((id) => `<@${id}>`).join('\n').slice(0, 1024) || 'aucun' },
      )] });
    }
    const user = interaction.options.getUser('membre', true);
    if (sub === 'blbot') {
      if (isBuyer(user.id)) return interaction.reply({ embeds: [ui.error('Impossible de blacklister un buyer.')], flags: 64 });
      const i = g.blbot.indexOf(user.id);
      if (i === -1) g.blbot.push(user.id);
      else g.blbot.splice(i, 1);
      db.save();
      return interaction.reply({ embeds: [ui.success(`${user} ${i === -1 ? 'ne peut plus' : 'peut de nouveau'} utiliser le bot.`)] });
    }
    if (!isBuyer(interaction.user.id)) return interaction.reply({ embeds: [ui.error('Seuls les buyers peuvent gérer les owners.')], flags: 64 });
    if (sub === 'ajouter' && !g.owners.includes(user.id)) g.owners.push(user.id);
    if (sub === 'retirer') g.owners = g.owners.filter((id) => id !== user.id);
    db.save();
    await interaction.reply({ embeds: [ui.success(`${user} ${sub === 'ajouter' ? 'est maintenant' : 'n’est plus'} owner du bot.`)] });
  },
};
