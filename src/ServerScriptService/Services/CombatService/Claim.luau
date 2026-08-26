--!strict
--[[
	« Ce contact a-t-il réellement eu lieu ? »

	Séparé de l'orchestration parce que ce sont deux responsabilités : `init` sait
	dans quel ORDRE poser les questions et quoi faire des réponses, ce module sait
	RÉPONDRE. Le découpage suit la même ligne que `StateService` / `Transitions` :
	le service enchaîne, le module tranche.

	Trois questions, du moins cher au plus cher, dans cet ordre :
	  1. l'instant revendiqué tombe-t-il dans la fenêtre active du coup ?
	  2. les deux combattants, rembobinés à cet instant, étaient-ils en contact ?
	  3. que produit ce contact, vu l'état du défenseur ?

	La table d'équilibrage arrive en argument (ADR-011) : ce module ne lit jamais
	`Config` au runtime, ce qui le rend réglable à chaud et testable avec des
	valeurs fabriquées.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local CombatResolver = require(script.Parent.Parent.Parent.Systems.CombatResolver)
local Frames = require(ReplicatedStorage.Shared.Combat.Frames)
local HitValidator = require(script.Parent.Parent.Parent.Systems.HitValidator)
local Result = require(ReplicatedStorage.Shared.Result)
local Rewind = require(script.Parent.Parent.Parent.Systems.Rewind)
local StateService = require(script.Parent.Parent.StateService)

type Balance = BalanceConfig.Balance
type Combatant = StateService.Combatant
type Swing = StateService.Swing

local Claim = {}

--[[
	Le contact revendiqué tombe-t-il dans la fenêtre active du coup ?

	Distincte de `Frames.phaseOf`, qui lit l'état COURANT : ici on lit la TRACE du
	coup à un instant révolu. C'est la seule fonction du projet qui accepte un
	instant passé, et la seule qui tolère un dépassement.

	Les deux bornes ne sont pas symétriques, et ne le seront jamais :
	  - début (`windup`) : strict. Un contact revendiqué avant la fin de l'armé
	    est un coup plus rapide que son animation ; le défenseur ne pourrait plus
	    caler sa parade sur ce qu'il voit, et c'est la parade qui prime ;
	  - fin : élargie de `ActivePhaseGrace`, parce que la hitbox client s'ouvre
	    sur Heartbeat et arrive donc au plus une frame en retard.

	Les deux refus portent des codes distincts, et c'est ce qui permet de lire
	sans instrumenter d'où vient un coup perdu : `ClaimTooEarly` systématique
	dénonce une chronologie mal ancrée, `ClaimTooLate` sporadique un framerate bas.
]]
function Claim.checkActiveWindow(swing: Swing, at: number, balance: Balance): Result.Verdict
	local step = balance.Melee[swing.index]
	if step == nil then
		return Result.err("UnknownSwing", `aucun frame data pour l'index {swing.index}`)
	end

	local elapsed = at - swing.startedAt
	if elapsed < step.windup then
		return Result.err(
			"ClaimTooEarly",
			`contact revendiqué à {string.format("%.3f", elapsed)} s, avant la fin de l'armé ({step.windup} s)`
		)
	end
	if elapsed > step.windup + step.active + balance.Network.ActivePhaseGrace then
		return Result.err(
			"ClaimTooLate",
			`contact revendiqué à {string.format("%.3f", elapsed)} s, après la fenêtre active`
		)
	end
	return Result.ok(true)
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

--[[
	Rembobine les deux combattants à l'instant revendiqué, vérifie que le contact
	était géométriquement possible, puis demande le verdict.

	Le code de refus remonte tel quel jusqu'au client : un joueur qui frappe à
	travers un mur doit lire `NoLineOfSight`, sinon il conclut que le jeu perd des
	coups au hasard.
]]
function Claim.resolve(
	attacker: Combatant,
	target: Combatant,
	swing: Swing,
	clientTime: number,
	now: number,
	balance: Balance
): Result.Result<CombatResolver.Outcome>
	local step = balance.Melee[swing.index]
	if step == nil then
		return Result.err("UnknownSwing", `aucun frame data pour l'index {swing.index}`)
	end

	local maxRewind = balance.Network.MaxRewind
	local attackerPose = Rewind.sampleAt(attacker.history, clientTime, now, maxRewind)
	if not attackerPose.ok then
		return Result.err(attackerPose.code, attackerPose.detail)
	end

	local targetPose = Rewind.sampleAt(target.history, clientTime, now, maxRewind)
	if not targetPose.ok then
		return Result.err(targetPose.code, targetPose.detail)
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
		return Result.err(valid.code, valid.detail)
	end

	return Result.ok(CombatResolver.resolve(step, {
		state = target.state,
		guard = target.guard,
		health = target.health,
	}, now, balance))
end

return Claim
