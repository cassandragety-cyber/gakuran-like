--!strict
--[[
	Point d'entrée client.

	Le WaitForChild initial est une garantie explicite : les modules partagés
	sont ensuite adressés par chemin direct (ReplicatedStorage.Shared.X), ce qui
	permet à luau-lsp de conserver l'inférence de types — un `WaitForChild` à
	chaque require rendrait tout `any` et ferait perdre l'intérêt du --!strict.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Config")
ReplicatedStorage:WaitForChild("Net")

local Loader = require(ReplicatedStorage.Shared.Loader)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Profiler = require(ReplicatedStorage.Shared.Profiler)

local SCOPE = "Boot/Client"
local startedAt = os.clock()

Profiler.setEnabled(RunService:IsStudio())

Net.Client.awaitReady()
Loader.load(script.Controllers, SCOPE)

Log.info(
	SCOPE,
	`OK — client prêt en {string.format("%.1f", (os.clock() - startedAt) * 1000)} ms`
)
