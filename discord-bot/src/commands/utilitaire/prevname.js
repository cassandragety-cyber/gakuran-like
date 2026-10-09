const { SlashCommandBuilder } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { ts } = require('../../util/time');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('prevname').setDescription('Anciens pseudos d’un membre')
    .addUserOption((o) => o.setName('membre').setDescription('Membre'))
    .addBooleanOption((o) => o.setName('effacer').setDescription('Effacer TES anciens pseudos')),
  async run(interaction) {
    if (interaction.options.getBoolean('effacer')) {
      delete db.global.prevnames[interaction.user.id];
      db.save();
      return interaction.reply({ embeds: [ui.success('Tes anciens pseudos ont été effacés.')], flags: 64 });
    }
    const user = interaction.options.getUser('membre') ?? interaction.user;
    const list = db.global.prevnames[user.id] ?? [];
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setAuthor({ name: `Anciens pseudos de ${user.username}`, iconURL: user.displayAvatarURL() })
      .setDescription(list.map((p) => `${ui.E.dot} **${p.name}** — ${ts(p.date)}`).join('\n') || 'Aucun pseudo enregistré.')] });
  },
};
