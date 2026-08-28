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

-- Délai au bout duquel on annonce l'état du rig même s'il n'a jamais atteint le
-- compte complet. Assez long pour couvrir un chargement lent, assez court pour
-- que le diagnostic arrive pendant qu'on regarde encore l'Output.
local REPORT_DELAY = 5

local rigLabel = "aucun rig"
local resolvedCount = 0
local missingNames: { string } = {}
local presentNames: { string } = {}

-- Jointures posables du personnage courant, sous leur nom canonique.
local current: { [string]: Motor6D } = {}
-- Observation de l'assemblage, débranchée dès que le rig est complet. Un seul
-- abonnement à la fois : un respawn remplace le précédent.
local watcher: RBXScriptConnection? = nil
-- Incrémenté à chaque liaison. Un rapport différé appartenant au personnage
-- précédent se reconnaît à sa génération périmée et s'abstient — sans quoi une
-- mort rapide couperait l'observation du personnage suivant.
local generation = 0

function Rig.joints(): { [string]: Motor6D }
	return current
end

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

function Rig.isComplete(): boolean
	return resolvedCount == #REQUIRED
end

--[[
	Journalise l'état de la dernière liaison, une fois.

	Séparé de `bind` parce que `bind` est rejoué à chaque `Motor6D` qui apparaît
	pendant l'assemblage du personnage : journaliser depuis `bind` produirait une
	ligne par membre répliqué, et la seule qui compte — l'état final — serait
	noyée dans le bruit qui la précède.
]]
function Rig.report()
	if resolvedCount == 0 then
		Log.error(
			SCOPE,
			`rig {rigLabel} : aucune jointure des poses n'existe sur ce personnage. `
				.. `Le combat fonctionnera — dégâts, verdicts, états — sans que rien ne bouge. `
				.. `Jointures du rig : {if #presentNames == 0
					then "aucune"
					else table.concat(presentNames, ", ")}`
		)
	elseif #missingNames > 0 then
		-- Attendu sur R6, et sans gravité : l'absence de coudes et de taille prive
		-- la pose de son pliage, pas de sa silhouette générale.
		Log.warn(
			SCOPE,
			`rig {rigLabel} : {resolvedCount}/{#REQUIRED} jointures posables, absentes = {table.concat(
				missingNames,
				", "
			)}`
		)
	else
		Log.info(SCOPE, `rig {rigLabel} : {resolvedCount}/{#REQUIRED} jointures posables`)
	end
end

--[[
	Indexe les Motor6D du personnage sous les noms canoniques des poses.

	**Ne journalise rien et peut être rejouée à volonté** : c'est ce qui permet à
	l'appelant de la relancer à chaque jointure qui apparaît, le temps que le
	personnage finisse de se répliquer. Voir `Procedural.bindCharacter`.

	Retourne une table vide plutôt que nil quand rien ne résout : l'appelant écrit
	alors dans le vide sans cas particulier. Un `nil` obligerait chaque appelant à
	retester ce que ce module a déjà constaté.
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
	table.clear(missingNames)
	for _, canonical in REQUIRED do
		local actual = if isR6 then R6_ALIASES[canonical] else canonical
		local motor = if actual then motors[actual] else nil
		if motor then
			joints[canonical] = motor
		else
			table.insert(missingNames, canonical)
		end
	end
	resolvedCount = #REQUIRED - #missingNames

	-- Retenu pour le rapport : quand rien ne résout, la seule question utile est
	-- « alors qu'est-ce qu'il Y A sur ce rig ? ».
	table.clear(presentNames)
	for name in motors do
		table.insert(presentNames, name)
	end
	table.sort(presentNames)

	return joints
end

--[[
	Lie un personnage, et **continue** de le recenser tant qu'il s'assemble.

	Un personnage Roblox est parenté à `workspace` AVANT que ses membres n'aient
	fini d'arriver, et `Humanoid` comme `HumanoidRootPart` sont parmi les tout
	premiers. Attendre l'un d'eux ne prouve donc rien sur les `Motor6D`, qui
	vivent dans les membres : un scan unique gagne la course une fois sur deux et
	la perd le reste du temps, laissant zéro jointure pour toute la vie du
	personnage. C'est ce qui a produit `R15 · 0/10` sur un rig pourtant complet
	une fraction de seconde plus tard, et c'est le défaut que cette fonction
	existe pour rendre impossible.

	D'où l'observation plutôt que l'attente : on réindexe à chaque `Motor6D` qui
	apparaît et on se débranche dès que le compte est bon. Rig-agnostique, sans
	sentinelle à deviner — la seule preuve qu'une jointure est là, c'est qu'elle
	est là.
]]
function Rig.bindCharacter(character: Model)
	if watcher then
		watcher:Disconnect()
		watcher = nil
	end
	generation += 1
	local mine = generation

	current = Rig.bind(character)
	if Rig.isComplete() then
		Rig.report()
		return
	end

	watcher = character.DescendantAdded:Connect(function(descendant: Instance)
		if not descendant:IsA("Motor6D") then
			return
		end
		current = Rig.bind(character)
		if Rig.isComplete() and watcher then
			watcher:Disconnect()
			watcher = nil
			Rig.report()
		end
	end)

	--[[
		Filet de sécurité : un rig qui n'atteint jamais le compte complet — un R6,
		ou un personnage réellement incomplet — ne déclencherait aucun rapport. On
		annonce donc l'état atteint après un délai, une seule fois. Sans ça, le cas
		« toujours zéro jointure » resterait muet, c'est-à-dire indiscernable de
		celui où tout va bien.
	]]
	task.delay(REPORT_DELAY, function()
		if mine ~= generation or watcher == nil then
			return
		end
		watcher:Disconnect()
		watcher = nil
		Rig.report()
	end)
end

return Rig
