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

local Parsers = require(script.Parent.Parsers)
local Types = require(script.Parent.Parent.Shared.Types)

export type Direction = "ClientToServer" | "ServerToClient"

export type Definition<T> = {
	id: string,
	direction: Direction,
	-- Clé dans Config/RateLimits.
	rateLimit: string,
	parse: (value: unknown) -> T?,
	--[[
		Un remote `devOnly` n'est PAS instancié quand le serveur n'est ni en
		Studio ni doté d'administrateurs déclarés (ADR-013). Il ne suffit pas de
		rejeter les appels : un remote absent de l'arbre n'offre aucune surface,
		et aucune régression de logique ne peut le rouvrir.
	]]
	devOnly: boolean?,
}

-- Version effacée, pour les traitements génériques (création des instances,
-- itération au boot). Le `any` est confiné ici et ne fuit pas vers les handlers.
export type AnyDefinition = Definition<any>

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
	parse = Parsers.parsePingRequest,
} :: Definition<Types.PingRequest>

Definitions.SystemPingReply = {
	id = "System.PingReply",
	direction = "ServerToClient",
	rateLimit = "SystemPing",
	parse = Parsers.parsePingReply,
} :: Definition<Types.PingReply>

--[[
	État autoritatif d'un joueur. Le serveur l'envoie sur changement discret
	(pour que le client réagisse dans la frame) et à cadence réduite pour les
	valeurs continues.
]]
Definitions.CombatStateSync = {
	id = "Combat.StateSync",
	direction = "ServerToClient",
	rateLimit = "CombatStateSync",
	parse = Parsers.parseStateSync,
} :: Definition<Types.StateSync>

Definitions.MoveSprintState = {
	id = "Move.SprintState",
	direction = "ClientToServer",
	rateLimit = "MoveSprint",
	parse = Parsers.parseSprintIntent,
} :: Definition<Types.SprintIntent>

Definitions.DebugSetTuning = {
	id = "Debug.SetTuning",
	direction = "ClientToServer",
	rateLimit = "DebugTuning",
	parse = Parsers.parseTuningChange,
	devOnly = true,
} :: Definition<Types.TuningChange>

Definitions.DebugTuningSync = {
	id = "Debug.TuningSync",
	direction = "ServerToClient",
	rateLimit = "DebugTuning",
	parse = Parsers.parseTuningChange,
	devOnly = true,
} :: Definition<Types.TuningChange>

-- Liste itérable, construite à la main pour rester ordonnée et explicite.
Definitions.List = {
	Definitions.SystemPingRequest :: AnyDefinition,
	Definitions.SystemPingReply :: AnyDefinition,
	Definitions.CombatStateSync :: AnyDefinition,
	Definitions.MoveSprintState :: AnyDefinition,
	Definitions.DebugSetTuning :: AnyDefinition,
	Definitions.DebugTuningSync :: AnyDefinition,
}

return Definitions
