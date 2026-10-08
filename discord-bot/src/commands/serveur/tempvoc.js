const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');

module.exports = {
  category: 'Serveur',
  data: new SlashCommandBuilder()
    .setName('tempvoc')
    .setDescription('Vocaux temporaires')
    .addSubcommand((s) => s.setName('setup').setDescription('Crée le salon « ➕ Créer ton vocal »')
      .addChannelOption((o) => o.setName('categorie').setDescription('Catégorie').addChannelTypes(ChannelType.GuildCategory)))
    .addSubcommand((s) => s.setName('nom').setDescription('Renomme ton vocal').addStringOption((o) => o.setName('nom').setDescription('Nom').setRequired(true).setMaxLength(90)))
    .addSubcommand((s) => s.setName('limite').setDescription('Nombre max de membres').addIntegerOption((o) => o.setName('nombre').setDescription('0 = illimité').setRequired(true).setMinValue(0).setMaxValue(99)))
    .addSubcommand((s) => s.setName('prive').setDescription('Seuls les membres ajoutés peuvent rejoindre'))
    .addSubcommand((s) => s.setName('public').setDescription('Tout le monde peut rejoindre'))
    .addSubcommand((s) => s.setName('invisible').setDescription('Cache ton vocal'))
    .addSubcommand((s) => s.setName('visible').setDescription('Rend ton vocal visible'))
    .addSubcommand((s) => s.setName('ajouter').setDescription('Autorise un membre').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('retirer').setDescription('Retire l’accès d’un membre').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true)))
    .addSubcommand((s) => s.setName('expulser').setDescription('Déconnecte un membre de ton vocal').addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))),
  async run(interaction) {
    const sub = interaction.options.getSubcommand();
    const tv = db.guild(interaction.guild.id).tempvoc;
    if (sub === 'setup') {
      if (!interaction.member.permissions.has(PermissionFlagsBits.ManageChannels)) return interaction.reply({ embeds: [ui.error('Permission « Gérer les salons » requise.')], flags: 64 });
      const hub = await interaction.guild.channels.create({ name: '➕ Créer ton vocal', type: ChannelType.GuildVoice, parent: interaction.options.getChannel('categorie')?.id ?? interaction.channel.parentId });
      tv.hub = hub.id;
      db.save();
      return interaction.reply({ embeds: [ui.success(`Vocaux temporaires prêts : rejoins ${hub} pour créer ton salon.`)] });
    }
    const ch = interaction.member.voice.channel;
    if (!ch || tv.channels[ch.id] !== interaction.user.id) return interaction.reply({ embeds: [ui.error('Tu dois être dans **ton** vocal temporaire.')], flags: 64 });
    const everyone = interaction.guild.roles.everyone;
    const user = interaction.options.getUser('membre');
    const actions = {
      nom: () => ch.setName(`🔊 ${interaction.options.getString('nom', true)}`),
      limite: () => ch.setUserLimit(interaction.options.getInteger('nombre', true)),
      prive: () => ch.permissionOverwrites.edit(everyone, { Connect: false }),
      public: () => ch.permissionOverwrites.edit(everyone, { Connect: null }),
      invisible: () => ch.permissionOverwrites.edit(everyone, { ViewChannel: false }),
      visible: () => ch.permissionOverwrites.edit(everyone, { ViewChannel: null }),
      ajouter: () => ch.permissionOverwrites.edit(user, { Connect: true, ViewChannel: true }),
      retirer: async () => { await ch.permissionOverwrites.edit(user, { Connect: false }); await ch.members.get(user.id)?.voice.disconnect(); },
      expulser: () => ch.members.get(user.id)?.voice.disconnect(),
    };
    await actions[sub]();
    await interaction.reply({ embeds: [ui.success('Vocal mis à jour.')], flags: 64 });
  },
};
