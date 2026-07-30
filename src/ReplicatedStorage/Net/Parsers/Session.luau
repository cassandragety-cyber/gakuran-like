--!strict
--[[
	Payloads de session et de diagnostic : mesure de latence, intention de sprint,
	état de combat répliqué, réglage à chaud.
]]

local CombatTypes = require(script.Parent.Parent.Parent.Shared.Combat.Types)
local Parsers = require(script.Parent)
local Types = require(script.Parent.Parent.Parent.Shared.Types)

local Session = {}

function Session.parsePingRequest(value: unknown): Types.PingRequest?
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

function Session.parsePingReply(value: unknown): Types.PingReply?
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

function Session.parseCombatState(value: unknown): CombatTypes.CombatState?
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

function Session.parseStateSync(value: unknown): Types.StateSync?
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

function Session.parseSprintIntent(value: unknown): Types.SprintIntent?
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
function Session.parseTuningChange(value: unknown): Types.TuningChange?
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

return Session
