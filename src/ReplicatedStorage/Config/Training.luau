--!strict
--[[
	Terrain d'entraînement et mannequins.

	**Provisoire par construction.** La Phase 3 génère la vraie carte depuis
	`Config/World`, et cette plateforme disparaîtra alors. Elle existe parce
	qu'une place Studio vide n'a pas de sol : sans elle, tester le combat
	consisterait à regarder un personnage tomber.

	Les positions sont volontairement resserrées : la portée du M1 est de 7 studs,
	et un mannequin à 30 studs obligerait à courir entre deux essais alors que le
	but est d'enchaîner des dizaines de coups par minute.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type DummySpec = {
	name: string,
	-- Décalage par rapport au centre de la plateforme.
	offset: Vector3,
}

local Training = {
	Ground = {
		Center = Vector3.new(0, 0, 0),
		Size = Vector3.new(120, 2, 120),
		Color = Color3.fromRGB(72, 76, 82),
	},

	Dummies = {
		{ name = "Dummy_Face", offset = Vector3.new(0, 3, -10) } :: DummySpec,
		{ name = "Dummy_Left", offset = Vector3.new(-8, 3, -14) } :: DummySpec,
		{ name = "Dummy_Right", offset = Vector3.new(8, 3, -14) } :: DummySpec,
	},

	--[[
		Un mannequin derrière un mur : c'est la cible qui prouve que la ligne de
		vue est réellement vérifiée côté serveur. Sans obstacle dans la scène, le
		refus `NoLineOfSight` ne serait jamais qu'une hypothèse.
	]]
	Obstacle = {
		offset = Vector3.new(-20, 5, -10),
		size = Vector3.new(1, 8, 10),
		dummy = { name = "Dummy_Behind", offset = Vector3.new(-24, 3, -10) } :: DummySpec,
	},

	-- Délai avant qu'un mannequin mis au sol ne revienne à pleine vie.
	RespawnDelay = 2.5,

	-- Hauteur du panneau d'information au-dessus du mannequin.
	BillboardHeight = 4.5,
}

return TableUtil.deepFreeze(Training)
