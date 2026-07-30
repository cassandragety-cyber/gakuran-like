--!strict
--[[
	Copie cliente de l'équilibrage.

	Le client prédit avec les mêmes règles que le serveur arbitre (COMBAT.md §1.6).
	Il lui faut donc les mêmes nombres : si un curseur du panneau de debug modifie
	la fenêtre de parade côté serveur sans que le client le sache, la prédiction
	dérive et on passe l'après-midi à déboguer une désynchronisation qu'on a
	soi-même créée. D'où la diffusion `Debug.TuningSync`.

	Comme côté serveur, la table est mutée en place : une référence gardée par un
	controller reste valide après un réglage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(ReplicatedStorage.Config.Balance)
local Debug = require(ReplicatedStorage.Config.Debug)
local Definitions = require(ReplicatedStorage.Net.Definitions)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local TableUtil = require(ReplicatedStorage.Shared.TableUtil)

local SCOPE = "TuningController"

type Balance = BalanceConfig.Balance

local TuningController = {}

local live: Balance = TableUtil.deepCopy(BalanceConfig)
local switchValues: { [string]: number } = {}
local listeners: { (path: string, value: number) -> () } = {}

function TuningController.balance(): Balance
	return live
end

function TuningController.onChanged(listener: (path: string, value: number) -> ())
	table.insert(listeners, listener)
end

--[[
	Valeur courante d'un chemin réglable. Le panneau s'en sert pour positionner
	ses curseurs à l'ouverture, sans savoir si la valeur vit dans l'équilibrage ou
	dans un interrupteur.
]]
function TuningController.currentValue(path: string): number?
	local tunable = Debug.Tunables[path]
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

--[[
	Valeur d'origine, telle qu'elle est sur le disque. Alimente le bouton de
	réinitialisation : le client renvoie les valeurs de `Config/Balance`, ce qui
	évite d'inventer un remote de reset dont le serveur devrait se méfier.
]]
function TuningController.defaultValue(path: string): number?
	local tunable = Debug.Tunables[path]
	if tunable == nil then
		return nil
	end
	if tunable.target == "Switch" then
		return tunable.default or 0
	end

	local container, key = TableUtil.resolvePath(BalanceConfig :: any, path)
	if container == nil then
		return nil
	end
	local value = container[key]
	return if type(value) == "number" then value else nil
end

function TuningController.request(path: string, value: number)
	Net.Client.fire(Definitions.DebugSetTuning, { path = path, value = value })
end

function TuningController.isAvailable(): boolean
	return Net.Client.available(Definitions.DebugSetTuning)
end

local function applyLocally(path: string, value: number)
	local tunable = Debug.Tunables[path]
	if tunable == nil then
		Log.warn(SCOPE, `réglage reçu pour un chemin inconnu : {path}`)
		return
	end

	if tunable.target == "Switch" then
		switchValues[path] = value
	else
		local container, key = TableUtil.resolvePath(live :: any, path)
		if container == nil then
			Log.warn(SCOPE, `chemin irrésolu côté client : {path}`)
			return
		end
		container[key] = value
	end

	for _, listener in listeners do
		task.spawn(listener, path, value)
	end
end

function TuningController.Init()
	for path, tunable in Debug.Tunables do
		if tunable.target == "Switch" then
			switchValues[path] = tunable.default or 0
		end
	end

	Net.Client.on(Definitions.DebugTuningSync, function(payload)
		applyLocally(payload.path, payload.value)
	end)
end

return TuningController
