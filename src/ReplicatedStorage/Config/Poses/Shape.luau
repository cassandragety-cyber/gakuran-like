--!strict
--[[
	Forme d'une pose procédurale, et l'unité dans laquelle on l'écrit.

	Isolé des familles de poses pour qu'elles puissent toutes s'y référer sans
	passer par `init`, ce qui formerait un cycle de require.

	Enveloppe temporelle, en fractions de `Animations[clé].targetDuration` :

	    |<- attack ->|<---- tenue ---->|<- release ->|
	    repos        pose              pose          repos

	`attack` est ce qui décide de la LISIBILITÉ, et c'est le seul nombre de ce
	fichier qui mérite qu'on s'y arrête. La garde a un attack très court
	(0,3 × 0,10 s = 30 ms) parce que la parade se joue sur une fenêtre de 200 ms :
	une pose qui met 100 ms à monter mangerait la moitié de la fenêtre avant que
	l'adversaire ait vu quoi que ce soit.
]]

local Shape = {}

export type Pose = {
	attack: number,
	release: number,
	joints: { [string]: CFrame },
}

--[[
	Orientation en degrés. Les poses sont relues et corrigées à l'œil, souvent par
	quelqu'un qui ne lit pas le code : les radians rendraient l'exercice absurde.
]]
function Shape.deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

return Shape
