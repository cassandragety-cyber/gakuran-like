--!strict
--[[
	Fonctions numériques partagées. Volontairement minimal : `math.clamp` et
	`math.round` existent déjà nativement, on n'ajoute ici que ce qui manque.
]]

local MathUtil = {}

function MathUtil.lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

--[[
	Position relative de `value` dans l'intervalle, dans [0, 1]. Utilisé par les
	curseurs du panneau de debug pour convertir une valeur d'équilibrage en
	position à l'écran. Un intervalle dégénéré retourne 0 plutôt que d'exploser
	en division par zéro : un curseur mal configuré doit être visible, pas fatal.
]]
function MathUtil.inverseLerp(from: number, to: number, value: number): number
	if to == from then
		return 0
	end
	return math.clamp((value - from) / (to - from), 0, 1)
end

--[[
	Arrondit à un pas donné. Les valeurs d'équilibrage de combat vivent sur une
	grille de 0,05 s (voir Config/Balance) ; régler au centième produirait des
	durées que l'animateur ne peut pas atteindre en frames entières.
]]
function MathUtil.roundTo(value: number, step: number): number
	if step <= 0 then
		return value
	end
	return math.round(value / step) * step
end

return MathUtil
