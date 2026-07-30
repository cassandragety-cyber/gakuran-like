--!strict
--[[
	Cycle de vie du personnage.

	Un seul endroit sait qu'un personnage apparaît ou disparaît, et applique les
	propriétés du `Humanoid` depuis l'équilibrage. Les autres services s'abonnent
	au lieu de brancher chacun leur `CharacterAdded`, pour la même raison que
	SessionService existe : sans point unique, l'ordre entre « le personnage
	existe » et « son état de combat existe » devient implicite.

	Toute connexion liée à un personnage vit dans un Trove détruit avec lui : un
	joueur qui meurt vingt fois ne doit pas laisser vingt connexions derrière.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Log)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TuningService = require(script.Parent.TuningService)

local SCOPE = "CharacterService"

export type CharacterRecord = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	trove: any,
}

local CharacterService = {}

CharacterService.Dependencies = { "TuningService" }

local records: { [Player]: CharacterRecord } = {}
local watched: { [Player]: boolean } = {}
local addedListeners: { (record: CharacterRecord) -> () } = {}
local removingListeners: { (player: Player) -> () } = {}

function CharacterService.onAdded(listener: (record: CharacterRecord) -> ())
	table.insert(addedListeners, listener)
end

function CharacterService.onRemoving(listener: (player: Player) -> ())
	table.insert(removingListeners, listener)
end

function CharacterService.get(player: Player): CharacterRecord?
	return records[player]
end

--[[
	Personnages actuellement vivants. Retourne la table interne : les appelants
	itèrent, ils n'écrivent pas. Copier à chaque frame pour se protéger d'un
	mésusage coûterait une allocation par frame et par service.
]]
function CharacterService.all(): { [Player]: CharacterRecord }
	return records
end

local function release(player: Player)
	local record = records[player]
	if not record then
		return
	end

	records[player] = nil
	record.trove:Destroy()

	for _, listener in removingListeners do
		task.spawn(listener, player)
	end
end

local function adopt(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if humanoid == nil or root == nil then
		Log.error(SCOPE, `personnage de {player.Name} sans Humanoid ni HumanoidRootPart`)
		return
	end

	local balance = TuningService.balance()
	humanoid.MaxHealth = balance.Character.MaxHealth
	humanoid.Health = balance.Character.MaxHealth
	humanoid.WalkSpeed = balance.Character.WalkSpeed
	humanoid.JumpPower = balance.Character.JumpPower
	humanoid.UseJumpPower = true
	-- Le ragdoll de la tranche 1.6 pilotera lui-même l'état ; d'ici là on veut
	-- simplement qu'un knockdown ne soit pas contredit par la physique par défaut.
	humanoid.BreakJointsOnDeath = false

	local trove = Trove.new()
	local record: CharacterRecord = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		trove = trove,
	}
	records[player] = record

	trove:Connect(humanoid.Died, function()
		release(player)
	end)
	trove:Connect(character.AncestryChanged, function(_, parent)
		if parent == nil then
			release(player)
		end
	end)

	for _, listener in addedListeners do
		task.spawn(listener, record)
	end
	Log.debug(SCOPE, `personnage adopté pour {player.Name}`)
end

local function watch(player: Player)
	if watched[player] then
		return
	end
	watched[player] = true

	player.CharacterAdded:Connect(function(character: Model)
		adopt(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		release(player)
	end)

	local existing = player.Character
	if existing then
		adopt(player, existing)
	end
end

function CharacterService.Init()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		watched[player] = nil
		release(player)
	end)
end

--[[
	Le rattrapage des joueurs déjà connectés se fait dans Start, pas dans Init.

	Adopter un personnage émet `onAdded`, et les abonnés — StateService en
	premier — ne s'inscrivent que pendant LEUR Init. Rattraper trop tôt
	produirait un joueur avec un personnage mais sans état de combat, un bug qui
	n'apparaît qu'au premier boot où quelqu'un est déjà là. C'est précisément ce
	que le découpage Init/Start du Loader existe pour éviter.
]]
function CharacterService.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CharacterService
