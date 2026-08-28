--!strict
--[[
	Poses du chain M1.

	Les deux premiers coups alternent les bras, le troisième engage la hanche, le
	finisher part de tout le corps. L'amplitude croissante n'est pas décorative :
	elle donne à l'adversaire de quoi anticiper. Un finisher qui ressemble à un
	jab priverait le défenseur du signal sur lequel il décide de parer.

	Les `attack` suivent le rapport `windup / durée totale` de `Balance.Melee` :
	la pose atteint son extension au moment exact où la hitbox s'ouvre. C'est ce
	que `ConfigValidator` protège du côté des durées, et ce qui empêche l'impact
	visuel de dériver de l'impact réel.
]]

local Shape = require(script.Parent.Shape)

local deg = Shape.deg

local Offense: { [string]: Shape.Pose } = {
	M1_1 = {
		attack = 0.22,
		release = 0.55,
		joints = {
			RightShoulder = deg(-95, 0, 8),
			RightElbow = deg(-8, 0, 0),
			LeftShoulder = deg(-25, 0, -18),
			LeftElbow = deg(-70, 0, 0),
			Waist = deg(4, -18, 0),
		},
	},
	M1_2 = {
		attack = 0.22,
		release = 0.55,
		joints = {
			LeftShoulder = deg(-95, 0, -8),
			LeftElbow = deg(-8, 0, 0),
			RightShoulder = deg(-25, 0, 18),
			RightElbow = deg(-70, 0, 0),
			Waist = deg(4, 18, 0),
		},
	},
	M1_3 = {
		attack = 0.27,
		release = 0.5,
		joints = {
			RightShoulder = deg(-105, 0, 20),
			RightElbow = deg(-20, 0, 0),
			LeftShoulder = deg(-20, 0, -25),
			LeftElbow = deg(-80, 0, 0),
			Waist = deg(8, -28, 0),
			RightHip = deg(0, -12, 0),
		},
	},
	-- Finisher : ample, lent à armer, et c'est voulu — 0,20 s d'armé, c'est la
	-- fenêtre pendant laquelle l'adversaire décide de parer ou d'esquiver.
	M1_4 = {
		attack = 0.27,
		release = 0.45,
		joints = {
			RightShoulder = deg(-125, 0, 35),
			RightElbow = deg(-12, 0, 0),
			LeftShoulder = deg(-35, 0, -40),
			LeftElbow = deg(-60, 0, 0),
			Waist = deg(14, -38, 0),
			RightHip = deg(0, -20, 0),
			LeftHip = deg(0, -10, 0),
			Neck = deg(6, -14, 0),
		},
	},
}

return Offense
