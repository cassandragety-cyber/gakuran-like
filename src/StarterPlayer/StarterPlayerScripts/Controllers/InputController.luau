--!strict
--[[
	Traduction des entrées matérielles en actions nommées.

	Seul module du projet qui connaît `UserInputService`. Le reste du code
	s'abonne à `"Attack"` ou `"Block"` sans savoir quelle touche c'est, ce qui
	rendra les keybinds personnalisables (brief §5.4) en écrasant simplement les
	tables de `Config/Input` avec les préférences du profil.

	Les boutons tactiles arriveront avec l'interface de combat (tranche 1.2) :
	ils appelleront `InputController.fire` et emprunteront donc exactement le même
	chemin que le clavier, sans code de combat spécifique au mobile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Input = require(ReplicatedStorage.Config.Input)

export type Phase = "Begin" | "End"

type Listener = (phase: Phase) -> ()

local InputController = {}

local listeners: { [string]: { Listener } } = {}
local keyToAction: { [Enum.KeyCode]: string } = {}
local buttonToAction: { [Enum.UserInputType]: string } = {}
local lastAction: string? = nil
local lastActionAt = 0
local lastListenerCount = 0

function InputController.onAction(action: string, listener: Listener)
	local bucket = listeners[action]
	if bucket == nil then
		bucket = {}
		listeners[action] = bucket
	end
	table.insert(bucket, listener)
end

--[[
	Déclenche une action comme si elle venait d'une touche. C'est le point
	d'entrée des boutons tactiles et des tests : on ne simule jamais un
	`InputObject`, on entre par le même endroit que tout le monde.
]]
function InputController.fire(action: string, phase: Phase)
	local bucket = listeners[action]

	lastAction = `{action} ({phase})`
	lastActionAt = os.clock()
	--[[
		Le nombre d'abonnés est retenu avec l'action. Sans lui, le panneau affiche
		« l'entrée est arrivée » alors qu'elle n'a été distribuée à personne — les
		deux situations se ressemblent à l'écran et ne se corrigent pas au même
		endroit.
	]]
	lastListenerCount = if bucket then #bucket else 0

	if bucket == nil then
		return
	end
	for _, listener in bucket do
		-- Un abonné qui échoue ne doit pas empêcher les suivants de recevoir
		-- l'action : sur une touche de combat, ça se verrait immédiatement.
		task.spawn(listener, phase)
	end
end

--[[
	Dernière action déclenchée et son ancienneté. Affiché par le panneau de debug :
	c'est ce qui permet de vérifier un keybind avant que l'action ait un
	consommateur.
]]
function InputController.lastFired(): (string?, number, number)
	return lastAction, os.clock() - lastActionAt, lastListenerCount
end

function InputController.isHeldAction(action: string): boolean
	return Input.Held[action] == true
end

local function resolve(input: InputObject): string?
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return keyToAction[input.KeyCode]
	end
	-- Les boutons de gamepad arrivent avec un KeyCode, pas un UserInputType.
	local gamepadAction = keyToAction[input.KeyCode]
	if gamepadAction then
		return gamepadAction
	end
	return buttonToAction[input.UserInputType]
end

function InputController.Init()
	for action, key in Input.Keys do
		keyToAction[key] = action
	end
	for action, key in Input.Gamepad do
		keyToAction[key] = action
	end
	for action, button in Input.MouseButtons do
		buttonToAction[button] = action
	end
end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- `processed` est vrai quand l'entrée a déjà servi à l'interface (saisie
		-- dans un champ de texte, clic sur un bouton). L'ignorer ferait attaquer
		-- le joueur en tapant une valeur dans le panneau de debug.
		if processed then
			return
		end
		local action = resolve(input)
		if action then
			InputController.fire(action, "Begin")
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		local action = resolve(input)
		if action == nil then
			return
		end

		-- Le relâchement d'une action MAINTENUE est délivré même si l'entrée a été
		-- consommée par l'interface : sans ça, une garde resterait bloquée en
		-- position haute dès que le curseur passe sur un élément d'interface.
		if InputController.isHeldAction(action) or not processed then
			InputController.fire(action, "End")
		end
	end)
end

return InputController
