const { SlashCommandBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('userinfo').setDescription('Informations sur un utilisateur')
    .addUserOption((o) => o.setName('membre').setDescription('Membre')),
  async run(interaction) {
    const user = await (interaction.options.getUser('membre') ?? interaction.user).fetch();
    const member = await interaction.guild.members.fetch(user.id).catch(() => null);
    const sanctions = db.guild(interaction.guild.id).sanctions[user.id]?.length ?? 0;
    const e = ui.embed(interaction.guild).setAuthor({ name: user.tag, iconURL: user.displayAvatarURL() }).setThumbnail(user.displayAvatarURL({ size: 512 }))
      .addFields(
        { name: '🆔 ID', value: `\`${user.id}\``, inline: true },
        { name: '🤖 Bot', value: user.bot ? 'oui' : 'non', inline: true },
        { name: '⚖️ Sanctions', value: String(sanctions), inline: true },
        { name: '📅 Compte créé', value: `${ts(user.createdAt, 'D')} (${ts(user.createdAt)})`, inline: true },
      );
    if (member) {
      e.addFields(
        { name: '📥 A rejoint', value: `${ts(member.joinedAt, 'D')} (${ts(member.joinedAt)})`, inline: true },
        { name: '💎 Boost', value: member.premiumSince ? ts(member.premiumSince) : 'non', inline: true },
        { name: `🎭 Rôles (${member.roles.cache.size - 1})`, value: member.roles.cache.filter((r) => r.id !== interaction.guild.id).sort((a, b) => b.position - a.position).map((r) => `${r}`).join(' ').slice(0, 1024) || 'aucun' },
      );
      if (member.isCommunicationDisabled()) e.addFields({ name: '🔇 Muet', value: `jusqu’à ${ts(member.communicationDisabledUntil)}` });
    }
    if (user.banner) e.setImage(user.bannerURL({ size: 1024 }));
    await interaction.reply({ embeds: [e] });
  },
};
