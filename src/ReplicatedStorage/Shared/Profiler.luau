--!strict
--[[
	Micro-profiler maison (exigence §6 du brief : mesurer le coût des hitbox).

	Le MicroProfiler de Roblox donne des frames isolées ; ce qu'on veut ici est
	une distribution sur une fenêtre glissante — c'est le p95 qui provoque les
	chutes de framerate perçues sur mobile, pas la moyenne.

	Coût quand désactivé : un test booléen et un retour. `record()` est conçu
	pour être appelé depuis une boucle de combat sans allouer.
]]

local RingBuffer = require(script.Parent.RingBuffer)

-- 240 échantillons ≈ 4 s à 60 Hz : assez pour un p95 stable, assez court pour
-- refléter la situation courante plutôt que l'historique de la session.
local WINDOW_SIZE = 240

export type Snapshot = {
	label: string,
	samples: number,
	totalCalls: number,
	minMs: number,
	averageMs: number,
	p95Ms: number,
	maxMs: number,
}

local Profiler = {}

local enabled = false
local windows: { [string]: RingBuffer.RingBuffer<number> } = {}
local totalCalls: { [string]: number } = {}

function Profiler.setEnabled(value: boolean)
	enabled = value
	if not value then
		table.clear(windows)
		table.clear(totalCalls)
	end
end

function Profiler.isEnabled(): boolean
	return enabled
end

--[[
	Enregistre une durée en secondes (typiquement `os.clock() - t0`).
	Usage : mesurer autour du bloc, pas avec une closure — une closure par
	ouverture de hitbox coûterait plus cher que ce qu'on mesure.
]]
function Profiler.record(label: string, seconds: number)
	if not enabled then
		return
	end

	local window = windows[label]
	if not window then
		window = RingBuffer.new(WINDOW_SIZE)
		windows[label] = window
	end

	RingBuffer.push(window, seconds)
	totalCalls[label] = (totalCalls[label] or 0) + 1
end

function Profiler.snapshot(label: string): Snapshot?
	local window = windows[label]
	if not window or window.count == 0 then
		return nil
	end

	local samples = RingBuffer.toArray(window)
	table.sort(samples)

	local sum = 0
	for _, value in samples do
		sum += value
	end

	local count = #samples
	local p95Index = math.max(1, math.ceil(count * 0.95))

	return {
		label = label,
		samples = count,
		totalCalls = totalCalls[label] or count,
		minMs = samples[1] * 1000,
		averageMs = (sum / count) * 1000,
		p95Ms = samples[p95Index] * 1000,
		maxMs = samples[count] * 1000,
	}
end

function Profiler.dump(): { Snapshot }
	local labels: { string } = {}
	for label in windows do
		table.insert(labels, label)
	end
	table.sort(labels)

	local out: { Snapshot } = {}
	for _, label in labels do
		local snapshot = Profiler.snapshot(label)
		if snapshot then
			table.insert(out, snapshot)
		end
	end
	return out
end

function Profiler.format(snapshot: Snapshot): string
	return string.format(
		"%-18s n=%-5d min=%.3fms moy=%.3fms p95=%.3fms max=%.3fms",
		snapshot.label,
		snapshot.totalCalls,
		snapshot.minMs,
		snapshot.averageMs,
		snapshot.p95Ms,
		snapshot.maxMs
	)
end

return Profiler
