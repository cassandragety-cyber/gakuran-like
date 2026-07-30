--!strict
--[[
	Le pas de temps du combat : une passe par frame sur tous les combattants.

	Séparé de `StateService` pour deux raisons. La première est la taille : le
	registre et son API d'un côté, la boucle de l'autre. La seconde est plus
	intéressante — cette boucle ne prend aucune décision de gameplay, elle fait
	seulement avancer le temps. Elle ne connaît donc ni le réseau, ni les joueurs,
	et reçoit tout ce dont elle a besoin en argument.

	Ordre des opérations dans la passe, et il compte :
	  1. expiration des échéances — un état échu ne doit pas régénérer une frame
	     de plus sous ses anciennes règles ;
	  2. endurance ;
	  3. échantillonnage de position — après le déplacement de la frame, sinon
	     l'historique aurait systématiquement une frame de retard sur la réalité
	     que le client a vue ;
	  4. réplication.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local Clock = require(ReplicatedStorage.Shared.Clock)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)
local StaminaModel = require(ReplicatedStorage.Shared.Combat.StaminaModel)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)

-- Cadence de réplication des valeurs continues (PV, endurance, garde). Les
-- changements discrets sont envoyés sans attendre, via le drapeau `dirty`.
local SYNC_RATE = 10

type Balance = BalanceConfig.Balance

local Stepper = {}

--[[
	Le type du combattant est décrit chez son propriétaire. On ne le require pas
	ici : `StateService` require déjà ce module, et l'inverse formerait un cycle.
	La structure est donc décrite par ce qu'on en utilise.
]]
type Steppable = {
	root: BasePart,
	state: any,
	stamina: StaminaModel.StaminaState,
	sprinting: boolean,
	history: RingBuffer.RingBuffer<any>,
	lastSampleAt: number,
	lastSyncAt: number,
	dirty: boolean,
}

local function sample(combatant: Steppable, now: number)
	local cframe = combatant.root.CFrame
	RingBuffer.push(combatant.history, {
		t = now,
		position = cframe.Position,
		look = cframe.LookVector,
	})
	combatant.lastSampleAt = now
end

function Stepper.step<T>(
	deltaTime: number,
	records: { [Model]: T },
	balance: Balance,
	replicate: (combatant: T, now: number) -> ()
)
	local now = Clock.now()
	local sampleInterval = 1 / balance.Network.PositionSampleRate
	local syncInterval = 1 / SYNC_RATE

	for _, entry in records do
		local combatant = (entry :: any) :: Steppable

		local expired = StateMachine.expire(combatant.state, now, balance)
		if expired then
			combatant.state = expired
			combatant.dirty = true
		end

		local drain = if combatant.sprinting then balance.Stamina.SprintDrainPerSecond else 0
		combatant.stamina.current =
			StaminaModel.step(combatant.stamina, now, deltaTime, drain, balance)

		if combatant.sprinting and not StaminaModel.canSprint(combatant.stamina, balance) then
			combatant.sprinting = false
			combatant.dirty = true
		end

		if now - combatant.lastSampleAt >= sampleInterval then
			sample(combatant, now)
		end

		if combatant.dirty or now - combatant.lastSyncAt >= syncInterval then
			replicate(entry, now)
		end
	end
end

return Stepper
