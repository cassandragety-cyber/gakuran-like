--!strict
--[[
	Contrôle des réglages à chaud. Module pur : il ne modifie rien, il autorise.

	Deux couches indépendantes protègent l'équilibrage (ADR-013) :
	  1. le remote `Debug.SetTuning` n'existe pas en production ;
	  2. ce module n'accepte que les chemins présents dans la liste blanche de
	     `Config/Debug`, et borne la valeur.

	La couche 2 existe pour le cas où la couche 1 tomberait — compte administrateur
	compromis, ou serveur laissé en mode développement par erreur. Elle borne alors
	les dégâts possibles au lieu de faire confiance à une identité.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Debug = require(ReplicatedStorage.Config.Debug)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Result = require(ReplicatedStorage.Shared.Result)
local TableUtil = require(ReplicatedStorage.Shared.TableUtil)

local TuningGuard = {}

function TuningGuard.tunableFor(path: string): Debug.Tunable?
	return Debug.Tunables[path]
end

--[[
	Valide un réglage et retourne la valeur effectivement applicable, alignée sur
	le pas du curseur. On aligne au lieu de refuser : un curseur produit des
	valeurs continues, et rejeter 0,203 quand le pas est 0,01 rendrait le panneau
	inutilisable pour une raison qui n'intéresse personne.
]]
function TuningGuard.check(path: string, value: number): Result.Result<number>
	local tunable = Debug.Tunables[path]
	if tunable == nil then
		return Result.err(
			"NotTunable",
			`« {path} » n'est pas dans la liste blanche de Config/Debug`
		)
	end

	if value ~= value then
		return Result.err("NotANumber", "valeur NaN")
	end

	local clamped = math.clamp(value, tunable.min, tunable.max)
	local aligned = MathUtil.roundTo(clamped, tunable.step)
	return Result.ok(math.clamp(aligned, tunable.min, tunable.max))
end

--[[
	Écrit une valeur validée dans la table d'équilibrage vivante. Réservé aux
	chemins de cible "Balance" ; les interrupteurs sont appliqués par
	TuningService, qui seul connaît leurs effets de bord.
]]
function TuningGuard.applyToBalance(
	balance: { [any]: any },
	path: string,
	value: number
): Result.Result<number>
	local container, key = TableUtil.resolvePath(balance, path)
	if container == nil then
		return Result.err(
			"PathNotFound",
			`« {path} » ne résout pas dans la table d'équilibrage`
		)
	end

	if type(container[key]) ~= "number" then
		return Result.err("NotNumeric", `« {path} » ne désigne pas un nombre`)
	end

	container[key] = value
	return Result.ok(value)
end

return TuningGuard
