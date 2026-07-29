--!strict
--[[
	LE CONTRAT RÉSEAU (ADR-005).

	C'est le seul endroit du projet où un remote peut naître. Net/init crée les
	objets Roblox à partir de cette table ; créer un RemoteEvent à la main
	ailleurs dans src/ est interdit, et le boot serveur échoue s'il détecte un
	remote non déclaré sous le dossier réseau.

	Chaque définition porte un `parse` plutôt qu'un `validate` booléen : la
	fonction RECONSTRUIT un payload propre à partir de la valeur brute au lieu
	de la laisser passer. Un client qui ajoute des champs, envoie une table avec
	métatable, ou glisse un `__index` piégé ne transmet donc rien au service :
	seules les valeurs explicitement recopiées survivent.

	Ajouter une entrée ici implique, dans le même commit :
	  1. une limite correspondante dans Config/RateLimits,
	  2. une ligne dans docs/THREAT_MODEL.md.
	Le point 1 est vérifié au boot par Net.initServer().
]]

local Types = require(script.Parent.Parent.Shared.Types)

export type Direction = "ClientToServer" | "ServerToClient"

export type Definition<T> = {
	id: string,
	direction: Direction,
	-- Clé dans Config/RateLimits.
	rateLimit: string,
	parse: (value: unknown) -> T?,
}

-- Version effacée, pour les traitements génériques (création des instances,
-- itération au boot). Le `any` est confiné ici et ne fuit pas vers les handlers.
export type AnyDefinition = Definition<any>

--[[
	Un entier fini dans une plage donnée. Rejette NaN, l'infini et les
	flottants — la plupart des payloads de gameplay sont des compteurs, et
	accepter 1.9999 quelque part finit toujours par produire un `nil` d'index.
]]
local function parseInteger(value: unknown, minimum: number, maximum: number): number?
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

local function parseFiniteNumber(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function parsePingRequest(value: unknown): Types.PingRequest?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = parseInteger(raw.seq, 0, 1e6)
	local clientTime = parseFiniteNumber(raw.clientTime)
	if seq == nil or clientTime == nil then
		return nil
	end

	return { seq = seq, clientTime = clientTime }
end

local function parsePingReply(value: unknown): Types.PingReply?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }

	local seq = parseInteger(raw.seq, 0, 1e6)
	local serverTime = parseFiniteNumber(raw.serverTime)
	if seq == nil or serverTime == nil then
		return nil
	end

	return { seq = seq, serverTime = serverTime }
end

local Definitions = {}

--[[
	Mesure de latence et de dérive d'horloge. Utilisé par DiagnosticsService pour
	vérifier en conditions réelles l'hypothèse centrale d'ADR-001 (le rembobinage
	borné à 250 ms couvre le ping des joueurs).
]]
Definitions.SystemPingRequest = {
	id = "System.PingRequest",
	direction = "ClientToServer",
	rateLimit = "SystemPing",
	parse = parsePingRequest,
} :: Definition<Types.PingRequest>

Definitions.SystemPingReply = {
	id = "System.PingReply",
	direction = "ServerToClient",
	rateLimit = "SystemPing",
	parse = parsePingReply,
} :: Definition<Types.PingReply>

-- Liste itérable, construite à la main pour rester ordonnée et explicite.
Definitions.List = {
	Definitions.SystemPingRequest :: AnyDefinition,
	Definitions.SystemPingReply :: AnyDefinition,
}

return Definitions
