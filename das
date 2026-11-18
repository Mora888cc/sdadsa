--[[
    NEVERLOSE — Roblox GUI wrapper (single-file, drop-in for Real Executor)

    Layout, palette and density are reconstructed from the supplied reference
    screenshots (photo_1: Players/ESP+Chams, photo_2: Ragebot + Bind popup).

    [INTEGRATION] The original script body belongs between the INTEGRATION
    markers near the bottom. The supplied body file was empty (0 bytes), so the
    region mounts an empty body; the adapter, registry, driver and every control
    are complete and live.
]]

--!nocheck

--================================================================================
-- CONFIG
--================================================================================

local CONFIG = {
    Window = {
        Size = Vector2.new(1120, 668),
        Padding = 14,
    },
    Preview = {
        Size = Vector2.new(292, 520),
    },
    ToggleKey = "RightShift",
    AutoSaveDebounce = 0.6,
    Folder = "NEVERLOSE",
    File = "NEVERLOSE/config.json",
    ToastLifetime = 3.2,
    MaxToasts = 4,
    AnimTime = 0.14,
}

--================================================================================
-- SERVICES
--================================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--================================================================================
-- EXECUTOR PROBE
-- Every executor-only global is resolved once, defensively. Absence is a normal
-- state here, not an error: the shim degrades instead of throwing.
--================================================================================

local function probeGlobal(name)
    local ok, value = pcall(function()
        return getfenv()[name]
    end)
    if ok and value ~= nil then
        return value
    end
    return nil
end

local Executor = {
    gethui = probeGlobal("gethui"),
    protectgui = probeGlobal("protectgui"),
    getcustomasset = probeGlobal("getcustomasset"),
    writefile = probeGlobal("writefile"),
    readfile = probeGlobal("readfile"),
    isfile = probeGlobal("isfile"),
    isfolder = probeGlobal("isfolder"),
    makefolder = probeGlobal("makefolder"),
    delfile = probeGlobal("delfile"),
    loadstring = probeGlobal("loadstring") or loadstring,
}

--================================================================================
-- THEME  (sampled from the reference screenshots)
--================================================================================

local THEME = {
    Background = Color3.fromRGB(9, 9, 13),
    Sidebar = Color3.fromRGB(12, 12, 17),
    Topbar = Color3.fromRGB(15, 15, 21),
    Panel = Color3.fromRGB(17, 17, 23),
    Card = Color3.fromRGB(20, 20, 27),
    CardAlt = Color3.fromRGB(24, 24, 32),
    Row = Color3.fromRGB(24, 24, 31),
    RowHover = Color3.fromRGB(29, 29, 38),
    Stroke = Color3.fromRGB(33, 33, 44),
    StrokeSoft = Color3.fromRGB(27, 27, 36),
    Accent = Color3.fromRGB(61, 155, 255),
    AccentDeep = Color3.fromRGB(38, 104, 184),
    Text = Color3.fromRGB(233, 233, 240),
    Muted = Color3.fromRGB(123, 123, 137),
    Dim = Color3.fromRGB(88, 88, 101),
    Success = Color3.fromRGB(86, 204, 128),
    Warning = Color3.fromRGB(240, 192, 86),
    Danger = Color3.fromRGB(238, 94, 94),
}

local FONT = {
    Bold = Enum.Font.GothamBold,
    Medium = Enum.Font.GothamMedium,
    Regular = Enum.Font.Gotham,
}

--================================================================================
-- ASSETS
-- No asset ids were supplied. Each entry probes for a custom asset, then falls
-- back to a vector/text recreation. Nothing logs to the console.
--================================================================================

local ASSETS = {
    Logo = "",           -- fill: "rbxassetid://<id>" for the wordmark glyph
    PreviewRender = "",  -- fill: "rbxassetid://<id>" for the ESP preview render
}

