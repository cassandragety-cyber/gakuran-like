--!strict
--[[
	Horloge de référence unique du projet.

	`workspace:GetServerTimeNow()` renvoie le même temps serveur sur le client
	et sur le serveur, à la dérive de synchronisation près. C'est la seule base
	valable pour arbitrer le parry côté serveur (ADR-002) et pour rembobiner
	les positions (ADR-001) : `tick()` et `os.time()` ne sont pas comparables
	entre deux machines.

	Règle : toute logique de combat qui manipule un instant passe par ce module.
	`monotonic()` sert uniquement aux mesures de durée locales (profiler, RTT),
	jamais à une comparaison client/serveur.
]]

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

function Clock.monotonic(): number
	return os.clock()
end

return Clock
