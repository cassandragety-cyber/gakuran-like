const { SlashCommandBuilder } = require('discord.js');
const ui = require('../../util/ui');
const { evaluate } = require('../../util/calc');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('calc').setDescription('Calculatrice (+ - * / ^ %, sqrt, sin, cos, log, pi…)')
    .addStringOption((o) => o.setName('expression').setDescription('Ex : (2+3)^2 / sqrt(16)').setRequired(true).setMaxLength(200)),
  async run(interaction) {
    const expr = interaction.options.getString('expression', true);
    try {
      const r = evaluate(expr);
      if (!Number.isFinite(r)) throw new Error('résultat non fini');
      await interaction.reply({ embeds: [ui.embed(interaction.guild).setDescription(`🧮 \`${expr}\`\n= **${Number(r.toPrecision(12)).toLocaleString('fr-FR', { maximumFractionDigits: 10 })}**`)] });
    } catch (err) {
      await interaction.reply({ embeds: [ui.error(`Expression invalide : ${err.message}`)], flags: 64 });
    }
  },
};
