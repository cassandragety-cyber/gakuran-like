--!strict
--[[
	Payloads de combat : intention d'attaque, contacts rapportés, verdicts, refus.

	La frontière la plus sensible du jeu. Deux plafonds y sont appliqués avant
	qu'aucune règle de combat ne s'exécute : le nombre de cibles d'un rapport, et
	la longueur d'un code de refus.
]]

local CombatTypes = require(script.Parent.Parent.Parent.Shared.Combat.Types)
local Parsers = require(script.Parent)
local Types = require(script.Parent.Parent.Parent.Shared.Types)

local Combat = {}

function Combat.parseAttackIntent(value: unknown): Types.AttackIntent?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = Parsers.parseInteger(raw.seq, 0, 1e6)
	local clientTime = Parsers.parseFiniteNumber(raw.clientTime)
	if seq == nil or clientTime == nil then
		return nil
	end
	return { seq = seq, clientTime = clientTime }
end

--[[
	Ouverture / fermeture de garde. Deux champs, aucun verdict : la surface la
	plus étroite possible pour la mécanique la plus rentable à tricher (ADR-002).
]]
function Combat.parseBlockIntent(value: unknown): Types.BlockIntent?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local open = Parsers.parseBoolean(raw.open)
	local clientTime = Parsers.parseFiniteNumber(raw.clientTime)
	if open == nil or clientTime == nil then
		return nil
	end
	return { open = open, clientTime = clientTime }
end

--[[
	Le nombre de cibles est plafonné ici, à l'entrée. Sans ce plafond, un client
	pourrait déclarer avoir touché tout le serveur d'un seul coup et forcer autant
	de rembobinages et de raycasts — un déni de service payé par le serveur avant
	même que la moindre règle de combat ne s'applique.
]]
function Combat.parseHitReport(value: unknown, maxTargets: number): Types.HitReport?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = Parsers.parseInteger(raw.seq, 0, 1e6)
	local clientTime = Parsers.parseFiniteNumber(raw.clientTime)
	local list = raw.targets
	if seq == nil or clientTime == nil or type(list) ~= "table" then
		return nil
	end

	local source = list :: { unknown }
	if #source == 0 or #source > maxTargets then
		return nil
	end

	local targets: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, entry in source do
		local model = Parsers.parseModel(entry)
		if model == nil then
			return nil
		end
		-- Un doublon ferait résoudre deux fois le même contact. On refuse le
		-- rapport entier plutôt que de dédupliquer en silence : un client honnête
		-- ne produit pas de doublon.
		if seen[model] then
			return nil
		end
		seen[model] = true
		table.insert(targets, model)
	end

	return { seq = seq, clientTime = clientTime, targets = targets }
end

local VERDICTS: { [string]: boolean } = {
	Hit = true,
	Blocked = true,
	Parried = true,
	Ignored = true,
}

function Combat.parseHitResult(value: unknown): Types.HitResult?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = Parsers.parseInteger(raw.seq, 0, 1e6)
	local verdict = raw.verdict
	local damage = Parsers.parseFiniteNumber(raw.damage)
	local targetHealth = Parsers.parseFiniteNumber(raw.targetHealth)
	local hitstop = Parsers.parseFiniteNumber(raw.hitstop)
	local target = Parsers.parseModel(raw.target)
	local guardBroken = Parsers.parseBoolean(raw.guardBroken)

	if
		seq == nil
		or type(verdict) ~= "string"
		or not VERDICTS[verdict]
		or damage == nil
		or targetHealth == nil
		or hitstop == nil
		or target == nil
		or guardBroken == nil
	then
		return nil
	end

	return {
		seq = seq,
		verdict = verdict :: CombatTypes.Verdict,
		damage = damage,
		-- Les propriétés de table sont invariantes en Luau : un `Model` ne se
		-- convertit pas en `Instance` à cette position, alors qu'il en est un.
		target = target :: Instance,
		targetHealth = targetHealth,
		hitstop = hitstop,
		guardBroken = guardBroken,
	}
end

function Combat.parseRefusal(value: unknown): Types.Refusal?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = Parsers.parseInteger(raw.seq, 0, 1e6)
	local code = raw.code
	if seq == nil or type(code) ~= "string" or #code == 0 or #code > 48 then
		return nil
	end
	return { seq = seq, code = code }
end

return Combat
