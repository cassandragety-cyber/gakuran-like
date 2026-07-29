--!strict
--[[
	Mesure du RTT et de la dérive d'horloge côté client.

	Trois mesures espacées à la connexion suffisent à caractériser une
	connexion ; au-delà, on mesurerait surtout du bruit tout en dépensant des
	paquets. `measure()` permet d'en déclencher une à la demande depuis la
	console (procédure de test, cf. docs/TESTING.md).

	Aucune boucle `while true` : un accumulateur sur Heartbeat qui se déconnecte
	de lui-même une fois les échantillons collectés (budget §6 du brief).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)

local SCOPE = "DiagnosticsController"
local SAMPLES_AT_JOIN = 3
local SAMPLE_INTERVAL = 1

type Pending = {
	sentMonotonic: number,
	sentClock: number,
}

local DiagnosticsController = {}

local pending: { [number]: Pending } = {}
local roundTrips: { number } = {}
local nextSequence = 0
local sampleConnection: RBXScriptConnection? = nil

--[[
	Envoie une mesure. Retourne le numéro de séquence, utile pour corréler dans
	les logs quand plusieurs mesures sont en vol.
]]
function DiagnosticsController.measure(): number
	local sequence = nextSequence
	nextSequence += 1

	local request: Pending = {
		sentMonotonic = Clock.monotonic(),
		sentClock = Clock.now(),
	}
	pending[sequence] = request

	Net.Client.fire(Definitions.SystemPingRequest, {
		seq = sequence,
		clientTime = request.sentClock,
	})

	return sequence
end

function DiagnosticsController.medianRoundTrip(): number?
	if #roundTrips == 0 then
		return nil
	end

	local sorted = table.clone(roundTrips)
	table.sort(sorted)
	return sorted[math.ceil(#sorted / 2)]
end

local function onReply(payload: { seq: number, serverTime: number })
	local request = pending[payload.seq]
	if not request then
		-- Réponse tardive après un `measure()` oublié : sans intérêt, mais pas
		-- anormale non plus.
		return
	end
	pending[payload.seq] = nil

	local roundTrip = Clock.monotonic() - request.sentMonotonic
	table.insert(roundTrips, roundTrip)

	-- serverTime est l'instant de réception côté serveur. L'écart au milieu de
	-- l'aller-retour mesure l'asymétrie de la liaison plus la dérive d'horloge.
	local skew = payload.serverTime - (request.sentClock + roundTrip / 2)

	Log.debug(
		SCOPE,
		string.format(
			"mesure %d : RTT %.0f ms, écart %.0f ms",
			payload.seq,
			roundTrip * 1000,
			skew * 1000
		)
	)

	if #roundTrips == SAMPLES_AT_JOIN then
		local median = DiagnosticsController.medianRoundTrip() or 0
		Log.info(SCOPE, string.format("RTT médian à la connexion : %.0f ms", median * 1000))
	end
end

function DiagnosticsController.Init()
	Net.Client.on(Definitions.SystemPingReply, onReply)
end

function DiagnosticsController.Start()
	local elapsed = 0
	local sent = 0

	DiagnosticsController.measure()
	sent += 1

	sampleConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < SAMPLE_INTERVAL then
			return
		end

		elapsed -= SAMPLE_INTERVAL
		DiagnosticsController.measure()
		sent += 1

		if sent >= SAMPLES_AT_JOIN then
			local connection = sampleConnection
			if connection then
				connection:Disconnect()
				sampleConnection = nil
			end
		end
	end)
end

return DiagnosticsController
