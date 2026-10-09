const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { parseDuration } = require('../../util/time');
const gws = require('../../modules/giveaways');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('giveaway')
    .setDescription('Giveaways')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('lancer').setDescription('Lance un giveaway')
      .addStringOption((o) => o.setName('prix').setDescription('Ce qu’on gagne').setRequired(true).setMaxLength(200))
      .addStringOption((o) => o.setName('duree').setDescription('Ex : 1h, 2j').setRequired(true))
      .addIntegerOption((o) => o.setName('gagnants').setDescription('Nombre de gagnants').setMinValue(1).setMaxValue(20))
      .addChannelOption((o) => o.setName('salon').setDescription('Salon (vide = actuel)').addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
      .addRoleOption((o) => o.setName('role_requis').setDescription('Rôle nécessaire pour participer')))
    .addSubcommand((s) => s.setName('terminer').setDescription('Termine un giveaway maintenant').addStringOption((o) => o.setName('message').setDescription('ID du message du giveaway').setRequired(true)))
    .addSubcommand((s) => s.setName('reroll').setDescription('Relance le tirage').addStringOption((o) => o.setName('message').setDescription('ID du message (vide = dernier)')))
    .addSubcommand((s) => s.setName('participants').setDescription('Liste des participants').addStringOption((o) => o.setName('message').setDescription('ID du message (vide = dernier)'))),
  async run(interaction, client) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'lancer') {
      const duration = parseDuration(interaction.options.getString('duree', true));
      if (!duration) return interaction.reply({ embeds: [ui.error('Durée invalide.')], flags: 64 });
      const ch = interaction.options.getChannel('salon') ?? interaction.channel;
      const gw = {
        prize: interaction.options.getString('prix', true), count: interaction.options.getInteger('gagnants') ?? 1,
        end: Date.now() + duration, host: interaction.user.id, channelId: ch.id,
        requiredRole: interaction.options.getRole('role_requis')?.id ?? null, entries: [], ended: false,
      };
      const msg = await ch.send({ content: '🎉 **GIVEAWAY** 🎉', embeds: [gws.giveawayEmbed(interaction.guild, gw)], components: [gws.giveawayRow(gw)] });
      g.giveaways[msg.id] = gw;
      db.save();
      return interaction.reply({ embeds: [ui.success(`Giveaway lancé dans ${ch} !`)], flags: 64 });
    }
    const latest = Object.entries(g.giveaways).sort((a, b) => b[1].end - a[1].end)[0]?.[0];
    const id = interaction.options.getString('message') ?? latest;
    const gw = id && g.giveaways[id];
    if (!gw) return interaction.reply({ embeds: [ui.error('Giveaway introuvable.')], flags: 64 });
    if (sub === 'participants') {
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`🎉 ${gw.prize} — ${gw.entries.length} participant(s)`).setDescription(gw.entries.map((u) => `<@${u}>`).join(', ').slice(0, 4000) || 'Aucun.')], flags: 64 });
    }
    if (sub === 'terminer' && gw.ended) return interaction.reply({ embeds: [ui.error('Déjà terminé.')], flags: 64 });
    if (sub === 'reroll' && !gw.ended) return interaction.reply({ embeds: [ui.error('Le giveaway n’est pas encore terminé.')], flags: 64 });
    await interaction.deferReply({ flags: 64 });
    await gws.end(client, interaction.guild.id, id, sub === 'reroll');
    await interaction.editReply({ embeds: [ui.success(sub === 'reroll' ? 'Nouveau tirage effectué.' : 'Giveaway terminé.')] });
  },
};
