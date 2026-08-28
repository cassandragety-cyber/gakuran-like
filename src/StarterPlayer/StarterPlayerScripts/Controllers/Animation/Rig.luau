--!strict
--[[
	Liaison d'un personnage : quelles jointures posables il possède, et le suivi
	de leur arrivée.

	Répond à « sur quoi puis-je écrire ? ». `Joints` répond à « qu'est-ce qu'une
	jointure ? », `Procedural` à « qu'est-ce que j'écris ? ». Les trois questions
	ont chacune coûté une recette pendant la tranche 1.3, chacune avec le même
	symptôme — un personnage immobile pendant que le combat tournait — et chacune
	avec une correction ailleurs.

	Ce module porte la deuxième : un personnage Roblox est parenté à `workspace`
	AVANT que ses membres n'aient fini d'arriver, et les jointures vivent dans les
	membres. Un recensement unique gagne la course une fois sur deux. On observe
	donc l'assemblage au lieu d'attendre un instant qu'on croit sûr.

	La règle qui en ressort, et qui vaut au-delà de l'animation : **une
	dégradation acceptable et une panne ne doivent jamais produire le même
	signal.** D'où le comptage `n/N`, affiché en permanence dans F2 et journalisé
	une fois par personnage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Joints = require(script.Parent.Joints)
local Log = require(ReplicatedStorage.Shared.Log)

local SCOPE = "Rig"

local Rig = {}

-- Délai au bout duquel on annonce l'état du rig même s'il n'a jamais atteint le
-- compte complet. Assez long pour couvrir un chargement lent, assez court pour
-- que le diagnostic arrive pendant qu'on regarde encore l'Output.
local REPORT_DELAY = 5

local rigLabel = "aucun rig"
local resolvedCount = 0
local missingNames: { string } = {}
local presentNames: { string } = {}
-- Contenu brut du personnage, relevé seulement quand aucune jointure ne
-- ressort : c'est alors la seule information qui puisse encore trancher.
local contentNames: { string } = {}

-- Jointures posables du personnage courant, sous leur nom canonique.
local current: { [string]: Joints.Joint } = {}
-- Classe réelle de chacune, conservée en parallèle : le type réduit `Joint` ne
-- la porte pas, et le diagnostic en a besoin.
local classNames: { [string]: string } = {}
-- Observation de l'assemblage, débranchée dès que le rig est complet. Un seul
-- abonnement à la fois : un respawn remplace le précédent.
local watcher: RBXScriptConnection? = nil
-- Incrémenté à chaque liaison. Un rapport différé appartenant au personnage
-- précédent se reconnaît à sa génération périmée et s'abstient — sans quoi une
-- mort rapide couperait l'observation du personnage suivant.
local generation = 0

function Rig.joints(): { [string]: Joints.Joint }
	return current
end

--[[
	Classe réelle de la jointure, pour le diagnostic. `Joints.Joint` réduit une
	jointure à son `Transform` et perd donc son type nominal : la sonde a besoin
	de le retrouver pour dire sur QUOI elle écrit.
]]
function Rig.classOf(canonical: string): string
	return classNames[canonical] or "inconnue"
end

--[[
	État de la dernière liaison, pour le panneau F2. Trois pannes se ressemblent à
	l'écran — personnage immobile — et ne se corrigent pas au même endroit : rig
	non lié, pose non déclenchée, pose déclenchée sans jointure où l'écrire.
]]
function Rig.diagnose(): (string, number, number)
	return rigLabel, resolvedCount, Joints.requiredCount()
end

function Rig.isComplete(): boolean
	return resolvedCount == Joints.requiredCount()
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
				.. `Jointures posables trouvées : {if #presentNames == 0
					then "aucune"
					else table.concat(presentNames, ", ")}`
		)
		-- Aucune jointure du tout : on ne sait plus si le modèle est le bon, s'il
		-- est vide, ou si ses jointures sont d'une classe qu'on n'accepte pas. Son
		-- contenu répond aux trois d'un coup.
		if #presentNames == 0 then
			Log.warn(
				SCOPE,
				`contenu du personnage : {if #contentNames == 0
					then "VIDE (modèle sans enfant — mauvais modèle, ou détruit)"
					else table.concat(contentNames, ", ")}`
			)
			Log.warn(SCOPE, `classes de jointure acceptées : {Joints.acceptedClasses}`)
		end
	elseif #missingNames > 0 then
		-- Attendu sur R6, et sans gravité : l'absence de coudes et de taille prive
		-- la pose de son pliage, pas de sa silhouette générale.
		Log.warn(
			SCOPE,
			`rig {rigLabel} : {resolvedCount}/{Joints.requiredCount()} jointures posables, absentes = {table.concat(
				missingNames,
				", "
			)}`
		)
	else
		Log.info(
			SCOPE,
			`rig {rigLabel} : {resolvedCount}/{Joints.requiredCount()} jointures posables`
		)
	end
end

--[[
	Indexe les jointures posables du personnage sous les noms canoniques des poses.

	**Ne journalise rien et peut être rejouée à volonté** : c'est ce qui permet à
	l'appelant de la relancer à chaque jointure qui apparaît, le temps que le
	personnage finisse de se répliquer. Voir `Procedural.bindCharacter`.

	Retourne une table vide plutôt que nil quand rien ne résout : l'appelant écrit
	alors dans le vide sans cas particulier. Un `nil` obligerait chaque appelant à
	retester ce que ce module a déjà constaté.
]]
function Rig.bind(character: Model): { [string]: Joints.Joint }
	local motors: { [string]: Joints.Joint } = {}
	local motorClasses: { [string]: string } = {}
	for _, descendant in character:GetDescendants() do
		if Joints.isPosable(descendant) then
			motors[descendant.Name] = (descendant :: any) :: Joints.Joint
			motorClasses[descendant.Name] = descendant.ClassName
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	rigLabel = if humanoid == nil then "sans Humanoid" elseif isR6 then "R6" else "R15"

	local joints: { [string]: Joints.Joint } = {}
	table.clear(classNames)
	table.clear(missingNames)
	for _, canonical in Joints.required() do
		local actual = Joints.nameFor(canonical, isR6)
		local motor = if actual then motors[actual] else nil
		if motor then
			joints[canonical] = motor
			classNames[canonical] = motorClasses[actual :: string]
		else
			table.insert(missingNames, canonical)
		end
	end
	resolvedCount = Joints.requiredCount() - #missingNames

	-- Retenu pour le rapport : quand rien ne résout, la seule question utile est
	-- « alors qu'est-ce qu'il Y A sur ce rig ? ».
	table.clear(presentNames)
	for name in motors do
		table.insert(presentNames, name)
	end
	table.sort(presentNames)

	--[[
		Et quand il n'y a rien du tout, la question devient « à quoi ressemble ce
		modèle ? ». On retient donc aussi le contenu brut du personnage.

		Écrire ce relevé coûte une itération à la liaison, une poignée de fois par
		vie de personnage. Ne pas l'écrire a coûté trois allers-retours de recette
		sur trois hypothèses successives — R6, course de réplication, classe de
		jointure — dont deux étaient fausses. Un diagnostic qui ne tranche pas
		déplace le coût sur celui qui teste.
	]]
	if next(motors) == nil then
		table.clear(contentNames)
		for _, child in character:GetChildren() do
			table.insert(contentNames, `{child.Name}:{child.ClassName}`)
		end
		table.sort(contentNames)
	end

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
		if not Joints.isPosable(descendant) then
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
