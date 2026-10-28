--[[
    Beagleware UI Library  v1.0.1

    Components : Toggle (+keybind), Keybind, Button, Dropdown, MultiDropdown,
                 Colorpicker, Textbox, Slider, Image, Label, Separator
    Features   : Animated window, collapsible sidebar groups, global search,
                 draggable sections (drag anywhere / off the window, drop back
                 on the window to reset), config save/load, live accent theme,
                 full teardown on re-execute (no leftover GUIs or connections).

    v1.0.1     : Fixed nil-length crash in dropdown render, dropdowns now expand
                 inline (push content down), cleaned up padding/spacing.

    Usage      : local Library = loadstring(readfile("BeaglewareUI.lua"))()
                 local Window  = Library:CreateWindow({ Title = "Beagleware" })
]]

----------------------------------------------------------------------
-- Services / constants
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local env         = (getgenv and getgenv()) or _G

local GUI_NAME   = "BeaglewareUI"
local CONFIG_DIR = "Beagleware"
local TITLE_H    = 48
local SIDE_W     = 150

-- Layout constants
local BODY_PAD_Y  = 12
local BODY_PAD_X  = 14
local ELEMENT_GAP = 8
local DD_H        = 52   -- closed dropdown / textbox row height
local DD_GAP      = 4    -- gap between dropdown box and its list

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local T = {
    Background   = Color3.fromRGB(16, 16, 19),
    Card         = Color3.fromRGB(22, 22, 26),
    Element      = Color3.fromRGB(30, 30, 35),
    ElementHover = Color3.fromRGB(39, 39, 46),
    Stroke       = Color3.fromRGB(38, 38, 45),
    Text         = Color3.fromRGB(236, 236, 242),
    SubText      = Color3.fromRGB(128, 128, 140),
    Off          = Color3.fromRGB(42, 42, 49),
    KnobOff      = Color3.fromRGB(122, 122, 132),
    Accent       = Color3.fromRGB(247, 168, 200),
}

local FONT, FONT_BOLD = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- Library table + class tables
----------------------------------------------------------------------
local Library = {
    Version = "1.0.1",
    Theme = T,
    Flags = {},
    Options = {},
    _binds = {},
    _accentFns = {},
    _zCounter = 10,
}

local Window      = {}; Window.__index = Window
local Category    = {}; Category.__index = Category
local Tab         = {}; Tab.__index = Tab
local Section     = {}; Section.__index = Section
local ElementBase = {}; ElementBase.__index = ElementBase

----------------------------------------------------------------------
-- Maid (tracks every global connection so nothing leaks)
----------------------------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new() return setmetatable({ _tasks = {} }, Maid) end

local function Dispose(t)
    local ty = typeof(t)
    if ty == "RBXScriptConnection" then t:Disconnect()
    elseif ty == "Instance" then t:Destroy()
    elseif ty == "function" then pcall(t)
    elseif ty == "table" and t.Destroy then pcall(t.Destroy, t) end
end

function Maid:Give(t) self._tasks[t] = true; return t end
function Maid:Clean(t) if self._tasks[t] then self._tasks[t] = nil; Dispose(t) end end
function Maid:Destroy()
    local tasks = self._tasks
    self._tasks = {}
    for t in pairs(tasks) do Dispose(t) end
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------
local DEFAULTS = {
    Frame       = { BorderSizePixel = 0 },
    CanvasGroup = { BorderSizePixel = 0 },
    ImageLabel  = { BorderSizePixel = 0, BackgroundTransparency = 1 },
    TextLabel   = { BorderSizePixel = 0, BackgroundTransparency = 1, Font = FONT, TextSize = 13,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left },
    TextButton  = { BorderSizePixel = 0, BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
                    Font = FONT, TextSize = 13, TextColor3 = T.Text },
    TextBox     = { BorderSizePixel = 0, BackgroundTransparency = 1, Font = FONT, TextSize = 13,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false },
    ScrollingFrame = { BorderSizePixel = 0, BackgroundTransparency = 1, ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Color3.fromRGB(70, 70, 80), CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
                    ElasticBehavior = Enum.ElasticBehavior.Never },
}

local function New(class, props, children)
    local inst = Instance.new(class)
    local d = DEFAULTS[class]
    if d then for k, v in pairs(d) do inst[k] = v end end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    inst.Parent = parent
    return inst
end

local function Corner(r) return New("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function Stroke(color, transparency, thickness)
    return New("UIStroke", {
        Color = color or T.Stroke, Transparency = transparency or 0, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end
local function Pad(t, r, b, l)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r or t),
        PaddingBottom = UDim.new(0, b or t), PaddingLeft = UDim.new(0, l or r or t),
    })
end
local function List(padding)
    return New("UIListLayout", { Padding = UDim.new(0, padding or 0), SortOrder = Enum.SortOrder.LayoutOrder })
end

local function Tween(inst, props, time, style, dir)
    local tw = TweenService:Create(inst,
        TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function Inside(gui, p)
    local a, s = gui.AbsolutePosition, gui.AbsoluteSize
    return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local KEY_ALIASES = {
    LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
    LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backspace = "Bksp", Escape = "Esc",
    Delete = "Del", Insert = "Ins", PageUp = "PgUp", PageDown = "PgDn", CapsLock = "Caps",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7",
    Eight = "8", Nine = "9",
}
local function KeyName(key) return key and (KEY_ALIASES[key.Name] or key.Name) or "-" end

local function ResolveImage(v)
    if type(v) == "number" then return "rbxassetid://" .. v end
    return v or ""
end

-- Drawn icons (no asset dependencies)
local Icons = {}
function Icons.Chevron(parent, color)
    local root = New("Frame", { Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14), Parent = parent })
    for _, d in ipairs({ { 4, 45 }, { 10, -45 } }) do
        New("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(d[1], 6), Size = UDim2.fromOffset(8, 2), Rotation = d[2], Parent = root },
            { Corner(1) })
    end
    return root
end
function Icons.Cross(parent, color)
    local root = New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), Parent = parent })
    for _, r in ipairs({ 45, -45 }) do
        New("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(13, 2), Rotation = r, Parent = root }, { Corner(1) })
    end
    return root
end
function Icons.Minus(parent, color)
    return New("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 2), Parent = parent }, { Corner(1) })
end
function Icons.Search(parent, color)
    local root = New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16), Parent = parent })
    New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(10, 10), Parent = root },
        { New("UICorner", { CornerRadius = UDim.new(1, 0) }), Stroke(color, 0, 2) })
    New("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(12, 12),
        Size = UDim2.fromOffset(6, 2), Rotation = 45, Parent = root }, { Corner(1) })
    return root
end

-- Animated collapse for AutomaticSize frames. `owner.Collapsed` tracks state.
local function AnimateCollapse(owner, frame, layout, extra, collapsed)
    owner.Collapsed = collapsed
    frame.ClipsDescendants = true
    if collapsed then
        local h = frame.AbsoluteSize.Y
        frame.AutomaticSize = Enum.AutomaticSize.None
        frame.Size = UDim2.new(1, 0, 0, h)
        Tween(frame, { Size = UDim2.new(1, 0, 0, 0) }, 0.25)
    else
        local target = layout.AbsoluteContentSize.Y + extra
        local tw = Tween(frame, { Size = UDim2.new(1, 0, 0, target) }, 0.25)
        tw.Completed:Connect(function()
            if not owner.Collapsed then
                frame.AutomaticSize = Enum.AutomaticSize.Y
                frame.Size = UDim2.new(1, 0, 0, 0)
            end
        end)
    end
