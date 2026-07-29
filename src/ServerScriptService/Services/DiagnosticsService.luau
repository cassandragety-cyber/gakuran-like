--!strict
--[[
	Mesure de latence par joueur et exposition du profiler.

	Ce service existe dès la Phase 0 parce qu'il porte l'hypothèse centrale du
	combat (ADR-001) : le rembobinage borné à 250 ms doit couvrir la latence
	réelle des joueurs. Sans mesure, ce chiffre resterait une croyance.

	Le client envoie son `Clock.now()` ; comme les deux machines lisent la même
	horloge serveur, l'écart à la réception est directement le délai aller
	client -> serveur. C'est exactement la quantité dont HitValidator aura
	besoin en Phase 1 pour décider de combien rembobiner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Config.Balance)
local Clock = require(ReplicatedStorage.Shared.Clock)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Profiler = require(ReplicatedStorage.Shared.Profiler)
local RingBuffer = require(ReplicatedStorage.Shared.RingBuffer)
local SessionService = require(script.Parent.SessionService)

local SCOPE = "DiagnosticsService"
local SAMPLE_WINDOW = 16

-- Au-delà, la mesure ne décrit plus une latence mais un client dont l'horloge
-- dérive (ou ment). On la journalise sans la mêler aux statistiques.
local IMPLAUSIBLE_DELAY = 2

local DiagnosticsService = {}

DiagnosticsService.Dependencies = { "SessionService" }

local latencies: { [Player]: RingBuffer.RingBuffer<number> } = {}

local function record(player: Player, delay: number)
	local window = latencies[player]
	if not window then
		window = RingBuffer.new(SAMPLE_WINDOW)
		latencies[player] = window
	end
	RingBuffer.push(window, delay)
end

--[[
	Latence aller médiane, en secondes. La médiane plutôt que la moyenne : un
	seul pic de 800 ms sur un réseau mobile fausserait durablement une moyenne.
]]
function DiagnosticsService.oneWayLatency(player: Player): number?
	local window = latencies[player]
	if not window or window.count == 0 then
		return nil
	end

	local samples = RingBuffer.toArray(window)
	table.sort(samples)
	return samples[math.ceil(#samples / 2)]
end

--[[
	Vrai si la latence du joueur dépasse ce que le rembobinage peut couvrir.
	En Phase 1, CombatService s'en servira pour expliquer un refus de hit plutôt
	que de laisser le joueur croire à un bug.
]]
function DiagnosticsService.exceedsRewindBudget(player: Player): boolean
	local latency = DiagnosticsService.oneWayLatency(player)
	return latency ~= nil and latency > Balance.Network.MaxRewind
end

function DiagnosticsService.dumpProfiler()
	if not Profiler.isEnabled() then
		Log.info(SCOPE, "profiler désactivé")
		return
	end

	local snapshots = Profiler.dump()
	if #snapshots == 0 then
		Log.info(SCOPE, "profiler actif, aucun échantillon")
		return
	end

	for _, snapshot in snapshots do
		Log.info(SCOPE, Profiler.format(snapshot))
	end
end

function DiagnosticsService.Init()
	Net.Server.on(Definitions.SystemPingRequest, function(player, payload)
		local receivedAt = Clock.now()
		local delay = receivedAt - payload.clientTime

		-- Un délai négatif signifie une horloge client en avance : plausible à
		-- quelques millisecondes près, suspect au-delà de la tolérance.
		if delay < -Balance.Network.ClockTolerance or delay > IMPLAUSIBLE_DELAY then
			Log.warn(
				SCOPE,
				`délai implausible de {player.Name} : {string.format("%.3f", delay)} s`
			)
		else
			record(player, math.max(delay, 0))
		end

		Net.Server.fire(Definitions.SystemPingReply, player, {
			seq = payload.seq,
			serverTime = receivedAt,
		})
	end)

	SessionService.onEnded(function(player: Player)
		latencies[player] = nil
	end)
end

return DiagnosticsService
