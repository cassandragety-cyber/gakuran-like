--!strict
--[[
	Curseur de réglage : libellé, glissière, saisie numérique.

	`onChanged` est appelé pendant le glissement, pas seulement au relâchement :
	régler une fenêtre de parade demande de sentir l'effet en continu, et le
	serveur borne de toute façon la cadence (`Config/RateLimits.DebugTuning`).

	La valeur affichée est celle que le SERVEUR a retenue, appliquée par
	`setValue` : si le serveur aligne 0,203 sur 0,20, le curseur doit le montrer,
	sinon on croit régler une valeur qui n'existe pas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Theme = require(script.Parent.Parent.Theme)

export type Config = {
	label: string,
	min: number,
	max: number,
	step: number,
	value: number,
	onChanged: (value: number) -> (),
}

export type Slider = {
	frame: Frame,
	setValue: (value: number) -> (),
}

local Slider = {}

local TRACK_HEIGHT = 6

function Slider.create(parent: Instance, config: Config): Slider
	local current = config.value

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, Theme.Sizes.RowHeight * 2)
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -70, 0, Theme.Sizes.RowHeight)
	label.Font = Theme.Fonts.Body
	label.TextSize = Theme.Sizes.TextSmall
	label.TextColor3 = Theme.Colors.TextMuted
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.label
	label.Parent = frame

	local box = Instance.new("TextBox")
	box.AnchorPoint = Vector2.new(1, 0)
	box.Position = UDim2.new(1, 0, 0, 0)
	box.Size = UDim2.new(0, 66, 0, Theme.Sizes.RowHeight)
	box.BackgroundColor3 = Theme.Colors.SurfaceRaised
	box.BorderSizePixel = 0
	box.Font = Theme.Fonts.Value
	box.TextSize = Theme.Sizes.TextSmall
	box.TextColor3 = Theme.Colors.Text
	box.ClearTextOnFocus = false
	box.Text = tostring(current)
	box.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = box

	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.Text = ""
	track.Position = UDim2.new(0, 0, 0, Theme.Sizes.RowHeight + 6)
	track.Size = UDim2.new(1, 0, 0, TRACK_HEIGHT)
	track.BackgroundColor3 = Theme.Colors.SurfaceRaised
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Colors.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(MathUtil.inverseLerp(config.min, config.max, current), 1)
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local function render(value: number)
		current = value
		fill.Size = UDim2.fromScale(MathUtil.inverseLerp(config.min, config.max, value), 1)
		local text = tostring(value)
		if box.Text ~= text and not box:IsFocused() then
			box.Text = text
		end
	end

	local function requestFromAlpha(alpha: number)
		local raw = MathUtil.lerp(config.min, config.max, math.clamp(alpha, 0, 1))
		local aligned = math.clamp(MathUtil.roundTo(raw, config.step), config.min, config.max)
		if aligned ~= current then
			render(aligned)
			config.onChanged(aligned)
		end
	end

	local dragging = false

	local function alphaFromPointer(position: Vector2): number
		return (position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dragging = true
		requestFromAlpha(alphaFromPointer(Vector2.new(input.Position.X, input.Position.Y)))
	end)

	-- Le suivi se fait sur UserInputService et non sur le bouton : le pointeur
	-- sort de la glissière dès qu'on tire un peu vite, et le réglage ne doit pas
	-- s'interrompre pour ça.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		requestFromAlpha(alphaFromPointer(Vector2.new(input.Position.X, input.Position.Y)))
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	box.FocusLost:Connect(function()
		local typed = tonumber(box.Text)
		if typed == nil then
			box.Text = tostring(current)
			return
		end
		local aligned = math.clamp(MathUtil.roundTo(typed, config.step), config.min, config.max)
		render(aligned)
		config.onChanged(aligned)
	end)

	return { frame = frame, setValue = render }
end

return Slider