end

local function Ripple(btn)
    local rel = UserInputService:GetMouseLocation() - btn.AbsolutePosition
    local d = btn.AbsoluteSize.X * 1.5
    local r = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rel.X, rel.Y),
        Size = UDim2.fromOffset(0, 0), BackgroundColor3 = T.Accent, BackgroundTransparency = 0.7, Parent = btn },
        { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    Tween(r, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 }, 0.55).Completed:Connect(function() r:Destroy() end)
end

----------------------------------------------------------------------
-- Teardown of any previous run
----------------------------------------------------------------------
local function GuiParents()
    local parents = {}
    if gethui then pcall(function() table.insert(parents, gethui()) end) end
    pcall(function() table.insert(parents, CoreGui) end)
    pcall(function() table.insert(parents, LocalPlayer:FindFirstChildOfClass("PlayerGui")) end)
    return parents
end

local function Sweep()
    for _, p in ipairs(GuiParents()) do
        pcall(function()
            for _, c in ipairs(p:GetChildren()) do
                if c.Name == GUI_NAME then c:Destroy() end
            end
        end)
    end
end

local function Mount(gui)
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
    for _, p in ipairs(GuiParents()) do
        if pcall(function() gui.Parent = p end) and gui.Parent then return end
    end
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

if env.__BeaglewareUI then
    pcall(function() env.__BeaglewareUI:Unload() end)
    env.__BeaglewareUI = nil
end
Sweep()

----------------------------------------------------------------------
-- Library core
----------------------------------------------------------------------
function Library:_safe(fn, ...)
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then warn("[Beagleware] callback error: " .. tostring(err)) end
    end)
end

function Library:OnUnload(fn) if self._maid then self._maid:Give(fn) end end

function Library:Unload()
    if self._maid then self._maid:Destroy(); self._maid = nil end
    if self.Gui then pcall(function() self.Gui:Destroy() end); self.Gui = nil end
    self._popup, self._listening, self.Window = nil, nil, nil
    self.Flags, self.Options, self._binds, self._accentFns = {}, {}, {}, {}
    if env.__BeaglewareUI == self then env.__BeaglewareUI = nil end
end

function Library:_accent(fn)
    table.insert(self._accentFns, fn)
    pcall(fn, T.Accent)
end

function Library:SetAccent(color)
    T.Accent = color
    for _, fn in ipairs(self._accentFns) do pcall(fn, color) end
end

function Library:_emit(obj, silent)
    if obj.Flag then self.Flags[obj.Flag] = obj.Value end
    if silent then return end
    if obj.Callback then self:_safe(obj.Callback, obj.Value) end
    for _, fn in ipairs(obj._listeners) do self:_safe(fn, obj.Value) end
end

function Library:_init(obj)
    if obj.Flag then self.Flags[obj.Flag] = obj.Value end
    if obj.Callback and obj.Value ~= nil then
        task.defer(function() pcall(obj.Callback, obj.Value) end)
    end
end

-- Generic pointer drag (windows, sliders, pickers, section dragging)
function Library:_pointerDrag(handle, cfg)
    local maid = self._maid
    handle.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        if cfg.CanStart and not cfg.CanStart() then return end
        local threshold = cfg.Threshold or 0
        local start = UserInputService:GetMouseLocation()
        local dragging = false
        local loop, ender

        local function begin()
            dragging = true
            if cfg.OnBegin then cfg.OnBegin(start) end
        end
        if threshold == 0 then
            begin()
            if cfg.OnMove then cfg.OnMove(start, start, 0) end
        end

        loop = maid:Give(RunService.RenderStepped:Connect(function(dt)
            local pos = UserInputService:GetMouseLocation()
            if not dragging then
                if (pos - start).Magnitude < threshold then return end
                begin()
            end
            if cfg.OnMove then cfg.OnMove(pos, start, dt) end
        end))
        ender = maid:Give(input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                maid:Clean(loop); maid:Clean(ender)
                if cfg.OnEnd then cfg.OnEnd(UserInputService:GetMouseLocation(), dragging) end
            end
        end))
    end)
end

-- Popups. Two kinds:
--   * overlay popups (colorpicker) live in a top layer so nothing clips them
--   * inline popups (dropdowns) set p.Inline = true and provide p.Open / p.Close;
--     they expand inside the layout and push other elements down.
function Library:_placePopup(p)
    local a = p.Anchor
    local pos, sz = a.AbsolutePosition, a.AbsoluteSize
    local vp = self.Gui.AbsoluteSize
    local x = p.AlignRight and (pos.X + sz.X - p._w) or pos.X
    local y = pos.Y + sz.Y + 4
    x = math.clamp(x, 4, math.max(4, vp.X - p._w - 4))
    y = math.min(y, vp.Y - p.Height - 8)
    p.Frame.Position = UDim2.fromOffset(x, y)
end

function Library:_openPopup(p)
    if self._popup == p then return end
    if self._popup then self:_closePopup() end
    self._popup = p

    if p.Inline then
        if p.Open then p.Open() end
        return
    end

    p._token = (p._token or 0) + 1
    p._w = p.Width or p.Anchor.AbsoluteSize.X
    p.Frame.Size = UDim2.fromOffset(p._w, 0)
    p.Frame.Visible = true
    self:_placePopup(p)
    Tween(p.Frame, { Size = UDim2.fromOffset(p._w, p.Height) }, 0.22)
    p._conn = self._maid:Give(RunService.RenderStepped:Connect(function()
        if not p.Anchor:IsDescendantOf(self.Gui) then self:_closePopup() return end
        self:_placePopup(p)
    end))
    if p.OnOpen then p.OnOpen() end
end

function Library:_closePopup()
    local p = self._popup
    if not p then return end
    self._popup = nil

    if p.Inline then
        if p.Close then p.Close() end
        return
    end

    if p._conn then self._maid:Clean(p._conn); p._conn = nil end
    local token = p._token
    Tween(p.Frame, { Size = UDim2.fromOffset(p._w, 0) }, 0.16).Completed:Connect(function()
        if p._token == token and self._popup ~= p then p.Frame.Visible = false end
    end)
    if p.OnClose then p.OnClose() end
end

function Library:_newPopupFrame()
    return New("Frame", { Name = "Popup", BackgroundColor3 = T.Card, Size = UDim2.fromOffset(0, 0), Visible = false,
        ClipsDescendants = true, Active = true, Parent = self.PopupLayer }, { Corner(6), Stroke(T.Stroke) })
end

-- Keybinds
function Library:_newBind(default, callback)
    local bind = { Key = default, Callback = callback }
    function bind:Set(key)
        self.Key = key
        if self.Refresh then self.Refresh() end
        if self.Changed then self.Changed(key) end
    end
    table.insert(self._binds, bind)
    return bind
end

function Library:_bindButton(parent, bind, position)
    local btn = New("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = position, Size = UDim2.fromOffset(44, 20),
        BackgroundTransparency = 0, BackgroundColor3 = T.Element, TextSize = 11, TextColor3 = T.SubText, Parent = parent },
        { Corner(5), Stroke(T.Stroke) })
    bind.Refresh = function()
        btn.Text = KeyName(bind.Key)
        Tween(btn, { TextColor3 = T.SubText }, 0.15)
    end
    bind.Refresh()
    btn.MouseEnter:Connect(function() Tween(btn, { BackgroundColor3 = T.ElementHover }, 0.12) end)
    btn.MouseLeave:Connect(function() Tween(btn, { BackgroundColor3 = T.Element }, 0.12) end)
    btn.MouseButton1Click:Connect(function()
        Library._listening = bind
        btn.Text = "..."
        Tween(btn, { TextColor3 = T.Accent }, 0.15)
    end)
    return btn
