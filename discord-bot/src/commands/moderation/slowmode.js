const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const ui = require('../../util/ui');
const { parseDuration, formatDuration } = require('../../util/time');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('slowmode')
    .setDescription('Change le mode lent d’un salon')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageChannels)
    .addStringOption((o) => o.setName('duree').setDescription('Ex : 5s, 1m, 2h (0 = désactiver, 6h max)').setRequired(true))
    .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildVoice, ChannelType.GuildForum)),
  async run(interaction) {
    const raw = interaction.options.getString('duree', true);
    const ms = raw === '0' || raw === 'off' ? 0 : parseDuration(/^\d+$/.test(raw) ? `${raw}s` : raw);
    if (ms === null || ms > 6 * 3600e3) return interaction.reply({ embeds: [ui.error('Durée invalide (6 heures maximum).')], flags: 64 });
    const ch = interaction.options.getChannel('salon') ?? interaction.channel;
    await ch.setRateLimitPerUser(Math.round(ms / 1000), `par ${interaction.user.tag}`);
    await interaction.reply({ embeds: [ui.success(ms ? `🐢 Mode lent de **${formatDuration(ms)}** sur ${ch}.` : `Mode lent désactivé sur ${ch}.`)] });
  },
};
