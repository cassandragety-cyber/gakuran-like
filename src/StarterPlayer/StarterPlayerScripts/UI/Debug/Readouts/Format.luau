--!strict
--[[
	Type d'une ligne de panneau, et les mises en forme partagées.

	Isolé des groupes de lignes pour qu'ils puissent tous s'y référer sans passer
	par `init`, ce qui formerait un cycle de require.

	Chaque `read` reçoit l'instant courant afin que toutes les lignes d'un même
	rafraîchissement soient cohérentes entre elles : lire l'horloge ligne par
	ligne produirait un affichage où une échéance est écoulée et la suivante non.
]]

local Theme = require(script.Parent.Parent.Parent.Theme)

local Format = {}

export type Reading = (now: number) -> (string, Color3?)

export type Readout = {
	section: string,
	label: string,
	read: Reading,
}

function Format.seconds(value: number): string
	return string.format("%.2f s", value)
end

--[[
	Temps restant avant une échéance. « écoulé » plutôt qu'une valeur négative :
	le panneau sert à régler des fenêtres de quelques dizaines de millisecondes,
	et un `-0.03 s` se lit moins vite qu'un mot.
]]
function Format.remaining(deadline: number?, now: number): (string, Color3?)
	if deadline == nil then
		return "—"
	end
	local left = deadline - now
	if left <= 0 then
		return "écoulé", Theme.Colors.TextMuted
	end
	return Format.seconds(left), Theme.Colors.Good
end

return Format
