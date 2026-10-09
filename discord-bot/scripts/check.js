// Vérification hors ligne : charge toutes les commandes et modules, et contrôle
// les règles que Discord impose aux commandes / (sans avoir besoin du token).
const path = require('node:path');
const { ApplicationCommandOptionType: T } = require('discord.js');
const { loadCommands } = require('../src/handlers/commands');

const errors = [];
const { commands } = loadCommands();

function checkOptions(where, options = []) {
  let optionalSeen = false;
  if (options.length > 25) errors.push(`${where} : plus de 25 options`);
  for (const o of options) {
    const w = `${where} ${o.name}`;
    if (!/^[-_\p{L}\p{N}]{1,32}$/u.test(o.name) || o.name !== o.name.toLowerCase()) errors.push(`${w} : nom invalide`);
    if (!o.description || o.description.length > 100) errors.push(`${w} : description vide ou > 100`);
    if (o.choices?.length > 25) errors.push(`${w} : plus de 25 choix`);
    for (const c of o.choices ?? []) if (c.name.length > 100) errors.push(`${w} : choix trop long`);
    if (o.type === T.Subcommand || o.type === T.SubcommandGroup) checkOptions(w, o.options);
    else {
      if (o.required && optionalSeen) errors.push(`${w} : option obligatoire après une facultative`);
      if (!o.required) optionalSeen = true;
    }
  }
}

let size = 0;
for (const cmd of commands.values()) {
  const json = cmd.data.toJSON();
  size += JSON.stringify(json).length;
  if (!cmd.category) errors.push(`/${json.name} : pas de catégorie`);
  if (typeof cmd.run !== 'function') errors.push(`/${json.name} : pas de run()`);
  checkOptions(`/${json.name}`, json.options);
}
if (commands.size > 100) errors.push(`${commands.size} commandes : Discord en accepte 100 maximum`);

// Les modules doivent au moins se charger
for (const f of require('node:fs').readdirSync(path.join(__dirname, '..', 'src', 'modules'))) require(path.join(__dirname, '..', 'src', 'modules', f));

if (errors.length) {
  console.error(`❌ ${errors.length} problème(s) :\n${errors.map((e) => `  - ${e}`).join('\n')}`);
  process.exit(1);
}
console.log(`✅ ${commands.size} commandes valides (${(size / 1024).toFixed(1)} Ko), modules chargés.`);
