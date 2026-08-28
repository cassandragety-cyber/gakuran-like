--!strict
--[[
	Poses subies : posture de combat, encaissements, étourdissement, chute.

	Cette famille porte la lisibilité pour le SPECTATEUR autant que pour les deux
	joueurs. Un combat où l'on ne voit pas qui prend cher n'est pas regardable, et
	le brief demande un jeu qui se joue à plusieurs sur un même terrain.

	Les poses de chute sont ici, et pas dans les clés « à venir » de `init` :
	`Knocked` est ATTEIGNABLE depuis la tranche 1.2, puisque le finisher de chaîne
	envoie au sol. Un état qu'on peut atteindre a un visuel — sinon le joueur
	tombe sans que rien ne le montre. Le ragdoll physique de la tranche 1.6
	remplacera la chute ; `GetUp` restera une animation dans tous les cas.
]]

local Shape = require(script.Parent.Shape)

local deg = Shape.deg

local Reaction: { [string]: Shape.Pose } = {
	-- Garde basse de combat : mains devant, buste de trois quarts. Premier signal
	-- visuel qu'un duel a commencé, donc volontairement discret — l'afficher en
	-- permanence lui retirerait précisément cette valeur.
	CombatStance = {
		attack = 0.2,
		release = 0,
		joints = {
			RightShoulder = deg(-28, 0, 14),
			LeftShoulder = deg(-32, 0, -14),
			RightElbow = deg(-55, 0, 0),
			LeftElbow = deg(-60, 0, 0),
			Waist = deg(5, -10, 0),
		},
	},

	HitLight = {
		attack = 0.2,
		release = 0.5,
		joints = {
			Waist = deg(-16, 8, 0),
			Neck = deg(-12, 10, 0),
			RightShoulder = deg(-14, 0, 22),
			LeftShoulder = deg(-14, 0, -22),
		},
	},
	HitHeavy = {
		attack = 0.18,
		release = 0.5,
		joints = {
			Waist = deg(-30, 14, 0),
			Neck = deg(-24, 16, 0),
			RightShoulder = deg(-8, 0, 42),
			LeftShoulder = deg(-8, 0, -42),
			RightHip = deg(-10, 0, 0),
		},
	},

	-- Étourdissement : bras ballants, buste voûté, tenu longtemps. L'adversaire
	-- doit voir d'un coup d'œil qu'il a une ouverture.
	Stun = {
		attack = 0.1,
		release = 0.2,
		joints = {
			RightShoulder = deg(12, 0, 16),
			LeftShoulder = deg(12, 0, -16),
			RightElbow = deg(-25, 0, 0),
			LeftElbow = deg(-25, 0, 0),
			Waist = deg(-20, 0, 0),
			Neck = deg(-26, 0, 0),
		},
	},

	KnockdownFall = {
		attack = 0.55,
		release = 0,
		joints = {
			Waist = deg(-62, 0, 0),
			Neck = deg(-30, 0, 0),
			RightShoulder = deg(28, 0, 58),
			LeftShoulder = deg(28, 0, -58),
			RightHip = deg(-40, 0, 0),
			LeftHip = deg(-46, 0, 0),
			RightKnee = deg(52, 0, 0),
			LeftKnee = deg(44, 0, 0),
		},
	},
	KnockdownIdle = {
		attack = 0.15,
		release = 0,
		joints = {
			Waist = deg(-68, 0, 0),
			Neck = deg(-34, 0, 0),
			RightShoulder = deg(30, 0, 62),
			LeftShoulder = deg(30, 0, -62),
			RightHip = deg(-44, 0, 0),
			LeftHip = deg(-50, 0, 0),
			RightKnee = deg(58, 0, 0),
			LeftKnee = deg(50, 0, 0),
		},
	},

	-- Relevage : on remonte par les genoux, buste encore penché. L'invulnérabilité
	-- de relevage couvre 0,35 s sur 0,60 s — la pose doit donc se lire comme « il
	-- se relève », pas comme « il est debout », sinon l'adversaire frappe dans les
	-- i-frames et croit à un hit fantôme.
	GetUp = {
		attack = 0.3,
		release = 0.45,
		joints = {
			Waist = deg(-34, 0, 0),
			Neck = deg(-14, 0, 0),
			RightShoulder = deg(-18, 0, 26),
			LeftShoulder = deg(-18, 0, -26),
			RightHip = deg(-22, 0, 0),
			RightKnee = deg(34, 0, 0),
		},
	},
	KO = {
		attack = 0.4,
		release = 0,
		joints = {
			Waist = deg(-74, 0, 8),
			Neck = deg(-38, 0, 0),
			RightShoulder = deg(34, 0, 70),
			LeftShoulder = deg(34, 0, -70),
			RightHip = deg(-52, 0, 0),
			LeftHip = deg(-56, 0, 0),
			RightKnee = deg(28, 0, 0),
			LeftKnee = deg(22, 0, 0),
		},
	},
}

return Reaction
