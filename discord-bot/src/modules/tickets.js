// Tickets : panneau avec bouton, salon privé, claim, fermeture avec transcript.
const { ActionRowBuilder, ButtonBuilder, ButtonStyle, PermissionsBitField, EmbedBuilder, AttachmentBuilder } = require('discord.js');
const db = require('../db');
const ui = require('../util/ui');
const { sendLog } = require('../util/logs');

const P = PermissionsBitField.Flags;

function panelPayload(guild, { title, description } = {}) {
  return {
    embeds: [ui.embed(guild).setTitle(title || `${ui.E.ticket} Support`).setDescription(description || 'Besoin d’aide ? Clique sur le bouton ci-dessous pour ouvrir un ticket privé avec le staff.')],
    components: [new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId('ticket:open').setLabel('Ouvrir un ticket').setEmoji('🎫').setStyle(ButtonStyle.Primary))],
  };
}

function ticketButtons(claimed) {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('ticket:claim').setLabel(claimed ? 'Pris en charge' : 'Prendre en charge').setEmoji('🙋').setStyle(ButtonStyle.Success).setDisabled(!!claimed),
    new ButtonBuilder().setCustomId('ticket:close').setLabel('Fermer').setEmoji('🔒').setStyle(ButtonStyle.Danger),
  );
}

const isStaff = (member, t) => member.permissions.has(P.ManageChannels) || (t.staffRole && member.roles.cache.has(t.staffRole));

async function open(interaction) {
  const { guild, user } = interaction;
  const t = db.guild(guild.id).tickets;
  const existing = Object.entries(t.open).find(([id, o]) => o.owner === user.id && guild.channels.cache.has(id));
  if (existing) return interaction.reply({ embeds: [ui.error(`Tu as déjà un ticket ouvert : <#${existing[0]}>`)], flags: 64 });
  await interaction.deferReply({ flags: 64 });
  const overwrites = [
    { id: guild.roles.everyone.id, deny: [P.ViewChannel] },
    { id: user.id, allow: [P.ViewChannel, P.SendMessages, P.AttachFiles, P.ReadMessageHistory] },
    { id: guild.members.me.id, allow: [P.ViewChannel, P.SendMessages, P.ManageChannels, P.ReadMessageHistory] },
  ];
  if (t.staffRole) overwrites.push({ id: t.staffRole, allow: [P.ViewChannel, P.SendMessages, P.ReadMessageHistory, P.AttachFiles] });
  const n = String(++t.counter).padStart(4, '0');
  const channel = await guild.channels.create({
    name: `🎫・ticket-${n}`,
    parent: guild.channels.cache.has(t.category) ? t.category : null,
    permissionOverwrites: overwrites,
    topic: `Ticket de ${user.tag} (${user.id})`,
  });
  t.open[channel.id] = { owner: user.id, claimedBy: null, opened: Date.now(), n };
  db.save();
  await channel.send({
    content: `${user}${t.staffRole ? ` <@&${t.staffRole}>` : ''}`,
    embeds: [ui.embed(guild).setTitle(`${ui.E.ticket} Ticket #${n}`).setDescription(`Bienvenue ${user} !\nExplique ta demande, un membre du staff va te répondre.\n\n🙋 **Prendre en charge** • 🔒 **Fermer**`)],
    components: [ticketButtons(false)],
    allowedMentions: { users: [user.id], roles: t.staffRole ? [t.staffRole] : [] },
  });
  await interaction.editReply({ embeds: [ui.success(`Ticket créé : ${channel}`)] });
}

async function close(interaction, reason) {
  const { guild, channel } = interaction;
  const t = db.guild(guild.id).tickets;
  const info = t.open[channel.id];
  if (!info) return interaction.reply({ embeds: [ui.error('Ce salon n’est pas un ticket.')], flags: 64 });
  await interaction.reply({ embeds: [ui.info(`🔒 Fermeture du ticket dans 5 secondes…`, guild)] });
  // Transcript texte de toute la conversation
  const all = [];
  let before;
  for (let i = 0; i < 10; i++) {
    const batch = await channel.messages.fetch({ limit: 100, before }).catch(() => null);
    if (!batch?.size) break;
    all.push(...batch.values());
    before = batch.last().id;
  }
  const text = all.reverse().map((m) => `[${new Date(m.createdTimestamp).toLocaleString('fr-FR')}] ${m.author.username} : ${m.content}${m.attachments.size ? ` [${m.attachments.map((a) => a.url).join(' ')}]` : ''}`).join('\n');
  const file = new AttachmentBuilder(Buffer.from(text || 'vide'), { name: `ticket-${info.n}.txt` });
  const log = new EmbedBuilder().setColor(ui.COLORS.warn).setTitle(`${ui.E.ticket} Ticket #${info.n} fermé`)
    .setDescription(`**Ouvert par :** <@${info.owner}>\n**Pris en charge par :** ${info.claimedBy ? `<@${info.claimedBy}>` : 'personne'}\n**Fermé par :** ${interaction.user}\n**Raison :** ${reason || 'aucune'}`).setTimestamp();
  await sendLog(guild, 'mod', { embeds: [log], files: [file] });
  const owner = await guild.client.users.fetch(info.owner).catch(() => null);
  await owner?.send({ embeds: [log], files: [new AttachmentBuilder(Buffer.from(text || 'vide'), { name: `ticket-${info.n}.txt` })] }).catch(() => {});
  delete t.open[channel.id];
  db.save();
  setTimeout(() => channel.delete('Ticket fermé').catch(() => {}), 5000);
}

module.exports = {
  panelPayload,
  open,
  close,
  isStaff,
  setup(client) {
    client.on('channelDelete', (ch) => {
      if (!ch.guild) return;
      const t = db.guild(ch.guild.id).tickets;
      if (t.open[ch.id]) {
        delete t.open[ch.id];
        db.save();
      }
    });
  },
  components: {
    async ticket(interaction) {
      const action = interaction.customId.split(':')[1];
      if (action === 'open') return open(interaction);
      const t = db.guild(interaction.guild.id).tickets;
      const info = t.open[interaction.channelId];
      if (!info) return interaction.reply({ embeds: [ui.error('Ticket introuvable.')], flags: 64 });
      if (action === 'claim') {
        if (!isStaff(interaction.member, t)) return interaction.reply({ embeds: [ui.error('Réservé au staff.')], flags: 64 });
        info.claimedBy = interaction.user.id;
        db.save();
        await interaction.update({ components: [ticketButtons(true)] });
        return interaction.followUp({ embeds: [ui.info(`🙋 ${interaction.user} prend en charge ce ticket.`, interaction.guild)] });
      }
      if (action === 'close') {
        if (!isStaff(interaction.member, t) && interaction.user.id !== info.owner) return interaction.reply({ embeds: [ui.error('Tu ne peux pas fermer ce ticket.')], flags: 64 });
        return close(interaction);
      }
    },
  },
};