local function resolveAsset(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    if path:match("^rbxassetid://%d+$") or path:match("^rbxasset://") then
        return path
    end
    if Executor.getcustomasset then
        local ok, result = pcall(Executor.getcustomasset, path)
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end
    return nil
end

--================================================================================
-- HELPERS
--================================================================================

local Connections = {}
local Threads = {}
local Instances = {}

local function track(connection)
    table.insert(Connections, connection)
    return connection
end

local function spawnTracked(fn, ...)
    local thread = task.spawn(fn, ...)
    table.insert(Threads, thread)
    return thread
end

local function new(className, props, parent)
    local instance = Instance.new(className)
    local parentRef = parent
    if not parentRef and props and props.Parent then
        parentRef = props.Parent
    end
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                instance[key] = value
            end
        end
    end
    instance.Parent = parentRef
    table.insert(Instances, instance)
    return instance
end

local function corner(instance, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = instance
    return c
end

local function stroke(instance, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.Stroke
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = instance
    return s
end

local function padding(instance, px)
    local p = Instance.new("UIPadding")
    local pad = UDim.new(0, px)
    p.PaddingTop = pad
    p.PaddingBottom = pad
    p.PaddingLeft = pad
    p.PaddingRight = pad
    p.Parent = instance
    return p
end

local function listLayout(instance, px, direction)
    local l = Instance.new("UIListLayout")
    l.FillDirection = direction or Enum.FillDirection.Vertical
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, px or 4)
    l.Parent = instance
    return l
end

local function tween(instance, props, duration)
    local info = TweenInfo.new(duration or CONFIG.AnimTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TweenService:Create(instance, info, props)
    t:Play()
    return t
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function roundToStep(value, minValue, step)
    if not step or step <= 0 then return value end
    local steps = math.floor((value - minValue) / step + 0.5)
    return minValue + steps * step
end

local function formatNumber(value)
    if math.abs(value - math.floor(value)) < 1e-6 then
        return tostring(math.floor(value))
    end
    return string.format("%.2f", value)
end

local function sanitizeText(text, maxLength)
    local capped = string.sub(tostring(text or ""), 1, maxLength or 64)
    return (capped:gsub("[%c]", ""))
end

local function keyNameToEnum(name)
    if type(name) ~= "string" or name == "" or name == "None" then
        return nil
    end
    local ok, key = pcall(function()
        return Enum.KeyCode[name]
    end)
    if ok then return key end
    return nil
end

local function enumToKeyName(key)
    if typeof(key) == "EnumItem" then
        return key.Name
    end
    return "None"
end

local MODIFIER_KEYS = {
    [Enum.KeyCode.LeftShift] = true,
    [Enum.KeyCode.RightShift] = true,
    [Enum.KeyCode.LeftControl] = true,
    [Enum.KeyCode.RightControl] = true,
    [Enum.KeyCode.LeftAlt] = true,
    [Enum.KeyCode.RightAlt] = true,
    [Enum.KeyCode.LeftMeta] = true,
    [Enum.KeyCode.RightMeta] = true,
    [Enum.KeyCode.CapsLock] = true,
}

--================================================================================
-- STATE
-- One store. Every control reads and writes here; visuals re-render from state.
-- Nothing duplicates truth between a widget and a variable.
--================================================================================

local Store = {
    values = {},
    schema = {},
    handlers = {},
    renderers = {},
    registry = {},
}

local markDirty -- forward

local function storeRegister(key, default, kind, validate)
    Store.schema[key] = { default = default, kind = kind, validate = validate }
    if Store.values[key] == nil then
        Store.values[key] = default
    end
end

local function storeGet(key)
    local value = Store.values[key]
    if value == nil then
        local entry = Store.schema[key]
        if entry then
            value = entry.default
            Store.values[key] = value
        end
    end
    return value
end

local function storeSet(key, value, silent)
    local entry = Store.schema[key]
    if entry and entry.validate then
        value = entry.validate(value)
    end
    Store.values[key] = value

    local handlers = Store.handlers[key]
    if handlers then
        for _, fn in ipairs(handlers) do
            spawnTracked(function()
                local ok, err = pcall(fn, value, key)
                if not ok then
                    warn("[NEVERLOSE] handler error on " .. key .. ": " .. tostring(err))
                end
            end)
        end
    end

    local renderers = Store.renderers[key]
    if renderers then
        for _, fn in ipairs(renderers) do
            pcall(fn, value)
        end
    end

    if not silent then
        markDirty()
    end
end

local function storeOnChange(key, fn)
    Store.handlers[key] = Store.handlers[key] or {}
    table.insert(Store.handlers[key], fn)
end

local function storeOnRender(key, fn)
    Store.renderers[key] = Store.renderers[key] or {}
    table.insert(Store.renderers[key], fn)
    pcall(fn, storeGet(key))
end

--================================================================================
-- DEFAULT SCHEMA
--================================================================================

local function clampNumber(fallback, minValue, maxValue)
    return function(v)
        local n = tonumber(v)
        if not n then return fallback end
        return clamp(n, minValue, maxValue)
    end
end

local function registerDefaults()
    storeRegister("ui.toggleKey", CONFIG.ToggleKey, "string", function(v)
        if keyNameToEnum(v) then return v end
        return CONFIG.ToggleKey
    end)
    storeRegister("ui.toggleBind", { key = CONFIG.ToggleKey, mode = "Toggle", show = false }, "keybind")

    storeRegister("aimbot.ragebot.enabled", false, "boolean")
    storeRegister("aimbot.ragebot.silent", true, "boolean")
    storeRegister("aimbot.ragebot.fov", 179, "number", clampNumber(179, 1, 360))
    storeRegister("aimbot.ragebot.resolver", false, "boolean")
    storeRegister("aimbot.ragebot.hideShots", false, "boolean")
    storeRegister("aimbot.ragebot.doubleTap", false, "boolean")
    storeRegister("aimbot.ragebot.mode", "Default", "string")
    storeRegister("aimbot.ragebot.teleportBoost", false, "boolean")
    storeRegister("aimbot.ragebot.hitChance", 0, "number", clampNumber(0, 0, 100))
    storeRegister("aimbot.ragebot.pointScale", false, "boolean")
    storeRegister("aimbot.ragebot.safePoints", "Default", "string")
    storeRegister("aimbot.ragebot.forceConditions", "Select", "string")
    storeRegister("aimbot.ragebot.headSafety", false, "boolean")
    storeRegister("aimbot.ragebot.bodyAim", "Default", "string")
    storeRegister("aimbot.ragebot.maxMisses", 0, "number", clampNumber(0, 0, 10))
    storeRegister("aimbot.ragebot.minDamageVisible", "Auto", "string")
    storeRegister("aimbot.ragebot.minDamageAutowall", "Auto", "string")
    storeRegister("aimbot.ragebot.autoStop", false, "boolean")
    storeRegister("aimbot.ragebot.conditions", "Select", "string")
    storeRegister("aimbot.ragebot.autoScope", false, "boolean")
    storeRegister("aimbot.ragebot.bind", { key = "None", mode = "Toggle", show = true }, "keybind")

    storeRegister("aimbot.antiaim.enabled", false, "boolean")
    storeRegister("aimbot.antiaim.pitch", "Default", "string")
    storeRegister("aimbot.antiaim.yaw", "Default", "string")
    storeRegister("aimbot.antiaim.jitter", 0, "number", clampNumber(0, 0, 180))

    storeRegister("aimbot.legitbot.enabled", false, "boolean")
    storeRegister("aimbot.legitbot.smoothing", 6, "number", clampNumber(6, 1, 30))
    storeRegister("aimbot.legitbot.fov", 12, "number", clampNumber(12, 1, 90))

    storeRegister("visuals.players.esp", true, "boolean")
    storeRegister("visuals.players.espWalls", false, "boolean")
    storeRegister("visuals.players.bulletTracer", "Disabled", "string")
    storeRegister("visuals.players.dynamicBoxes", true, "boolean")
    storeRegister("visuals.players.radar", true, "boolean")
    storeRegister("visuals.players.dormant", true, "boolean")
    storeRegister("visuals.players.shared", true, "boolean")
    storeRegister("visuals.players.soundEsp", "Disabled", "string")
    storeRegister("visuals.players.offscreen", "Disabled", "string")
    storeRegister("visuals.players.radius", 150, "number", clampNumber(150, 0, 500))
    storeRegister("visuals.players.glow", false, "boolean")
    storeRegister("visuals.players.chams", true, "boolean")
    storeRegister("visuals.players.chamsWalls", false, "boolean")
    storeRegister("visuals.players.chamsStyle", "Glow Outline", "string")
    storeRegister("visuals.players.backtrack", false, "boolean")
    storeRegister("visuals.players.backtrackStyle", "Textured", "string")
    storeRegister("visuals.players.onShot", false, "boolean")
    storeRegister("visuals.players.onShotStyle", "Textured", "string")
    storeRegister("visuals.players.ragdolls", false, "boolean")
    storeRegister("visuals.players.ragdollsStyle", "Textured", "string")
    storeRegister("visuals.players.chipList", {}, "table", function(v)
        if type(v) ~= "table" then return {} end
        local out = {}
        for index, item in ipairs(v) do
            if index > 24 then break end
            if type(item) == "string" then table.insert(out, item) end
        end
        return out
    end)

    storeRegister("visuals.weapon.esp", false, "boolean")
    storeRegister("visuals.weapon.ammo", false, "boolean")
    storeRegister("visuals.weapon.names", false, "boolean")

    storeRegister("visuals.grenades.esp", false, "boolean")
    storeRegister("visuals.grenades.timer", false, "boolean")
    storeRegister("visuals.grenades.trail", false, "boolean")

    storeRegister("visuals.world.bomb", false, "boolean")
    storeRegister("visuals.world.dropped", false, "boolean")
    storeRegister("visuals.world.projectiles", false, "boolean")

    storeRegister("visuals.view.model", false, "boolean")
    storeRegister("visuals.view.thirdperson", false, "boolean")
    storeRegister("visuals.view.fov", 90, "number", clampNumber(90, 60, 130))

    storeRegister("misc.main.bunnyhop", false, "boolean")
    storeRegister("misc.main.autoPeek", false, "boolean")
    storeRegister("misc.main.fakeDuck", false, "boolean")
    storeRegister("misc.main.autoAccept", false, "boolean")
    storeRegister("misc.main.ping", 0, "number", clampNumber(0, 0, 400))

    storeRegister("misc.inventory.skinChanger", false, "boolean")
    storeRegister("misc.inventory.knifeModel", "Default", "string")
    storeRegister("misc.inventory.gloveModel", "Default", "string")

    storeRegister("misc.scripts.sandbox", "", "string", function(v)
        return sanitizeText(v, 8192)
    end)

    storeRegister("misc.configs.name", "default", "string", function(v)
        local clean = sanitizeText(v, 32):gsub("[^%w_%-%.]", "")
        if clean == "" then return "default" end
        return clean
    end)

    storeRegister("preview.health", true, "boolean")
end

--================================================================================
-- PERSISTENCE
--================================================================================

local Persistence = { available = false }

local function persistenceInit()
    if not (Executor.writefile and Executor.readfile and Executor.isfile) then
        return
    end
    if Executor.isfolder and Executor.makefolder then
        local ok, exists = pcall(Executor.isfolder, CONFIG.Folder)
        if not (ok and exists) then
            pcall(Executor.makefolder, CONFIG.Folder)
        end
    end
    Persistence.available = true
end

local function serializeValues()
    local out = {}
    for key, entry in pairs(Store.schema) do
        local value = Store.values[key]
        if value == nil then value = entry.default end
        if type(value) == "table" then
            local copy = {}
            for k, v in pairs(value) do
                local tv = type(v)
                if tv == "string" or tv == "number" or tv == "boolean" then
                    copy[k] = v
                end
            end
            out[key] = copy
        elseif type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            out[key] = value
        end
    end
    return out
end

local function coerceAgainstSchema(key, value)
    local entry = Store.schema[key]
    if not entry then return nil end

    if entry.kind == "boolean" then
        if type(value) ~= "boolean" then return nil end
    elseif entry.kind == "number" then
        local n = tonumber(value)
        if not n then return nil end
        value = n
    elseif entry.kind == "string" then
        if type(value) ~= "string" then return nil end
        value = string.sub(value, 1, 8192)
    elseif entry.kind == "table" then
        if type(value) ~= "table" then return nil end
    elseif entry.kind == "keybind" then
        if type(value) ~= "table" then return nil end
        local mode = value.mode
        if mode ~= "Toggle" and mode ~= "Hold" and mode ~= "Always" then
            mode = "Toggle"
        end
        local keyName = value.key
        if type(keyName) ~= "string" or not keyNameToEnum(keyName) then
            keyName = "None"
        end
        value = { key = keyName, mode = mode, show = value.show ~= false }
    end

    if entry.validate then
        local ok, validated = pcall(entry.validate, value)
        if ok then value = validated else return nil end
    end
    return value
end

local function applyConfig(decoded)
    if type(decoded) ~= "table" then return 0 end
    local applied = 0
    for key, value in pairs(decoded) do
        local coerced = coerceAgainstSchema(key, value)
        if coerced ~= nil then
            Store.values[key] = coerced
            applied = applied + 1
        end
    end
    return applied
end

local function renderAll()
    for key, renderers in pairs(Store.renderers) do
        local value = storeGet(key)
        for _, fn in ipairs(renderers) do
            pcall(fn, value)
        end
    end
end

local function writeConfigTo(path)
    if not (Persistence.available and Executor.writefile) then return false end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(serializeValues())
    end)
    if not ok or type(encoded) ~= "string" then return false end
    return pcall(Executor.writefile, path, encoded) == true
end

local function readConfigFrom(path)
    if not (Persistence.available and Executor.readfile and Executor.isfile) then return nil end
    local ok, exists = pcall(Executor.isfile, path)
    if not ok or not exists then return nil end
    local readOk, contents = pcall(Executor.readfile, path)
    if not readOk or type(contents) ~= "string" or contents == "" then return nil end
    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(contents)
    end)
    if not decodedOk then return nil end
    return decoded
end

local saveToken = 0

markDirty = function()
    saveToken = saveToken + 1
    local token = saveToken
    spawnTracked(function()
        task.wait(CONFIG.AutoSaveDebounce)
        if token ~= saveToken then return end
        writeConfigTo(CONFIG.File)
    end)
end

local function saveNow()
    return writeConfigTo(CONFIG.File)
end

--================================================================================
-- NOTIFICATIONS
--================================================================================

local ToastHost
local notificationHistory = {}

local function toastInit(parent)
    ToastHost = new("Frame", {
        Name = "ToastHost",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 18),
        Size = UDim2.new(0, 288, 1, -36),
        BackgroundTransparency = 1,
        ZIndex = 60,
    }, parent)
    listLayout(ToastHost, 8, Enum.FillDirection.Vertical)
end

