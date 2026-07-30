--!strict
--[[
	Correspondance touches → actions nommées.

	Le reste du code ne connaît que des noms d'action (`"Attack"`, `"Block"`…) ;
	seul InputController connaît `UserInputService`. C'est ce qui rendra les
	keybinds personnalisables (brief §5.4) sans toucher au gameplay : il suffira
	d'écraser ces tables avec les préférences du profil.

	Les actions de compétences (`Skill1`..`Skill4`) arriveront avec les styles, en
	Phase 2 : les déclarer maintenant sans style à lancer ne servirait à rien.
]]

local TableUtil = require(script.Parent.Parent.Shared.TableUtil)

export type ActionName = "Attack" | "Block" | "Dash" | "Sprint" | "ToggleDebug"

local Input = {
	-- Ordre d'affichage dans l'écran de paramètres (Phase 4).
	Actions = { "Attack", "Block", "Dash", "Sprint", "ToggleDebug" } :: { ActionName },

	Keys = {
		Block = Enum.KeyCode.F,
		Dash = Enum.KeyCode.Q,
		Sprint = Enum.KeyCode.LeftShift,
		ToggleDebug = Enum.KeyCode.F2,
	} :: { [string]: Enum.KeyCode },

	MouseButtons = {
		Attack = Enum.UserInputType.MouseButton1,
	} :: { [string]: Enum.UserInputType },

	Gamepad = {
		Attack = Enum.KeyCode.ButtonX,
		Block = Enum.KeyCode.ButtonL2,
		Dash = Enum.KeyCode.ButtonR1,
		Sprint = Enum.KeyCode.ButtonL3,
	} :: { [string]: Enum.KeyCode },

	--[[
		Actions maintenues plutôt que déclenchées. La garde en fait partie : la
		fenêtre de parade s'ouvre à l'appui et la garde tient tant qu'on ne
		relâche pas, donc le relâchement est un événement à part entière.
	]]
	Held = {
		Block = true,
		Sprint = true,
	} :: { [string]: boolean },
}

return TableUtil.deepFreeze(Input)
