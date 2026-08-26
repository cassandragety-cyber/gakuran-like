--!strict
--[[
	Rendu du volume de hitbox, activé par l'interrupteur « Afficher les hitbox ».

	Pendant les essais, un coup qui ne touche pas laisse deux explications
	possibles : la boîte était ailleurs, ou le serveur a refusé. Voir la boîte
	tranche entre les deux immédiatement, ce qui vaut mieux que de déduire la
	géométrie d'un code de refus.

	Une seule pièce, réutilisée et simplement déplacée : créer et détruire une
	instance par coup produirait des déchets à collecter au moment le plus chargé
	de la frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TuningController = require(script.Parent.TuningController)
local Types = require(ReplicatedStorage.Shared.Types)

local HitboxVisualizer = {}

HitboxVisualizer.Dependencies = { "TuningController" }

-- Durée d'affichage après l'impact. Plus courte que la phase active serait
-- illisible à l'œil ; plus longue laisserait croire à une portée persistante.
local LINGER = 0.25

local box: Part? = nil
local hideAt = 0

local function ensureBox(): Part
	local existing = box
	if existing then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "HitboxPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.75
	part.Color = Color3.fromRGB(232, 84, 84)
	part.Material = Enum.Material.Neon
	part.Parent = workspace

	box = part
	return part
end

function HitboxVisualizer.isEnabled(): boolean
	return (TuningController.currentValue("ShowHitboxes") or 0) > 0
end

--[[
	Montre le volume tel qu'il a été interrogé. On passe la CFrame calculée par le
	détecteur plutôt que de la recalculer : afficher une boîte reconstruite
	indépendamment reviendrait à déboguer deux calculs au lieu d'un.
]]
function HitboxVisualizer.show(frame: CFrame, hitbox: Types.HitboxSpec)
	if not HitboxVisualizer.isEnabled() then
		return
	end

	local part = ensureBox()
	part.Size = if hitbox.shape == "Sphere" then Vector3.one * hitbox.size.X else hitbox.size
	part.Shape = if hitbox.shape == "Sphere" then Enum.PartType.Ball else Enum.PartType.Block
	part.CFrame = frame
	part.Transparency = 0.75
	hideAt = os.clock() + LINGER
end

function HitboxVisualizer.Start()
	RunService.Heartbeat:Connect(function()
		local part = box
		if part == nil or part.Transparency >= 1 then
			return
		end
		if os.clock() >= hideAt then
			part.Transparency = 1
		end
	end)
end

return HitboxVisualizer
