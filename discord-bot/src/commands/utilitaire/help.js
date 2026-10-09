const { SlashCommandBuilder, ActionRowBuilder, StringSelectMenuBuilder, ApplicationCommandOptionType } = require('discord.js');
const ui = require('../../util/ui');
const config = require('../../config');

const CATS = {
  Modération: ['🔨', 'Ban, kick, mute, warn, clear, lock…'],
  Sécurité: ['🛡️', 'Antiraid, whitelist, blacklist, filtres'],
  Logs: ['📜', 'Salons de logs'],
  Serveur: ['⚙️', 'Setup, tickets, giveaways, bienvenue, backups…'],
  Musique: ['🎵', 'Lecteur musique'],
  Niveaux: ['🏆', 'XP et classements'],
  Jeux: ['🎮', 'Morpion, puissance 4, pendu, démineur, snake…'],
  Utilitaire: ['🧰', 'Infos et outils'],
  Bot: ['🤖', 'Contrôle du bot (owners)'],
};

// Liste « /commande sous-commande — description » à partir des définitions
function lines(cmd) {
  const json = cmd.data.toJSON();
  const subs = (json.options ?? []).filter((o) => o.type === ApplicationCommandOptionType.Subcommand);
  if (!subs.length) return [`\`/${json.name}\` — ${json.description}`];
  return subs.map((s) => `\`/${json.name} ${s.name}\` — ${s.description}`);
}

function home(guild, client) {
  const count = client.commands.size;
  return ui.embed(guild).setAuthor({ name: `${config.botName} • Aide`, iconURL: client.user.displayAvatarURL() })
    .setDescription(`**${count}** commandes, toutes en \`/\`.\nChoisis une catégorie dans le menu ci-dessous.\n\n${Object.entries(CATS).map(([n, [e, d]]) => `${e} **${n}** — ${d}`).join('\n')}`)
    .setThumbnail(client.user.displayAvatarURL({ size: 256 }));
}

function menu(selected) {
  return new ActionRowBuilder().addComponents(new StringSelectMenuBuilder().setCustomId('help:cat').setPlaceholder('📚 Choisir une catégorie…')
    .addOptions([{ label: 'Accueil', value: 'home', emoji: '🏠' }, ...Object.entries(CATS).map(([n, [e, d]]) => ({ label: n, value: n, emoji: e, description: d, default: n === selected }))]));
}

function category(guild, client, cat) {
  const cmds = client.commands.filter((c) => c.category === cat).sort((a, b) => a.data.name.localeCompare(b.data.name));
  const text = cmds.map((c) => lines(c).join('\n')).join('\n');
  return ui.embed(guild).setTitle(`${CATS[cat][0]} ${cat}`).setDescription(ui.truncate(text || 'Aucune commande.', 4000));
}

module.exports = {
  category: 'Utilitaire',
  data: new SlashCommandBuilder().setName('help').setDescription('Liste des commandes')
    .addStringOption((o) => o.setName('commande').setDescription('Détails d’une commande').setAutocomplete(true)),
  async autocomplete(interaction, client) {
    const q = interaction.options.getFocused().toLowerCase();
    await interaction.respond(client.commands.filter((c) => c.data.name.includes(q)).first(25).map((c) => ({ name: `/${c.data.name}`, value: c.data.name })));
  },
  async run(interaction, client) {
    const name = interaction.options.getString('commande');
    if (name) {
      const cmd = client.commands.get(name.replace('/', ''));
      if (!cmd) return interaction.reply({ embeds: [ui.error('Commande inconnue.')], flags: 64 });
      const json = cmd.data.toJSON();
      const opts = (json.options ?? []).filter((o) => o.type !== ApplicationCommandOptionType.Subcommand).map((o) => `\`${o.required ? `<${o.name}>` : `[${o.name}]`}\` ${o.description}`);
      return interaction.reply({ embeds: [ui.embed(interaction.guild).setTitle(`/${json.name}`).setDescription(`${json.description}\n\n${lines(cmd).join('\n')}${opts.length ? `\n\n**Options :**\n${opts.join('\n')}` : ''}`).setFooter({ text: '<obligatoire> [facultatif]' })] });
    }
    await interaction.reply({ embeds: [home(interaction.guild, client)], components: [menu()] });
  },
  components: {
    async help(interaction, client) {
      const v = interaction.values[0];
      await interaction.update({ embeds: [v === 'home' ? home(interaction.guild, client) : category(interaction.guild, client, v)], components: [menu(v)] });
    },
  },
};
