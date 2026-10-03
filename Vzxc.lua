--[[
	NurHub  |  LocalScript  |  v1.2
	Telegram: https://t.me/NurHuboffical
	Без библиотеки Drawing: всё на Frame / UIStroke / Highlight / Lighting.
	Положить как LocalScript (например StarterPlayerScripts) или запустить через executor.
	Открыть / закрыть меню: кнопка NH или RightShift (меняется в Setting).

	Что нового в v1.2: Aimbot-клавиша (E по умолчанию, меняется), режимы Key / RMB / Always.
	Что было в v1.1:
	  • Visual  -> HUD: Show FPS, Custom FPS (фейк), 2D-экран для перемещения плашки, палитра
	  • Config  -> 5 слотов: сохранить с именем / загрузить / удалить
	  • Combat  -> Aimbot: выбор части тела (2D-игрок + список), FOV, скорость, FOV-круг
	  • Fix     -> Tracers: три кнопки в один ряд, ничего не перекрывается
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local Lighting     = game:GetService("Lighting")
local GuiService   = game:GetService("GuiService")
local HttpService  = game:GetService("HttpService")

local LP = Players.LocalPlayer
local TG_LINK = "https://t.me/NurHuboffical"
local WHITE = Color3.new(1, 1, 1)
local ENV = (typeof(getgenv) == "function" and getgenv()) or _G

pcall(function() RunService:UnbindFromRenderStep("NurHubAim") end)

local conns = {}
local function connect(sig, fn)
	local c = sig:Connect(fn)
	conns[#conns + 1] = c
	return c
end

----------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------
local function mount(gui)
	local ok = pcall(function()
		gui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = LP:WaitForChild("PlayerGui")
	end
end

local function cleanOld()
	local roots = { LP:FindFirstChildOfClass("PlayerGui") }
	pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
	pcall(function() if typeof(gethui) == "function" then table.insert(roots, gethui()) end end)
	for _, r in ipairs(roots) do
		for _, n in ipairs({ "NurHub_UI", "NurHub_ESP", "NurHub_HUD" }) do
			local o = r and r:FindFirstChild(n)
			if o then pcall(function() o:Destroy() end) end
		end
	end
	for _, n in ipairs({ "NH_CC", "NH_Bloom", "NH_Rays" }) do
		local o = Lighting:FindFirstChild(n)
		if o then o:Destroy() end
	end
end
cleanOld()

local function new(class, props, parent)
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do o[k] = v end
	end
	if parent then o.Parent = parent end
	return o
end

local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, color, th, tr)
	return new("UIStroke", {
		Color = color, Thickness = th or 1, Transparency = tr or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function tw(o, t, props, style, dir)
	local tween = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

local orderCounter = 0
local function ord()
	orderCounter += 1
	return orderCounter
end

----------------------------------------------------------------
-- Реестр настроек (для Config: сохранить / загрузить)
----------------------------------------------------------------
local Reg = {}
local function register(id, kind, get, set)
	if id then Reg[id] = { kind = kind, get = get, set = set } end
end

local function snapshot()
	local d = {}
	for id, e in pairs(Reg) do
		local ok, v = pcall(e.get)
		if ok and v ~= nil then
			if e.kind == "color" then
				d[id] = { r = v.R, g = v.G, b = v.B }
			else
				d[id] = v
			end
		end
	end
	return d
end

local function applySnapshot(d)
	for id, v in pairs(d) do
		local e = Reg[id]
		if e then
			pcall(function()
				if e.kind == "color" then
					e.set(Color3.new(v.r, v.g, v.b))
				else
					e.set(v)
				end
			end)
		end
	end
end

----------------------------------------------------------------
-- Тема / регистры (акцент, цвет меню, прозрачность)
----------------------------------------------------------------
local Theme = {
	accent = Color3.fromRGB(64, 98, 255),
	text   = Color3.fromRGB(235, 235, 242),
	sub    = Color3.fromRGB(140, 140, 156),
	off    = Color3.fromRGB(48, 48, 58),
	chip   = Color3.fromRGB(34, 34, 42),
}
local RED = Color3.fromRGB(235, 80, 64)

local accentFns = {}
local function onAccent(fn)
	accentFns[#accentFns + 1] = fn
	fn()
end
local function setAccent(c)
	Theme.accent = c
	for _, f in ipairs(accentFns) do pcall(f) end
end

local menuColor = Color3.fromRGB(13, 13, 16)
local menuTrans = 0
local bgReg = {}
local function applyBg()
	for _, e in ipairs(bgReg) do
		e.inst.BackgroundColor3 = menuColor:Lerp(WHITE, e.lerp)
		e.inst.BackgroundTransparency = e.base + (1 - e.base) * menuTrans
	end
end
local function regBg(inst, lerp, base)
	bgReg[#bgReg + 1] = { inst = inst, lerp = lerp, base = base or 0 }
	applyBg()
end

----------------------------------------------------------------
-- Перетаскивание / слайдеры
----------------------------------------------------------------
local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

-- слайдер/полоса: на время перетаскивания блокируем прокрутку страницы
local function makeDrag(button, callback)
	local dragging = false
	local scroller
	local function upd(i)
		local w = math.max(button.AbsoluteSize.X, 1)
		callback(math.clamp((i.Position.X - button.AbsolutePosition.X) / w, 0, 1))
	end
	button.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			scroller = button:FindFirstAncestorOfClass("ScrollingFrame")
			if scroller then scroller.ScrollingEnabled = false end
			upd(i)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and isMove(i) then upd(i) end
	end)
	connect(UIS.InputEnded, function(i)
		if dragging and isPress(i) then
			dragging = false
			if scroller then scroller.ScrollingEnabled = true end
		end
	end)
end

local function makeDraggable(handle, target, onClick)
	local dragging, moved = false, false
	local startMouse, startPos
	handle.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging, moved = true, false
			startMouse = i.Position
			startPos = target.Position
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and isMove(i) then
			local d = i.Position - startMouse
			if d.Magnitude > 5 then moved = true end
			if moved then
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
	connect(UIS.InputEnded, function(i)
		if dragging and isPress(i) then
			dragging = false
			if not moved and onClick then onClick() end
		end
	end)
end

----------------------------------------------------------------
-- UI-компоненты
----------------------------------------------------------------
local function Card(parent, title, big)
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0, LayoutOrder = ord(),
	}, parent)
	regBg(card, 0.045)
	corner(card, 9)
	stroke(card, Color3.fromRGB(36, 36, 46), 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, card)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	if title then
		new("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, big and 22 or 16), LayoutOrder = ord(),
			Font = Enum.Font.GothamBold, Text = big and title or string.upper(title), TextSize = big and 15 or 11,
			TextColor3 = Color3.fromRGB(235, 235, 245), TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
	end
	return card
end

local function Label(parent, text, color, size)
	return new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.Gotham, TextSize = size or 12, TextColor3 = color or Theme.sub,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = text, LayoutOrder = ord(),
	}, parent)
end

local function Button(parent, text, cb)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.chip, BorderSizePixel = 0,
		AutoButtonColor = false, Font = Enum.Font.GothamMedium, Text = text, TextSize = 12,
		TextColor3 = Theme.text, LayoutOrder = ord(),
	}, parent)
	corner(b, 7)
	b.MouseEnter:Connect(function() tw(b, .15, { BackgroundColor3 = Color3.fromRGB(44, 44, 54) }) end)
	b.MouseLeave:Connect(function() tw(b, .15, { BackgroundColor3 = Theme.chip }) end)
	b.MouseButton1Click:Connect(function() if cb then cb(b) end end)
	return b
end

-- стрелка-шеврон
local function Chevron(parent, pos)
	local c = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = pos, Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1, Rotation = -90,
	}, parent)
	for _, d in ipairs({ { 3.5, 45 }, { 8.5, -45 } }) do
		local b = new("Frame", {
			AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(d[1], 5.5),
			Size = UDim2.fromOffset(7, 2), Rotation = d[2], BackgroundColor3 = Theme.sub, BorderSizePixel = 0,
		}, c)
		corner(b, 1)
	end
	return c
end

-- раскрывающаяся «шторка»
local function Expandable(parent, headerH)
	local wrap = new("Frame", {
		Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1,
		ClipsDescendants = true, LayoutOrder = ord(),
	}, parent)
	local header = new("Frame", { Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1 }, wrap)
	local drawer = new("Frame", {
		Position = UDim2.new(0, 0, 0, headerH + 4), Size = UDim2.new(1, 0, 0, 0), BorderSizePixel = 0,
	}, wrap)
	regBg(drawer, 0.015)
	corner(drawer, 7)
	local layout = new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, drawer)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, drawer)
	local open = false
	local function target() return headerH + 4 + layout.AbsoluteContentSize.Y + 16 + 2 end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		drawer.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 16)
		if open then tw(wrap, .25, { Size = UDim2.new(1, 0, 0, target()) }) end
	end)
	local function set(v)
		open = v
		tw(wrap, .38, { Size = UDim2.new(1, 0, 0, v and target() or headerH) })
	end
	return wrap, header, drawer, set
