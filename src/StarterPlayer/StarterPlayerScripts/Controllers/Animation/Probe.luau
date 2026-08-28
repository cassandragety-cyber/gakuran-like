--!strict
--[[
	Mesure au point d'écriture des poses.

	Ce module existe parce que cinq allers-retours de recette ont porté sur le
	même symptôme — personnage immobile — et que chacun a été traité par une
	hypothèse. Trois étaient fausses. La leçon n'est pas « mieux deviner » : c'est
	qu'un chemin qui produit un effet visuel doit pouvoir **rendre compte de ce
	qu'il a écrit**, sans quoi le débogage se fait par élimination sur la machine
	de quelqu'un d'autre.

	Ce qu'il mesure, et pourquoi ces trois choses précisément :

	  - **combien** de jointures ont été écrites dans la frame. Zéro sépare « la
	    pose ne tourne pas » de « la pose tourne mais n'atteint rien » ;
	  - **quoi**, sur quelle jointure et de quelle classe, avec l'angle obtenu.
	    Une valeur nulle sépare « on n'écrit pas » de « on écrit l'identité » ;
	  - **ce qu'il en reste à la frame suivante**, relu AVANT la nouvelle
	    écriture. C'est la seule mesure qui distingue « on n'écrit pas » de « on
	    écrit et quelque chose écrase » — les deux donnant le même personnage
	    immobile, et ne se corrigeant pas au même endroit.

	La relecture différée d'une frame est le cœur du dispositif : relire juste
	après avoir écrit ne prouverait rien, puisque personne n'a encore eu l'occasion
	d'écraser.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Clock)
local Log = require(ReplicatedStorage.Shared.Log)

local SCOPE = "PoseProbe"

-- Tolérance de comparaison entre ce qu'on a écrit et ce qu'on relit. Large
-- devant le bruit de recomposition d'un CFrame, étroite devant la moindre pose.
local EPSILON = 1e-4

-- Plafond de lignes émises par capture, pour qu'un `capture(10)` mal réglé ne
-- noie pas l'Output.
local MAX_LINES = 240

local Probe = {}

type Sample = {
	jointName: string,
	className: string,
	value: CFrame,
}

local lastWrites: { [string]: CFrame } = {}
local sample: Sample? = nil
local writeCount = 0
local overwritten = false
local readBackAngle: number? = nil

local captureUntil = 0
local linesLeft = 0

--[[
	Angle total d'un CFrame, en degrés. Un seul nombre suffit à distinguer
	« identité » de « pose » ; les trois axes séparés n'apprendraient rien de plus
	sur la question posée ici.
]]
local function angleOf(value: CFrame): number
	local _, magnitude = value:ToAxisAngle()
	return math.deg(magnitude)
end

--[[
	Démarre une capture journalisée. Appelable depuis la barre de commande du
	client via `AnimationController.probe(secondes)`.
]]
function Probe.capture(seconds: number)
	captureUntil = Clock.monotonic() + math.clamp(seconds, 0.1, 10)
	linesLeft = MAX_LINES
	Log.info(SCOPE, `capture démarrée pour {string.format("%.1f", seconds)} s`)
end

--[[
	Relit ce que la frame précédente a écrit, AVANT que celle-ci n'écrive.

	Une valeur qui a changé entre deux frames sans qu'on y touche est la preuve
	d'un écrasement — l'`Animator`, un autre script, ou le moteur.
]]
function Probe.readBack(joints: { [string]: { Transform: CFrame } })
	local watched = sample
	if watched == nil then
		return
	end

	local joint = joints[watched.jointName]
	if joint == nil then
		overwritten = true
		readBackAngle = nil
		return
	end

	local actual = joint.Transform
	readBackAngle = angleOf(actual)
	overwritten = not actual:FuzzyEq(watched.value, EPSILON)
end

--[[
	Enregistre une écriture. La jointure retenue pour l'échantillon est la
	PREMIÈRE de la frame : un échantillon stable vaut mieux qu'un échantillon
	représentatif, puisqu'on cherche à savoir si l'écriture tient, pas laquelle.
]]
function Probe.wrote(jointName: string, className: string, value: CFrame)
	writeCount += 1
	lastWrites[jointName] = value
	if writeCount == 1 then
		sample = { jointName = jointName, className = className, value = value }
	end
end

function Probe.beginFrame()
	writeCount = 0
end

function Probe.endFrame()
	if Clock.monotonic() > captureUntil or linesLeft <= 0 then
		return
	end
	linesLeft -= 1

	local watched = sample
	if watched == nil then
		Log.info(SCOPE, "frame : 0 jointure écrite (aucune pose n'atteint de jointure)")
		return
	end

	Log.info(
		SCOPE,
		`frame : {writeCount} écrite(s) · {watched.jointName} ({watched.className}) `
			.. `écrit {string.format("%.1f", angleOf(watched.value))}° · `
			.. `relu {if readBackAngle then string.format("%.1f°", readBackAngle) else "absent"} · `
			.. `{if overwritten then "ÉCRASÉ" else "tenu"}`
	)
end

--[[
	Résumé pour le panneau F2 : nombre d'écritures de la dernière frame, jointure
	témoin, et si sa valeur a survécu à la frame précédente.
]]
function Probe.status(): (number, string, boolean)
	local watched = sample
	if watched == nil then
		return writeCount, "aucune jointure atteinte", false
	end
	return writeCount,
		string.format(
			"%s (%s) %.0f° → relu %s",
			watched.jointName,
			watched.className,
			angleOf(watched.value),
			if readBackAngle then string.format("%.0f°", readBackAngle) else "absent"
		),
		overwritten
end

return Probe
