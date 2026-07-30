--!strict
--[[
	Ligne « libellé / valeur » du panneau de debug.

	`setValue` accepte une couleur pour signaler un écart : le rouge est ce qui
	permet de repérer une divergence de prédiction du coin de l'œil, en pleine
	action, sans lire les chiffres.
]]

local Theme = require(script.Parent.Parent.Theme)

export type Row = {
	frame: Frame,
	setValue: (text: string, color: Color3?) -> (),
}

local Row = {}

function Row.create(parent: Instance, label: string): Row
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, Theme.Sizes.RowHeight)
	frame.Parent = parent

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(0.5, 0, 1, 0)
	name.Font = Theme.Fonts.Body
	name.TextSize = Theme.Sizes.TextSmall
	name.TextColor3 = Theme.Colors.TextMuted
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = label
	name.Parent = frame

	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Position = UDim2.new(0.5, 0, 0, 0)
	value.Size = UDim2.new(0.5, 0, 1, 0)
	value.Font = Theme.Fonts.Value
	value.TextSize = Theme.Sizes.TextSmall
	value.TextColor3 = Theme.Colors.Text
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = "—"
	value.Parent = frame

	return {
		frame = frame,
		setValue = function(text: string, color: Color3?)
			-- On n'écrit que si le texte change : réassigner `Text` invalide la
			-- mise en page du TextLabel, et le panneau se rafraîchit 10 fois par
			-- seconde sur une trentaine de lignes.
			if value.Text ~= text then
				value.Text = text
			end
			local target = color or Theme.Colors.Text
			if value.TextColor3 ~= target then
				value.TextColor3 = target
			end
		end,
	}
end

return Row
