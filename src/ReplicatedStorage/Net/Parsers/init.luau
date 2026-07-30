--!strict
--[[
	Primitives de reconstruction des payloads réseau.

	Chaque fonction RECONSTRUIT une valeur propre au lieu de valider sur place la
	table reçue : champs supplémentaires, métatables et pièges `__index` ne
	franchissent donc jamais cette frontière (docs/THREAT_MODEL.md §1).

	Découpé par domaine : ici les briques, dans `Session` et `Combat` les payloads
	qui les composent.
]]

local Parsers = {}

--[[
	Un entier fini dans une plage donnée. Rejette NaN, l'infini et les
	flottants — la plupart des payloads de gameplay sont des compteurs, et
	accepter 1.9999 quelque part finit toujours par produire un `nil` d'index.
]]
function Parsers.parseInteger(value: unknown, minimum: number, maximum: number): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value % 1 ~= 0 or value < minimum or value > maximum then
		return nil
	end
	return value
end

function Parsers.parseFiniteNumber(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function Parsers.parseBoolean(value: unknown): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

--[[
	Reconstruit un CombatState. Les champs d'échéance sont optionnels : `nil` y
	signifie « pas d'échéance », ce qui est un état légitime (une garde maintenue
	n'expire pas). On distingue donc « absent » de « invalide ».
]]
function Parsers.parseOptionalNumber(value: unknown): (boolean, number?)
	if value == nil then
		return true, nil
	end
	local parsed = Parsers.parseFiniteNumber(value)
	if parsed == nil then
		return false, nil
	end
	return true, parsed
end

--[[
	Un modèle envoyé comme cible. On ne vérifie ici que la FORME : c'est une
	instance, c'est un Model, il est encore dans l'arbre. La question « est-ce un
	combattant connu ? » appartient au serveur, qui seul détient le registre — un
	parseur qui y répondrait devrait connaître l'état du jeu.
]]
function Parsers.parseModel(value: unknown): Model?
	if typeof(value) ~= "Instance" then
		return nil
	end
	local instance = value :: Instance
	if not instance:IsA("Model") or instance.Parent == nil then
		return nil
	end
	return instance
end

return Parsers
