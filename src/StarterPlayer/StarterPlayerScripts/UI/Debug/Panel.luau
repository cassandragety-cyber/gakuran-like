--!strict
--[[
	Châssis du panneau de debug : la fenêtre, les sections, le défilement.

	Le panneau est construit une fois et masqué plutôt que détruit à chaque
	fermeture : reconstruire une trentaine de lignes et vingt curseurs à chaque
	appui sur F2 produirait un à-coup visible en pleine session de réglage.

	`Enum.ZIndexBehavior.Sibling` et un `DisplayOrder` élevé garantissent qu'il
	reste au-dessus du HUD de combat qui arrivera en tranche 1.2.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Theme)

export type Panel = {
	gui: ScreenGui,
	setVisible: (visible: boolean) -> (),
	isVisible: () -> boolean,
	section: (title: string) -> Frame,
	addButton: (text: string, onClick: () -> ()) -> TextButton,
	destroy: () -> (),
}

local Panel = {}

function Panel.create(width: number): Panel
	local gui = Instance.new("ScreenGui")
	gui.Name = "BanchouDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(1, 0)
	window.Position = UDim2.new(1, -12, 0, 12)
	window.Size = UDim2.new(0, width, 1, -24)
	window.BackgroundColor3 = Theme.Colors.Background
	window.BackgroundTransparency = 0.08
	window.BorderSizePixel = 0
	window.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.Corner)
	corner.Parent = window

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.Parent = window

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Theme.Fonts.Strong
	title.TextSize = Theme.Sizes.TextTitle
	title.TextColor3 = Theme.Colors.Text
	title.Text = "Banchou — debug (F2)"
	title.Parent = window

	local body = Instance.new("ScrollingFrame")
	body.Position = UDim2.new(0, 0, 0, 28)
	body.Size = UDim2.new(1, 0, 1, -28)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = body

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = body

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function section(sectionTitle: string): Frame
		local header = Instance.new("TextLabel")
		header.BackgroundTransparency = 1
		header.LayoutOrder = nextOrder()
		header.Size = UDim2.new(1, 0, 0, 22)
		header.Font = Theme.Fonts.Strong
		header.TextSize = Theme.Sizes.TextBody
		header.TextColor3 = Theme.Colors.Accent
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = sectionTitle
		header.Parent = body

		local container = Instance.new("Frame")
		container.BackgroundColor3 = Theme.Colors.Surface
		container.BackgroundTransparency = 0.35
		container.BorderSizePixel = 0
		container.LayoutOrder = nextOrder()
		container.Size = UDim2.new(1, 0, 0, 0)
		container.AutomaticSize = Enum.AutomaticSize.Y
		container.Parent = body

		local containerCorner = Instance.new("UICorner")
		containerCorner.CornerRadius = UDim.new(0, 4)
		containerCorner.Parent = container

		local containerLayout = Instance.new("UIListLayout")
		containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
		containerLayout.Padding = UDim.new(0, 2)
		containerLayout.Parent = container

		local containerPadding = Instance.new("UIPadding")
		containerPadding.PaddingTop = UDim.new(0, 6)
		containerPadding.PaddingBottom = UDim.new(0, 6)
		containerPadding.PaddingLeft = UDim.new(0, 6)
		containerPadding.PaddingRight = UDim.new(0, 6)
		containerPadding.Parent = container

		return container
	end

	local function addButton(text: string, onClick: () -> ()): TextButton
		local button = Instance.new("TextButton")
		button.LayoutOrder = nextOrder()
		-- Hauteur au minimum tactile : le panneau sert aussi pendant les tests
		-- sur téléphone.
		button.Size = UDim2.new(1, 0, 0, Theme.Sizes.TouchTarget)
		button.BackgroundColor3 = Theme.Colors.SurfaceRaised
		button.BorderSizePixel = 0
		button.Font = Theme.Fonts.Body
		button.TextSize = Theme.Sizes.TextBody
		button.TextColor3 = Theme.Colors.Text
		button.Text = text
		button.Parent = body

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 4)
		buttonCorner.Parent = button

		button.Activated:Connect(onClick)
		return button
	end

	return {
		gui = gui,
		setVisible = function(visible: boolean)
			gui.Enabled = visible
		end,
		isVisible = function(): boolean
			return gui.Enabled
		end,
		section = section,
		addButton = addButton,
		destroy = function()
			gui:Destroy()
		end,
	}
end

return Panel
