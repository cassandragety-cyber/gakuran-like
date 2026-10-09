const { SlashCommandBuilder, ChannelType } = require('discord.js');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('serverinfo').setDescription('Informations et statistiques du serveur'),
  async run(interaction) {
    const g = interaction.guild;
    await g.members.fetch().catch(() => {});
    const c = g.channels.cache;
    const humans = g.members.cache.filter((m) => !m.user.bot).size;
    const inVoice = g.voiceStates.cache.filter((v) => v.channelId).size;
    const e = ui.embed(g).setTitle(g.name).setThumbnail(g.iconURL({ size: 512 }))
      .addFields(
        { name: '👑 Propriétaire', value: `<@${g.ownerId}>`, inline: true },
        { name: '📅 Créé', value: ts(g.createdAt, 'D'), inline: true },
        { name: '🆔 ID', value: `\`${g.id}\``, inline: true },
        { name: '👥 Membres', value: `${g.memberCount} (👤 ${humans} • 🤖 ${g.memberCount - humans})`, inline: true },
        { name: '🔊 En vocal', value: String(inVoice), inline: true },
        { name: '💎 Boosts', value: `${g.premiumSubscriptionCount} (niveau ${g.premiumTier})`, inline: true },
        { name: '💬 Salons', value: `${c.filter((x) => x.type === ChannelType.GuildText).size} texte • ${c.filter((x) => x.type === ChannelType.GuildVoice).size} vocal • ${c.filter((x) => x.type === ChannelType.GuildCategory).size} catégories`, inline: true },
        { name: '🎭 Rôles', value: String(g.roles.cache.size - 1), inline: true },
        { name: '😀 Émojis', value: String(g.emojis.cache.size), inline: true },
      );
    if (g.vanityURLCode) e.addFields({ name: '🔗 URL', value: `discord.gg/${g.vanityURLCode}`, inline: true });
    if (g.bannerURL()) e.setImage(g.bannerURL({ size: 1024 }));
    await interaction.reply({ embeds: [e] });
  },
};