local function notify(message, kind)
    local text = sanitizeText(message, 120)
    table.insert(notificationHistory, { message = text, kind = kind or "info" })
    if #notificationHistory > 50 then
        table.remove(notificationHistory, 1)
    end

    if not ToastHost then return end

    local color = THEME.Accent
    if kind == "success" then color = THEME.Success end
    if kind == "warning" then color = THEME.Warning end
    if kind == "error" then color = THEME.Danger end

    local existing = {}
    for _, child in ipairs(ToastHost:GetChildren()) do
        if child:IsA("Frame") then table.insert(existing, child) end
    end
    if #existing >= CONFIG.MaxToasts then
        existing[1]:Destroy()
    end

    local toast = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = THEME.Panel,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, ToastHost)
    corner(toast, 6)
    stroke(toast, THEME.Stroke)

    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 1, -16),
        Position = UDim2.new(0, 10, 0, 8),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, toast)
    corner(bar, 2)

    new("TextLabel", {
        Position = UDim2.new(0, 22, 0, 0),
        Size = UDim2.new(1, -32, 1, 0),
        BackgroundTransparency = 1,
        Font = FONT.Medium,
        Text = text,
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 62,
    }, toast)

    toast.BackgroundTransparency = 1
    tween(toast, { BackgroundTransparency = 0.05 }, 0.16)

    spawnTracked(function()
        task.wait(CONFIG.ToastLifetime)
        if toast and toast.Parent then
            tween(toast, { BackgroundTransparency = 1 }, 0.24)
            task.wait(0.26)
            pcall(function() toast:Destroy() end)
        end
    end)
end

--================================================================================
-- UI CONSTRUCTION
--================================================================================

local Ui = {
    root = nil,
    window = nil,
    overlay = nil,
    preview = nil,
    pages = {},
    navButtons = {},
    popups = {},
    currentPage = nil,
    visible = true,
}

local function resolveParent()
    if Executor.gethui then
        local ok, result = pcall(Executor.gethui)
        if ok and typeof(result) == "Instance" then
            return result
        end
    end
    local ok, result = pcall(function() return CoreGui end)
    if ok and result then
        return result
    end
    if LocalPlayer then
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then return playerGui end
    end
    return nil
end

local function buildRoot()
    local parent = resolveParent()
    if not parent then return nil end

    local gui = new("ScreenGui", {
        Name = "NEVERLOSE",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
    }, parent)

    if Executor.protectgui then
        pcall(Executor.protectgui, gui)
    end

    Ui.root = gui
    toastInit(gui)
    return gui
end

local function closeAllPopups()
    for index = #Ui.popups, 1, -1 do
        local popup = Ui.popups[index]
        if popup and popup.Parent then
            popup:Destroy()
        end
    end
    Ui.popups = {}
end

local function openPopup(anchorButton, height)
    closeAllPopups()
    local overlay = Ui.overlay
    local popup = new("Frame", {
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 40,
        Size = UDim2.fromOffset(anchorButton.AbsoluteSize.X, height),
        Position = UDim2.fromOffset(
            math.floor(anchorButton.AbsolutePosition.X - overlay.AbsolutePosition.X),
            math.floor(anchorButton.AbsolutePosition.Y - overlay.AbsolutePosition.Y + anchorButton.AbsoluteSize.Y + 4)
        ),
    }, overlay)
    corner(popup, 5)
    stroke(popup, THEME.Stroke)
    table.insert(Ui.popups, popup)
    return popup
end

local function buildTopbar(parent)
    local bar = new("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = THEME.Topbar,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, parent)
    stroke(bar, THEME.StrokeSoft)

    local saveButton = new("TextButton", {
        Name = "Save",
        Size = UDim2.fromOffset(76, 28),
        Position = UDim2.fromOffset(16, 12),
        BackgroundColor3 = THEME.Row,
        AutoButtonColor = false,
        Font = FONT.Medium,
        Text = "Save",
        TextColor3 = THEME.Text,
        TextSize = 12,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, bar)
    corner(saveButton, 5)
    stroke(saveButton, THEME.Stroke)
    track(saveButton.MouseEnter:Connect(function()
        tween(saveButton, { BackgroundColor3 = THEME.RowHover }, 0.12)
    end))
    track(saveButton.MouseLeave:Connect(function()
        tween(saveButton, { BackgroundColor3 = THEME.Row }, 0.12)
    end))
    track(saveButton.MouseButton1Click:Connect(function()
        if saveNow() then
            notify("Configuration saved", "success")
        else
            notify("Save unavailable — in-memory only", "warning")
        end
    end))

    local actions = new("Frame", {
        Name = "Actions",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -98, 0, 12),
        Size = UDim2.fromOffset(96, 28),
        BackgroundTransparency = 1,
        ZIndex = 11,
    }, bar)
    listLayout(actions, 6, Enum.FillDirection.Horizontal)
    actions.HorizontalAlignment = Enum.HorizontalAlignment.Right

    local function iconButton(glyph)
        local button = new("TextButton", {
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = THEME.Row,
            AutoButtonColor = false,
            Font = FONT.Bold,
            Text = glyph,
            TextColor3 = THEME.Muted,
            TextSize = 13,
            BorderSizePixel = 0,
            LayoutOrder = 1,
            ZIndex = 12,
        }, actions)
        corner(button, 5)
        stroke(button, THEME.Stroke)
        track(button.MouseEnter:Connect(function()
            tween(button, { BackgroundColor3 = THEME.RowHover, TextColor3 = THEME.Text }, 0.12)
        end))
        track(button.MouseLeave:Connect(function()
            tween(button, { BackgroundColor3 = THEME.Row, TextColor3 = THEME.Muted }, 0.12)
        end))
        return button
    end

    Ui.settingsButton = iconButton("⚙")
    Ui.bellButton = iconButton("◔")
    Ui.searchButton = iconButton("⌕")
    return bar
end

local function buildSidebar(parent)
    local bar = new("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 196, 1, -52),
        Position = UDim2.new(0, 0, 0, 52),
        BackgroundColor3 = THEME.Sidebar,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, parent)
    stroke(bar, THEME.StrokeSoft)

    local brand = new("TextLabel", {
        Name = "Brand",
        Size = UDim2.new(1, -20, 0, 34),
        Position = UDim2.fromOffset(16, 10),
        BackgroundTransparency = 1,
        Font = FONT.Bold,
        Text = "NEVERLOSE",
        TextColor3 = THEME.Text,
        TextSize = 19,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 11,
    }, bar)

    local logoPath = resolveAsset(ASSETS.Logo)
    if logoPath then
        brand.Text = ""
        new("ImageLabel", {
            Size = UDim2.fromOffset(128, 22),
            BackgroundTransparency = 1,
            Image = logoPath,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 12,
        }, brand)
    end

    local userCard = new("Frame", {
        Name = "UserCard",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 10, 1, -10),
        Size = UDim2.new(1, -20, 0, 52),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, bar)
    corner(userCard, 6)
    stroke(userCard, THEME.Stroke)

    local avatar = new("Frame", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.fromOffset(10, 12),
        BackgroundColor3 = THEME.AccentDeep,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, userCard)
    corner(avatar, 14)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = FONT.Bold,
        Text = "N",
        TextColor3 = THEME.Background,
        TextSize = 13,
        ZIndex = 13,
    }, avatar)

    new("TextLabel", {
        Position = UDim2.fromOffset(46, 10),
        Size = UDim2.new(1, -54, 0, 16),
        BackgroundTransparency = 1,
        Font = FONT.Bold,
        Text = string.upper(LocalPlayer and LocalPlayer.DisplayName or "PAKETA"),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
    }, userCard)

    new("TextLabel", {
        Position = UDim2.fromOffset(46, 26),
        Size = UDim2.new(1, -54, 0, 14),
        BackgroundTransparency = 1,
        Font = FONT.Regular,
        Text = "TILL: 01.01.03.00",
        TextColor3 = THEME.Dim,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12,
    }, userCard)

    local navHost = new("ScrollingFrame", {
        Name = "Nav",
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -164),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 11,
    }, bar)
    padding(navHost, 2)
    listLayout(navHost, 2)

    Ui.navHost = navHost
    return bar
end

local NAV_DEFINITION = {
    { section = "AimBot" },
    { id = "ragebot", label = "Ragebot", glyph = "◈" },
    { id = "antiaim", label = "Anti Aim", glyph = "↺" },
    { id = "legitbot", label = "Legitbot", glyph = "◉" },
    { section = "Visuals" },
    { id = "players", label = "Players", glyph = "▣" },
    { id = "weapon", label = "Weapon", glyph = "✦" },
    { id = "grenades", label = "Grenades", glyph = "◐" },
    { id = "world", label = "World", glyph = "◍" },
    { id = "view", label = "View", glyph = "◑" },
    { section = "Miscellaneous" },
    { id = "main", label = "Main", glyph = "✧" },
    { id = "inventory", label = "Inventory", glyph = "◇" },
    { id = "scripts", label = "Scripts", glyph = "⟨⟩" },
    { id = "configs", label = "Configs", glyph = "◈" },
}