end

----------------------------------------------------------------------
-- Configs
----------------------------------------------------------------------
local function FSReady() return writefile and readfile and isfolder and makefolder and listfiles and isfile end
local function EnsureDir() if FSReady() and not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end end

function Library:ListConfigs()
    local out = {}
    if not FSReady() then return out end
    EnsureDir()
    for _, path in ipairs(listfiles(CONFIG_DIR)) do
        local name = path:match("([^/\\]+)%.json$")
        if name then table.insert(out, name) end
    end
    table.sort(out)
    return out
end

function Library:SaveConfig(name)
    if not FSReady() or not name or name == "" then return false end
    EnsureDir()
    local data = {}
    for flag, obj in pairs(self.Options) do
        if obj._export then data[flag] = obj._export() end
    end
    writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    return true
end

function Library:LoadConfig(name)
    if not FSReady() or not name then return false end
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if not isfile(path) then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok then return false end
    for flag, value in pairs(data) do
        local obj = self.Options[flag]
        if obj and obj._import then pcall(obj._import, value) end
    end
    return true
end

function Library:DeleteConfig(name)
    if not (delfile and isfile) or not name then return false end
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if isfile(path) then delfile(path) return true end
    return false
end

function Library:SetAutoload(name)
    if not FSReady() then return end
    EnsureDir()
    local path = CONFIG_DIR .. "/autoload.txt"
    if name then writefile(path, name) elseif delfile and isfile(path) then delfile(path) end
end

function Library:GetAutoload()
    if not FSReady() then return nil end
    local path = CONFIG_DIR .. "/autoload.txt"
    return isfile(path) and readfile(path) or nil
end

