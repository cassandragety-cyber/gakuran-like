--!strict
--[[
	Reconstruction des payloads réseau.

	Chaque fonction RECONSTRUIT une valeur propre au lieu de valider sur place la
	table reçue : champs supplémentaires, métatables et pièges `__index` ne
	franchissent donc jamais cette frontière. C'est la première ligne du modèle de
	menace (docs/THREAT_MODEL.md §1).

	Séparé de `Definitions` pour que le contrat réseau reste lisible d'un coup
	d'œil : d'un côté la liste des remotes, de l'autre la mécanique de parsing.
]]

local CombatTypes = require(script.Parent.Parent.Shared.Combat.Types)
local Types = require(script.Parent.Parent.Shared.Types)

local Parsers = {}

--[[
	Un entier fini dans une plage donnée. Rejette NaN, l'infini et les
	flottants — la plupart des payloads de gameplay sont des compteurs, et
	accepter 1.9999 quelque part finit toujours par produire un `nil` d'index.
]]
function Parsers.parseInteger(value: unknown, minimum: number, maximum: number): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value % 1 ~= 0 or value < minimum or value > maximum then
		return nil
	end
	return value
end

function Parsers.parseFiniteNumber(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function Parsers.parsePingRequest(value: unknown): Types.PingRequest?
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

function Parsers.parsePingReply(value: unknown): Types.PingReply?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = Parsers.parseInteger(raw.seq, 0, 1e6)
	local serverTime = Parsers.parseFiniteNumber(raw.serverTime)
	if seq == nil or serverTime == nil then
		return nil
	end

	return { seq = seq, serverTime = serverTime }
end

function Parsers.parseBoolean(value: unknown): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

local STATE_NAMES: { [string]: boolean } = {
	Idle = true,
	Attacking = true,
	Blocking = true,
	Dashing = true,
	Stunned = true,
	Knocked = true,
	GettingUp = true,
	Downed = true,
}

--[[
	Reconstruit un CombatState. Les champs d'échéance sont optionnels : `nil` y
	signifie « pas d'échéance », ce qui est un état légitime (une garde maintenue
	n'expire pas). On distingue donc « absent » de « invalide ».
]]
function Parsers.parseOptionalNumber(value: unknown): (boolean, number?)
	if value == nil then
		return true, nil
	end
	local parsed = Parsers.parseFiniteNumber(value)
	if parsed == nil then
		return false, nil
	end
	return true, parsed
end

function Parsers.parseCombatState(value: unknown): CombatTypes.CombatState?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local name = raw.name
	if type(name) ~= "string" or not STATE_NAMES[name] then
		return nil
	end

	local enteredAt = Parsers.parseFiniteNumber(raw.enteredAt)
	local chainIndex = Parsers.parseInteger(raw.chainIndex, 0, 16)
	if enteredAt == nil or chainIndex == nil then
		return nil
	end

	local expiresOk, expiresAt = Parsers.parseOptionalNumber(raw.expiresAt)
	local windowOk, windowUntil = Parsers.parseOptionalNumber(raw.windowUntil)
	local deadlineOk, chainDeadline = Parsers.parseOptionalNumber(raw.chainDeadline)
	if not expiresOk or not windowOk or not deadlineOk then
		return nil
	end

	return {
		name = name :: CombatTypes.StateName,
		enteredAt = enteredAt,
		expiresAt = expiresAt,
		windowUntil = windowUntil,
		chainIndex = chainIndex,
		chainDeadline = chainDeadline,
	}
end

function Parsers.parseStateSync(value: unknown): Types.StateSync?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local userId = Parsers.parseInteger(raw.userId, 1, 1e15)
	local state = Parsers.parseCombatState(raw.state)
	local health = Parsers.parseFiniteNumber(raw.health)
	local stamina = Parsers.parseFiniteNumber(raw.stamina)
	local guard = Parsers.parseFiniteNumber(raw.guard)
	local dashReadyAt = Parsers.parseFiniteNumber(raw.dashReadyAt)
	local parryReadyAt = Parsers.parseFiniteNumber(raw.parryReadyAt)
	if
		userId == nil
		or state == nil
		or health == nil
		or stamina == nil
		or guard == nil
		or dashReadyAt == nil
		or parryReadyAt == nil
	then
		return nil
	end

	return {
		userId = userId,
		state = state,
		health = health,
		stamina = stamina,
		guard = guard,
		dashReadyAt = dashReadyAt,
		parryReadyAt = parryReadyAt,
	}
end

function Parsers.parseSprintIntent(value: unknown): Types.SprintIntent?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local active = Parsers.parseBoolean(raw.active)
	local clientTime = Parsers.parseFiniteNumber(raw.clientTime)
	if active == nil or clientTime == nil then
		return nil
	end
	return { active = active, clientTime = clientTime }
end

--[[
	`path` est borné en longueur et restreint à un alphabet sans surprise. Ce
	n'est pas la vraie défense — la liste blanche de TuningGuard l'est — mais ça
	évite qu'un chemin absurde traverse le middleware et se retrouve dans un log.
]]
function Parsers.parseTuningChange(value: unknown): Types.TuningChange?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local path = raw.path
	local numeric = Parsers.parseFiniteNumber(raw.value)
	if type(path) ~= "string" or numeric == nil then
		return nil
	end
	if #path == 0 or #path > 64 or string.match(path, "^[%a%d%._]+$") == nil then
		return nil
	end
	return { path = path, value = numeric }
end

return Parsers
