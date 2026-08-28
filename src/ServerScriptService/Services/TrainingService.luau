--!strict
--[[
	Terrain d'entraînement : la plateforme, les mannequins, leur affichage.

	Un mannequin est un combattant à part entière dans le registre de
	`StateService` : même état, même chemin de dégâts, mêmes règles. C'est ce qui
	permettra en tranche 1.3 de lui faire tenir une garde et en 1.4 de lui faire
	parer, sans écrire un second système de combat pour les cibles d'entraînement.

	Il n'a délibérément pas de `Humanoid`. Rien ne le fait marcher, et fabriquer un
	rig R15 valide pour une cible immobile aurait coûté du code sans rien apporter :
	ses points de vie vivent dans son enregistrement de combattant, et son panneau
	les affiche.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(ReplicatedStorage.Shared.Log)
local StateService = require(script.Parent.StateService)
local Training = require(ReplicatedStorage.Config.Training)
local Trove = require(ReplicatedStorage.Packages.Trove)

local SCOPE = "TrainingService"

local TrainingService = {}

TrainingService.Dependencies = { "StateService" }

type DummyView = {
	combatant: StateService.Combatant,
	health: TextLabel,
	verdict: TextLabel,
	resetAt: number?,
	guarding: boolean,
}

local trove = Trove.new()
local dummies: { DummyView } = {}

local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Size = size
	instance.Position = position
	instance.Color = color
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	return instance
end

local function buildBillboard(parent: BasePart): (TextLabel, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Training.BillboardHeight, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = parent

	local health = Instance.new("TextLabel")
	health.BackgroundTransparency = 1
	health.Size = UDim2.new(1, 0, 0.5, 0)
	health.Font = Enum.Font.Code
	health.TextSize = 16
	health.TextColor3 = Color3.fromRGB(236, 236, 240)
	health.TextStrokeTransparency = 0.4
	health.Parent = billboard

	local verdict = Instance.new("TextLabel")
	verdict.BackgroundTransparency = 1
	verdict.Position = UDim2.fromScale(0, 0.5)
	verdict.Size = UDim2.new(1, 0, 0.5, 0)
	verdict.Font = Enum.Font.Code
	verdict.TextSize = 14
	verdict.TextColor3 = Color3.fromRGB(150, 150, 162)
	verdict.TextStrokeTransparency = 0.4
	verdict.Text = "—"
	verdict.Parent = billboard

	return health, verdict
end

local function spawnDummy(spec: Training.DummySpec, parent: Folder): DummyView
	local origin = Training.Ground.Center + spec.offset

	local model = Instance.new("Model")
	model.Name = spec.name

	-- Le nom `HumanoidRootPart` n'est pas décoratif : c'est la pièce que le
	-- rembobinage échantillonne et celle dont l'orientation sert de référence,
	-- exactement comme pour un joueur.
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), origin, Color3.fromRGB(196, 84, 84))
	root.Parent = model
	model.PrimaryPart = root

	local head = part(
		"Head",
		Vector3.new(1.4, 1.4, 1.4),
		origin + Vector3.new(0, 1.8, 0),
		Color3.fromRGB(224, 196, 168)
	)
	head.Parent = model

	local base = part(
		"Base",
		Vector3.new(3, 0.4, 3),
		origin - Vector3.new(0, 1.2, 0),
		Color3.fromRGB(48, 50, 56)
	)
	base.Parent = model

	model.Parent = parent

	local health, verdict = buildBillboard(root)
	local combatant = StateService.register(model, root, nil, nil)

	return {
		combatant = combatant,
		health = health,
		verdict = verdict,
		resetAt = nil,
		guarding = spec.guarding == true,
	}
end

--[[
	Maintient la garde d'un mannequin qui doit la tenir.

	On ne remonte la garde que depuis `Idle`, jamais en forçant l'état : le
	mannequin subit donc réellement le guard break, reste étourdi ses 1,6 s, puis
	se remet en garde quand la machine à états le lui permet. C'est exactement la
	boucle qu'on veut pouvoir observer en frappant — jauge qui descend, rupture,
	ouverture, retour.
]]
local function holdGuard(view: DummyView)
	local combatant = view.combatant
	if combatant.state.name ~= "Idle" or combatant.health <= 0 then
		return
	end
	StateService.requestTransition(combatant, "Blocking", workspace:GetServerTimeNow())
end

local function refresh(view: DummyView, now: number)
	local combatant = view.combatant

	if view.guarding then
		holdGuard(view)
	end

	-- La jauge de garde n'est affichée que sur les cibles qui gardent : sur les
	-- autres elle resterait au maximum et n'apprendrait rien.
	if view.guarding then
		view.health.Text = string.format(
			"%d / %d   ▌%d",
			math.floor(combatant.health),
			combatant.maxHealth,
			math.floor(combatant.guard.current)
		)
	else
		view.health.Text =
			string.format("%d / %d", math.floor(combatant.health), combatant.maxHealth)
	end
	view.health.TextColor3 = if combatant.health <= 0
		then Color3.fromRGB(232, 84, 84)
		else Color3.fromRGB(236, 236, 240)

	-- Le panneau montre ce que le SERVEUR a décidé, jamais ce que le client a
	-- cru : c'est la seule façon de distinguer un vrai refus d'un problème
	-- d'affichage pendant les essais.
	local verdict = combatant.lastVerdict
	if verdict then
		view.verdict.Text = if combatant.lastDamage > 0
			then string.format(
				"%s −%d  ·  %s",
				verdict,
				math.floor(combatant.lastDamage),
				combatant.state.name
			)
			else string.format("%s  ·  %s", verdict, combatant.state.name)
	else
		view.verdict.Text = combatant.state.name
	end

	-- Remise à zéro autonome : sans elle, la première chaîne de 4 coups met le
	-- mannequin au sol et il faut relancer la partie pour continuer à tester.
	if combatant.health <= 0 then
		if view.resetAt == nil then
			view.resetAt = now + Training.RespawnDelay
		elseif now >= (view.resetAt :: number) then
			view.resetAt = nil
			StateService.reset(combatant)
			view.verdict.Text = "réinitialisé"
		end
	else
		view.resetAt = nil
	end
end

function TrainingService.Init()
	local container = Instance.new("Folder")
	container.Name = "TrainingGround"
	trove:Add(container)

	local ground = Training.Ground
	local floor = part(
		"Floor",
		ground.Size,
		ground.Center - Vector3.new(0, ground.Size.Y / 2, 0),
		ground.Color
	)
	floor.Parent = container

	local obstacle = Training.Obstacle
	local wall = part(
		"Obstacle",
		obstacle.size,
		ground.Center + obstacle.offset,
		Color3.fromRGB(96, 100, 108)
	)
	wall.Parent = container

	for _, spec in Training.Dummies do
		table.insert(dummies, spawnDummy(spec, container))
	end
	table.insert(dummies, spawnDummy(obstacle.dummy, container))

	container.Parent = workspace
	Log.info(SCOPE, `terrain d'entraînement monté avec {#dummies} mannequins`)
end

function TrainingService.Start()
	trove:Connect(RunService.Heartbeat, function()
		local now = workspace:GetServerTimeNow()
		for _, view in dummies do
			refresh(view, now)
		end
	end)
end

return TrainingService
