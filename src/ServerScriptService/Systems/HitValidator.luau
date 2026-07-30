--!strict
--[[
	Un coup rapporté par un client est-il plausible ?

	Module pur (ADR-011) : la ligne de vue arrive sous forme de **fonction
	injectée**, parce qu'un raycast est une opération Roblox et que ce module doit
	rester testable en fabriquant des poses. L'appelant fournit le prédicat ; ici
	on décide seulement quand l'interroger.

	Chaque refus porte un code, et ces codes remontent jusqu'au client. Un joueur
	qui frappe à travers un mur doit savoir que le coup a été refusé pour cette
	raison, sinon il conclut que le jeu perd des coups au hasard.

	Ce que ce module ne fait PAS : vérifier la cadence (le middleware réseau s'en
	charge) ni l'état du défenseur (c'est CombatResolver). Il répond à une seule
	question : « ce contact était-il géométriquement et temporellement possible ? »
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatTypes = require(ReplicatedStorage.Shared.Combat.Types)
local Result = require(ReplicatedStorage.Shared.Result)
local Types = require(ReplicatedStorage.Shared.Types)

type Snapshot = CombatTypes.Snapshot

export type Claim = {
	-- Poses rembobinées à l'instant revendiqué par le client, pas à la réception.
	attacker: Snapshot,
	target: Snapshot,
	hitbox: Types.HitboxSpec,
	-- Marge ajoutée aux demi-dimensions de la boîte, pour absorber
	-- l'interpolation et la latence résiduelle.
	toleranceStuds: number,
	-- Cosinus de l'angle maximal entre le regard de l'attaquant et sa cible.
	facingDot: number,
	hasLineOfSight: (from: Vector3, to: Vector3) -> boolean,
}

local HitValidator = {}

--[[
	Fraîcheur de l'horodatage client. Séparé du reste parce qu'il se vérifie AVANT
	de rembobiner : inutile de chercher une pose pour un instant qu'on refuse déjà.

	La borne négative autorise une petite avance d'horloge (dérive de
	synchronisation normale) ; la borne positive est celle du rembobinage.
]]
function HitValidator.checkTimestamp(
	clientTime: number,
	now: number,
	clockTolerance: number,
	maxRewind: number
): Result.Result<true>
	local age = now - clientTime
	if age < -clockTolerance then
		return Result.err(
			"FutureTimestamp",
			`horodatage {string.format("%.3f", -age)} s dans le futur`
		)
	end
	if age > maxRewind then
		return Result.err("StaleTimestamp", `horodatage vieux de {string.format("%.3f", age)} s`)
	end
	return Result.ok(true)
end

--[[
	Le contact revendiqué est-il possible ?

	Ordre des contrôles : du moins coûteux au plus coûteux. L'angle est un produit
	scalaire, la boîte trois comparaisons, la ligne de vue un raycast. Sur un
	serveur à 30 joueurs, l'ordre décide du coût réel.
]]
function HitValidator.check(claim: Claim): Result.Result<true>
	local attacker = claim.attacker
	local target = claim.target
	local toTarget = target.position - attacker.position

	-- Cône de face. Le calcul est horizontal : viser au-dessus ou en dessous ne
	-- doit pas faire perdre un coup, la hitbox s'en charge en Y.
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude > 1e-3 then
		local facing = Vector3.new(attacker.look.X, 0, attacker.look.Z)
		if facing.Magnitude > 1e-3 and facing.Unit:Dot(flat.Unit) < claim.facingDot then
			return Result.err("BehindAttacker", "la cible n'était pas dans le cône de face")
		end
	end

	-- Boîte de l'attaquant, exprimée dans son repère local. `CFrame.lookAt` sur la
	-- pose rembobinée reconstruit l'orientation qu'il avait à cet instant.
	local frame = CFrame.lookAt(attacker.position, attacker.position + attacker.look)
	local local_ = (frame * claim.hitbox.offset):PointToObjectSpace(target.position)
	local half = claim.hitbox.size / 2 + Vector3.one * claim.toleranceStuds

	if claim.hitbox.shape == "Sphere" then
		local radius = claim.hitbox.size.X / 2 + claim.toleranceStuds
		if local_.Magnitude > radius then
			return Result.err("TooFar", "hors du rayon de la hitbox")
		end
	elseif
		math.abs(local_.X) > half.X
		or math.abs(local_.Y) > half.Y
		or math.abs(local_.Z) > half.Z
	then
		return Result.err("TooFar", "hors de la boîte de la hitbox")
	end

	if not claim.hasLineOfSight(attacker.position, target.position) then
		return Result.err("NoLineOfSight", "un obstacle séparait les deux combattants")
	end

	return Result.ok(true)
end

return HitValidator
