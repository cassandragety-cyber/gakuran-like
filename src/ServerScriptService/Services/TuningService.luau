--!strict
--[[
	La table d'équilibrage vivante et son réglage à chaud (ADR-011).

	`Config.Balance` reste gelé : c'est la référence immuable et la source du
	bouton « réinitialiser ». Ce qui circule dans le combat est la copie détenue
	ici, mutée en place — donc une référence gardée par un service reste valide
	après un réglage, sans invalidation à propager.

	En production sans administrateur déclaré, la copie est **regelée** : la
	garantie d'immuabilité de la Phase 0 tient alors aussi côté combat. Elle ne
	reste mutable que là où quelqu'un a explicitement le droit de régler.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local Debug = require(ReplicatedStorage.Config.Debug)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local DevAccess = require(ReplicatedStorage.Shared.DevAccess)
local LatencySim = require(ReplicatedStorage.Net.LatencySim)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Result = require(ReplicatedStorage.Shared.Result)
local TableUtil = require(ReplicatedStorage.Shared.TableUtil)
local TuningGuard = require(script.Parent.Parent.Systems.TuningGuard)

local SCOPE = "TuningService"

type Balance = BalanceConfig.Balance

local TuningService = {}

local live: Balance = TableUtil.deepCopy(BalanceConfig)
local switchValues: { [string]: number } = {}
local listeners: { (path: string, value: number) -> () } = {}

--[[
	Effets de bord des interrupteurs. Un interrupteur sans entrée ici serait un
	curseur inerte : la table est donc la définition de ce qui existe réellement,
	et ConfigValidator vérifie la correspondance avec `Config/Debug` au boot.
]]
local SWITCH_EFFECTS: { [string]: (value: number) -> () } = {
	SimulatedLatencyMs = function(value: number)
		LatencySim.setRoundTrip(value / 1000)
	end,
}

function TuningService.balance(): Balance
	return live
end

function TuningService.switchValue(name: string): number?
	return switchValues[name]
end

--[[
	Valeur courante d'un chemin réglable, quelle que soit sa cible. Le panneau de
	debug s'en sert pour afficher la position initiale des curseurs sans savoir
	où la valeur est rangée.
]]
function TuningService.currentValue(path: string): number?
	local tunable = TuningGuard.tunableFor(path)
	if tunable == nil then
		return nil
	end

	if tunable.target == "Switch" then
		return switchValues[path]
	end

	local container, key = TableUtil.resolvePath(live :: any, path)
	if container == nil then
		return nil
	end
	local value = container[key]
	return if type(value) == "number" then value else nil
end

function TuningService.onChanged(listener: (path: string, value: number) -> ())
	table.insert(listeners, listener)
end

local function notify(path: string, value: number)
	for _, listener in listeners do
		task.spawn(listener, path, value)
	end
end

--[[
	Applique un réglage. Retourne la valeur réellement retenue, alignée sur le pas
	du curseur : le panneau doit afficher ce que le serveur a fait, pas ce qu'il a
	demandé.
]]
function TuningService.set(path: string, value: number): Result.Result<number>
	local checked = TuningGuard.check(path, value)
	if not checked.ok then
		return checked
	end

	local tunable = TuningGuard.tunableFor(path) :: Debug.Tunable
	local retained = checked.value

	if tunable.target == "Switch" then
		local effect = SWITCH_EFFECTS[path]
		if effect == nil and not tunable.clientOnly then
			return Result.err("NoEffect", `l'interrupteur « {path} » n'a aucun effet déclaré`)
		end
		switchValues[path] = retained
		if effect then
			effect(retained)
		end
	else
		local applied = TuningGuard.applyToBalance(live :: any, path, retained)
		if not applied.ok then
			return applied
		end
	end

	notify(path, retained)
	return Result.ok(retained)
end

--[[
	Remet tout à la configuration du disque. Un après-midi de réglages se jette en
	un appel, et c'est voulu : sans ce bouton on hésite à essayer des valeurs
	extrêmes, ce qui est exactement l'usage du panneau.
]]
function TuningService.reset()
	for path, tunable in Debug.Tunables do
		if tunable.target == "Switch" then
			local default = tunable.default or 0
			switchValues[path] = default
			local effect = SWITCH_EFFECTS[path]
			if effect then
				effect(default)
			end
			notify(path, default)
		else
			local source, sourceKey = TableUtil.resolvePath(BalanceConfig :: any, path)
			if source ~= nil then
				local value = source[sourceKey]
				TuningGuard.applyToBalance(live :: any, path, value)
				notify(path, value)
			end
		end
	end
	Log.info(SCOPE, "équilibrage réinitialisé depuis Config/Balance")
end

function TuningService.Init()
	for path, tunable in Debug.Tunables do
		if tunable.target == "Switch" then
			switchValues[path] = tunable.default or 0
		end
	end

	-- Un interrupteur serveur sans effet serait un curseur inerte. On le détecte
	-- au boot plutôt qu'en se demandant, un après-midi de réglages plus tard,
	-- pourquoi rien ne bouge.
	for path, tunable in Debug.Tunables do
		if
			tunable.target == "Switch"
			and not tunable.clientOnly
			and SWITCH_EFFECTS[path] == nil
		then
			error(
				`[TuningService] l'interrupteur serveur « {path} » n'a aucun effet déclaré`,
				0
			)
		end
	end

	if not DevAccess.isEnabled() then
		-- Personne ne peut régler sur ce serveur : on regèle la copie pour
		-- retrouver la garantie d'immuabilité de la Phase 0.
		TableUtil.deepFreeze(live)
		Log.info(SCOPE, "aucun accès de développement, équilibrage vivant gelé")
		return
	end

	Log.warn(SCOPE, "réglage à chaud ACTIF sur ce serveur")

	if not Net.Server.available(Definitions.DebugSetTuning) then
		return
	end

	Net.Server.on(Definitions.DebugSetTuning, function(player, payload)
		if not DevAccess.isAllowed(player) then
			Log.warn(SCOPE, `réglage refusé pour {player.Name} : pas administrateur`)
			return
		end

		local applied = TuningService.set(payload.path, payload.value)
		if not applied.ok then
			Log.warn(SCOPE, `réglage refusé ({applied.code}) : {applied.detail or payload.path}`)
			return
		end

		Log.info(SCOPE, `{player.Name} a réglé {payload.path} = {applied.value}`)
		-- Diffusé à tous : le client prédit avec sa propre copie, et deux copies
		-- divergentes produiraient une désynchronisation qu'on aurait créée
		-- soi-même en bougeant un curseur.
		Net.Server.fireAll(Definitions.DebugTuningSync, {
			path = payload.path,
			value = applied.value,
		})
	end)
end

return TuningService
