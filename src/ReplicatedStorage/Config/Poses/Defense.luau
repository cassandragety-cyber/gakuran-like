--!strict
--[[
	Poses de défense : garde, encaissement en garde, rupture.

	C'est la famille qui porte la lisibilité de la tranche 1.4. La parade se joue
	sur 200 ms ; si l'adversaire ne peut pas distinguer d'un coup d'œil « il
	garde », « il encaisse en garde » et « sa garde a cédé », la mécanique de
	skill du jeu devient une loterie.
]]

local Shape = require(script.Parent.Shape)

local deg = Shape.deg

--[[
	Silhouette de garde, partagée par la montée et la tenue.

	Une seule table pour les deux : `BlockStart` et `BlockHold` doivent viser
	exactement la même cible, sinon le passage de l'une à l'autre produit un
	décrochage visible au moment où le joueur a le plus besoin de lire sa garde.
]]
local GUARD_JOINTS = {
	-- Les deux avant-bras remontent devant le visage. C'est la silhouette qui
	-- doit se reconnaître à distance et de dos.
	RightShoulder = deg(-72, 0, 22),
	LeftShoulder = deg(-72, 0, -22),
	RightElbow = deg(-85, 0, 0),
	LeftElbow = deg(-85, 0, 0),
	-- Léger repli du buste : protéger, c'est se faire petit.
	Waist = deg(12, 0, 0),
	Neck = deg(-10, 0, 0),
}

local Defense: { [string]: Shape.Pose } = {
	BlockStart = { attack = 0.3, release = 0, joints = GUARD_JOINTS },
	BlockHold = { attack = 0.1, release = 0, joints = GUARD_JOINTS },

	-- Encaissement en garde : le buste recule, les bras encaissent sans s'ouvrir.
	-- La garde doit rester lisible pendant la réaction, sinon l'adversaire croit
	-- l'avoir percée et s'engage sur une ouverture qui n'existe pas.
	BlockHitReact = {
		attack = 0.25,
		release = 0.45,
		joints = {
			RightShoulder = deg(-64, 0, 30),
			LeftShoulder = deg(-64, 0, -30),
			RightElbow = deg(-92, 0, 0),
			LeftElbow = deg(-92, 0, 0),
			Waist = deg(-14, 0, 0),
			Neck = deg(-14, 0, 0),
		},
	},

	-- Guard break : les bras s'ouvrent en grand, le buste part en arrière. C'est
	-- la pose la plus ample du jeu — elle annonce 1,6 s d'ouverture, et les deux
	-- joueurs doivent la lire sans hésiter, l'un pour fuir, l'autre pour punir.
	GuardBreak = {
		attack = 0.12,
		release = 0.35,
		joints = {
			RightShoulder = deg(-30, 0, 75),
			LeftShoulder = deg(-30, 0, -75),
			RightElbow = deg(-15, 0, 0),
			LeftElbow = deg(-15, 0, 0),
			Waist = deg(-26, 0, 0),
			Neck = deg(-22, 0, 0),
		},
	},
}

return Defense
