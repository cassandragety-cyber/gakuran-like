--!strict
--[[
	Le combat vu du client : prédire, détecter, rapporter, réconcilier.

	Séquence d'un coup :
	  1. le joueur appuie ; on prédit localement la transition avec les MÊMES
	     règles que le serveur (`StateMachine`). Un refus prédit n'est pas envoyé —
	     inutile de faire valider par le réseau un coup qu'on sait illégal ;
	  2. la demande part, horodatée sur l'horloge commune ;
	  3. à l'instant d'impact prédit (fin de l'armé), la hitbox s'ouvre une fois et
	     les cibles trouvées partent dans un rapport ;
	  4. le serveur renvoie un verdict par cible, ou un refus avec son code.

	Pourquoi la hitbox n'est ouverte qu'UNE fois, à l'instant d'impact, et non à
	chaque frame de la phase active : le serveur valide le contact à l'instant
	revendiqué, un seul instant. Balayer la phase entière produirait des contacts
	que le serveur refuserait pour cause de phase, et le joueur verrait des coups
	disparaître sans raison lisible.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Frames = require(ReplicatedStorage.Shared.Combat.Frames)
local HitboxDetector = require(script.Parent.HitboxDetector)
local HitboxVisualizer = require(script.Parent.HitboxVisualizer)
local InputController = require(script.Parent.InputController)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local StateMirrorController = require(script.Parent.StateMirrorController)
local TuningController = require(script.Parent.TuningController)
local Types = require(ReplicatedStorage.Shared.Types)

local SCOPE = "CombatController"

local CombatController = {}

CombatController.Dependencies = {
	"InputController",
	"StateMirrorController",
	"TuningController",
	"HitboxVisualizer",
}

type PendingSwing = {
	seq: number,
	-- Instant d'impact prédit, sur l'horloge commune.
	impactAt: number,
	reported: boolean,
}

-- Démarre à 1 : le 0 est réservé aux refus NON SÉQUENCÉS, ceux des demandes qui
-- n'ont pas de numéro — la garde en particulier, dont le payload ne porte qu'un
-- booléen et un horodatage. Sans cette réserve, le tout premier coup de la
-- partie et un refus de garde se ressembleraient.
local nextSequence = 1
local pending: PendingSwing? = nil
local lastVerdict: string? = nil
local lastRefusal: string? = nil
local lastEventAt = 0
local sentCount = 0

function CombatController.lastOutcome(): (string?, string?, number)
	return lastVerdict, lastRefusal, Clock.monotonic() - lastEventAt
end

function CombatController.sentCount(): number
	return sentCount
end

--[[
	Tente une attaque et **retourne toujours** ce qui s'est passé.

	Le retour n'est pas un confort : la version précédente pouvait sortir sans
	rien dire à trois endroits, ce qui rendait une panne indiscernable d'un
	joueur qui ne clique pas. Une fonction qui peut échouer en silence est une
	fonction qu'on ne peut pas déboguer à distance.
]]
local function requestAttack(): string
	local balance = TuningController.balance()

	local attempt = StateMirrorController.tryPredict("Attacking")
	if not attempt.ok then
		lastRefusal = `local:{attempt.code}`
		lastEventAt = Clock.monotonic()
		return `refus local : {attempt.code} ({attempt.detail or "sans détail"})`
	end

	local state = attempt.value
	local step = Frames.stepFor(state.chainIndex, balance)
	if step == nil then
		lastRefusal = `local:NoFrameData`
		lastEventAt = Clock.monotonic()
		return `aucun frame data pour l'index de chaîne {state.chainIndex}`
	end

	local sequence = nextSequence
	nextSequence += 1

	pending = {
		seq = sequence,
		impactAt = state.enteredAt + step.windup,
		reported = false,
	}

	if not Net.Client.available(Definitions.CombatAttack) then
		lastRefusal = "local:RemoteMissing"
		lastEventAt = Clock.monotonic()
		return "le remote Combat.Attack est absent côté client"
	end

	Net.Client.fire(Definitions.CombatAttack, {
		seq = sequence,
		clientTime = state.enteredAt,
	})
	sentCount += 1

	return `coup {sequence} envoyé, index {state.chainIndex}, impact dans {string.format(
		"%.0f",
		step.windup * 1000
	)} ms`
end

--[[
	Déclenche une attaque sans passer par l'entrée clavier/souris.

	Sert à couper un diagnostic en deux : si cet appel produit un coup alors que
	le clic n'en produit pas, la panne est dans la chaîne d'entrée et pas dans le
	combat. Utilisable depuis la barre de commande du client.
]]
function CombatController.debugAttack(): string
	local outcome = requestAttack()
	Log.info(SCOPE, `debugAttack : {outcome}`)
	return outcome
end

--[[
	Ouvre la hitbox quand l'instant d'impact prédit est atteint. Un coup qui ne
	touche personne n'envoie rien : le serveur n'a pas besoin d'apprendre les coups
	dans le vide, il en déduit lui-même la fin de chaîne à l'expiration.
]]
local function tick()
	local swing = pending
	if swing == nil or swing.reported then
		return
	end

	local openedAt = Clock.now()
	if openedAt < swing.impactAt then
		return
	end

	swing.reported = true
	pending = nil

	local character = HitboxDetector.ownCharacter()
	if character == nil then
		return
	end

	local hitbox = Frames.meleeHitbox(TuningController.balance())
	local targets, frame = HitboxDetector.query(character, hitbox)
	if frame then
		HitboxVisualizer.show(frame, hitbox)
	end

	-- Un coup dans le vide n'est pas rapporté : le serveur n'a pas besoin de
	-- l'apprendre, il déduit lui-même la fin de chaîne à l'expiration du coup.
	if #targets == 0 then
		return
	end

	Net.Client.fire(Definitions.CombatHitReport, {
		seq = swing.seq,
		-- L'instant où la hitbox a RÉELLEMENT été ouverte, et non l'instant
		-- d'impact prédit. Les deux diffèrent du dépassement de frame : `tick`
		-- s'exécute sur Heartbeat, donc au plus une frame après `impactAt`. C'est
		-- cet instant que le serveur rembobine, et les positions interrogées
		-- ci-dessus sont celles de cette frame-ci — dater le paquet d'`impactAt`
		-- ferait valider une géométrie contre des poses d'un autre instant.
		clientTime = openedAt,
		-- Luau refuse le transtypage direct entre deux types de tableaux ;
		-- le contenu est bien constitué d'Instance.
		targets = (targets :: any) :: { Instance },
	})
end

local function onHitResult(payload: Types.HitResult)
	lastVerdict = `{payload.verdict} −{math.floor(payload.damage)}`
	lastEventAt = Clock.monotonic()
	Log.debug(
		SCOPE,
		`coup {payload.seq} : {payload.verdict} sur {payload.target.Name}, cible à {math.floor(
			payload.targetHealth
		)} PV`
	)
end

local function onRefusal(payload: Types.Refusal)
	-- Les refus non séquencés appartiennent à une autre demande que l'attaque —
	-- la garde aujourd'hui. `GuardController` les affiche dans sa propre section ;
	-- les reprendre ici ferait apparaître un `ParryCooldown` sous « Dernier refus »
	-- du combat, au moment où l'on cherche pourquoi un coup ne passe pas.
	if payload.seq == Definitions.UNSEQUENCED then
		return
	end

	lastRefusal = payload.code
	lastEventAt = Clock.monotonic()
	-- Un refus n'est pas une erreur : c'est la réponse attendue quand on frappe à
	-- travers un mur ou hors cooldown. On le journalise pour pouvoir l'expliquer.
	Log.debug(SCOPE, `demande {payload.seq} refusée : {payload.code}`)
end

function CombatController.Init()
	Net.Client.on(Definitions.CombatHitResult, onHitResult)
	Net.Client.on(Definitions.CombatRefusal, onRefusal)

	InputController.onAction("Attack", function(phase)
		if phase ~= "Begin" then
			return
		end
		-- Journalisé en Info et non en Debug : c'est la ligne qu'on veut lire en
		-- premier quand « le clic ne fait rien ».
		Log.info(SCOPE, requestAttack())
	end)
end

function CombatController.Start()
	RunService.Heartbeat:Connect(tick)
end

return CombatController