end

local function DrawerRow(parent, text, builder)
	local _, header, drawer, setOpen = Expandable(parent, 28)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -30, 1, 0), Font = Enum.Font.GothamMedium,
		Text = text, TextSize = 13, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	local chev = Chevron(header, UDim2.new(1, -8, .5, 0))
	local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, header)
	local open = false
	hit.MouseButton1Click:Connect(function()
		open = not open
		setOpen(open)
		tw(chev, .3, { Rotation = open and 0 or -90 })
	end)
	if builder then builder(drawer) end
end

local function Toggle(parent, text, default, callback, builder, id)
	local _, header, drawer, setOpen = Expandable(parent, 28)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -70, 1, 0), Font = Enum.Font.GothamMedium,
		Text = text, TextSize = 13, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	local sw = new("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0),
		Size = UDim2.fromOffset(34, 18), BorderSizePixel = 0,
	}, header)
	corner(sw, 9)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, .5), Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 2, .5, 0),
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, sw)
	corner(knob, 7)
	local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, header)

	local state = default and true or false
	local function render(anim)
		local d = anim and .22 or 0
		tw(sw, d, { BackgroundColor3 = state and Theme.accent or Theme.off })
		tw(knob, d, { Position = state and UDim2.new(1, -16, .5, 0) or UDim2.new(0, 2, .5, 0) })
	end
	onAccent(function() render(false) end)
	local function setState(v, fire)
		state = v and true or false
		render(true)
		if fire and callback then callback(state) end
	end
	hit.MouseButton1Click:Connect(function() setState(not state, true) end)
	register(id, "bool", function() return state end, function(v) setState(v, true) end)

	if builder then
		local chev = Chevron(header, UDim2.new(1, -52, .5, 0))
		local arrowHit = new("TextButton", {
			BackgroundTransparency = 1, Text = "", AnchorPoint = Vector2.new(1, .5),
			Position = UDim2.new(1, -40, .5, 0), Size = UDim2.fromOffset(26, 28),
		}, header)
		local open = false
		arrowHit.MouseButton1Click:Connect(function()
			open = not open
			setOpen(open)
			tw(chev, .3, { Rotation = open and 0 or -90 })
		end)
		builder(drawer)
	end
end

local function Slider(parent, text, min, max, default, decimals, callback, fmt, id)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(.6, 0, 0, 16), Font = Enum.Font.GothamMedium,
		Text = text, TextSize = 12, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local val = new("TextLabel", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(.4, 0, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local bar = new("TextButton", {
		Text = "", AutoButtonColor = false, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.off, BorderSizePixel = 0,
	}, row)
	corner(bar, 3)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, bar)
	corner(fill, 3)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, fill)
	corner(knob, 6)
	onAccent(function() fill.BackgroundColor3 = Theme.accent end)

	local cur = default
	local function set(v, fire)
		v = math.clamp(v, min, max)
		local m = 10 ^ decimals
		v = math.floor(v * m + .5) / m
		cur = v
		tw(fill, .07, { Size = UDim2.new((v - min) / (max - min), 0, 1, 0) })
		val.Text = fmt and fmt(v) or tostring(v)
		if fire and callback then callback(v) end
	end
	makeDrag(bar, function(a) set(min + (max - min) * a, true) end)
	set(default, false)
	register(id, "number", function() return cur end, function(v) set(tonumber(v) or cur, true) end)
end

local function ColorBar(parent, label, onChange)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), Font = Enum.Font.GothamMedium,
		Text = label, TextSize = 10, TextColor3 = Theme.sub, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local bar = new("TextButton", {
		Text = "", AutoButtonColor = false, Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, row)
	corner(bar, 4)
	local grad = new("UIGradient", {}, bar)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, bar)
	corner(knob, 6)
	stroke(knob, Color3.fromRGB(18, 18, 22), 2)
	makeDrag(bar, onChange)
	return {
		grad = grad,
		set = function(a) tw(knob, .06, { Position = UDim2.new(a, 0, .5, 0) }) end,
	}
end

local BRIGHT = {
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 50),
	Color3.fromRGB(80, 255, 120), Color3.fromRGB(60, 230, 255), Color3.fromRGB(70, 100, 255),
	Color3.fromRGB(170, 80, 255), Color3.fromRGB(255, 90, 200),
}
local DARKS = {
	Color3.fromRGB(13, 13, 16), Color3.fromRGB(0, 0, 0), Color3.fromRGB(10, 12, 28),
	Color3.fromRGB(28, 10, 14), Color3.fromRGB(10, 24, 18), Color3.fromRGB(24, 12, 32),
	Color3.fromRGB(30, 30, 36), Color3.fromRGB(40, 28, 16),
}

-- палитра с оттенками: превью + быстрые цвета + Hue / Saturation / Brightness
local function ColorPicker(parent, default, callback, swatches, id)
	swatches = swatches or BRIGHT
	local h, s, v = default:ToHSV()
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, top)
	local preview = new("Frame", { Size = UDim2.fromOffset(26, 16), BorderSizePixel = 0, LayoutOrder = 0 }, top)
	corner(preview, 4)
	stroke(preview, Color3.fromRGB(70, 70, 84), 1)

	local hueB, satB, valB
	local function refresh(fire)
		local c = Color3.fromHSV(h, s, v)
		preview.BackgroundColor3 = c
		satB.grad.Color = ColorSequence.new(Color3.fromHSV(h, 0, v), Color3.fromHSV(h, 1, v))
		valB.grad.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
		hueB.set(h); satB.set(s); valB.set(v)
		if fire and callback then callback(c) end
	end
	for i, c in ipairs(swatches) do
		local b = new("TextButton", {
			Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(14, 14), BackgroundColor3 = c,
			BorderSizePixel = 0, LayoutOrder = i,
		}, top)
		corner(b, 4)
		stroke(b, Color3.fromRGB(60, 60, 72), 1)
		b.MouseButton1Click:Connect(function()
			h, s, v = c:ToHSV()
			refresh(true)
		end)
	end
	hueB = ColorBar(parent, "Hue", function(a) h = math.min(a, 0.999); refresh(true) end)
	satB = ColorBar(parent, "Saturation", function(a) s = a; refresh(true) end)
	valB = ColorBar(parent, "Brightness", function(a) v = a; refresh(true) end)
	local keys = {}
	for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(math.min(i / 6, 0.999), 1, 1)) end
	hueB.grad.Color = ColorSequence.new(keys)
	refresh(false)
	register(id, "color", function() return Color3.fromHSV(h, s, v) end, function(c)
		h, s, v = c:ToHSV()
		refresh(true)
	end)
end

-- Кнопки выбора. Раскладка считается вручную (без UIGridLayout), поэтому
-- все кнопки ряда всегда на одном уровне и ничего не переносится/не перекрывается.
local function Options(parent, list, default, callback, cols, id)
	cols = cols or 2
	local gap = 4
	local rows = math.ceil(#list / cols)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, rows * 24 + (rows - 1) * gap), BackgroundTransparency = 1, LayoutOrder = ord(),
	}, parent)
	local sel = default
	local btns = {}
	local function render()
		for name, b in pairs(btns) do
			local on = name == sel
			tw(b, .2, { BackgroundColor3 = on and Theme.accent or Theme.chip, TextColor3 = on and WHITE or Theme.sub })
		end
	end
	for i, name in ipairs(list) do
		local c = (i - 1) % cols
		local r = math.floor((i - 1) / cols)
		local b = new("TextButton", {
			Text = name, AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 11,
			BorderSizePixel = 0, LayoutOrder = i,
			Size = UDim2.new(1 / cols, -gap * (cols - 1) / cols, 0, 24),
			Position = UDim2.new(c / cols, c * gap / cols, 0, r * (24 + gap)),
		}, holder)
		corner(b, 6)
		btns[name] = b
		b.MouseButton1Click:Connect(function()
			sel = name
			render()
			if callback then callback(name) end
		end)
	end
	onAccent(render)
	register(id, "string", function() return sel end, function(n)
		if btns[n] then
			sel = n
			render()
			if callback then callback(n) end
		end
	end)
end

----------------------------------------------------------------
-- Выбор части тела для аимбота (2D-игрок + список)
----------------------------------------------------------------
local PART_LIST = { "Head", "Torso", "Left arm", "Right arm", "Left leg", "Right leg" }
local PART_INFO = {
	["Head"]      = "Precise target, small hitbox",
	["Torso"]     = "Biggest hitbox, most reliable",
	["Left arm"]  = "Limb target, medium hitbox",
	["Right arm"] = "Limb target, medium hitbox",
	["Left leg"]  = "Low target, steady aim",
	["Right leg"] = "Low target, steady aim",
}
-- x, y, w, h, круглая, размер свечения
local FIG = {
	["Head"]      = { 45, 0, 30, 30, true, 74 },
	["Torso"]     = { 34, 34, 52, 58, false, 118 },
	["Left arm"]  = { 16, 34, 14, 56, false, 84 },
	["Right arm"] = { 90, 34, 14, 56, false, 84 },
	["Left leg"]  = { 35, 96, 22, 62, false, 92 },
	["Right leg"] = { 63, 96, 22, 62, false, 92 },
}
local PART_OFF = Color3.fromRGB(68, 68, 90)
local PART_OFF_STROKE = Color3.fromRGB(98, 98, 124)

