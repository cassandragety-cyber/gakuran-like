--!strict
--[[
	Invariants du contenu et des conventions : table de raretés, budgets réseau,
	noms de stockage, règles produit de la monétisation.

	Plusieurs de ces contrôles font respecter une décision produit plutôt qu'une
	contrainte technique (pas de pity sur Mythic, rien qui vende du combat, clés
	de stockage versionnées). Ils sont ici parce qu'une règle appliquée par le
	programme survit mieux qu'une règle écrite dans un document.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Check = require(script.Parent.Check)
local DataStores = require(ReplicatedStorage.Config.DataStores)
local Monetization = require(ReplicatedStorage.Config.Monetization)
local Rarity = require(ReplicatedStorage.Config.Styles.Rarity)
local RateLimits = require(ReplicatedStorage.Config.RateLimits)

local check = Check.check
local isPositive = Check.isPositive
local EPSILON = Check.EPSILON

local M = {}

function M.validateRarity(problems: { string })
	local order = Rarity.ORDER
	local weights = (Rarity.WEIGHTS :: any) :: { [string]: number }
	local colors = (Rarity.COLORS :: any) :: { [string]: Color3 }

	local total = 0
	local declared: { [string]: boolean } = {}

	for _, name in order do
		declared[name] = true
		local weight = weights[name]
		check(problems, isPositive(weight), `Rarity.WEIGHTS.{name} doit être un nombre > 0`)
		check(problems, colors[name] ~= nil, `Rarity.COLORS.{name} manquant`)
		if type(weight) == "number" then
			total += weight
		end
	end

	for name in weights do
		check(problems, declared[name] == true, `Rarity.WEIGHTS.{name} absent de Rarity.ORDER`)
	end

	check(
		problems,
		math.abs(total - 100) < EPSILON,
		`la somme des poids de rareté vaut {total}, elle doit valoir exactement 100`
	)

	local threshold = Rarity.PITY_THRESHOLD
	check(
		problems,
		type(threshold) == "number" and threshold >= 0 and threshold % 1 == 0,
		"Rarity.PITY_THRESHOLD doit être un entier >= 0 (0 = pity désactivé)"
	)

	if type(threshold) == "number" and threshold > 0 then
		local target = Rarity.PITY_TARGET_RARITY
		check(
			problems,
			declared[target] == true,
			`Rarity.PITY_TARGET_RARITY « {target} » n'est pas une rareté connue`
		)
		-- Décision produit figée : un Mythic garanti détruirait la valeur du
		-- Mythic. Le jour où quelqu'un tente ce raccourci, le serveur refuse.
		check(
			problems,
			target ~= "Mythic",
			"Rarity.PITY_TARGET_RARITY ne peut pas être Mythic : aucun pity sur Mythic"
		)
	end

	for _, name in Rarity.PITY_RESET_ON do
		check(
			problems,
			declared[name] == true,
			`Rarity.PITY_RESET_ON contient une rareté inconnue : {name}`
		)
	end
end

function M.validateRateLimits(problems: { string })
	local entries = (RateLimits :: any) :: { [string]: any }

	check(
		problems,
		type(entries.Default) == "table",
		"Config/RateLimits doit définir une limite Default"
	)
	check(
		problems,
		type(entries.ViolationsBeforeKick) == "number" and entries.ViolationsBeforeKick > 0,
		"Config/RateLimits.ViolationsBeforeKick doit être un nombre > 0"
	)

	for key, value in entries do
		if type(value) ~= "table" then
			continue
		end
		check(problems, isPositive(value.capacity), `RateLimits.{key}.capacity doit être > 0`)
		check(
			problems,
			isPositive(value.refillPerSecond),
			`RateLimits.{key}.refillPerSecond doit être > 0`
		)
	end
end

function M.validateDataStores(problems: { string })
	for key, value in (DataStores :: any) :: { [string]: any } do
		if type(value) ~= "string" then
			continue
		end
		-- Convention figée : le nom d'affichage du jeu peut changer, les clés non.
		check(
			problems,
			string.match(value, "^Banchou_%a+_v%d+$") ~= nil,
			`DataStores.{key} = « {value} » ne suit pas la convention Banchou_<Nom>_v<N>`
		)
	end

	check(
		problems,
		DataStores.ProfileSchemaVersion >= 1 and DataStores.ProfileSchemaVersion % 1 == 0,
		"DataStores.ProfileSchemaVersion doit être un entier >= 1"
	)
end

--[[
	Garde-fou produit : le brief interdit de vendre de la statistique de combat.
	Cette règle survit mieux dans un test de boot que dans un document.
]]
function M.validateMonetization(problems: { string })
	local groups = {
		{ label = "Gamepasses", entries = (Monetization.Gamepasses :: any) :: { [string]: any } },
		{ label = "DevProducts", entries = (Monetization.DevProducts :: any) :: { [string]: any } },
	}

	for _, group in groups do
		for key, entry in group.entries do
			local label = `Monetization.{group.label}.{key}`
			check(
				problems,
				type(entry.id) == "number" and entry.id >= 0 and entry.id % 1 == 0,
				`{label}.id doit être un entier >= 0 (0 = produit pas encore créé)`
			)
			check(
				problems,
				isPositive(entry.suggestedPrice),
				`{label}.suggestedPrice doit être > 0`
			)
			check(
				problems,
				entry.grantsCombatAdvantage == false,
				`{label} vend un avantage de combat — interdit par la règle produit (brief §5.7)`
			)
		end
	end
end

return M
