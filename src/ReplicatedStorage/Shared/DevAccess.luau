--!strict
--[[
	Qui a le droit aux outils de développement.

	Deux questions distinctes, et c'est volontaire :
	  - `isEnabled()` : ce serveur doit-il *créer* les remotes de développement ?
	    Décision prise une fois au boot (ADR-013).
	  - `isAllowed(player)` : ce joueur précis peut-il s'en servir ? Vérifié à
	    chaque appel, parce qu'un serveur en Studio accepte tout le monde alors
	    qu'un serveur de production n'accepte que la liste.

	Le défaut compte : `AdminUserIds` vide signifie qu'en production les remotes
	n'existent pas et que la table d'équilibrage vivante est regelée.
]]

local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Parent.Config.Debug)

local DevAccess = {}

function DevAccess.isEnabled(): boolean
	return RunService:IsStudio() or #Debug.AdminUserIds > 0
end

function DevAccess.isAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(Debug.AdminUserIds, player.UserId) ~= nil
end

return DevAccess
