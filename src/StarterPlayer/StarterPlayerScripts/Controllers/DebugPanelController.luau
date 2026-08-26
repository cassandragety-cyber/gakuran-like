--!strict
--[[
	Le panneau F2.

	Objectif : passer des heures sur le mannequin d'entraînement sans jamais
	éditer un fichier ni relancer. Deux moitiés — lecture de l'état à gauche,
	réglage à droite — décrites dans docs/PHASE1.md §4.

	Les lignes sont déclarées en données, pas en code : ajouter un indicateur
	quand une tranche ultérieure produit la valeur correspondante est une entrée
	dans `ROWS`. C'est aussi pourquoi le panneau n'affiche aujourd'hui que ce qui
	existe réellement — l'écart de prédiction et le coût des hitbox apparaîtront
	avec les tranches qui les produisent, pas comme des cases vides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Clock)
local DebugConfig = require(ReplicatedStorage.Config.Debug)
local DevAccess = require(ReplicatedStorage.Shared.DevAccess)
local InputController = require(script.Parent.InputController)
local Log = require(ReplicatedStorage.Shared.Log)
local Panel = require(script.Parent.Parent.UI.Debug.Panel)
local Readouts = require(script.Parent.Parent.UI.Debug.Readouts)
local Row = require(script.Parent.Parent.UI.Debug.Row)
local Slider = require(script.Parent.Parent.UI.Debug.Slider)
local TuningController = require(script.Parent.TuningController)

local SCOPE = "DebugPanelController"

local DebugPanelController = {}

local panel: Panel.Panel? = nil
local rows: { [string]: Row.Row } = {}
local sliders: { [string]: Slider.Slider } = {}

DebugPanelController.Dependencies = {
	"InputController",
	"StateMirrorController",
	"TuningController",
	"DiagnosticsController",
}

local function refresh()
	local now = Clock.now()
	for _, entry in Readouts.rows do
		local row = rows[`{entry.section}/{entry.label}`]
		if row then
			local text, color = entry.read(now)
			row.setValue(text, color)
		end
	end
end

local function buildReadouts(handle: Panel.Panel)
	local sections: { [string]: Frame } = {}
	for _, entry in Readouts.rows do
		local container = sections[entry.section]
		if not container then
			container = handle.section(entry.section)
			sections[entry.section] = container
		end
		rows[`{entry.section}/{entry.label}`] = Row.create(container, entry.label)
	end
end

local function buildTuning(handle: Panel.Panel)
	local container = handle.section("Réglages")

	-- Tri alphabétique : l'ordre d'itération d'une table Luau n'est pas stable, et
	-- un panneau dont les curseurs changent de place entre deux sessions est
	-- pénible à utiliser à la souris.
	local paths: { string } = {}
	for path in DebugConfig.Tunables do
		table.insert(paths, path)
	end
	table.sort(paths)

	for _, path in paths do
		local tunable = DebugConfig.Tunables[path]
		local current = TuningController.currentValue(path)
		if current == nil then
			continue
		end

		sliders[path] = Slider.create(container, {
			label = tunable.label,
			min = tunable.min,
			max = tunable.max,
			step = tunable.step,
			value = current,
			onChanged = function(value: number)
				TuningController.request(path, value)
			end,
		})
	end

	handle.addButton("Réinitialiser l'équilibrage", function()
		for _, path in paths do
			local default = TuningController.defaultValue(path)
			if default ~= nil then
				TuningController.request(path, default)
			end
		end
	end)
end

function DebugPanelController.Init()
	if not DevAccess.isEnabled() then
		return
	end

	-- Le serveur est seul juge : si le remote de réglage n'existe pas, le panneau
	-- resterait un affichage sans effet. Autant ne pas le construire.
	if not TuningController.isAvailable() then
		Log.info(SCOPE, "réglage à chaud indisponible sur ce serveur, panneau désactivé")
		return
	end

	local handle = Panel.create(DebugConfig.Panel.Width)
	panel = handle
	buildReadouts(handle)
	buildTuning(handle)

	InputController.onAction("ToggleDebug", function(phase)
		if phase == "Begin" then
			handle.setVisible(not handle.isVisible())
		end
	end)

	-- Le serveur peut aligner une valeur sur le pas du curseur : on rejoue sa
	-- réponse dans l'interface pour ne jamais afficher un réglage qui n'existe pas.
	TuningController.onChanged(function(path: string, value: number)
		local slider = sliders[path]
		if slider then
			slider.setValue(value)
		end
	end)
end

function DebugPanelController.Start()
	if panel == nil then
		return
	end

	local handle = panel :: Panel.Panel
	local interval = 1 / DebugConfig.Panel.RefreshRate
	local elapsed = interval

	RunService.Heartbeat:Connect(function(deltaTime: number)
		-- Rien n'est recalculé quand le panneau est fermé : il ne coûte alors que
		-- ce test, ce qui permet de le laisser chargé en permanence.
		if not handle.isVisible() then
			return
		end
		elapsed += deltaTime
		if elapsed < interval then
			return
		end
		elapsed = 0
		refresh()
	end)
end

return DebugPanelController
