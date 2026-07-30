--!strict
--[[
	Buffer circulaire à capacité fixe.

	Deux usages dans le projet : la fenêtre glissante d'échantillons du Profiler,
	et (Phase 1) l'historique de positions par joueur que HitValidator rembobine
	pour la lag compensation. Dans les deux cas on veut une allocation unique au
	départ et zéro allocation par écriture — d'où la table pré-remplie plutôt
	qu'un `table.insert` / `table.remove` qui décale tout le tableau.
]]

export type RingBuffer<T> = {
	capacity: number,
	count: number,
	-- Index de la prochaine écriture, dans [1, capacity].
	head: number,
	items: { T },
}

local RingBuffer = {}

function RingBuffer.new<T>(capacity: number): RingBuffer<T>
	assert(capacity > 0, "capacity doit être > 0")
	return {
		capacity = capacity,
		count = 0,
		head = 1,
		items = table.create(capacity) :: { T },
	}
end

function RingBuffer.push<T>(buffer: RingBuffer<T>, value: T)
	buffer.items[buffer.head] = value
	buffer.head = buffer.head % buffer.capacity + 1
	if buffer.count < buffer.capacity then
		buffer.count += 1
	end
end

--[[
	Élément à l'index donné, 1 = le plus ancien. Retourne nil hors bornes.

	Existe pour que le rembobinage puisse parcourir l'historique sans allouer :
	`toArray` copie, et un coup rapporté déclenche un parcours par cible.
]]
function RingBuffer.at<T>(buffer: RingBuffer<T>, index: number): T?
	if index < 1 or index > buffer.count then
		return nil
	end
	local start = if buffer.count < buffer.capacity then 1 else buffer.head
	local slot = (start + index - 2) % buffer.capacity + 1
	return buffer.items[slot]
end

--[[
	Copie les éléments du plus ancien au plus récent. Alloue : réservé aux
	chemins froids (dump du profiler), jamais à une frame de combat.
]]
function RingBuffer.toArray<T>(buffer: RingBuffer<T>): { T }
	local out = table.create(buffer.count) :: { T }
	local start = if buffer.count < buffer.capacity then 1 else buffer.head

	for offset = 0, buffer.count - 1 do
		local index = (start + offset - 1) % buffer.capacity + 1
		out[offset + 1] = buffer.items[index]
	end
	return out
end

function RingBuffer.clear<T>(buffer: RingBuffer<T>)
	table.clear(buffer.items)
	buffer.count = 0
	buffer.head = 1
end

return RingBuffer
