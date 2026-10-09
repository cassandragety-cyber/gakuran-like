const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const db = require('../../db');
const ui = require('../../util/ui');
const { checkHierarchy } = require('../../util/perms');
const { modLog } = require('../../util/logs');
const { addSanction } = require('../../util/sanctions');

// Retire tous les rôles retirables (sauf ceux protégés par /securite noderank)
async function derank(member, reason) {
  const keep = db.guild(member.guild.id).security.noderank;
  const me = member.guild.members.me;
  const roles = member.roles.cache.filter((r) => r.id === member.guild.id || r.managed || keep.includes(r.id) || r.position >= me.roles.highest.position);
  await member.roles.set(roles, reason);
}

module.exports = {
  category: 'Modération',
  derank,
  data: new SlashCommandBuilder()
    .setName('derank')
    .setDescription('Retire tous les rôles d’un membre')
    .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles)
    .addUserOption((o) => o.setName('membre').setDescription('Membre').setRequired(true))
    .addStringOption((o) => o.setName('raison').setDescription('Raison')),
  async run(interaction) {
    const member = interaction.options.getMember('membre');
    if (!member) return interaction.reply({ embeds: [ui.error('Membre introuvable.')], flags: 64 });
    const err = checkHierarchy(interaction, member, 'derank');
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    const reason = interaction.options.getString('raison');
    const count = member.roles.cache.size - 1;
    await derank(member, `derank par ${interaction.user.tag}`);
    const id = addSanction(interaction.guild.id, member.id, { type: 'derank', reason, modId: interaction.user.id });
    await modLog(interaction.guild, { action: 'derank', target: member.user, moderator: interaction.user, reason, id });
    await interaction.reply({ embeds: [ui.embed(interaction.guild).setDescription(`📉 ${member} a été **derank** (${count} rôle(s) retiré(s)).`)] });
  },
};