local function buildNav()
    local order = 0
    for _, entry in ipairs(NAV_DEFINITION) do
        order = order + 1
        if entry.section then
            local header = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundTransparency = 1,
                Font = FONT.Bold,
                Text = "  " .. string.upper(entry.section),
                TextColor3 = THEME.Dim,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = order,
                ZIndex = 12,
            }, Ui.navHost)
            header.LayoutOrder = order
        else
            local button = new("TextButton", {
                Name = entry.id,
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundColor3 = THEME.Sidebar,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = order,
                ZIndex = 12,
            }, Ui.navHost)
            corner(button, 5)

            local marker = new("Frame", {
                Size = UDim2.new(0, 2, 0, 16),
                Position = UDim2.new(0, 0, 0.5, -8),
                BackgroundColor3 = THEME.Accent,
                BorderSizePixel = 0,
                BackgroundTransparency = 1,
                ZIndex = 13,
            }, button)
            corner(marker, 1)

            local glyph = new("TextLabel", {
                Size = UDim2.fromOffset(22, 32),
                Position = UDim2.fromOffset(14, 0),
                BackgroundTransparency = 1,
                Font = FONT.Bold,
                Text = entry.glyph,
                TextColor3 = THEME.Muted,
                TextSize = 13,
                ZIndex = 13,
            }, button)

            local label = new("TextLabel", {
                Position = UDim2.fromOffset(42, 0),
                Size = UDim2.new(1, -50, 1, 0),
                BackgroundTransparency = 1,
                Font = FONT.Medium,
                Text = entry.label,
                TextColor3 = THEME.Muted,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 13,
            }, button)

            Ui.navButtons[entry.id] = {
                button = button,
                label = label,
                glyph = glyph,
                marker = marker,
            }

            track(button.MouseEnter:Connect(function()
                if Ui.currentPage == entry.id then return end
                label.TextColor3 = THEME.Text
                glyph.TextColor3 = THEME.Text
            end))
            track(button.MouseLeave:Connect(function()
                if Ui.currentPage == entry.id then return end
                label.TextColor3 = THEME.Muted
                glyph.TextColor3 = THEME.Muted
            end))
            track(button.MouseButton1Click:Connect(function()
                Ui.selectPage(entry.id)
            end))
        end
    end
end

local function buildContent(parent)
    local content = new("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -196, 1, -52),
        Position = UDim2.new(0, 196, 0, 52),
        BackgroundTransparency = 1,
        ZIndex = 10,
    }, parent)
    Ui.content = content
    return content
end

local function buildPageSurface(pageId)
    local surface = new("Frame", {
        Name = pageId,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 11,
    }, Ui.content)

    local left = new("ScrollingFrame", {
        Name = "Left",
        Position = UDim2.fromOffset(14, 14),
        Size = UDim2.new(0.5, -20, 1, -28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 11,
    }, surface)
    listLayout(left, 10)

    local right = new("ScrollingFrame", {
        Name = "Right",
        Position = UDim2.new(0.5, 6, 0, 14),
        Size = UDim2.new(0.5, -20, 1, -28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 11,
    }, surface)
    listLayout(right, 10)

    Ui.pages[pageId] = { surface = surface, left = left, right = right, built = false }
    return Ui.pages[pageId]
end

local function buildCard(parent, title)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Card,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, parent)
    corner(card, 6)
    stroke(card, THEME.StrokeSoft)
    padding(card, 12)

    local host = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 12,
    }, card)
    listLayout(host, 4)

    if title then
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            Font = FONT.Bold,
            Text = title,
            TextColor3 = THEME.Text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = -2,
            ZIndex = 12,
        }, host)
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = THEME.StrokeSoft,
            BorderSizePixel = 0,
            LayoutOrder = -1,
            ZIndex = 12,
        }, host)
    end

    return host
end

--================================================================================
-- CONTROLS
-- Every control renders from the store and writes only to the store.
--================================================================================

local orderCounter = 0
local function nextOrder()
    orderCounter = orderCounter + 1
    return orderCounter
end

local function registerControl(key, label, pageId, kind)
    table.insert(Store.registry, { key = key, label = label, page = pageId, kind = kind })
end

local function rowLabel(parent, text, widthReserve)
    return new("TextLabel", {
        Size = UDim2.new(1, -(widthReserve or 110), 1, 0),
        BackgroundTransparency = 1,
        Font = FONT.Medium,
        Text = text,
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 13,
    }, parent)
end

local function controlToggle(parent, key, label, pageId)
    registerControl(key, label, pageId, "toggle")
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, parent)
    rowLabel(row, label)

    local trackFrame = new("Frame", {
        Name = "Track",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(38, 18),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
        ZIndex = 13,
    }, row)
    corner(trackFrame, 9)

    local thumb = new("Frame", {
        Name = "Thumb",
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = THEME.Muted,
        BorderSizePixel = 0,
        ZIndex = 14,
    }, trackFrame)
    corner(thumb, 6)

    storeOnRender(key, function(value)
        local on = value == true
        tween(trackFrame, { BackgroundColor3 = on and THEME.Accent or THEME.Stroke }, 0.14)
        tween(thumb, {
            Position = UDim2.fromOffset(on and 23 or 3, 3),
            BackgroundColor3 = on and THEME.Text or THEME.Muted,
        }, 0.14)
    end)

    track(row.MouseButton1Click:Connect(function()
        storeSet(key, not (storeGet(key) == true))
    end))
    return row
end

local function controlSlider(parent, key, label, minValue, maxValue, step, suffix, pageId)
    registerControl(key, label, pageId, "slider")
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, parent)
    rowLabel(row, label)

    local readout = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(46, 18),
        BackgroundColor3 = THEME.Row,
        Font = FONT.Medium,
        Text = formatNumber(storeGet(key)),
        TextColor3 = THEME.Text,
        TextSize = 11,
        BorderSizePixel = 0,
        ZIndex = 13,
    }, row)
    corner(readout, 4)
    stroke(readout, THEME.Stroke)

    local trackFrame = new("Frame", {
        Name = "Track",
        Position = UDim2.fromOffset(0, 26),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
        ZIndex = 13,
    }, row)
    corner(trackFrame, 2)

    local fill = new("Frame", {
        Name = "Fill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 14,
    }, trackFrame)
    corner(fill, 2)

    local knob = new("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(11, 11),
        BackgroundColor3 = THEME.Text,
        BorderSizePixel = 0,
        ZIndex = 15,
    }, trackFrame)
    corner(knob, 6)

    storeOnRender(key, function(value)
        local ratio = 0
        if maxValue > minValue then
            ratio = clamp((value - minValue) / (maxValue - minValue), 0, 1)
        end
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        knob.Position = UDim2.new(ratio, 0, 0.5, 0)
        readout.Text = formatNumber(value) .. (suffix or "")
    end)

    local dragging = false
    local function updateFromInput(input)
        local relative = (input.Position.X - trackFrame.AbsolutePosition.X) / math.max(trackFrame.AbsoluteSize.X, 1)
        relative = clamp(relative, 0, 1)
        local raw = minValue + relative * (maxValue - minValue)
        storeSet(key, clamp(roundToStep(raw, minValue, step), minValue, maxValue))
    end

    track(trackFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            updateFromInput(input)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    return row
end

local function popupList(popup, items, onSelect, isSelected)
    local scroll = new("ScrollingFrame", {
        Size = UDim2.new(1, -6, 1, -6),
        Position = UDim2.fromOffset(3, 3),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 41,
    }, popup)
    listLayout(scroll, 1)

    for index, item in ipairs(items) do
        if index > 64 then break end
        local option = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = THEME.RowHover,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Font = FONT.Medium,
            Text = item,
            TextColor3 = (isSelected and isSelected(item)) and THEME.Accent or THEME.Muted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            BorderSizePixel = 0,
            LayoutOrder = index,
            ZIndex = 42,
        }, scroll)
        option.Text = "  " .. item
        track(option.MouseEnter:Connect(function()
            option.BackgroundTransparency = 0
        end))
        track(option.MouseLeave:Connect(function()
            option.BackgroundTransparency = 1
        end))
        track(option.MouseButton1Click:Connect(function()
            onSelect(item)
        end))
    end
    return scroll
end

local function controlDropdown(parent, key, label, items, pageId, options)
    options = options or {}
    registerControl(key, label, pageId, "dropdown")
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, parent)
    rowLabel(row, label, 150)

    local button = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(options.width or 132, 22),
        BackgroundColor3 = THEME.Row,
        AutoButtonColor = false,
        Font = FONT.Medium,
        Text = tostring(storeGet(key)),
        TextColor3 = THEME.Text,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BorderSizePixel = 0,
        ZIndex = 13,
    }, row)
    corner(button, 4)
    stroke(button, THEME.Stroke)

    storeOnRender(key, function(value)
        button.Text = tostring(value)
    end)

    track(button.MouseButton1Click:Connect(function()
        local popup = openPopup(button, math.min(26 * math.min(#items, 7) + 8, 200))
        popupList(popup, items, function(item)
            storeSet(key, item)
            closeAllPopups()
        end, function(item)
            return item == storeGet(key)
        end)
    end))

    return row
end

local function controlText(parent, key, label, pageId, placeholder, options)
    options = options or {}
    registerControl(key, label, pageId, "text")
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, parent)
    rowLabel(row, label, 150)

    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(options.width or 132, 22),
        BackgroundColor3 = THEME.Row,
        Font = FONT.Medium,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = THEME.Dim,
        Text = "",
        TextColor3 = THEME.Text,
        TextSize = 11,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 13,
    }, row)
    corner(box, 4)
    stroke(box, THEME.Stroke)

    local function paint(value)
        if not box:IsFocused() then
            box.Text = "  " .. tostring(value or "")
        end
    end
    paint(storeGet(key))
    storeOnRender(key, paint)

    track(box.FocusLost:Connect(function(enterPressed)
        local clean = sanitizeText((box.Text:gsub("^%s+", "")), options.maxLength or 64)
        storeSet(key, clean)
        paint(clean)
        if enterPressed then
            notify("Value set: " .. tostring(clean), "success")
        end
    end))

    return row
end

