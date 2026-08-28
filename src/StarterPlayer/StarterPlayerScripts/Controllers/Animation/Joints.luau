--!strict
--[[
	Ce qui compte comme jointure posable, et ce que les poses réclament.

	Séparé de `Rig`, qui lie un personnage et surveille son assemblage : ici on
	répond à « qu'est-ce qu'une jointure ? », là-bas à « lesquelles ce personnage
	a-t-il ? ». La première réponse ne dépend d'aucun personnage.

	**Le défaut que ce module existe pour rendre impossible.** Chercher uniquement
	la classe `Motor6D` ne trouve **rien** sur un rig dont les jointures sont des
	`AnimationConstraint` — pas « des noms qui ne correspondent pas », rien du
	tout. Le combat tourne alors normalement, dégâts et verdicts compris, avec un
	personnage parfaitement immobile. C'est le troisième visage du même symptôme
	pendant la recette de la tranche 1.3, après le nommage R6 et la course de
	réplication.

	D'où l'inclusion **par capacité** et non par classe seule : une jointure est
	posable si elle expose un `Transform` de type `CFrame`. C'est la propriété
	dont le moteur de pose se sert, donc c'est le seul critère qui décrive
	vraiment le besoin — et il survivra à la prochaine classe de jointure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PosesConfig = require(ReplicatedStorage.Config.Poses)

--[[
	Une jointure posable, réduite à ce dont le moteur de pose a besoin. Un type
	nominal ne conviendrait plus dès lors que deux classes sans ancêtre commun
	utile rendent le même service.
]]
export type Joint = { Transform: CFrame }

local Joints = {}

--[[
	Classes connues pour porter un `Transform`. La liste sert de filtre rapide
	avant le test de capacité, pas de définition : c'est le `Transform` qui fait
	foi.
]]
local ACCEPTED_CLASSES: { [string]: boolean } = {
	Motor6D = true,
	AnimationConstraint = true,
}

Joints.acceptedClasses = "Motor6D, AnimationConstraint"

--[[
	Classes que notre voie d'écriture DÉPLACE réellement.

	Distinction mesurée, pas supposée, et c'est tout l'objet de cette table. Un
	`AnimationConstraint` expose bien un `Transform` : il passe donc le test de
	capacité, se recense, et le panneau affiche `10/10 jointures`. Mais écrire ce
	`Transform` au render step ne bouge pas le personnage — vérifié en jeu, valeurs
	nominales pleines (85° sur un coude), relues intactes à la frame suivante, et
	zéro mouvement. La contrainte est résolue par la physique, pas par la couche
	d'animation où nous écrivons.

	Sans cette table, « posable » et « effectivement déplaçable » se confondent, et
	un rig à contraintes produit un rapport de succès — `10/10` en vert — devant un
	personnage immobile. C'est exactement ce qui a coûté sept allers-retours de
	recette, et c'est ce que ce garde-fou rend impossible.
]]
local DRIVABLE_CLASSES: { [string]: boolean } = {
	Motor6D = true,
}

Joints.drivableClasses = "Motor6D"

function Joints.isDrivable(className: string): boolean
	return DRIVABLE_CLASSES[className] == true
end

--[[
	Correspondance canonique (R15) → R6.

	Les poses sont écrites en noms R15, qui font référence. Un R6 nomme les
	siennes avec des espaces et n'a ni taille, ni coudes, ni poignets, ni genoux :
	son torse est d'une seule pièce. Ce qui ne figure pas ici n'existe pas sur un
	R6 et sera abandonné — la pose y perd son pliage, pas sa silhouette.
]]
local R6_ALIASES: { [string]: string } = {
	Neck = "Neck",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}

--[[
	Nom réel de la jointure sur ce rig, ou nil si le rig ne la possède pas.
]]
function Joints.nameFor(canonical: string, isR6: boolean): string?
	if not isR6 then
		return canonical
	end
	return R6_ALIASES[canonical]
end

--[[
	Cette instance est-elle une jointure sur laquelle on peut poser ?

	La capacité est **testée**, pas supposée : une classe peut figurer dans la
	liste et ne pas offrir la propriété sur une version donnée du moteur. Mieux
	vaut l'écarter au recensement, où on sait le dire, que planter à la première
	frame de combat.
]]
function Joints.isPosable(instance: Instance): boolean
	if not ACCEPTED_CLASSES[instance.ClassName] then
		return false
	end
	local ok, value = pcall(function()
		return (instance :: any).Transform
	end)
	return ok and typeof(value) == "CFrame"
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

function Joints.required(): { string }
	return REQUIRED
end

function Joints.requiredCount(): number
	return #REQUIRED
end

return Joints
