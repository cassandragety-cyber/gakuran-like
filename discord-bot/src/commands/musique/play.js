const { SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');
const ui = require('../../util/ui');
const { resolve } = require('../../music/source');
const { GuildQueue, queues } = require('../../music/queue');
const { voiceCheck } = require('../../modules/music');
const { clock } = require('../../util/time');

async function enqueue(interaction, tracks, { playlist, next } = {}) {
  const vc = interaction.member.voice.channel;
  const me = interaction.guild.members.me;
  const perms = vc.permissionsFor(me);
  if (!perms.has(PermissionFlagsBits.Connect) || !perms.has(PermissionFlagsBits.Speak)) throw new Error(`je n’ai pas la permission de parler dans ${vc}`);
  let q = queues.get(interaction.guild.id);
  const wasPlaying = !!q?.current;
  q ??= new GuildQueue(interaction.guild, vc, interaction.channel);
  q.textChannel = interaction.channel;
  await q.add(tracks, { next });
  if (!wasPlaying && !playlist) return ui.info(`${ui.E.music} C’est parti : **[${ui.truncate(tracks[0].title, 80)}](${tracks[0].url})**`, interaction.guild);
  const e = ui.embed(interaction.guild).setAuthor({ name: playlist ? '📜 Playlist ajoutée' : '➕ Ajouté à la file' });
  if (playlist) e.setDescription(`**${ui.truncate(playlist, 100)}** — ${tracks.length} titres`);
  else e.setDescription(`**[${ui.truncate(tracks[0].title, 100)}](${tracks[0].url})**\n⏱️ ${clock(tracks[0].duration)} • position **${next ? 1 : q.tracks.length}** dans la file`).setThumbnail(tracks[0].thumbnail);
  return e;
}

module.exports = {
  category: 'Musique',
  enqueue,
  data: new SlashCommandBuilder()
    .setName('play')
    .setDescription('Joue une musique (titre, lien YouTube / SoundCloud / Spotify, playlist)')
    .addStringOption((o) => o.setName('recherche').setDescription('Titre ou lien').setRequired(true).setMaxLength(500))
    .addBooleanOption((o) => o.setName('ensuite').setDescription('Jouer juste après le titre en cours')),
  async run(interaction) {
    const [, err] = voiceCheck(interaction, { needQueue: false });
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    await interaction.deferReply();
    let res;
    try {
      res = await resolve(interaction.options.getString('recherche', true), `${interaction.user}`);
    } catch (e) {
      return interaction.editReply({ embeds: [ui.error(`Recherche impossible : ${ui.truncate(e.message, 300)}`)] });
    }
    try {
      await interaction.editReply({ embeds: [await enqueue(interaction, res.tracks, { playlist: res.playlist, next: interaction.options.getBoolean('ensuite') })] });
    } catch (e) {
      await interaction.editReply({ embeds: [ui.error(ui.truncate(e.message, 300))] });
    }
  },
};
