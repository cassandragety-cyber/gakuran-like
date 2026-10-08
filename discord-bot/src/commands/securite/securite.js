const { SlashCommandBuilder, PermissionFlagsBits, ChannelType } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { parseDuration, formatDuration } = require('../../util/time');

module.exports = {
  category: 'Sécurité',
  access: 'trusted',
  data: new SlashCommandBuilder()
    .setName('securite')
    .setDescription('Réglages avancés de la sécurité')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((s) => s.setName('raidmode').setDescription('Expulse automatiquement toute nouvelle arrivée')
      .addStringOption((o) => o.setName('etat').setDescription('on/off').setRequired(true).addChoices({ name: 'on', value: 'on' }, { name: 'off', value: 'off' }))
      .addStringOption((o) => o.setName('duree').setDescription('Durée (vide = jusqu’à désactivation)')))
    .addSubcommand((s) => s.setName('createlimit').setDescription('Expulse les comptes trop récents à leur arrivée')
      .addStringOption((o) => o.setName('age').setDescription('Âge minimum du compte, ex : 3j, 1sem (0 = désactivé)').setRequired(true)))
    .addSubcommand((s) => s.setName('pingraid').setDescription('Qui mentionner quand un raid est détecté')
      .addRoleOption((o) => o.setName('role').setDescription('Rôle à mentionner'))
      .addBooleanOption((o) => o.setName('everyone').setDescription('Mentionner @everyone'))
      .addBooleanOption((o) => o.setName('desactiver').setDescription('Ne mentionner personne')))
    .addSubcommand((s) => s.setName('noderank').setDescription('Rôles jamais retirés par un derank')
      .addStringOption((o) => o.setName('action').setDescription('Action').setRequired(true).addChoices({ name: 'ajouter', value: 'add' }, { name: 'retirer', value: 'del' }, { name: 'liste', value: 'list' }, { name: 'vider', value: 'clear' }))
      .addRoleOption((o) => o.setName('role').setDescription('Rôle')))
    .addSubcommand((s) => s.setName('antilink').setDescription('Type de liens bloqués et domaines autorisés')
      .addStringOption((o) => o.setName('mode').setDescription('Bloquer…').addChoices({ name: 'les invitations Discord', value: 'invites' }, { name: 'tous les liens', value: 'all' }))
      .addStringOption((o) => o.setName('autoriser').setDescription('Domaine à autoriser (ex : youtube.com)'))
      .addStringOption((o) => o.setName('interdire').setDescription('Domaine à retirer des autorisés')))
    .addSubcommand((s) => s.setName('ignorer').setDescription('Salon ignoré par l’antilink ou l’antispam')
      .addStringOption((o) => o.setName('filtre').setDescription('Filtre').setRequired(true).addChoices({ name: 'antilink', value: 'antilink' }, { name: 'antispam', value: 'antispam' }))
      .addChannelOption((o) => o.setName('salon').setDescription('Salon ou catégorie').setRequired(true).addChannelTypes(ChannelType.GuildText, ChannelType.GuildCategory, ChannelType.GuildAnnouncement, ChannelType.GuildVoice)))
    .addSubcommand((s) => s.setName('antirank').setDescription('Quels ajouts de rôles déclenchent l’antirank')
      .addStringOption((o) => o.setName('type').setDescription('Type').setRequired(true).addChoices({ name: 'rôles dangereux seulement', value: 'danger' }, { name: 'tous les rôles', value: 'all' }))
      .addRoleOption((o) => o.setName('ignorer').setDescription('Rôle à ignorer (re-cliquer pour retirer)'))),
  async run(interaction) {
    const sec = db.guild(interaction.guild.id).security;
    const sub = interaction.options.getSubcommand();
    const reply = (t) => interaction.reply({ embeds: [ui.success(t)] });
    if (sub === 'raidmode') {
      const on = interaction.options.getString('etat', true) === 'on';
      const d = parseDuration(interaction.options.getString('duree'));
      sec.raidmode = on;
      sec.raidmodeUntil = on && d ? Date.now() + d : 0;
      db.save();
      return reply(on ? `🚨 Mode raid **activé**${d ? ` pour ${formatDuration(d)}` : ''} : toute arrivée sera expulsée.` : 'Mode raid **désactivé**.');
    }
    if (sub === 'createlimit') {
      const raw = interaction.options.getString('age', true);
      const ms = raw === '0' ? 0 : parseDuration(raw);
      if (ms === null) return interaction.reply({ embeds: [ui.error('Durée invalide.')], flags: 64 });
      sec.createlimit = ms;
      db.save();
      return reply(ms ? `Les comptes de moins de **${formatDuration(ms)}** seront expulsés.` : 'Limite d’âge désactivée.');
    }
    if (sub === 'pingraid') {
      const role = interaction.options.getRole('role');
      sec.pingraid = interaction.options.getBoolean('desactiver') ? null : interaction.options.getBoolean('everyone') ? 'everyone' : role?.id ?? sec.pingraid;
      db.save();
      return reply(`Ping raid : ${sec.pingraid ? (sec.pingraid === 'everyone' ? '@everyone' : `<@&${sec.pingraid}>`) : 'personne'}.`);
    }
    if (sub === 'noderank') {
      const action = interaction.options.getString('action', true);
      const role = interaction.options.getRole('role');
      if (action === 'list') return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle('Rôles protégés du derank').setDescription(sec.noderank.map((id) => `<@&${id}>`).join('\n') || 'Aucun.')] });
      if (action === 'clear') sec.noderank = [];
      else if (!role) return interaction.reply({ embeds: [ui.error('Précise un rôle.')], flags: 64 });
      else if (action === 'add' && !sec.noderank.includes(role.id)) sec.noderank.push(role.id);
      else if (action === 'del') sec.noderank = sec.noderank.filter((id) => id !== role.id);
      db.save();
      return reply('Liste noderank mise à jour.');
    }
    if (sub === 'antilink') {
      const m = interaction.options.getString('mode');
      const allow = interaction.options.getString('autoriser')?.toLowerCase();
      const deny = interaction.options.getString('interdire')?.toLowerCase();
      sec.antilinkAllow ??= [];
      if (m) sec.antilinkMode = m;
      if (allow && !sec.antilinkAllow.includes(allow)) sec.antilinkAllow.push(allow);
      if (deny) sec.antilinkAllow = sec.antilinkAllow.filter((d) => d !== deny);
      db.save();
      return reply(`Antilink : bloque **${sec.antilinkMode === 'all' ? 'tous les liens' : 'les invitations'}**.\nDomaines autorisés : ${sec.antilinkAllow.map((d) => `\`${d}\``).join(', ') || 'aucun'}`);
    }
    if (sub === 'ignorer') {
      const f = interaction.options.getString('filtre', true);
      const ch = interaction.options.getChannel('salon', true);
      const list = sec.ignored[f];
      const i = list.indexOf(ch.id);
      if (i === -1) list.push(ch.id);
      else list.splice(i, 1);
      db.save();
      return reply(`${ch} ${i === -1 ? 'est maintenant ignoré' : 'n’est plus ignoré'} par l’${f}.`);
    }
    if (sub === 'antirank') {
      sec.antirankType = interaction.options.getString('type', true);
      const role = interaction.options.getRole('ignorer');
      if (role) {
        const i = sec.antirankIgnore.indexOf(role.id);
        if (i === -1) sec.antirankIgnore.push(role.id);
        else sec.antirankIgnore.splice(i, 1);
      }
      db.save();
      return reply(`Antirank : ${sec.antirankType === 'all' ? 'tous les rôles' : 'rôles dangereux'}. Ignorés : ${sec.antirankIgnore.map((r) => `<@&${r}>`).join(', ') || 'aucun'}`);
    }
  },
};