local function TargetPicker(parent, default, callback, id)
	local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 236), BackgroundTransparency = 1, LayoutOrder = ord() }, parent)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(.5, 0, 0, 14), Font = Enum.Font.GothamBold,
		Text = "AIMBOT TARGET", TextSize = 10, TextColor3 = Theme.sub, TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)
	local nameLbl = new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(.55, 0, 0, 32),
		Font = Enum.Font.GothamBold, TextSize = 26, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, holder)
	local descLbl = new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(.55, 0, 0, 14),
		Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.sub, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, holder)

	local dots, texts, parts = {}, {}, {}
	local sel = default
	local pulse

	-- 2D игрок
	local fig = new("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -4, .5, 0),
		Size = UDim2.fromOffset(120, 176), BackgroundTransparency = 1,
	}, holder)
	local glow = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(60, 50), Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = RED, BackgroundTransparency = .8, BorderSizePixel = 0, ZIndex = 1,
	}, fig)
	corner(glow, 80)
	TweenService:Create(glow, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = .9 }):Play()
	local floorShadow = new("Frame", {
		Position = UDim2.fromOffset(15, 162), Size = UDim2.fromOffset(90, 10),
		BackgroundColor3 = Color3.fromRGB(10, 10, 14), BorderSizePixel = 0, ZIndex = 1,
	}, fig)
	corner(floorShadow, 5)

	local function render(name, animate)
		sel = name
		nameLbl.Text = name
		descLbl.Text = PART_INFO[name]
		for _, n in ipairs(PART_LIST) do
			local on = n == name
			tw(dots[n], .2, { BackgroundColor3 = on and RED or Theme.off })
			tw(texts[n], .2, { TextColor3 = on and WHITE or Theme.sub })
			local p = parts[n]
			tw(p.btn, animate and .25 or 0, { BackgroundColor3 = on and RED or PART_OFF })
			tw(p.stroke, animate and .25 or 0, { Color = on and WHITE or PART_OFF_STROKE })
			if not on then p.stroke.Thickness = 1.5 end
		end
		-- свечение переезжает на выбранную часть
		local s = FIG[name]
		local gs = s[6]
		tw(glow, animate and .5 or 0, {
			Position = UDim2.fromOffset(s[1] + s[3] / 2, s[2] + s[4] / 2),
			Size = UDim2.fromOffset(gs, gs),
		}, Enum.EasingStyle.Back)
		-- «поп» + пульсация обводки
		local p = parts[name]
		if pulse then pulse:Cancel() end
		if animate then
			p.scale.Scale = .82
			tw(p.scale, .45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		p.stroke.Thickness = 2
		pulse = TweenService:Create(p.stroke, TweenInfo.new(.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 4 })
		pulse:Play()
	end

	for i, name in ipairs(PART_LIST) do
		local row = new("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 76 + (i - 1) * 26), Size = UDim2.new(.5, -6, 0, 24),
		}, holder)
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 2, .5, 0), Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Theme.off, BorderSizePixel = 0,
		}, row)
		corner(dot, 5)
		local t = new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0),
			Font = Enum.Font.GothamMedium, Text = name, TextSize = 13, TextColor3 = Theme.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		dots[name], texts[name] = dot, t
		row.MouseButton1Click:Connect(function()
			if sel ~= name then
				render(name, true)
				if callback then callback(name) end
			end
		end)
	end

	for _, name in ipairs(PART_LIST) do
		local s = FIG[name]
		local b = new("TextButton", {
			Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(s[1], s[2]),
			Size = UDim2.fromOffset(s[3], s[4]), BackgroundColor3 = PART_OFF, BorderSizePixel = 0, ZIndex = 2,
		}, fig)
		corner(b, s[5] and 15 or 7)
		local st = stroke(b, PART_OFF_STROKE, 1.5)
		local sc = new("UIScale", {}, b)
		parts[name] = { btn = b, stroke = st, scale = sc }
		b.MouseEnter:Connect(function()
			if sel ~= name then tw(b, .15, { BackgroundColor3 = Color3.fromRGB(86, 86, 112) }) end
		end)
		b.MouseLeave:Connect(function()
			if sel ~= name then tw(b, .15, { BackgroundColor3 = PART_OFF }) end
		end)
		b.MouseButton1Click:Connect(function()
			if sel ~= name then
				render(name, true)
				if callback then callback(name) end
			end
		end)
	end

	render(default, false)
	register(id, "string", function() return sel end, function(n)
		if PART_INFO[n] then
			render(n, true)
			if callback then callback(n) end
		end
	end)
end

----------------------------------------------------------------
-- ESP (без Drawing: Frame-линии, UIStroke, Highlight)
----------------------------------------------------------------
local ESP = {
	box2d    = { on = false, color = WHITE },
	box3d    = { on = false, color = WHITE },
	skeleton = { on = false, color = WHITE },
	chams    = { on = false, color = WHITE, transp = 0.5 },
	outline  = { on = false, color = WHITE },
	tracers  = { on = false, color = WHITE, origin = "Bottom" },
	thickness = 1.5,
	maxDist = 2500,
}

local espGui = new("ScreenGui", {
	Name = "NurHub_ESP", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
mount(espGui)

local function newLine()
	return new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, BackgroundColor3 = WHITE,
		Visible = false, Size = UDim2.fromOffset(0, 1),
	}, espGui)
end
local function drawLine(f, a, b, col, th)
	local d = b - a
	f.Size = UDim2.fromOffset(d.Magnitude, th)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = col
	f.Visible = true
end

local R15 = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6 = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local EDGES = {}
for i = 0, 7 do
	for _, b in ipairs({ 1, 2, 4 }) do
		if bit32.band(i, b) == 0 then EDGES[#EDGES + 1] = { i, i + b } end
	end
end

local store = {}
local function hideList(l) if l then for _, f in ipairs(l) do f.Visible = false end end end
local function hideAll(d)
	if d.box then d.box.Visible = false end
	hideList(d.e3); hideList(d.sk)
	if d.tr then d.tr.Visible = false end
	if d.hl then d.hl.Enabled = false end
end
local function destroyData(d)
	for _, v in pairs(d) do
		if typeof(v) == "Instance" then
			pcall(function() v:Destroy() end)
		elseif type(v) == "table" then
			for _, x in ipairs(v) do pcall(function() x:Destroy() end) end
		end
	end
end

connect(RunService.RenderStepped, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vs = cam.ViewportSize
	local th = ESP.thickness

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local d = store[plr]
			if not d then d = {}; store[plr] = d end
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)

			if not (hum and root and hum.Health > 0) or (cam.CFrame.Position - root.Position).Magnitude > ESP.maxDist then
				hideAll(d)
			else
				-- Chams + Outline (Highlight)
				if ESP.chams.on or ESP.outline.on then
					if not d.hl then
						d.hl = new("Highlight", { DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, espGui)
					end
					d.hl.Adornee = char
					d.hl.FillColor = ESP.chams.color
					d.hl.FillTransparency = ESP.chams.on and ESP.chams.transp or 1
					d.hl.OutlineColor = ESP.outline.color
					d.hl.OutlineTransparency = ESP.outline.on and 0 or 1
					d.hl.Enabled = true
				elseif d.hl then
					d.hl.Enabled = false
				end

				-- Box 2D / Box 3D
				local pts, allFront
				local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
				if ESP.box2d.on or ESP.box3d.on then
					local cf, size = char:GetBoundingBox()
					local hs = size / 2
					pts, allFront = {}, true
					for i = 0, 7 do
						local x = (i % 2) * 2 - 1
						local y = (math.floor(i / 2) % 2) * 2 - 1
						local z = math.floor(i / 4) * 2 - 1
						local p = cam:WorldToViewportPoint(cf:PointToWorldSpace(Vector3.new(x * hs.X, y * hs.Y, z * hs.Z)))
						pts[i] = p
						if p.Z <= 0 then
							allFront = false
						else
							minX = math.min(minX, p.X); minY = math.min(minY, p.Y)
							maxX = math.max(maxX, p.X); maxY = math.max(maxY, p.Y)
						end
					end
				end

				if ESP.box2d.on and pts and allFront then
					if not d.box then
						d.box = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, espGui)
						d.boxStroke = new("UIStroke", { Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, d.box)
					end
					d.box.Position = UDim2.fromOffset(minX, minY)
					d.box.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
					d.boxStroke.Color = ESP.box2d.color
					d.boxStroke.Thickness = th
					d.box.Visible = true
				elseif d.box then
					d.box.Visible = false
				end

				if ESP.box3d.on and pts then
					if not d.e3 then
						d.e3 = {}
						for i = 1, 12 do d.e3[i] = newLine() end
					end
					for i, e in ipairs(EDGES) do
						local a, b = pts[e[1]], pts[e[2]]
						if a.Z > 0 and b.Z > 0 then
							drawLine(d.e3[i], Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), ESP.box3d.color, th)
						else
							d.e3[i].Visible = false
						end
					end
				else
					hideList(d.e3)
				end

				-- Skeleton
				if ESP.skeleton.on then
					local list = hum.RigType == Enum.HumanoidRigType.R15 and R15 or R6
					if not d.sk then
						d.sk = {}
						for i = 1, 14 do d.sk[i] = newLine() end
					end
					for i = 1, 14 do
						local pr, line = list[i], d.sk[i]
						if pr then
							local a, b = char:FindFirstChild(pr[1]), char:FindFirstChild(pr[2])
							if a and b then
								local pa = cam:WorldToViewportPoint(a.Position)
								local pb = cam:WorldToViewportPoint(b.Position)
								if pa.Z > 0 and pb.Z > 0 then
									drawLine(line, Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y), ESP.skeleton.color, th)
								else
									line.Visible = false
								end
							else
								line.Visible = false
							end
						else
							line.Visible = false
						end
					end
				else
					hideList(d.sk)
				end

				-- Tracers
				if ESP.tracers.on then
					local rp = cam:WorldToViewportPoint(root.Position)
					if rp.Z > 0 then
						local o = Vector2.new(vs.X / 2, vs.Y)
						if ESP.tracers.origin == "Top" then
							o = Vector2.new(vs.X / 2, 0)
						elseif ESP.tracers.origin == "Crosshair" then
							o = Vector2.new(vs.X / 2, vs.Y / 2)
						end
						if not d.tr then d.tr = newLine() end
						drawLine(d.tr, o, Vector2.new(rp.X, rp.Y), ESP.tracers.color, th)
					elseif d.tr then
						d.tr.Visible = false
					end
				elseif d.tr then
					d.tr.Visible = false
				end
			end
		end
	end
