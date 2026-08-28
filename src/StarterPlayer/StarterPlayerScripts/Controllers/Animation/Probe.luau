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
local sampleAngle = 0
--[[
	Toutes les jointures écrites dans la frame, avec leur angle.

	Un témoin unique ne peut pas répondre à « les épaules reçoivent-elles une
	valeur franche ? » : il faut la répartition. C'est la question qu'on se pose
	dès qu'une pose s'écrit sans se voir, et y répondre en une capture évite un
	aller-retour de plus.
]]
local written: { { name: string, angle: number } } = {}
local writeCount = 0
local overwritten = false
local readBackAngle: number? = nil

local captureUntil = 0
local linesLeft = 0
local linesEmitted = 0
-- Nombre de passages dans la boucle de rendu, lu de l'extérieur pour distinguer
-- « la boucle ne tourne pas » de « la boucle tourne sans rien écrire ».
local frames = 0

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
	local window = math.clamp(seconds, 0.1, 10)
	local startedFrames = frames

	captureUntil = Clock.monotonic() + window
	linesLeft = MAX_LINES
	linesEmitted = 0
	Log.info(SCOPE, `capture démarrée pour {string.format("%.1f", window)} s`)

	--[[
		Une capture qui n'émet RIEN doit le dire.

		Sans cette conclusion, une boucle de rendu morte produit le même Output
		qu'une capture lancée hors combat : rien. C'est ce silence-là qui a coûté un
		aller-retour — l'instrument doit rendre compte de sa propre absence de
		mesure, sinon il ne renseigne que les cas où tout va déjà bien.
	]]
	task.delay(window + 0.2, function()
		if linesEmitted > 0 then
			Log.info(SCOPE, `capture terminée : {linesEmitted} frame(s) mesurée(s)`)
			return
		end
		if frames == startedFrames then
			Log.error(
				SCOPE,
				"capture terminée : AUCUNE frame exécutée. La boucle de rendu des poses "
					.. "n'a pas tourné une seule fois — le problème est l'accrochage au "
					.. "rendu, pas les poses ni les jointures."
			)
		else
			Log.warn(SCOPE, "capture terminée : la boucle tourne mais n'a rien journalisé")
		end
	end)
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
	Enregistre une écriture.

	Le témoin retenu est la jointure la PLUS AMPLE de la frame, et non la
	première. La première est arbitraire — l'ordre d'itération d'une table ne
	veut rien dire — et elle a coûté un aller-retour : `Waist` sortait à 12°,
	ce qui se lit « la pose est faible » alors que les épaules recevaient 75° au
	même instant. Le témoin doit répondre à « cette pose a-t-elle de
	l'amplitude ? », donc porter le maximum.
]]
function Probe.wrote(jointName: string, className: string, value: CFrame)
	writeCount += 1
	lastWrites[jointName] = value

	local angle = angleOf(value)
	table.insert(written, { name = jointName, angle = angle })

	if writeCount == 1 or angle > sampleAngle then
		sample = { jointName = jointName, className = className, value = value }
		sampleAngle = angle
	end
end

--[[
	Compteur de vivacité de la boucle de rendu.

	C'est la mesure qui manquait, et son absence a coûté un tour de plus : la
	sonde ne rendait compte que **depuis l'intérieur** d'`update`. Une boucle qui
	ne tourne pas produit donc exactement le même silence qu'une boucle qui tourne
	sans rien écrire — et les deux ne se corrigent pas au même endroit.

	Lu de l'extérieur, par le panneau, ce compteur sépare les deux sans ambiguïté.
	Règle générale : **un instrument doit pouvoir rendre compte de son propre
	silence**, sinon il ne mesure que les cas où tout va déjà bien.
]]
function Probe.beginFrame()
	frames += 1
	writeCount = 0
	sampleAngle = 0
	table.clear(written)
end

function Probe.frames(): number
	return frames
end

function Probe.endFrame()
	if Clock.monotonic() > captureUntil or linesLeft <= 0 then
		return
	end
	linesLeft -= 1
	linesEmitted += 1

	if writeCount == 0 then
		Log.info(
			SCOPE,
			"frame : AUCUNE écriture (aucune pose active, ou aucune jointure atteinte)"
		)
		return
	end

	local watched = sample :: Sample
	local parts: { string } = {}
	for _, entry in written do
		table.insert(parts, string.format("%s %.0f°", entry.name, entry.angle))
	end

	Log.info(
		SCOPE,
		`frame : {writeCount} écrite(s) ({watched.className}) — {table.concat(parts, " · ")} `
			.. `‖ max {watched.jointName} {string.format("%.1f", sampleAngle)}° · `
			.. `relu {if readBackAngle then string.format("%.1f°", readBackAngle) else "absent"} · `
			.. `{if overwritten then "ÉCRASÉ" else "tenu"}`
	)
end

--[[
	Résumé pour le panneau F2.

	`writeCount` porte la frame COURANTE ; l'échantillon, lui, survit à une frame
	sans écriture. Les afficher ensemble sans le dire — ce que faisait la première
	version — laisse lire « on écrit ceci » là où il faut lire « on n'écrit plus
	rien, voici la dernière écriture connue ». Les deux se ressemblent et ne se
	corrigent pas au même endroit : la distinction est donc explicite.
]]
function Probe.status(): (number, string, boolean)
	local watched = sample
	if writeCount == 0 then
		if watched == nil then
			return 0, "aucune écriture (aucune pose n'a jamais atteint de jointure)", true
		end
		return 0,
			string.format(
				"aucune écriture cette frame · dernière : %s %.0f°",
				watched.jointName,
				angleOf(watched.value)
			),
			true
	end

	-- « max » explicite : sans ce mot, un angle de témoin se lit comme l'amplitude
	-- de toute la pose, alors qu'il n'en est que la borne haute.
	local current = watched :: Sample
	return writeCount,
		string.format(
			"max %s (%s) %.0f° → relu %s",
			current.jointName,
			current.className,
			sampleAngle,
			if readBackAngle then string.format("%.0f°", readBackAngle) else "absent"
		),
		overwritten
end

return Probe
