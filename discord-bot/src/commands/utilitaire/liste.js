const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { paginate, chunk } = require('../../util/paginate');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('liste').setDescription('Listes de membres')
    .addStringOption((o) => o.setName('type').setDescription('Quoi lister').setRequired(true).addChoices(
      { name: 'Administrateurs', value: 'admins' }, { name: 'Bots', value: 'bots' }, { name: 'Boosters', value: 'boosters' },
      { name: 'Bots avec permissions dangereuses', value: 'botadmins' }, { name: 'Membres en vocal', value: 'voice' },
    )),
  async run(interaction) {
    await interaction.deferReply();
    const members = await interaction.guild.members.fetch();
    const type = interaction.options.getString('type', true);
    const filters = {
      admins: [(m) => !m.user.bot && m.permissions.has(PermissionFlagsBits.Administrator), '👑 Administrateurs', (m) => `${m}`],
      bots: [(m) => m.user.bot, '🤖 Bots', (m) => `${m} \`${m.id}\``],
      boosters: [(m) => m.premiumSince, '💎 Boosters', (m) => `${m} — depuis ${ts(m.premiumSince)}`],
      botadmins: [(m) => m.user.bot && (m.permissions.has(PermissionFlagsBits.Administrator) || m.permissions.has(PermissionFlagsBits.BanMembers) || m.permissions.has(PermissionFlagsBits.ManageRoles)), '⚠️ Bots à permissions dangereuses', (m) => `${m} — ${m.permissions.has(PermissionFlagsBits.Administrator) ? 'Administrateur' : 'Ban/Rôles'}`],
      voice: [(m) => m.voice.channelId, '🔊 En vocal', (m) => `${m} — ${m.voice.channel}`],
    };
    const [fn, title, fmt] = filters[type];
    const list = [...members.filter(fn).values()];
    const pages = chunk(list, 20);
    await paginate(interaction, Math.max(1, pages.length), (p) => ui.embed(interaction.guild).setTitle(`${title} (${list.length})`).setDescription(list.length ? pages[p].map(fmt).join('\n') : 'Personne.'));
  },
};
