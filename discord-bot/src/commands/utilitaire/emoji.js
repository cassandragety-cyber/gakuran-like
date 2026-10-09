const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('emoji').setDescription('Émojis')
    .addSubcommand((s) => s.setName('image').setDescription('Récupère l’image d’un émoji').addStringOption((o) => o.setName('emoji').setDescription('Émoji personnalisé').setRequired(true)))
    .addSubcommand((s) => s.setName('voler').setDescription('Ajoute un émoji d’un autre serveur à celui-ci')
      .addStringOption((o) => o.setName('emoji').setDescription('Émoji personnalisé ou lien d’image').setRequired(true))
      .addStringOption((o) => o.setName('nom').setDescription('Nom').setMaxLength(32))),
  async run(interaction) {
    const raw = interaction.options.getString('emoji', true);
    const m = raw.match(/<(a?):(\w+):(\d+)>/);
    const url = m ? `https://cdn.discordapp.com/emojis/${m[3]}.${m[1] ? 'gif' : 'png'}?size=128` : /^https?:\/\//.test(raw) ? raw : null;
    if (!url) return interaction.reply({ embeds: [ui.error('Donne un émoji personnalisé (pas un émoji Unicode) ou un lien d’image.')], flags: 64 });
    if (interaction.options.getSubcommand() === 'image') return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(m?.[2] ?? 'Émoji').setImage(url.replace('size=128', 'size=512'))] });
    if (!interaction.member.permissions.has(PermissionFlagsBits.ManageGuildExpressions)) return interaction.reply({ embeds: [ui.error('Permission « Gérer les expressions » requise.')], flags: 64 });
    const name = (interaction.options.getString('nom') ?? m?.[2] ?? 'emoji').replace(/[^\w]/g, '_');
    const emoji = await interaction.guild.emojis.create({ attachment: url, name, reason: `par ${interaction.user.tag}` });
    await interaction.reply({ embeds: [ui.success(`Émoji ajouté : ${emoji} \`:${emoji.name}:\``)] });
  },
};
