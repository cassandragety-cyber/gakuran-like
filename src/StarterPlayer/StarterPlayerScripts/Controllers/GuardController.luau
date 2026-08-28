--!strict
--[[
	La garde vue du client : prédire, envoyer, ne jamais réclamer.

	Le contrôleur envoie **deux** messages par levée — ouverture, fermeture — et
	rien d'autre. Il n'existe aucun chemin par lequel ce fichier pourrait
	annoncer une parade : c'est ADR-002, et c'est ce qui met la mécanique la plus
	rentable à tricher hors de portée du client.

	La prédiction locale sert la lisibilité, pas l'autorité. Elle monte la pose de
	garde dans la frame de l'appui, sans attendre l'aller-retour réseau. À 150 ms
	de latence, attendre le serveur ferait apparaître la garde après la fermeture
	de la fenêtre de parade — le joueur parerait à l'aveugle, ce qui rendrait la
	tranche 1.4 injouable avant même d'être écrite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationController = require(script.Parent.AnimationController)
local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local InputController = require(script.Parent.InputController)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local StateMirrorController = require(script.Parent.StateMirrorController)

local SCOPE = "GuardController"

local GuardController = {}

GuardController.Dependencies = {
	"InputController",
	"StateMirrorController",
	"AnimationController",
}

-- Ce que le joueur DEMANDE, distinct de ce que l'autorité accorde. Les deux
-- divergent le temps d'un aller-retour, et pendant un guard break bien plus
-- longtemps : la touche reste enfoncée alors que la garde est tombée.
local held = false
local lastRefusal: string? = nil
local lastRefusalAt = 0

function GuardController.isHeld(): boolean
	return held
end

function GuardController.lastRefusal(): (string?, number)
	return lastRefusal, Clock.monotonic() - lastRefusalAt
end

local function send(open: boolean)
	if not Net.Client.available(Definitions.CombatBlockState) then
		lastRefusal = "local:RemoteMissing"
		lastRefusalAt = Clock.monotonic()
		Log.warn(SCOPE, "le remote Combat.BlockState est absent côté client")
		return
	end

	Net.Client.fire(Definitions.CombatBlockState, {
		open = open,
		-- L'instant de l'APPUI, pas celui de l'envoi. C'est lui qui ancre la
		-- fenêtre de parade côté serveur (COMBAT.md §4, ADR-017) : le dater à
		-- l'envoi décalerait la fenêtre de la latence montante.
		clientTime = Clock.now(),
	})
end

--[[
	Ouvre la garde. Retourne toujours une description de ce qui s'est passé, pour
	la même raison qu'en tranche 1.2 : une fonction qui peut échouer en silence
	est une fonction qu'on ne peut pas déboguer à distance.
]]
local function openGuard(): string
	if held then
		return "garde déjà levée"
	end

	local attempt = StateMirrorController.tryPredict("Blocking")
	if not attempt.ok then
		lastRefusal = `local:{attempt.code}`
		lastRefusalAt = Clock.monotonic()
		return `refus local : {attempt.code} ({attempt.detail or "sans détail"})`
	end

	held = true
	AnimationController.play("BlockStart")
	AnimationController.play("BlockHold")
	send(true)
	return "garde levée"
end

local function closeGuard(): string
	if not held then
		return "garde déjà baissée"
	end
	held = false

	-- La pose retombe sans attendre l'autorité. Un relâchement est toujours
	-- accordé : rien ne le coûte, et une garde qui resterait affichée le temps
	-- d'un aller-retour se lirait comme une entrée perdue.
	AnimationController.stop("BlockStart")
	AnimationController.stop("BlockHold")

	local attempt = StateMirrorController.tryPredict("Idle")
	if not attempt.ok then
		-- Cas normal après un guard break : l'autorité a imposé `Stunned`, dont
		-- aucune transition ne part. On envoie quand même la fermeture, sinon le
		-- serveur croirait la garde encore levée à la fin de l'étourdissement.
		send(false)
		return `garde relâchée hors état de garde ({attempt.code})`
	end

	send(false)
	return "garde relâchée"
end

--[[
	États dans lesquels l'autorité a RETIRÉ la garde. Le guard break y mène, le
	knockdown aussi.

	La liste est explicite, et c'est le point délicat : réconcilier sur « l'état
	autoritatif n'est pas Blocking » ferait retomber la garde au premier paquet
	suivant l'appui, puisque le serveur n'a pas encore traité l'ouverture. La
	pose clignoterait à chaque levée. Un `Idle` autoritatif ne veut pas dire
	« garde refusée », il veut dire « pas encore au courant ».
]]
local GUARD_LOST: { [string]: boolean } = {
	Stunned = true,
	Knocked = true,
	GettingUp = true,
	Downed = true,
}

--[[
	Réaligne la pose sur l'autorité.

	Sans ça, un guard break laisserait la pose de garde à l'écran pendant les
	1,6 s d'étourdissement, alors que le joueur est en réalité grand ouvert : le
	retour visuel mentirait au moment précis où il compte le plus.
]]
local function reconcile()
	if not held then
		return
	end
	local authoritative = StateMirrorController.authoritative()
	if authoritative == nil or not GUARD_LOST[authoritative.name] then
		return
	end

	held = false
	AnimationController.stop("BlockStart")
	AnimationController.stop("BlockHold")
	lastRefusal = `autorité:{authoritative.name}`
	lastRefusalAt = Clock.monotonic()
end

function GuardController.Init()
	InputController.onAction("Block", function(phase)
		local outcome = if phase == "Begin" then openGuard() else closeGuard()
		Log.debug(SCOPE, outcome)
	end)

	--[[
		Les refus de garde arrivent sur le même remote que ceux d'attaque, sans
		champ qui les distingue. Le `seq` le fait : une demande de garde n'est pas
		numérotée, le serveur la refuse donc sous le 0 réservé, et les attaques
		numérotent à partir de 1. Sans ce tri, un `ParryCooldown` s'afficherait
		dans la section Combat et un `ClaimTooEarly` dans la section Garde — soit
		exactement l'inverse de ce qu'on regarde en déboguant.
	]]
	Net.Client.on(Definitions.CombatRefusal, function(payload)
		if payload.seq ~= Definitions.UNSEQUENCED then
			return
		end
		lastRefusal = `serveur:{payload.code}`
		lastRefusalAt = Clock.monotonic()
	end)
end

function GuardController.Start()
	StateMirrorController.onSync(reconcile)
end

return GuardController