end)

connect(Players.PlayerRemoving, function(p)
	local d = store[p]
	if d then destroyData(d); store[p] = nil end
end)

----------------------------------------------------------------
-- HUD: FPS-плашка + Aimbot (FOV-круг)
----------------------------------------------------------------
local hudGui = new("ScreenGui", {
	Name = "NurHub_HUD", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
mount(hudGui)

local FPS = { on = false, custom = false, value = 999, color = WHITE, x = 0.03, y = 0.03, real = 60 }
local fpsTextViews, fpsPosViews = {}, {}

local fpsBadge = new("TextLabel", {
	BackgroundColor3 = Color3.fromRGB(10, 10, 14), BackgroundTransparency = .4, BorderSizePixel = 0,
	AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.GothamBold, TextSize = 16, Text = "60 FPS",
	TextColor3 = WHITE, Visible = false, AnchorPoint = Vector2.new(FPS.x, FPS.y), Position = UDim2.fromScale(FPS.x, FPS.y),
}, hudGui)
corner(fpsBadge, 6)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
}, fpsBadge)
fpsTextViews[1] = fpsBadge
fpsPosViews[1] = fpsBadge

local function fpsString()
	local n = (FPS.custom and FPS.value) or FPS.real
	return tostring(n) .. " FPS"
end
local function refreshFps()
	local txt = fpsString()
	for _, l in ipairs(fpsTextViews) do
		l.Text = txt
		l.TextColor3 = FPS.color
	end
end
local function applyFpsPos()
	for _, l in ipairs(fpsPosViews) do
		l.AnchorPoint = Vector2.new(FPS.x, FPS.y)
		l.Position = UDim2.fromScale(FPS.x, FPS.y)
	end
end

do
	local frames, acc = 0, 0
	connect(RunService.RenderStepped, function(dt)
		frames += 1
		acc += dt
		if acc >= 0.5 then
			FPS.real = math.floor(frames / acc + 0.5)
			frames, acc = 0, 0
			refreshFps()
		end
	end)
end

-- Aimbot
local Aim = {
	on = false, target = "Head", fov = 150, smooth = 35,
	mode = "Key", key = Enum.KeyCode.E, binding = false,
	visible = true, showFov = false, fovColor = WHITE,
}
local aiming, aimKeyDown = false, false
connect(UIS.InputBegan, function(i, gp)
	-- смена кнопки наводки
	if Aim.binding and i.UserInputType == Enum.UserInputType.Keyboard then
		Aim.binding = false
		Aim.key = i.KeyCode
		if Aim.onKeyChanged then Aim.onKeyChanged() end
		return
	end
	if i.UserInputType == Enum.UserInputType.MouseButton2 then aiming = true end
	if not gp and i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == Aim.key then
		aimKeyDown = true
	end
end)
connect(UIS.InputEnded, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton2 then aiming = false end
	if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == Aim.key then
		aimKeyDown = false
	end
end)

