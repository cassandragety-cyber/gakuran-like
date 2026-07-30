--!strict
--[[
	Lecture du frame data et progression de la chaîne d'attaque.

	Séparé de StateMachine parce que ce sont deux questions différentes : la
	machine décide de la LÉGALITÉ d'une transition, ce module décide d'OÙ ON EN EST
	dans un coup et dans une chaîne. Les deux grossiraient ensemble sinon, et
	c'est ici que la tranche 1.2 ajoutera la résolution index -> `MeleeStep`.

	Module pur, comme tout `Shared/Combat/` : la table d'équilibrage arrive en
	argument (ADR-011).
]]

local BalanceConfig = require(script.Parent.Parent.Parent.Config.Balance)
local Result = require(script.Parent.Parent.Result)
local SharedTypes = require(script.Parent.Parent.Types)
local Types = require(script.Parent.Types)

type CombatState = Types.CombatState
type Phase = Types.Phase
type TransitionContext = Types.TransitionContext
type Balance = BalanceConfig.Balance

local Frames = {}

--[[
	Hitbox du chain M1, construite depuis l'équilibrage.

	Elle est globale et non par coup : un joueur doit pouvoir apprendre UNE
	portée. Des volumes qui changent à chaque coup de la chaîne rendraient
	l'apprentissage impossible à l'œil. Les styles pourront fournir la leur en
	Phase 2, mais toujours une par style, pas une par coup.
]]
function Frames.meleeHitbox(balance: Balance): SharedTypes.HitboxSpec
	return {
		shape = "Box",
		size = balance.Hitbox.MeleeSize,
		offset = balance.Hitbox.MeleeOffset,
		maxTargets = balance.Hitbox.MaxTargetsPerSwing,
	}
end

--[[
	Frame data du coup à cet index, ou nil hors chaîne.
]]
function Frames.stepFor(index: number, balance: Balance): BalanceConfig.MeleeStep?
	return balance.Melee[index]
end

--[[
	Phase courante d'une attaque, ou nil si le joueur n'attaque pas. L'impact
	tombe à la fin de l'armé : c'est le contrat que docs/ANIMATIONS.md impose à
	l'animateur et que ConfigValidator vérifie au boot.
]]
function Frames.phaseOf(state: CombatState, now: number, balance: Balance): Phase?
	if state.name ~= "Attacking" then
		return nil
	end

	local step = balance.Melee[state.chainIndex]
	if not step then
		return nil
	end

	local elapsed = now - state.enteredAt
	if elapsed < step.windup then
		return "Windup"
	elseif elapsed < step.windup + step.active then
		return "Active"
	end
	return "Recovery"
end

--[[
	Index du prochain coup de chaîne. Retourne 1 quand la chaîne est repartie de
	zéro, sinon l'index suivant. `chainDeadline` nil signifie « coup en cours,
	pas encore résolu » : on autorise alors l'enchaînement par anticipation.
]]
function Frames.nextChainIndex(state: CombatState, now: number, balance: Balance): number
	local deadline = state.chainDeadline
	if state.chainIndex <= 0 or (deadline ~= nil and now > deadline) then
		return 1
	end
	return math.min(state.chainIndex + 1, #balance.Melee)
end

function Frames.canChain(state: CombatState, context: TransitionContext): Result.Result<true>
	local balance = context.balance
	if state.chainIndex >= #balance.Melee then
		return Result.err("ChainComplete", "le dernier coup de la chaîne est déjà parti")
	end

	-- On ne s'annule pas son propre armé : sinon un joueur qui martèle la touche
	-- ne jouerait jamais que des débuts d'animation, sans jamais rien risquer.
	local phase = Frames.phaseOf(state, context.now, balance)
	if phase == "Windup" then
		return Result.err("StillInWindup", "l'armé du coup courant n'est pas terminé")
	end

	local deadline = state.chainDeadline
	if deadline ~= nil and context.now > deadline then
		return Result.err("ComboWindowClosed", "la fenêtre de combo est fermée")
	end
	return Result.ok(true)
end

return Frames
