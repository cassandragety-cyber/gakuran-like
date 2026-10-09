const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('vocal')
    .setDescription('Gestion des membres en vocal')
    .setDefaultMemberPermissions(PermissionFlagsBits.MoveMembers)
    .addSubcommand((s) => s.setName('kick').setDescription('Déconnecte un membre du vocal').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('deplacer').setDescription('Déplace tous les membres de ton vocal vers un autre')
      .addChannelOption((o) => o.setName('salon').setDescription('Destination').setRequired(true).addChannelTypes(ChannelType.GuildVoice, ChannelType.GuildStageVoice)))
    .addSubcommand((s) => s.setName('rassembler').setDescription('Ramène TOUS les membres en vocal du serveur dans un salon')
      .addChannelOption((o) => o.setName('salon').setDescription('Destination (vide = ton vocal)').addChannelTypes(ChannelType.GuildVoice, ChannelType.GuildStageVoice)))
    .addSubcommand((s) => s.setName('vider').setDescription('Déconnecte tout le monde d’un salon vocal')
      .addChannelOption((o) => o.setName('salon').setDescription('Salon').setRequired(true).addChannelTypes(ChannelType.GuildVoice, ChannelType.GuildStageVoice))),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    if (sub === 'kick') {
      const m = interaction.options.getMember('membre');
      if (!m?.voice.channel) return interaction.reply({ embeds: [ui.error('Ce membre n’est pas en vocal.')], flags: 64 });
      await m.voice.disconnect(`par ${interaction.user.tag}`);
      return interaction.reply({ embeds: [ui.success(`${m} a été déconnecté du vocal.`)] });
    }
    await interaction.deferReply();
    let members;
    let dest = interaction.options.getChannel('salon');
    if (sub === 'deplacer') {
      const from = interaction.member.voice.channel;
      if (!from) return interaction.editReply({ embeds: [ui.error('Tu dois être en vocal.')] });
      members = [...from.members.values()];
    } else if (sub === 'rassembler') {
      dest ??= interaction.member.voice.channel;
      if (!dest) return interaction.editReply({ embeds: [ui.error('Précise un salon ou rejoins un vocal.')] });
      members = [...interaction.guild.voiceStates.cache.filter((v) => v.channelId && v.channelId !== dest.id).map((v) => v.member).filter(Boolean)];
    } else {
      members = [...dest.members.values()];
      dest = null;
    }
    let n = 0;
    for (const m of members) await m.voice.setChannel(dest, `par ${interaction.user.tag}`).then(() => n++).catch(() => {});
    await interaction.editReply({ embeds: [ui.success(`**${n}** membre(s) ${dest ? `déplacé(s) vers ${dest}` : 'déconnecté(s)'}.`)] });
  },
};
