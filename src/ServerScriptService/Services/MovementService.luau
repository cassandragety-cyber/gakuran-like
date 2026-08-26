--!strict
--[[
	Vitesse de déplacement autoritative.

	Le client envoie une intention de sprint ; le serveur seul décide de la
	`WalkSpeed`. Ce n'est pas de la paranoïa : la garde ralentie et le coût
	d'endurance du sprint sont des règles du jeu, et une règle appliquée par le
	client n'est qu'une suggestion.

	Ce service est séparé de StateService pour garder une seule direction de
	dépendance : StateService détient l'état (dont l'intention de sprint), et
	MovementService le lit pour en déduire une vitesse. L'inverse créerait un cycle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(script.Parent.CharacterService)
local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local StateService = require(script.Parent.StateService)
local TuningService = require(script.Parent.TuningService)

local SCOPE = "MovementService"

local MovementService = {}

MovementService.Dependencies = { "CharacterService", "StateService", "TuningService" }

--[[
	Vitesse due à l'état courant. `Knocked`, `Stunned`, `GettingUp` et `Downed`
	immobilisent : un joueur étourdi qui continue de marcher rendrait le stun
	illisible pour l'adversaire, qui ne saurait pas s'il a le droit de frapper.
]]
local function speedFor(player: Player): number
	local balance = TuningService.balance()
	-- `get` prend un Model depuis ADR-014 ; c'est `ofPlayer` qui traduit.
	local record = StateService.ofPlayer(player)
	if record == nil then
		return balance.Character.WalkSpeed
	end

	local name = record.state.name
	if name == "Stunned" or name == "Knocked" or name == "GettingUp" or name == "Downed" then
		return 0
	elseif name == "Blocking" then
		return balance.Character.WalkSpeed * balance.Block.WalkSpeedMultiplier
	elseif record.sprinting then
		return balance.Character.SprintSpeed
	end
	return balance.Character.WalkSpeed
end

--[[
	La vitesse n'est réécrite que lorsqu'elle change réellement. Assigner
	`WalkSpeed` à chaque frame déclencherait une réplication de propriété par
	personnage et par frame, pour rien.
]]
local function apply()
	for player, character in CharacterService.all() do
		local target = speedFor(player)
		if math.abs(character.humanoid.WalkSpeed - target) > 0.01 then
			character.humanoid.WalkSpeed = target
		end
	end
end

function MovementService.Init()
	Net.Server.on(Definitions.MoveSprintState, function(player, payload)
		-- `clientTime` n'est pas utilisé pour décider : il ne sert qu'à repérer un
		-- client dont l'horloge dérive. L'autorisation dépend de l'endurance,
		-- que le serveur seul connaît.
		local drift = Clock.now() - payload.clientTime
		local tolerance = TuningService.balance().Network.ClockTolerance
		if drift < -tolerance then
			Log.warn(
				SCOPE,
				`horloge en avance pour {player.Name} : {string.format("%.3f", drift)} s`
			)
		end

		local combatant = StateService.ofPlayer(player)
		if combatant == nil then
			return
		end
		StateService.setSprinting(combatant, payload.active)
	end)
end

function MovementService.Start()
	RunService.Heartbeat:Connect(apply)
end

return MovementService
