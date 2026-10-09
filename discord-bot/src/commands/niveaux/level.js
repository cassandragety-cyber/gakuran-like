const { SlashCommandBuilder, AttachmentBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { xpFor, rankOf } = require('../../modules/leveling');
const { rankCard } = require('../../util/cards');

module.exports = {
  category: 'Niveaux',
  data: new SlashCommandBuilder()
    .setName('level')
    .setDescription('Affiche la carte de niveau d’un membre')
    .addUserOption((o) => o.setName('membre').setDescription('Membre')),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    if (!g.leveling.enabled) return interaction.reply({ embeds: [ui.error('Les niveaux sont désactivés (`/leveling on`).')], flags: 64 });
    const user = interaction.options.getUser('membre') ?? interaction.user;
    const u = g.leveling.users[user.id] ?? { xp: 0, level: 0 };
    await interaction.deferReply();
    const buf = await rankCard({ avatarURL: user.displayAvatarURL({ extension: 'png', size: 256 }), username: user.username, level: u.level, xp: u.xp, needed: xpFor(u.level), rank: rankOf(g, user.id), color: ui.colorFor(interaction.guild) });
    await interaction.editReply({ files: [new AttachmentBuilder(buf, { name: 'niveau.png' })] });
  },
};
