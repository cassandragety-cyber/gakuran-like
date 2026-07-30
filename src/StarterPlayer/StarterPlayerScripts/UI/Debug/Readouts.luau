--!strict
--[[
	Ce que le panneau de debug affiche, décrit en données.

	Une ligne = un libellé et une fonction de lecture. Ajouter un indicateur quand
	une tranche ultérieure produit la valeur correspondante est donc une entrée
	dans cette table, pas une modification du contrôleur. C'est aussi pourquoi le
	panneau n'affiche que ce qui existe réellement aujourd'hui : l'écart de
	prédiction et le coût des hitbox arriveront avec les tranches qui les
	produisent, pas comme des cases vides.

	Chaque `read` reçoit l'instant courant afin que toutes les lignes d'un même
	rafraîchissement soient cohérentes entre elles : lire l'horloge ligne par ligne
	produirait un affichage où une échéance est écoulée et la suivante non.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent.Parent.Parent.Controllers
local DiagnosticsController = require(Controllers.DiagnosticsController)
local InputController = require(Controllers.InputController)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local StateMirrorController = require(Controllers.StateMirrorController)
local Theme = require(script.Parent.Parent.Theme)
local TuningController = require(Controllers.TuningController)

type Reading = (now: number) -> (string, Color3?)

local function seconds(value: number): string
	return string.format("%.2f s", value)
end

local function remaining(deadline: number?, now: number): (string, Color3?)
	if deadline == nil then
		return "—"
	end
	local left = deadline - now
	if left <= 0 then
		return "écoulé", Theme.Colors.TextMuted
	end
	return seconds(left), Theme.Colors.Good
end

export type Readout = {
	section: string,
	label: string,
	read: Reading,
}

local Readouts = {}

Readouts.rows = {
	{
		section = "État",
		label = "État",
		read = function(): (string, Color3?)
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
		read = function(): (string, Color3?)
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
		read = function(): (string, Color3?)
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
		read = function(): (string, Color3?)
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
		read = function(): (string, Color3?)
			local mirror = StateMirrorController.own()
			if mirror == nil then
				return "—"
			end
			return string.format(
				"%d / %d",
				math.floor(mirror.sync.guard),
				TuningController.balance().Block.GuardHealth
			)
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

	{
		section = "Réseau",
		label = "RTT médian",
		read = function(): (string, Color3?)
			local rtt = DiagnosticsController.medianRoundTrip()
			if rtt == nil then
				return "en cours de mesure", Theme.Colors.TextMuted
			end
			return string.format("%d ms", math.floor(rtt * 1000))
		end,
	},
	{
		section = "Réseau",
		label = "Fraîcheur de l'état",
		read = function(now: number): (string, Color3?)
			local mirror = StateMirrorController.own()
			if mirror == nil then
				return "—"
			end
			local age = (now - mirror.receivedAt) * 1000
			-- Au-delà de 250 ms, l'affichage décrit un passé dont le joueur ne
			-- peut plus rien déduire : autant le signaler franchement.
			local color = if age > 250 then Theme.Colors.Accent else Theme.Colors.TextMuted
			return string.format("%d ms", math.floor(age)), color
		end,
	},
	{
		section = "Entrées",
		label = "Dernière action",
		read = function(): (string, Color3?)
			local action, age = InputController.lastFired()
			if action == nil then
				return "aucune", Theme.Colors.TextMuted
			end
			return string.format("%s · %.1f s", action, age)
		end,
	},
}

return Readouts
