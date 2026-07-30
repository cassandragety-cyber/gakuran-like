--!strict
--[[
	Orchestration du combat. Reçoit les demandes, appelle les modules purs,
	applique le résultat, réplique le verdict.

	Ne contient **aucune valeur numérique de gameplay** : tout vient de la table
	d'équilibrage vivante. Ne contient non plus aucune règle — les règles sont
	dans `Shared/Combat` (partagées avec le client) et dans `Systems` (autorité).
	Ce fichier ne fait que l'enchaînement, dans le bon ordre, avec les bons refus.

	Le point le moins évident : la phase du coup est évaluée à l'instant
	REVENDIQUÉ par le client, pas à la réception. À 150 ms de latence, l'état
	courant de l'attaquant est déjà sorti de la phase active quand son rapport
	arrive ; valider contre le présent rejetterait des coups honnêtes. D'où
	`Combatant.lastSwing`, qui survit au retour à `Idle`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatResolver = require(script.Parent.Parent.Systems.CombatResolver)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Frames = require(ReplicatedStorage.Shared.Combat.Frames)
local HitValidator = require(script.Parent.Parent.Systems.HitValidator)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Profiler = require(ReplicatedStorage.Shared.Profiler)
local Rewind = require(script.Parent.Parent.Systems.Rewind)
local StateService = require(script.Parent.StateService)
local TuningService = require(script.Parent.TuningService)

local SCOPE = "CombatService"

local CombatService = {}

CombatService.Dependencies = { "StateService", "TuningService" }

local function refuse(player: Player, seq: number, code: string)
	Net.Server.fire(Definitions.CombatRefusal, player, { seq = seq, code = code })
end

--[[
	Phase du coup à un instant donné, calculée depuis la trace du coup et non
	depuis l'état courant. Retourne nil si l'instant précède le début du coup.
]]
local function phaseAt(
	swing: StateService.Swing,
	at: number,
	balance: BalanceConfig.Balance
): CombatTypes.Phase?
	local step = balance.Melee[swing.index]
	if step == nil then
		return nil
	end

	local elapsed = at - swing.startedAt
	if elapsed < 0 then
		return nil
	elseif elapsed < step.windup then
		return "Windup"
	elseif elapsed < step.windup + step.active then
		return "Active"
	end
	return "Recovery"
end

--[[
	Ligne de vue. Injectée dans HitValidator plutôt qu'appelée depuis lui : le
	raycast est la seule opération Roblox de la chaîne de validation, et l'isoler
	garde le validateur testable hors moteur.
]]
local function lineOfSightBetween(attacker: Model, target: Model): (Vector3, Vector3) -> boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker, target }
	params.IgnoreWater = true

	return function(from: Vector3, to: Vector3): boolean
		local direction = to - from
		if direction.Magnitude < 1e-3 then
			return true
		end
		return workspace:Raycast(from, direction, params) == nil
	end
end

local function resolveHit(
	attacker: StateService.Combatant,
	target: StateService.Combatant,
	swing: StateService.Swing,
	clientTime: number,
	now: number
): (string?, CombatResolver.Outcome?)
	local balance = TuningService.balance()
	local step = balance.Melee[swing.index]
	if step == nil then
		return "UnknownSwing", nil
	end

	local attackerPose =
		Rewind.sampleAt(attacker.history, clientTime, now, balance.Network.MaxRewind)
	if not attackerPose.ok then
		return attackerPose.code, nil
	end

	local targetPose = Rewind.sampleAt(target.history, clientTime, now, balance.Network.MaxRewind)
	if not targetPose.ok then
		return targetPose.code, nil
	end

	local valid = HitValidator.check({
		attacker = attackerPose.value,
		target = targetPose.value,
		hitbox = Frames.meleeHitbox(balance),
		toleranceStuds = balance.Hitbox.ServerToleranceStuds,
		facingDot = balance.Hitbox.FacingDot,
		hasLineOfSight = lineOfSightBetween(attacker.model, target.model),
	})
	if not valid.ok then
		return valid.code, nil
	end

	return nil,
		CombatResolver.resolve(step, {
			state = target.state,
			guard = target.guard,
			health = target.health,
		}, now, balance)
end

local function applyOutcome(
	attacker: StateService.Combatant,
	target: StateService.Combatant,
	outcome: CombatResolver.Outcome,
	seq: number,
	clientTime: number
)
	local balance = TuningService.balance()

	if outcome.verdict ~= "Ignored" then
		StateService.applyDamage(target, outcome.damage)
		StateService.tagCombat(attacker)
		StateService.tagCombat(target)

		-- La fenêtre de combo court depuis l'impact revendiqué, pas depuis la
		-- réception : sinon un joueur à forte latence disposerait d'une fenêtre
		-- plus longue que les autres.
		StateService.markImpact(attacker, clientTime + balance.Combat.ComboWindow)

		if outcome.knockdown then
			StateService.impose(target, "Knocked", balance.Knockdown.RagdollDuration)
		end
	end

	StateService.recordVerdict(target, outcome.verdict, outcome.damage)

	local payload = {
		seq = seq,
		verdict = outcome.verdict,
		damage = outcome.damage,
		target = target.model,
		targetHealth = target.health,
		hitstop = outcome.hitstop,
	}

	local attackingPlayer = attacker.player
	if attackingPlayer then
		Net.Server.fire(Definitions.CombatHitResult, attackingPlayer, payload)
	end

	-- La cible reçoit le même verdict : c'est ce qui lui permettra de jouer sa
	-- réaction, et en tranche 1.4 de confirmer ou corriger sa prédiction de parade.
	local targetPlayer = target.player
	if targetPlayer then
		Net.Server.fire(Definitions.CombatHitResult, targetPlayer, payload)
	end
end

local function onAttack(player: Player, payload: { seq: number, clientTime: number })
	local combatant = StateService.ofPlayer(player)
	if combatant == nil then
		refuse(player, payload.seq, "NoCombatant")
		return
	end

	local entered = StateService.requestTransition(combatant, "Attacking")
	if not entered.ok then
		refuse(player, payload.seq, entered.code)
		return
	end
	StateService.tagCombat(combatant)
end

local function onHitReport(
	player: Player,
	payload: { seq: number, clientTime: number, targets: { Instance } }
)
	local started = os.clock()
	local attacker = StateService.ofPlayer(player)
	if attacker == nil then
		refuse(player, payload.seq, "NoCombatant")
		return
	end

	local swing = attacker.lastSwing
	if swing == nil then
		refuse(player, payload.seq, "NoSwing")
		return
	end

	local balance = TuningService.balance()
	local now = Clock.now()

	local fresh = HitValidator.checkTimestamp(
		payload.clientTime,
		now,
		balance.Network.ClockTolerance,
		balance.Network.MaxRewind
	)
	if not fresh.ok then
		refuse(player, payload.seq, fresh.code)
		return
	end

	-- La hitbox n'est ouverte que pendant la phase active. Un contact revendiqué
	-- hors de cette fenêtre n'est pas une question de latence : c'est un client
	-- qui rapporte un coup qu'il n'a pas porté.
	if phaseAt(swing, payload.clientTime, balance) ~= "Active" then
		refuse(player, payload.seq, "WrongPhase")
		return
	end

	for _, instance in payload.targets do
		local model = instance :: Model
		if model == attacker.model then
			continue
		end

		local target = StateService.get(model)
		if target == nil then
			refuse(player, payload.seq, "UnknownTarget")
			continue
		end

		-- Doublon entre deux rapports du même coup : on ignore sans le compter
		-- comme une infraction. La perte de paquets fait légitimement renvoyer.
		if attacker.swingHits[model] then
			continue
		end

		local code, outcome = resolveHit(attacker, target, swing, payload.clientTime, now)
		if outcome == nil then
			refuse(player, payload.seq, code or "Rejected")
			continue
		end

		attacker.swingHits[model] = true
		applyOutcome(attacker, target, outcome, payload.seq, payload.clientTime)
	end

	Profiler.record("hit_validate", os.clock() - started)
end

function CombatService.Init()
	Net.Server.on(Definitions.CombatAttack, onAttack)
	Net.Server.on(Definitions.CombatHitReport, onHitReport)
	Log.debug(SCOPE, "handlers de combat enregistrés")
end

return CombatService
