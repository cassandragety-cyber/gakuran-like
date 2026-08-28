--!strict
--[[
	Orchestration du combat. Reçoit les demandes, appelle les modules purs,
	applique le résultat, réplique le verdict.

	Ne contient **aucune valeur numérique de gameplay** : tout vient de la table
	d'équilibrage vivante. Ne contient non plus aucune règle — les règles sont
	dans `Shared/Combat` (partagées avec le client), dans `Systems` (autorité) et
	dans `Claim` (« ce contact a-t-il eu lieu ? »). Ce fichier ne fait que
	l'enchaînement, dans le bon ordre, avec les bons refus.

	Le point le moins évident : la phase du coup est évaluée à l'instant
	REVENDIQUÉ par le client, pas à la réception. À 150 ms de latence, l'état
	courant de l'attaquant est déjà sorti de la phase active quand son rapport
	arrive ; valider contre le présent rejetterait des coups honnêtes. D'où
	`Combatant.lastSwing`, qui survit au retour à `Idle`.

	Le corollaire, oublié en tranche 1.2 et payé par un refus systématique : cette
	trace doit aussi être DATÉE sur l'horloge du client. Instant revendiqué et
	instant de départ doivent venir de la même horloge, sinon la fenêtre active se
	décale de la latence montante et aucun coup ne tombe dedans (ADR-017).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Claim = require(script.Claim)
local Clock = require(ReplicatedStorage.Shared.Clock)
local CombatResolver = require(script.Parent.Parent.Systems.CombatResolver)
local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local HitValidator = require(script.Parent.Parent.Systems.HitValidator)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Profiler = require(ReplicatedStorage.Shared.Profiler)
local StateService = require(script.Parent.StateService)
local TuningService = require(script.Parent.TuningService)

local SCOPE = "CombatService"

local CombatService = {}

CombatService.Dependencies = { "StateService", "TuningService" }

local function refuse(player: Player, seq: number, code: string)
	Net.Server.fire(Definitions.CombatRefusal, player, { seq = seq, code = code })
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

		if outcome.verdict == "Blocked" then
			StateService.consumeGuard(target, outcome.guardRemaining)

			--[[
				La garde a cédé. L'étourdissement est imposé, donc arbitré par
				priorité : `Stunned` (3) l'emporte sur `Blocking` (1), et la table de
				transitions n'offre aucune sortie depuis `Stunned`. Le défenseur ne
				peut donc pas remonter sa garde avant la fin — c'est ce qui fait du
				guard break une vraie ouverture et pas une simple gêne.

				La jauge repart pleine : rouvrir sur une jauge vide re-casserait au
				coup suivant, transformant une punition ponctuelle en verrou.
			]]
			if outcome.guardBroken then
				StateService.breakGuard(target, balance.Block.GuardBreakStun)
			end
		end

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
		guardBroken = outcome.guardBroken,
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

	-- L'instant revendiqué passe par la même borne que celle d'un rapport de
	-- contact, et pour la même raison : au-delà, on ne rembobine pas. Un coup daté
	-- hors fenêtre est refusé avant d'exister, plutôt que d'ancrer une chronologie
	-- que la validation du contact ne saura ensuite plus atteindre.
	local balance = TuningService.balance()
	local fresh = HitValidator.checkTimestamp(
		payload.clientTime,
		Clock.now(),
		balance.Network.ClockTolerance,
		balance.Network.MaxRewind
	)
	if not fresh.ok then
		refuse(player, payload.seq, fresh.code)
		return
	end

	-- Le coup est daté au départ revendiqué, pas à la réception : c'est contre
	-- cette chronologie que le rapport de contact sera validé, et ce rapport est
	-- daté sur l'horloge du client (ADR-017). La légalité de la transition, elle,
	-- reste jugée à l'heure serveur — un instant fourni par le client ne doit
	-- jamais pouvoir avancer un cooldown.
	local entered = StateService.requestTransition(combatant, "Attacking", payload.clientTime)
	if not entered.ok then
		refuse(player, payload.seq, entered.code)
		return
	end
	StateService.tagCombat(combatant)
end

--[[
	Ouverture ou fermeture de la garde.

	Il n'y a **aucun** message de parade : le client dit seulement quand il a levé
	sa garde, et le serveur en dérive la fenêtre (ADR-002). Le refus est renvoyé
	avec son code — `ParryCooldown` notamment, sans quoi un joueur qui rouvre trop
	tôt verrait sa garde ne pas monter sans savoir pourquoi.

	La fermeture n'est jamais refusée pour cause de ressource : `Blocking -> Idle`
	ne coûte rien. Elle peut en revanche être refusée par la table de transitions
	si le joueur n'est plus en garde (étourdi par un guard break, par exemple), et
	c'est correct — l'état a déjà été changé par l'autorité.
]]
local function onBlockState(player: Player, payload: { open: boolean, clientTime: number })
	local combatant = StateService.ofPlayer(player)
	if combatant == nil then
		-- Refus explicite plutôt que retour muet. La version précédente sortait en
		-- silence ici : le client voyait alors sa prédiction contredite sans le
		-- moindre code, ce qui est exactement la panne qu'on s'interdit.
		refuse(player, Definitions.UNSEQUENCED, "NoCombatant")
		return
	end

	local balance = TuningService.balance()
	local fresh = HitValidator.checkTimestamp(
		payload.clientTime,
		Clock.now(),
		balance.Network.ClockTolerance,
		balance.Network.MaxRewind
	)
	if not fresh.ok then
		-- Un horodatage hors fenêtre sur une OUVERTURE est refusé : il ancrerait
		-- une fenêtre de parade dans un passé qu'on ne sait plus arbitrer. Sur une
		-- fermeture, il n'ancre rien — on laisse donc la garde retomber plutôt que
		-- de coincer le joueur en position haute à cause d'une dérive d'horloge.
		if payload.open then
			refuse(player, Definitions.UNSEQUENCED, fresh.code)
			return
		end
	end

	local previous = combatant.state.name
	local target: CombatTypes.StateName = if payload.open then "Blocking" else "Idle"
	local entered = StateService.requestTransition(combatant, target, payload.clientTime)
	if not entered.ok then
		-- Journalisé avec l'état de DÉPART : « refusé » seul ne dit pas pourquoi,
		-- et le pourquoi est presque toujours l'état dans lequel le serveur croyait
		-- le joueur — typiquement une attaque que le client a déjà vue finir.
		Log.debug(
			SCOPE,
			`garde refusée à {player.Name} : {entered.code} (état serveur : {previous})`
		)
		refuse(player, Definitions.UNSEQUENCED, entered.code)
		return
	end

	if payload.open then
		StateService.tagCombat(combatant)
	end
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
	-- hors de cette fenêtre n'est pas une question de latence : c'est un client qui
	-- rapporte un coup qu'il n'a pas porté.
	local window = Claim.checkActiveWindow(swing, payload.clientTime, balance)
	if not window.ok then
		refuse(player, payload.seq, window.code)
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

		local resolved = Claim.resolve(attacker, target, swing, payload.clientTime, now, balance)
		if not resolved.ok then
			refuse(player, payload.seq, resolved.code)
			continue
		end

		attacker.swingHits[model] = true
		applyOutcome(attacker, target, resolved.value, payload.seq, payload.clientTime)
	end

	Profiler.record("hit_validate", os.clock() - started)
end

function CombatService.Init()
	Net.Server.on(Definitions.CombatAttack, onAttack)
	Net.Server.on(Definitions.CombatBlockState, onBlockState)
	Net.Server.on(Definitions.CombatHitReport, onHitReport)
	Log.debug(SCOPE, "handlers de combat enregistrés")
end

return CombatService
