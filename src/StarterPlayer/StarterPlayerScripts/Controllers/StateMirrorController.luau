--!strict
--[[
	Miroir local de l'état autoritatif.

	Tranche 1.1 : le client ne prédit encore rien, ce module ne fait donc que
	conserver ce que le serveur envoie. C'est délibérément une couture et non un
	raccourci — à partir de la tranche 1.2, `predicted()` divergera de
	`authoritative()` et le panneau de debug affichera l'écart, qui est
	l'instrument principal du réglage de la parade (COMBAT.md §5, cas 2).

	Conserver l'instant de réception permet de savoir si l'affichage est frais :
	un état vieux de 400 ms explique bien des « bugs » qui n'en sont pas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Net = require(ReplicatedStorage.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local StateMirrorController = {}

export type Mirror = {
	sync: Types.StateSync,
	receivedAt: number,
}

local mirrors: { [number]: Mirror } = {}
local listeners: { (mirror: Mirror) -> () } = {}

function StateMirrorController.of(userId: number): Mirror?
	return mirrors[userId]
end

function StateMirrorController.own(): Mirror?
	return mirrors[Players.LocalPlayer.UserId]
end

--[[
	État que le client considère comme le sien à l'instant présent. Identique à
	l'autorité en tranche 1.1 ; la prédiction locale s'insérera ici.
]]
function StateMirrorController.predicted(): CombatTypes.CombatState?
	local mirror = StateMirrorController.own()
	return if mirror then mirror.sync.state else nil
end

function StateMirrorController.authoritative(): CombatTypes.CombatState?
	local mirror = StateMirrorController.own()
	return if mirror then mirror.sync.state else nil
end

function StateMirrorController.onSync(listener: (mirror: Mirror) -> ())
	table.insert(listeners, listener)
end

function StateMirrorController.Init()
	Net.Client.on(Definitions.CombatStateSync, function(payload)
		local mirror: Mirror = { sync = payload, receivedAt = Clock.now() }
		mirrors[payload.userId] = mirror

		for _, listener in listeners do
			task.spawn(listener, mirror)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		mirrors[player.UserId] = nil
	end)
end

return StateMirrorController
