--!strict
--[[
	Intention de sprint.

	Le client n'écrit pas sa vitesse : il envoie « je veux courir » et le serveur
	décide. On ne renvoie l'intention que lorsqu'elle change réellement, pour ne
	pas dépenser un paquet par frame sur une touche maintenue.

	Le relâchement est renvoyé même si le serveur a déjà coupé le sprint faute
	d'endurance : sans ça, un joueur qui relâche après épuisement laisserait le
	serveur croire qu'il court encore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local InputController = require(script.Parent.InputController)
local Net = require(ReplicatedStorage.Net)

local MovementController = {}

MovementController.Dependencies = { "InputController" }

local sprintRequested = false

function MovementController.isSprintRequested(): boolean
	return sprintRequested
end

local function send(active: boolean)
	if sprintRequested == active then
		return
	end
	sprintRequested = active

	Net.Client.fire(Definitions.MoveSprintState, {
		active = active,
		clientTime = Clock.now(),
	})
end

function MovementController.Init()
	InputController.onAction("Sprint", function(phase)
		send(phase == "Begin")
	end)
end

return MovementController
