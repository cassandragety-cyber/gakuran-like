--!strict
--[[
	Latence simulée, côté serveur, pour tenir la recette à 150 ms sans deux
	machines distantes.

	Pourquoi une file et pas un `task.delay` par paquet : `task.delay` ne garantit
	pas l'ordre de reprise entre deux tâches, et deux paquets de combat inversés
	produisent exactement les symptômes d'un bug de réseau. On passerait des
	heures à déboguer une inversion qu'on aurait soi-même introduite.

	La file est strictement FIFO : on ne dépile la tête que quand son échéance est
	atteinte. L'ordre est donc préservé même si le délai est modifié en cours de
	route depuis le panneau de debug.
]]

local RunService = game:GetService("RunService")

local Clock = require(script.Parent.Parent.Shared.Clock)

type Entry = {
	dueAt: number,
	run: () -> (),
}

local LatencySim = {}

local queue: { Entry } = {}
local head = 1
local oneWayDelay = 0
local connection: RBXScriptConnection? = nil

--[[
	On avance un curseur au lieu de retirer les éléments : créer des trous en
	tête d'un tableau Luau rend `#queue` indéfini. La file est vidée d'un coup
	quand elle est entièrement consommée, ce qui arrive à chaque flush en
	pratique, et compactée au-delà d'un seuil pour borner le pire cas.
]]
local COMPACT_THRESHOLD = 128

local function flush()
	local now = Clock.now()
	local count = #queue

	while head <= count do
		local entry = queue[head]
		if now < entry.dueAt then
			break
		end
		head += 1
		-- Un handler qui échoue ne doit pas bloquer la file derrière lui.
		task.spawn(entry.run)
	end

	if head > count then
		table.clear(queue)
		head = 1
	elseif head > COMPACT_THRESHOLD then
		local remaining = table.move(queue, head, count, 1, table.create(count - head + 1))
		table.clear(queue)
		table.move(remaining, 1, #remaining, 1, queue)
		head = 1
	end
end

--[[
	Délai aller-retour en secondes. Il est appliqué en deux moitiés, à l'entrée et
	à la sortie, pour que la latence ressentie corresponde au chiffre affiché.
]]
function LatencySim.setRoundTrip(seconds: number)
	oneWayDelay = math.max(seconds, 0) / 2

	if oneWayDelay > 0 and not connection then
		connection = RunService.Heartbeat:Connect(flush)
	elseif oneWayDelay == 0 and connection then
		-- On vide ce qui restait plutôt que de l'abandonner : sinon désactiver la
		-- simulation ferait disparaître des paquets en vol.
		flush()
		connection:Disconnect()
		connection = nil
	end
end

function LatencySim.oneWayDelay(): number
	return oneWayDelay
end

--[[
	Exécute `run` immédiatement si la simulation est désactivée — coût nul en
	production — sinon l'ajoute à la file.
]]
function LatencySim.dispatch(run: () -> ())
	if oneWayDelay <= 0 then
		run()
		return
	end
	table.insert(queue, { dueAt = Clock.now() + oneWayDelay, run = run })
end

function LatencySim.pending(): number
	return #queue - head + 1
end

return LatencySim