function Library:LoadAutoload()
    local name = self:GetAutoload()
    if name then return self:LoadConfig(name) end
    return false
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
function Library:CreateWindow(opts)
    opts = opts or {}
    self:Unload()
    Sweep()
    self._maid = Maid.new()
    env.__BeaglewareUI = self

    local gui = New("ScreenGui", { Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1000 })
    Mount(gui)
    self.Gui = gui

    local cam = workspace.CurrentCamera
    local vps = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local size = opts.Size or Vector2.new(660, 470)
    local w, h = math.min(size.X, vps.X - 20), math.min(size.Y, vps.Y - 20)

    local window = setmetatable({
        Tabs = {}, Query = "", ToggleKey = opts.ToggleKey or Enum.KeyCode.RightControl,
        Visible = true, Minimized = false, _w = w, _h = h, _fullH = h, _sideOrder = 0,
    }, Window)
    self.Window = window

    local frame = New("CanvasGroup", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(vps.X / 2, vps.Y / 2), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = T.Background, GroupTransparency = 1, Active = true, Parent = gui },
        { Corner(10), Stroke(T.Stroke) })
    local scale = New("UIScale", { Scale = 0.92, Parent = frame })
    window.Frame, window.Scale = frame, scale

    window.FloatLayer = New("Frame", { Name = "Floating", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = gui })
    self.FloatLayer = window.FloatLayer
    self.PopupLayer = New("Frame", { Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100, Parent = gui })

    -- Title bar
    local titlebar = New("Frame", { Name = "Titlebar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TITLE_H), Parent = frame })
    local dragHandle = New("TextButton", { Name = "DragHandle", Size = UDim2.fromScale(1, 1), Parent = titlebar })
    New("TextLabel", { Text = opts.Title or "Beagleware", Font = FONT_BOLD, TextSize = 15,
        Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, 160, 1, 0), Parent = titlebar })
    window.TitleLabel = titlebar:FindFirstChild("TextLabel")

    local searchHolder = New("Frame", { Name = "Search", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(math.min(280, w - 360), 30), BackgroundColor3 = T.Card, Parent = titlebar },
        { Corner(8), Stroke(T.Stroke) })
    local sIcon = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(16, 16), Parent = searchHolder })
    Icons.Search(sIcon, T.SubText).Position = UDim2.fromScale(0.5, 0.5)
    local searchBox = New("TextBox", { PlaceholderText = "Search everything...", PlaceholderColor3 = T.SubText, Text = "",
        Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -44, 1, 0), ClipsDescendants = true, Parent = searchHolder })
    window.SearchBox = searchBox

    local function ctrlButton(offsetX, drawIcon, onClick)
        local b = New("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, offsetX, 0.5, 0),
            Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, BackgroundColor3 = T.Element, Parent = titlebar }, { Corner(6) })
        drawIcon(b, T.SubText)
        b.MouseEnter:Connect(function() Tween(b, { BackgroundTransparency = 0 }, 0.12) end)
        b.MouseLeave:Connect(function() Tween(b, { BackgroundTransparency = 1 }, 0.12) end)
        b.MouseButton1Click:Connect(onClick)
    end
    ctrlButton(-14, Icons.Cross, function() Library:Unload() end)
    ctrlButton(-44, Icons.Minus, function() window:SetMinimized(not window.Minimized) end)

    New("Frame", { Name = "TitleLine", BackgroundColor3 = T.Stroke, Position = UDim2.fromOffset(0, TITLE_H),
        Size = UDim2.new(1, 0, 0, 1), Parent = frame })

    -- Body
    window.Body = New("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TITLE_H + 1),
        Size = UDim2.new(1, 0, 1, -(TITLE_H + 1)), Parent = frame })
    window.Sidebar = New("ScrollingFrame", { Name = "Sidebar", Position = UDim2.fromOffset(10, 10),
        Size = UDim2.new(0, SIDE_W, 1, -20), ScrollBarThickness = 0, Parent = window.Body }, { List(3) })
    New("Frame", { Name = "SideLine", BackgroundColor3 = T.Stroke, Position = UDim2.fromOffset(SIDE_W + 20, 10),
        Size = UDim2.new(0, 1, 1, -20), Parent = window.Body })
    window.Content = New("Frame", { Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(SIDE_W + 21, 0), Size = UDim2.new(1, -(SIDE_W + 21), 1, 0), Parent = window.Body })

    -- Search
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        window.Query = searchBox.Text
        window:_applySearch()
    end)
    searchBox.Focused:Connect(function() Tween(searchHolder:FindFirstChildOfClass("UIStroke"), { Color = T.Accent }, 0.15) end)
    searchBox.FocusLost:Connect(function() Tween(searchHolder:FindFirstChildOfClass("UIStroke"), { Color = T.Stroke }, 0.15) end)

    -- Window dragging
    local origin
    self:_pointerDrag(dragHandle, {
        Threshold = 0,
        OnBegin = function() origin = frame.Position; self:_closePopup() end,
        OnMove = function(pos, start)
            local d = pos - start
            local vp = gui.AbsoluteSize
            local cx = math.clamp(origin.X.Offset + d.X, 100 - window._w / 2, vp.X - 100 + window._w / 2)
            local cy = math.clamp(origin.Y.Offset + d.Y, window._h / 2, vp.Y - 40 + window._h / 2)
            frame.Position = UDim2.fromOffset(cx, cy)
        end,
    })

    -- Global input: keybinds, popup outside-click, menu toggle
    self._maid:Give(UserInputService.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            local p = self._popup
            if p then
                local m = UserInputService:GetMouseLocation()
                if not Inside(p.Frame, m) and not Inside(p.Anchor, m) then self:_closePopup() end
            end
            return
        end
        if t ~= Enum.UserInputType.Keyboard then return end
        local lis = self._listening
        if lis then
            self._listening = nil
            local k = input.KeyCode
            if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then lis:Set(nil) else lis:Set(k) end
            return
        end
        if UserInputService:GetFocusedTextBox() then return end
        if window.ToggleKey and input.KeyCode == window.ToggleKey then
            window:SetVisible(not window.Visible)
            return
        end
        for _, b in ipairs(self._binds) do
            if b.Key and b.Key == input.KeyCode and b.Callback then self:_safe(b.Callback) end
        end
    end))

    -- Intro animation
    Tween(scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    Tween(frame, { GroupTransparency = 0 }, 0.3)

    return window
end

function Window:SetTitle(text) self.TitleLabel.Text = text end
function Window:SetToggleKey(key) self.ToggleKey = key end
function Window:Destroy() Library:Unload() end

function Window:SetVisible(v)
    if self.Visible == v then return end
    self.Visible = v
    Library:_closePopup()
    if v then
        self.Frame.Visible = true
        self.FloatLayer.Visible = true
        self.Scale.Scale = 0.94
        Tween(self.Scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
        Tween(self.Frame, { GroupTransparency = 0 }, 0.22)
    else
        self.FloatLayer.Visible = false
        Tween(self.Scale, { Scale = 0.94 }, 0.2)
        Tween(self.Frame, { GroupTransparency = 1 }, 0.2).Completed:Connect(function()
            if not self.Visible then self.Frame.Visible = false end
        end)
    end
end
function Window:Toggle() self:SetVisible(not self.Visible) end

function Window:SetMinimized(m)
    self.Minimized = m
    Library:_closePopup()
    local newH = m and TITLE_H or self._fullH
    local dy = (newH - self._h) / 2
    self._h = newH
    Tween(self.Frame, { Size = UDim2.fromOffset(self._w, newH),
        Position = self.Frame.Position + UDim2.fromOffset(0, dy) }, 0.3)
end

function Window:_selectTab(tab)
    if self.ActiveTab == tab then return end
    Library:_closePopup()
    local prev = self.ActiveTab
    if prev then
        prev.Active = false
        prev.Page.Visible = false
        prev:_style(false)
    end
    self.ActiveTab = tab
    tab.Active = true
    tab.Page.Position = UDim2.fromOffset(0, 12)
    tab.Page.Visible = true
    Tween(tab.Page, { Position = UDim2.fromOffset(0, 0) }, 0.3)
    tab:_style(true)
end

function Window:_applySearch()
    local q = self.Query:lower()
    local firstWithMatch, activeHas = nil, false
    for _, tab in ipairs(self.Tabs) do
        local tabAny = false
        for _, sec in ipairs(tab.Sections) do
            local secMatch = q == "" or sec.Name:lower():find(q, 1, true) ~= nil
            local any = secMatch
            for _, el in ipairs(sec.Elements) do
                local m = secMatch or (el.SearchName and tostring(el.SearchName):lower():find(q, 1, true) ~= nil) or false
                el._filtered = not m
                el:_refresh()
                if m then any = true end
            end
            if not sec.Floating then sec.Card.Visible = any end
            if any then tabAny = true end
        end
        if tabAny then
            firstWithMatch = firstWithMatch or tab
            if tab == self.ActiveTab then activeHas = true end
        end
    end
    if q ~= "" and not activeHas and firstWithMatch then self:_selectTab(firstWithMatch) end
end

-- Sidebar construction
function Window:_buildTab(name, container, order, nested)
    local tab = setmetatable({ Window = self, Name = name, Sections = {}, Active = false, _count = { Left = 0, Right = 0 } }, Tab)

    tab.Button = New("TextButton", { Name = "Tab_" .. name, BackgroundColor3 = T.Element, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = container }, { Corner(6) })
    tab.Label = New("TextLabel", { Text = name, TextColor3 = T.SubText, Position = UDim2.fromOffset(nested and 10 or 12, 0),
        Size = UDim2.new(1, -14, 1, 0), Parent = tab.Button })
    if nested then
        tab.Line = New("Frame", { BackgroundColor3 = T.Stroke, Position = UDim2.new(0, -6, 0, -1), Size = UDim2.new(0, 1, 1, 2), Parent = tab.Button })
    end
    tab.Button.MouseEnter:Connect(function()
        if not tab.Active then Tween(tab.Label, { TextColor3 = T.Text }, 0.12) end
    end)
    tab.Button.MouseLeave:Connect(function()
        if not tab.Active then Tween(tab.Label, { TextColor3 = T.SubText }, 0.12) end
    end)
    tab.Button.MouseButton1Click:Connect(function() self:_selectTab(tab) end)

    tab.Page = New("Frame", { Name = "Page_" .. name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        Visible = false, Parent = self.Content })
    -- Two columns: 10px outer edge, 3px inner padding (room for strokes), ~12px gap between columns
    local function column(x, scaleX)
        return New("ScrollingFrame", { Position = UDim2.new(scaleX, x, 0, 0), Size = UDim2.new(0.5, -13, 1, 0), Parent = tab.Page },
            { List(10), Pad(12, 3, 12, 3) })
    end
    tab.Left  = column(10, 0)
    tab.Right = column(3, 0.5)

    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self:_selectTab(tab) end
    return tab
end

function Tab:_style(active)
    Tween(self.Button, { BackgroundTransparency = active and 0 or 1 }, 0.2)
    Tween(self.Label, { TextColor3 = active and T.Text or T.SubText }, 0.2)
    if self.Line then Tween(self.Line, { BackgroundColor3 = active and T.Accent or T.Stroke }, 0.2) end
end
function Tab:Select() self.Window:_selectTab(self) end

function Window:AddTab(name)
    self._sideOrder += 1
    return self:_buildTab(name, self.Sidebar, self._sideOrder, false)
end

function Window:AddCategory(name)
    self._sideOrder += 1
    local cat = setmetatable({ Window = self, Name = name, Collapsed = false, _order = 0 }, Category)
    local holder = New("Frame", { Name = "Category_" .. name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self._sideOrder, Parent = self.Sidebar }, { List(2) })
    local header = New("TextButton", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = holder })
    New("TextLabel", { Text = name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -40, 1, 0), Parent = header })
    local chev = Icons.Chevron(header, T.SubText)
    chev.Position = UDim2.new(1, -18, 0.5, 0)
    local children = New("Frame", { Name = "Children", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ClipsDescendants = true, LayoutOrder = 2, Parent = holder })
    cat.Inner = New("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -18, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = children }, { List(2) })
    local layout = cat.Inner:FindFirstChildOfClass("UIListLayout")
    header.MouseButton1Click:Connect(function()
        AnimateCollapse(cat, children, layout, 0, not cat.Collapsed)
        Tween(chev, { Rotation = cat.Collapsed and -90 or 0 }, 0.2)
    end)
    return cat
end

function Category:AddTab(name)
    self._order += 1
    return self.Window:_buildTab(name, self.Inner, self._order, true)
end

----------------------------------------------------------------------
-- Sections (draggable cards)
----------------------------------------------------------------------
function Tab:AddSection(title, side)
    if side ~= "Left" and side ~= "Right" then
        side = (self._count.Left <= self._count.Right) and "Left" or "Right"
    end
    self._count[side] += 1
    local column = side == "Left" and self.Left or self.Right

    local sec = setmetatable({ Tab = self, Name = title, Elements = {}, Collapsed = false, Floating = false, Side = side }, Section)
    sec.Card = New("Frame", { Name = "Section_" .. title, BackgroundColor3 = T.Card, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Active = true, LayoutOrder = self._count[side], Parent = column },
        { Corner(8), List(0) })
    sec.Stroke = Stroke(T.Stroke)
    sec.Stroke.Parent = sec.Card

    sec.Header = New("TextButton", { Name = "Header", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 1, Parent = sec.Card })
    sec.Title = New("TextLabel", { Text = title, Font = FONT_BOLD, Position = UDim2.fromOffset(BODY_PAD_X, 0),
        Size = UDim2.new(1, -(BODY_PAD_X + 34), 1, 0), Parent = sec.Header })
    sec.Chevron = Icons.Chevron(sec.Header, T.SubText)
    sec.Chevron.Position = UDim2.new(1, -(BODY_PAD_X + 6), 0.5, 0)
    New("Frame", { BackgroundColor3 = T.Stroke, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), Parent = sec.Header })

    sec.Body = New("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, ClipsDescendants = true, LayoutOrder = 2, Parent = sec.Card },
        { List(ELEMENT_GAP), Pad(BODY_PAD_Y, BODY_PAD_X, BODY_PAD_Y, BODY_PAD_X) })
    sec.Layout = sec.Body:FindFirstChildOfClass("UIListLayout")

    -- Drag out / drop back
    Library:_pointerDrag(sec.Header, {
        Threshold = 5,
        CanStart = function() return not sec._resetting end,
        OnBegin = function(startMouse) sec:_beginFloat(startMouse) end,
        OnMove = function(pos, _, dt) sec:_moveFloat(pos, dt) end,
        OnEnd = function(pos, dragged)
            if not dragged then
                sec:SetCollapsed(not sec.Collapsed)
                return
            end
            Tween(sec.Stroke, { Color = T.Stroke }, 0.2)
            local win = Library.Window
            if sec.Floating and win and win.Visible and Inside(win.Frame, pos) then sec:Reset() end
        end,
    })

    table.insert(self.Sections, sec)
    return sec
