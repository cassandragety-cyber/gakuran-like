const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { modLog } = require('../../util/logs');
const { addSanction } = require('../../util/sanctions');

module.exports = {
  category: 'Modération',
  data: new SlashCommandBuilder()
    .setName('cmute')
    .setDescription('Mute un membre dans un seul salon')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageChannels)
    .addSubcommand((s) => s.setName('ajouter').setDescription('Mute un membre dans un salon')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildVoice, ChannelType.GuildAnnouncement))
      .addStringOption((o) => o.setName('raison').setDescription('Raison')))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire le mute salon')
      .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildVoice, ChannelType.GuildAnnouncement))),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    const channel = interaction.options.getChannel('salon') ?? interaction.channel;
    if (!member) return interaction.reply({ embeds: [ui.error('Membre introuvable.')], flags: 64 });
    const g = db.guild(interaction.guild.id);
    const list = (g.cmutes[channel.id] ??= []);
    if (interaction.options.getSubcommand() === 'retirer') {
      await channel.permissionOverwrites.delete(member, `uncmute par ${interaction.user.tag}`).catch(() => {});
      g.cmutes[channel.id] = list.filter((id) => id !== member.id);
      db.save();
      return interaction.reply({ embeds: [ui.success(`${member} peut de nouveau parler dans ${channel}.`)] });
    }
    const err = checkHierarchy(interaction, member, 'mute');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    const reason = interaction.options.getString('raison');
    await channel.permissionOverwrites.edit(member, { SendMessages: false, AddReactions: false, Speak: false, SendMessagesInThreads: false }, { reason: `cmute par ${interaction.user.tag}` });
    if (!list.includes(member.id)) list.push(member.id);
    const id = addSanction(interaction.guild.id, member.id, { type: 'cmute', reason, modId: interaction.user.id });
    db.save();
    await modLog(interaction.guild, { action: 'cmute', target: member.user, moderator: interaction.user, reason, id, extra: `**Salon :** ${channel}` });
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setDescription(`${ui.E.mute} ${member} est muet dans ${channel}.`)] });
  },
};
