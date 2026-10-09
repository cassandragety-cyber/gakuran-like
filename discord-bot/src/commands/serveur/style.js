const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { resolveGifLink } = require('../../util/gifs');
const { buildAnnounce } = require('../../util/announce');

const ACTIONS = [
  { name: 'ban', value: 'ban' }, { name: 'tempban', value: 'tempban' }, { name: 'kick', value: 'kick' },
  { name: 'mute', value: 'mute' }, { name: 'warn', value: 'warn' }, { name: 'unban', value: 'unban' },
];

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('style')
    .setDescription('Apparence du bot : couleur et GIF des sanctions')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
    .addSubcommand((s) => s.setName('couleur').setDescription('Couleur des embeds').addStringOption((o) => o.setName('hex').setDescription('Ex : #8b5cf6 (« reset » = défaut)').setRequired(true)))
    .addSubcommand((s) => s.setName('gifs').setDescription('Choisit d’où viennent les GIF des sanctions')
      .addStringOption((o) => o.setName('mode').setDescription('Mode').setRequired(true).addChoices(
        { name: 'Anime (Klipy / API anime + tes GIF)', value: 'anime' },
        { name: 'Perso (uniquement tes GIF ajoutés)', value: 'perso' },
        { name: 'Carte animée générée avec l’avatar', value: 'carte' },
        { name: 'Aucun GIF', value: 'off' },
      )))
    .addSubcommand((s) => s.setName('gif-ajouter').setDescription('Ajoute un GIF pour une sanction (lien Klipy, Tenor, Giphy ou .gif)')
      .addStringOption((o) => o.setName('action').setDescription('Sanction').setRequired(true).addChoices(...ACTIONS))
      .addStringOption((o) => o.setName('lien').setDescription('Ex : https://klipy.com/gifs/domain-expansion-gojo-4').setRequired(true)))
    .addSubcommand((s) => s.setName('gif-retirer').setDescription('Retire un GIF ajouté')
      .addStringOption((o) => o.setName('action').setDescription('Sanction').setRequired(true).addChoices(...ACTIONS))
      .addIntegerOption((o) => o.setName('numero').setDescription('Numéro (vide = tous)').setMinValue(1)))
    .addSubcommand((s) => s.setName('gif-liste').setDescription('GIF ajoutés par sanction'))
    .addSubcommand((s) => s.setName('apercu').setDescription('Aperçu d’une annonce de sanction')
      .addStringOption((o) => o.setName('action').setDescription('Sanction').setRequired(true).addChoices(...ACTIONS))),
  async run(interaction) {
    const g = db.guild(interaction.guild.id);
    const sub = interaction.options.getSubcommand();
    if (sub === 'couleur') {
      const raw = interaction.options.getString('hex', true);
      const n = parseInt(raw.replace('#', ''), 16);
      g.color = raw === 'reset' || !Number.isFinite(n) ? null : n;
      db.save();
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setDescription(`🎨 Couleur des embeds : **${g.color ? `#${g.color.toString(16).padStart(6, '0')}` : 'par défaut'}**`)] });
    }
    if (sub === 'gifs') {
      const mode = interaction.options.getString('mode', true);
      g.style.gifs = mode !== 'off';
      g.style.mode = mode;
      db.save();
      return interaction.reply({ embeds: [ui.success(`GIF des sanctions : **${mode}**.`)] });
    }
    const action = interaction.options.getString('action');
    if (sub === 'gif-ajouter') {
      await interaction.deferReply({ flags: 64 });
      let url;
      try {
        url = await resolveGifLink(interaction.options.getString('lien', true));
      } catch (err) {
        return interaction.editReply({ embeds: [ui.error(`Impossible de récupérer ce GIF : ${err.message}.\nAstuce : clic droit sur le GIF → « Copier l’adresse de l’image », et colle ce lien.`)] });
      }
      (g.style.customGifs[action] ??= []).push(url);
      db.save();
      return interaction.editReply({ embeds: [ui.success(`GIF ajouté pour **${action}** (${g.style.customGifs[action].length} au total).`).setImage(url)] });
    }
    if (sub === 'gif-retirer') {
      const n = interaction.options.getInteger('numero');
      if (!n) delete g.style.customGifs[action];
      else g.style.customGifs[action]?.splice(n - 1, 1);
      db.save();
      return interaction.reply({ embeds: [ui.success('GIF retiré.')], flags: 64 });
    }
    if (sub === 'gif-liste') {
      const lines = ACTIONS.map(({ value }) => `**${value}** : ${(g.style.customGifs[value] ?? []).map((u, i) => `[${i + 1}](${u})`).join(' ') || '*aucun*'}`);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('🎞️ GIF des sanctions').setDescription(`Mode : **${g.style.gifs === false ? 'off' : g.style.mode ?? 'anime'}**\n\n${lines.join('\n')}`)], flags: 64 });
    }
    await interaction.deferReply();
    await interaction.editReply(await buildAnnounce(interaction.guild, { action, user: interaction.user, moderator: interaction.client.user, reason: 'Ceci est un aperçu', duration: action === 'mute' || action === 'tempban' ? 3600e3 : undefined }));
  },
};
