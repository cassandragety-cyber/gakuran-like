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

local BalanceConfig = require(script.Parent.Parent.Config.Balance)
local CombatParsers = require(script.Parent.Parsers.Combat)
local SessionParsers = require(script.Parent.Parsers.Session)
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
	Numéro de séquence réservé aux refus de demandes NON SÉQUENCÉES.

	Toutes les demandes ne portent pas de `seq` : `Combat.BlockState` ne transporte
	qu'un booléen et un horodatage. Leurs refus reviennent pourtant par le même
	remote que ceux des attaques, sans champ qui les distingue — c'est ce 0 qui
	les trie, et les attaques numérotent donc à partir de 1.

	Vit ici parce que c'est un point de contrat entre le serveur qui l'écrit et le
	client qui le lit : dupliqué des deux côtés, il dériverait.
]]
Definitions.UNSEQUENCED = 0

--[[
	Mesure de latence et de dérive d'horloge. Utilisé par DiagnosticsService pour
	vérifier en conditions réelles l'hypothèse centrale d'ADR-001 (le rembobinage
	borné à 250 ms couvre le ping des joueurs).
]]
Definitions.SystemPingRequest = {
	id = "System.PingRequest",
	direction = "ClientToServer",
	rateLimit = "SystemPing",
	parse = SessionParsers.parsePingRequest,
} :: Definition<Types.PingRequest>

Definitions.SystemPingReply = {
	id = "System.PingReply",
	direction = "ServerToClient",
	rateLimit = "SystemPing",
	parse = SessionParsers.parsePingReply,
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
	parse = SessionParsers.parseStateSync,
} :: Definition<Types.StateSync>

Definitions.MoveSprintState = {
	id = "Move.SprintState",
	direction = "ClientToServer",
	rateLimit = "MoveSprint",
	parse = SessionParsers.parseSprintIntent,
} :: Definition<Types.SprintIntent>

Definitions.DebugSetTuning = {
	id = "Debug.SetTuning",
	direction = "ClientToServer",
	rateLimit = "DebugTuning",
	parse = SessionParsers.parseTuningChange,
	devOnly = true,
} :: Definition<Types.TuningChange>

Definitions.DebugTuningSync = {
	id = "Debug.TuningSync",
	direction = "ServerToClient",
	rateLimit = "DebugTuning",
	parse = SessionParsers.parseTuningChange,
	devOnly = true,
} :: Definition<Types.TuningChange>

--[[
	Demande d'attaque. Le serveur en dérive l'index de chaîne (ADR-012).
]]
Definitions.CombatAttack = {
	id = "Combat.Attack",
	direction = "ClientToServer",
	rateLimit = "CombatAttack",
	parse = CombatParsers.parseAttackIntent,
} :: Definition<Types.AttackIntent>

--[[
	Ouverture / fermeture de la garde. Le client n'y déclare jamais une parade :
	il date son appui, le serveur arbitre (ADR-002).
]]
Definitions.CombatBlockState = {
	id = "Combat.BlockState",
	direction = "ClientToServer",
	rateLimit = "CombatBlock",
	parse = CombatParsers.parseBlockIntent,
} :: Definition<Types.BlockIntent>

--[[
	Contacts détectés par le client. Le plafond de cibles est appliqué par le
	parseur, avec la valeur d'équilibrage : un rapport surdimensionné est rejeté
	avant d'avoir coûté un seul rembobinage.
]]
Definitions.CombatHitReport = {
	id = "Combat.HitReport",
	direction = "ClientToServer",
	rateLimit = "CombatHitReport",
	parse = function(value: unknown): Types.HitReport?
		return CombatParsers.parseHitReport(value, BalanceConfig.Hitbox.MaxTargetsPerSwing)
	end,
} :: Definition<Types.HitReport>

Definitions.CombatHitResult = {
	id = "Combat.HitResult",
	direction = "ServerToClient",
	rateLimit = "CombatFeedback",
	parse = CombatParsers.parseHitResult,
} :: Definition<Types.HitResult>

--[[
	Refus, avec son code. Sans ce retour, un coup rejeté pour cause de mur ou de
	cooldown se lit comme un coup perdu, et le joueur conclut que le jeu rate des
	entrées.
]]
Definitions.CombatRefusal = {
	id = "Combat.Refusal",
	direction = "ServerToClient",
	rateLimit = "CombatFeedback",
	parse = CombatParsers.parseRefusal,
} :: Definition<Types.Refusal>

-- Liste itérable, construite à la main pour rester ordonnée et explicite.
Definitions.List = {
	Definitions.SystemPingRequest :: AnyDefinition,
	Definitions.SystemPingReply :: AnyDefinition,
	Definitions.CombatStateSync :: AnyDefinition,
	Definitions.MoveSprintState :: AnyDefinition,
	Definitions.CombatAttack :: AnyDefinition,
	Definitions.CombatBlockState :: AnyDefinition,
	Definitions.CombatHitReport :: AnyDefinition,
	Definitions.CombatHitResult :: AnyDefinition,
	Definitions.CombatRefusal :: AnyDefinition,
	Definitions.DebugSetTuning :: AnyDefinition,
	Definitions.DebugTuningSync :: AnyDefinition,
}

return Definitions
