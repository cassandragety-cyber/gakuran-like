--!strict
--[[
	Point d'entrée unique de l'animation : `play(clé)` / `stop(clé)`.

	Le reste du client ne sait pas — et ne doit pas savoir — si une clé est
	servie par un asset Roblox ou par la pose procédurale de repli. C'est
	exactement la promesse d'ADR-009 : brancher une vraie animation consiste à
	remplacer un `0` par un asset id dans `Config/Animations`, sans toucher à une
	ligne de code de combat. Ce module est l'endroit où cette indirection est
	payée, une fois.

	La durée est REDRESSÉE : un asset qui dure 0,62 s pour une clé dont le
	contrat annonce 0,45 s est joué à 1,38× plutôt que laissé tel quel. Sans ce
	redressement, l'impact visuel dériverait de l'impact réel dès la première
	animation livrée par un animateur, et c'est précisément le « hit fantôme »
	que le brief interdit. `ConfigValidator` vérifie le contrat au boot, celui-ci
	le fait respecter à la lecture.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Config.Animations)
local Log = require(ReplicatedStorage.Shared.Log)
local Procedural = require(script.Parent.Animation.Procedural)

local SCOPE = "AnimationController"

local AnimationController = {}

type Entry = {
	track: AnimationTrack,
	definition: Animations.AnimationDef,
}

--[[
	Table explicite plutôt que `Enum.AnimationPriority[nom]`. L'indexation
	dynamique d'un enum n'est pas vérifiable : une priorité mal orthographiée dans
	`Config/Animations` lèverait une exception à la frame du premier coup, en
	production, au lieu d'être une erreur de type ici.
]]
local PRIORITY: { [Animations.Priority]: Enum.AnimationPriority } = {
	Core = Enum.AnimationPriority.Core,
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
	Action3 = Enum.AnimationPriority.Action3,
	Action4 = Enum.AnimationPriority.Action4,
}

local tracks: { [string]: Entry } = {}
local missing: { [string]: boolean } = {}

local function definitionFor(key: string): Animations.AnimationDef?
	local byKey = (Animations :: any) :: { [string]: Animations.AnimationDef }
	return byKey[key]
end

--[[
	Charge les assets réels sur l'Animator du personnage courant.

	Les clés à `id = 0` ne produisent aucun `AnimationTrack` : elles passeront par
	la pose procédurale. On ne fabrique donc jamais de piste vide, qui se
	jouerait sans rien afficher et masquerait l'absence d'asset.
]]
local function loadTracks(target: Animator)
	table.clear(tracks)

	local assets: { Instance } = {}
	local byKey = (Animations :: any) :: { [string]: Animations.AnimationDef }

	for key, definition in byKey do
		if definition.id <= 0 then
			continue
		end

		local asset = Instance.new("Animation")
		asset.Name = key
		asset.AnimationId = `rbxassetid://{definition.id}`

		local track = target:LoadAnimation(asset)
		track.Priority = PRIORITY[definition.priority]
		track.Looped = definition.looped

		tracks[key] = { track = track, definition = definition }
		table.insert(assets, asset)
	end

	if #assets == 0 then
		return
	end

	--[[
		Préchargement exigé par le brief (§6) : un premier coup qui attend le
		téléchargement de son animation se joue en retard, donc à côté de sa
		hitbox. On précharge en tâche de fond — bloquer l'entrée en jeu pour des
		assets d'animation coûterait plus cher que le défaut qu'on corrige.
	]]
	task.spawn(function()
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
		if not ok then
			Log.warn(SCOPE, `préchargement des animations incomplet : {err}`)
		end
	end)
end

function AnimationController.bindCharacter(character: Model)
	Procedural.bindCharacter(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local found = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil

	if found then
		loadTracks(found)
	else
		-- Sans Animator, seules les poses procédurales restent disponibles. Elles
		-- écrivent sur les Motor6D directement et n'en dépendent pas.
		table.clear(tracks)
		Log.warn(SCOPE, "aucun Animator sur le personnage, assets d'animation indisponibles")
	end
end

--[[
	Joue une clé d'animation. Retourne faux si la clé n'est servie ni par un asset
	ni par une pose — un cas que `ConfigValidator` interdit au boot, et qu'on
	journalise **une seule fois par clé** pour ne pas noyer l'Output à 60 fps si
	la validation venait à être contournée.
]]
function AnimationController.play(key: string): boolean
	local definition = definitionFor(key)
	if definition == nil then
		if not missing[key] then
			missing[key] = true
			Log.warn(SCOPE, `clé d'animation inconnue : {key}`)
		end
		return false
	end

	local entry = tracks[key]
	if entry then
		local track = entry.track
		-- `Length` vaut 0 tant que l'asset n'est pas chargé : on joue alors à
		-- vitesse nominale plutôt que de diviser par zéro, et le redressement
		-- prendra effet à la lecture suivante.
		local speed = if track.Length > 0 then track.Length / definition.targetDuration else 1
		track:Play()
		track:AdjustSpeed(speed)
		return true
	end

	if Procedural.play(key, definition.targetDuration, definition.looped) then
		return true
	end

	if not missing[key] then
		missing[key] = true
		Log.warn(SCOPE, `clé {key} sans asset ni pose procédurale`)
	end
	return false
end

--[[
	Cette clé est-elle en cours de lecture ?

	Sert à arbitrer entre deux lectures qui décrivent le même événement sous deux
	angles — `GuardBreak` et `Stun` en sont le cas type. Les mélanger produirait
	une silhouette moyenne qui ne ressemble à aucune des deux.
]]
function AnimationController.isPlaying(key: string): boolean
	local entry = tracks[key]
	if entry then
		return entry.track.IsPlaying
	end
	return Procedural.isPlaying(key)
end

function AnimationController.stop(key: string)
	local entry = tracks[key]
	if entry then
		entry.track:Stop()
		return
	end
	Procedural.stop(key)
end

--[[
	Arrête tout. Utilisé lors d'une transition qui invalide la lecture en cours :
	une garde qui casse ne doit pas laisser la pose de garde à l'écran pendant
	l'étourdissement.
]]
function AnimationController.stopAll()
	for key in tracks do
		AnimationController.stop(key)
	end
	local byKey = (Animations :: any) :: { [string]: Animations.AnimationDef }
	for key in byKey do
		Procedural.stop(key)
	end
end

--[[
	Lecture pour le panneau de debug : combien de poses procédurales tournent, et
	combien d'assets réels sont chargés. C'est ce qui permet de vérifier d'un coup
	d'œil qu'une animation livrée a bien remplacé son repli.
]]
function AnimationController.counts(): (number, number)
	local loaded = 0
	for _ in tracks do
		loaded += 1
	end
	return loaded, Procedural.activeCount()
end

--[[
	État du moteur de pose, relayé tel quel.

	Le panneau lit ce module et pas `Procedural`, qui vit dans un sous-dossier :
	`AnimationController` reste le point d'entrée unique de l'animation, y compris
	pour le diagnostic.
]]
function AnimationController.rigStatus(): (string, number, number, boolean)
	return Procedural.diagnose()
end

--[[
	Mesure au point d'écriture, relayée depuis `Animation/Probe`.

	`writeStatus` alimente le panneau en continu ; `capture` journalise une ligne
	par frame pendant quelques secondes, à déclencher depuis la barre de commande
	du client :

	    require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.AnimationController).capture(1)

	Les deux répondent à la question que cinq allers-retours de recette n'ont pas
	su trancher : écrit-on réellement sur une jointure, avec quelle valeur, et
	qu'en reste-t-il à la frame suivante.
]]
function AnimationController.writeStatus(): (number, string, boolean)
	return Procedural.writeStatus()
end

function AnimationController.capture(seconds: number?)
	Procedural.capture(seconds or 1)
end

--[[
	Attend l'`Humanoid`, puis lie.

	On n'attend QUE l'`Humanoid`, et uniquement parce qu'il porte le type de rig
	et l'`Animator`. On n'attend surtout pas les jointures : elles vivent dans les
	membres, qui arrivent après, et aucune pièce du personnage ne permet de
	conclure qu'elles sont toutes là. La version précédente attendait
	`HumanoidRootPart` en le croyant dernier arrivé — il est parmi les premiers —
	et recensait donc régulièrement zéro `Motor6D`, pour toute la vie du
	personnage.

	C'est `Procedural.bindCharacter` qui règle la course, en réindexant à chaque
	jointure qui apparaît plutôt qu'en pariant sur un instant.
]]
local function bindWhenReady(character: Model)
	task.spawn(function()
		if character:WaitForChild("Humanoid", 10) == nil then
			Log.warn(SCOPE, "personnage sans Humanoid après 10 s, animations inactives")
			return
		end
		-- Le personnage a pu être remplacé pendant l'attente (mort rapide,
		-- respawn) : lier un rig déjà détaché écraserait le rig courant.
		if character.Parent == nil then
			return
		end
		AnimationController.bindCharacter(character)
	end)
end

function AnimationController.Start()
	Procedural.Start()

	local player = Players.LocalPlayer
	local existing = player.Character
	if existing then
		bindWhenReady(existing)
	end
	player.CharacterAdded:Connect(bindWhenReady)
end

return AnimationController
