--!strict
--[[
	Validation de la configuration au démarrage.

	Pourquoi ce module existe : la règle d'or du projet veut que tout
	l'équilibrage vive dans Config/, éditable sans lire de code. Le corollaire
	est qu'une faute de frappe dans Config/ doit être attrapée immédiatement et
	bruyamment, sinon elle part en production sous forme de comportement bizarre
	(un parry impossible, une animation désynchronisée du hit) que personne ne
	relie à un fichier de données.

	Il est délibérément placé dans Systems/ et non dans Config/ : c'est de la
	logique, et Config/ n'en contient pas.

	Découpage : `CombatRules` pour l'équilibrage et le contrat d'animation,
	`ContentRules` pour le contenu et les conventions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRules = require(script.CombatRules)
local ContentRules = require(script.ContentRules)
local Result = require(ReplicatedStorage.Shared.Result)

local ConfigValidator = {}

function ConfigValidator.validate(): Result.Result<true>
	local problems: { string } = {}

	ContentRules.validateRarity(problems)
	CombatRules.validateBalance(problems)
	CombatRules.validateAnimations(problems)
	ContentRules.validateRateLimits(problems)
	ContentRules.validateDataStores(problems)
	ContentRules.validateMonetization(problems)

	if #problems > 0 then
		return Result.err(
			"ConfigInvalid",
			`{#problems} problème(s) :\n  - {table.concat(problems, "\n  - ")}`
		)
	end
	return Result.ok(true)
end

return ConfigValidator
