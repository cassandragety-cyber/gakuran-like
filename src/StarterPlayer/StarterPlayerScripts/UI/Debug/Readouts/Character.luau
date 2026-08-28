--!strict
--[[
	Lignes du panneau qui décrivent LE PERSONNAGE : état, ressources, garde,
	parade.

	Ce sont celles qu'on regarde en réglant une valeur d'équilibrage — un
	cooldown, une jauge, une fenêtre. Séparées des lignes de diagnostic technique
	(`Diagnostics`) parce qu'on ne les consulte pas au même moment ni pour la
	même raison.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent.Parent.Parent.Parent.Controllers
local Format = require(script.Parent.Format)
local GuardController = require(Controllers.GuardController)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local StateMirrorController = require(Controllers.StateMirrorController)
local Theme = require(script.Parent.Parent.Parent.Theme)
local TuningController = require(Controllers.TuningController)

local remaining = Format.remaining

local rows: { Format.Readout } = {
	{
		section = "État",
		label = "État",
		read = function(_now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			if state == nil then
				return "en attente du serveur", Theme.Colors.Warning
			end
			return state.name,
				if state.name == "Idle" then Theme.Colors.TextMuted else Theme.Colors.Accent
		end,
	},
	{
		section = "État",
		label = "Phase",
		read = function(now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			if state == nil then
				return "—"
			end
			local phase = StateMachine.phaseOf(state, now, TuningController.balance())
			return phase or "—"
		end,
	},
	{
		section = "État",
		label = "Échéance",
		read = function(now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			return remaining(if state then state.expiresAt else nil, now)
		end,
	},
	{
		section = "État",
		label = "Index de chaîne",
		read = function(_now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			return if state then tostring(state.chainIndex) else "—"
		end,
	},
	{
		section = "État",
		label = "Chaîne expire dans",
		read = function(now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			return remaining(if state then state.chainDeadline else nil, now)
		end,
	},

	{
		section = "Ressources",
		label = "PV",
		read = function(_now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			if mirror == nil then
				return "—"
			end
			local max = TuningController.balance().Character.MaxHealth
			return string.format("%d / %d", math.floor(mirror.sync.health), max)
		end,
	},
	{
		section = "Ressources",
		label = "Endurance",
		read = function(_now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			if mirror == nil then
				return "—"
			end
			local balance = TuningController.balance()
			local value = mirror.sync.stamina
			local color = if value <= balance.Stamina.MinimumToAct
				then Theme.Colors.Warning
				else Theme.Colors.Text
			return string.format("%d / %d", math.floor(value), balance.Stamina.Max), color
		end,
	},
	{
		section = "Ressources",
		label = "Jauge de garde",
		read = function(_now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			if mirror == nil then
				return "—"
			end
			local balance = TuningController.balance()
			local value = mirror.sync.guard
			-- Seuil d'alerte : ce qu'un finisher retire d'un coup. En dessous, la
			-- prochaine garde tenue contre le 4e coup casse — c'est l'information
			-- utile pour régler `GuardHealth`, pas le pourcentage brut.
			local color = if value <= balance.Melee[#balance.Melee].damage
				then Theme.Colors.Warning
				else Theme.Colors.Text
			return string.format("%d / %d", math.floor(value), balance.Block.GuardHealth), color
		end,
	},
	{
		section = "Garde",
		label = "Demandée / accordée",
		read = function(_now: number): (string, Color3?)
			local authoritative = StateMirrorController.authoritative()
			local granted = authoritative ~= nil and authoritative.name == "Blocking"
			local requested = GuardController.isHeld()

			--[[
				Les deux valeurs divergent normalement le temps d'un aller-retour.
				Une divergence QUI DURE veut dire autre chose : garde refusée
				(cooldown de parade), ou guard break en cours. C'est la ligne qui
				distingue « le serveur n'a pas encore répondu » de « le serveur a
				dit non », deux situations identiques à l'écran.
			]]
			local color = if requested == granted then Theme.Colors.Text else Theme.Colors.Warning
			return string.format(
				"%s / %s",
				if requested then "oui" else "non",
				if granted then "oui" else "non"
			),
				color
		end,
	},
	{
		section = "Garde",
		label = "Dernier refus",
		read = function(_now: number): (string, Color3?)
			local refusal, age = GuardController.lastRefusal()
			if refusal == nil then
				return "aucun", Theme.Colors.TextMuted
			end
			return string.format("%s · %.1f s", refusal, age), Theme.Colors.Warning
		end,
	},

	{
		section = "Parade",
		label = "Fenêtre ouverte",
		read = function(now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			if state == nil then
				return "—"
			end
			if StateMachine.isParryWindowOpen(state, now) then
				return "OUI", Theme.Colors.Good
			end
			return "non", Theme.Colors.TextMuted
		end,
	},
	{
		section = "Parade",
		label = "Fenêtre restante",
		read = function(now: number): (string, Color3?)
			local state = StateMirrorController.authoritative()
			if state == nil or state.name ~= "Blocking" then
				return "—"
			end
			return remaining(state.windowUntil, now)
		end,
	},
	{
		section = "Parade",
		label = "Cooldown",
		read = function(now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			return remaining(if mirror then mirror.sync.parryReadyAt else nil, now)
		end,
	},
	{
		section = "Parade",
		label = "Cooldown de dash",
		read = function(now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			return remaining(if mirror then mirror.sync.dashReadyAt else nil, now)
		end,
	},
}

return rows
