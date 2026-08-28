--!strict
--[[
	Résolution des jointures d'un personnage sous les noms canoniques des poses.

	Séparé de `Procedural` parce que ce sont deux questions : ce module répond à
	« sur quoi puis-je écrire ? », `Procedural` à « qu'est-ce que j'écris ? ». La
	première a une réponse qui dépend du rig, la seconde non — et c'est cette
	indépendance qui permet d'écrire les poses une seule fois.

	**Le défaut que ce module existe pour rendre impossible.** Les poses sont
	écrites en noms R15, qui font référence. Un rig R6 nomme ses jointures
	autrement — avec des espaces — et n'a ni taille, ni coudes, ni poignets, ni
	genoux : son torse est d'une seule pièce. Sur une place réglée en R6, les
	poses d'attaque ne résolvaient donc **aucune** jointure et la garde une seule,
	un tilt de tête de 10°. Le combat se jouait normalement — dégâts, verdicts,
	états, jauge de garde — sans que le personnage ne bouge, et rien dans l'Output
	ne le disait. C'est ce qui a coûté la recette de la tranche 1.3.

	La leçon est celle d'ADR-016 et d'ADR-017, appliquée à l'affichage : une
	dégradation acceptable et une panne ne doivent jamais se ressembler. Une pose
	partielle est un compromis, une pose vide est un bug, et ce module les compte
	pour que le panneau F2 les sépare.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Log)
local PosesConfig = require(ReplicatedStorage.Config.Poses)

local SCOPE = "Rig"

--[[
	Correspondance canonique (R15) → R6. Ce qui n'y figure pas n'existe pas sur un
	R6 et sera abandonné : un torse rigide ne se plie pas à la taille, et un bras
	sans coude ne se replie pas devant le visage.
]]
local R6_ALIASES: { [string]: string } = {
	Neck = "Neck",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}

local Rig = {}

local rigLabel = "aucun rig"
local resolvedCount = 0

--[[
	Jointures citées par au moins une pose.

	Calculée une fois au chargement, elle est le dénominateur du diagnostic : sans
	elle, l'absence d'une jointure resterait une non-écriture silencieuse,
	indiscernable d'une pose qui ne se déclenche pas.
]]
local REQUIRED: { string } = (function(): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for _, pose in PosesConfig.Poses do
		for jointName in pose.joints do
			if not seen[jointName] then
				seen[jointName] = true
				table.insert(names, jointName)
			end
		end
	end
	table.sort(names)
	return names
end)()

function Rig.requiredCount(): number
	return #REQUIRED
end

--[[
	État de la dernière liaison, pour le panneau F2. Trois pannes se ressemblent à
	l'écran — personnage immobile — et ne se corrigent pas au même endroit : rig
	non lié, pose non déclenchée, pose déclenchée sans jointure où l'écrire.
]]
function Rig.diagnose(): (string, number, number)
	return rigLabel, resolvedCount, #REQUIRED
end

--[[
	Indexe les Motor6D du personnage sous les noms canoniques des poses.

	Retourne une table vide plutôt que nil quand rien ne résout : l'appelant
	écrit alors dans le vide sans cas particulier, et c'est le journal qui porte
	l'alerte. Un `nil` obligerait chaque appelant à retester ce que ce module a
	déjà constaté.
]]
function Rig.bind(character: Model): { [string]: Motor6D }
	local motors: { [string]: Motor6D } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	rigLabel = if humanoid == nil then "sans Humanoid" elseif isR6 then "R6" else "R15"

	local joints: { [string]: Motor6D } = {}
	local missing: { string } = {}
	for _, canonical in REQUIRED do
		local actual = if isR6 then R6_ALIASES[canonical] else canonical
		local motor = if actual then motors[actual] else nil
		if motor then
			joints[canonical] = motor
		else
			table.insert(missing, canonical)
		end
	end
	resolvedCount = #REQUIRED - #missing

	if resolvedCount == 0 then
		local present: { string } = {}
		for name in motors do
			table.insert(present, name)
		end
		table.sort(present)

		Log.error(
			SCOPE,
			`rig {rigLabel} : aucune jointure des poses n'existe sur ce personnage. `
				.. `Le combat fonctionnera — dégâts, verdicts, états — sans que rien ne bouge. `
				.. `Jointures du rig : {if #present == 0
					then "aucune"
					else table.concat(present, ", ")}`
		)
		return joints
	end

	if #missing > 0 then
		-- Attendu sur R6, et sans gravité : l'absence de coudes et de taille prive
		-- la pose de son pliage, pas de sa silhouette générale.
		Log.warn(
			SCOPE,
			`rig {rigLabel} : {resolvedCount}/{#REQUIRED} jointures posables, absentes = {table.concat(
				missing,
				", "
			)}`
		)
	else
		Log.info(SCOPE, `rig {rigLabel} : {resolvedCount}/{#REQUIRED} jointures posables`)
	end
	return joints
end

return Rig