local aimCircle = new("Frame", {
	AnchorPoint = Vector2.new(.5, .5), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
}, hudGui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, aimCircle)
local aimStroke = new("UIStroke", { Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, aimCircle)

local AIM_PARTS = {
	["Head"]      = { "Head" },
	["Torso"]     = { "UpperTorso", "Torso" },
	["Left arm"]  = { "LeftUpperArm", "Left Arm" },
	["Right arm"] = { "RightUpperArm", "Right Arm" },
	["Left leg"]  = { "LeftUpperLeg", "Left Leg" },
	["Right leg"] = { "RightUpperLeg", "Right Leg" },
}
local function aimPartOf(char)
	for _, n in ipairs(AIM_PARTS[Aim.target] or AIM_PARTS.Head) do
		local p = char:FindFirstChild(n)
		if p then return p end
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function touchOnly()
	return UIS.TouchEnabled and not UIS.MouseEnabled
end

local function visibleFrom(cam, part, char)
	local ignore = { char }
	if LP.Character then table.insert(ignore, LP.Character) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local o = cam.CFrame.Position
	return workspace:Raycast(o, part.Position - o, params) == nil
end

local function aimStep(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local ap = touchOnly() and (cam.ViewportSize / 2) or UIS:GetMouseLocation()

	aimCircle.Visible = Aim.on and Aim.showFov
	if aimCircle.Visible then
		aimCircle.Size = UDim2.fromOffset(Aim.fov * 2, Aim.fov * 2)
		aimCircle.Position = UDim2.fromOffset(ap.X, ap.Y)
		aimStroke.Color = Aim.fovColor
	end

	if not Aim.on then return end
	-- активация: на телефоне всегда, на ПК по режиму (клавиша / ПКМ / всегда)
	if not touchOnly() then
		if Aim.mode == "Key" and not aimKeyDown then return end
		if Aim.mode == "RMB" and not aiming then return end
	end

	local best, bestD = nil, Aim.fov
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and plr.Character then
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			local part = aimPartOf(plr.Character)
			if hum and hum.Health > 0 and part then
				local sp, on = cam:WorldToViewportPoint(part.Position)
				if on then
					local dd = (Vector2.new(sp.X, sp.Y) - ap).Magnitude
					if dd < bestD and (not Aim.visible or visibleFrom(cam, part, plr.Character)) then
						best, bestD = part, dd
					end
				end
			end
		end
	end

	if best then
		local cur = cam.CFrame
		local a = 1 - (1 - Aim.smooth / 100) ^ (math.clamp(dt, 0, 0.1) * 60)
		cam.CFrame = cur:Lerp(CFrame.new(cur.Position, best.Position), a)
	end
end
RunService:BindToRenderStep("NurHubAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	pcall(aimStep, dt)
end)

----------------------------------------------------------------
-- WORLD (Lighting + шейдеры + погода)
----------------------------------------------------------------
local orig = {
	Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
	Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, FogColor = Lighting.FogColor,
	GlobalShadows = Lighting.GlobalShadows, ExposureCompensation = Lighting.ExposureCompensation,
}
local cc    = new("ColorCorrectionEffect", { Name = "NH_CC" }, Lighting)
local bloom = new("BloomEffect", { Name = "NH_Bloom", Intensity = 0, Size = 24, Threshold = 2 }, Lighting)
local rays  = new("SunRaysEffect", { Name = "NH_Rays", Intensity = 0, Spread = 0.6 }, Lighting)

local PRESETS = {
	["Sakura"]  = { tint = Color3.fromRGB(255, 226, 236), sat = 0.15, contrast = 0.05, bloom = 0.4, weather = "sakura" },
	["Blood"]   = { tint = Color3.fromRGB(255, 165, 165), sat = 0.1, contrast = 0.2, bright = -0.08, bloom = 0.3, weather = "blood" },
	["4K"]      = { sat = 0.25, contrast = 0.22, bright = 0.02, bloom = 0.5, rays = 0.1 },
	["Snow"]    = { tint = Color3.fromRGB(226, 240, 255), sat = -0.1, bright = 0.05, weather = "snow" },
	["Rain"]    = { tint = Color3.fromRGB(190, 205, 225), sat = -0.2, contrast = 0.1, bright = -0.05, weather = "rain" },
	["Sunset"]  = { tint = Color3.fromRGB(255, 200, 150), sat = 0.25, rays = 0.25, bloom = 0.6 },
	["Neon"]    = { tint = Color3.fromRGB(220, 190, 255), sat = 0.5, contrast = 0.25, bloom = 1.2 },
	["Noir"]    = { sat = -1, contrast = 0.3 },
	["Vintage"] = { tint = Color3.fromRGB(255, 235, 200), sat = -0.25, contrast = 0.1 },
}
local PRESET_LIST = { "Sakura", "Blood", "4K", "Snow", "Rain", "Sunset", "Neon", "Noir", "Vintage" }

local W = {
	shader = false, preset = "4K",
	light = { on = false, val = 0.1, tint = WHITE },
	glow  = { on = false, int = 1, thr = 0.9 },
	dark  = { on = false, val = 0.4 },
	grade = { on = false, sat = 0.2, con = 0.1 },
	fog   = { on = false, val = 0.3, color = Color3.fromRGB(180, 180, 190) },
	rays  = { on = false, val = 0.3 },
	fullbright = false, noshadows = false,
	time  = { on = false, val = 12 },
}

-- частицы погоды
local weatherPart = new("Part", {
	Name = "NH_Weather", Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
	Transparency = 1, Size = Vector3.new(90, 1, 90), CastShadow = false,
})
local weatherEmitters = {}
local WEATHER = {
	snow = function(e)
		e.Rate = 260; e.Lifetime = NumberRange.new(5, 6); e.Speed = NumberRange.new(6, 9)
		e.Size = NumberSequence.new(0.3); e.Color = ColorSequence.new(WHITE)
		e.Transparency = NumberSequence.new(0.1); e.Acceleration = Vector3.new(2, 0, 1)
		e.RotSpeed = NumberRange.new(-60, 60); e.SpreadAngle = Vector2.new(12, 12)
	end,
	rain = function(e)
		e.Rate = 650; e.Lifetime = NumberRange.new(0.4, 0.45); e.Speed = NumberRange.new(95, 110)
		e.Size = NumberSequence.new(0.14); e.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
		e.Transparency = NumberSequence.new(0.35); e.SpreadAngle = Vector2.new(3, 3)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	end,
	sakura = function(e)
		e.Rate = 70; e.Lifetime = NumberRange.new(7, 9); e.Speed = NumberRange.new(3, 6)
		e.Size = NumberSequence.new(0.5); e.Color = ColorSequence.new(Color3.fromRGB(255, 170, 200), Color3.fromRGB(255, 205, 225))
		e.Transparency = NumberSequence.new(0.05); e.Acceleration = Vector3.new(3, 0, 1.5)
		e.RotSpeed = NumberRange.new(-120, 120); e.SpreadAngle = Vector2.new(25, 25)
	end,
	blood = function(e)
		e.Rate = 130; e.Lifetime = NumberRange.new(2.5, 3); e.Speed = NumberRange.new(12, 16)
		e.Size = NumberSequence.new(0.35); e.Color = ColorSequence.new(Color3.fromRGB(170, 0, 10))
		e.Transparency = NumberSequence.new(0.1); e.SpreadAngle = Vector2.new(6, 6)
	end,
}
local function setWeather(kind)
	for k, e in pairs(weatherEmitters) do e.Enabled = (k == kind) end
	if kind then
		if not weatherEmitters[kind] then
			local e = new("ParticleEmitter", {
				EmissionDirection = Enum.NormalId.Bottom, LockedToPart = false,
				Rotation = NumberRange.new(0, 360),
			}, weatherPart)
			WEATHER[kind](e)
			weatherEmitters[kind] = e
		end
		weatherEmitters[kind].Enabled = true
		weatherPart.Parent = workspace.CurrentCamera
	else
		weatherPart.Parent = nil
	end
end

local function applyWorld()
	local p = (W.shader and PRESETS[W.preset]) or {}

	local bright = (p.bright or 0) + (W.light.on and W.light.val or 0) - (W.dark.on and W.dark.val * 0.5 or 0)
	local contrast = (p.contrast or 0) + (W.grade.on and W.grade.con or 0)
	local sat = (p.sat or 0) + (W.grade.on and W.grade.sat or 0)
	local tint = p.tint or WHITE
	if W.light.on then
		tint = Color3.new(tint.R * W.light.tint.R, tint.G * W.light.tint.G, tint.B * W.light.tint.B)
	end
	cc.Brightness = math.clamp(bright, -1, 1)
	cc.Contrast = math.clamp(contrast, -1, 1)
	cc.Saturation = math.clamp(sat, -1, 1)
	cc.TintColor = tint

	bloom.Intensity = (p.bloom or 0) + (W.glow.on and W.glow.int or 0)
	bloom.Threshold = W.glow.on and W.glow.thr or (p.bloom and 1.2 or 2)
	rays.Intensity = math.clamp((p.rays or 0) + (W.rays.on and W.rays.val or 0), 0, 1)

	Lighting.ExposureCompensation = orig.ExposureCompensation - (W.dark.on and W.dark.val * 1.5 or 0)
	Lighting.Brightness = orig.Brightness + (W.fullbright and 2 or 0)
	if W.fullbright then
		Lighting.Ambient = Color3.fromRGB(170, 170, 170)
		Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	else
		Lighting.Ambient = orig.Ambient
		Lighting.OutdoorAmbient = orig.OutdoorAmbient
	end
	if W.fog.on then
		Lighting.FogStart = 0
		Lighting.FogEnd = math.max(30, 2200 * (1 - W.fog.val) ^ 2)
		Lighting.FogColor = W.fog.color
	else
		Lighting.FogStart = orig.FogStart
		Lighting.FogEnd = orig.FogEnd
		Lighting.FogColor = orig.FogColor
	end
	Lighting.GlobalShadows = (not W.noshadows) and orig.GlobalShadows or false
	setWeather(p.weather)
end

connect(RunService.RenderStepped, function()
	local cam = workspace.CurrentCamera
	if weatherPart.Parent and cam then
		weatherPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 38, 0))
	end
	if W.time.on then Lighting.ClockTime = W.time.val end
end)

----------------------------------------------------------------
-- ГЛАВНОЕ ОКНО
----------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "NurHub_UI", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
mount(gui)

local Root = new("Frame", {
	Name = "Root", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
	Size = UDim2.fromOffset(660, 420), BackgroundTransparency = 1, Visible = false,
}, gui)
local userScale = new("UIScale", { Scale = 1 }, Root)
local Anim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, Root)
local animScale = new("UIScale", { Scale = .88 }, Anim)
corner(Anim, 12)
local mainStroke = stroke(Anim, Color3.fromRGB(40, 40, 52), 1, 1)

local Main = new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, GroupTransparency = 1 }, Anim)
regBg(Main, 0)
corner(Main, 12)

-- сайдбар
local Side = new("Frame", { Size = UDim2.new(0, 150, 1, 0), BorderSizePixel = 0 }, Main)
regBg(Side, 0.02)
new("Frame", {
	Position = UDim2.new(0, 150, 0, 0), Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = Color3.fromRGB(32, 32, 40), BorderSizePixel = 0,
}, Main)

new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.new(0, 18, 0, 16), Size = UDim2.new(0, 100, 0, 32),
	Font = Enum.Font.GothamBlack, Text = "NurHub", TextSize = 24, TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
}, Side)
local spark = new("Frame", {
	AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(0, 120, 0, 20), Size = UDim2.fromOffset(6, 6),
	Rotation = 45, BorderSizePixel = 0,
}, Side)
onAccent(function() spark.BackgroundColor3 = Theme.accent end)

new("Frame", {
	Position = UDim2.new(0, 20, 0, 222), Size = UDim2.new(1, -40, 0, 1),
	BackgroundColor3 = Color3.fromRGB(36, 36, 46), BorderSizePixel = 0,
}, Side)
new("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -12),
	Size = UDim2.new(1, -30, 0, 14), Font = Enum.Font.Gotham, Text = "v1.2  •  t.me/NurHuboffical",
	TextSize = 10, TextColor3 = Color3.fromRGB(90, 90, 104), TextXAlignment = Enum.TextXAlignment.Left,
}, Side)

-- зоны перетаскивания
local dragLogo = new("Frame", { Size = UDim2.new(0, 150, 0, 62), BackgroundTransparency = 1 }, Side)
local dragTop = new("Frame", { Position = UDim2.new(0, 151, 0, 0), Size = UDim2.new(1, -151, 0, 14), BackgroundTransparency = 1 }, Main)
makeDraggable(dragLogo, Root)
makeDraggable(dragTop, Root)

local Content = new("Frame", {
	Position = UDim2.new(0, 162, 0, 16), Size = UDim2.new(1, -174, 1, -28), BackgroundTransparency = 1,
}, Main)

-- вкладки
local TABS = { { "Visual", 70 }, { "Combat", 106 }, { "World", 142 }, { "Config", 178 }, { "Setting", 232 }, { "Info", 268 } }
local selector = new("Frame", {
	Position = UDim2.new(0, 10, 0, TABS[1][2]), Size = UDim2.new(1, -20, 0, 32),
	BackgroundColor3 = Color3.fromRGB(30, 30, 40), BorderSizePixel = 0,
}, Side)
corner(selector, 8)
local selBar = new("Frame", {
	AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 5, .5, 0), Size = UDim2.fromOffset(3, 16), BorderSizePixel = 0,
}, selector)
corner(selBar, 2)
onAccent(function() selBar.BackgroundColor3 = Theme.accent end)

