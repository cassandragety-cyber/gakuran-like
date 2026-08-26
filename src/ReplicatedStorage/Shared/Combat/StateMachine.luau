--!strict
--[[
	La machine à états du combat. Spécification : docs/COMBAT.md §1.

	Module pur : aucune API Roblox hors types de données, aucune lecture de
	configuration — la table d'équilibrage arrive dans le contexte (ADR-011).
	Le serveur l'utilise pour arbitrer, le client pour prédire. Les deux
	appliquent donc littéralement le même code, ce qui est la seule façon
	d'éviter qu'une prédiction dérive d'un cas limite (COMBAT.md §1.6).

	Deux familles d'appels, à ne pas confondre :
	  - `canRequest` / `enter`  : transitions DEMANDÉES par le joueur, soumises
	    à la table d'autorisations et aux gardes.
	  - `canImpose` / `impose`  : transitions IMPOSÉES par le serveur, arbitrées
	    par priorité. Le client ne s'en sert jamais de sa propre initiative.
]]

local BalanceConfig = require(script.Parent.Parent.Parent.Config.Balance)
local Frames = require(script.Parent.Frames)
local Result = require(script.Parent.Parent.Result)
local Types = require(script.Parent.Types)

type CombatState = Types.CombatState
type StateName = Types.StateName
type TransitionContext = Types.TransitionContext
type Balance = BalanceConfig.Balance

local StateMachine = {}

--[[
	Réexports : la phase et l'index de chaîne appartiennent à `Frames`, mais tout
	le code de combat interroge la machine à états. On évite ainsi que chaque
	appelant ait à connaître le découpage interne.
]]
StateMachine.phaseOf = Frames.phaseOf
StateMachine.nextChainIndex = Frames.nextChainIndex

--[[
	Priorités des transitions imposées. Une transition imposée l'emporte si sa
	priorité est STRICTEMENT supérieure à celle de l'état courant.

	`GettingUp` est au niveau de `Stunned` et non de `Knocked` : être renvoyé au
	sol pendant un relevage doit rester possible une fois l'invulnérabilité
	écoulée, sinon le relevage devient un abri gratuit.
]]
local PRIORITY: { [StateName]: number } = {
	Idle = 0,
	Attacking = 1,
	Blocking = 1,
	Dashing = 2,
	Stunned = 3,
	GettingUp = 3,
	Knocked = 4,
	Downed = 5,
}

--[[
	Transitions qu'un joueur peut DEMANDER. Ce qui est absent est interdit, et
	deux absences sont des décisions de design (COMBAT.md §1.3) :
	  - pas de `Attacking -> Blocking` : rater un coup doit coûter, la
	    récupération est la punition du coup dans le vide ;
	  - pas de `Blocking -> Attacking` : il faut relâcher la garde, sinon la
	    garde permanente ne coûte rien.
	Les retours vers `Idle` depuis `Attacking` et `Dashing` se font par
	expiration, jamais sur demande.
]]
local REQUESTABLE: { [StateName]: { [StateName]: boolean } } = {
	Idle = { Attacking = true, Blocking = true, Dashing = true },
	Attacking = { Attacking = true, Dashing = true },
	Blocking = { Idle = true, Dashing = true },
	Dashing = {},
	Stunned = {},
	Knocked = {},
	GettingUp = {},
	Downed = {},
}

function StateMachine.priorityOf(name: StateName): number
	return PRIORITY[name]
end

function StateMachine.idle(now: number): CombatState
	return { name = "Idle", enteredAt = now, chainIndex = 0 }
end

function StateMachine.isInvulnerable(state: CombatState, now: number): boolean
	if state.name ~= "Dashing" and state.name ~= "GettingUp" then
		return false
	end
	local window = state.windowUntil
	return window ~= nil and now <= window
end

function StateMachine.isParryWindowOpen(state: CombatState, now: number): boolean
	if state.name ~= "Blocking" then
		return false
	end
	local window = state.windowUntil
	return window ~= nil and now <= window
end

local function canDash(state: CombatState, context: TransitionContext): Result.Verdict
	local balance = context.balance
	if context.now < context.dashReadyAt then
		return Result.err("DashCooldown", "le dash n'est pas rechargé")
	end
	if context.stamina < balance.Dash.StaminaCost then
		return Result.err("NotEnoughStamina", "endurance insuffisante pour dasher")
	end

	if state.name == "Attacking" then
		local phase = Frames.phaseOf(state, context.now, balance)
		if phase ~= "Recovery" then
			return Result.err("NotCancelable", "seule la récupération peut être annulée")
		end
		local step = balance.Melee[state.chainIndex]
		if not step or not step.cancelable then
			return Result.err("NotCancelable", "ce coup ne peut pas être annulé")
		end
	end
	return Result.ok(true)
