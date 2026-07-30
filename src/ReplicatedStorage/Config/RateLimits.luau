--!strict
--[[
	Budget d'appels par joueur et par remote (ADR-005).

	`capacity` = taille de la rafale tolérée, `refillPerSecond` = cadence
	soutenable. La clé doit correspondre au champ `rateLimit` d'une entrée de
	Net/Definitions ; Config.validate() vérifie la correspondance dans les deux
	sens au boot, pour qu'un remote ne puisse jamais exister sans limite.

	Chaque nouvelle entrée ici implique une ligne dans docs/THREAT_MODEL.md.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type Limit = {
	capacity: number,
	refillPerSecond: number,
}

local RateLimits = {
	-- Filet de sécurité si un remote oublie sa limite : volontairement strict,
	-- pour que l'oubli se remarque en test plutôt qu'en production.
	Default = { capacity = 5, refillPerSecond = 2 } :: Limit,

	-- Diagnostic : 3 mesures à la connexion, puis une mesure à la demande.
	SystemPing = { capacity = 6, refillPerSecond = 0.5 } :: Limit,

	-- Réplication d'état : sens serveur -> client uniquement, donc jamais
	-- consommée. L'entrée existe parce que le contrat exige une limite déclarée
	-- pour chaque remote, sans exception à retenir.
	CombatStateSync = { capacity = 60, refillPerSecond = 30 } :: Limit,

	-- Intention de sprint : deux messages par course (début, fin). Une rafale de
	-- 6 couvre un joueur qui tapote la touche, la cadence soutenue non.
	MoveSprint = { capacity = 6, refillPerSecond = 3 } :: Limit,

	-- Réglage à chaud : un curseur qu'on fait glisser produit une rafale
	-- légitime. Généreux, mais le remote n'existe pas en production (ADR-013).
	DebugTuning = { capacity = 30, refillPerSecond = 15 } :: Limit,

	-- Nombre d'infractions (rate-limit dépassé OU payload malformé) tolérées
	-- avant kick. Un client légitime ne produit jamais de payload malformé :
	-- au-delà de ce seuil, c'est un outil, pas de la latence.
	ViolationsBeforeKick = 12,

	-- Message affiché au kick. Volontairement neutre : on ne détaille pas la
	-- règle franchie, ça aide surtout celui qui la teste.
	KickMessage = "Connexion interrompue : trop de requêtes envoyées. Reconnectez-vous.",
}

return TableUtil.deepFreeze(RateLimits)