local tabBtns, pages, ptok = {}, {}, {}
local current = "Visual"

-- Страница: заголовок «Раздел · Подраздел». single = одна колонка на всю ширину
local function Page(name, sub, single)
	local cg = new("CanvasGroup", {
		Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Visible = false, GroupTransparency = 1,
	}, Content)
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold,
		RichText = true, TextSize = 16, TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
		Text = name .. ' <font color="rgb(140,140,156)">· ' .. sub .. "</font>",
	}, cg)
	local sf = new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Color3.fromRGB(70, 70, 88),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, cg)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingTop = UDim.new(0, 2) }, sf)
	local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, sf)
	pages[name] = cg

	if single then
		local c = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		}, holder)
		new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, c)
		return c
	end

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		VerticalAlignment = Enum.VerticalAlignment.Top, SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	local function col(o)
		local c = new("Frame", {
			Size = UDim2.new(.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, LayoutOrder = o,
		}, holder)
		new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, c)
		return c
	end
	return col(1), col(2)
end

local function switchTab(name)
	if name == current then return end
	local prev = current
	current = name
	ptok[prev] = (ptok[prev] or 0) + 1
	ptok[name] = (ptok[name] or 0) + 1
	local myOld = ptok[prev]

	local old, nextPage = pages[prev], pages[name]
	tw(old, .18, { GroupTransparency = 1, Position = UDim2.new(0, 0, 0, -12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(.2, function()
		if ptok[prev] == myOld and current ~= prev then old.Visible = false end
	end)
	nextPage.Position = UDim2.new(0, 0, 0, 24)
	nextPage.GroupTransparency = 1
	nextPage.Visible = true
	tw(nextPage, .45, { GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0) })

	for _, t in ipairs(TABS) do
		if t[1] == name then tw(selector, .4, { Position = UDim2.new(0, 10, 0, t[2]) }, Enum.EasingStyle.Quart) end
		tw(tabBtns[t[1]], .25, { TextColor3 = (t[1] == name) and WHITE or Theme.sub })
	end
end

for _, t in ipairs(TABS) do
	local b = new("TextButton", {
		Position = UDim2.new(0, 10, 0, t[2]), Size = UDim2.new(1, -20, 0, 32), BackgroundTransparency = 1,
		AutoButtonColor = false, Text = t[1], Font = Enum.Font.GothamMedium, TextSize = 14,
		TextColor3 = (t[1] == current) and WHITE or Theme.sub, TextXAlignment = Enum.TextXAlignment.Left,
	}, Side)
	new("UIPadding", { PaddingLeft = UDim.new(0, 18) }, b)
	tabBtns[t[1]] = b
	b.MouseEnter:Connect(function()
		if current ~= t[1] then tw(b, .15, { TextColor3 = Color3.fromRGB(200, 200, 212) }) end
	end)
	b.MouseLeave:Connect(function()
		if current ~= t[1] then tw(b, .15, { TextColor3 = Theme.sub }) end
	end)
	b.MouseButton1Click:Connect(function() switchTab(t[1]) end)
end

----------------------------------------------------------------
-- VISUAL
----------------------------------------------------------------
do
	local L, R = Page("Visual", "ESP")

	local c1 = Card(L, "ESP")
	Toggle(c1, "Box 2D", false, function(v) ESP.box2d.on = v end, function(dr)
		ColorPicker(dr, WHITE, function(c) ESP.box2d.color = c end, nil, "esp.box2d.color")
	end, "esp.box2d")
	Toggle(c1, "Box 3D", false, function(v) ESP.box3d.on = v end, function(dr)
		ColorPicker(dr, WHITE, function(c) ESP.box3d.color = c end, nil, "esp.box3d.color")
	end, "esp.box3d")
	Toggle(c1, "Skeleton", false, function(v) ESP.skeleton.on = v end, function(dr)
		ColorPicker(dr, WHITE, function(c) ESP.skeleton.color = c end, nil, "esp.skeleton.color")
	end, "esp.skeleton")

	local c3 = Card(L, "Options")
	Slider(c3, "Line thickness", 1, 4, 1.5, 1, function(v) ESP.thickness = v end, nil, "esp.thickness")
	Slider(c3, "Max distance", 100, 5000, 2500, 0, function(v) ESP.maxDist = v end, function(v) return v .. " st" end, "esp.maxdist")

	local c2 = Card(R, "Render")
	Toggle(c2, "Chams", false, function(v) ESP.chams.on = v end, function(dr)
		ColorPicker(dr, WHITE, function(c) ESP.chams.color = c end, nil, "esp.chams.color")
		Slider(dr, "Fill transparency", 0, 1, 0.5, 2, function(v) ESP.chams.transp = v end, nil, "esp.chams.transp")
	end, "esp.chams")
	Toggle(c2, "Outline", false, function(v) ESP.outline.on = v end, function(dr)
		ColorPicker(dr, WHITE, function(c) ESP.outline.color = c end, nil, "esp.outline.color")
	end, "esp.outline")
	Toggle(c2, "Tracers", false, function(v) ESP.tracers.on = v end, function(dr)
		Label(dr, "Line origin", Theme.sub, 11)
		Options(dr, { "Bottom", "Top", "Crosshair" }, "Bottom", function(n) ESP.tracers.origin = n end, 3, "esp.tracers.origin")
		ColorPicker(dr, WHITE, function(c) ESP.tracers.color = c end, nil, "esp.tracers.color")
	end, "esp.tracers")

	-- HUD: FPS
	local ch = Card(R, "HUD")
	Toggle(ch, "Show FPS", false, function(v)
		FPS.on = v
		fpsBadge.Visible = v
	end, function(dr)
		Toggle(dr, "Custom FPS", false, function(v)
			FPS.custom = v
			refreshFps()
		end, nil, "fps.custom")

		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = ord() }, dr)
		local tb = new("TextBox", {
			Size = UDim2.fromOffset(84, 34), BackgroundColor3 = Color3.fromRGB(12, 12, 16), BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 18, Text = "999", PlaceholderText = "FPS",
			PlaceholderColor3 = Theme.sub, ClearTextOnFocus = false, TextColor3 = Theme.accent,
		}, row)
		corner(tb, 8)
		stroke(tb, Color3.fromRGB(46, 46, 58), 1.5)
		onAccent(function() tb.TextColor3 = Theme.accent end)
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 0), Size = UDim2.new(1, -92, 1, 0),
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.sub, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "Drag the badge across the screen",
		}, row)
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			local d = (tb.Text:gsub("%D", ""))
			if #d > 5 then d = d:sub(1, 5) end
			if d ~= tb.Text then tb.Text = d end
			FPS.value = tonumber(d)
			refreshFps()
		end)
		register("fps.value", "number", function() return FPS.value or 999 end, function(v) tb.Text = tostring(math.floor(tonumber(v) or 999)) end)

		-- 2D экран: перетаскивай плашку, куда поставить FPS
		local preview = new("Frame", {
			Size = UDim2.new(1, 0, 0, 96), BorderSizePixel = 0, BackgroundColor3 = WHITE,
			ClipsDescendants = true, LayoutOrder = ord(),
		}, dr)
		corner(preview, 8)
		stroke(preview, Color3.fromRGB(46, 46, 60), 1.5)
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 42, 80)),
				ColorSequenceKeypoint.new(.75, Color3.fromRGB(16, 16, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 24)),
			}),
		}, preview)
		local pbadge = new("TextButton", {
			AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(10, 10, 14), BackgroundTransparency = .35,
			BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.GothamBold, TextSize = 12,
			Text = "60 FPS", TextColor3 = WHITE,
		}, preview)
		corner(pbadge, 5)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
		}, pbadge)
		fpsTextViews[#fpsTextViews + 1] = pbadge
		fpsPosViews[#fpsPosViews + 1] = pbadge
		applyFpsPos()
		refreshFps()

		local pdrag, grab, scroller = false, Vector2.zero, nil
		pbadge.InputBegan:Connect(function(i)
			if isPress(i) then
				pdrag = true
				grab = Vector2.new(i.Position.X, i.Position.Y) - pbadge.AbsolutePosition
				scroller = pbadge:FindFirstAncestorOfClass("ScrollingFrame")
				if scroller then scroller.ScrollingEnabled = false end
			end
		end)
		connect(UIS.InputChanged, function(i)
			if pdrag and isMove(i) then
				local rel = Vector2.new(i.Position.X, i.Position.Y) - preview.AbsolutePosition - grab
				local free = preview.AbsoluteSize - pbadge.AbsoluteSize
				FPS.x = math.clamp(rel.X / math.max(free.X, 1), 0, 1)
				FPS.y = math.clamp(rel.Y / math.max(free.Y, 1), 0, 1)
				applyFpsPos()
			end
		end)
		connect(UIS.InputEnded, function(i)
			if pdrag and isPress(i) then
				pdrag = false
				if scroller then scroller.ScrollingEnabled = true end
			end
		end)
		register("fps.x", "number", function() return FPS.x end, function(v) FPS.x = math.clamp(tonumber(v) or 0, 0, 1); applyFpsPos() end)
		register("fps.y", "number", function() return FPS.y end, function(v) FPS.y = math.clamp(tonumber(v) or 0, 0, 1); applyFpsPos() end)

		ColorPicker(dr, WHITE, function(c)
			FPS.color = c
			refreshFps()
		end, nil, "fps.color")
	end, "fps.on")
end

----------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------
do
	local C = Page("Combat", "Aimbot", true)
	local card = Card(C, nil)
	Toggle(card, "Aimbot", false, function(v) Aim.on = v end, function(dr)
		TargetPicker(dr, "Head", function(n) Aim.target = n end, "aim.target")
		Slider(dr, "FOV", 30, 500, 150, 0, function(v) Aim.fov = v end, nil, "aim.fov")
		Slider(dr, "Speed", 1, 100, 35, 0, function(v) Aim.smooth = v end, function(v) return v .. "%" end, "aim.smooth")
		Label(dr, "Activation (PC)", Theme.sub, 11)
		Options(dr, { "Key", "RMB", "Always" }, "Key", function(n) Aim.mode = n end, 3, "aim.mode")
		local aimKeyBtn = Button(dr, "Aim key: " .. Aim.key.Name, function(b)
			Aim.binding = true
			b.Text = "Press any key..."
		end)
		Aim.onKeyChanged = function() aimKeyBtn.Text = "Aim key: " .. Aim.key.Name end
		register("aim.key", "string", function() return Aim.key.Name end, function(n)
			local ok, kc = pcall(function() return Enum.KeyCode[n] end)
			if ok and kc then
				Aim.key = kc
				Aim.onKeyChanged()
			end
		end)
		Toggle(dr, "Visible check", true, function(v) Aim.visible = v end, nil, "aim.visible")
		Toggle(dr, "Show FOV circle", false, function(v) Aim.showFov = v end, function(d2)
			ColorPicker(d2, WHITE, function(c) Aim.fovColor = c end, nil, "aim.fovcolor")
		end, "aim.showfov")
	end, "aim.on")
end

----------------------------------------------------------------
-- WORLD
----------------------------------------------------------------
do
	local L, R = Page("World", "Lighting")

	local cs = Card(L, "Shader")
	Toggle(cs, "Shader", false, function(v) W.shader = v; applyWorld() end, function(dr)
		Options(dr, PRESET_LIST, "4K", function(n) W.preset = n; applyWorld() end, 2, "w.preset")
	end, "w.shader")

	local ct = Card(L, "Time of day")
	Toggle(ct, "Custom time", false, function(v)
		W.time.on = v
		if not v then Lighting.ClockTime = orig.ClockTime end
	end, function(dr)
		Slider(dr, "Time", 0, 24, 12, 1, function(val) W.time.val = val end, function(val)
			local hh = math.floor(val) % 24
			local mm = math.floor((val - math.floor(val)) * 60)
			return string.format("%02d:%02d", hh, mm)
		end, "w.time.val")
	end, "w.time.on")

	local cl = Card(R, "Lighting")
	Toggle(cl, "Light correction", false, function(v) W.light.on = v; applyWorld() end, function(dr)
		Slider(dr, "Brightness", -0.5, 0.5, 0.1, 2, function(v) W.light.val = v; applyWorld() end, nil, "w.light.val")
		ColorPicker(dr, WHITE, function(c) W.light.tint = c; applyWorld() end, nil, "w.light.tint")
	end, "w.light.on")
	Toggle(cl, "Glow", false, function(v) W.glow.on = v; applyWorld() end, function(dr)
		Slider(dr, "Intensity", 0, 3, 1, 2, function(v) W.glow.int = v; applyWorld() end, nil, "w.glow.int")
		Slider(dr, "Threshold", 0, 2, 0.9, 2, function(v) W.glow.thr = v; applyWorld() end, nil, "w.glow.thr")
	end, "w.glow.on")
	Toggle(cl, "Darkness", false, function(v) W.dark.on = v; applyWorld() end, function(dr)
		Slider(dr, "Strength", 0, 1, 0.4, 2, function(v) W.dark.val = v; applyWorld() end, nil, "w.dark.val")
	end, "w.dark.on")
	Toggle(cl, "Color grading", false, function(v) W.grade.on = v; applyWorld() end, function(dr)
		Slider(dr, "Saturation", -1, 1, 0.2, 2, function(v) W.grade.sat = v; applyWorld() end, nil, "w.grade.sat")
		Slider(dr, "Contrast", -1, 1, 0.1, 2, function(v) W.grade.con = v; applyWorld() end, nil, "w.grade.con")
	end, "w.grade.on")
	Toggle(cl, "Fog", false, function(v) W.fog.on = v; applyWorld() end, function(dr)
		Slider(dr, "Density", 0, 1, 0.3, 2, function(v) W.fog.val = v; applyWorld() end, nil, "w.fog.val")
		ColorPicker(dr, W.fog.color, function(c) W.fog.color = c; applyWorld() end, nil, "w.fog.color")
	end, "w.fog.on")
	Toggle(cl, "Sun rays", false, function(v) W.rays.on = v; applyWorld() end, function(dr)
		Slider(dr, "Intensity", 0, 1, 0.3, 2, function(v) W.rays.val = v; applyWorld() end, nil, "w.rays.val")
	end, "w.rays.on")
	Toggle(cl, "Full bright", false, function(v) W.fullbright = v; applyWorld() end, nil, "w.fullbright")
	Toggle(cl, "No shadows", false, function(v) W.noshadows = v; applyWorld() end, nil, "w.noshadows")
end

----------------------------------------------------------------
-- CONFIG (5 слотов)
----------------------------------------------------------------
do
	local L, R = Page("Config", "Configs")
	local MAX = 5
	local CFG_FILE = "NurHub_configs.json"
	local canFS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"

	local function readSlots()
		if canFS then
			local ok, res = pcall(function()
				if isfile(CFG_FILE) then return HttpService:JSONDecode(readfile(CFG_FILE)) end
			end)
			if ok and type(res) == "table" then return res end
		end
		return ENV.NurHubSlots or {}
	end
	local slots = readSlots()
	local function writeSlots()
		ENV.NurHubSlots = slots
		if canFS then pcall(writefile, CFG_FILE, HttpService:JSONEncode(slots)) end
	end
	local function count()
		local n = 0
		for i = 1, MAX do if slots[tostring(i)] then n += 1 end end
		return n
	end

	-- левая карточка: новый конфиг
	local cn = Card(L, "New config", true)
	Label(cn, "Save your current settings under a name", Theme.sub, 11)
	local nameBox = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(12, 12, 16), BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.text, Text = "",
		PlaceholderText = "Config name...", PlaceholderColor3 = Theme.sub, ClearTextOnFocus = false,
		LayoutOrder = ord(),
	}, cn)
	corner(nameBox, 8)
	stroke(nameBox, Color3.fromRGB(46, 46, 58), 1.5)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #nameBox.Text > 16 then nameBox.Text = nameBox.Text:sub(1, 16) end
	end)

	local saveBtn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = WHITE, BorderSizePixel = 0, AutoButtonColor = false,
		Font = Enum.Font.GothamBold, TextSize = 13, Text = "Save", TextColor3 = Color3.fromRGB(18, 18, 40),
		LayoutOrder = ord(),
	}, cn)
	corner(saveBtn, 8)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(180, 90, 255), Color3.fromRGB(60, 130, 255)),
	}, saveBtn)
	local slotsLbl = Label(cn, "Slots: 0 / " .. MAX, Theme.sub, 12)
	local status = Label(cn, "", Theme.sub, 11)

	-- правая карточка: сохранённые
	local cs = Card(R, "Saved", true)
	local rows = {}
	local renderSlots

	local function flash(stroke_)
		tw(stroke_, .12, { Color = Theme.accent })
		task.delay(.4, function() tw(stroke_, .4, { Color = Color3.fromRGB(46, 46, 58) }) end)
	end

	for i = 1, MAX do
		local key = tostring(i)
		local btn = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", LayoutOrder = ord(),
		}, cs)
		corner(btn, 9)
		local st = stroke(btn, Color3.fromRGB(46, 46, 58), 1.5)
		local num = new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(14, 40),
			Font = Enum.Font.GothamBold, Text = tostring(i), TextSize = 12, TextColor3 = Theme.sub,
		}, btn)
		local nm = new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -78, 1, 0),
			Font = Enum.Font.GothamMedium, Text = "— empty —", TextSize = 13, TextColor3 = Color3.fromRGB(70, 70, 84),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}, btn)
		local del = new("TextButton", {
			AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Color3.fromRGB(34, 34, 44), BorderSizePixel = 0, AutoButtonColor = false,
			Font = Enum.Font.GothamBold, Text = "×", TextSize = 16, TextColor3 = Theme.sub, Visible = false,
		}, btn)
		corner(del, 7)
		del.MouseEnter:Connect(function() tw(del, .15, { BackgroundColor3 = RED, TextColor3 = WHITE }) end)
		del.MouseLeave:Connect(function() tw(del, .15, { BackgroundColor3 = Color3.fromRGB(34, 34, 44), TextColor3 = Theme.sub }) end)

		btn.MouseEnter:Connect(function()
			if slots[key] then tw(btn, .15, { BackgroundColor3 = Color3.fromRGB(20, 20, 26) }) end
		end)
		btn.MouseLeave:Connect(function() tw(btn, .15, { BackgroundColor3 = Color3.fromRGB(14, 14, 18) }) end)

		btn.MouseButton1Click:Connect(function()
			local s = slots[key]
			if s then
				applySnapshot(s.data or {})
				status.Text = "Loaded: " .. s.name
				flash(st)
			end
		end)
		del.MouseButton1Click:Connect(function()
			local s = slots[key]
			if s then
				slots[key] = nil
				writeSlots()
				status.Text = "Deleted: " .. s.name
				renderSlots()
			end
		end)
		rows[i] = { num = num, nm = nm, del = del, st = st }
	end

	function renderSlots()
		for i = 1, MAX do
			local s = slots[tostring(i)]
			local r = rows[i]
			if s then
				r.nm.Text = s.name
				r.nm.TextColor3 = Theme.text
				r.num.TextColor3 = Theme.text
				r.del.Visible = true
			else
				r.nm.Text = "— empty —"
				r.nm.TextColor3 = Color3.fromRGB(70, 70, 84)
				r.num.TextColor3 = Theme.sub
				r.del.Visible = false
			end
		end
		slotsLbl.Text = "Slots: " .. count() .. " / " .. MAX
	end

	saveBtn.MouseButton1Click:Connect(function()
		local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			status.Text = "Enter a name first"
			return
		end
		local slot
		for i = 1, MAX do
			local s = slots[tostring(i)]
			if s and s.name:lower() == name:lower() then slot = i break end
		end
		if not slot then
			for i = 1, MAX do
				if not slots[tostring(i)] then slot = i break end
			end
		end
		if not slot then
			status.Text = "No free slots (" .. MAX .. " / " .. MAX .. ")"
			return
		end
		slots[tostring(slot)] = { name = name, data = snapshot() }
		writeSlots()
		nameBox.Text = ""
		status.Text = "Saved: " .. name .. (canFS and "" or "  (memory only)")
		renderSlots()
		flash(rows[slot].st)
	end)
	renderSlots()
