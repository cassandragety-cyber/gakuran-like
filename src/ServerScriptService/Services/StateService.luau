--!strict
--[[
	L'état de combat autoritatif. Personne d'autre n'écrit ces valeurs.

	Un unique `Heartbeat` fait tout avancer : expiration des échéances,
	endurance, échantillonnage des positions, réplication. Aucun `task.delay` par
	joueur ni par action — un minuteur ne s'annule pas proprement quand un joueur
	est interrompu ou quitte la partie, et 30 joueurs en combat produiraient des
	centaines de tâches en vol dont plus personne ne connaît la pertinence.

	La réplication combine deux régimes : immédiate sur changement discret, pour
	que le client réagisse dans la frame, et à cadence réduite pour les valeurs
	continues. Un changement d'état attendu jusqu'à 100 ms serait ressenti comme
	de l'input lag.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(script.Parent.CharacterService)
local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Net = require(ReplicatedStorage.Net)
local Result = require(ReplicatedStorage.Shared.Result)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)
local SessionService = require(script.Parent.SessionService)
local StaminaModel = require(ReplicatedStorage.Shared.Combat.StaminaModel)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local TuningService = require(script.Parent.TuningService)

-- Cadence de réplication des valeurs continues (endurance, PV, garde).
local SYNC_RATE = 10

-- L'historique couvre confortablement le rembobinage maximal de 0,25 s :
-- 32 échantillons à 20 Hz valent 1,6 s, ce qui laisse de la marge pour un pic
-- de latence sans jamais rendre le rembobinage plus permissif — c'est
-- `Balance.Network.MaxRewind` qui le borne, pas la taille du tampon.
local HISTORY_SIZE = 32

type CombatState = CombatTypes.CombatState
type StateName = CombatTypes.StateName

export type PlayerCombat = {
	player: Player,
	state: CombatState,
	health: number,
	stamina: StaminaModel.StaminaState,
	guard: number,
	dashReadyAt: number,
	parryReadyAt: number,
	sprinting: boolean,
	history: RingBuffer.RingBuffer<CombatTypes.Snapshot>,
	lastSampleAt: number,
	lastSyncAt: number,
	dirty: boolean,
}

local StateService = {}

StateService.Dependencies = { "SessionService", "CharacterService", "TuningService" }

local records: { [Player]: PlayerCombat } = {}

function StateService.get(player: Player): PlayerCombat?
	return records[player]
end

function StateService.contextFor(record: PlayerCombat, now: number): CombatTypes.TransitionContext
	return {
		now = now,
		stamina = record.stamina.current,
		dashReadyAt = record.dashReadyAt,
		parryReadyAt = record.parryReadyAt,
		balance = TuningService.balance(),
	}
end

local function replicate(record: PlayerCombat, now: number)
	record.lastSyncAt = now
	record.dirty = false
	-- Tranche 1.1 : le propriétaire seulement. Les joueurs proches en auront
	-- besoin dès qu'il y aura un retour visuel à jouer sur autrui (tranche 1.3).
	Net.Server.fire(Definitions.CombatStateSync, record.player, {
		userId = record.player.UserId,
		state = record.state,
		health = record.health,
		stamina = record.stamina.current,
		guard = record.guard,
		dashReadyAt = record.dashReadyAt,
		parryReadyAt = record.parryReadyAt,
	})
end

--[[
	Marque l'état comme devant être répliqué sans attendre la prochaine cadence.
	Réservé aux changements discrets : un état, un cooldown consommé, un KO.
]]
local function touch(record: PlayerCombat)
	record.dirty = true
end

--[[
	Effets de bord d'une entrée d'état. Ils vivent ici et pas dans StateMachine :
	la machine est pure et ne consomme pas de ressources, elle décide seulement de
	la légalité et de la forme de l'état.
]]
local function applyEntryCost(record: PlayerCombat, target: StateName, now: number)
	local balance = TuningService.balance()

	if target == "Dashing" then
		record.stamina.current = StaminaModel.spend(record.stamina, balance.Dash.StaminaCost)
		record.dashReadyAt = now + balance.Dash.Cooldown
	elseif target == "Blocking" then
		-- Le cooldown court à partir de l'OUVERTURE, pas du relâchement : sinon
		-- le maintien-relâche en boucle rouvrirait une fenêtre de parade à chaque
		-- pression.
		record.parryReadyAt = now + balance.Parry.Cooldown
	end
end

--[[
	Transition demandée par le joueur. Passe par la table d'autorisations et les
	gardes de StateMachine ; un refus est une information normale, retournée avec
	son code, pas une erreur.
]]
function StateService.requestTransition(
	player: Player,
	target: StateName
): Result.Result<CombatState>
	local record = records[player]
	if record == nil then
		return Result.err("NoCharacter", "aucun état de combat pour ce joueur")
	end

	local now = Clock.now()
	local context = StateService.contextFor(record, now)
	local allowed = StateMachine.canRequest(record.state, target, context)
	if not allowed.ok then
		return Result.err(allowed.code, allowed.detail)
	end

	record.state = StateMachine.enter(record.state, target, context)
	applyEntryCost(record, target, now)
	touch(record)
	return Result.ok(record.state)
end

--[[
	Transition imposée par le serveur, arbitrée par priorité (COMBAT.md §1.4). Le
	client ne peut jamais en déclencher une : c'est ce qui rend impossible de
	sortir d'un `Stunned` en demandant une transition.
]]
function StateService.impose(
	player: Player,
	target: StateName,
	duration: number?,
	invulnerableFor: number?
): boolean
	local record = records[player]
	if record == nil then
		return false
	end
	if not StateMachine.canImpose(record.state, target) then
		return false
	end

	record.state = StateMachine.impose(target, Clock.now(), duration, invulnerableFor)
	touch(record)
	return true
end

--[[
	Pose le tag de combat, qui ralentit la régénération d'endurance. Appelé à
	chaque coup donné ou reçu à partir de la tranche 1.2.
]]
function StateService.tagCombat(player: Player)
	local record = records[player]
	if record then
		record.stamina.lastCombatAt = Clock.now()
	end
end

function StateService.setSprinting(player: Player, active: boolean): boolean
	local record = records[player]
	if record == nil then
		return false
	end

	if active and not StaminaModel.canSprint(record.stamina, TuningService.balance()) then
		return false
	end

	record.sprinting = active
	return true
end

function StateService.isSprinting(player: Player): boolean
	local record = records[player]
	return record ~= nil and record.sprinting
end

local function sample(record: PlayerCombat, now: number)
	local character = CharacterService.get(record.player)
	if character == nil then
		return
	end

	local cframe = character.root.CFrame
	RingBuffer.push(record.history, {
		t = now,
		position = cframe.Position,
		look = cframe.LookVector,
	})
	record.lastSampleAt = now
end

local function step(deltaTime: number)
	local now = Clock.now()
	local balance = TuningService.balance()
	local sampleInterval = 1 / balance.Network.PositionSampleRate
	local syncInterval = 1 / SYNC_RATE

	for _, record in records do
		local expired = StateMachine.expire(record.state, now, balance)
		if expired then
			record.state = expired
			touch(record)
		end

		local drain = if record.sprinting then balance.Stamina.SprintDrainPerSecond else 0
		record.stamina.current = StaminaModel.step(record.stamina, now, deltaTime, drain, balance)

		if record.sprinting and not StaminaModel.canSprint(record.stamina, balance) then
			record.sprinting = false
			touch(record)
		end

		if now - record.lastSampleAt >= sampleInterval then
			sample(record, now)
		end

		if record.dirty or now - record.lastSyncAt >= syncInterval then
			replicate(record, now)
		end
	end
end

local function create(player: Player)
	local balance = TuningService.balance()
	local now = Clock.now()

	records[player] = {
		player = player,
		state = StateMachine.idle(now),
		health = balance.Character.MaxHealth,
		stamina = { current = balance.Stamina.Max, lastCombatAt = 0 },
		guard = balance.Block.GuardHealth,
		dashReadyAt = 0,
		parryReadyAt = 0,
		sprinting = false,
		history = RingBuffer.new(HISTORY_SIZE),
		lastSampleAt = 0,
		lastSyncAt = 0,
		dirty = true,
	}
end

function StateService.Init()
	CharacterService.onAdded(function(record)
		create(record.player)
	end)

	-- L'état de combat disparaît avec le personnage : un état conservé entre deux
	-- vies ferait réapparaître un joueur étourdi ou au sol.
	CharacterService.onRemoving(function(player)
		records[player] = nil
	end)

	SessionService.onEnded(function(player)
		records[player] = nil
	end)
end

function StateService.Start()
	RunService.Heartbeat:Connect(step)
end

return StateService
