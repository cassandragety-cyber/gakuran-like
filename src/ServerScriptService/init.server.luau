--!strict
--[[
	Point d'entrée serveur.

	Ordre non négociable :
	  1. valider la configuration — inutile de démarrer un serveur dont
	     l'équilibrage est incohérent, il produirait des bugs inexplicables ;
	  2. publier les remotes — les services enregistrent leurs handlers dans
	     leur Init, les remotes doivent donc déjà exister ;
	  3. charger les services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigValidator = require(script.Systems.ConfigValidator)
local Loader = require(ReplicatedStorage.Shared.Loader)
local Log = require(ReplicatedStorage.Shared.Log)
local Net = require(ReplicatedStorage.Net)
local Profiler = require(ReplicatedStorage.Shared.Profiler)
local Result = require(ReplicatedStorage.Shared.Result)

local SCOPE = "Boot/Server"
local startedAt = os.clock()

--[[
	Message actionnable plutôt qu'une erreur de require cryptique : à partir de la
	Phase 1, le nettoyage des connexions de personnage passe par Trove (ADR-008),
	donc les dépendances Wally deviennent nécessaires.
]]
local packages = ReplicatedStorage:FindFirstChild("Packages")
assert(
	packages ~= nil and packages:FindFirstChild("Trove") ~= nil,
	"[Boot/Server] dépendances absentes : lancez `wally install` puis resynchronisez Rojo"
)

Result.expect(ConfigValidator.validate(), "[Boot/Server] configuration invalide")
Log.info(SCOPE, "configuration validée")

-- Le profiler reste éteint en production : sa fenêtre glissante coûte une
-- allocation par label et ses mesures n'intéressent que le développement.
Profiler.setEnabled(RunService:IsStudio())

Net.initServer()
Loader.load(script.Services, SCOPE)

Log.info(
	SCOPE,
	`OK — serveur prêt en {string.format("%.1f", (os.clock() - startedAt) * 1000)} ms`
)
