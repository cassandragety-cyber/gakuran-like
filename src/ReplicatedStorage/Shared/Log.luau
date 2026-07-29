--!strict
--[[
	Logging à niveaux, préfixé par module.

	En production le niveau minimum est Info : les logs Debug de combat sont
	trop verbeux pour un serveur à 30 joueurs et coûtent de la bande passante
	console. En Studio tout est visible.
]]

local RunService = game:GetService("RunService")

export type Level = "Debug" | "Info" | "Warn" | "Error"

local RANK: { [string]: number } = {
	Debug = 10,
	Info = 20,
	Warn = 30,
	Error = 40,
}

local minimumRank = if RunService:IsStudio() then RANK.Debug else RANK.Info

local Log = {}

function Log.setLevel(level: Level)
	minimumRank = RANK[level]
end

function Log.debug(scope: string, message: string)
	if minimumRank <= RANK.Debug then
		print(`[{scope}] {message}`)
	end
end

function Log.info(scope: string, message: string)
	if minimumRank <= RANK.Info then
		print(`[{scope}] {message}`)
	end
end

function Log.warn(scope: string, message: string)
	if minimumRank <= RANK.Warn then
		warn(`[{scope}] {message}`)
	end
end

--[[
	Erreur non fatale : on veut la stack dans les logs du serveur sans tuer la
	session du joueur. Les erreurs fatales utilisent `error()` directement.
]]
function Log.error(scope: string, message: string)
	warn(`[{scope}] ERREUR : {message}\n{debug.traceback("", 2)}`)
end

return Log