end

function Section:SetCollapsed(c)
    Library:_closePopup()
    AnimateCollapse(self, self.Body, self.Layout, BODY_PAD_Y * 2, c)
    Tween(self.Chevron, { Rotation = c and -90 or 0 }, 0.2)
end

function Section:_beginFloat(startMouse)
    Library:_closePopup()
    local card = self.Card
    local abs, size = card.AbsolutePosition, card.AbsoluteSize
    if not self.Floating then
        local ph = New("Frame", { Name = "Placeholder", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, size.Y),
            LayoutOrder = card.LayoutOrder, Parent = card.Parent }, { Corner(8), Stroke(T.Accent, 0.75) })
        self.Placeholder = ph
        self.Floating = true
        card.Size = UDim2.fromOffset(size.X, 0)
        card.Parent = Library.FloatLayer
    end
    Library._zCounter += 1
    card.ZIndex = Library._zCounter
    card.Position = UDim2.fromOffset(abs.X, abs.Y)
    self._cur = abs
    self._grab = startMouse - abs
    self._size = size
    Tween(self.Stroke, { Color = T.Accent }, 0.15)
end

function Section:_moveFloat(pos, dt)
    local vp = Library.Gui.AbsoluteSize
    local target = pos - self._grab
    target = Vector2.new(
        math.clamp(target.X, 60 - self._size.X, vp.X - 60),
        math.clamp(target.Y, 0, vp.Y - 40))
    self._cur = self._cur:Lerp(target, 1 - math.exp(-dt * 28))
    self.Card.Position = UDim2.fromOffset(self._cur.X, self._cur.Y)
end

-- Snap the section back to its original slot
function Section:Reset(instant)
    if not self.Floating then return end
    self.Floating = false
    self._resetting = true
    local card, ph = self.Card, self.Placeholder
    local function finalize()
        self._resetting = false
        if not card.Parent or not ph.Parent then return end
        card.Parent = ph.Parent
        card.LayoutOrder = ph.LayoutOrder
        card.Size = UDim2.new(1, 0, 0, 0)
        card.Position = UDim2.new()
        card.ZIndex = 1
        ph:Destroy()
        self.Placeholder = nil
        self.Stroke.Color = T.Stroke
    end
    if instant or not self.Tab.Active then
        finalize()
    else
        local a = ph.AbsolutePosition
        Tween(card, { Position = UDim2.fromOffset(a.X, a.Y) }, 0.3).Completed:Connect(finalize)
    end
end
Section.ResetPosition = Section.Reset

----------------------------------------------------------------------
-- Elements
----------------------------------------------------------------------
function ElementBase:_refresh() self.Frame.Visible = (not self._hidden) and (not self._filtered) end
function ElementBase:SetVisible(v) self._hidden = not v; self:_refresh() end
function ElementBase:OnChanged(fn) table.insert(self._listeners, fn); return self end
function ElementBase:Get() return self.Value end
function ElementBase:Destroy()
    for i, e in ipairs(self.Section.Elements) do if e == self then table.remove(self.Section.Elements, i) break end end
    if self.Flag then Library.Options[self.Flag] = nil; Library.Flags[self.Flag] = nil end
    self.Frame:Destroy()
end

function Section:_element(kind, opts, height)
    local frame = New("Frame", { Name = kind, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height),
        LayoutOrder = #self.Elements + 1, Parent = self.Body })
    local obj = setmetatable({ Frame = frame, Kind = kind, Section = self, Flag = opts.Flag, Callback = opts.Callback,
        SearchName = opts.Name, _listeners = {} }, ElementBase)
    table.insert(self.Elements, obj)
    if opts.Flag then Library.Options[opts.Flag] = obj end
    return obj
end

local function RowLabel(parent, name, desc, rightPad)
    local nameLbl = New("TextLabel", { Text = name, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, -rightPad, 0, 16), Position = desc and UDim2.fromOffset(0, 3) or UDim2.fromScale(0, 0.5),
        AnchorPoint = desc and Vector2.zero or Vector2.new(0, 0.5), Parent = parent })
    local descLbl
    if desc then
        descLbl = New("TextLabel", { Text = desc, TextSize = 11, TextColor3 = T.SubText, TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, -rightPad, 0, 14), Parent = parent })
    end
    return nameLbl, descLbl
end

local function parseKey(name)
    if not name or name == "None" then return nil end
    local ok, k = pcall(function() return Enum.KeyCode[name] end)
    return ok and k or nil
end

-- Toggle (optional keybind) ---------------------------------------------
function Section:AddToggle(opts)
    opts = opts or {}
    local desc = opts.Description
    local hasBind = opts.Keybind ~= nil and opts.Keybind ~= false
    local obj = self:_element("Toggle", opts, desc and 38 or 28)
    obj.Value = opts.Default and true or false
    local f = obj.Frame

    RowLabel(f, opts.Name or "Toggle", desc, 52 + (hasBind and 50 or 0))
    local hit = New("TextButton", { Size = UDim2.fromScale(1, 1), Parent = f })
    local track = New("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(36, 18), BackgroundColor3 = T.Off, Parent = f }, { Corner(9) })
    local knob = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(12, 12), BackgroundColor3 = T.KnobOff, Parent = track }, { Corner(6) })

    local function render(instant)
        local on, t = obj.Value, instant and 0 or 0.18
        Tween(track, { BackgroundColor3 = on and T.Accent or T.Off }, t)
        Tween(knob, { Position = on and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and WHITE or T.KnobOff }, t)
    end
    render(true)
    Library:_accent(function() render(true) end)

    function obj:Set(v, silent)
        v = not not v
        if v == self.Value then return end
        self.Value = v
        render()
        Library:_emit(self, silent)
    end
    hit.MouseButton1Click:Connect(function() obj:Set(not obj.Value) end)
    hit.MouseEnter:Connect(function() Tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.12) end)
    hit.MouseLeave:Connect(function() Tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.12) end)

    if hasBind then
        local default = typeof(opts.Keybind) == "EnumItem" and opts.Keybind or nil
        obj.Bind = Library:_newBind(default, function() obj:Set(not obj.Value) end)
        Library:_bindButton(f, obj.Bind, UDim2.new(1, -44, 0.5, 0))
    end

    obj._export = function() return { v = obj.Value, k = obj.Bind and (obj.Bind.Key and obj.Bind.Key.Name or "None") or nil } end
    obj._import = function(d)
        if type(d) ~= "table" then return end
        obj:Set(d.v)
        if obj.Bind and d.k then obj.Bind:Set(parseKey(d.k)) end
    end
    Library:_init(obj)
    return obj