local function controlKeybind(parent, key, label, pageId)
    registerControl(key, label, pageId, "keybind")
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, parent)
    rowLabel(row, label, 150)

    local button = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(110, 22),
        BackgroundColor3 = THEME.Row,
        AutoButtonColor = false,
        Font = FONT.Medium,
        Text = "None",
        TextColor3 = THEME.Text,
        TextSize = 11,
        BorderSizePixel = 0,
        ZIndex = 13,
    }, row)
    corner(button, 4)
    stroke(button, THEME.Stroke)

    local function current()
        local value = storeGet(key)
        if type(value) ~= "table" then
            value = { key = "None", mode = "Toggle", show = true }
        end
        return value
    end

    local function render()
        local value = current()
        button.Text = value.key .. " · " .. value.mode
    end
    storeOnRender(key, render)

    track(button.MouseButton1Click:Connect(function()
        local popup = openPopup(button, 132)
        padding(popup, 8)
        local host = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ZIndex = 41,
        }, popup)
        listLayout(host, 6)

        local function field(rowLabelText, initialText, onClick)
            local fieldRow = new("Frame", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                LayoutOrder = nextOrder(),
                ZIndex = 41,
            }, host)
            rowLabel(fieldRow, rowLabelText, 60)
            local fieldButton = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(96, 22),
                BackgroundColor3 = THEME.Row,
                AutoButtonColor = false,
                Font = FONT.Medium,
                Text = initialText,
                TextColor3 = THEME.Text,
                TextSize = 11,
                BorderSizePixel = 0,
                ZIndex = 42,
            }, fieldRow)
            corner(fieldButton, 4)
            stroke(fieldButton, THEME.Stroke)
            track(fieldButton.MouseButton1Click:Connect(function()
                onClick(fieldButton)
            end))
            return fieldButton
        end

        field("Key", current().key, function(fieldButton)
            fieldButton.Text = "press…"
            local connection
            connection = UserInputService.InputBegan:Connect(function(input, processed)
                if processed then return end
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if MODIFIER_KEYS[input.KeyCode] then return end
                local value = current()
                value.key = enumToKeyName(input.KeyCode)
                storeSet(key, value)
                fieldButton.Text = value.key
                render()
                notify("Bound to " .. value.key, "success")
                if connection then connection:Disconnect() end
                closeAllPopups()
            end)
        end)

        field("Mode", current().mode, function(fieldButton)
            local modes = { "Toggle", "Hold", "Always" }
            local value = current()
            local index = 1
            for position, mode in ipairs(modes) do
                if mode == value.mode then index = position end
            end
            index = (index % #modes) + 1
            value.mode = modes[index]
            storeSet(key, value)
            fieldButton.Text = value.mode
            render()
        end)
    end))

    return row
end

--================================================================================
-- PAGE BUILDERS
--================================================================================

local PageBuilders = {}

PageBuilders.ragebot = function(page)
    local mainCard = buildCard(page.left, "Main")
    controlToggle(mainCard, "aimbot.ragebot.enabled", "Enable Ragebot", "ragebot")
    controlToggle(mainCard, "aimbot.ragebot.silent", "Silent Aim", "ragebot")
    controlSlider(mainCard, "aimbot.ragebot.fov", "FOV", 1, 360, 1, "", "ragebot")
    controlToggle(mainCard, "aimbot.ragebot.resolver", "Override Resolver", "ragebot")

    local accuracy = buildCard(page.left, "Accuracy")
    controlSlider(accuracy, "aimbot.ragebot.hitChance", "Hit Chance", 0, 100, 1, "%", "ragebot")
    controlToggle(accuracy, "aimbot.ragebot.pointScale", "Static Point Scale", "ragebot")
    controlDropdown(accuracy, "aimbot.ragebot.safePoints", "Safe Points", { "Default", "Always", "Never", "Lethal" }, "ragebot")
    controlDropdown(accuracy, "aimbot.ragebot.forceConditions", "Force Conditions", { "Select", "Air", "Standing", "Crouch", "Moving" }, "ragebot")
    controlToggle(accuracy, "aimbot.ragebot.headSafety", "Head Safety If Lethal", "ragebot")
    controlDropdown(accuracy, "aimbot.ragebot.bodyAim", "Body Aim", { "Default", "Head", "Chest", "Stomach", "Nearest" }, "ragebot")
    controlSlider(accuracy, "aimbot.ragebot.maxMisses", "Max Misses", 0, 10, 1, "", "ragebot")

    local exploits = buildCard(page.right, "Exploits")
    controlToggle(exploits, "aimbot.ragebot.hideShots", "Hide Shots", "ragebot")
    controlToggle(exploits, "aimbot.ragebot.doubleTap", "Double Tap", "ragebot")
    controlDropdown(exploits, "aimbot.ragebot.mode", "Mode", { "Default", "Instant", "Defensive", "Fast" }, "ragebot")
    controlToggle(exploits, "aimbot.ragebot.teleportBoost", "Teleport Boost", "ragebot")
    controlKeybind(exploits, "aimbot.ragebot.bind", "Bind", "ragebot")

    local minDamage = buildCard(page.right, "Min. Damage")
    controlDropdown(minDamage, "aimbot.ragebot.minDamageVisible", "Visible", { "Auto", "Low", "Medium", "High", "Override" }, "ragebot", { width = 96 })
    controlDropdown(minDamage, "aimbot.ragebot.minDamageAutowall", "Autowall", { "Auto", "Low", "Medium", "High", "Override" }, "ragebot", { width = 96 })

    local misc = buildCard(page.right, "Misc")
    controlToggle(misc, "aimbot.ragebot.autoStop", "Auto Stop", "ragebot")
    controlDropdown(misc, "aimbot.ragebot.conditions", "Conditions", { "Select", "Lethal", "Low HP", "Reloading" }, "ragebot")
    controlToggle(misc, "aimbot.ragebot.autoScope", "Auto Scope", "ragebot")
end

PageBuilders.antiaim = function(page)
    local card = buildCard(page.left, "Anti Aim")
    controlToggle(card, "aimbot.antiaim.enabled", "Enable Anti Aim", "antiaim")
    controlDropdown(card, "aimbot.antiaim.pitch", "Pitch", { "Default", "Up", "Down", "Zero", "Fake" }, "antiaim")
    controlDropdown(card, "aimbot.antiaim.yaw", "Yaw", { "Default", "Forward", "Backward", "Left", "Right", "Jitter" }, "antiaim")
    controlSlider(card, "aimbot.antiaim.jitter", "Jitter Range", 0, 180, 1, "°", "antiaim")
end

PageBuilders.legitbot = function(page)
    local card = buildCard(page.left, "Legitbot")
    controlToggle(card, "aimbot.legitbot.enabled", "Enable Legitbot", "legitbot")
    controlSlider(card, "aimbot.legitbot.smoothing", "Smoothing", 1, 30, 1, "", "legitbot")
    controlSlider(card, "aimbot.legitbot.fov", "FOV", 1, 90, 1, "", "legitbot")
end

local ALL_CHIPS = {
    "Money", "Scoped", "Flashed", "Defusing", "Armor", "Hit", "Has Bomb", "Ammo",
    "FakeDuck", "Break LC", "Distance", "Taser", "Item Name", "Ping", "Item Icon",
}

local function toggleChip(name)
    local list = storeGet("visuals.players.chipList")
    if type(list) ~= "table" then list = {} end
    local rebuilt = {}
    local found = false
    for _, item in ipairs(list) do
        if item == name then found = true else table.insert(rebuilt, item) end
    end
    if not found then table.insert(rebuilt, name) end
    storeSet("visuals.players.chipList", rebuilt)
end

local function chipActive(name)
    local list = storeGet("visuals.players.chipList")
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
        if item == name then return true end
    end
    return false
end

PageBuilders.players = function(page)
    local esp = buildCard(page.left, "ESP")
    controlToggle(esp, "visuals.players.esp", "Enable ESP", "players")
    controlToggle(esp, "visuals.players.espWalls", "Through Walls", "players")
    controlDropdown(esp, "visuals.players.bulletTracer", "Bullet Tracer", { "Disabled", "Beam", "Line", "Rifle" }, "players")
    controlToggle(esp, "visuals.players.dynamicBoxes", "Dynamic Boxes", "players")
    controlToggle(esp, "visuals.players.radar", "In-Game Radar", "players")
    controlToggle(esp, "visuals.players.dormant", "Dormant", "players")
    controlToggle(esp, "visuals.players.shared", "Shared ESP", "players")
    controlDropdown(esp, "visuals.players.soundEsp", "Sound ESP", { "Disabled", "Circle", "Ring", "Pulse" }, "players")
    controlDropdown(esp, "visuals.players.offscreen", "Offscreen ESP", { "Disabled", "Arrow", "Dot", "Edge" }, "players")
    controlSlider(esp, "visuals.players.radius", "Radius", 0, 500, 1, "", "players")

    local glow = buildCard(page.left, "Glow")
    controlToggle(glow, "visuals.players.glow", "Enable Glow", "players")

    local chams = buildCard(page.right, "Chams")
    controlToggle(chams, "visuals.players.chams", "Enable Chams", "players")
    controlToggle(chams, "visuals.players.chamsWalls", "Through Walls", "players")
    controlDropdown(chams, "visuals.players.chamsStyle", "Style", { "Textured", "Flat", "Glow", "Glow Outline", "Glass", "Material" }, "players")
    controlToggle(chams, "visuals.players.backtrack", "Backtrack", "players")
    controlDropdown(chams, "visuals.players.backtrackStyle", "Style", { "Textured", "Flat", "Glow", "Glow Outline", "Glass", "Material" }, "players")
    controlToggle(chams, "visuals.players.onShot", "On Shot", "players")
    controlDropdown(chams, "visuals.players.onShotStyle", "Style", { "Textured", "Flat", "Glow", "Glow Outline", "Glass", "Material" }, "players")
    controlToggle(chams, "visuals.players.ragdolls", "Ragdolls", "players")
    controlDropdown(chams, "visuals.players.ragdollsStyle", "Style", { "Textured", "Flat", "Glow", "Glow Outline", "Glass", "Material" }, "players")

    local chips = buildCard(page.right, "Drag & Drop Elements")
    local chipHost = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, chips)
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.fromOffset(74, 22)
    grid.CellPadding = UDim2.fromOffset(6, 6)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = chipHost

    local chipButtons = {}
    for index, name in ipairs(ALL_CHIPS) do
        local chip = new("TextButton", {
            BackgroundColor3 = THEME.Row,
            AutoButtonColor = false,
            Font = FONT.Medium,
            Text = name,
            TextColor3 = THEME.Muted,
            TextSize = 11,
            BorderSizePixel = 0,
            LayoutOrder = index,
            ZIndex = 13,
        }, chipHost)
        corner(chip, 4)
        stroke(chip, THEME.Stroke)
        chipButtons[name] = chip
        track(chip.MouseButton1Click:Connect(function()
            toggleChip(name)
        end))
    end

    storeOnRender("visuals.players.chipList", function()
        for name, chip in pairs(chipButtons) do
            local active = chipActive(name)
            chip.TextColor3 = active and THEME.Accent or THEME.Muted
            chip.BackgroundColor3 = active and THEME.CardAlt or THEME.Row
        end
    end)
