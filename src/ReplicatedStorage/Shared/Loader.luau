--!strict
--[[
	Chargeur de modules à cycle de vie (ADR-004). Sert aux Services serveur et
	aux Controllers client.

	Contrat d'un module chargé :
		local MonService = {}
		MonService.Dependencies = { "AutreService" }   -- optionnel
		function MonService.Init() end                 -- optionnel, synchrone
		function MonService.Start() end                -- optionnel, peut yield
		return MonService

	`Dependencies` sert UNIQUEMENT à ordonner Init/Start. L'accès typé entre
	modules se fait par un `require` direct : c'est le seul moyen de conserver
	l'inférence de types en --!strict, qu'un registre `get(name): any` ferait
	perdre.

	Init de tous, puis Start de tous : à la fin des Init, tout module peut
	supposer que ses dépendances sont prêtes, sans ordre d'appel implicite.
]]

local Log = require(script.Parent.Log)

export type Module = {
	Dependencies: { string }?,
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local UNVISITED, VISITING, DONE = 0, 1, 2

local Loader = {}
local hasLoaded = false

local function collect(container: Instance, registry: { [string]: Module })
	for _, child in container:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local loaded = require(child) :: any
		if type(loaded) ~= "table" then
			error(`[Loader] {child.Name} doit retourner une table, reçu {type(loaded)}`, 0)
		end
		registry[child.Name] = loaded :: Module
	end
end

--[[
	Tri topologique en profondeur. L'ordre de départ est trié par nom pour que
	deux boots successifs produisent exactement la même séquence : un bug
	d'initialisation qui n'apparaît qu'un boot sur deux est le pire à traquer.
]]
local function resolveOrder(registry: { [string]: Module }): { string }
	local names: { string } = {}
	for name in registry do
		table.insert(names, name)
	end
	table.sort(names)

	local state: { [string]: number } = {}
	local path: { string } = {}
	local order: { string } = {}

	local function visit(name: string)
		local current = state[name] or UNVISITED
		if current == DONE then
			return
		elseif current == VISITING then
			error(`[Loader] cycle de dépendances : {table.concat(path, " -> ")} -> {name}`, 0)
		end

		local module = registry[name]
		if not module then
			error(`[Loader] dépendance introuvable : {name} (déclarée par {path[#path]})`, 0)
		end

		state[name] = VISITING
		table.insert(path, name)

		local dependencies = module.Dependencies
		if dependencies then
			for _, dependency in dependencies do
				visit(dependency)
			end
		end

		table.remove(path)
		state[name] = DONE
		table.insert(order, name)
	end

	for _, name in names do
		visit(name)
	end
	return order
end

function Loader.load(container: Instance, label: string)
	assert(not hasLoaded, "[Loader] load() ne peut être appelé qu'une fois par contexte")
	hasLoaded = true

	local registry: { [string]: Module } = {}
	collect(container, registry)
	local order = resolveOrder(registry)

	for _, name in order do
		local init = registry[name].Init
		if init then
			init()
		end
	end

	-- Start est lancé en task.spawn : un module qui yield (attente d'un asset,
	-- appel DataStore) ne doit pas retarder le démarrage des suivants.
	for _, name in order do
		local start = registry[name].Start
		if start then
			task.spawn(start)
		end
	end

	Log.info(label, `{#order} modules chargés : {table.concat(order, ", ")}`)
end

return Loader
