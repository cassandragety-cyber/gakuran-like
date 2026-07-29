--!strict
--[[
	Chaîne de contrôle appliquée à TOUT paquet client -> serveur, avant qu'un
	service ne voie quoi que ce soit : rate-limit, puis parsing strict.

	Le compteur d'infractions est volontairement commun aux dépassements de
	cadence et aux payloads malformés : la latence peut produire des rafales
	légitimes, mais elle ne produit jamais un payload de forme invalide. Les
	deux ensemble dessinent un profil bien plus net qu'un seuil sur un seul.

	Ce module ne s'active que côté serveur ; il est require par Net/init des deux
	côtés, d'où les gardes sur RunService.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Clock = require(script.Parent.Parent.Shared.Clock)
local Definitions = require(script.Parent.Definitions)
local Log = require(script.Parent.Parent.Shared.Log)
local RateLimits = require(script.Parent.Parent.Config.RateLimits)
local TokenBucket = require(script.Parent.Parent.Shared.TokenBucket)

local SCOPE = "Net"

local Middleware = {}

local buckets: { [Player]: { [string]: TokenBucket.Bucket } } = {}
local violations: { [Player]: number } = {}

local function limitFor(key: string): RateLimits.Limit
	local limit = (RateLimits :: any)[key]
	if type(limit) == "table" and type(limit.capacity) == "number" then
		return limit :: RateLimits.Limit
	end
	return RateLimits.Default
end

--[[
	Enregistre une infraction et sanctionne au seuil. On ne kick pas au premier
	écart : un joueur qui reprend le jeu après un freeze système peut envoyer
	une petite rafale légitime.
]]
function Middleware.flag(player: Player, reason: string)
	local count = (violations[player] or 0) + 1
	violations[player] = count

	Log.warn(
		SCOPE,
		`infraction {count}/{RateLimits.ViolationsBeforeKick} — {player.Name} : {reason}`
	)

	if count >= RateLimits.ViolationsBeforeKick then
		Log.warn(SCOPE, `kick de {player.Name} après {count} infractions`)
		player:Kick(RateLimits.KickMessage)
	end
end

function Middleware.violationCount(player: Player): number
	return violations[player] or 0
end

--[[
	Retourne le payload typé, ou nil si le paquet doit être ignoré. Un nil est
	toujours final : l'appelant ne fait rien d'autre que revenir.
]]
function Middleware.accept<T>(player: Player, definition: Definitions.Definition<T>, raw: unknown): T?
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local limit = limitFor(definition.rateLimit)
	local now = Clock.now()

	local bucket = perPlayer[definition.rateLimit]
	if not bucket then
		bucket = TokenBucket.new(limit.capacity, limit.refillPerSecond, now)
		perPlayer[definition.rateLimit] = bucket
	end

	if not TokenBucket.tryConsume(bucket, now, 1) then
		Middleware.flag(player, `cadence dépassée sur {definition.id}`)
		return nil
	end

	local payload = definition.parse(raw)
	if payload == nil then
		Middleware.flag(player, `payload malformé sur {definition.id}`)
		return nil
	end

	return payload
end

function Middleware.start()
	if not RunService:IsServer() then
		return
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
		violations[player] = nil
	end)
end

return Middleware
