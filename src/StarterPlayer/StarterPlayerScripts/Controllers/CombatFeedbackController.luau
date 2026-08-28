--!strict
--[[
	Traduit l'état de combat en retour visuel.

	Un seul module décide de ce qui se joue, et il le décide à partir de l'état
	**autoritatif reflété**, jamais à partir des entrées. La différence est ce qui
	empêche le mensonge visuel : si le serveur refuse une attaque, aucune
	animation ne part, parce que rien n'a changé dans l'état. Le joueur voit ce
	qui est vrai, pas ce qu'il a demandé.

	Le pendant de cette règle, c'est que la prédiction locale doit être bonne :
	c'est elle qui alimente l'état reflété avant l'aller-retour réseau
	(`StateMirrorController`). Le retour visuel est donc immédiat sans être
	inventé — il suit une prédiction que le serveur appliquera à l'identique.

	Ce que ce module ne fait PAS encore : le hitstop. Le verdict le transporte
	depuis la tranche 1.2, mais le figement à l'impact appartient au paquet de
	lisibilité de la parade (VFX + SFX + 0,08 s), livré en 1.4 d'un bloc — un
	figement seul, sans les deux autres, se lit comme une saccade réseau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationController = require(script.Parent.AnimationController)
local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Net = require(ReplicatedStorage.Net)
local StateMirrorController = require(script.Parent.StateMirrorController)
local TuningController = require(script.Parent.TuningController)
local Types = require(ReplicatedStorage.Shared.Types)

local CombatFeedbackController = {}

CombatFeedbackController.Dependencies = {
	"StateMirrorController",
	"AnimationController",
	"TuningController",
}

-- Signature de l'état joué : le nom seul ne suffit pas, deux coups successifs de
-- la chaîne partagent l'état `Attacking` et doivent jouer des poses différentes.
local lastSignature: string? = nil
-- `-inf` et non 0 : `monotonic` part de zéro au lancement du client, si bien
-- qu'un 0 signifierait « en combat » pendant les quatre premières secondes de la
-- partie, et la posture de combat s'afficherait au spawn.
local lastCombatAt = -math.huge

--[[
	Clé d'animation correspondant à un état, ou nil quand l'état n'a rien à jouer
	de lui-même.

	`Blocking` est absent volontairement : la garde est pilotée par
	`GuardController`, qui la monte à l'appui sans attendre que l'état reflété
	confirme. Passer par ici lui coûterait la prédiction, donc la lisibilité de la
	fenêtre de parade.
]]
local function keyForState(name: string, chainIndex: number): string?
	if name == "Attacking" then
		return `M1_{chainIndex}`
	elseif name == "Stunned" then
		return "Stun"
	elseif name == "Knocked" then
		return "KnockdownFall"
	elseif name == "GettingUp" then
		return "GetUp"
	elseif name == "Downed" then
		return "KO"
	end
	return nil
end

--[[
	Tag de combat local, pour l'affichage seulement — le tag autoritatif vit sur
	le serveur et ne sert pas ici.

	Mesuré sur `monotonic` et non sur `Clock.now()` : c'est une DURÉE locale, et
	`Clock` réserve explicitement `now()` aux instants comparables entre machines.
	Mélanger les deux donnerait un écart de l'ordre du milliard de secondes, donc
	un tag jamais actif — et une posture de combat qui ne s'affiche jamais, sans
	la moindre erreur pour le signaler.
]]
local function inCombat(): boolean
	local elapsed = Clock.monotonic() - lastCombatAt
	return elapsed < TuningController.balance().Stamina.CombatTagDuration
end

local function follow()
	local state = StateMirrorController.predicted()
	local signature = `{state.name}:{state.chainIndex}`
	if signature == lastSignature then
		return
	end
	lastSignature = signature

	local key = keyForState(state.name, state.chainIndex)
	if key then
		--[[
			`GuardBreak` décrit déjà l'étourdissement qui suit une rupture de garde,
			et sa durée est calée sur `GuardBreakStun` (vérifié au boot). Jouer
			`Stun` par-dessus mélangerait deux silhouettes en une moyenne qui ne
			ressemble à ni l'une ni l'autre — or c'est le moment où la lecture
			compte le plus, puisqu'elle annonce 1,6 s d'ouverture.
		]]
		if key == "Stun" and AnimationController.isPlaying("GuardBreak") then
			return
		end
		AnimationController.play(key)
		return
	end

	--[[
		Retour au neutre. La posture de combat n'est jouée qu'avec le tag de
		combat actif : c'est le premier signal qu'un duel a commencé, et l'afficher
		en permanence lui retirerait précisément cette valeur.
	]]
	if state.name == "Idle" and inCombat() then
		AnimationController.play("CombatStance")
	else
		AnimationController.stop("CombatStance")
	end
end

--[[
	Réaction à un coup subi.

	Jouée uniquement quand la cible, c'est nous : le verdict est envoyé aux deux
	camps, et l'attaquant qui jouerait la réaction de sa victime produirait un
	contresens visuel.
]]
local function onHitResult(payload: Types.HitResult)
	lastCombatAt = Clock.monotonic()

	local character = Players.LocalPlayer.Character
	if character == nil or payload.target ~= character then
		return
	end

	if payload.verdict == "Blocked" then
		--[[
			La rupture de garde a sa propre pose, et c'est indispensable : elle
			annonce 1,6 s d'ouverture. La confondre avec un encaissement ordinaire
			priverait les deux joueurs de l'information la plus importante de
			l'échange — l'un qu'il doit fuir, l'autre qu'il peut punir.
		]]
		if payload.guardBroken then
			-- Le verdict et la réplication de l'état arrivent par deux remotes
			-- distincts, dont l'ordre n'est pas garanti. On coupe donc `Stun` ici
			-- aussi : quel que soit celui qui arrive en premier, c'est `GuardBreak`
			-- qui reste, et la lecture ne dépend pas du réseau.
			AnimationController.stop("Stun")
			AnimationController.play("GuardBreak")
		else
			AnimationController.play("BlockHitReact")
		end
		return
	end

	if payload.verdict == "Hit" then
		local heavy = payload.damage >= TuningController.balance().Combat.HeavyHitDamage
		AnimationController.play(if heavy then "HitHeavy" else "HitLight")
	end
end

function CombatFeedbackController.Init()
	Net.Client.on(Definitions.CombatHitResult, onHitResult)
end

function CombatFeedbackController.Start()
	RunService.Heartbeat:Connect(follow)
end

return CombatFeedbackController
