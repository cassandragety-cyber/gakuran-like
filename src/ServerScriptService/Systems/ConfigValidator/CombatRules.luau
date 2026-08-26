--!strict
--[[
	Invariants de l'équilibrage de combat et du contrat animation <-> gameplay.

	Ce fichier porte la vérification la plus utile du projet : que la durée
	annoncée d'une animation corresponde exactement à la somme des phases que le
	code va cadencer. Sans elle, rien n'empêche l'impact visuel et l'impact réel
	de diverger, et c'est précisément ce qui produit un « hit fantôme ».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Config.Animations)
local Balance = require(ReplicatedStorage.Config.Balance)
local Check = require(script.Parent.Check)

local check = Check.check
local isPositive = Check.isPositive
local EPSILON = Check.EPSILON

local M = {}

function M.validateBalance(problems: { string })
	local combat = Balance.Combat
	local melee = Balance.Melee

	check(problems, isPositive(combat.ComboWindow), "Balance.Combat.ComboWindow doit être > 0")
	check(
		problems,
		combat.DefaultChainLength >= 2 and combat.DefaultChainLength <= combat.MaxChainLength,
		`Balance.Combat.DefaultChainLength doit être entre 2 et {combat.MaxChainLength}`
	)
	check(
		problems,
		#melee == combat.DefaultChainLength,
		`Balance.Melee contient {#melee} coups pour une chaîne de {combat.DefaultChainLength}`
	)

	for index, step in melee do
		local label = `Balance.Melee[{index}]`
		check(problems, isPositive(step.windup), `{label}.windup doit être > 0`)
		check(problems, isPositive(step.active), `{label}.active doit être > 0`)
		check(problems, isPositive(step.recovery), `{label}.recovery doit être > 0`)
		check(problems, isPositive(step.damage), `{label}.damage doit être > 0`)
		check(problems, step.hitstop >= 0, `{label}.hitstop doit être >= 0`)

		-- Le brief impose que ce soit le dernier coup qui envoie au sol : un
		-- knockdown en milieu de chaîne rendrait la suite injouable.
		local shouldKnockdown = index == #melee
		check(
			problems,
			step.knockdown == shouldKnockdown,
			`{label}.knockdown devrait valoir {tostring(shouldKnockdown)} (seul le dernier coup envoie au sol)`
		)
	end

	local parry = Balance.Parry
	check(problems, isPositive(parry.Window), "Balance.Parry.Window doit être > 0")
	check(
		problems,
		parry.Window < combat.ComboWindow,
		"Balance.Parry.Window doit rester inférieure à la fenêtre de combo, sinon le parry couvre tout le chain"
	)
	check(problems, isPositive(parry.AttackerStun), "Balance.Parry.AttackerStun doit être > 0")

	local block = Balance.Block
	check(
		problems,
		block.DamageMultiplier > 0 and block.DamageMultiplier < 1,
		"Balance.Block.DamageMultiplier doit être dans ]0, 1[ : une garde qui annule tout supprime le guard break"
	)
	check(problems, isPositive(block.GuardHealth), "Balance.Block.GuardHealth doit être > 0")

	local dash = Balance.Dash
	check(problems, isPositive(dash.Duration), "Balance.Dash.Duration doit être > 0")
	check(
		problems,
		dash.InvulnerabilityDuration <= dash.Duration,
		"Balance.Dash.InvulnerabilityDuration ne peut pas dépasser la durée du dash"
	)
	check(
		problems,
		dash.Cooldown > dash.Duration,
		"Balance.Dash.Cooldown doit dépasser la durée du dash, sinon le dash est enchaînable sans fin"
	)

	local network = Balance.Network
	check(
		problems,
		network.MaxRewind > 0 and network.MaxRewind <= 0.5,
		"Balance.Network.MaxRewind doit être dans ]0, 0.5] : au-delà, la fenêtre de triche s'ouvre (ADR-001)"
	)
	check(
		problems,
		isPositive(network.ClockTolerance),
		"Balance.Network.ClockTolerance doit être > 0"
	)

	-- La marge de fin de phase active doit rester petite devant la phase active
	-- la plus courte : au-delà, elle cesse d'absorber une frame et devient une
	-- rallonge de la fenêtre de contact, ce qui déplace l'impact réel loin de
	-- l'impact visuel.
	local shortestActive = math.huge
	for _, step in melee do
		shortestActive = math.min(shortestActive, step.active)
	end
	check(
		problems,
		network.ActivePhaseGrace >= 0 and network.ActivePhaseGrace <= shortestActive,
		`Balance.Network.ActivePhaseGrace doit être dans [0, {shortestActive}] : au-delà de la phase active la plus courte, ce n'est plus une tolérance de frame mais une hitbox rallongée`
	)
end

--[[
	Le cœur du contrat animation <-> gameplay : si l'animation dure autre chose
	que la somme des phases, l'impact visuel et l'impact réel divergent. C'est
	la cause classique du « hit fantôme » que le brief interdit.
]]
function M.validateAnimations(problems: { string })
	local byKey = (Animations :: any) :: { [string]: Animations.AnimationDef }

	for key, definition in byKey do
		check(
			problems,
			type(definition.id) == "number" and definition.id >= 0 and definition.id % 1 == 0,
			`Animations.{key}.id doit être un entier >= 0 (0 = fallback procédural)`
		)
		check(
			problems,
			isPositive(definition.targetDuration),
			`Animations.{key}.targetDuration doit être > 0`
		)
	end

	for index, step in Balance.Melee do
		local key = `M1_{index}`
		local animation = byKey[key]
		if not animation then
			table.insert(problems, `Animations.{key} manquant pour Balance.Melee[{index}]`)
			continue
		end

		local expected = step.windup + step.active + step.recovery
		check(
			problems,
			math.abs(animation.targetDuration - expected) < EPSILON,
			`Animations.{key}.targetDuration = {animation.targetDuration} mais Balance.Melee[{index}] totalise {expected}`
		)
	end

	local pairsToMatch: { { key: string, expected: number, source: string } } = {
		{ key = "DashForward", expected = Balance.Dash.Duration, source = "Balance.Dash.Duration" },
		{
			key = "DashBackward",
			expected = Balance.Dash.Duration,
			source = "Balance.Dash.Duration",
		},
		{ key = "DashLeft", expected = Balance.Dash.Duration, source = "Balance.Dash.Duration" },
		{ key = "DashRight", expected = Balance.Dash.Duration, source = "Balance.Dash.Duration" },
		{
			key = "GuardBreak",
			expected = Balance.Block.GuardBreakStun,
			source = "Balance.Block.GuardBreakStun",
		},
		{
			key = "Stun",
			expected = Balance.Parry.AttackerStun,
			source = "Balance.Parry.AttackerStun",
		},
		{
			key = "GetUp",
			expected = Balance.Knockdown.GetUpDuration,
			source = "Balance.Knockdown.GetUpDuration",
		},
	}

	for _, entry in pairsToMatch do
		local animation = byKey[entry.key]
		if not animation then
			table.insert(problems, `Animations.{entry.key} manquant`)
			continue
		end
		check(
			problems,
			math.abs(animation.targetDuration - entry.expected) < EPSILON,
			`Animations.{entry.key}.targetDuration = {animation.targetDuration} mais {entry.source} vaut {entry.expected}`
		)
	end

	check(
		problems,
		byKey.BlockStart ~= nil and byKey.BlockStart.targetDuration <= Balance.Parry.Window,
		"Animations.BlockStart doit se lire en moins que Balance.Parry.Window, sinon le parry est invisible"
	)
end

return M
