--!strict
--[[
	Thème visuel partagé par toute l'interface.

	Centralisé dès maintenant pour que les écrans de jeu (téléphone, boutique,
	HUD) n'inventent pas chacun leurs couleurs. `TouchTarget` est une contrainte
	et pas une suggestion : 44 pixels est le minimum sous lequel un bouton devient
	frustrant au pouce, et 60 % des joueurs visés sont sur mobile.
]]

local Theme = {
	Colors = {
		Background = Color3.fromRGB(18, 18, 22),
		Surface = Color3.fromRGB(28, 28, 34),
		SurfaceRaised = Color3.fromRGB(38, 38, 46),
		Border = Color3.fromRGB(58, 58, 68),
		Text = Color3.fromRGB(236, 236, 240),
		TextMuted = Color3.fromRGB(150, 150, 162),
		Accent = Color3.fromRGB(232, 84, 84),
		Good = Color3.fromRGB(104, 196, 120),
		Warning = Color3.fromRGB(240, 176, 64),
	},

	Fonts = {
		Body = Enum.Font.Gotham,
		Strong = Enum.Font.GothamBold,
		-- Les valeurs numériques sont en police à largeur fixe : sans ça, un
		-- compteur qui défile fait sautiller toute la ligne.
		Value = Enum.Font.Code,
	},

	Sizes = {
		TextSmall = 12,
		TextBody = 14,
		TextTitle = 16,
		RowHeight = 20,
		Padding = 8,
		Corner = 6,
		TouchTarget = 44,
	},
}

return Theme
