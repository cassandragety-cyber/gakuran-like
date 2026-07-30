--!strict
--[[
	Miroir de l'état autoritatif, et prédiction locale.

	Le client tient deux états : celui que le serveur a confirmé, et celui qu'il
	prédit. La prédiction n'est pas un luxe — c'est ce qui permet d'ouvrir la
	hitbox au bon instant local. Sans elle, à 150 ms de latence, le joueur verrait
	son coup partir un tiers de seconde après avoir cliqué.

	La prédiction utilise **le même module** que l'arbitrage serveur
	(`Shared/Combat/StateMachine`), avec une seule différence : le client
	n'applique jamais de transition imposée de sa propre initiative. Un `Stunned`,
	un `Knocked` ou un `Downed` ne peuvent lui arriver que du serveur.

	Quand les deux états divergent, l'autorité gagne, et l'écart est compté. Ce
	compteur est l'instrument principal du réglage de la parade en tranche 1.4
	(COMBAT.md §5, cas 2) : il transforme « ça a l'air bizarre » en un nombre.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Net = require(ReplicatedStorage.Net)
local Result = require(ReplicatedStorage.Shared.Result)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local TuningController = require(script.Parent.TuningController)
local Types = require(ReplicatedStorage.Shared.Types)

type CombatState = CombatTypes.CombatState
type StateName = CombatTypes.StateName

local StateMirrorController = {}

StateMirrorController.Dependencies = { "TuningController" }

export type Mirror = {
	sync: Types.StateSync,
	receivedAt: number,
}

export type Divergence = {
	count: number,
	last: string?,
	lastAt: number,
}

local mirrors: { [number]: Mirror } = {}
local predicted: CombatState = StateMachine.idle(0)
local divergence: Divergence = { count = 0, last = nil, lastAt = 0 }
local listeners: { (mirror: Mirror) -> () } = {}

function StateMirrorController.of(userId: number): Mirror?
	return mirrors[userId]
end

function StateMirrorController.own(): Mirror?
	return mirrors[Players.LocalPlayer.UserId]
end

function StateMirrorController.predicted(): CombatState
	return predicted
end

function StateMirrorController.authoritative(): CombatState?
	local mirror = StateMirrorController.own()
	return if mirror then mirror.sync.state else nil
end

function StateMirrorController.divergence(): Divergence
	return divergence
end

function StateMirrorController.onSync(listener: (mirror: Mirror) -> ())
	table.insert(listeners, listener)
end

--[[
	Tente une transition en local. Retourne le même `Result` que le serveur
	produira, ce qui permet au contrôleur de combat de ne pas envoyer une demande
	que l'autorité refusera de toute façon — un paquet économisé, et un refus
	affiché immédiatement plutôt qu'un aller-retour plus tard.
]]
function StateMirrorController.tryPredict(target: StateName): Result.Result<CombatState>
	local mirror = StateMirrorController.own()
	if mirror == nil then
		return Result.err("NoState", "aucun état reçu du serveur")
	end

	local now = Clock.now()
	local context: CombatTypes.TransitionContext = {
		now = now,
		stamina = mirror.sync.stamina,
		dashReadyAt = mirror.sync.dashReadyAt,
		parryReadyAt = mirror.sync.parryReadyAt,
		balance = TuningController.balance(),
	}

	local allowed = StateMachine.canRequest(predicted, target, context)
	if not allowed.ok then
		return Result.err(allowed.code, allowed.detail)
	end

	predicted = StateMachine.enter(predicted, target, context)
	return Result.ok(predicted)
end

function StateMirrorController.Init()
	Net.Client.on(Definitions.CombatStateSync, function(payload)
		local mirror: Mirror = { sync = payload, receivedAt = Clock.now() }
		mirrors[payload.userId] = mirror

		if payload.userId == Players.LocalPlayer.UserId then
			-- L'autorité écrase la prédiction, toujours. On ne compte l'écart que
			-- sur le NOM de l'état : les échéances diffèrent forcément de quelques
			-- millisecondes, et les compter comme divergences noierait le signal.
			if predicted.name ~= payload.state.name then
				divergence.count += 1
				divergence.last = `{predicted.name} -> {payload.state.name}`
				divergence.lastAt = mirror.receivedAt
			end
			predicted = payload.state
		end

		for _, listener in listeners do
			task.spawn(listener, mirror)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		mirrors[player.UserId] = nil
	end)
end

function StateMirrorController.Start()
	-- La prédiction avance seule entre deux réplications : sans ça, un coup
	-- prédit resterait affiché comme en cours jusqu'au prochain paquet.
	RunService.Heartbeat:Connect(function()
		local expired = StateMachine.expire(predicted, Clock.now(), TuningController.balance())
		if expired then
			predicted = expired
		end
	end)
end

return StateMirrorController