end

----------------------------------------------------------------
-- SETTING
----------------------------------------------------------------
local menuKey = Enum.KeyCode.RightShift
local binding = false
local setMenu, unload

do
	local L, R = Page("Setting", "Menu")

	local cm = Card(L, "Menu")
	DrawerRow(cm, "Menu size", function(dr)
		Slider(dr, "Scale", 70, 130, 100, 0, function(v) userScale.Scale = v / 100 end, function(v) return v .. "%" end, "menu.scale")
	end)
	DrawerRow(cm, "Transparency", function(dr)
		Slider(dr, "Amount", 0, 60, 0, 0, function(v) menuTrans = v / 100; applyBg() end, function(v) return v .. "%" end, "menu.trans")
	end)
	DrawerRow(cm, "Colors", function(dr)
		Label(dr, "Accent color", Theme.sub, 11)
		ColorPicker(dr, Theme.accent, function(c) setAccent(c) end, nil, "menu.accent")
		Label(dr, "Menu color", Theme.sub, 11)
		ColorPicker(dr, menuColor, function(c) menuColor = c; applyBg() end, DARKS, "menu.color")
	end)

	local cx = Card(R, "Misc")
	local keyBtn
	keyBtn = Button(cx, "Menu key: RightShift", function(b)
		binding = true
		b.Text = "Press any key..."
	end)
	register("menu.key", "string", function() return menuKey.Name end, function(n)
		local ok, kc = pcall(function() return Enum.KeyCode[n] end)
		if ok and kc then
			menuKey = kc
			keyBtn.Text = "Menu key: " .. kc.Name
		end
	end)
	connect(UIS.InputBegan, function(i, gp)
		if binding and i.UserInputType == Enum.UserInputType.Keyboard then
			binding = false
			menuKey = i.KeyCode
			keyBtn.Text = "Menu key: " .. i.KeyCode.Name
			return
		end
		if not gp and i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == menuKey then
			setMenu(not Root.Visible or Main.GroupTransparency > 0.5)
		end
	end)
	Button(cx, "Unload NurHub", function() unload() end)
