// Aiguillage de toutes les interactions : commandes /, boutons, menus, formulaires.
const { MessageFlags } = require('discord.js');
const db = require('../db');
const ui = require('../util/ui');
const { isBuyer, isOwner, isTrusted } = require('../util/perms');

const ACCESS = {
  buyer: [(i) => isBuyer(i.user.id), 'Commande réservée aux **buyers** du bot (OWNER_IDS).'],
  owner: [(i) => isOwner(i.user.id), 'Commande réservée aux **owners** du bot.'],
  trusted: [(i) => isTrusted(i.guild, i.user.id), 'Commande réservée au **propriétaire du serveur** et aux **owners** du bot.'],
};

async function replyError(interaction, text) {
  const payload = { embeds: [ui.error(text)], flags: MessageFlags.Ephemeral };
  try {
    if (interaction.deferred || interaction.replied) await interaction.followUp(payload);
    else await interaction.reply(payload);
  } catch {}
}

module.exports = (client) => {
  client.on('interactionCreate', async (interaction) => {
    if (!interaction.inGuild()) return;
    if (db.global.blbot.includes(interaction.user.id) && !isBuyer(interaction.user.id)) {
      if (interaction.isRepliable()) return replyError(interaction, 'Tu es blacklisté du bot.');
      return;
    }
    try {
      if (interaction.isAutocomplete()) {
        const cmd = client.commands.get(interaction.commandName);
        return await cmd?.autocomplete?.(interaction, client);
      }
      if (interaction.isChatInputCommand()) {
        const cmd = client.commands.get(interaction.commandName);
        if (!cmd) return;
        const access = cmd.access && ACCESS[cmd.access];
        if (access && !access[0](interaction)) return replyError(interaction, access[1]);
        return await cmd.run(interaction, client);
      }
      if (interaction.isMessageComponent() || interaction.isModalSubmit()) {
        const prefix = interaction.customId.split(':')[0];
        const handler = client.components.get(prefix);
        // Les boutons gérés par un collecteur (pagination, confirmations) n'ont pas de handler global
        if (handler) await handler(interaction, client);
      }
    } catch (err) {
      console.error(`[interaction] ${interaction.commandName ?? interaction.customId} :`, err);
      replyError(interaction, `Une erreur est survenue : \`${ui.truncate(err.message, 300)}\``);
    }
  });
};