end

PageBuilders.weapon = function(page)
    local card = buildCard(page.left, "Weapon")
    controlToggle(card, "visuals.weapon.esp", "Weapon ESP", "weapon")
    controlToggle(card, "visuals.weapon.ammo", "Ammo Counter", "weapon")
    controlToggle(card, "visuals.weapon.names", "Weapon Names", "weapon")
end

PageBuilders.grenades = function(page)
    local card = buildCard(page.left, "Grenades")
    controlToggle(card, "visuals.grenades.esp", "Grenade ESP", "grenades")
    controlToggle(card, "visuals.grenades.timer", "Fuse Timer", "grenades")
    controlToggle(card, "visuals.grenades.trail", "Trajectory Trail", "grenades")
end

PageBuilders.world = function(page)
    local card = buildCard(page.left, "World")
    controlToggle(card, "visuals.world.bomb", "Bomb ESP", "world")
    controlToggle(card, "visuals.world.dropped", "Dropped Weapons", "world")
    controlToggle(card, "visuals.world.projectiles", "Projectiles", "world")
end

PageBuilders.view = function(page)
    local card = buildCard(page.left, "View")
    controlToggle(card, "visuals.view.model", "Wireframe Model", "view")
    controlToggle(card, "visuals.view.thirdperson", "Third Person", "view")
    controlSlider(card, "visuals.view.fov", "Field of View", 60, 130, 1, "°", "view")
end

PageBuilders.main = function(page)
    local card = buildCard(page.left, "Miscellaneous")
    controlToggle(card, "misc.main.bunnyhop", "Bunnyhop", "main")
    controlToggle(card, "misc.main.autoPeek", "Auto Peek", "main")
    controlToggle(card, "misc.main.fakeDuck", "Fake Duck", "main")
    controlToggle(card, "misc.main.autoAccept", "Auto Accept", "main")
    controlSlider(card, "misc.main.ping", "Ping Spike", 0, 400, 5, " ms", "main")

    local keyCard = buildCard(page.right, "Interface")
    controlKeybind(keyCard, "ui.toggleBind", "Toggle Menu", "main")
    controlText(keyCard, "ui.toggleKey", "Menu Key", "main", "RightShift")

    storeOnChange("ui.toggleBind", function(value)
        if type(value) == "table" and value.key and value.key ~= "None" then
            if storeGet("ui.toggleKey") ~= value.key then
                storeSet("ui.toggleKey", value.key)
            end
        end
    end)
end

PageBuilders.inventory = function(page)
    local card = buildCard(page.left, "Inventory")
    controlToggle(card, "misc.inventory.skinChanger", "Skin Changer", "inventory")
    controlDropdown(card, "misc.inventory.knifeModel", "Knife Model", { "Default", "Karambit", "Butterfly", "Bayonet", "Talon" }, "inventory")
    controlDropdown(card, "misc.inventory.gloveModel", "Glove Model", { "Default", "Sport", "Specialist", "Driver", "Hand Wraps" }, "inventory")
end

PageBuilders.scripts = function(page)
    local card = buildCard(page.left, "Script Runner")
    local editor = new("TextBox", {
        Size = UDim2.new(1, 0, 0, 132),
        BackgroundColor3 = THEME.Panel,
        Font = FONT.Medium,
        MultiLine = true,
        Text = storeGet("misc.scripts.sandbox"),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, card)
    padding(editor, 8)
    corner(editor, 4)
    stroke(editor, THEME.Stroke)

    track(editor:GetPropertyChangedSignal("Text"):Connect(function()
        Store.values["misc.scripts.sandbox"] = sanitizeText(editor.Text, 8192)
        markDirty()
    end))

    local runButton = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = THEME.Row,
        AutoButtonColor = false,
        Font = FONT.Bold,
        Text = "Execute",
        TextColor3 = THEME.Text,
        TextSize = 12,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, card)
    corner(runButton, 4)
    stroke(runButton, THEME.Stroke)
    track(runButton.MouseButton1Click:Connect(function()
        local source = sanitizeText(editor.Text, 8192)
        if source == "" then
            notify("Nothing to execute", "warning")
            return
        end
        if not Executor.loadstring then
            notify("loadstring unavailable in this executor", "error")
            return
        end
        local chunk, compileError = Executor.loadstring(source)
        if not chunk then
            notify("Compile error: " .. tostring(compileError), "error")
            return
        end
        local ok, runtimeError = pcall(chunk)
        if ok then
            notify("Script executed", "success")
        else
            notify("Runtime error: " .. tostring(runtimeError), "error")
        end
    end))
end

PageBuilders.configs = function(page)
    local card = buildCard(page.left, "Configuration")
    controlText(card, "misc.configs.name", "Config Name", "configs", "default")

    local function actionButton(text, callback, tone)
        local button = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = THEME.Row,
            AutoButtonColor = false,
            Font = FONT.Bold,
            Text = text,
            TextColor3 = tone or THEME.Text,
            TextSize = 12,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
            ZIndex = 12,
        }, card)
        corner(button, 4)
        stroke(button, THEME.Stroke)
        track(button.MouseButton1Click:Connect(callback))
        return button
    end

    actionButton("Save Current", function()
        if saveNow() then
            notify("Saved to " .. CONFIG.File, "success")
        else
            notify("Filesystem unavailable", "error")
        end
    end)

    actionButton("Load Saved", function()
        local decoded = readConfigFrom(CONFIG.File)
        if not decoded then
            notify("No saved config found", "warning")
            return
        end
        local applied = applyConfig(decoded)
        renderAll()
        notify("Loaded " .. tostring(applied) .. " values", "success")
    end)

    actionButton("Reset Defaults", function()
        for key, entry in pairs(Store.schema) do
            Store.values[key] = entry.default
        end
        renderAll()
        markDirty()
        notify("Defaults restored", "warning")
    end)

    actionButton("Delete Config", function()
        if Persistence.available and Executor.delfile then
            local ok = pcall(Executor.delfile, CONFIG.File)
            if ok then
                notify("Config deleted", "warning")
            else
                notify("Delete failed", "error")
            end
        else
            notify("Filesystem unavailable", "error")
        end
    end, THEME.Danger)

    local info = buildCard(page.right, "Persistence")
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT.Regular,
        Text = "Storage: " .. (Persistence.available and CONFIG.File or "in-memory only"),
        TextColor3 = THEME.Muted,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
        ZIndex = 12,
    }, info)

    controlToggle(info, "preview.health", "Preview Health Bar", "configs")
end

--================================================================================
-- PREVIEW PANEL
--================================================================================

