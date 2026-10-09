const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { LABELS, PUNISHMENTS } = require('../../modules/antiraid');

const moduleChoices = () => db.ANTIRAID_MODULES.map((m) => ({ name: `${m} — ${LABELS[m]}`.slice(0, 100), value: m }));

module.exports = {
  category: 'Sécurité',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('antiraid')
    .setDescription('Configure un module antiraid précis')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((s) => s.setName('module').setDescription('Active / désactive un module')
      .addStringOption((o) => o.setName('module').setDescription('Module').setRequired(true).addChoices(...moduleChoices()))
      .addStringOption((o) => o.setName('etat').setDescription('État').setRequired(true).addChoices({ name: 'on', value: 'on' }, { name: 'max (ignore la whitelist)', value: 'max' }, { name: 'off', value: 'off' }))
      .addIntegerOption((o) => o.setName('nombre').setDescription('Limite : nombre d’actions autorisées (modules à limite)').setMinValue(1).setMaxValue(100))
      .addIntegerOption((o) => o.setName('secondes').setDescription('Limite : sur combien de secondes').setMinValue(1).setMaxValue(3600)))
    .addSubcommand((s) => s.setName('punition').setDescription('Sanction appliquée à l’auteur d’un raid')
      .addStringOption((o) => o.setName('module').setDescription('Module (ou « tous »)').setRequired(true).addChoices({ name: 'tous les modules', value: 'all' }, ...moduleChoices().slice(0, 24)))
      .addStringOption((o) => o.setName('sanction').setDescription('Sanction').setRequired(true).addChoices(
        { name: 'derank (retire tous ses rôles)', value: 'derank' }, { name: 'derank + mute 1h', value: 'derank_timeout' },
        { name: 'kick', value: 'kick' }, { name: 'ban', value: 'ban' },
      ))),
  async run(interaction) {
    const sec = db.guild(interaction.guild.id).security;
    const module = interaction.options.getString('module', true);
    if (interaction.options.getSubcommand() === 'punition') {
      const p = interaction.options.getString('sanction', true);
      if (!PUNISHMENTS.includes(p)) return;
      if (module === 'all') sec.punish = { default: p };
      else sec.punish[module] = p;
      db.save();
      return interaction.reply({ embeds: [ui.success(`Sanction **${p.replace('_', ' + ')}** pour ${module === 'all' ? '**tous les modules**' : `**${module}**`}.`)] });
    }
    const state = interaction.options.getString('etat', true);
    sec.modules[module] = state;
    const n = interaction.options.getInteger('nombre');
    const w = interaction.options.getInteger('secondes');
    if ((n || w) && sec.limits[module]) sec.limits[module] = { count: n ?? sec.limits[module].count, window: w ?? sec.limits[module].window };
    db.save();
    const lim = sec.limits[module];
    await interaction.reply({ embeds: [ui.success(`${ui.E.shield} **${module}** (${LABELS[module]}) → **${state}**${lim ? ` • limite \`${lim.count} action(s) / ${lim.window}s\`` : ''}`)] });
  },
};
