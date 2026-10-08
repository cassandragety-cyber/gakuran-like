const { SlashCommandBuilder, ActionRowBuilder, StringSelectMenuBuilder, ComponentType } = require('discord.js');
const ui = require('../../util/ui');
const { resolve } = require('../../music/source');
const { voiceCheck } = require('../../modules/music');
const { enqueue } = require('./play');
const { clock } = require('../../util/time');

module.exports = {
  category: 'Musique',
  data: new SlashCommandBuilder()
    .setName('recherche')
    .setDescription('Cherche une musique et choisis parmi 10 résultats')
    .addStringOption((o) => o.setName('recherche').setDescription('Titre').setRequired(true).setMaxLength(200)),
  async run(interaction) {
    const [, err] = voiceCheck(interaction, { needQueue: false });
    if (err) return interaction.reply({ embeds: [ui.error(err)], flags: 64 });
    await interaction.deferReply();
    let tracks;
    try {
      ({ tracks } = await resolve(interaction.options.getString('recherche', true), `${interaction.user}`, { results: 10 }));
    } catch (e) {
      return interaction.editReply({ embeds: [ui.error(`Recherche impossible : ${ui.truncate(e.message, 300)}`)] });
    }
    const menu = new StringSelectMenuBuilder().setCustomId('pick').setPlaceholder('🎵 Choisis une musique…')
      .addOptions(tracks.slice(0, 10).map((t, i) => ({ label: ui.truncate(t.title, 100), description: ui.truncate(`${t.author ?? ''} • ${clock(t.duration)}`, 100), value: String(i) })));
    const msg = await interaction.editReply({
      embeds: [ui.embed(interaction.guild).setTitle('🔎 Résultats').setDescription(tracks.slice(0, 10).map((t, i) => `\`${i + 1}.\` **${ui.truncate(t.title, 70)}** — ${clock(t.duration)}`).join('\n'))],
      components: [new ActionRowBuilder().addComponents(menu)],
    });
    const pick = await msg.awaitMessageComponent({ componentType: ComponentType.StringSelect, filter: (i) => i.user.id === interaction.user.id, time: 60e3 }).catch(() => null);
    if (!pick) return interaction.editReply({ components: [] });
    await pick.deferUpdate();
    try {
      await interaction.editReply({ embeds: [await enqueue(interaction, [tracks[Number(pick.values[0])]])], components: [] });
    } catch (e) {
      await interaction.editReply({ embeds: [ui.error(ui.truncate(e.message, 300))], components: [] });
    }
  },
};