local function buildPreview(parent)
    local panel = new("Frame", {
        Name = "Preview",
        Size = UDim2.fromOffset(CONFIG.Preview.Size.X, CONFIG.Preview.Size.Y),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, parent)
    corner(panel, 8)
    stroke(panel, THEME.Stroke)
    padding(panel, 12)

    local host = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 11,
    }, panel)
    listLayout(host, 8)

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Font = FONT.Medium,
        Text = "Interactive ESP Preview",
        TextColor3 = THEME.Muted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 1,
        ZIndex = 12,
    }, host)

    local stage = new("Frame", {
        Size = UDim2.new(1, 0, 0, 300),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        ZIndex = 11,
    }, host)
    corner(stage, 6)
    stroke(stage, THEME.StrokeSoft)

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        Position = UDim2.fromOffset(0, 6),
        BackgroundTransparency = 1,
        Font = FONT.Medium,
        Text = "neverlose.cc",
        TextColor3 = THEME.Text,
        TextSize = 12,
        ZIndex = 12,
    }, stage)

    local renderPath = resolveAsset(ASSETS.PreviewRender)
    if renderPath then
        new("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.54, 12),
            Size = UDim2.new(0.86, 0, 0.74, 0),
            BackgroundTransparency = 1,
            Image = renderPath,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 12,
        }, stage)
    else
        local figure = new("Frame", {
            Name = "Figure",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.56, 12),
            Size = UDim2.fromOffset(78, 196),
            BackgroundTransparency = 1,
            ZIndex = 12,
        }, stage)

        local silhouette = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = THEME.Background,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 12,
        }, figure)
        corner(silhouette, 6)
        stroke(silhouette, THEME.Success, 1, 0.25)

        local head = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.03, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundColor3 = THEME.Success,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, figure)
        corner(head, 13)

        local torso = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.18, 0),
            Size = UDim2.fromOffset(44, 66),
            BackgroundColor3 = THEME.Success,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, figure)
        corner(torso, 8)

        local legs = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.53, 0),
            Size = UDim2.fromOffset(38, 84),
            BackgroundColor3 = THEME.Success,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, figure)
        corner(legs, 8)

        local healthTrack = new("Frame", {
            Name = "HealthTrack",
            Position = UDim2.new(0, 32, 0.5, -66),
            Size = UDim2.fromOffset(3, 132),
            BackgroundColor3 = THEME.Stroke,
            BorderSizePixel = 0,
            ZIndex = 12,
        }, stage)
        corner(healthTrack, 2)
        local healthFill = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0.74, 0),
            BackgroundColor3 = THEME.Warning,
            BorderSizePixel = 0,
            ZIndex = 13,
        }, healthTrack)
        corner(healthFill, 2)

        new("TextLabel", {
            Position = UDim2.new(0, 40, 0.5, -58),
            Size = UDim2.fromOffset(40, 14),
            BackgroundTransparency = 1,
            Font = FONT.Bold,
            Text = "100",
            TextColor3 = THEME.Success,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 12,
        }, stage)

        storeOnRender("preview.health", function(value)
            healthTrack.Visible = value == true
        end)
    end

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = FONT.Medium,
        Text = "Drag & Drop Elements",
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 3,
        ZIndex = 12,
    }, host)

    local chipMirror = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 4,
        ZIndex = 11,
    }, host)
    local mirrorGrid = Instance.new("UIGridLayout")
    mirrorGrid.CellSize = UDim2.fromOffset(78, 20)
    mirrorGrid.CellPadding = UDim2.fromOffset(4, 4)
    mirrorGrid.SortOrder = Enum.SortOrder.LayoutOrder
    mirrorGrid.Parent = chipMirror

    local mirrorButtons = {}
    for index, name in ipairs(ALL_CHIPS) do
        local chip = new("TextButton", {
            BackgroundColor3 = THEME.Row,
            AutoButtonColor = false,
            Font = FONT.Medium,
            Text = name,
            TextColor3 = THEME.Muted,
            TextSize = 10,
            BorderSizePixel = 0,
            LayoutOrder = index,
            ZIndex = 12,
        }, chipMirror)
        corner(chip, 3)
        stroke(chip, THEME.StrokeSoft)
        mirrorButtons[name] = chip
        track(chip.MouseButton1Click:Connect(function()
            toggleChip(name)
        end))
    end

    storeOnRender("visuals.players.chipList", function()
        for name, chip in pairs(mirrorButtons) do
            chip.TextColor3 = chipActive(name) and THEME.Accent or THEME.Muted
        end
    end)

    Ui.preview = panel
    return panel
end

--================================================================================
-- DRAGGING
--================================================================================

local function makeDraggable(handle, target)
    if not handle then return end
    local dragging = false
    local dragStart
    local startPosition

    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragging = true
        dragStart = input.Position
        startPosition = target.Position
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - dragStart
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local nextX = clamp(startPosition.X.Offset + delta.X, -target.AbsoluteSize.X + 120, viewport.X - 120)
        local nextY = clamp(startPosition.Y.Offset + delta.Y, 0, viewport.Y - 48)
        target.Position = UDim2.new(startPosition.X.Scale, nextX, startPosition.Y.Scale, nextY)
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

--================================================================================
-- PAGE ROUTER
--================================================================================

function Ui.selectPage(pageId)
    local page = Ui.pages[pageId]
    if not page then return end
    Ui.currentPage = pageId

    for id, entry in pairs(Ui.pages) do
        entry.surface.Visible = (id == pageId)
    end

    for id, nav in pairs(Ui.navButtons) do
        local active = (id == pageId)
        nav.label.TextColor3 = active and THEME.Accent or THEME.Muted
        nav.glyph.TextColor3 = active and THEME.Accent or THEME.Muted
        nav.marker.BackgroundTransparency = active and 0 or 1
        nav.button.BackgroundTransparency = active and 0.6 or 1
    end

    if not page.built then
        page.built = true
        local builder = PageBuilders[pageId]
        if builder then
            local ok, err = pcall(builder, page)
            if not ok then
                warn("[NEVERLOSE] page builder failed (" .. pageId .. "): " .. tostring(err))
            end
        end
    end
end

--================================================================================
-- SEARCH + NOTIFICATION OVERLAYS
--================================================================================

local function buildSearchOverlay(parent)
    local overlay = new("Frame", {
        Name = "SearchOverlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.55,
        Visible = false,
        ZIndex = 70,
        Active = true,
    }, parent)

    local panel = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 90),
        Size = UDim2.fromOffset(420, 340),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 71,
    }, overlay)
    corner(panel, 8)
    stroke(panel, THEME.Stroke)
    padding(panel, 12)

    local box = new("TextBox", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = THEME.Row,
        Font = FONT.Medium,
        PlaceholderText = "Search settings…",
        PlaceholderColor3 = THEME.Dim,
        Text = "",
        TextColor3 = THEME.Text,
        TextSize = 12,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 72,
    }, panel)
    corner(box, 5)
    stroke(box, THEME.Stroke)
    box.Text = "  "

    local results = new("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 38),
        Size = UDim2.new(1, 0, 1, -38),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 72,
    }, panel)
    listLayout(results, 2)

    local function renderResults(query)
        for _, child in ipairs(results:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local lowered = string.lower(query)
        local shown = 0
        for _, entry in ipairs(Store.registry) do
            if shown >= 40 then break end
            if lowered == "" or string.find(string.lower(entry.label), lowered, 1, true) then
                shown = shown + 1
                local button = new("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundColor3 = THEME.Row,
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Font = FONT.Medium,
                    Text = "  " .. entry.label .. "   ·   " .. entry.page,
                    TextColor3 = THEME.Muted,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    ZIndex = 73,
                    LayoutOrder = shown,
                }, results)
                track(button.MouseEnter:Connect(function()
                    button.BackgroundTransparency = 0
                    button.TextColor3 = THEME.Text
                end))
                track(button.MouseLeave:Connect(function()
                    button.BackgroundTransparency = 1
                    button.TextColor3 = THEME.Muted
                end))
                track(button.MouseButton1Click:Connect(function()
                    Ui.selectPage(entry.page)
                    overlay.Visible = false
                end))
            end
        end
    end

    track(box:GetPropertyChangedSignal("Text"):Connect(function()
        renderResults(sanitizeText((box.Text:gsub("^%s+", "")), 40))
    end))

    track(overlay.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local px, py = panel.AbsolutePosition.X, panel.AbsolutePosition.Y
        local inside = input.Position.X >= px and input.Position.X <= px + panel.AbsoluteSize.X
            and input.Position.Y >= py and input.Position.Y <= py + panel.AbsoluteSize.Y
        if not inside then
            overlay.Visible = false
        end
    end))

    Ui.searchOverlay = overlay
    return overlay
end

local function buildBellOverlay(parent)
    local overlay = new("Frame", {
        Name = "BellOverlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.55,
        Visible = false,
        ZIndex = 70,
        Active = true,
    }, parent)

    local panel = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 90),
        Size = UDim2.fromOffset(380, 320),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ZIndex = 71,
    }, overlay)
    corner(panel, 8)
    stroke(panel, THEME.Stroke)
    padding(panel, 12)

    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Font = FONT.Bold,
        Text = "Notifications",
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 72,
    }, panel)

    local list = new("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 1, -28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 72,
    }, panel)
    listLayout(list, 3)

    local function refresh()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        local shown = 0
        for index = #notificationHistory, 1, -1 do
            shown = shown + 1
            if shown > 40 then break end
            local entry = notificationHistory[index]
            local label = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = THEME.Row,
                BackgroundTransparency = 1,
                Font = FONT.Regular,
                Text = "  " .. entry.message,
                TextColor3 = THEME.Muted,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                BorderSizePixel = 0,
                ZIndex = 73,
                LayoutOrder = shown,
            }, list)
        end
    end

    Ui.bellRefresh = refresh

    track(overlay.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local px, py = panel.AbsolutePosition.X, panel.AbsolutePosition.Y
        local inside = input.Position.X >= px and input.Position.X <= px + panel.AbsoluteSize.X
            and input.Position.Y >= py and input.Position.Y <= py + panel.AbsoluteSize.Y
        if not inside then
            overlay.Visible = false
        end
    end))

    Ui.bellOverlay = overlay
    return overlay
end

--================================================================================
-- INTEGRATION ADAPTER
-- The only surface the wrapped script touches. Either direction works:
-- script -> Adapter.get/bind, GUI -> store -> handler -> script.
--================================================================================

local Adapter = {
    running = false,
    handlers = {},
    toggles = {},
    held = {},
}

function Adapter.bind(featureKey, callback)
    if type(featureKey) ~= "string" or type(callback) ~= "function" then
        return false
    end
    if Store.schema[featureKey] == nil then
        storeRegister(featureKey, false, "boolean")
    end
    Adapter.handlers[featureKey] = Adapter.handlers[featureKey] or {}
    table.insert(Adapter.handlers[featureKey], callback)
    storeOnChange(featureKey, function(value)
        if Adapter.running then
            local ok, err = pcall(callback, value, featureKey)
            if not ok then
                warn("[NEVERLOSE] adapter callback failed (" .. featureKey .. "): " .. tostring(err))
            end
        end
    end)
    pcall(callback, storeGet(featureKey), featureKey)
    return true
