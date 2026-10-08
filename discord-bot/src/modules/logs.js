// Logs automatiques : messages, rôles, vocal, boosts, arrivées/départs.
const { EmbedBuilder, AttachmentBuilder } = require('discord.js');
const { sendLog } = require('../util/logs');
const { COLORS, truncate } = require('../util/ui');

const e = (color) => new EmbedBuilder().setColor(color).setTimestamp();

module.exports = {
  setup(client) {
    client.on('messageDelete', async (m) => {
      if (!m.guild || m.author?.bot) return;
      const embed = e(COLORS.error).setAuthor({ name: m.author ? `${m.author.username} • message supprimé` : 'Message supprimé', iconURL: m.author?.displayAvatarURL() })
        .setDescription(`**Salon :** ${m.channel}\n${m.content ? `\`\`\`${truncate(m.content.replace(/`/g, 'ˋ'), 1800)}\`\`\`` : '*contenu inconnu (message trop ancien)*'}`);
      if (m.attachments?.size) embed.addFields({ name: 'Pièces jointes', value: m.attachments.map((a) => a.name).join(', ').slice(0, 1024) });
      await sendLog(m.guild, 'message', embed);
    });
    client.on('messageUpdate', async (o, n) => {
      if (!n.guild || n.author?.bot || o.content === n.content || o.partial) return;
      await sendLog(n.guild, 'message', e(COLORS.warn).setAuthor({ name: `${n.author.username} • message modifié`, iconURL: n.author.displayAvatarURL() })
        .setDescription(`**Salon :** ${n.channel} • [aller au message](${n.url})`)
        .addFields({ name: 'Avant', value: truncate(o.content || '*vide*', 1024) }, { name: 'Après', value: truncate(n.content || '*vide*', 1024) }));
    });
    client.on('messageDeleteBulk', async (msgs, channel) => {
      const text = [...msgs.values()].reverse().map((m) => `[${new Date(m.createdTimestamp).toLocaleString('fr-FR')}] ${m.author?.username ?? '?'} : ${m.content ?? ''}`).join('\n');
      await sendLog(channel.guild, 'message', { embeds: [e(COLORS.error).setDescription(`🧹 **${msgs.size}** messages supprimés dans ${channel}`)], files: [new AttachmentBuilder(Buffer.from(text || 'vide'), { name: 'messages.txt' })] });
    });

    client.on('guildMemberUpdate', async (o, n) => {
      if (o.partial) return;
      const added = n.roles.cache.filter((r) => !o.roles.cache.has(r.id));
      const removed = o.roles.cache.filter((r) => !n.roles.cache.has(r.id));
      if (added.size || removed.size) {
        await sendLog(n.guild, 'role', e(COLORS.warn).setAuthor({ name: `${n.user.username} • rôles modifiés`, iconURL: n.user.displayAvatarURL() })
          .setDescription(`${n}\n${added.map((r) => `➕ ${r}`).join('\n')}\n${removed.map((r) => `➖ ${r}`).join('\n')}`));
      }
      if (!o.premiumSince && n.premiumSince) {
        await sendLog(n.guild, 'boost', e(0xf47fff).setDescription(`💎 ${n} vient de **booster** le serveur ! (${n.guild.premiumSubscriptionCount} boosts)`).setThumbnail(n.user.displayAvatarURL()));
      } else if (o.premiumSince && !n.premiumSince) {
        await sendLog(n.guild, 'boost', e(COLORS.error).setDescription(`💔 ${n} ne booste plus le serveur.`));
      }
    });
    client.on('roleCreate', (r) => sendLog(r.guild, 'role', e(COLORS.success).setDescription(`🎭 Rôle créé : ${r} (\`${r.name}\`)`)));
    client.on('roleDelete', (r) => sendLog(r.guild, 'role', e(COLORS.error).setDescription(`🎭 Rôle supprimé : \`${r.name}\``)));

    client.on('voiceStateUpdate', async (o, n) => {
      const member = n.member ?? o.member;
      if (!member || member.user.bot) return;
      let text = null;
      if (!o.channelId && n.channelId) text = `🔊 ${member} a rejoint ${n.channel}`;
      else if (o.channelId && !n.channelId) text = `🔇 ${member} a quitté ${o.channel}`;
      else if (o.channelId !== n.channelId) text = `🔀 ${member} : ${o.channel} ➜ ${n.channel}`;
      if (text) await sendLog(n.guild, 'voice', e(COLORS.mute).setDescription(text));
    });

    client.on('guildMemberAdd', (m) => sendLog(m.guild, 'member', e(COLORS.success).setAuthor({ name: `${m.user.username} a rejoint`, iconURL: m.user.displayAvatarURL() })
      .setDescription(`${m} • compte créé <t:${Math.floor(m.user.createdTimestamp / 1000)}:R>\nMembres : **${m.guild.memberCount}**`)));
    client.on('guildMemberRemove', (m) => sendLog(m.guild, 'member', e(COLORS.error).setAuthor({ name: `${m.user.username} est parti`, iconURL: m.user.displayAvatarURL() })
      .setDescription(`${m.user} • ${m.roles?.cache.size > 1 ? `rôles : ${m.roles.cache.filter((r) => r.id !== m.guild.id).map((r) => r.name).join(', ').slice(0, 500)}` : 'aucun rôle'}`)));
  },
};
