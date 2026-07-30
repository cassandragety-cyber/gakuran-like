--!strict
--[[
	Utilitaires de tables. Volontairement minimal : on n'ajoute une fonction ici
	que le jour où un module s'en sert.
]]

local TableUtil = {}

--[[
	Gèle une table et toutes ses sous-tables.

	Tout module de Config/ se termine par `return TableUtil.deepFreeze(T)`. Un
	équilibrage modifié à chaud depuis un script de gameplay est un bug qui ne
	se voit qu'en production, sur un serveur, des heures plus tard : `table.freeze`
	le transforme en erreur immédiate à la ligne fautive.
]]
function TableUtil.deepFreeze<T>(value: T): T
	local asTable = value :: any
	if type(asTable) ~= "table" or table.isfrozen(asTable) then
		return value
	end

	for _, child in pairs(asTable) do
		if type(child) == "table" then
			TableUtil.deepFreeze(child)
		end
	end

	table.freeze(asTable)
	return value
end

--[[
	Copie récursive. Sert à construire la table d'équilibrage vivante à partir de
	`Config/Balance`, qui est gelée : sans copie, le réglage à chaud exigerait de
	dégeler la configuration et ferait perdre la garantie posée en Phase 0
	(ADR-011).
]]
function TableUtil.deepCopy<T>(value: T): T
	local source = value :: any
	if type(source) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(source) do
		copy[key] = if type(child) == "table" then TableUtil.deepCopy(child) else child
	end
	return copy :: any
end

--[[
	Résout un chemin pointé (`"Parry.Window"`, `"Melee.1.windup"`) et retourne le
	conteneur et la clé finale, pour pouvoir lire ET écrire. Un segment
	entièrement numérique est traité comme un index de tableau.

	Retourne `nil` comme premier résultat si le chemin ne mène nulle part — c'est
	un refus normal, pas une erreur : les chemins viennent d'une liste blanche de
	configuration qu'un humain édite, et une faute de frappe doit être signalée,
	pas fatale.
]]
function TableUtil.resolvePath(root: { [any]: any }, path: string): ({ [any]: any }?, any)
	local container: any = root
	local segments = string.split(path, ".")

	for index, segment in segments do
		local key: any = tonumber(segment) or segment
		if type(container) ~= "table" then
			return nil, nil
		end

		if index == #segments then
			if container[key] == nil then
				return nil, nil
			end
			return container, key
		end
		container = container[key]
	end
	return nil, nil
end

return TableUtil