end

----------------------------------------------------------------
-- INFO
----------------------------------------------------------------
do
	local L, R = Page("Info", "About")
	local ca = Card(L, "About")
	Label(ca, "NurHub v1.2", Theme.text, 13)
	Label(ca, "Visual, Combat, World, Config and Setting modules.", Theme.sub, 12)

	local cg = Card(R, "Telegram")
	Label(cg, "t.me/NurHuboffical", Theme.text, 13)
	Button(cg, "Copy link", function(b)
		local fn = (typeof(setclipboard) == "function" and setclipboard) or (typeof(toclipboard) == "function" and toclipboard)
		local ok = fn and pcall(fn, TG_LINK)
		b.Text = ok and "Copied!" or TG_LINK
		task.delay(1.6, function() if b.Parent then b.Text = "Copy link" end end)
	end)
	Button(cg, "Open Telegram", function()
		pcall(function() GuiService:OpenBrowserWindow(TG_LINK) end)
	end)
end

----------------------------------------------------------------
-- Открытие / закрытие меню + кнопка NH
----------------------------------------------------------------
local menuOpen = false
local menuTok = 0
function setMenu(open)
	if menuOpen == open then return end
	menuOpen = open
	menuTok += 1
	local my = menuTok
	if open then
		Root.Visible = true
		tw(Main, .4, { GroupTransparency = 0 })
		tw(mainStroke, .4, { Transparency = 0 })
		tw(animScale, .5, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		tw(Main, .25, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw(mainStroke, .25, { Transparency = 1 })
		tw(animScale, .28, { Scale = .88 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(.3, function()
			if menuTok == my then Root.Visible = false end
		end)
	end
end

-- начальное состояние страницы
pages[current].Visible = true
pages[current].GroupTransparency = 0

-- кнопка NH
local OpenBtn = new("Frame", {
	Name = "NH_Button", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(0, 46, .5, 0),
	Size = UDim2.fromOffset(50, 50), BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
}, gui)
corner(OpenBtn, 16)
local btnScale = new("UIScale", { Scale = 1 }, OpenBtn)
local btnStroke = stroke(OpenBtn, WHITE, 2)
local btnGrad = new("UIGradient", {}, btnStroke)
onAccent(function()
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.accent),
		ColorSequenceKeypoint.new(.5, WHITE),
		ColorSequenceKeypoint.new(1, Theme.accent),
	})
end)
local letterN = new("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(.5, 1, .5, 0),
	Size = UDim2.fromOffset(20, 24), Font = Enum.Font.GothamBlack, Text = "N", TextSize = 20, TextColor3 = WHITE,
}, OpenBtn)
local letterH = new("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(.5, -1, .5, 0),
	Size = UDim2.fromOffset(20, 24), Font = Enum.Font.GothamBlack, Text = "H", TextSize = 20, TextColor3 = WHITE,
}, OpenBtn)
local hitBtn = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1) }, OpenBtn)
makeDraggable(hitBtn, OpenBtn, function() setMenu(not menuOpen) end)
hitBtn.MouseEnter:Connect(function() tw(btnScale, .25, { Scale = 1.1 }, Enum.EasingStyle.Back) end)
hitBtn.MouseLeave:Connect(function() tw(btnScale, .25, { Scale = 1 }, Enum.EasingStyle.Back) end)
hitBtn.MouseButton1Down:Connect(function() tw(btnScale, .12, { Scale = .92 }) end)
hitBtn.MouseButton1Up:Connect(function() tw(btnScale, .2, { Scale = 1.1 }, Enum.EasingStyle.Back) end)

connect(RunService.RenderStepped, function()
	local t = os.clock()
	local off = math.sin(t * 2.4) * 4
	letterN.Position = UDim2.new(.5, 1 + math.cos(t * 2.4) * 2, .5, off)
	letterH.Position = UDim2.new(.5, -1 - math.cos(t * 2.4) * 2, .5, -off)
	btnGrad.Rotation = (t * 120) % 360
end)

----------------------------------------------------------------
-- Выгрузка
----------------------------------------------------------------
function unload()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() RunService:UnbindFromRenderStep("NurHubAim") end)
	for _, d in pairs(store) do destroyData(d) end
	pcall(function() for k, v in pairs(orig) do Lighting[k] = v end end)
	pcall(function() cc:Destroy(); bloom:Destroy(); rays:Destroy(); weatherPart:Destroy() end)
	pcall(function() espGui:Destroy() end)
	pcall(function() hudGui:Destroy() end)
	pcall(function() gui:Destroy() end)
end

setMenu(true)
