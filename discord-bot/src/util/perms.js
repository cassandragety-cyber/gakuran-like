// Hiérarchie des droits du bot :
//   buyer   → IDs dans OWNER_IDS (.env), tous les droits
//   owner   → ajoutés via /owner, gèrent la sécurité sur tous les serveurs
//   trusted → buyer, owner ou propriétaire du serveur
//   whitelist → ignorés par l'antiraid (sauf modules en mode « max »)
const { PermissionFlagsBits } = require('discord.js');
const config = require('../config');
const db = require('../db');

const isBuyer = (id) => config.ownerIds.includes(id);
const isOwner = (id) => isBuyer(id) || db.global.owners.includes(id);
const isTrusted = (guild, id) => isOwner(id) || guild?.ownerId === id;

function isWhitelisted(guild, member) {
  const id = member?.id ?? member;
  if (isTrusted(guild, id)) return true;
  const wl = db.guild(guild.id).security.whitelist;
  if (wl.users.includes(id)) return true;
  const roles = member?.roles?.cache;
  return !!roles && wl.roles.some((r) => roles.has(r));
}

// Permissions qu'on considère comme « dangereuses » (antirank, rolemenu…)
const DANGEROUS = [
  PermissionFlagsBits.Administrator, PermissionFlagsBits.ManageGuild, PermissionFlagsBits.ManageRoles,
  PermissionFlagsBits.ManageChannels, PermissionFlagsBits.BanMembers, PermissionFlagsBits.KickMembers,
  PermissionFlagsBits.ManageWebhooks, PermissionFlagsBits.MentionEveryone, PermissionFlagsBits.ModerateMembers,
  PermissionFlagsBits.ManageGuildExpressions, PermissionFlagsBits.ManageMessages,
];
const isDangerousRole = (role) => DANGEROUS.some((p) => role.permissions.has(p, false));

// Vérifie qu'un modérateur peut agir sur une cible. Renvoie un message d'erreur ou null.
function checkHierarchy(interaction, target, action = 'sanctionner') {
  const { guild, member: mod } = interaction;
  const me = guild.members.me;
  if (!target) return null; // utilisateur hors serveur : seul le ban/unban s'applique
  if (target.id === mod.id) return `Tu ne peux pas te ${action} toi-même.`;
  if (target.id === me.id) return `Je ne peux pas me ${action} moi-même.`;
  if (target.id === guild.ownerId) return `Impossible de ${action} le propriétaire du serveur.`;
  if (isOwner(target.id) && !isBuyer(mod.id)) return `Ce membre est owner du bot, impossible de le ${action}.`;
  if (mod.id !== guild.ownerId && !isOwner(mod.id) && target.roles.highest.position >= mod.roles.highest.position)
    return `Ce membre a un rôle supérieur ou égal au tien.`;
  if (target.roles.highest.position >= me.roles.highest.position)
    return `Mon rôle est trop bas pour ${action} ce membre. Monte mon rôle dans les paramètres du serveur.`;
  return null;
}

module.exports = { isBuyer, isOwner, isTrusted, isWhitelisted, isDangerousRole, DANGEROUS, checkHierarchy };