end

-- Standalone keybind -----------------------------------------------------
function Section:AddKeybind(opts)
    opts = opts or {}
    local obj = self:_element("Keybind", opts, 28)
    local f = obj.Frame
    RowLabel(f, opts.Name or "Keybind", nil, 60)
    obj.Bind = Library:_newBind(opts.Default, function()
        if opts.Callback then Library:_safe(opts.Callback, obj.Bind.Key) end
    end)
    obj.Value = opts.Default
    obj.Bind.Changed = function(key)
        obj.Value = key
        if obj.Flag then Library.Flags[obj.Flag] = key end
        if opts.Changed then Library:_safe(opts.Changed, key) end
        for _, fn in ipairs(obj._listeners) do Library:_safe(fn, key) end
    end
    Library:_bindButton(f, obj.Bind, UDim2.fromScale(1, 0.5))
    function obj:Set(key) self.Bind:Set(key) end
    obj._export = function() return obj.Value and obj.Value.Name or "None" end
    obj._import = function(d) obj.Bind:Set(parseKey(d)) end
    if obj.Flag then Library.Flags[obj.Flag] = obj.Value end
    return obj
end

-- Button -----------------------------------------------------------------
function Section:AddButton(opts)
    opts = opts or {}
    local obj = self:_element("Button", opts, 32)
    local btn = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Element, BackgroundTransparency = 0,
        Text = opts.Name or "Button", ClipsDescendants = true, Parent = obj.Frame }, { Corner(6), Stroke(T.Stroke) })
    btn.MouseEnter:Connect(function() Tween(btn, { BackgroundColor3 = T.ElementHover }, 0.12) end)
    btn.MouseLeave:Connect(function() Tween(btn, { BackgroundColor3 = T.Element }, 0.12) end)
    btn.MouseButton1Down:Connect(function() Tween(btn, { BackgroundColor3 = Color3.fromRGB(24, 24, 28) }, 0.08) end)
    btn.MouseButton1Up:Connect(function() Tween(btn, { BackgroundColor3 = T.ElementHover }, 0.12) end)
    btn.MouseButton1Click:Connect(function()
        Ripple(btn)
        if opts.Callback then Library:_safe(opts.Callback) end
    end)
    function obj:SetText(t) btn.Text = t; self.SearchName = t end
    return obj
end

-- Dropdown / MultiDropdown -------------------------------------------------
-- The option list expands INLINE (inside the element's frame), so the element
-- grows and pushes everything below it down instead of overlaying it.
function Section:_dropdown(opts, multi)
    opts = opts or {}
    local kind = multi and "MultiDropdown" or "Dropdown"
    local obj = self:_element(kind, opts, DD_H)
    local f = obj.Frame
    obj.Options = {}
    obj.Value = multi and {} or nil      -- always a valid value before anything renders
    local selected = {}
    local isOpen, token = false, 0

    New("TextLabel", { Text = opts.Name or kind, TextSize = 12, TextColor3 = T.SubText, Size = UDim2.new(1, 0, 0, 16), Parent = f })
    local box = New("TextButton", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0,
        BackgroundColor3 = T.Element, Parent = f }, { Corner(6), Stroke(T.Stroke) })
    local boxStroke = box:FindFirstChildOfClass("UIStroke")
    local valueLbl = New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -36, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = box })
    local chev = Icons.Chevron(box, T.SubText)
    chev.Position = UDim2.new(1, -16, 0.5, 0)

    local listTop = DD_H + DD_GAP
    local listHolder = New("Frame", { Name = "OptionList", Position = UDim2.fromOffset(0, listTop), Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = T.Card, ClipsDescendants = true, Visible = false, Parent = f }, { Corner(6), Stroke(T.Stroke) })
    local scroll = New("ScrollingFrame", { Size = UDim2.fromScale(1, 1), Parent = listHolder }, { List(2), Pad(4) })

    local items = {}
    local function listHeight() return math.min(#obj.Options * 28 + 6, 176) end

    local popup = { Inline = true, Frame = listHolder, Anchor = box }
    popup.Open = function()
        isOpen = true
        token += 1
        listHolder.Visible = true
        local h = listHeight()
        Tween(listHolder, { Size = UDim2.new(1, 0, 0, h) }, 0.22)
        Tween(f, { Size = UDim2.new(1, 0, 0, listTop + h) }, 0.22)
        Tween(chev, { Rotation = 180 }, 0.2)
        Tween(boxStroke, { Color = T.Accent }, 0.15)
    end
    popup.Close = function()
        isOpen = false
        token += 1
        local mine = token
        Tween(listHolder, { Size = UDim2.new(1, 0, 0, 0) }, 0.18)
        Tween(f, { Size = UDim2.new(1, 0, 0, DD_H) }, 0.18).Completed:Connect(function()
            if token == mine then listHolder.Visible = false end
        end)
        Tween(chev, { Rotation = 0 }, 0.2)
        Tween(boxStroke, { Color = T.Stroke }, 0.15)
    end
    box.MouseEnter:Connect(function() Tween(box, { BackgroundColor3 = T.ElementHover }, 0.12) end)
    box.MouseLeave:Connect(function() Tween(box, { BackgroundColor3 = T.Element }, 0.12) end)
    box.MouseButton1Click:Connect(function()
        if Library._popup == popup then Library:_closePopup() else Library:_openPopup(popup) end
    end)

    local function collect()
        local r = {}
        for _, name in ipairs(obj.Options) do if selected[name] then r[#r + 1] = name end end
        return r
    end
    local function render()
        local val = obj.Value
        for name, it in pairs(items) do
            local on
            if multi then on = selected[name] == true else on = (val == name) end
            it.Label.TextColor3 = on and T.Accent or T.Text
            if it.Check then Tween(it.Check, { BackgroundColor3 = on and T.Accent or T.Element }, 0.15) end
        end
        if multi then
            valueLbl.Text = (type(val) == "table" and #val > 0) and table.concat(val, ", ") or "None"
        else
            valueLbl.Text = val ~= nil and tostring(val) or "Select..."
        end
    end

    local function pick(name)
        if multi then
            selected[name] = not selected[name] or nil
            obj.Value = collect()
        else
            obj.Value = name
            Library:_closePopup()
        end
        render()
        Library:_emit(obj)
    end

    local function build(list)
        for _, it in pairs(items) do it.Button:Destroy() end
        items = {}
        obj.Options = list
        for i, name in ipairs(list) do
            local btn = New("TextButton", { Name = tostring(name), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.ElementHover,
                BackgroundTransparency = 1, LayoutOrder = i, Parent = scroll }, { Corner(4) })
            local lbl = New("TextLabel", { Text = tostring(name), Position = UDim2.fromOffset(multi and 30 or 9, 0),
                Size = UDim2.new(1, multi and -38 or -18, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn })
            local check
            if multi then
                check = New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(14, 14),
                    BackgroundColor3 = T.Element, Parent = btn }, { Corner(4), Stroke(T.Stroke) })
            end
            btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0 }, 0.1) end)
            btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 1 }, 0.1) end)
            btn.MouseButton1Click:Connect(function() pick(name) end)
            items[name] = { Button = btn, Label = lbl, Check = check }
        end
        if isOpen then
            local h = listHeight()
            Tween(listHolder, { Size = UDim2.new(1, 0, 0, h) }, 0.18)
            Tween(f, { Size = UDim2.new(1, 0, 0, listTop + h) }, 0.18)
        end
    end

    -- initial value (set BEFORE the first render / accent registration)
    local list = opts.Options or {}
    if multi then
        for _, n in ipairs(opts.Default or {}) do selected[n] = true end
        build(list)
        obj.Value = collect()
    else
        obj.Value = opts.Default or list[1]
        build(list)
    end
    render()
    Library:_accent(render)

    function obj:Set(v, silent)
        if multi then
            selected = {}
            if type(v) == "table" then
                for k, n in pairs(v) do
                    if type(k) == "number" then selected[n] = true elseif n then selected[k] = true end
                end
            end
            self.Value = collect()
        else
            self.Value = v
        end
        render()
        Library:_emit(self, silent)
    end
    function obj:SetOptions(newList, keep)
        newList = newList or {}
        if multi then
            local old = selected
            selected = {}
            if keep then for _, n in ipairs(newList) do if old[n] then selected[n] = true end end end
            build(newList)
            self.Value = collect()
        else
            build(newList)
            if not (keep and table.find(newList, self.Value)) then self.Value = newList[1] end
        end
        render()
        Library:_emit(self)
    end
    obj.Refresh = obj.SetOptions
    obj._export = function() return obj.Value end
    obj._import = function(v) obj:Set(v) end
    Library:_init(obj)
    return obj
