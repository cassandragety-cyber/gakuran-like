const { SlashCommandBuilder, PermissionFlagsBits, ActionRowBuilder, StringSelectMenuBuilder, ButtonBuilder, ButtonStyle } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { isTrusted } = require('../../util/perms');
const { LABELS } = require('../../modules/antiraid');

const ICON = { off: '🔴', on: '🟢', max: '🟣' };
const RECOMMENDED = ['antibot', 'antichannel', 'antirole', 'antiwebhook', 'antiban', 'antikick', 'antirank', 'antiupdate', 'antieveryone', 'antilink', 'antispam', 'antitoken'];

function panel(guild, selected) {
  const sec = db.guild(guild.id).security;
  const lines = db.ANTIRAID_MODULES.map((m) => {
    const lim = sec.limits[m];
    const p = sec.punish[m] ?? sec.punish.default;
    return `${ICON[sec.modules[m]]} **${m}** — ${LABELS[m]}${lim ? ` \`${lim.count}/${lim.window}s\`` : ''} • *${p.replace('_', ' + ')}*`;
  });
  const on = db.ANTIRAID_MODULES.filter((m) => sec.modules[m] !== 'off').length;
  const e = ui.embed(guild)
    .setTitle(`${ui.E.shield} Panneau de sécurité`)
    .setDescription(`**${on}/${db.ANTIRAID_MODULES.length}** protections actives\n🟢 activé • 🟣 max (même la whitelist est surveillée) • 🔴 désactivé\n\n${lines.join('\n')}`)
    .addFields(
      { name: 'Whitelist', value: `${sec.whitelist.users.length} membre(s), ${sec.whitelist.roles.length} rôle(s)`, inline: true },
      { name: 'Blacklist', value: `${Object.keys(sec.blacklist).length} utilisateur(s)`, inline: true },
      { name: 'Mode raid', value: sec.raidmode ? '🚨 ACTIF' : 'inactif', inline: true },
    )
    .setFooter({ text: 'Choisis un module dans le menu pour le modifier' });
  const select = new StringSelectMenuBuilder().setCustomId('secur:select').setPlaceholder('🛡️ Choisir un module…')
    .addOptions(db.ANTIRAID_MODULES.map((m) => ({ label: m, description: LABELS[m], value: m, emoji: ICON[sec.modules[m]], default: m === selected })));
  const rows = [new ActionRowBuilder().addComponents(select)];
  if (selected) {
    rows.push(new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId(`secur:set:${selected}:on`).setLabel('Activer').setEmoji('🟢').setStyle(ButtonStyle.Success),
      new ButtonBuilder().setCustomId(`secur:set:${selected}:max`).setLabel('Max').setEmoji('🟣').setStyle(ButtonStyle.Primary),
      new ButtonBuilder().setCustomId(`secur:set:${selected}:off`).setLabel('Désactiver').setEmoji('🔴').setStyle(ButtonStyle.Danger),
    ));
  }
  rows.push(new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('secur:all:recommended').setLabel('Config recommandée').setEmoji('✨').setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId('secur:all:max').setLabel('Tout en max').setEmoji('🔒').setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId('secur:all:off').setLabel('Tout désactiver').setEmoji('💤').setStyle(ButtonStyle.Secondary),
  ));
  return { embeds: [e], components: rows };
}

function setAll(guild, state) {
  const sec = db.guild(guild.id).security;
  for (const m of db.ANTIRAID_MODULES) sec.modules[m] = state === 'recommended' ? (RECOMMENDED.includes(m) ? 'on' : 'off') : state;
  db.save();
}

module.exports = {
  category: 'Sécurité',
  access: 'trusted',
  setAll,
  data: new SlashCommandBuilder()
    .setName('secur')
    .setDescription('Panneau de sécurité : active/désactive toutes les protections antiraid')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addStringOption((o) => o.setName('etat').setDescription('Changer tous les modules d’un coup').addChoices(
      { name: 'Recommandé', value: 'recommended' }, { name: 'Tout activer', value: 'on' }, { name: 'Tout en max', value: 'max' }, { name: 'Tout désactiver', value: 'off' },
    )),
  async run(interaction) {
    const state = interaction.options.getString('etat');
    if (state) setAll(interaction.guild, state);
    await interaction.reply(panel(interaction.guild));
  },
  components: {
    async secur(interaction) {
      if (!isTrusted(interaction.guild, interaction.user.id)) return interaction.reply({ embeds: [ui.error('Réservé au propriétaire du serveur et aux owners du bot.')], flags: 64 });
      const [, action, a, b] = interaction.customId.split(':');
      if (action === 'select') return interaction.update(panel(interaction.guild, interaction.values[0]));
      if (action === 'set') {
        db.guild(interaction.guild.id).security.modules[a] = b;
        db.save();
        return interaction.update(panel(interaction.guild, a));
      }
      if (action === 'all') {
        setAll(interaction.guild, a);
        return interaction.update(panel(interaction.guild));
      }
    },
  },
};
