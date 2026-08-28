--!strict
--[[
	Poses procédurales : le repli visuel quand `Animations[clé].id == 0`.

	ADR-009 promet qu'on puisse brancher une vraie animation en remplaçant un 0
	par un asset id, sans toucher au code. Ce dossier est l'autre moitié de cette
	promesse : tant que le 0 est là, le personnage joue **quand même** quelque
	chose de lisible. Un combat sans retour visuel ne se teste pas — on ne sait
	ni si on a paré, ni ce qu'on a encaissé.

	DONNÉE PURE, découpée par famille : `Defense`, `Offense`, `Reaction`. La forme
	d'une pose et l'unité dans laquelle on l'écrit vivent dans `Shape`.

	Noms de jointures : R15. Un rig R6 n'en possède aucune ; la pose est alors
	ignorée jointure par jointure plutôt que de faire échouer la lecture.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

local Defense = require(script.Defense)
local Offense = require(script.Offense)
local Reaction = require(script.Reaction)
local Shape = require(script.Shape)

export type Pose = Shape.Pose

local Poses: { [string]: Pose } = {}

--[[
	Fusion des familles. Une clé présente dans deux familles est une erreur de
	rangement, pas un remplacement silencieux : on l'affirme ici plutôt que de
	laisser l'ordre des `require` décider laquelle gagne.
]]
for _, family in { Defense, Offense, Reaction } do
	for key, pose in family do
		assert(Poses[key] == nil, `Config/Poses : la clé {key} est définie dans deux familles`)
		Poses[key] = pose
	end
end

--[[
	Clés d'animation sans pose procédurale, et ce qui les servira.

	Ce n'est pas une liste de choses oubliées : ce sont des états qu'aucun code
	ne sait encore atteindre, et poser leur silhouette maintenant reviendrait à
	dessiner à l'aveugle. `ConfigValidator` exige qu'une clé d'animation soit dans
	exactement un des trois cas — asset réel, pose procédurale, ou déclarée ici.
	Un oubli échoue donc au boot au lieu de produire un personnage figé en plein
	combat, défaut qu'on ne remarque que tard et qu'on ne relie pas à sa cause.

	La locomotion n'a pas de pose et n'en aura pas : le script `Animate` de Roblox
	s'en charge déjà, et la doubler ferait lutter deux systèmes sur les mêmes
	jointures.
]]
local Pending: { [string]: string } = {
	Idle = "moteur Roblox",
	Walk = "moteur Roblox",
	Run = "moteur Roblox",
	Jump = "moteur Roblox",
	Fall = "moteur Roblox",
	Land = "moteur Roblox",

	ParrySuccess = "1.4",
	DashForward = "1.5",
	DashBackward = "1.5",
	DashLeft = "1.5",
	DashRight = "1.5",
}

return TableUtil.deepFreeze({ Poses = Poses, Pending = Pending })