end

local function canBlock(context: TransitionContext): Result.Verdict
	local balance = context.balance
	if context.now < context.parryReadyAt then
		return Result.err("ParryCooldown", "la garde ne peut pas être réouverte si tôt")
	end
	if context.stamina < balance.Stamina.MinimumToAct then
		return Result.err("NotEnoughStamina", "endurance insuffisante pour garder")
	end
	return Result.ok(true)
end

--[[
	Une demande du joueur est-elle recevable ? Retourne un `Result` porteur d'un
	code : le refus est une information normale (cooldown, endurance) qu'on veut
	pouvoir afficher, pas une erreur.
]]
function StateMachine.canRequest(
	state: CombatState,
	target: StateName,
	context: TransitionContext
): Result.Verdict
	if not REQUESTABLE[state.name][target] then
		return Result.err(
			"TransitionForbidden",
			`{state.name} -> {target} n'est pas une demande valide`
		)
	end

	if target == "Attacking" then
		if state.name == "Attacking" then
			return Frames.canChain(state, context)
		end
		return Result.ok(true)
	elseif target == "Dashing" then
		return canDash(state, context)
	elseif target == "Blocking" then
		return canBlock(context)
	end

	-- Blocking -> Idle : relâcher la garde ne demande aucune ressource.
	return Result.ok(true)
end

--[[
	Construit l'état résultant d'une demande acceptée. Ne vérifie rien :
	`canRequest` doit avoir été appelé avant, et l'appelant est responsable de
	cet enchaînement.
]]
function StateMachine.enter(
	state: CombatState,
	target: StateName,
	context: TransitionContext
): CombatState
	local now = context.now
	local balance = context.balance

	if target == "Attacking" then
		local index = Frames.nextChainIndex(state, now, balance)
		local step = balance.Melee[index]
		return {
			name = "Attacking",
			enteredAt = now,
			expiresAt = now + step.windup + step.active + step.recovery,
			chainIndex = index,
			chainDeadline = nil,
		}
	elseif target == "Blocking" then
		return {
			name = "Blocking",
			enteredAt = now,
			-- La fenêtre de parade s'ouvre à l'instant de l'appui et se ferme
			-- seule ; le serveur en est le seul arbitre (ADR-002).
			windowUntil = now + balance.Parry.Window,
			chainIndex = state.chainIndex,
			chainDeadline = state.chainDeadline,
		}
	elseif target == "Dashing" then
		return {
			name = "Dashing",
			enteredAt = now,
			expiresAt = now + balance.Dash.Duration,
			windowUntil = now + balance.Dash.InvulnerabilityDuration,
			chainIndex = 0,
		}
	end

	return StateMachine.idle(now)
end

function StateMachine.canImpose(state: CombatState, target: StateName): boolean
	return PRIORITY[target] > PRIORITY[state.name]
end

function StateMachine.impose(
	target: StateName,
	now: number,
	duration: number?,
	invulnerableFor: number?
): CombatState
	return {
		name = target,
		enteredAt = now,
		expiresAt = if duration then now + duration else nil,
		windowUntil = if invulnerableFor then now + invulnerableFor else nil,
		chainIndex = 0,
	}
end

--[[
	Fait avancer un état dont l'échéance est atteinte. Retourne nil quand il n'y
	a rien à faire — l'appelant sait alors qu'aucune réplication n'est utile.

	`Knocked` enchaîne sur `GettingUp` plutôt que sur `Idle` : c'est
	l'invulnérabilité de relevage qui empêche le viol de knockdown en boucle.
]]
function StateMachine.expire(state: CombatState, now: number, balance: Balance): CombatState?
	local expiresAt = state.expiresAt
	if expiresAt == nil or now < expiresAt then
		return nil
	end

	if state.name == "Knocked" then
		return {
			name = "GettingUp",
			enteredAt = now,
			expiresAt = now + balance.Knockdown.GetUpDuration,
			windowUntil = now + balance.Knockdown.GetUpInvulnerability,
			chainIndex = 0,
		}
	end

	local next_: CombatState = StateMachine.idle(now)
	if state.name == "Attacking" then
		-- Le coup s'achève sans avoir été résolu : on ouvre la fenêtre de reset
		-- de chaîne, ce qui laisse au joueur le droit de continuer un instant.
		next_.chainIndex = state.chainIndex
		next_.chainDeadline = state.chainDeadline or (now + balance.Combat.WhiffResetDelay)
	end
	return next_
end

return StateMachine
