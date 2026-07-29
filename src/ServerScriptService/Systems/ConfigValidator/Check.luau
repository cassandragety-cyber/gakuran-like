--!strict
--[[
	Primitives partagées par les règles de validation.

	`check` accumule au lieu d'interrompre : on veut la liste complète des
	problèmes de configuration en une passe, pas les découvrir un par un sur dix
	démarrages successifs.
]]

local Check = {}

-- Les durées d'animation sont comparées à des sommes de flottants : on compare
-- à la microseconde, pas à l'identique.
Check.EPSILON = 1e-6

function Check.check(problems: { string }, condition: boolean, message: string)
	if not condition then
		table.insert(problems, message)
	end
end

function Check.isPositive(value: unknown): boolean
	return type(value) == "number" and value > 0
end

return Check