end

function Adapter.get(featureKey)
    return storeGet(featureKey)
end

function Adapter.set(featureKey, value)
    storeSet(featureKey, value)
end

function Adapter.isActive(featureKey)
    local value = Store.values[featureKey]
    if type(value) == "table" then
        if value.mode == "Always" then return true end
        if value.mode == "Toggle" then return Adapter.toggles[featureKey] == true end
        if value.mode == "Hold" then return Adapter.held[featureKey] == true end
        return false
    end
    return storeGet(featureKey) == true
end

function Adapter.start()
    if Adapter.running then return false end
    Adapter.running = true
    for featureKey, callbacks in pairs(Adapter.handlers) do
        for _, callback in ipairs(callbacks) do
            pcall(callback, Adapter.isActive(featureKey), featureKey)
        end
    end
    return true
end

function Adapter.stop()
    if not Adapter.running then return false end
    Adapter.running = false
    return true
end

function Adapter.restart()
    if Adapter.running then Adapter.stop() end
    return Adapter.start()
end

function Adapter.getenv()
    return {
        get = Adapter.get,
        set = Adapter.set,
        bind = Adapter.bind,
        active = Adapter.isActive,
        notify = notify,
    }
end

--================================================================================
-- KEYBIND RUNTIME
--================================================================================

local function pointerInsidePopup(position)
    for _, popup in ipairs(Ui.popups) do
        if popup and popup.Parent then
            local px, py = popup.AbsolutePosition.X, popup.AbsolutePosition.Y
            if position.X >= px and position.X <= px + popup.AbsoluteSize.X
                and position.Y >= py and position.Y <= py + popup.AbsoluteSize.Y then
                return true
            end
        end
    end
    return false
end

local function keyRuntimeInit()
    track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if #Ui.popups > 0 and not pointerInsidePopup(input.Position) then
                closeAllPopups()
            end
        end

        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        local toggleKey = keyNameToEnum(storeGet("ui.toggleKey"))
        if toggleKey and input.KeyCode == toggleKey then
            Ui.visible = not Ui.visible
            if Ui.window then Ui.window.Visible = Ui.visible end
            if Ui.preview then Ui.preview.Visible = Ui.visible end
            if not Ui.visible then
                closeAllPopups()
                if Ui.searchOverlay then Ui.searchOverlay.Visible = false end
                if Ui.bellOverlay then Ui.bellOverlay.Visible = false end
            end
            return
        end

        if input.KeyCode == Enum.KeyCode.Escape then
            closeAllPopups()
            if Ui.searchOverlay then Ui.searchOverlay.Visible = false end
            if Ui.bellOverlay then Ui.bellOverlay.Visible = false end
            return
        end

        for featureKey, callbacks in pairs(Adapter.handlers) do
            local bind = Store.values[featureKey]
            if type(bind) == "table" and bind.key ~= "None" then
                local key = keyNameToEnum(bind.key)
                if key and key == input.KeyCode then
                    if bind.mode == "Toggle" then
                        Adapter.toggles[featureKey] = not Adapter.toggles[featureKey]
                    elseif bind.mode == "Hold" then
                        Adapter.held[featureKey] = true
                    end
                    local active = Adapter.isActive(featureKey)
                    for _, callback in ipairs(callbacks) do
                        pcall(callback, active, featureKey)
                    end
                end
            end
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        for featureKey, bind in pairs(Store.values) do
            if type(bind) == "table" and bind.key ~= "None" and bind.mode == "Hold" then
                local key = keyNameToEnum(bind.key)
                if key and key == input.KeyCode then
                    Adapter.held[featureKey] = false
                    local callbacks = Adapter.handlers[featureKey]
                    if callbacks then
                        for _, callback in ipairs(callbacks) do
                            pcall(callback, false, featureKey)
                        end
                    end
                end
            end
        end
    end))
end

--================================================================================
-- ORIGINAL SCRIPT
-- The supplied body file was empty (0 bytes). Drop the finished body between the
-- two markers verbatim; nothing else in this file needs to change.
--================================================================================

-- [INTEGRATION] original script begins (unmodified)

local function originalScript()
    -- Body slot. Runs exactly once per Adapter.start(), in original order.
end

-- [INTEGRATION] original script ends

-- [INTEGRATION] adapter — the only code that calls into the original
local function runOriginalOnce()
    local ok, err = pcall(originalScript)
    if not ok then
        warn("[NEVERLOSE] original script error: " .. tostring(err))
    end
end

--================================================================================
-- TEARDOWN
--================================================================================

local function teardown()
    pcall(saveNow)

    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    Connections = {}

    for _, thread in ipairs(Threads) do
        pcall(function() task.cancel(thread) end)
    end
    Threads = {}

    closeAllPopups()

    if Ui.root then
        pcall(function() Ui.root:Destroy() end)
        Ui.root = nil
    end

    for _, instance in ipairs(Instances) do
        if instance and instance.Parent then
            pcall(function() instance:Destroy() end)
        end
    end
    Instances = {}
end

--================================================================================
-- WINDOW ASSEMBLY
--================================================================================

local function chromeButton(parent, glyph, offsetX, handler, hoverColor)
    local button = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, offsetX, 0, 12),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = THEME.Row,
        AutoButtonColor = false,
        Font = FONT.Bold,
        Text = glyph,
        TextColor3 = THEME.Muted,
        TextSize = 12,
        BorderSizePixel = 0,
        ZIndex = 20,
    }, parent)
    corner(button, 5)
    stroke(button, THEME.Stroke)
    track(button.MouseEnter:Connect(function()
        tween(button, { TextColor3 = hoverColor or THEME.Text, BackgroundColor3 = THEME.RowHover }, 0.12)
    end))
    track(button.MouseLeave:Connect(function()
        tween(button, { TextColor3 = THEME.Muted, BackgroundColor3 = THEME.Row }, 0.12)
    end))
    track(button.MouseButton1Click:Connect(handler))
    return button
end

local function buildWindow()
    local window = new("Frame", {
        Name = "Window",
        Position = UDim2.fromOffset(80, 60),
        Size = UDim2.fromOffset(CONFIG.Window.Size.X, CONFIG.Window.Size.Y),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ZIndex = 9,
    }, Ui.root)
    corner(window, 8)
    stroke(window, THEME.Stroke)

    local overlay = new("Frame", {
        Name = "Overlay",
        Size = UDim2.fromOffset(CONFIG.Window.Size.X, CONFIG.Window.Size.Y),
        BackgroundTransparency = 1,
        ZIndex = 30,
        -- Active stays false: an Active frame would swallow every click meant
        -- for the controls beneath it. Popup children still receive input.
        Active = false,
    }, window)
    Ui.overlay = overlay

    local topbar = buildTopbar(window)
    buildSidebar(window)
    buildContent(window)
    buildNav()
    buildSearchOverlay(Ui.root)
    buildBellOverlay(Ui.root)

    local previewHost = new("Frame", {
        Name = "PreviewHost",
        Position = UDim2.fromOffset(CONFIG.Window.Size.X + CONFIG.Window.Padding, 0),
        Size = UDim2.fromOffset(CONFIG.Preview.Size.X, CONFIG.Preview.Size.Y),
        BackgroundTransparency = 1,
        ZIndex = 9,
    }, Ui.root)
    buildPreview(previewHost)

    makeDraggable(topbar, window)
    makeDraggable(Ui.preview, previewHost)

    chromeButton(topbar, "✕", -12, function()
        notify("Menu closed", "warning")
        teardown()
    end, THEME.Danger)

    chromeButton(topbar, "–", -48, function()
        Ui.visible = not Ui.visible
        window.Visible = Ui.visible
        Ui.preview.Visible = Ui.visible
    end)

    track(Ui.searchButton.MouseButton1Click:Connect(function()
        if Ui.searchOverlay then
            Ui.searchOverlay.Visible = not Ui.searchOverlay.Visible
            if Ui.bellOverlay then Ui.bellOverlay.Visible = false end
        end
    end))
    track(Ui.bellButton.MouseButton1Click:Connect(function()
        if Ui.bellOverlay then
            Ui.bellOverlay.Visible = not Ui.bellOverlay.Visible
            if Ui.searchOverlay then Ui.searchOverlay.Visible = false end
            if Ui.bellRefresh then Ui.bellRefresh() end
        end
    end))
    track(Ui.settingsButton.MouseButton1Click:Connect(function()
        Ui.selectPage("configs")
    end))

    Ui.window = window
    return window
end

--================================================================================
-- BOOTSTRAP
--================================================================================

local function boot()
    registerDefaults()
    persistenceInit()

    local decoded = readConfigFrom(CONFIG.File)
    if decoded then
        applyConfig(decoded)
    end

    if not buildRoot() then
        warn("[NEVERLOSE] no GUI parent available (gethui/CoreGui/PlayerGui)")
        return
    end

    buildWindow()
    for _, entry in ipairs(NAV_DEFINITION) do
        if entry.id then
            buildPageSurface(entry.id)
        end
    end
    renderAll()
    Ui.selectPage("players")

    keyRuntimeInit()

    if getgenv then
        local ok = pcall(function()
            getgenv().NEVERLOSE = Adapter.getenv()
            return true
        end)
        if not ok then
            -- Some executors expose getgenv read-only; the adapter still works locally.
        end
    end

    local started = Adapter.start()
    if started then
        runOriginalOnce()
    end

    notify("Menu loaded · " .. (Persistence.available and "config bound" or "in-memory"), "success")
end

boot()






