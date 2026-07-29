--!strict
--[[
	Registre des sessions joueur.

	Un seul endroit sait quand une session commence et se termine ; les autres
	services s'y abonnent au lieu de connecter chacun leur PlayerRemoving. Sans
	ça, l'ordre de nettoyage entre services devient implicite et on finit avec
	un service qui lit les données d'un joueur qu'un autre vient d'effacer.

	Ce service ne persiste rien : la persistance arrive en Phase 2 avec
	DataService, qui s'abonnera ici.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Clock = require(ReplicatedStorage.Shared.Clock)
local Log = require(ReplicatedStorage.Shared.Log)

local SCOPE = "SessionService"

export type Session = {
	player: Player,
	startedAt: number,
}

local SessionService = {}

local sessions: { [Player]: Session } = {}
local startedCallbacks: { (session: Session) -> () } = {}
local endedCallbacks: { (player: Player) -> () } = {}

local function begin(player: Player)
	if sessions[player] then
		return
	end

	local session: Session = { player = player, startedAt = Clock.now() }
	sessions[player] = session
	Log.debug(SCOPE, `session ouverte pour {player.Name}`)

	for _, callback in startedCallbacks do
		-- Un abonné qui échoue ne doit pas empêcher les suivants d'être notifiés.
		task.spawn(callback, session)
	end
end

local function finish(player: Player)
	if not sessions[player] then
		return
	end

	sessions[player] = nil
	for _, callback in endedCallbacks do
		task.spawn(callback, player)
	end
	Log.debug(SCOPE, `session fermée pour {player.Name}`)
end

function SessionService.onStarted(callback: (session: Session) -> ())
	table.insert(startedCallbacks, callback)
end

function SessionService.onEnded(callback: (player: Player) -> ())
	table.insert(endedCallbacks, callback)
end

function SessionService.get(player: Player): Session?
	return sessions[player]
end

function SessionService.durationOf(player: Player): number?
	local session = sessions[player]
	return if session then Clock.now() - session.startedAt else nil
end

function SessionService.count(): number
	local total = 0
	for _ in sessions do
		total += 1
	end
	return total
end

function SessionService.Init()
	Players.PlayerAdded:Connect(begin)
	Players.PlayerRemoving:Connect(finish)

	-- Un joueur peut avoir rejoint pendant le chargement des scripts serveur ;
	-- sans ce rattrapage, il n'aurait jamais de session.
	for _, player in Players:GetPlayers() do
		begin(player)
	end
end

return SessionService