end

function Section:AddDropdown(opts) return self:_dropdown(opts, false) end
function Section:AddMultiDropdown(opts) return self:_dropdown(opts, true) end

-- Colorpicker ------------------------------------------------------------
function Section:AddColorpicker(opts)
    opts = opts or {}
    local obj = self:_element("Colorpicker", opts, 28)
    local f = obj.Frame
    RowLabel(f, opts.Name or "Color", nil, 50)

    local swatch = New("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(34, 18),
        BackgroundTransparency = 0, Parent = f }, { Corner(5), Stroke(T.Stroke) })
    local swatchStroke = swatch:FindFirstChildOfClass("UIStroke")

    local POPUP_W = 196
    local popupFrame = Library:_newPopupFrame()
    local popup = { Frame = popupFrame, Anchor = swatch, Width = POPUP_W, Height = 172, AlignRight = true }
    popup.OnOpen = function() Tween(swatchStroke, { Color = T.Accent }, 0.15) end
    popup.OnClose = function() Tween(swatchStroke, { Color = T.Stroke }, 0.15) end
    swatch.MouseButton1Click:Connect(function()
        if Library._popup == popup then Library:_closePopup() else Library:_openPopup(popup) end
    end)

    local sv = New("TextButton", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(180, 100), BackgroundTransparency = 0,
        BackgroundColor3 = Color3.new(1, 0, 0), Parent = popupFrame }, { Corner(4) })
    New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = sv }, {
        Corner(4),
        New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }),
    })
    New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv }, {
        Corner(4),
        New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }),
    })
    local svCursor = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE,
        ZIndex = 3, Parent = sv }, { New("UICorner", { CornerRadius = UDim.new(1, 0) }), Stroke(Color3.new(0, 0, 0), 0.2) })

    local hue = New("TextButton", { Position = UDim2.fromOffset(8, 116), Size = UDim2.fromOffset(180, 12), BackgroundTransparency = 0,
        BackgroundColor3 = WHITE, Parent = popupFrame }, { Corner(6) })
    local kp = {}
    local cols = { Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 255, 0), Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 255, 255),
        Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 255), Color3.fromRGB(255, 0, 0) }
    for i, c in ipairs(cols) do kp[i] = ColorSequenceKeypoint.new((i - 1) / 6, c) end
    New("UIGradient", { Color = ColorSequence.new(kp), Parent = hue })
    local hueCursor = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 18), BackgroundColor3 = WHITE,
        Parent = hue }, { Corner(2), Stroke(Color3.new(0, 0, 0), 0.3) })

    local hexHolder = New("Frame", { Position = UDim2.fromOffset(8, 136), Size = UDim2.fromOffset(180, 28), BackgroundColor3 = T.Element,
        Parent = popupFrame }, { Corner(5), Stroke(T.Stroke) })
    local hexBox = New("TextBox", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 12,
        ClipsDescendants = true, Parent = hexHolder })

    local h, s, v = (opts.Default or T.Accent):ToHSV()
    local function update(silent)
        local c = Color3.fromHSV(h, s, v)
        obj.Value = c
        swatch.BackgroundColor3 = c
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svCursor.Position = UDim2.fromScale(s, 1 - v)
        hueCursor.Position = UDim2.fromScale(h, 0.5)
        if not hexBox:IsFocused() then hexBox.Text = "#" .. c:ToHex():upper() end
        Library:_emit(obj, silent)
    end

    Library:_pointerDrag(sv, { OnMove = function(pos)
        local a, sz = sv.AbsolutePosition, sv.AbsoluteSize
        s = math.clamp((pos.X - a.X) / sz.X, 0, 1)
        v = 1 - math.clamp((pos.Y - a.Y) / sz.Y, 0, 1)
        update()
    end })
    Library:_pointerDrag(hue, { OnMove = function(pos)
        local a, sz = hue.AbsolutePosition, hue.AbsoluteSize
        h = math.clamp((pos.X - a.X) / sz.X, 0, 1)
        update()
    end })
    hexBox.FocusLost:Connect(function()
        local txt = hexBox.Text:gsub("#", "")
        local ok, c = pcall(Color3.fromHex, txt)
        if ok and c then h, s, v = c:ToHSV() end
        update()
    end)

    function obj:Set(c, silent) h, s, v = c:ToHSV(); update(silent) end
    obj._export = function() return obj.Value:ToHex() end
    obj._import = function(hex) local ok, c = pcall(Color3.fromHex, hex); if ok then obj:Set(c) end end
    update(true)
    Library:_init(obj)
    return obj
end

