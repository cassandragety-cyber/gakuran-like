--!strict
--[[
	Table des animations du jeu.

	`id = 0` signifie « pas encore d'asset uploadé » : le client joue alors un
	fallback procédural (Motor6D piloté au CFrame) de même durée. Brancher une
	vraie animation consiste donc à remplacer un 0 par un asset id ici, sans
	toucher à une ligne de code de combat.

	`targetDuration` est un CONTRAT, pas une indication : le code de combat
	cadence les phases sur Balance, l'animation doit s'y conformer sinon
	l'impact visuel et l'impact réel divergent — c'est exactement ce qui produit
	les « hits fantômes » que le brief interdit. Config.validate() vérifie au
	boot que ces durées correspondent aux valeurs de Balance ; un désaccord fait
	échouer le démarrage du serveur.

	docs/ANIMATIONS.md est la version lisible de ce fichier, destinée à
	l'animateur. Les deux doivent être modifiés dans le même commit.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type Priority = "Core" | "Idle" | "Movement" | "Action" | "Action2" | "Action3" | "Action4"

export type AnimationDef = {
	id: number,
	priority: Priority,
	looped: boolean,
	targetDuration: number,
}

local function def(
	id: number,
	priority: Priority,
	looped: boolean,
	targetDuration: number
): AnimationDef
	return { id = id, priority = priority, looped = looped, targetDuration = targetDuration }
end

local Animations = {
	-- --------------------------------------------------------------------
	-- Locomotion. Remplace le pack Roblox par défaut pour donner sa silhouette
	-- au personnage (posture de banchou : épaules basses, mains en poche).
	-- --------------------------------------------------------------------
	Idle = def(0, "Idle", true, 2.0),
	Walk = def(0, "Movement", true, 1.0),
	Run = def(0, "Movement", true, 0.7),
	Jump = def(0, "Movement", false, 0.4),
	Fall = def(0, "Movement", true, 1.0),
	Land = def(0, "Movement", false, 0.3),
	-- Posture adoptée dès que le tag de combat est actif : c'est le premier
	-- signal visuel qu'un duel a commencé.
	CombatStance = def(0, "Idle", true, 2.0),

	-- --------------------------------------------------------------------
	-- Chain M1. Durées = windup + active + recovery de Balance.Melee[n].
	-- --------------------------------------------------------------------
	M1_1 = def(0, "Action", false, 0.45),
	M1_2 = def(0, "Action", false, 0.45),
	M1_3 = def(0, "Action", false, 0.55),
	M1_4 = def(0, "Action", false, 0.75),

	-- --------------------------------------------------------------------
	-- Défense.
	-- --------------------------------------------------------------------
	-- Doit se lire en moins que Balance.Parry.Window : si la pose de garde
	-- apparaît après la fermeture de la fenêtre, le parry devient invisible.
	BlockStart = def(0, "Action2", false, 0.10),
	BlockHold = def(0, "Action", true, 1.0),
	BlockHitReact = def(0, "Action3", false, 0.25),
	ParrySuccess = def(0, "Action4", false, 0.40),
	GuardBreak = def(0, "Action4", false, 1.6),

	-- --------------------------------------------------------------------
	-- Déplacement de combat. Quatre directions : un dash arrière qui joue
	-- l'animation avant se lit comme un bug côté adversaire.
	-- --------------------------------------------------------------------
	DashForward = def(0, "Action2", false, 0.20),
	DashBackward = def(0, "Action2", false, 0.20),
	DashLeft = def(0, "Action2", false, 0.20),
	DashRight = def(0, "Action2", false, 0.20),

	-- --------------------------------------------------------------------
	-- Réactions. Elles portent la lisibilité du combat pour le spectateur
	-- autant que pour les deux joueurs.
	-- --------------------------------------------------------------------
	HitLight = def(0, "Action3", false, 0.30),
	HitHeavy = def(0, "Action3", false, 0.45),
	Stun = def(0, "Action4", false, 1.2),
	KnockdownFall = def(0, "Action4", false, 0.50),
	KnockdownIdle = def(0, "Action3", true, 1.0),
	GetUp = def(0, "Action4", false, 0.60),
	KO = def(0, "Action4", false, 1.0),
}

return TableUtil.deepFreeze(Animations)
