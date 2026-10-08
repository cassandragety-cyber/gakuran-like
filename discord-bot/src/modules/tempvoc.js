// Salons vocaux temporaires : rejoindre le salon « ➕ Créer ton vocal » crée un vocal perso.
const { ChannelType, PermissionsBitField } = require('discord.js');
const db = require('../db');

const P = PermissionsBitField.Flags;

module.exports = {
  setup(client) {
    client.on('voiceStateUpdate', async (o, n) => {
      const guild = n.guild;
      const tv = db.guild(guild.id).tempvoc;
      // Création
      if (tv.hub && n.channelId === tv.hub && n.member && !n.member.user.bot) {
        const hub = n.channel;
        try {
          const ch = await guild.channels.create({
            name: `🔊 ${n.member.displayName}`,
            type: ChannelType.GuildVoice,
            parent: hub.parentId,
            permissionOverwrites: [
              ...hub.permissionOverwrites.cache.map((ow) => ({ id: ow.id, allow: ow.allow, deny: ow.deny, type: ow.type })),
              { id: n.member.id, allow: [P.ManageChannels, P.MoveMembers, P.Connect, P.ViewChannel, P.MuteMembers] },
            ],
          });
          tv.channels[ch.id] = n.member.id;
          db.save();
          await n.member.voice.setChannel(ch);
        } catch (err) {
          console.warn('[tempvoc]', err.message);
        }
      }
      // Suppression quand le salon temporaire est vide
      if (o.channelId && tv.channels[o.channelId] && o.channel && o.channel.members.size === 0) {
        delete tv.channels[o.channelId];
        db.save();
        await o.channel.delete('Vocal temporaire vide').catch(() => {});
      }
    });
    // Nettoyage au démarrage des salons restés vides
    client.on('botReady', () => {
      for (const guild of client.guilds.cache.values()) {
        const tv = db.guild(guild.id).tempvoc;
        for (const id of Object.keys(tv.channels)) {
          const ch = guild.channels.cache.get(id);
          if (!ch) delete tv.channels[id];
          else if (ch.members.size === 0) { ch.delete('Vocal temporaire vide').catch(() => {}); delete tv.channels[id]; }
        }
      }
      db.save();
    });
  },
};
