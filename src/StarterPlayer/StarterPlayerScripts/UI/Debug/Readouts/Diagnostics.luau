--!strict
--[[
	Lignes du panneau qui décrivent LA MACHINERIE : réseau, prédiction, combat,
	performance, entrées.

	On les consulte quand quelque chose ne marche pas, pas quand on règle
	l'équilibrage. C'est ce qui justifie la séparation d'avec `Character` : deux
	usages, deux moments, deux fichiers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent.Parent.Parent.Parent.Controllers
local AnimationController = require(Controllers.AnimationController)
local CombatController = require(Controllers.CombatController)
local DiagnosticsController = require(Controllers.DiagnosticsController)
local Format = require(script.Parent.Format)
local InputController = require(Controllers.InputController)
local Profiler = require(ReplicatedStorage.Shared.Profiler)
local StateMirrorController = require(Controllers.StateMirrorController)
local Theme = require(script.Parent.Parent.Parent.Theme)

local rows: { Format.Readout } = {
	{
		section = "Réseau",
		label = "RTT médian",
		read = function(_now: number): (string, Color3?)
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
		section = "Prédiction",
		label = "État prédit",
		read = function(_now: number): (string, Color3?)
			return StateMirrorController.predicted().name, Theme.Colors.TextMuted
		end,
	},
	{
		section = "Prédiction",
		label = "Écarts",
		read = function(_now: number): (string, Color3?)
			local divergence = StateMirrorController.divergence()
			if divergence.count == 0 then
				return "0", Theme.Colors.Good
			end
			-- Rouge dès le premier écart : à latence nulle en Studio il ne devrait
			-- jamais y en avoir, donc tout écart mérite d'être regardé.
			return string.format("%d · %s", divergence.count, divergence.last or "—"),
				Theme.Colors.Accent
		end,
	},
	{
		section = "Combat",
		label = "Coups envoyés",
		read = function(_now: number): (string, Color3?)
			local sent = CombatController.sentCount()
			return tostring(sent), if sent == 0 then Theme.Colors.Warning else Theme.Colors.Good
		end,
	},
	{
		section = "Combat",
		label = "Dernier verdict",
		read = function(_now: number): (string, Color3?)
			local verdict = CombatController.lastOutcome()
			return verdict or "—", if verdict then Theme.Colors.Good else Theme.Colors.TextMuted
		end,
	},
	{
		section = "Combat",
		label = "Dernier refus",
		read = function(_now: number): (string, Color3?)
			local _, refusal, age = CombatController.lastOutcome()
			if refusal == nil then
				return "aucun", Theme.Colors.TextMuted
			end
			return string.format("%s · %.1f s", refusal, age), Theme.Colors.Warning
		end,
	},
	{
		section = "Performance",
		label = "Hitbox p95",
		read = function(_now: number): (string, Color3?)
			local snapshot = Profiler.snapshot("hitbox")
			if snapshot == nil then
				return "aucun échantillon", Theme.Colors.TextMuted
			end
			-- Budget de la Phase 1 : 0,15 ms par ouverture.
			local color = if snapshot.p95Ms > 0.15 then Theme.Colors.Accent else Theme.Colors.Good
			return string.format("%.3f ms  (n=%d)", snapshot.p95Ms, snapshot.totalCalls), color
		end,
	},
	{
		section = "Performance",
		label = "Rig posable",
		read = function(_now: number): (string, Color3?)
			local rig, resolved, required, bound = AnimationController.rigStatus()
			if not bound then
				return "moteur de pose non démarré", Theme.Colors.Accent
			end
			--[[
				Trois pannes se ressemblent à l'écran — personnage immobile — et ne
				se corrigent pas au même endroit : rig non lié, pose non déclenchée,
				pose déclenchée sans jointure où l'écrire. Cette ligne les sépare.

				Zéro jointure posable est la panne qui a coûté la recette de la
				1.3 : une place réglée en R6 alors que les poses sont écrites en
				noms R15.
			]]
			local color = if resolved == 0
				then Theme.Colors.Accent
				elseif resolved < required then Theme.Colors.Warning
				else Theme.Colors.Good
			return string.format("%s · %d/%d jointures", rig, resolved, required), color
		end,
	},
	{
		section = "Performance",
		label = "Animations",
		read = function(_now: number): (string, Color3?)
			local loaded, procedural = AnimationController.counts()
			--[[
				« assets / poses » : c'est la ligne qui dit si une animation livrée a
				réellement remplacé son repli procédural. Tant qu'aucun asset n'est
				branché, `Config/Animations` est plein de 0 et ce compteur reste à
				zéro — ce qui est l'état normal du projet aujourd'hui, pas un défaut.
			]]
			return string.format("%d asset(s) · %d pose(s) active(s)", loaded, procedural),
				if loaded == 0 then Theme.Colors.TextMuted else Theme.Colors.Good
		end,
	},
	{
		section = "Entrées",
		label = "Dernière action",
		read = function(_now: number): (string, Color3?)
			local action, age, listeners = InputController.lastFired()
			if action == nil then
				return "aucune", Theme.Colors.TextMuted
			end
			-- Le nombre d'abonnés distingue « l'entrée n'arrive pas » de « l'entrée
			-- arrive mais personne ne l'écoute ». Les deux se ressemblent à l'écran
			-- et ne se corrigent pas au même endroit.
			return string.format("%s · %d abonné(s) · %.1f s", action, listeners, age),
				if listeners == 0 then Theme.Colors.Accent else Theme.Colors.Text
		end,
	},
}

return rows
