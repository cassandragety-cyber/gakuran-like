--!strict
--[[
	Ce que le panneau de debug affiche, décrit en données.

	Une ligne = un libellé et une fonction de lecture. Ajouter un indicateur quand
	une tranche ultérieure produit la valeur correspondante est donc une entrée
	dans une de ces tables, pas une modification du contrôleur. C'est aussi
	pourquoi le panneau n'affiche que ce qui existe réellement aujourd'hui : les
	valeurs arrivent avec la tranche qui les produit, pas comme des cases vides.

	Découpage : `Character` pour ce qu'on regarde en RÉGLANT (état, ressources,
	garde, parade), `Diagnostics` pour ce qu'on regarde quand ÇA NE MARCHE PAS
	(réseau, prédiction, performance, entrées). L'ordre de concaténation est
	l'ordre d'affichage.
]]

local Character = require(script.Character)
local Diagnostics = require(script.Diagnostics)
local Format = require(script.Format)

export type Readout = Format.Readout

local Readouts = {}

Readouts.rows = table.clone(Character)
table.move(Diagnostics, 1, #Diagnostics, #Readouts.rows + 1, Readouts.rows)

return Readouts
