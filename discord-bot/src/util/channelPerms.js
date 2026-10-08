// Verrouillage / masquage de salons pour /lock /unlock /hide /unhide.
const { ChannelType, SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('./ui');
const { modLog } = require('./logs');
const { isTrusted } = require('./perms');

const MODES = {
  lock: { perms: ['SendMessages', 'SendMessagesInThreads', 'CreatePublicThreads', 'AddReactions', 'Speak'], value: false, verb: 'verrouillé', emoji: ui.E.lock, desc: 'Ferme un salon, une catégorie ou tout le serveur' },
  unlock: { perms: ['SendMessages', 'SendMessagesInThreads', 'CreatePublicThreads', 'AddReactions', 'Speak'], value: null, verb: 'déverrouillé', emoji: ui.E.unlock, desc: 'Rouvre un salon, une catégorie ou tout le serveur' },
  hide: { perms: ['ViewChannel'], value: false, verb: 'caché', emoji: '🙈', desc: 'Cache un salon, une catégorie ou tout le serveur' },
  unhide: { perms: ['ViewChannel'], value: null, verb: 'affiché', emoji: '👁️', desc: 'Ré-affiche un salon, une catégorie ou tout le serveur' },
};

async function apply(channel, mode, reason) {
  const everyone = channel.guild.roles.everyone;
  const overwrite = Object.fromEntries(MODES[mode].perms.map((p) => [p, MODES[mode].value]));
  await channel.permissionOverwrites.edit(everyone, overwrite, { reason });
}

function build(mode) {
  const m = MODES[mode];
  return {
    category: 'Modération',
    data: new SlashCommandBuilder()
      .setName(mode)
      .setDescription(m.desc)
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageChannels)
      .addChannelOption((o) => o.setName('salon').setDescription('Salon ou catégorie (vide = salon actuel)')
        .addChannelTypes(ChannelType.GuildText, ChannelType.GuildVoice, ChannelType.GuildCategory, ChannelType.GuildAnnouncement, ChannelType.GuildForum, ChannelType.GuildStageVoice))
      .addBooleanOption((o) => o.setName('tout').setDescription('Appliquer à TOUS les salons du serveur'))
      .addStringOption((o) => o.setName('raison').setDescription('Raison')),
    async run(interaction) {
      const reason = `${interaction.user.tag} : ${interaction.options.getString('raison') || `${mode}`}`;
      let targets;
      if (interaction.options.getBoolean('tout')) {
        if (!isTrusted(interaction.guild, interaction.user.id) && !interaction.member.permissions.has(PermissionFlagsBits.Administrator))
          return interaction.reply({ embeds: [ui.error('L’option `tout` est réservée aux administrateurs.')], flags: 64 });
        targets = [...interaction.guild.channels.cache.filter((c) => !c.isThread()).values()];
      } else {
        const ch = interaction.options.getChannel('salon') ?? interaction.channel;
        targets = [ch];
        if (ch.type === ChannelType.GuildCategory) targets.push(...ch.children.cache.values());
      }
      await interaction.deferReply();
      let ok = 0;
      for (const ch of targets) {
        try { await apply(ch, mode, reason); ok++; } catch {}
      }
      await modLog(interaction.guild, { action: mode, moderator: interaction.user, extra: `${m.emoji} **${ok}** salon(s) ${m.verb}(s) : ${targets.length > 5 ? `${targets.slice(0, 5).join(', ')}…` : targets.join(', ')}` });
      await interaction.editReply({ embeds: [ui.embed(interaction.guild).setDescription(`${m.emoji} **${ok}** salon(s) ${m.verb}(s)${targets.length === 1 ? ` : ${targets[0]}` : ''}.`)] });
    },
  };
}

module.exports = { build };
