--!strict
--[[
	Changements d'état d'un combattant, et les coûts qui les accompagnent.

	Séparé du registre parce que ce sont deux responsabilités : `StateService`
	sait QUI existe, ce module sait ce qu'il advient d'un combattant donné. Les
	deux écrivent le drapeau `dirty` — c'est le seul champ partagé, et il ne veut
	dire qu'une chose : « cet état doit être répliqué sans attendre la cadence ».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Result = require(ReplicatedStorage.Shared.Result)
local StaminaModel = require(ReplicatedStorage.Shared.Combat.StaminaModel)
local StateMachine = require(ReplicatedStorage.Shared.Combat.StateMachine)
local TuningService = require(script.Parent.Parent.TuningService)
local Types = require(script.Parent.Types)

type Combatant = Types.Combatant
type CombatState = CombatTypes.CombatState
type StateName = CombatTypes.StateName

local Transitions = {}

function Transitions.contextFor(combatant: Combatant, now: number): CombatTypes.TransitionContext
	return {
		now = now,
		stamina = combatant.stamina.current,
		dashReadyAt = combatant.dashReadyAt,
		parryReadyAt = combatant.parryReadyAt,
		balance = TuningService.balance(),
	}
end

--[[
	Effets de bord d'une entrée d'état. Ils vivent ici et pas dans StateMachine :
	la machine est pure et ne consomme pas de ressources, elle décide seulement de
	la légalité et de la forme de l'état.
]]
local function applyEntryCost(
	combatant: Combatant,
	target: StateName,
	now: number,
	startedAt: number
)
	local balance = TuningService.balance()

	if target == "Dashing" then
		combatant.stamina.current = StaminaModel.spend(combatant.stamina, balance.Dash.StaminaCost)
		combatant.dashReadyAt = now + balance.Dash.Cooldown
	elseif target == "Blocking" then
		-- Le cooldown court depuis l'OUVERTURE, pas le relâchement : sinon le
		-- maintien-relâche en boucle rouvrirait une fenêtre de parade à chaque
		-- pression.
		combatant.parryReadyAt = now + balance.Parry.Cooldown
	elseif target == "Attacking" then
		combatant.lastSwing = { index = combatant.state.chainIndex, startedAt = startedAt }
		-- Nouveau coup, nouvelle ardoise de cibles.
		combatant.swingHits = {}
	end
end

--[[
	Transition demandée par le joueur. Passe par la table d'autorisations et les
	gardes de StateMachine ; un refus est une information normale, retournée avec
	son code, pas une erreur.

	`startedAt` est l'instant où l'action a réellement commencé **chez le
	client**, sur l'horloge commune (`Clock`, donc `GetServerTimeNow`). Il ne sert
	qu'à dater la trace du coup, jamais à évaluer sa légalité — la distinction
	est le fond d'ADR-017 :

	  - la légalité (cooldowns, endurance, transitions permises) est jugée à
	    `now`, l'heure serveur. Un instant fourni par le client ne doit jamais
	    pouvoir avancer un cooldown ;
	  - la CHRONOLOGIE du coup est ancrée à `startedAt`, parce que c'est contre
	    elle que le rapport de contact sera validé, et que ce rapport est daté
	    sur l'horloge du client. Ancrer à la réception décalerait toute la
	    fenêtre active de la latence montante, et refuserait chaque coup.

	L'appelant est responsable d'avoir borné `startedAt` (cf.
	`HitValidator.checkTimestamp`) : sans borne, un client daterait son coup une
	heure plus tôt. Omettre l'argument revient à dater le coup à la réception,
	ce qui est le bon défaut pour une transition d'origine serveur.
]]
function Transitions.requestTransition(
	combatant: Combatant,
	target: StateName,
	startedAt: number?
): Result.Result<CombatState>
	local now = Clock.now()
	local context = Transitions.contextFor(combatant, now)
	local allowed = StateMachine.canRequest(combatant.state, target, context)
	if not allowed.ok then
		return Result.err(allowed.code, allowed.detail)
	end

	combatant.state = StateMachine.enter(combatant.state, target, context)
	applyEntryCost(combatant, target, now, startedAt or now)
	combatant.dirty = true
	return Result.ok(combatant.state)
end

--[[
	Transition imposée par le serveur, arbitrée par priorité (COMBAT.md §1.4). Le
	client ne peut jamais en déclencher une : c'est ce qui rend impossible de
	sortir d'un `Stunned` en demandant une transition.
]]
function Transitions.impose(
	combatant: Combatant,
	target: StateName,
	duration: number?,
	invulnerableFor: number?
): boolean
	if not StateMachine.canImpose(combatant.state, target) then
		return false
	end

	combatant.state = StateMachine.impose(target, Clock.now(), duration, invulnerableFor)
	combatant.dirty = true
	return true
end

--[[
	Enregistre qu'un coup a touché, en fixant l'échéance de la chaîne.

	Passe par une fonction plutôt que par une écriture directe sur l'état : le
	champ `chainDeadline` porte deux règles à la fois (fenêtre de combo et reset
	sur coup manqué), et un seul endroit doit décider laquelle s'applique.
]]
function Transitions.markImpact(combatant: Combatant, deadline: number)
	combatant.state.chainDeadline = deadline
	combatant.dirty = true
end

return Transitions
