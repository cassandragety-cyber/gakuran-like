const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('renew')
    .setDescription('Supprime et recrée un salon à l’identique (vide tous ses messages)')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageChannels)
    .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement)),
  async run(interaction) {
    const ch = interaction.options.getChannel('salon') ?? interaction.channel;
    const clone = await ch.clone({ reason: `renew par ${interaction.user.tag}` });
    await clone.setPosition(ch.position);
    await ch.delete(`renew par ${interaction.user.tag}`);
    await clone.send({ embeds: [ui.embed(interaction.guild).setDescription(`♻️ Salon recréé par ${interaction.user}.`)] });
    if (ch.id !== interaction.channelId) await interaction.reply({ embeds: [ui.success(`Salon recréé : ${clone}`)], flags: 64 });
  },
};
