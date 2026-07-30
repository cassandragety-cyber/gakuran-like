--!strict
--[[
	Ouverture des hitbox côté client (ADR-001).

	Le client détecte le contact, le serveur le revalide. Ce module ne décide de
	rien : il répond à « quels modèles occupent ce volume, à cet instant ».

	Deux choix de performance délibérés, parce que ce code tourne au moment le plus
	chargé d'une frame de combat :
	  - `OverlapParams` est construit une fois et réutilisé, pas alloué par coup ;
	  - le résultat est dédupliqué par modèle, sinon un personnage à quinze parties
	    produirait quinze entrées pour un seul adversaire.

	Le coût est mesuré via `Profiler.record("hitbox", …)`. Budget de la Phase 1 :
	p95 sous 0,15 ms par ouverture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profiler = require(ReplicatedStorage.Shared.Profiler)
local Types = require(ReplicatedStorage.Shared.Types)

local HitboxDetector = {}

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.MaxParts = 32

--[[
	Modèles présents dans la hitbox, hors personnage de l'attaquant.

	`maxTargets` plafonne le retour côté client aussi. Ce n'est pas une mesure de
	sécurité — le serveur applique son propre plafond — mais ça évite d'envoyer un
	paquet que le serveur rejettera en entier, ce qui coûterait au joueur le coup
	tout entier plutôt que les cibles en trop.
]]
function HitboxDetector.query(character: Model, hitbox: Types.HitboxSpec): ({ Model }, CFrame?)
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return {}, nil
	end

	local started = os.clock()
	params.FilterDescendantsInstances = { character }

	local frame = root.CFrame * hitbox.offset
	local parts = if hitbox.shape == "Sphere"
		then workspace:GetPartBoundsInRadius(frame.Position, hitbox.size.X / 2, params)
		else workspace:GetPartBoundsInBox(frame, hitbox.size, params)

	local found: { Model } = {}
	local seen: { [Model]: boolean } = {}

	for _, hit in parts do
		-- On remonte au modèle : la hitbox touche une jambe, le combat s'applique
		-- au combattant.
		local model = hit:FindFirstAncestorOfClass("Model")
		if model == nil or seen[model] then
			continue
		end
		-- Le terrain d'entraînement contient des pièces décoratives ; seules les
		-- cibles ont une pièce racine nommée comme telle.
		if model:FindFirstChild("HumanoidRootPart") == nil then
			continue
		end

		seen[model] = true
		table.insert(found, model)
		if #found >= hitbox.maxTargets then
			break
		end
	end

	Profiler.record("hitbox", os.clock() - started)
	-- La CFrame interrogée est retournée pour que le visualiseur montre le volume
	-- réellement testé, et non une reconstruction indépendante qu'il faudrait
	-- déboguer séparément.
	return found, frame
end

function HitboxDetector.ownCharacter(): Model?
	local character = Players.LocalPlayer.Character
	if character == nil or character.Parent == nil then
		return nil
	end
	return character
end

return HitboxDetector
