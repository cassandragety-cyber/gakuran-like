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

return TableUtil
