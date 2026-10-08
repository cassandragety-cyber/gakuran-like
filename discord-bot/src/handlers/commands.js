// Chargement des commandes et des modules, et enregistrement des commandes / sur chaque serveur.
const fs = require('node:fs');
const path = require('node:path');
const { Collection, InteractionContextType } = require('discord.js');

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : e.name.endsWith('.js') ? [p] : [];
  });
}

function loadCommands() {
  const commands = new Collection();
  const components = new Map();
  for (const file of walk(path.join(__dirname, '..', 'commands'))) {
    // Un fichier peut exporter une commande ou une liste de commandes
    for (const cmd of [require(file)].flat()) {
      if (!cmd.data) continue;
      // Toutes les commandes sont réservées aux serveurs (pas de MP)
      cmd.data.setContexts?.(InteractionContextType.Guild);
      if (commands.has(cmd.data.name)) throw new Error(`commande en double : ${cmd.data.name}`);
      commands.set(cmd.data.name, cmd);
      for (const [prefix, fn] of Object.entries(cmd.components ?? {})) components.set(prefix, fn);
    }
  }
  return { commands, components };
}

function loadModules(client, components) {
  for (const file of walk(path.join(__dirname, '..', 'modules'))) {
    const mod = require(file);
    mod.setup?.(client);
    for (const [prefix, fn] of Object.entries(mod.components ?? {})) components.set(prefix, fn);
  }
}

async function registerGuild(guild, commands) {
  try {
    await guild.commands.set(commands.map((c) => c.data.toJSON()));
  } catch (err) {
    console.error(`[commandes] impossible d'enregistrer sur ${guild.name} :`, err.message);
  }
}

module.exports = { loadCommands, loadModules, registerGuild };