-- Textbox ----------------------------------------------------------------
function Section:AddTextbox(opts)
    opts = opts or {}
    local obj = self:_element("Textbox", opts, DD_H)
    local f = obj.Frame
    New("TextLabel", { Text = opts.Name or "Textbox", TextSize = 12, TextColor3 = T.SubText, Size = UDim2.new(1, 0, 0, 16), Parent = f })
    local holder = New("Frame", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.Element,
        Parent = f }, { Corner(6), Stroke(T.Stroke) })
    local stroke = holder:FindFirstChildOfClass("UIStroke")
    local tb = New("TextBox", { Text = opts.Default or "", PlaceholderText = opts.Placeholder or "Type here...",
        PlaceholderColor3 = Color3.fromRGB(92, 92, 102), ClearTextOnFocus = opts.ClearTextOnFocus or false,
        Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), ClipsDescendants = true, Parent = holder })

    local function commit(silent)
        local val = tb.Text
        if opts.Numeric then val = tonumber(val) or 0 end
        obj.Value = val
        Library:_emit(obj, silent)
    end
    if opts.Numeric then
        tb:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = tb.Text:gsub("[^%d%.%-]", "")
            if clean ~= tb.Text then tb.Text = clean end
        end)
    end
    if opts.Live then tb:GetPropertyChangedSignal("Text"):Connect(function() commit() end) end
    tb.Focused:Connect(function() Tween(stroke, { Color = T.Accent }, 0.15) end)
    tb.FocusLost:Connect(function()
        Tween(stroke, { Color = T.Stroke }, 0.15)
        commit()
    end)

    obj.Value = opts.Numeric and (tonumber(tb.Text) or 0) or tb.Text
    function obj:Set(v, silent) tb.Text = tostring(v); commit(silent) end
    function obj:GetText() return tb.Text end
    obj._export = function() return obj.Value end
    obj._import = function(v) obj:Set(v) end
    Library:_init(obj)
    return obj
end

-- Slider -----------------------------------------------------------------
function Section:AddSlider(opts)
    opts = opts or {}
    local min, max = opts.Min or 0, opts.Max or 100
    local inc = opts.Increment or 1
    local dec = #((tostring(inc):match("%.(%d+)")) or "")
    local suffix = opts.Suffix or ""
    local obj = self:_element("Slider", opts, 36)
    local f = obj.Frame

    New("TextLabel", { Text = opts.Name or "Slider", Size = UDim2.new(1, -70, 0, 16), Position = UDim2.fromOffset(0, 0), Parent = f })
    local valLbl = New("TextLabel", { Size = UDim2.fromOffset(70, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.SubText, TextSize = 12, Parent = f })
    local track = New("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = T.Off,
        Parent = f }, { Corner(3) })
    local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, Parent = track }, { Corner(3) })
    local knob = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = WHITE, Parent = fill }, { New("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local hit = New("TextButton", { Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 20), Parent = f })
    Library:_accent(function(c) fill.BackgroundColor3 = c end)

    local function snap(x)
        x = math.clamp(x, min, max)
        x = math.floor((x - min) / inc + 0.5) * inc + min
        return tonumber(string.format("%." .. dec .. "f", math.clamp(x, min, max)))
    end
    local function render(instant)
        local frac = (max == min) and 0 or (obj.Value - min) / (max - min)
        if instant then fill.Size = UDim2.fromScale(frac, 1) else Tween(fill, { Size = UDim2.fromScale(frac, 1) }, 0.08) end
        valLbl.Text = string.format("%." .. dec .. "f", obj.Value) .. suffix
    end

    obj.Value = snap(opts.Default or min)
    render(true)

    function obj:Set(x, silent)
        x = snap(x)
        if x == self.Value then return end
        self.Value = x
        render()
        Library:_emit(self, silent)
    end
    Library:_pointerDrag(hit, {
        OnBegin = function() Tween(knob, { Size = UDim2.fromOffset(15, 15) }, 0.1) end,
        OnMove = function(pos)
            local a, sz = track.AbsolutePosition, track.AbsoluteSize
            obj:Set(min + math.clamp((pos.X - a.X) / sz.X, 0, 1) * (max - min))
        end,
        OnEnd = function() Tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.12) end,
    })
    obj._export = function() return obj.Value end
    obj._import = function(v) obj:Set(tonumber(v) or min) end
    Library:_init(obj)
    return obj
end

-- Image ------------------------------------------------------------------
function Section:AddImage(opts)
    opts = opts or {}
    local obj = self:_element("Image", opts, opts.Height or 100)
    local img = New("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = T.Element,
        Image = ResolveImage(opts.Image), ScaleType = opts.ScaleType or Enum.ScaleType.Crop,
        ImageColor3 = opts.Color or WHITE, Parent = obj.Frame }, { Corner(opts.Corner or 6), Stroke(T.Stroke) })
    function obj:SetImage(v) img.Image = ResolveImage(v) end
    return obj
end

-- Label ------------------------------------------------------------------
function Section:AddLabel(text, opts)
    if type(text) == "table" then opts = text; text = opts.Text end
    opts = opts or {}
    local obj = self:_element("Label", { Name = text }, 20)
    local f = obj.Frame
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.Size = UDim2.new(1, 0, 0, 0)
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
    local main = New("TextLabel", { Text = text or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, RichText = opts.RichText or false, TextColor3 = opts.Color or T.Text, LayoutOrder = 1, Parent = f })
    local sub
    local function ensureSub(t)
        if not sub then
            sub = New("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
                TextSize = 11, TextColor3 = T.SubText, LayoutOrder = 2, Parent = f })
        end
        sub.Text = t
    end
    if opts.Description then ensureSub(opts.Description) end
    function obj:SetText(t) main.Text = t; self.SearchName = t end
    function obj:SetDescription(t) ensureSub(t) end
    return obj
end

-- Separator --------------------------------------------------------------
function Section:AddSeparator(text)
    local obj = self:_element("Separator", {}, text and 18 or 10)
    New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = T.Stroke, Parent = obj.Frame })
    if text then
        New("TextLabel", { Text = text, TextSize = 11, TextColor3 = T.SubText, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0, BackgroundColor3 = T.Card, TextXAlignment = Enum.TextXAlignment.Center,
            Parent = obj.Frame }, { Pad(0, 8) })
    end
    return obj
end

----------------------------------------------------------------------
-- Ready-made settings tab (configs, menu key, accent colour)
----------------------------------------------------------------------
function Window:CreateSettings()
    local cat = self:AddCategory("Settings")
    local tab = cat:AddTab("General")

    local cfg = tab:AddSection("Configs", "Left")
    local nameBox = cfg:AddTextbox({ Name = "Config name", Placeholder = "my-config" })
    local saved = cfg:AddDropdown({ Name = "Saved configs", Options = Library:ListConfigs(), Default = Library:GetAutoload() })
    local function refreshList() saved:SetOptions(Library:ListConfigs(), true) end
    cfg:AddButton({ Name = "Save config", Callback = function()
        local n = nameBox:GetText()
        if n == "" then n = saved.Value or "" end
        if Library:SaveConfig(n) then refreshList(); saved:Set(n, true) end
    end })
    cfg:AddButton({ Name = "Load config", Callback = function() Library:LoadConfig(saved.Value) end })
    cfg:AddButton({ Name = "Delete config", Callback = function() Library:DeleteConfig(saved.Value); refreshList() end })
    cfg:AddButton({ Name = "Refresh list", Callback = refreshList })
    cfg:AddToggle({ Name = "Load on start", Description = "Loads the selected config next time",
        Default = Library:GetAutoload() ~= nil,
        Callback = function(on) Library:SetAutoload(on and saved.Value or nil) end })

    local menu = tab:AddSection("Menu", "Left")
    menu:AddKeybind({ Name = "Show / hide menu", Default = self.ToggleKey, Changed = function(k) self.ToggleKey = k end })
    menu:AddButton({ Name = "Reset all sections", Callback = function()
        for _, t in ipairs(self.Tabs) do for _, s in ipairs(t.Sections) do s:Reset() end end
    end })
    menu:AddButton({ Name = "Unload UI", Callback = function() Library:Unload() end })

    local theme = tab:AddSection("Theme", "Right")
    theme:AddColorpicker({ Name = "Accent", Default = T.Accent, Callback = function(c) Library:SetAccent(c) end })
    return tab
end

return Library
