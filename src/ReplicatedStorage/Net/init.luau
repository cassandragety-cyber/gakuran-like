--!strict
--[[
	Runtime réseau typé.

	Le serveur instancie les remotes à partir de Net/Definitions ; le client les
	résout à la demande. Aucun appel n'atteint un handler sans être passé par
	Net/Middleware.

	Usage serveur :
		Net.Server.on(Definitions.SystemPingRequest, function(player, payload)
			-- payload est typé Types.PingRequest, déjà validé
		end)
		Net.Server.fire(Definitions.SystemPingReply, player, { ... })

	Usage client :
		Net.Client.fire(Definitions.SystemPingRequest, { seq = 1, clientTime = t })
		Net.Client.on(Definitions.SystemPingReply, function(payload) ... end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Definitions = require(script.Definitions)
local DevAccess = require(script.Parent.Shared.DevAccess)
local LatencySim = require(script.LatencySim)
local Log = require(script.Parent.Shared.Log)
local Middleware = require(script.Middleware)
local RateLimits = require(script.Parent.Config.RateLimits)

local FOLDER_NAME = "BanchouNet"
local SCOPE = "Net"

local Net = {}
Net.Server = {}
Net.Client = {}

local serverRemotes: { [string]: RemoteEvent } = {}
local clientRemotes: { [string]: RemoteEvent } = {}

-- ==========================================================================
-- Serveur
-- ==========================================================================

--[[
	Vérifie que le contrat est complet AVANT d'exposer quoi que ce soit :
	identifiants uniques et limite de cadence déclarée pour chacun. Un remote
	sans limite est exactement le trou par lequel passe le premier exploit venu,
	donc on refuse de démarrer plutôt que de servir avec un défaut implicite.
]]
local function assertContractIsComplete()
	local seen: { [string]: boolean } = {}

	for _, definition in Definitions.List do
		if seen[definition.id] then
			error(`[Net] identifiant de remote dupliqué : {definition.id}`, 0)
		end
		seen[definition.id] = true

		local limit = (RateLimits :: any)[definition.rateLimit]
		if type(limit) ~= "table" or type(limit.capacity) ~= "number" then
			error(
				`[Net] {definition.id} référence la limite « {definition.rateLimit} », absente de Config/RateLimits`,
				0
			)
		end
	end
end

function Net.initServer()
	assert(RunService:IsServer(), "[Net] initServer() est réservé au serveur")
	assertContractIsComplete()

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local devEnabled = DevAccess.isEnabled()
	local skipped: { string } = {}

	for _, definition in Definitions.List do
		if definition.devOnly and not devEnabled then
			-- ADR-013 : on ne crée pas l'instance. Un remote absent de l'arbre
			-- n'offre aucune surface à explorer.
			table.insert(skipped, definition.id)
			continue
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = definition.id
		remote.Parent = folder
		serverRemotes[definition.id] = remote
	end

	-- Filet de sécurité contre un script qui créerait un remote hors contrat :
	-- il n'est pas rate-limité, donc il ne doit pas exister silencieusement.
	folder.ChildAdded:Connect(function(child: Instance)
		if not serverRemotes[child.Name] then
			Log.error(SCOPE, `remote non déclaré ajouté au dossier réseau : {child.Name}`)
		end
	end)

	folder.Parent = ReplicatedStorage
	Middleware.start()

	local published = #Definitions.List - #skipped
	Log.info(SCOPE, `{published} remotes publiés`)
	if #skipped > 0 then
		Log.info(
			SCOPE,
			`{#skipped} remotes de développement non instanciés : {table.concat(skipped, ", ")}`
		)
	end
end

--[[
	Un remote existe-t-il sur ce serveur ? Faux uniquement pour un `devOnly` en
	production. Les services l'appellent pour ne pas enregistrer un handler sur
	un remote absent.
]]
function Net.Server.available(definition: Definitions.AnyDefinition): boolean
	return serverRemotes[definition.id] ~= nil
end

local function serverRemote(definition: Definitions.AnyDefinition): RemoteEvent
	local remote = serverRemotes[definition.id]
	if not remote then
		error(
			`[Net] remote {definition.id} introuvable — Net.initServer() a-t-il été appelé ?`,
			2
		)
	end
	return remote
end

function Net.Server.on<T>(
	definition: Definitions.Definition<T>,
	handler: (player: Player, payload: T) -> ()
)
	assert(
		definition.direction == "ClientToServer",
		`[Net] {definition.id} n'est pas un remote client -> serveur`
	)

	serverRemote(definition).OnServerEvent:Connect(function(player: Player, raw: unknown)
		-- Le rate-limit et le parsing s'appliquent à l'ARRIVÉE, jamais après le
		-- délai simulé : c'est le débit réel qu'on veut borner, pas un débit
		-- retardé. Seule l'exécution du handler est décalée.
		local payload = Middleware.accept(player, definition, raw)
		if payload == nil then
			return
		end
		LatencySim.dispatch(function()
			handler(player, payload)
		end)
	end)
end

function Net.Server.fire<T>(definition: Definitions.Definition<T>, player: Player, payload: T)
	assert(
		definition.direction == "ServerToClient",
		`[Net] {definition.id} n'est pas un remote serveur -> client`
	)
	local remote = serverRemote(definition)
	LatencySim.dispatch(function()
		remote:FireClient(player, payload)
	end)
end

function Net.Server.fireAll<T>(definition: Definitions.Definition<T>, payload: T)
	assert(
		definition.direction == "ServerToClient",
		`[Net] {definition.id} n'est pas un remote serveur -> client`
	)
	local remote = serverRemote(definition)
	LatencySim.dispatch(function()
		remote:FireAllClients(payload)
	end)
end

-- ==========================================================================
-- Client
-- ==========================================================================

--[[
	Bloque jusqu'à ce que le serveur ait publié les remotes.

	À appeler une fois au démarrage du client, AVANT le chargement des
	controllers : sans ça, le premier `Net.Client.on` d'un `Init` yielderait sur
	un WaitForChild et retarderait l'initialisation de tous les controllers
	suivants. Le contrat du Loader (« Init ne yield pas ») tient grâce à cet
	appel préalable.
]]
function Net.Client.awaitReady()
	assert(RunService:IsClient(), "[Net] awaitReady() est réservé au client")
	ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

--[[
	Un remote `devOnly` peut légitimement ne pas exister : on le cherche sans
	attendre, sinon un client de production resterait bloqué pour toujours sur un
	WaitForChild d'un remote qui ne viendra jamais.
]]
local function clientRemote(definition: Definitions.AnyDefinition): RemoteEvent?
	local cached = clientRemotes[definition.id]
	if cached then
		return cached
	end

	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	local remote: Instance? = if definition.devOnly
		then folder:FindFirstChild(definition.id)
		else folder:WaitForChild(definition.id)

	if remote == nil then
		return nil
	end

	local event = remote :: RemoteEvent
	clientRemotes[definition.id] = event
	return event
end

function Net.Client.available(definition: Definitions.AnyDefinition): boolean
	return clientRemote(definition) ~= nil
end

function Net.Client.fire<T>(definition: Definitions.Definition<T>, payload: T)
	assert(
		definition.direction == "ClientToServer",
		`[Net] {definition.id} n'est pas un remote client -> serveur`
	)
	local remote = clientRemote(definition)
	if remote == nil then
		Log.warn(SCOPE, `{definition.id} indisponible sur ce serveur, envoi ignoré`)
		return
	end
	remote:FireServer(payload)
end

--[[
	Le payload serveur est reparsé côté client. Ce n'est pas une mesure de
	sécurité (le serveur est de confiance) mais une garantie de typage : le
	handler reçoit un T, jamais un `any` venu du réseau.
]]
function Net.Client.on<T>(definition: Definitions.Definition<T>, handler: (payload: T) -> ())
	assert(
		definition.direction == "ServerToClient",
		`[Net] {definition.id} n'est pas un remote serveur -> client`
	)

	local remote = clientRemote(definition)
	if remote == nil then
		-- Remote de développement absent en production : ne pas s'abonner est le
		-- comportement correct, pas une anomalie à signaler.
		return
	end

	remote.OnClientEvent:Connect(function(raw: unknown)
		local payload = definition.parse(raw)
		if payload == nil then
			Log.error(SCOPE, `payload serveur illisible sur {definition.id}`)
			return
		end
		handler(payload)
	end)
end

return Net
