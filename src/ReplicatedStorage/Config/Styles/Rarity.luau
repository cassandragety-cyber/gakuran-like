--!strict
--[[
	Table de raretés du gacha de styles et configuration du pity.

	Les poids sont exprimés en pourcentage et doivent totaliser exactement 100 :
	Config.validate() rejette toute autre somme. Un tirage se fait sur ces poids
	de rareté d'abord, puis uniformément parmi les styles de la rareté tirée
	(pondérés par leur propre `weight`) — de cette façon, ajouter un 16e style
	Rare ne dilue pas la probabilité d'obtenir un Mythic.

	PITY (décision produit) : un compteur de rolls sans Epic ni Mythic vit dans
	le profil du joueur. À PITY_THRESHOLD, le prochain roll est forcé sur
	PITY_TARGET_RARITY, puis le compteur repart à zéro. Il n'y a délibérément
	AUCUN pity sur Mythic : un Mythic garanti au bout de N rolls cesse d'être
	une histoire qu'on raconte à ses amis.

	Pour désactiver le pity : PITY_THRESHOLD = 0.
]]

local TableUtil = require(script.Parent.Parent.Parent.Shared.TableUtil)

local Rarity = {
	-- Ordre croissant de rareté. Sert aussi à l'affichage et au tri de l'UI.
	ORDER = { "Common", "Uncommon", "Rare", "Epic", "Mythic" },

	WEIGHTS = {
		Common = 60,
		Uncommon = 25,
		Rare = 10,
		Epic = 4,
		Mythic = 1,
	},

	-- Couleurs d'UI par rareté, définies ici pour que l'ajout d'une rareté
	-- future n'oblige pas à toucher au thème.
	COLORS = {
		Common = Color3.fromRGB(178, 178, 178),
		Uncommon = Color3.fromRGB(104, 196, 120),
		Rare = Color3.fromRGB(84, 158, 232),
		Epic = Color3.fromRGB(168, 106, 232),
		Mythic = Color3.fromRGB(240, 176, 64),
	},

	PITY_THRESHOLD = 150,
	PITY_TARGET_RARITY = "Epic",

	-- Raretés qui remettent le compteur de pity à zéro quand elles sortent
	-- naturellement.
	PITY_RESET_ON = { "Epic", "Mythic" },
}

return TableUtil.deepFreeze(Rarity)
