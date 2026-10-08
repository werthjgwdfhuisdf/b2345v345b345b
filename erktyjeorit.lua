Toggles = Toggles or {}
Options = Options or {}
BacktrackApi = BacktrackApi or {}
PSilentApi = PSilentApi or {}

local function installSafeDrawingWrapper()
    if type(Drawing) ~= 'table' or type(Drawing.new) ~= 'function' then
        return
    end

    local wrappedFlag = '__xeno_safe_drawing_new_wrapped'
    local alreadyWrapped = false
    pcall(function()
        if type(getgenv) == 'function' then
            local env = getgenv()
            if type(env) == 'table' and env[wrappedFlag] == true then
                alreadyWrapped = true
            end
        end
    end)
    if alreadyWrapped then
        return
    end

    local originalNew = Drawing.new
    local noop = function() end
    local function makeDummyDrawing()
        return setmetatable({}, {
            __index = function(_, key)
                if key == 'Remove' or key == 'Destroy' then
                    return noop
                end
                return nil
            end,
            __newindex = function()
            end
        })
    end

    Drawing.new = function(...)
        local ok, obj = pcall(originalNew, ...)
        if not ok then
            return makeDummyDrawing()
        end
        if obj == nil or type(obj) == 'number' then
            return makeDummyDrawing()
        end
        return obj
    end

    pcall(function()
        if type(getgenv) == 'function' then
            local env = getgenv()
            if type(env) == 'table' then
                env[wrappedFlag] = true
            end
        end
    end)
end

installSafeDrawingWrapper()

-- Mute ExamsAC client reporter (ExamsReport + AnimationBlendController*)
do
    local Players = game:GetService('Players')
    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local StarterPlayer = game:GetService('StarterPlayer')
    local SCANNER_NAME = 'AnimationBlendController*'
    local REMOTE_NAME = 'ExamsReport'

    local genv = _G
    pcall(function()
        if type(getgenv) == 'function' then
            local g = getgenv()
            if type(g) == 'table' then
                genv = g
            end
        end
    end)
    genv.__MuteExamsReport = genv.__MuteExamsReport or {
        blocked = 0,
        scannersKilled = 0,
        hooked = false,
    }
    local muteState = genv.__MuteExamsReport

    local function isExamsReport(inst)
        return typeof(inst) == 'Instance'
            and inst.ClassName == 'RemoteEvent'
            and inst.Name == REMOTE_NAME
    end

    local function neutralizeScript(s)
        if not s or not s:IsA('LocalScript') then return end
        pcall(function() s.Disabled = true end)
        pcall(function()
            if type(getscriptthread) == 'function' then
                local th = getscriptthread(s)
                if th then task.cancel(th) end
            end
        end)
        pcall(function()
            if type(getconnections) == 'function' then
                for _, sig in ipairs({ s.AncestryChanged, s.Changed }) do
                    pcall(function()
                        for _, conn in ipairs(getconnections(sig)) do
                            pcall(function() conn:Disable() end)
                            pcall(function() conn:Disconnect() end)
                        end
                    end)
                end
            end
        end)
        pcall(function()
            if type(getsenv) == 'function' then
                local env = getsenv(s)
                if type(env) == 'table' then
                    env.u67 = true
                    env.aimStrikes = 0
                    for k in pairs(env) do
                        if type(env[k]) == 'function' then
                            env[k] = function() end
                        end
                    end
                end
            end
        end)
        pcall(function() s:Destroy() end)
    end

    local function killScanner(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if child.Name == SCANNER_NAME and child:IsA('LocalScript') then
                neutralizeScript(child)
                muteState.scannersKilled = muteState.scannersKilled + 1
            end
        end
    end

    local function watchContainer(container)
        if not container then
            return
        end
        killScanner(container)
        pcall(function()
            container.ChildAdded:Connect(function(child)
                if child.Name == SCANNER_NAME and child:IsA('LocalScript') then
                    task.defer(function()
                        killScanner(container)
                    end)
                end
            end)
        end)
    end

    local function startMuteExams()
        local localPlayer = Players.LocalPlayer or Players:WaitForChild('LocalPlayer', 30)
        if not localPlayer then
            return
        end
        local playerScripts = localPlayer:FindFirstChild('PlayerScripts')
            or localPlayer:WaitForChild('PlayerScripts', 10)
        watchContainer(playerScripts)
        watchContainer(StarterPlayer:FindFirstChild('StarterPlayerScripts'))

        if not muteState.hooked then
            -- 1. Hard __namecall interception
            if type(hookmetamethod) == 'function' and type(getnamecallmethod) == 'function' then
                pcall(function()
                    local oldNamecall
                    oldNamecall = hookmetamethod(game, '__namecall', function(self, ...)
                        local method = getnamecallmethod()
                        if method == 'FireServer' and isExamsReport(self) then
                            muteState.blocked = muteState.blocked + 1
                            return nil
                        end
                        return oldNamecall(self, ...)
                    end)
                end)
            end

            -- 2. Direct probe.FireServer hookfunction fallback
            if type(hookfunction) == 'function' then
                pcall(function()
                    local probe = Instance.new('RemoteEvent')
                    local oldFire
                    oldFire = hookfunction(probe.FireServer, function(self, ...)
                        if isExamsReport(self) then
                            muteState.blocked = muteState.blocked + 1
                            return nil
                        end
                        return oldFire(self, ...)
                    end)
                    muteState.probe = probe
                end)
            end

            muteState.hooked = true
        end
    end

    if type(task) == 'table' and type(task.spawn) == 'function' then
        task.spawn(function()
            pcall(startMuteExams)
        end)
    else
        pcall(startMuteExams)
    end
end

-- Wrap callbacks so runtime errors never surface
local function safeCallback(fn)
    return function(...)
        local args = { ... }
        local function runner()
            return fn(table.unpack(args))
        end
        -- swallow any error to keep the script silent
        xpcall(runner, function() end)
    end
end

local function safeConnect(signal, fn)
    if signal == nil or type(signal.Connect) ~= 'function' or type(fn) ~= 'function' then
        return nil
    end
    return signal:Connect(safeCallback(fn))
end

local function safeSpawn(fn, ...)
    if type(fn) ~= 'function' then
        return nil
    end
    local args = { ... }
    local function runner()
        return fn(table.unpack(args))
    end
    if type(task) == 'table' and type(task.spawn) == 'function' then
        return task.spawn(safeCallback(runner))
    end
    local co = coroutine.create(safeCallback(runner))
    return coroutine.resume(co)
end

-- Shared role manager state used by ESP/Trigger logic.
local function normalizePlayerNameText(value)
    if type(value) ~= 'string' then
        return ''
    end
    return string.lower((value:gsub('^%s+', ''):gsub('%s+$', '')))
end

local function normalizeRoleText(role)
    role = tostring(role or 'Neutral')
    if role == 'Target' or role == 'Friend' or role == 'Neutral' then
        return role
    end
    return 'Neutral'
end

local requestSaveRoles

local function getSharedRoleStore()
    local env = _G
    pcall(function()
        if type(getgenv) == 'function' then
            local g = getgenv()
            if type(g) == 'table' then
                env = g
            end
        end
    end)
    if type(env.__bomzRoleAssignments) ~= 'table' then
        env.__bomzRoleAssignments = {
            byUserId = {},
            byName = {},
        }
    end
    return env.__bomzRoleAssignments
end

local function readPlayerIdentity(playerOrName)
    local userId = nil
    local name = nil
    local displayName = nil

    if type(playerOrName) == 'string' then
        name = playerOrName
        return userId, name, displayName
    end

    pcall(function()
        if playerOrName and playerOrName.UserId ~= nil then
            userId = playerOrName.UserId
        end
    end)
    pcall(function()
        if playerOrName and type(playerOrName.Name) == 'string' then
            name = playerOrName.Name
        end
    end)
    pcall(function()
        if playerOrName and type(playerOrName.DisplayName) == 'string' then
            displayName = playerOrName.DisplayName
        end
    end)

    return userId, name, displayName
end

local function setSharedPlayerRole(playerOrName, role, skipSave)
    local store = getSharedRoleStore()
    local normalizedRole = normalizeRoleText(role)
    local userId, name, displayName = readPlayerIdentity(playerOrName)

    if userId ~= nil then
        store.byUserId[userId] = normalizedRole
        if type(name) == 'string' then
            store.byName[normalizePlayerNameText(name)] = normalizedRole
            store.byUserIdToName = store.byUserIdToName or {}
            store.byUserIdToName[userId] = name
        end
        if not skipSave and type(requestSaveRoles) == 'function' then
            requestSaveRoles()
        end
        return
    end
    local key = normalizePlayerNameText(name)
    if key ~= '' then
        store.byName[key] = normalizedRole
    end
    if not skipSave and type(requestSaveRoles) == 'function' then
        requestSaveRoles()
    end
end

local function getSharedPlayerRole(player)
    if not player then
        return nil
    end
    local store = getSharedRoleStore()
    local userId, name, displayName = readPlayerIdentity(player)
    local role = userId ~= nil and store.byUserId[userId] or nil
    if role then
        return normalizeRoleText(role)
    end
    local n1 = normalizePlayerNameText(name)
    local n2 = normalizePlayerNameText(displayName or '')
    if n1 ~= '' and store.byName[n1] then
        return normalizeRoleText(store.byName[n1])
    end
    if n2 ~= '' and store.byName[n2] then
        return normalizeRoleText(store.byName[n2])
    end

    -- Fallback: check if player is whitelisted in Trigger bot UI options
    local isWhitelisted = false
    pcall(function()
        if Options then
            local tw = Options.TriggerWhitelist
            if tw and type(tw.Value) == 'table' then
                if tw.Value[name] or (displayName and tw.Value[displayName]) then
                    isWhitelisted = true
                end
            end
        end
    end)
    if isWhitelisted then
        return 'Friend'
    end

    return nil
end

local function isSharedFriendRole(player)
    return getSharedPlayerRole(player) == 'Friend'
end

local function isSharedTargetRole(player)
    return getSharedPlayerRole(player) == 'Target'
end

pcall(function()
    local function mute() end
    print = mute
    warn = mute
end)

-- ?????????????????????????????????????????????
--  Whitelist (pastebin)
-- ?????????????????????????????????????????????
do
    local PASTE_RAW_URL = 'https://pastebin.com/raw/iGFPydSc'

    local function detect_http_getter()
        if type(syn) == 'table' and type(syn.request) == 'function' then
            return function(url)
                local r = syn.request({ Url = url, Method = 'GET' })
                return (r and (r.Body or r.body)) or r
            end
        end
        if type(http) == 'table' and type(http.request) == 'function' then
            return function(url)
                local r = http.request({ Url = url, Method = 'GET' })
                return (r and (r.Body or r.body)) or r
            end
        end
        if type(request) == 'function' then
            return function(url)
                local r = request(url)
                if type(r) == 'table' then return (r.Body or r.body) end
                return r
            end
        end
        if type(xeno) == 'table' and type(xeno.request) == 'function' then
            return function(url)
                local r = xeno.request({ Url = url, Method = 'GET' })
                return (r and (r.Body or r.body)) or r
            end
        end
        if type(game) == 'table' and type(game.HttpGet) == 'function' then
            return function(url) return game:HttpGet(url) end
        end
        return nil
    end

    local http_getter = detect_http_getter()

    local function fetch_raw(url)
        if http_getter then
            local ok, res = pcall(http_getter, url)
            if ok and res then return res end
        end
        return nil
    end

    local allowedUsers = {}
    local raw = fetch_raw(PASTE_RAW_URL)
    if raw then
        local loader = loadstring or load
        local ok, chunk = pcall(loader, raw)
        if ok and type(chunk) == 'function' then
            local ok2, result = pcall(chunk)
            if ok2 and type(result) == 'table' then
                allowedUsers = result
            end
        end
        if type(allowedUsers) ~= 'table' or #allowedUsers == 0 then
            allowedUsers = {}
            for line in raw:gmatch('[^\r\n]+') do
                line = line:gsub('^%s+', ''):gsub('%s+$', '')
                if line ~= '' then table.insert(allowedUsers, line) end
            end
        end
    end

    local Players = game:GetService('Players')
    local playerName = Players.LocalPlayer and Players.LocalPlayer.Name or ''
    local allowed = false
    for _, name in ipairs(allowedUsers) do
        if type(name) == 'string' and playerName:lower() == name:lower() then
            allowed = true
            break
        end
    end
    if not allowed then
        Players.LocalPlayer:Kick('???')
        return
    end
end

-- Minimal helper to create option objects
local function makeOption(id, default)
    local obj = { Value = default }
    function obj:OnChanged(fn)
        self.__onchange = fn
    end
    function obj:SetValue(v)
        self.Value = v
        if self.__onchange then
            pcall(self.__onchange, v)
        end
    end
    function obj:GetState()
        -- For keypickers that expose a GetState method; default to false
        return false
    end
    return obj
end

local function makeToggle(id, default)
    local obj = { Value = default }
    function obj:OnChanged(fn)
        self.__onchange = fn
    end
    function obj:SetValue(v)
        self.Value = v
        if self.__onchange then
            pcall(self.__onchange, v)
        end
    end
    return obj
end

-- Minimal UI stub that exposes the small API used in this script
local Library = {}
Library.Unloaded = false
Library.KeybindFrame = { Visible = true }

-- store unload callbacks
local unloadCallbacks = {}
function Library:OnUnload(fn)
    if type(fn) == 'function' then
        table.insert(unloadCallbacks, fn)
    end
end
function Library:Unload()
    Library.Unloaded = true
    for _, cb in ipairs(unloadCallbacks) do
        pcall(cb)
    end
end

-- Create a very small window/tab/groupbox/tabbox system that only records
-- Toggles and Options and returns objects with the methods the script calls.
function Library:CreateWindow(opts)
    local Window = {}
    function Window:AddTab(name)
        local Tab = { name = name }
        function Tab:AddLeftGroupbox(title)
            local gb = {}
            function gb:AddToggle(id, cfg)
                Toggles[id] = makeToggle(id, cfg and cfg.Default)
                return Toggles[id]
            end
            function gb:AddLabel(_) -- returns a small helper for colorpicker/keypicker chaining
                local cap = {}
                function cap:AddColorPicker(id, cfg)
                    Options[id] = makeOption(id, cfg and cfg.Default)
                    return Options[id]
                end
                function cap:AddKeyPicker(id, cfg)
                    Options[id] = makeOption(id, cfg and cfg.Default)
                    return Options[id]
                end
                return cap
            end
            function gb:AddSlider(id, cfg)
                Options[id] = makeOption(id, cfg and cfg.Default)
                return Options[id]
            end
            function gb:AddDropdown(id, cfg)
                Options[id] = makeOption(id, cfg and cfg.Default)
                return Options[id]
            end
            function gb:AddInput(id, cfg)
                cfg = cfg or {}
                local defaultValue = cfg.Default
                if defaultValue == nil then
                    defaultValue = ''
                end
                if type(defaultValue) ~= 'string' then
                    defaultValue = tostring(defaultValue)
                end
                Options[id] = makeOption(id, defaultValue)
                return Options[id]
            end
            function gb:AddButton(name, fn)
                -- call once to keep semantics similar to original (no-op until pressed)
                gb[name] = fn
                return gb
            end
            return gb
        end
        function Tab:AddRightGroupbox(title)
            return Tab:AddLeftGroupbox(title)
        end
        function Tab:AddRightTabbox()
            local tabbox = {}
            function tabbox:AddTab(n)
                -- Tabbox pages should expose control methods directly (AddToggle/AddSlider/etc).
                return Tab:AddLeftGroupbox(n)
            end
            return tabbox
        end
        return Tab
    end
    return Window
end

-- Try to use the real GUI API from gui.lua while keeping the old Add* interface.
local function isGuiLibrary(lib)
    return type(lib) == 'table'
        and type(lib.Window) == 'function'
        and type(lib.Page) == 'function'
end

local function enumFromString(raw)
    if type(raw) ~= 'string' then
        return nil
    end

    local keyCodeName = raw:match('^Enum%.KeyCode%.(.+)$')
    if keyCodeName and Enum.KeyCode[keyCodeName] then
        return Enum.KeyCode[keyCodeName]
    end

    local inputTypeName = raw:match('^Enum%.UserInputType%.(.+)$')
    if inputTypeName and Enum.UserInputType[inputTypeName] then
        return Enum.UserInputType[inputTypeName]
    end

    return nil
end

local function normalizeKeyValue(raw)
    if typeof and typeof(raw) == 'EnumItem' then
        return raw
    end

    local parsed = enumFromString(raw)
    if parsed then
        return parsed
    end

    if type(raw) == 'string' then
        local candidate = raw
        if #candidate == 1 then
            candidate = string.upper(candidate)
        end

        if Enum.KeyCode[candidate] then
            return Enum.KeyCode[candidate]
        end
        if Enum.UserInputType[candidate] then
            return Enum.UserInputType[candidate]
        end
    end

    return raw
end

local function multiValueToList(value)
    local out = {}
    if type(value) ~= 'table' then
        return out
    end

    local hasNumericKey = false
    for k, _ in pairs(value) do
        if type(k) == 'number' then
            hasNumericKey = true
            break
        end
    end

    if hasNumericKey then
        for _, v in pairs(value) do
            if type(v) == 'string' then
                table.insert(out, v)
            end
        end
        return out
    end

    for k, v in pairs(value) do
        if v and type(k) == 'string' then
            table.insert(out, k)
        end
    end

    return out
end

local function multiValueToMap(value)
    local out = {}
    if type(value) ~= 'table' then
        return out
    end

    for k, v in pairs(value) do
        if type(v) == 'string' then
            out[v] = true
        elseif type(k) == 'string' and v == true then
            out[k] = true
        end
    end

    return out
end

local function getPlayerNames()
    local players = game:GetService('Players')
    local out = {}
    for _, pl in ipairs(players:GetPlayers()) do
        if pl ~= players.LocalPlayer then
            table.insert(out, pl.Name)
        end
    end
    table.sort(out)
    return out
end

local function getInventoryToolNames()
    local players = game:GetService('Players')
    local localPlayer = players.LocalPlayer
    local out = {}
    local seen = {}

    local function collect(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if child and child:IsA('Tool') then
                local name = tostring(child.Name or '')
                if name ~= '' and not seen[name] then
                    seen[name] = true
                    table.insert(out, name)
                end
            end
        end
    end

    if localPlayer then
        collect(localPlayer:FindFirstChild('Backpack'))
        collect(localPlayer.Character)
    end

    table.sort(out, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return out
end

local function resolveGuiLibrary()
    local existing = nil

    pcall(function()
        if type(getgenv) == 'function' then
            local env = getgenv()
            if env and isGuiLibrary(env.Library) then
                existing = env.Library
            end
        end
    end)

    if not existing and isGuiLibrary(_G.Library) then
        existing = _G.Library
    end

    if existing then
        return existing
    end

    if type(isfile) ~= 'function' or type(readfile) ~= 'function' or type(loadstring) ~= 'function' then
        return nil
    end

    local candidates = {
        'coincide_lib.luau',
        '.\\coincide_lib.luau',
        'C:\\Users\\antihype\\Downloads\\coincide_lib.luau',
        'C:/Users/antihype/Downloads/coincide_lib.luau',
        'gui.lua',
        '.\\gui.lua',
        'C:\\Users\\antihype\\Downloads\\gui.lua',
        'C:/Users/antihype/Downloads/gui.lua',
    }

    for _, path in ipairs(candidates) do
        local ok, result = pcall(function()
            if not isfile(path) then
                return nil
            end

            local source = readfile(path)
            local marker = source:find('%-%-example here')
            if marker then
                source = source:sub(1, marker - 1) .. '\ngetgenv().Library = Library\nreturn Library\n'
            end

            local chunk = loadstring(source)
            if not chunk then
                return nil
            end

            local loaded = chunk()
            if isGuiLibrary(loaded) then
                return loaded
            end

            if type(getgenv) == 'function' then
                local env = getgenv()
                if env and isGuiLibrary(env.Library) then
                    return env.Library
                end
            end

            return nil
        end)

        if ok and isGuiLibrary(result) then
            return result
        end
    end

    local okRemote, remoteSource = pcall(function()
        if type(game) == 'table' and type(game.HttpGet) == 'function' then
            return game:HttpGet('https://raw.githubusercontent.com/ExtroDevGit/Coincide-UI/refs/heads/main/lib.luau')
        end
        return nil
    end)
    if okRemote and type(remoteSource) == 'string' and #remoteSource > 0 then
        local chunk = loadstring(remoteSource)
        if chunk then
            local loaded = chunk()
            if isGuiLibrary(loaded) then
                return loaded
            end
            if type(getgenv) == 'function' and isGuiLibrary(getgenv().Library) then
                return getgenv().Library
            end
        end
    end

    return nil
end

local GuiLibrary = nil
if GuiLibrary then
    local function makeGroupbox(section)
        local gb = {}

        function gb:AddToggle(id, cfg)
            cfg = cfg or {}
            local wrapped = makeToggle(id, cfg.Default == true)

            local native = section:Toggle({
                Name = cfg.Text or cfg.Name or id,
                Flag = id,
                Default = cfg.Default == true,
                Callback = function(value)
                    wrapped.Value = value
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, value)
                    end
                end
            })

            function wrapped:AddColorPicker(cpId, cpCfg)
                cpCfg = cpCfg or {}
                local defaultColor = cpCfg.Default or Color3.fromRGB(255, 255, 255)
                local defaultAlpha = cpCfg.Alpha or cpCfg.Transparency or 1
                local cpWrapped = makeOption(cpId, defaultColor)
                cpWrapped.Alpha = defaultAlpha

                if native and type(native.AddColorpicker) == 'function' then
                    pcall(function()
                        native:AddColorpicker({
                            Flag = cpId,
                            Default = defaultColor,
                            Alpha = defaultAlpha,
                            Callback = function(color, alpha)
                                cpWrapped.Value = color
                                cpWrapped.Alpha = alpha
                                if cpWrapped.__onchange then
                                    pcall(cpWrapped.__onchange, color)
                                end
                            end
                        })
                    end)
                end

                Options[cpId] = cpWrapped
                return cpWrapped
            end

            function wrapped:AddKeyPicker(kpId, kpCfg)
                kpCfg = kpCfg or {}
                local kpWrapped = makeOption(kpId, normalizeKeyValue(kpCfg.Default or Enum.KeyCode.C))
                kpWrapped.__state = false

                if native and type(native.AddKeybind) == 'function' then
                    pcall(function()
                        native:AddKeybind({
                            Default = normalizeKeyValue(kpCfg.Default or Enum.KeyCode.C),
                            Mode = kpCfg.Mode or 'Toggle',
                            Callback = function(state)
                                kpWrapped.__state = state
                                if kpWrapped.__onchange then
                                    pcall(kpWrapped.__onchange, kpWrapped.Value)
                                end
                            end
                        })
                    end)
                end

                Options[kpId] = kpWrapped
                return kpWrapped
            end

            Toggles[id] = wrapped
            return wrapped
        end

        function gb:AddLabel(labelText)
            local nativeLabel = section:Label(labelText or '')
            local cap = {}

            function cap:AddColorPicker(id, cfg)
                cfg = cfg or {}
                local defaultColor = cfg.Default or Color3.fromRGB(255, 255, 255)
                local defaultAlpha = cfg.Alpha or cfg.Transparency or 0
                local wrapped = makeOption(id, defaultColor)
                wrapped.Alpha = defaultAlpha

                local native = nativeLabel:Colorpicker({
                    Name = cfg.Title or cfg.Text or id,
                    Flag = id,
                    Default = defaultColor,
                    Alpha = defaultAlpha,
                    Callback = function(color, alpha)
                        wrapped.Value = color
                        wrapped.Alpha = alpha
                        if wrapped.__onchange then
                            pcall(wrapped.__onchange, color)
                        end
                    end
                })

                function wrapped:SetValue(v)
                    if native and type(native.Set) == 'function' then
                        pcall(function() native:Set(v, wrapped.Alpha or 0) end)
                    else
                        wrapped.Value = v
                        if wrapped.__onchange then
                            pcall(wrapped.__onchange, v)
                        end
                    end
                end

                Options[id] = wrapped
                return wrapped
            end

            function cap:AddKeyPicker(id, cfg)
                cfg = cfg or {}
                local wrapped = makeOption(id, normalizeKeyValue(cfg.Default or Enum.KeyCode.C))
                wrapped.__state = false

                local function syncFromFlags()
                    local keyData = GuiLibrary.Flags and GuiLibrary.Flags[id]
                    if type(keyData) == 'table' then
                        wrapped.__state = keyData.Toggled and true or false
                        wrapped.Value = enumFromString(keyData.Key) or keyData.Key or wrapped.Value
                    end
                end

                local native = nativeLabel:Keybind({
                    Name = cfg.Text or labelText or id,
                    Flag = id,
                    Default = normalizeKeyValue(cfg.Default or Enum.KeyCode.C),
                    Mode = cfg.Mode or 'Toggle',
                    Callback = function()
                        syncFromFlags()
                        if wrapped.__onchange then
                            pcall(wrapped.__onchange, wrapped.Value)
                        end
                    end
                })

                syncFromFlags()

                function wrapped:GetState()
                    return wrapped.__state == true
                end

                function wrapped:SetValue(v)
                    local normalized = normalizeKeyValue(v)
                    if native and type(native.Set) == 'function' then
                        pcall(function()
                            if cfg.Mode then
                                native:Set({ Key = normalized, Mode = cfg.Mode })
                            else
                                native:Set(normalized)
                            end
                        end)
                        syncFromFlags()
                        if wrapped.__onchange then
                            pcall(wrapped.__onchange, wrapped.Value)
                        end
                    else
                        wrapped.Value = normalized
                        wrapped.__state = false
                        if wrapped.__onchange then
                            pcall(wrapped.__onchange, wrapped.Value)
                        end
                    end
                end

                Options[id] = wrapped
                return wrapped
            end

            return cap
        end

        function gb:AddSlider(id, cfg)
            cfg = cfg or {}

            local decimals = cfg.Decimals
            if type(decimals) ~= 'number' then
                if type(cfg.Rounding) == 'number' then
                    if cfg.Rounding <= 0 then
                        decimals = 1
                    else
                        decimals = 1 / (10 ^ cfg.Rounding)
                    end
                else
                    decimals = 1
                end
            end

            local wrapped = makeOption(id, cfg.Default or 0)
            local native = section:Slider({
                Name = cfg.Text or cfg.Name or id,
                Flag = id,
                Default = cfg.Default or 0,
                Min = cfg.Min or 0,
                Max = cfg.Max or 100,
                Decimals = decimals,
                Suffix = cfg.Suffix or '',
                Callback = function(value)
                    wrapped.Value = value
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, value)
                    end
                end
            })

            function wrapped:SetValue(v)
                if native and type(native.Set) == 'function' then
                    pcall(function() native:Set(v) end)
                else
                    wrapped.Value = v
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, v)
                    end
                end
            end

            Options[id] = wrapped
            return wrapped
        end

        function gb:AddDropdown(id, cfg)
            cfg = cfg or {}
            local isMulti = cfg.Multi == true
            local isPlayerList = cfg.SpecialType == 'Player'
            local items = cfg.Items or cfg.Values or {}
            if isPlayerList then
                items = getPlayerNames()
            end

            local defaultValue = cfg.Default
            if isMulti then
                defaultValue = multiValueToList(defaultValue)
            end

            local wrapped = makeOption(id, isMulti and multiValueToMap(defaultValue) or defaultValue)

            local native = section:Dropdown({
                Name = cfg.Text or cfg.Name or id,
                Flag = id,
                Items = items,
                Default = defaultValue,
                Multi = isMulti,
                Callback = function(value)
                    local normalized = value
                    if isMulti then
                        normalized = multiValueToMap(value)
                    end
                    wrapped.Value = normalized
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, normalized)
                    end
                end
            })

            if isPlayerList and native and type(native.Refresh) == 'function' then
                local players = game:GetService('Players')
                local function refreshPlayers()
                    pcall(function()
                        native:Refresh(getPlayerNames())
                    end)
                end
                pcall(function() safeConnect(players.PlayerAdded, refreshPlayers) end)
                pcall(function() safeConnect(players.PlayerRemoving, refreshPlayers) end)
            end

            function wrapped:SetValue(v)
                local toSet = v
                if isMulti then
                    toSet = multiValueToList(v)
                end

                if native and type(native.Set) == 'function' then
                    pcall(function() native:Set(toSet) end)
                else
                    local normalized = isMulti and multiValueToMap(toSet) or toSet
                    wrapped.Value = normalized
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, normalized)
                    end
                end
            end

            Options[id] = wrapped
            return wrapped
        end

        function gb:AddInput(id, cfg)
            cfg = cfg or {}
            local defaultValue = cfg.Default
            if defaultValue == nil then
                defaultValue = ''
            end
            if type(defaultValue) ~= 'string' then
                defaultValue = tostring(defaultValue)
            end

            local wrapped = makeOption(id, defaultValue)
            local native = nil

            if type(section.Textbox) == 'function' then
                pcall(function()
                    native = section:Textbox({
                        Name = cfg.Text or cfg.Name or id,
                        Flag = id,
                        Default = defaultValue,
                        Placeholder = cfg.Placeholder or '',
                        Numeric = cfg.Numeric == true,
                        Finished = cfg.Finished == true,
                        Callback = function(value)
                            local text = value
                            if text == nil then
                                text = ''
                            end
                            if type(text) ~= 'string' then
                                text = tostring(text)
                            end
                            wrapped.Value = text
                            if wrapped.__onchange then
                                pcall(wrapped.__onchange, text)
                            end
                        end
                    })
                end)
            elseif type(section.Input) == 'function' then
                pcall(function()
                    native = section:Input({
                        Name = cfg.Text or cfg.Name or id,
                        Flag = id,
                        Default = defaultValue,
                        Placeholder = cfg.Placeholder or '',
                        Numeric = cfg.Numeric == true,
                        Finished = cfg.Finished == true,
                        Callback = function(value)
                            local text = value
                            if text == nil then
                                text = ''
                            end
                            if type(text) ~= 'string' then
                                text = tostring(text)
                            end
                            wrapped.Value = text
                            if wrapped.__onchange then
                                pcall(wrapped.__onchange, text)
                            end
                        end
                    })
                end)
            end

            function wrapped:SetValue(v)
                local text = v
                if text == nil then
                    text = ''
                end
                if type(text) ~= 'string' then
                    text = tostring(text)
                end

                if native and type(native.Set) == 'function' then
                    pcall(function() native:Set(text) end)
                else
                    wrapped.Value = text
                    if wrapped.__onchange then
                        pcall(wrapped.__onchange, text)
                    end
                end
            end

            Options[id] = wrapped
            return wrapped
        end

        function gb:AddButton(name, fn)
            local nativeButton = section:Button()
            if nativeButton and type(nativeButton.Add) == 'function' then
                pcall(function()
                    nativeButton:Add(name, fn or function() end)
                end)
            end
            return gb
        end

        return gb
    end

    function Library:CreateWindow(opts)
        opts = opts or {}
        local realWindow = GuiLibrary:Window({
            Width = opts.Width or 550,
            Height = opts.Height or 555,
            Title = opts.Title or 'Coincide',
            Logo = opts.Logo or opts.logo or '77218680285262',
            FadeTime = opts.MenuFadeTime or opts.FadeTime or opts.fadetime or 0.2
        })

        pcall(function()
            if type(GuiLibrary.Watermark) == 'function' and not Library.Watermark then
                Library.Watermark = GuiLibrary:Watermark({ Text = "Coincide | dev" })
            end
        end)

        pcall(function()
            if type(GuiLibrary.PreviewWindow) == 'function' and not Library.PreviewWindow then
                local preview = GuiLibrary:PreviewWindow({
                    Title = "Preview",
                    Width = 240,
                    Height = 277
                })
                if preview and type(preview.PositionNextTo) == 'function' then
                    preview:PositionNextTo(realWindow)
                end
                if preview and type(preview.SyncWithWindow) == 'function' then
                    preview:SyncWithWindow(realWindow)
                end
                Library.PreviewWindow = preview
            end
        end)

        pcall(function()
            if type(GuiLibrary.Playerlist) == 'function' and not Library.Playerlist then
                local playerList = GuiLibrary:Playerlist({
                    Title = "Players",
                    Width = 240,
                    Height = 276
                })
                if playerList and Library.PreviewWindow and type(playerList.PositionBelow) == 'function' then
                    playerList:PositionBelow(Library.PreviewWindow)
                elseif playerList and type(playerList.PositionNextTo) == 'function' then
                    playerList:PositionNextTo(realWindow)
                end
                if playerList and type(playerList.SyncWithWindow) == 'function' then
                    playerList:SyncWithWindow(realWindow)
                end
                Library.Playerlist = playerList
            end
        end)

        pcall(function()
            if type(GuiLibrary.SettingsWindow) == 'function' and not Library.SettingsWindow then
                local settings = GuiLibrary:SettingsWindow({
                    Title = "Settings",
                    Width = 240,
                    Height = 555
                })
                if settings and type(settings.PositionNextTo) == 'function' then
                    settings:PositionNextTo(realWindow)
                end
                if settings and type(settings.SyncWithWindow) == 'function' then
                    settings:SyncWithWindow(realWindow)
                end
                if settings and type(settings.ApplySettings) == 'function' then
                    settings:ApplySettings()
                end
                Library.SettingsWindow = settings
            end
        end)

        pcall(function()
            if type(GuiLibrary.KeybindList) == 'function' and not Library.KeybindList then
                Library.KeybindList = GuiLibrary:KeybindList({
                    Title = "Keybinds"
                })
            end
        end)

        local window = {}
        function window:AddTab(name)
            local page = realWindow:Page({
                Name = name or 'Tab',
                Columns = 2
            })

            local tab = { name = name }

            function tab:AddLeftGroupbox(title)
                local section = page:Section({ Name = title or 'Left', Side = 1 })
                return makeGroupbox(section)
            end

            function tab:AddRightGroupbox(title)
                local section = page:Section({ Name = title or 'Right', Side = 2 })
                return makeGroupbox(section)
            end

            function tab:AddRightTabbox()
                local tabbox = {}
                function tabbox:AddTab(tabName)
                    return tab:AddRightGroupbox(tabName)
                end
                return tabbox
            end

            return tab
        end

        return window
    end

    function Library:Unload()
        if Library.Unloaded then
            return
        end

        Library.Unloaded = true
        pcall(function()
            if type(GuiLibrary.Unload) == 'function' then
                GuiLibrary:Unload()
            end
        end)
        for _, cb in ipairs(unloadCallbacks) do
            pcall(cb)
        end
    end
end

-- Minimal ThemeManager/SaveManager stubs used later in the script
local ThemeManager = { SetLibrary = function() end, ApplyToTab = function() end, SetFolder = function() end }
local SaveManager = {
    SetLibrary = function() end,
    IgnoreThemeSettings = function() end,
    SetIgnoreIndexes = function() end,
    SetFolder = function() end,
    BuildConfigSection = function() end,
    LoadAutoloadConfig = function() end
}

-- Expose Library globally (script expects it as global variable)
_G.Library = Library

local Window = Library:CreateWindow({
    -- Set Center to true if you want the menu to appear in the center
    -- Set AutoShow to true if you want the menu to appear when it is created
    -- Position and Size are also valid options here
    -- but you do not need to define them unless you are changing them :)

    Title = 'Bomzhood Hub',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

-- CALLBACK NOTE:
-- Passing in callback functions via the initial element parameters (i.e. Callback = function(Value)...) works
-- HOWEVER, using Toggles/Options.INDEX:OnChanged(function(Value) ... ) is the RECOMMENDED way to do this.
-- I strongly recommend decoupling UI code from logic code. i.e. Create your UI elements FIRST, and THEN setup :OnChanged functions later.

-- You do not have to set your tabs & groups up this way, just a prefrence.
local Tabs = {
    -- Creates a new tab titled Main
    Main = Window:AddTab('Main'),
    Visuals = Window:AddTab('Visuals'),
    Inventory = Window:AddTab('Inventory'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

-- Weapon Helpers groupbox (Linoria stub for SaveManager)
local TripleGroup = Tabs.Main:AddLeftGroupbox('Weapon Helpers')
TripleGroup:AddToggle('VestFixEnable', { Text = 'Vest Fix', Default = false })

local function IsPlayerKO(pl)
    if not pl then return false end
    local root = pl.Character
    local playersFolder = workspace:FindFirstChild('Players')
    if playersFolder then
        local wsChar = playersFolder:FindFirstChild(pl.Name)
        if wsChar then
            root = wsChar
        end
    end
    if not root then return false end

    local be = root:FindFirstChild('BodyEffects')
    if not be then return false end

    local ko = be:FindFirstChild('K.O') or be:FindFirstChild('K.O.')
    if ko and ko:IsA('BoolValue') then
        return ko.Value
    end

    return false
end

-- ?????????????????????????????????????????????
--  VEST FIX MODULE (DefenseBBGUI.Vest)
-- ?????????????????????????????????????????????
do
    local DEFENSE_NAME = 'DefenseBBGUI'
    local VEST_NAME = 'Vest'
    local NORMAL_HRP_SIZE = Vector3.new(2, 2, 1)
    local HRP_INFLATE_EPS = 0.35
    -- Was 20 Hz for all players; 5 Hz is enough and much cheaper.
    local FIX_POLL_INTERVAL = 1 / 5

    local VestFixEnabled = false
    local playerConnections = {}
    local bbBaseline = {}
    local fixAccumulator = 0

    local Players = game:GetService('Players')
    local RunService = game:GetService('RunService')

    local function getCharacterRoots(player)
        local roots = {}
        if player.Character then table.insert(roots, player.Character) end
        local folder = workspace:FindFirstChild('Players')
        if folder then
            local wsChar = folder:FindFirstChild(player.Name)
            if wsChar and wsChar ~= player.Character then table.insert(roots, wsChar) end
        end
        return roots
    end

    local function isHrpInflated(hrp)
        local s = hrp.Size
        return math.abs(s.X - NORMAL_HRP_SIZE.X) > HRP_INFLATE_EPS
            or math.abs(s.Y - NORMAL_HRP_SIZE.Y) > HRP_INFLATE_EPS
            or math.abs(s.Z - NORMAL_HRP_SIZE.Z) > HRP_INFLATE_EPS
    end

    local function getTorsoPart(character)
        return character:FindFirstChild('UpperTorso')
            or character:FindFirstChild('Torso')
            or character:FindFirstChild('HumanoidRootPart')
    end

    local function getVestCenterYOffsetStuds(bb, torso)
        local vest = bb:FindFirstChild(VEST_NAME)
        if not vest or not vest:IsA('GuiObject') then return 0 end
        local bbH = bb.Size.Y.Offset
        if bbH <= 0 then return 0 end
        local vestH = vest.Size.Y.Offset
        local ap = vest.AnchorPoint
        local pos = vest.Position
        local vestCenterY = pos.Y.Offset + vestH * (0.5 - ap.Y)
        local bbCenterY = bbH * 0.5
        local deltaPixels = vestCenterY - bbCenterY
        local scale = torso.Size.Y / bbH
        return deltaPixels * scale
    end

    local function getStudsOffsetForTorsoCenter(hrp, torso, bb)
        local yFix = getVestCenterYOffsetStuds(bb, torso)
        local targetWorld = (torso.CFrame * CFrame.new(0, yFix, 0)).Position
        return hrp.CFrame:PointToObjectSpace(targetWorld)
    end

    local function captureBillboardBaseline(bb, hrp)
        if bbBaseline[bb] then return bbBaseline[bb] end
        if hrp and isHrpInflated(hrp) then return nil end
        bbBaseline[bb] = {
            StudsOffset = bb.StudsOffset,
            Size = bb.Size,
            ExtentsOffset = bb.ExtentsOffset,
            ExtentsOffsetWorldSpace = bb.ExtentsOffsetWorldSpace,
            StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace,
        }
        return bbBaseline[bb]
    end

    local function restoreDefenseBBGui(character)
        local hrp = character and character:FindFirstChild('HumanoidRootPart')
        local bb = hrp and hrp:FindFirstChild(DEFENSE_NAME)
        if not bb or not bb:IsA('BillboardGui') then return end
        local base = bbBaseline[bb]
        if base then
            bb.StudsOffset = base.StudsOffset
            bb.Size = base.Size
            bb.ExtentsOffset = base.ExtentsOffset
            bb.ExtentsOffsetWorldSpace = base.ExtentsOffsetWorldSpace
            bb.StudsOffsetWorldSpace = base.StudsOffsetWorldSpace
        else
            -- Best-effort undo when baseline was never captured (HRP already inflated).
            bb.ExtentsOffset = Vector3.zero
            bb.ExtentsOffsetWorldSpace = Vector3.zero
            bb.StudsOffsetWorldSpace = Vector3.zero
        end
    end

    local function fixDefenseBBGui(character)
        if not VestFixEnabled or not character then return end
        local hrp = character:FindFirstChild('HumanoidRootPart')
        local bb = hrp and hrp:FindFirstChild(DEFENSE_NAME)
        if not bb or not bb:IsA('BillboardGui') then return end
        local base = captureBillboardBaseline(bb, hrp)
        if not isHrpInflated(hrp) then
            if base then
                bb.StudsOffset = base.StudsOffset
                bb.Size = base.Size
                bb.ExtentsOffset = base.ExtentsOffset
                bb.ExtentsOffsetWorldSpace = base.ExtentsOffsetWorldSpace
                bb.StudsOffsetWorldSpace = base.StudsOffsetWorldSpace
            end
            return
        end
        local torso = getTorsoPart(character)
        if torso and torso ~= hrp then
            bb.StudsOffset = getStudsOffsetForTorsoCenter(hrp, torso, bb)
        elseif base then
            local scaleY = hrp.Size.Y / NORMAL_HRP_SIZE.Y
            local scaleX = hrp.Size.X / NORMAL_HRP_SIZE.X
            local so = base.StudsOffset
            bb.StudsOffset = Vector3.new(so.X / scaleX, so.Y / scaleY, so.Z / scaleX)
        end
        if base then bb.Size = base.Size end
        bb.ExtentsOffset = Vector3.zero
        bb.ExtentsOffsetWorldSpace = Vector3.zero
        bb.StudsOffsetWorldSpace = Vector3.zero
    end

    local function restoreAll()
        for _, pl in ipairs(Players:GetPlayers()) do
            for _, root in ipairs(getCharacterRoots(pl)) do
                restoreDefenseBBGui(root)
            end
        end
    end

    local function disconnectPlayer(player)
        local pack = playerConnections[player]
        if not pack then return end
        for _, conn in ipairs(pack) do conn:Disconnect() end
        playerConnections[player] = nil
    end

    local function bindHrpSizeFix(player, character)
        local hrp = character:FindFirstChild('HumanoidRootPart')
        if not hrp then return end
        table.insert(playerConnections[player], hrp:GetPropertyChangedSignal('Size'):Connect(function()
            if VestFixEnabled then fixDefenseBBGui(character) end
        end))
        local bb = hrp:FindFirstChild(DEFENSE_NAME)
        if bb and bb:IsA('BillboardGui') then
            captureBillboardBaseline(bb, hrp)
            table.insert(playerConnections[player], bb:GetPropertyChangedSignal('StudsOffset'):Connect(function()
                if VestFixEnabled then
                    local character2 = bb:FindFirstAncestorOfClass('Model')
                    if character2 and isHrpInflated(hrp) then fixDefenseBBGui(character2) end
                end
            end))
        end
        if VestFixEnabled then fixDefenseBBGui(character) end
    end

    local function bindCharacter(player, character)
        if not playerConnections[player] then playerConnections[player] = {} end
        bindHrpSizeFix(player, character)
        table.insert(playerConnections[player], character.DescendantAdded:Connect(function(desc)
            if desc.Name == DEFENSE_NAME and desc:IsA('BillboardGui') then
                captureBillboardBaseline(desc, character:FindFirstChild('HumanoidRootPart'))
                bindHrpSizeFix(player, character)
            end
        end))
    end

    local function bindPlayer(player)
        player.CharacterAdded:Connect(function(character)
            disconnectPlayer(player)
            playerConnections[player] = {}
            bindCharacter(player, character)
        end)
        disconnectPlayer(player)
        playerConnections[player] = {}
        for _, root in ipairs(getCharacterRoots(player)) do
            bindCharacter(player, root)
        end
    end

    local function applyFixToAll()
        if not VestFixEnabled then return end
        for _, pl in ipairs(Players:GetPlayers()) do
            for _, root in ipairs(getCharacterRoots(pl)) do
                local hrp = root:FindFirstChild('HumanoidRootPart')
                -- Skip untouched characters ? no inflated HRP means nothing to fix.
                if hrp and isHrpInflated(hrp) then
                    fixDefenseBBGui(root)
                end
            end
        end
    end

    local function setVestFixEnabled(enabled)
        VestFixEnabled = enabled == true
        if VestFixEnabled then
            applyFixToAll()
        else
            restoreAll()
        end
    end

    if Toggles and Toggles.VestFixEnable then
        if type(Toggles.VestFixEnable.OnChanged) == 'function' then
            Toggles.VestFixEnable:OnChanged(function(v)
                setVestFixEnabled(v == true or (Toggles.VestFixEnable and Toggles.VestFixEnable.Value == true))
            end)
        end
        VestFixEnabled = Toggles.VestFixEnable.Value == true
        if VestFixEnabled then
            applyFixToAll()
        end
    end

    -- Lightweight backup poll only while enabled (event hooks cover most cases).
    safeConnect(RunService.Heartbeat, function(dt)
        if not VestFixEnabled then
            fixAccumulator = 0
            return
        end
        fixAccumulator = fixAccumulator + dt
        if fixAccumulator < FIX_POLL_INTERVAL then return end
        fixAccumulator = 0
        applyFixToAll()
    end)

    for _, pl in ipairs(Players:GetPlayers()) do bindPlayer(pl) end
    Players.PlayerAdded:Connect(bindPlayer)
    Players.PlayerRemoving:Connect(disconnectPlayer)
end

-- Weapon Helpers continued
-- Auto Fire: when enabled, holding LMB while any gun is equipped spams very fast clicks
TripleGroup:AddToggle('AutoRev', { Text = 'Auto Fire', Default = false })

-- Auto Fire: very fast click spam while holding a gun + LMB
do
    local Players = game:GetService('Players')
    local LocalPlayer = Players.LocalPlayer

    local UIS = game:GetService('UserInputService')
    local VirtualUser = game:GetService('VirtualUser')

    -- Weapon names used across this script / Boom Hood gun helpers
    local AUTO_FIRE_WEAPONS = {
        ['[Revolver]'] = true,
        ['[Double-Barrel SG]'] = true,
        ['[Shotgun]'] = true,
        ['[TacticalShotgun]'] = true,
    }

    local function isAutoFireWeapon(tool)
        if not tool or not tool:IsA('Tool') then
            return false
        end
        local name = tostring(tool.Name or '')
        if AUTO_FIRE_WEAPONS[name] then
            return true
        end
        local lowered = string.lower(name)
        return lowered == '[revolver]'
            or lowered == 'revolver'
            or string.find(lowered, 'revolver', 1, true) ~= nil
            or lowered == '[double-barrel sg]'
            or lowered == '[double-barrel]'
            or string.find(lowered, 'double%-barrel', 1, false) ~= nil
            or lowered == '[tacticalshotgun]'
            or lowered == '[tactical shotgun]'
            or (string.find(lowered, 'tactical', 1, true) ~= nil and string.find(lowered, 'shotgun', 1, true) ~= nil)
            or lowered == '[shotgun]'
            or lowered == 'shotgun'
            or (string.find(lowered, 'shotgun', 1, true) ~= nil and string.find(lowered, 'tactical', 1, true) == nil)
    end

    local AutoFireEnabled = false
    local fireHold = false
    local fireBeginConn, fireEndConn

    local function autoFireSpamLoop()
        local usedCapture = false
        while fireHold do
            local ok, curTool = pcall(function()
                if LocalPlayer and LocalPlayer.Character then
                    return LocalPlayer.Character:FindFirstChildOfClass('Tool')
                end
                return nil
            end)
            if not ok or not curTool then break end
            if not isAutoFireWeapon(curTool) then break end

            if not UIS:IsKeyDown(Enum.KeyCode.LeftControl) and not UIS:IsKeyDown(Enum.KeyCode.RightControl) then
                local activated = false
                pcall(function()
                    if curTool and type(curTool.Activate) == 'function' then
                        curTool:Activate()
                        activated = true
                    end
                end)

                if not activated then
                    if not usedCapture then
                        pcall(function() VirtualUser:CaptureController() end)
                        usedCapture = true
                    end
                    pcall(function()
                        VirtualUser:Button1Down()
                        task.wait(0.006)
                        VirtualUser:Button1Up()
                    end)
                end
            end

            task.wait(0.03)
        end
    end

    if Toggles and Toggles.AutoRev then
        Toggles.AutoRev:OnChanged(function()
            AutoFireEnabled = Toggles.AutoRev.Value
            if AutoFireEnabled then
                if not fireBeginConn then
                    fireBeginConn = safeConnect(UIS.InputBegan, function(input, gameProcessed)
                        if gameProcessed then return end
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                        if not AutoFireEnabled then return end
                        local cur = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Tool')
                        if not isAutoFireWeapon(cur) then return end
                        if fireHold then return end
                        fireHold = true
                        safeSpawn(autoFireSpamLoop)
                    end)
                end

                if not fireEndConn then
                    fireEndConn = safeConnect(UIS.InputEnded, function(input, gameProcessed)
                        if gameProcessed then return end
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                        fireHold = false
                    end)
                end
            else
                if fireBeginConn then pcall(function() fireBeginConn:Disconnect() end) fireBeginConn = nil end
                if fireEndConn then pcall(function() fireEndConn:Disconnect() end) fireEndConn = nil end
                fireHold = false
            end
        end)
    end

    Library:OnUnload(function()
        if fireBeginConn then pcall(function() fireBeginConn:Disconnect() end) fireBeginConn = nil end
        if fireEndConn then pcall(function() fireEndConn:Disconnect() end) fireEndConn = nil end
        fireHold = false
        AutoFireEnabled = false
    end)
end

-- Anti-AimViewer (from 123.lua Anti-Spec, without __namecall)
if not Toggles.AntiAimViewerEnabled then
    Toggles.AntiAimViewerEnabled = makeToggle('AntiAimViewerEnabled', false)
end

do
    local syncAntiAimViewer = nil

    local function bindChange(obj, fn)
        if type(obj) ~= 'table' then
            return
        end
        local prev = obj.__onchange
        obj.__onchange = function(...)
            if type(prev) == 'function' then
                pcall(prev, ...)
            end
            pcall(fn, ...)
        end
    end

    bindChange(Toggles.AntiAimViewerEnabled, function()
        if syncAntiAimViewer then
            syncAntiAimViewer()
        end
    end)

    safeSpawn(function()
        local Players = game:GetService('Players')
        local ReplicatedStorage = game:GetService('ReplicatedStorage')
        local RunService = game:GetService('RunService')
        local Workspace = game:GetService('Workspace')

        local LocalPlayer = Players.LocalPlayer
        repeat task.wait() until LocalPlayer

        local antiSpecEnabled = false
        local antiSpecTelem = nil
        local antiSpecAdminRemotes = nil
        local antiSpecWasKilled = false
        local antiSpecMouseInvokeOld = nil
        local antiSpecKillClock = 0
        local antiSpecHideTick = 0

        local NAN = 0 / 0
        local NAN_VEC = Vector3.new(NAN, NAN, NAN)
        local NAN_CF = CFrame.new(NAN, NAN, NAN)

        local function hiddenTelemPayload()
            antiSpecHideTick = antiSpecHideTick + 1
            local mode = antiSpecHideTick % 3
            if mode == 0 then
                return NAN_CF, NAN_VEC, 0
            elseif mode == 1 then
                return CFrame.new(), false, 0
            end
            return CFrame.new(), nil, 0
        end

        local function findSpecTelemetry()
            local ps = LocalPlayer:FindFirstChild('PlayerScripts')
            if not ps then
                return nil
            end
            local s = ps:FindFirstChild('SpecTelemetry')
            if s and s:IsA('LocalScript') then
                return s
            end
            return nil
        end

        local function killSpecTelemetry()
            local s = findSpecTelemetry()
            if not s then
                return
            end
            pcall(function()
                if type(getscriptthread) == 'function' then
                    local th = getscriptthread(s)
                    if th then
                        task.cancel(th)
                    end
                end
            end)
            pcall(function()
                s.Disabled = true
            end)
        end

        local function restoreSpecTelemetry()
            local s = findSpecTelemetry()
            if not s then
                return
            end
            pcall(function()
                if s.Disabled then
                    s.Disabled = false
                end
            end)
        end

        local function getBodyMousePos()
            local char = LocalPlayer.Character
            if not char then
                return nil
            end
            local be = char:FindFirstChild('BodyEffects')
            if not be then
                local folder = Workspace:FindFirstChild('Players')
                local wchar = folder and folder:FindFirstChild(LocalPlayer.Name)
                be = wchar and wchar:FindFirstChild('BodyEffects')
            end
            return be and be:FindFirstChild('MousePos')
        end

        local function setupMouseInvokeSpoof()
            if antiSpecMouseInvokeOld or type(filtergc) ~= 'function' or type(hookfunction) ~= 'function' then
                return
            end
            local invoke = filtergc('function', { Constants = { 'MOUSEPOS' } }, true)
            if type(invoke) ~= 'function' then
                return
            end
            local wrap = function(p1, ...)
                if antiSpecEnabled then
                    if p1 == 'MOUSEPOS' or p1 == 'Aim' then
                        return nil
                    end
                end
                return antiSpecMouseInvokeOld(p1, ...)
            end
            if type(newcclosure) == 'function' then
                wrap = newcclosure(wrap)
            end
            antiSpecMouseInvokeOld = hookfunction(invoke, wrap)
        end

        local function setAntiAimViewer(enabled)
            antiSpecEnabled = enabled == true
            if antiSpecEnabled then
                killSpecTelemetry()
                antiSpecWasKilled = true
                setupMouseInvokeSpoof()
            else
                restoreSpecTelemetry()
                antiSpecWasKilled = false
            end
        end

        local function setupAntiAimViewer()
            antiSpecAdminRemotes = ReplicatedStorage:FindFirstChild('AdminRemotes')
                or ReplicatedStorage:WaitForChild('AdminRemotes', 30)
            if not antiSpecAdminRemotes then
                return
            end

            antiSpecTelem = antiSpecAdminRemotes:FindFirstChild('Telem')
                or antiSpecAdminRemotes:WaitForChild('Telem', 30)
            if not antiSpecTelem then
                return
            end

            local ps = LocalPlayer:FindFirstChild('PlayerScripts')
                or LocalPlayer:WaitForChild('PlayerScripts', 30)
            if ps then
                safeConnect(ps.ChildAdded, function(child)
                    if antiSpecEnabled and child.Name == 'SpecTelemetry' and child:IsA('LocalScript') then
                        task.defer(killSpecTelemetry)
                    end
                end)
            end

            local function antiSpecStep(dt)
                if not antiSpecEnabled or not antiSpecAdminRemotes or not antiSpecTelem then
                    if antiSpecWasKilled and not antiSpecEnabled then
                        restoreSpecTelemetry()
                        antiSpecWasKilled = false
                    end
                    return
                end

                antiSpecKillClock = antiSpecKillClock + (dt or 0)
                if antiSpecKillClock >= 0.2 then
                    antiSpecKillClock = 0
                    killSpecTelemetry()
                end

                local mp = getBodyMousePos()
                if mp then
                    pcall(function()
                        mp.Value = NAN_VEC
                    end)
                end

                if antiSpecAdminRemotes:GetAttribute('SpecActive') then
                    pcall(function()
                        antiSpecTelem:FireServer(hiddenTelemPayload())
                    end)
                end
            end

            safeConnect(RunService.Heartbeat, antiSpecStep)
        end

        setupAntiAimViewer()

        syncAntiAimViewer = function()
            setAntiAimViewer(Toggles.AntiAimViewerEnabled and Toggles.AntiAimViewerEnabled.Value == true)
        end
        syncAntiAimViewer()

        Library:OnUnload(function()
            setAntiAimViewer(false)
        end)
    end)
end

local TabBox = Tabs.Main:AddRightTabbox() -- Add Tabbox on right side

-- Trigger Bot tab (replaces previous Tab 1/Tab 2)
local Tab1 = TabBox:AddTab('Trigger Bot')
Tab1:AddToggle('TriggerEnabled', { Text = 'Enable Trigger Bot', Default = false })
-- Key picker with built-in Mode support (Hold/Toggle/Always). We also expose a small dropdown
-- for backwards compatibility and easy access in case some runtimes don't expose the popup.
Tab1:AddLabel('Trigger Key'):AddKeyPicker('TriggerKey', { Default = 'C', NoUI = false, Text = 'Trigger Key', Mode = 'Hold' })
Tab1:AddSlider('TriggerDelay', { Text = 'Delay (ms)', Default = 0, Min = 0, Max = 500, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerRevolverRange', { Text = 'Revolver Range', Default = 165, Min = 0, Max = 165, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerDoubleBarrelRange', { Text = 'Double-Barrel Range', Default = 120, Min = 0, Max = 120, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerShotgunRange', { Text = 'Shotgun Range', Default = 95, Min = 0, Max = 95, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerTacticalShotgunRange', { Text = 'Tactical Shotgun Range', Default = 65, Min = 0, Max = 65, Rounding = 0, Compact = false })
Tab1:AddToggle('TriggerMissEnabled', { Text = 'Enable Miss Chance', Default = false })
Tab1:AddSlider('TriggerMissPercent', { Text = 'Miss Chance (% near-miss fire)', Default = 0, Min = 0, Max = 100, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerMissRadius', { Text = 'Miss Radius (px)', Default = 30, Min = 5, Max = 150, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerMissRevolverShots', { Text = 'Miss Revolver Shots', Default = 3, Min = 1, Max = 6, Rounding = 0, Compact = false })
Tab1:AddSlider('TriggerMissShotgunShots', { Text = 'Miss Shotgun Shots', Default = 1, Min = 1, Max = 3, Rounding = 0, Compact = false })

-- Trigger whitelist stubbed out for safety
Options.TriggerWhitelist = makeOption('TriggerWhitelist', {})

-- We rely solely on the KeyPicker's own mode (selected via the small popup) and read
-- its stored value per-frame; no separate dropdown is required.

local Tab2 = TabBox:AddTab('Auto-Shot')
Tab2:AddToggle('AutoShotEnabled', { Text = 'Enable Auto-Shot', Default = true })
Tab2:AddLabel('Auto-Shot Key'):AddKeyPicker('AutoShotKey', { Default = 'X', NoUI = false, Text = 'Auto-Shot Key', Mode = 'Hold' })
Tab2:AddToggle('AutoShotQuickSelectEnabled', { Text = 'Auto-Shot Quick Select (LeftAlt)', Default = true })
Tab2:AddDropdown('AutoShotMode', {
    Text = 'Auto-Shot Mode',
    Values = { 'SINGLE', 'BURST' },
    Default = 'BURST',
    Multi = false,
    Callback = function() end
})
Tab2:AddDropdown('AutoShotTargetPlayer', {
    SpecialType = 'Player',
    Text = 'Auto-Shot Target',
    Multi = false,
    Default = '',
    Callback = function() end
})
Tab2:AddSlider('AutoShotDelayMin', { Text = 'Auto-Shot Min Delay (ms)', Default = 130, Min = 0, Max = 500, Rounding = 0, Compact = false })
Tab2:AddSlider('AutoShotDelayMax', { Text = 'Auto-Shot Max Delay (ms)', Default = 200, Min = 0, Max = 500, Rounding = 0, Compact = false })

-- Inventory tab: auto sorter
do
    local InventoryTab = Tabs.Inventory
    if InventoryTab then
        local sorterGroup = InventoryTab:AddLeftGroupbox('Inventory Sorter')
        sorterGroup:AddToggle('InventoryAutoSortEnabled', { Text = 'Auto Sort', Default = false })
        sorterGroup:AddToggle('InventoryAutoSortOnSpawn', { Text = 'Auto Sort On Spawn', Default = true })
        sorterGroup:AddLabel('Auto Sort Key')
            :AddKeyPicker('InventoryAutoSortKey', { Default = 'V', NoUI = false, Text = 'Auto Sort Key', Mode = 'Hold' })

        local inventoryItems = getInventoryToolNames()
        for i = 1, 9 do
            sorterGroup:AddDropdown('InventorySlot' .. i, {
                Text = 'Slot ' .. i,
                Values = inventoryItems,
                Default = '',
                Multi = false,
                Callback = function() end,
            })
        end
    end
end

-- Trigger Bot implementation
do
    -- Triggerbot wired to UI keybind (Options.TriggerKey) and Trigger toggle
    local Players = game:GetService('Players')
    local RunService = game:GetService('RunService')
    local UIS = game:GetService('UserInputService')
    local LocalPlayer = Players.LocalPlayer
    local mouse = LocalPlayer and LocalPlayer:GetMouse()
    local isTriggerMouseDown = false
    local nextAllowedShotAt = 0
    local lastWeaponName = nil
    -- One miss roll per trigger-key press. Shot budget depends on weapon:
    -- shotguns = 1 shot, revolver = several. Prevents per-frame re-rolls.
    local missBindWasActive = false
    local missNearAllow = false
    local missShotsLeft = 0
    local REVOLVER_MISS_SHOTS_FALLBACK = 3
    local SHOTGUN_MISS_SHOTS_FALLBACK = 1

    local function getTriggerMaxRange(toolName)
        if toolName == '[Revolver]' then
            local value = tonumber(Options and Options.TriggerRevolverRange and Options.TriggerRevolverRange.Value) or 165
            return math.clamp(value, 0, 165)
        elseif toolName == '[Double-Barrel SG]' then
            local value = tonumber(Options and Options.TriggerDoubleBarrelRange and Options.TriggerDoubleBarrelRange.Value) or 120
            return math.clamp(value, 0, 120)
        elseif toolName == '[Shotgun]' then
            local value = tonumber(Options and Options.TriggerShotgunRange and Options.TriggerShotgunRange.Value) or 95
            return math.clamp(value, 0, 95)
        elseif toolName == '[TacticalShotgun]' then
            local value = tonumber(Options and Options.TriggerTacticalShotgunRange and Options.TriggerTacticalShotgunRange.Value) or 65
            return math.clamp(value, 0, 65)
        end
        return nil
    end

    local TriggerWhitelist = {}

    local function forceReleaseTriggerMouse()
        if isTriggerMouseDown then
            pcall(function() mouse1release() end)
        end
        isTriggerMouseDown = false
    end

    local function stopTriggerFire()
        forceReleaseTriggerMouse()
        nextAllowedShotAt = 0
    end

    local function tryTriggerShot(currentToolName)
        local delayMs = 0
        pcall(function()
            delayMs = tonumber(Options and Options.TriggerDelay and Options.TriggerDelay.Value) or 0
        end)
        local userDelaySec = math.max(delayMs, 0) / 1000
        local now = os.clock()

        if lastWeaponName ~= currentToolName then
            lastWeaponName = currentToolName
            nextAllowedShotAt = 0
            forceReleaseTriggerMouse()
        end

        if now < nextAllowedShotAt then
            return
        end

        pcall(function() mouse1press() end)
        isTriggerMouseDown = true
        task.delay(0.01, function()
            forceReleaseTriggerMouse()
        end)

        nextAllowedShotAt = now + userDelaySec
    end

    -- Robustly rebuild TriggerWhitelist from the UI dropdown value.
    -- The dropdown may return several shapes depending on runtime: { name = true },
    -- array-style { [1] = 'name' }, numeric keys, or userId numbers. Handle common cases.
    local function rebuildTriggerWhitelist()
        TriggerWhitelist = {}
        pcall(function()
            if not (Options and Options.TriggerWhitelist) then return end
            local val = Options.TriggerWhitelist.Value
            if type(val) ~= 'table' then return end
            for k, v in next, val do
                local candidateName = nil

                -- common case: key = playerName, value = true
                if type(k) == 'string' and v == true then
                    candidateName = k
                end

                -- array-style: value is the playerName string
                if not candidateName and type(v) == 'string' then
                    candidateName = v
                end

                -- numeric key or value might be a userId
                if not candidateName then
                    if type(k) == 'number' then
                        local p = Players:GetPlayerByUserId(k)
                        if p then candidateName = p.Name end
                    elseif type(v) == 'number' then
                        local p = Players:GetPlayerByUserId(v)
                        if p then candidateName = p.Name end
                    elseif type(k) == 'string' then
                        local num = tonumber(k)
                        if num then
                            local p = Players:GetPlayerByUserId(num)
                            if p then candidateName = p.Name end
                        end
                    end
                end

                -- Player object cases (some libs may pass object refs)
                if not candidateName and type(k) == 'userdata' and typeof(k) == 'Instance' and k.IsA and k:IsA('Player') then
                    candidateName = k.Name
                end
                if not candidateName and type(v) == 'userdata' and typeof(v) == 'Instance' and v.IsA and v:IsA('Player') then
                    candidateName = v.Name
                end

                if candidateName then
                    TriggerWhitelist[candidateName] = true
                end
            end
        end)
    end

    -- Wire OnChanged to rebuild and do an initial build
    if Options and Options.TriggerWhitelist and type(Options.TriggerWhitelist.OnChanged) == 'function' then
        pcall(function() Options.TriggerWhitelist:OnChanged(rebuildTriggerWhitelist) end)
    end
    rebuildTriggerWhitelist()

    -- Miss logic:
    --   ? Cursor ON player  ? always shoot (hit).
    --   ? Cursor NEAR player (within Miss Radius) but not on them ? near-miss:
    --       Miss Chance % = chance to still click (soft / legit spray).
    -- One roll per bind press; budget from Miss Shots panel (revolver vs shotguns).
    local function isMissFeatureActive()
        local enabled = false
        pcall(function()
            enabled = Toggles and Toggles.TriggerMissEnabled and Toggles.TriggerMissEnabled.Value == true
        end)
        if not enabled then
            return false
        end
        local mode = 'Hitbox'
        pcall(function()
            mode = tostring(Options and Options.TriggerMode and Options.TriggerMode.Value) or 'Hitbox'
        end)
        return mode == 'Hitbox'
    end

    local function readMissChancePercent()
        local chance = 0
        pcall(function()
            chance = tonumber(Options and Options.TriggerMissPercent and Options.TriggerMissPercent.Value) or 0
        end)
        return math.clamp(chance, 0, 100)
    end

    local function readMissRadiusPx()
        local radius = 30
        pcall(function()
            radius = tonumber(Options and Options.TriggerMissRadius and Options.TriggerMissRadius.Value) or 30
        end)
        return math.max(radius, 1)
    end

    local function getCurrentTriggerToolName()
        local name = nil
        pcall(function()
            local curTool = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Tool')
            if curTool then
                name = curTool.Name
            end
        end)
        return name
    end

    local function getMissShotBudget(toolName)
        if toolName == '[Revolver]' then
            local shots = REVOLVER_MISS_SHOTS_FALLBACK
            pcall(function()
                shots = tonumber(Options and Options.TriggerMissRevolverShots and Options.TriggerMissRevolverShots.Value) or REVOLVER_MISS_SHOTS_FALLBACK
            end)
            return math.clamp(math.floor(shots), 1, 6)
        end
        local shots = SHOTGUN_MISS_SHOTS_FALLBACK
        pcall(function()
            shots = tonumber(Options and Options.TriggerMissShotgunShots and Options.TriggerMissShotgunShots.Value) or SHOTGUN_MISS_SHOTS_FALLBACK
        end)
        return math.clamp(math.floor(shots), 1, 3)
    end

    local function resetMissDecision()
        missNearAllow = false
        missShotsLeft = 0
    end

    local function rollMissForPress(toolName)
        local chance = readMissChancePercent()
        if chance <= 0 then
            resetMissDecision()
            return
        end
        missNearAllow = math.random(1, 100) <= chance
        missShotsLeft = getMissShotBudget(toolName)
    end

    local function getNearestEnemyOnScreen(radius)
        local cam = workspace.CurrentCamera
        if not cam then return nil end
        local mousePos = UIS:GetMouseLocation()
        local bestDist = radius
        local bestPlayer = nil
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and not isSharedFriendRole(pl) then
                if not (TriggerWhitelist and TriggerWhitelist[pl.Name] and not isSharedTargetRole(pl)) then
                    if not (Toggles.TriggerTargetOnly and Toggles.TriggerTargetOnly.Value == true and not isSharedTargetRole(pl)) then
                        local char = pl.Character
                        if char then
                            local hum = char:FindFirstChildOfClass('Humanoid')
                            local root = char:FindFirstChild('HumanoidRootPart') or char:FindFirstChildOfClass('BasePart')
                            if hum and hum.Health and hum.Health > 0 and root then
                                local sp, onScreen = cam:WorldToViewportPoint(root.Position)
                                if onScreen and sp.Z > 0 then
                                    local dx = sp.X - mousePos.X
                                    local dy = sp.Y - mousePos.Y
                                    local dist = math.sqrt(dx * dx + dy * dy)
                                    if dist < bestDist then
                                        bestDist = dist
                                        bestPlayer = pl
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return bestPlayer
    end

    -- Near-miss only: % = chance to FIRE while off-target but near an enemy.
    -- Direct hits never call this ? they always fire.
    -- Consumes one shot from the per-press budget (fire or intentional miss).
    local function shouldFireNearMiss(pl)
        local chance = readMissChancePercent()
        if chance <= 0 then
            resetMissDecision()
            return false
        end

        if missShotsLeft <= 0 then
            return false
        end

        missShotsLeft = missShotsLeft - 1
        if not missNearAllow then
            return false
        end
        return true
    end

    -- We'll respect the UI toggle (Toggles.TriggerEnabled) and the KeyPicker stored in Options.TriggerKey
    local triggerEnabledCached = false
    pcall(function()
        triggerEnabledCached = Toggles and Toggles.TriggerEnabled and Toggles.TriggerEnabled.Value == true
        if Toggles and Toggles.TriggerEnabled and type(Toggles.TriggerEnabled.OnChanged) == 'function' then
            local prev = Toggles.TriggerEnabled.__onchange
            Toggles.TriggerEnabled:OnChanged(function(...)
                if type(prev) == 'function' then
                    pcall(prev, ...)
                end
                triggerEnabledCached = Toggles.TriggerEnabled.Value == true
            end)
        end
    end)

safeConnect(RunService.RenderStepped, function()
        if Library.Unloaded then
            stopTriggerFire()
            resetMissDecision()
            return
        end
        if not triggerEnabledCached then
            if isTriggerMouseDown then
                stopTriggerFire()
                resetMissDecision()
            end
            return
        end
        if not LocalPlayer or not mouse then
            stopTriggerFire()
            resetMissDecision()
            return
        end

        -- determine key state from KeyPicker (supports Hold/Toggle/Always modes)
        local keyActive = false
        pcall(function()
            local mode = 'Hold'
            local keyValue = nil
            local okv, v = pcall(function() return (Options and Options.TriggerKey and Options.TriggerKey.Value) end)
            if okv then
                keyValue = v
            end

            if keyValue then
                if type(keyValue) == 'table' and keyValue[2] then
                    mode = tostring(keyValue[2])
                elseif type(keyValue) == 'table' and keyValue.Mode then
                    mode = tostring(keyValue.Mode)
                end
            end

            if mode == 'Always' then
                keyActive = true
                return
            end

            if Options and Options.TriggerKey and type(Options.TriggerKey.GetState) == 'function' then
                local ok2, st = pcall(function() return Options.TriggerKey:GetState() end)
                if ok2 and st then
                    keyActive = true
                    return
                end
            end

            local function isPressed(raw)
                if typeof(raw) == 'EnumItem' then
                    if raw.EnumType == Enum.KeyCode then
                        local okDown, isDown = pcall(function() return UIS:IsKeyDown(raw) end)
                        return okDown and isDown
                    end
                    if raw.EnumType == Enum.UserInputType then
                        local okMouse, isDown = pcall(function() return UIS:IsMouseButtonPressed(raw) end)
                        return okMouse and isDown
                    end
                    return false
                end

                if type(raw) == 'string' then
                    local kc = Enum.KeyCode[raw]
                    if kc then
                        local okDown, isDown = pcall(function() return UIS:IsKeyDown(kc) end)
                        return okDown and isDown
                    end
                    local ui = Enum.UserInputType[raw]
                    if ui then
                        local okMouse, isDown = pcall(function() return UIS:IsMouseButtonPressed(ui) end)
                        return okMouse and isDown
                    end
                end

                return false
            end

            local lookup = keyValue
            if type(keyValue) == 'table' then
                lookup = keyValue.Key or keyValue[1]
            end

            if isPressed(lookup) then
                keyActive = true
                return
            end

            -- fallback for commonly used hold behavior with keyboard-only key names
            if type(lookup) == 'string' and #lookup == 1 then
                local upper = string.upper(lookup)
                local keyEnum = Enum.KeyCode[upper]
                if keyEnum then
                    local okDown, isDown = pcall(function() return UIS:IsKeyDown(keyEnum) end)
                    if okDown and isDown then
                        keyActive = true
                    end
                end
            end
        end)
        if not keyActive then
            stopTriggerFire()
            resetMissDecision()
            missBindWasActive = false
            return
        end

        -- One miss roll per bind press (rising edge). Always mode re-rolls when budget is spent.
        do
            local triggerKeyMode = 'Hold'
            pcall(function()
                local keyValue = Options and Options.TriggerKey and Options.TriggerKey.Value
                if type(keyValue) == 'table' then
                    triggerKeyMode = tostring(keyValue[2] or keyValue.Mode or 'Hold')
                end
            end)
            local toolName = getCurrentTriggerToolName()
            local shouldRoll = false
            if not missBindWasActive then
                shouldRoll = true
            elseif triggerKeyMode == 'Always' and missShotsLeft <= 0 and isMissFeatureActive() then
                shouldRoll = true
            end
            if shouldRoll and isMissFeatureActive() then
                rollMissForPress(toolName)
            end
            missBindWasActive = true
        end

        -- skip if local player is holding [Knife]
        local skipLocalKnife = false
        pcall(function()
            if LocalPlayer and LocalPlayer.Character then
                local curTool = LocalPlayer.Character:FindFirstChildOfClass('Tool')
                if curTool and curTool.Name == '[Knife]' then
                    skipLocalKnife = true
                end
            end
        end)
        if skipLocalKnife then
            stopTriggerFire()
            return
        end

        local target = nil
        local isNearMiss = false
        pcall(function() target = mouse.Target end)

        local fromGhost = false
        local ghostPlayer = nil
        pcall(function()
            if not (BacktrackApi and BacktrackApi.isActive and BacktrackApi.isActive()) then
                return
            end
            if type(BacktrackApi.resolveFromPart) ~= 'function' then
                return
            end
            local gpl, live, gpart = BacktrackApi.resolveFromPart(target)
            if not gpl or not live then
                return
            end
            -- Dead ghosts already have CanQuery off; skip extra Range/LoS raycast.
            if typeof(gpart) == 'Instance' and gpart:IsA('BasePart') and gpart.CanQuery == false then
                return
            end
            local origin = nil
            if type(BacktrackApi.muzzleOrigin) == 'function' then
                origin = BacktrackApi.muzzleOrigin()
            end
            local passesChance = true
            if type(BacktrackApi.peekTriggerUseGhost) == 'function' then
                passesChance = BacktrackApi.peekTriggerUseGhost() == true
            elseif type(BacktrackApi.peekUseGhost) == 'function' then
                passesChance = BacktrackApi.peekUseGhost() == true
            end
            local registers = passesChance
            if registers and type(BacktrackApi.wouldRegister) == 'function' then
                registers = BacktrackApi.wouldRegister(origin, live, gpl) == true
            end
            if registers then
                ghostPlayer = gpl
                target = live
                fromGhost = true
                return
            end
            -- Ghost would not register: look through it at the live model. Do not nil target / stop fire.
            local cam = workspace.CurrentCamera
            if not cam then
                return
            end
            local mousePos = UIS:GetMouseLocation()
            local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local exclude = {}
            if LocalPlayer.Character then
                exclude[#exclude + 1] = LocalPlayer.Character
            end
            local folder = workspace:FindFirstChild('BacktrackGhosts')
            if folder then
                exclude[#exclude + 1] = folder
            end
            params.FilterDescendantsInstances = exclude
            local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
            if result and result.Instance then
                target = result.Instance
            end
        end)

        -- Old near-miss path: only scan players when cursor is NOT already on a player.
        if (not fromGhost) and isMissFeatureActive() then
            local playerOnTarget = nil
            if target and target.Parent then
                local modelOnTarget = target.Parent:FindFirstAncestorOfClass('Model') or target.Parent
                pcall(function() playerOnTarget = Players:GetPlayerFromCharacter(modelOnTarget) end)
            end
            if not playerOnTarget then
                local radius = readMissRadiusPx()
                local nearPlayer = getNearestEnemyOnScreen(radius)
                if nearPlayer then
                    local char = nearPlayer.Character
                    if char then
                        target = char:FindFirstChild('HumanoidRootPart') or char:FindFirstChildOfClass('BasePart')
                        isNearMiss = true
                    end
                end
            end
        end

        if not target or not target.Parent then
            stopTriggerFire()
            if not isNearMiss then
                resetMissDecision()
            end
            return
        end

        local triggerMode = 'Hitbox'
        pcall(function() triggerMode = tostring(Options.TriggerMode.Value) end)

        -- find humanoid on the target's parent or its parent
        local parent = target.Parent
        local humanoid = parent:FindFirstChildOfClass('Humanoid') or (parent.Parent and parent.Parent:FindFirstChildOfClass('Humanoid'))

        -- attempt to resolve the character/model and player for KO checks
        local modelInstance = parent:FindFirstAncestorOfClass('Model') or parent
        local pl = ghostPlayer
        if not pl then
            pcall(function()
                if modelInstance then pl = Players:GetPlayerFromCharacter(modelInstance) end
            end)
        else
            pcall(function()
                if pl.Character then
                    modelInstance = pl.Character
                    parent = pl.Character
                    humanoid = pl.Character:FindFirstChildOfClass('Humanoid') or humanoid
                end
            end)
        end

        if (not fromGhost) and triggerMode == 'Model' then
            local modelFits = false
            pcall(function()
                if pl and pl.Character then
                    local cam = workspace.CurrentCamera
                    local mousePos = UIS:GetMouseLocation()
                    for _, part in ipairs(pl.Character:GetChildren()) do
                        if part:IsA('BasePart') and part.Name ~= 'HumanoidRootPart' then
                            local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen then
                                local dx = sp.X - mousePos.X
                                local dy = sp.Y - mousePos.Y
                                if dx * dx + dy * dy < 900 then
                                    modelFits = true
                                    break
                                end
                            end
                        end
                    end
                end
            end)
            if not modelFits then
                humanoid = nil
            else
                pcall(function()
                    local myChar = LocalPlayer.Character
                    local myRoot = myChar and myChar:FindFirstChild('HumanoidRootPart')
                    local theirChar = pl.Character
                    local theirPart = nil
                    for _, part in ipairs(theirChar:GetChildren()) do
                        if part:IsA('BasePart') and part.Name ~= 'HumanoidRootPart' then
                            theirPart = part
                            break
                        end
                    end
                    if myRoot and theirPart then
                        local rayParams = RaycastParams.new()
                        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                        rayParams.FilterDescendantsInstances = { myChar, theirChar }
                        local result = workspace:Raycast(myRoot.Position, theirPart.Position - myRoot.Position, rayParams)
                        if result and result.Instance then
                            humanoid = nil
                        end
                    end
                end)
            end
        end

        -- skip if the target is our local player or in the trigger whitelist
        if parent.Name == (LocalPlayer and LocalPlayer.Name) then
            stopTriggerFire()
            resetMissDecision()
            return
        end
        if pl and isSharedFriendRole(pl) then
            stopTriggerFire()
            resetMissDecision()
            return
        end
        if pl and Toggles.TriggerTargetOnly and Toggles.TriggerTargetOnly.Value == true and not isSharedTargetRole(pl) then
            stopTriggerFire()
            resetMissDecision()
            return
        end
        if pl and TriggerWhitelist and TriggerWhitelist[pl.Name] and not isSharedTargetRole(pl) then
            -- whitelisted player: do not trigger
            stopTriggerFire()
            resetMissDecision()
            return
        end

        -- helper: robust KO check that inspects BodyEffects under the model or workspace.Players entry
        local function modelIsKO(m, targ)
            if not m then return false end
            local be = m:FindFirstChild('BodyEffects')
            local directKO = m:FindFirstChild('K.O') or m:FindFirstChild('K.O.')
            if directKO and directKO:IsA('BoolValue') then
                return directKO.Value
            end
            if not be and m.Parent then
                be = m.Parent:FindFirstChild('BodyEffects')
            end
            -- O(1) lookup by name ? never walk all workspace.Players children.
            if not be then
                local playersFolder = workspace:FindFirstChild('Players')
                local entryName = (typeof(m) == 'Instance' and m.Name) or nil
                if not entryName and pl then
                    entryName = pl.Name
                end
                if playersFolder and entryName then
                    local entry = playersFolder:FindFirstChild(entryName)
                    if entry then
                        be = entry:FindFirstChild('BodyEffects')
                    end
                end
            end
            if not be then return false end
            local ko = be:FindFirstChild('K.O') or be:FindFirstChild('K.O.')
            if ko and ko:IsA('BoolValue') then
                return ko.Value
            end
            return false
        end

        -- check humanoid health and KO state (prefer IsPlayerKO when available, fallback to model check)
        local isKO = false
        pcall(function()
            if pl and IsPlayerKO and type(IsPlayerKO) == 'function' then
                isKO = IsPlayerKO(pl)
            else
                isKO = modelIsKO(modelInstance, target)
            end
        end)

        -- if KO, skip
        if isKO then
            stopTriggerFire()
            resetMissDecision()
            return
        end

        if humanoid and not isKO and humanoid.Health and humanoid.Health > 0 then
            -- Hard range gating for requested weapons.
            local inRangeAllowed = true
            local currentToolName = nil
            pcall(function()
                local curTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Tool')
                if curTool then
                    local tname = curTool.Name
                    currentToolName = tname
                    local maxRange = getTriggerMaxRange(tname)

                    if maxRange then
                        local root = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild('HumanoidRootPart') or LocalPlayer.Character.PrimaryPart)
                        local targPos = nil

                        if target and target:IsA('BasePart') then
                            targPos = target.Position
                        elseif modelInstance then
                            local targetRoot = modelInstance:FindFirstChild('HumanoidRootPart') or modelInstance.PrimaryPart
                            if targetRoot and targetRoot:IsA('BasePart') then
                                targPos = targetRoot.Position
                            end
                        end

                        if not root or not targPos then
                            inRangeAllowed = false
                        elseif (root.Position - targPos).Magnitude > maxRange then
                            inRangeAllowed = false
                        end
                    end
                end
            end)

            if not inRangeAllowed then
                -- release and skip firing when out of range
                stopTriggerFire()
                return
            end

            if isNearMiss then
                -- Off-target but near enemy: fire only with Miss Chance % (one roll per bind press).
                if shouldFireNearMiss(pl) then
                    tryTriggerShot(currentToolName)
                else
                    forceReleaseTriggerMouse()
                end
            else
                -- Direct lock on player: always shoot (old behavior).
                tryTriggerShot(currentToolName)
            end
            return
        end

        stopTriggerFire()
        if not isNearMiss then
            resetMissDecision()
        end

    end)

    Library:OnUnload(function()
        stopTriggerFire()
        resetMissDecision()
    end)
end

-- Auto-Shot module from New Text Document.lua (without hitbox/whitelist logic)
do
    local Players = game:GetService('Players')
    local Workspace = game:GetService('Workspace')
    local RunService = game:GetService('RunService')
    local UIS = game:GetService('UserInputService')
    local LocalPlayer = Players.LocalPlayer
    local VirtualInputManager = nil
    pcall(function() VirtualInputManager = game:GetService('VirtualInputManager') end)

    local ignoredContainer = Workspace:FindFirstChild('Ignored')
    local ignoredWatcherConnection = nil

    local isAutoShotRunning = false
    local autoShotTargetPlayerName = ''
    local runtimeConnections = {}
    local processingBulletRays = setmetatable({}, { __mode = 'k' })

    local function trackConnection(conn)
        if conn then
            table.insert(runtimeConnections, conn)
        end
        return conn
    end

    local function readToggle(id, fallback)
        local state = fallback == true
        pcall(function()
            if Toggles and Toggles[id] ~= nil then
                state = Toggles[id].Value == true
            end
        end)
        return state
    end

    local function readNumber(id, fallback)
        local value = fallback
        pcall(function()
            if Options and Options[id] and tonumber(Options[id].Value) ~= nil then
                value = tonumber(Options[id].Value)
            end
        end)
        return value
    end

    local function readString(id, fallback)
        local value = fallback
        pcall(function()
            if Options and Options[id] and type(Options[id].Value) == 'string' then
                value = Options[id].Value
            end
        end)
        return value
    end

    local function extractSelectedName(raw)
        if type(raw) == 'string' then
            return raw
        end
        if type(raw) ~= 'table' then
            return ''
        end
        if type(raw.Value) == 'string' then
            return raw.Value
        end
        if type(raw[1]) == 'string' then
            return raw[1]
        end
        for k, v in pairs(raw) do
            if type(k) == 'string' and v == true then
                return k
            end
            if type(v) == 'string' then
                return v
            end
        end
        return ''
    end

    local function syncAutoShotTargetFromOption()
        local resolved = ''
        pcall(function()
            if Options and Options.AutoShotTargetPlayer then
                resolved = extractSelectedName(Options.AutoShotTargetPlayer.Value)
            end
        end)
        autoShotTargetPlayerName = type(resolved) == 'string' and resolved or ''
    end

    local function setAutoShotTarget(name)
        local targetName = type(name) == 'string' and name or ''
        if autoShotTargetPlayerName == targetName then
            return
        end

        autoShotTargetPlayerName = targetName
        pcall(function()
            if Options and Options.AutoShotTargetPlayer and type(Options.AutoShotTargetPlayer.SetValue) == 'function' then
                Options.AutoShotTargetPlayer:SetValue(targetName)
            end
        end)
    end

    local function isAutoShotKeyActive()
        local isActive = false
        pcall(function()
            if not (Options and Options.AutoShotKey) then
                return
            end

            if type(Options.AutoShotKey.GetState) == 'function' then
                local okState, state = pcall(function()
                    return Options.AutoShotKey:GetState()
                end)
                if okState and state then
                    isActive = true
                    return
                end
            end

            local keyValue = Options.AutoShotKey.Value
            if type(keyValue) == 'table' then
                local mode = keyValue.Mode or keyValue[2]
                if type(mode) == 'string' and string.lower(mode) == 'always' then
                    isActive = true
                    return
                end
            end
            local lookup = keyValue
            if type(keyValue) == 'table' then
                lookup = keyValue.Key or keyValue[1]
            end

            local function isPressed(raw)
                if typeof(raw) == 'EnumItem' then
                    if raw.EnumType == Enum.KeyCode then
                        local okDown, down = pcall(function() return UIS:IsKeyDown(raw) end)
                        return okDown and down
                    end
                    if raw.EnumType == Enum.UserInputType then
                        local okMouse, down = pcall(function() return UIS:IsMouseButtonPressed(raw) end)
                        return okMouse and down
                    end
                    return false
                end

                if type(raw) == 'string' then
                    local keyCodeName = raw:match('^Enum%.KeyCode%.(.+)$')
                    local inputTypeName = raw:match('^Enum%.UserInputType%.(.+)$')
                    local keyName = keyCodeName or raw
                    if type(keyName) == 'string' and #keyName == 1 then
                        keyName = string.upper(keyName)
                    end
                    local keyCode = Enum.KeyCode[keyName]
                    if keyCode then
                        local okDown, down = pcall(function() return UIS:IsKeyDown(keyCode) end)
                        return okDown and down
                    end
                    local inputType = Enum.UserInputType[inputTypeName or raw]
                    if inputType then
                        local okMouse, down = pcall(function() return UIS:IsMouseButtonPressed(inputType) end)
                        return okMouse and down
                    end
                end

                return false
            end

            isActive = isPressed(lookup)
        end)
        return isActive
    end

    local function pickTargetUnderCursor()
        if not readToggle('AutoShotQuickSelectEnabled', true) then
            return false
        end
        if not LocalPlayer then
            return false
        end

        local mouse = LocalPlayer:GetMouse()
        if not mouse then
            return false
        end

        local target = nil
        pcall(function()
            target = mouse.Target
        end)
        if not target then
            return false
        end

        local model = target:FindFirstAncestorOfClass('Model')
        if not model then
            return false
        end

        local player = Players:GetPlayerFromCharacter(model)
        if player and player ~= LocalPlayer then
            setAutoShotTarget(player.Name)
            return true
        end

        return false
    end

    local function performMouseClick(holdTime)
        if type(mouse1click) == 'function' then
            pcall(function()
                mouse1click()
            end)
            return
        end

        if type(mouse1press) == 'function' and type(mouse1release) == 'function' then
            pcall(function()
                mouse1press()
                if holdTime and holdTime > 0 then
                    task.wait(holdTime)
                end
                mouse1release()
            end)
            return
        end

        if VirtualInputManager and type(VirtualInputManager.SendMouseButtonEvent) == 'function' then
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                if holdTime and holdTime > 0 then
                    task.wait(holdTime)
                end
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
        end
    end

    local function heartbeatWait(seconds)
        if not seconds or seconds <= 0 then
            return
        end
        local deadline = os.clock() + seconds
        while os.clock() < deadline do
            RunService.Heartbeat:Wait()
        end
    end

    local function handleAutoShot()
        syncAutoShotTargetFromOption()
        if autoShotTargetPlayerName == '' then
            return
        end
        if isAutoShotRunning then
            return
        end
        if not readToggle('AutoShotEnabled', true) then
            return
        end
        if not isAutoShotKeyActive() then
            return
        end

        isAutoShotRunning = true
        task.spawn(function()
            local minDelayMs = math.max(0, readNumber('AutoShotDelayMin', 130))
            local maxDelayMs = math.max(0, readNumber('AutoShotDelayMax', 200))
            if maxDelayMs < minDelayMs then
                minDelayMs, maxDelayMs = maxDelayMs, minDelayMs
            end

            local delayMs = minDelayMs
            if maxDelayMs > minDelayMs then
                delayMs = minDelayMs + math.random() * (maxDelayMs - minDelayMs)
            end
            if delayMs > 0 then
                heartbeatWait(delayMs / 1000)
            end

            if Library.Unloaded then
                isAutoShotRunning = false
                return
            end
            if not readToggle('AutoShotEnabled', true) then
                isAutoShotRunning = false
                return
            end
            if autoShotTargetPlayerName == '' then
                isAutoShotRunning = false
                return
            end
            if not isAutoShotKeyActive() then
                isAutoShotRunning = false
                return
            end

            local mode = string.upper(readString('AutoShotMode', 'BURST'))
            if mode == 'SINGLE' then
                performMouseClick(0.01)
            else
                while true do
                    if Library.Unloaded then
                        break
                    end
                    if not readToggle('AutoShotEnabled', true) then
                        break
                    end
                    if autoShotTargetPlayerName == '' then
                        break
                    end
                    if string.upper(readString('AutoShotMode', 'BURST')) ~= 'BURST' then
                        break
                    end
                    if not isAutoShotKeyActive() then
                        break
                    end
                    performMouseClick(0.001)
                    task.wait(0.01)
                end
            end

            isAutoShotRunning = false
        end)
    end

    if Options and Options.AutoShotTargetPlayer and type(Options.AutoShotTargetPlayer.OnChanged) == 'function' then
        pcall(function()
            Options.AutoShotTargetPlayer:OnChanged(function()
                syncAutoShotTargetFromOption()
            end)
        end)
    end
    syncAutoShotTargetFromOption()

    trackConnection(safeConnect(UIS.InputBegan, function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.KeyCode == Enum.KeyCode.LeftAlt then
            pickTargetUnderCursor()
        end
    end))

    trackConnection(safeConnect(Players.PlayerRemoving, function(player)
        if player and player.Name == autoShotTargetPlayerName then
            setAutoShotTarget('')
        end
    end))

    local watchedBulletRays = setmetatable({}, { __mode = 'k' })
    local queuedBulletRayChecks = setmetatable({}, { __mode = 'k' })
    local ownerAttributeKeys = { 'OwnerCharachter', 'OwnerCharacter', 'Owner', 'owner' }

    local function normalizeName(value)
        if value == nil then
            return ''
        end
        if type(value) ~= 'string' then
            value = tostring(value)
        end

        local normalized = string.lower(value)
        normalized = normalized:gsub('^@', '')
        normalized = normalized:gsub('%s+', '')
        normalized = normalized:gsub('%.character$', '')
        normalized = normalized:gsub('_character$', '')
        normalized = normalized:gsub('%-character$', '')
        return normalized
    end

    local function getTargetMatchSet()
        syncAutoShotTargetFromOption()
        local set = {}
        local normalizedTarget = normalizeName(autoShotTargetPlayerName)
        if normalizedTarget == '' then
            return set
        end

        set[normalizedTarget] = true
        for _, pl in ipairs(Players:GetPlayers()) do
            if normalizeName(pl.Name) == normalizedTarget or normalizeName(pl.DisplayName) == normalizedTarget then
                set[normalizeName(pl.Name)] = true
                set[normalizeName(pl.DisplayName)] = true
                break
            end
        end
        return set
    end

    local function isBulletRayInstance(instance)
        if not instance or typeof(instance) ~= 'Instance' then
            return false
        end
        local upperName = string.upper(instance.Name or '')
        return upperName == 'BULLET_RAYS' or string.find(upperName, 'BULLET_RAY', 1, true) ~= nil
    end

    local function ownerValueToName(value)
        if value == nil then
            return ''
        end
        if type(value) == 'string' then
            return value
        end
        if typeof(value) == 'Instance' then
            if value:IsA('Player') then
                return value.Name or ''
            end
            if value:IsA('Model') then
                local ownerPlayer = nil
                pcall(function()
                    ownerPlayer = Players:GetPlayerFromCharacter(value)
                end)
                if ownerPlayer and ownerPlayer.Name then
                    return ownerPlayer.Name
                end
            end
            return value.Name or ''
        end
        return tostring(value)
    end

    local function readOwnerCharacter(instance)
        if not instance or typeof(instance) ~= 'Instance' then
            return ''
        end

        local current = instance
        for _ = 1, 14 do
            if not current or typeof(current) ~= 'Instance' then
                break
            end

            for _, key in ipairs(ownerAttributeKeys) do
                local value = nil
                pcall(function()
                    value = current:GetAttribute(key)
                end)
                local ownerName = ownerValueToName(value)
                if ownerName ~= '' then
                    return ownerName
                end
            end

            if current == ignoredContainer or current == Workspace then
                break
            end
            current = current.Parent
        end

        return ''
    end

    local function ownerMatchesTarget(ownerNormalized, targetSet)
        if ownerNormalized == '' then
            return false
        end
        if targetSet[ownerNormalized] then
            return true
        end

        for targetName in pairs(targetSet) do
            if targetName ~= '' then
                if string.find(ownerNormalized, targetName, 1, true) ~= nil then
                    return true
                end
                if string.find(targetName, ownerNormalized, 1, true) ~= nil then
                    return true
                end
            end
        end

        return false
    end

    local processBulletRay

    local function queueBulletRayCheck(instance)
        if not instance or typeof(instance) ~= 'Instance' then
            return
        end
        if queuedBulletRayChecks[instance] then
            return
        end

        queuedBulletRayChecks[instance] = true
        task.defer(function()
            queuedBulletRayChecks[instance] = nil
            processBulletRay(instance)
        end)
    end

    local function watchBulletRay(instance)
        if not isBulletRayInstance(instance) then
            return
        end
        if watchedBulletRays[instance] then
            return
        end

        watchedBulletRays[instance] = true
        for _, key in ipairs(ownerAttributeKeys) do
            local signal = nil
            local okSignal = pcall(function()
                signal = instance:GetAttributeChangedSignal(key)
            end)
            if okSignal and signal then
                trackConnection(safeConnect(signal, function()
                    queueBulletRayCheck(instance)
                end))
            end
        end

        trackConnection(safeConnect(instance.AncestryChanged, function(_, parent)
            if not parent then
                watchedBulletRays[instance] = nil
                queuedBulletRayChecks[instance] = nil
                processingBulletRays[instance] = nil
            end
        end))

        queueBulletRayCheck(instance)
    end

    processBulletRay = function(instance)
        if not isBulletRayInstance(instance) then
            return
        end
        if Library.Unloaded then
            return
        end
        if not readToggle('AutoShotEnabled', true) then
            return
        end
        if processingBulletRays[instance] then
            return
        end

        local targetSet = getTargetMatchSet()
        if next(targetSet) == nil then
            return
        end

        processingBulletRays[instance] = true
        task.spawn(function()
            local owner = ''
            for _ = 1, 60 do
                owner = readOwnerCharacter(instance)
                if owner ~= '' then
                    break
                end
                task.wait(0.01)
            end

            local ownerNormalized = normalizeName(owner)
            if ownerMatchesTarget(ownerNormalized, targetSet) then
                handleAutoShot()
            end

            processingBulletRays[instance] = nil
        end)
    end

    local function attachIgnoredWatcher(container)
        if ignoredWatcherConnection then
            pcall(function()
                ignoredWatcherConnection:Disconnect()
            end)
            ignoredWatcherConnection = nil
        end

        ignoredContainer = container
        if not ignoredContainer or typeof(ignoredContainer) ~= 'Instance' then
            return
        end

        ignoredWatcherConnection = trackConnection(safeConnect(ignoredContainer.DescendantAdded, function(desc)
            watchBulletRay(desc)
        end))

        pcall(function()
            if isBulletRayInstance(ignoredContainer) then
                watchBulletRay(ignoredContainer)
            end
            for _, desc in ipairs(ignoredContainer:GetDescendants()) do
                watchBulletRay(desc)
            end
        end)
    end

    attachIgnoredWatcher(ignoredContainer)

    trackConnection(safeConnect(Workspace.ChildAdded, function(child)
        if child and child.Name == 'Ignored' then
            attachIgnoredWatcher(child)
        end
    end))

    trackConnection(safeConnect(Workspace.ChildRemoved, function(child)
        if child and ignoredContainer and child == ignoredContainer then
            attachIgnoredWatcher(nil)
        end
    end))

    -- DescendantAdded already watches new rays. Full GetDescendants every 50ms was a
    -- major FPS killer. Keep a rare safety scan only while Auto-Shot is armed.
    local lastIgnoredScan = 0
    trackConnection(safeConnect(RunService.Heartbeat, function()
        if not ignoredContainer or Library.Unloaded then
            return
        end
        if not readToggle('AutoShotEnabled', true) then
            return
        end
        if autoShotTargetPlayerName == nil or autoShotTargetPlayerName == '' then
            return
        end

        local now = os.clock()
        if (now - lastIgnoredScan) < 1.0 then
            return
        end
        lastIgnoredScan = now

        pcall(function()
            for _, desc in ipairs(ignoredContainer:GetDescendants()) do
                if isBulletRayInstance(desc) then
                    watchBulletRay(desc)
                end
            end
        end)
    end))

    Library:OnUnload(function()
        for _, conn in ipairs(runtimeConnections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        runtimeConnections = {}
        isAutoShotRunning = false
    end)
end

-- Inventory sorter: reorder backpack tools by 9 configured slots
do
    local Players = game:GetService('Players')
    local UIS = game:GetService('UserInputService')
    local RunService = game:GetService('RunService')

    local function readInventoryToggle(id, defaultValue)
        local value = defaultValue == true
        pcall(function()
            if Toggles and Toggles[id] then
                value = Toggles[id].Value == true
            end
        end)
        return value == true
    end

    local function readInventorySlot(index)
        local text = ''
        pcall(function()
            if Options and Options['InventorySlot' .. index] then
                text = Options['InventorySlot' .. index].Value
            end
        end)
        if text == nil then
            text = ''
        end
        if type(text) ~= 'string' then
            text = tostring(text)
        end
        text = text:match('^%s*(.-)%s*$')
        return string.lower(text)
    end

    local function isSortKeyActive()
        local keyOpt = Options and Options.InventoryAutoSortKey or nil
        if not keyOpt then
            return false
        end

        if type(keyOpt.GetState) == 'function' then
            local okState, state = pcall(function()
                return keyOpt:GetState()
            end)
            if okState then
                return state == true
            end
        end

        local keyValue = nil
        pcall(function()
            keyValue = keyOpt.Value
        end)
        if type(keyValue) == 'table' then
            keyValue = keyValue.Key or keyValue[1]
        end

        if typeof(keyValue) == 'EnumItem' then
            if keyValue.EnumType == Enum.KeyCode then
                local okDown, down = pcall(function()
                    return UIS:IsKeyDown(keyValue)
                end)
                return okDown and down
            end
            if keyValue.EnumType == Enum.UserInputType then
                local okDown, down = pcall(function()
                    return UIS:IsMouseButtonPressed(keyValue)
                end)
                return okDown and down
            end
        end

        if type(keyValue) == 'string' then
            local asKeyCode = Enum.KeyCode[keyValue]
            if asKeyCode then
                local okDown, down = pcall(function()
                    return UIS:IsKeyDown(asKeyCode)
                end)
                if okDown and down then
                    return true
                end
            end

            local asInputType = Enum.UserInputType[keyValue]
            if asInputType then
                local okDown, down = pcall(function()
                    return UIS:IsMouseButtonPressed(asInputType)
                end)
                if okDown and down then
                    return true
                end
            end

            if #keyValue == 1 then
                local upper = string.upper(keyValue)
                local keyEnum = Enum.KeyCode[upper]
                if keyEnum then
                    local okDown, down = pcall(function()
                        return UIS:IsKeyDown(keyEnum)
                    end)
                    if okDown and down then
                        return true
                    end
                end
            end
        end

        return false
    end

    local function runInventorySort()
        local localPlayer = Players.LocalPlayer
        if not localPlayer then
            return
        end

        local backpack = localPlayer:FindFirstChild('Backpack')
        if not backpack then
            return
        end

        local sortSlots = {}
        for i = 1, 9 do
            sortSlots[i] = readInventorySlot(i)
        end

        local children = {}
        local function collectTools(container)
            if not container then
                return
            end
            for _, child in ipairs(container:GetChildren()) do
                if child and child:IsA('Tool') then
                    table.insert(children, child)
                end
            end
        end
        collectTools(backpack)
        collectTools(localPlayer.Character)

        if #children == 0 then
            return
        end

        local sorted = {}

        for i = 1, #children do
            local child = children[i]
            if child and child:IsA('Tool') then
                pcall(function()
                    child.Parent = localPlayer
                end)
            end
        end

        for slot = 1, 9 do
            local matcher = sortSlots[slot]
            if matcher and matcher ~= '' then
                for i = 1, #children do
                    local child = children[i]
                    if child and child:IsA('Tool') and not sorted[child] then
                        local lowerName = string.lower(tostring(child.Name or child))
                        if lowerName == matcher then
                            pcall(function()
                                child.Parent = backpack
                            end)
                            sorted[child] = true
                        end
                    end
                end
            end
        end

        for i = 1, #children do
            local child = children[i]
            if child and child:IsA('Tool') and not sorted[child] then
                pcall(function()
                    child.Parent = backpack
                end)
            end
        end
    end

    local function shouldAutoSortOnSpawn()
        return readInventoryToggle('InventoryAutoSortEnabled', false)
            and readInventoryToggle('InventoryAutoSortOnSpawn', true)
    end

    local spawnSortWindowEndsAt = 0
    local spawnSortDebounceToken = 0
    local backpackWatcher = nil
    local backpackOwnerWatcher = nil

    local function disconnectConnection(conn)
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
    end

    local function requestSpawnAutoSort(delaySeconds)
        spawnSortDebounceToken = spawnSortDebounceToken + 1
        local token = spawnSortDebounceToken
        local delayValue = tonumber(delaySeconds) or 0.15

        task.delay(delayValue, function()
            if Library.Unloaded then
                return
            end
            if token ~= spawnSortDebounceToken then
                return
            end
            if os.clock() > spawnSortWindowEndsAt then
                return
            end
            if not shouldAutoSortOnSpawn() then
                return
            end
            safeSpawn(runInventorySort)
        end)
    end

    local function beginSpawnSortWindow()
        if not shouldAutoSortOnSpawn() then
            return
        end

        spawnSortWindowEndsAt = os.clock() + 8
        requestSpawnAutoSort(0.25)

        task.delay(0.9, function()
            if Library.Unloaded then
                return
            end
            if os.clock() <= spawnSortWindowEndsAt and shouldAutoSortOnSpawn() then
                safeSpawn(runInventorySort)
            end
        end)

        task.delay(1.8, function()
            if Library.Unloaded then
                return
            end
            if os.clock() <= spawnSortWindowEndsAt and shouldAutoSortOnSpawn() then
                safeSpawn(runInventorySort)
            end
        end)
    end

    local function attachBackpackWatcher(backpack)
        disconnectConnection(backpackWatcher)
        backpackWatcher = nil

        if not backpack or not backpack:IsA('Backpack') then
            return
        end

        backpackWatcher = safeConnect(backpack.ChildAdded, function(child)
            if Library.Unloaded then
                return
            end
            if not child or not child:IsA('Tool') then
                return
            end
            if os.clock() <= spawnSortWindowEndsAt then
                requestSpawnAutoSort(0.18)
            end
        end)
    end

    local lastKeyState = false
    safeConnect(RunService.Heartbeat, function()
        if Library.Unloaded then
            return
        end

        if not readInventoryToggle('InventoryAutoSortEnabled', false) then
            lastKeyState = false
            return
        end

        local keyState = isSortKeyActive()
        if keyState and not lastKeyState then
            safeSpawn(runInventorySort)
        end
        lastKeyState = keyState
    end)

    local localPlayer = Players.LocalPlayer
    if localPlayer then
        attachBackpackWatcher(localPlayer:FindFirstChild('Backpack'))
        backpackOwnerWatcher = safeConnect(localPlayer.ChildAdded, function(child)
            if child and child:IsA('Backpack') then
                attachBackpackWatcher(child)
            end
        end)

        safeConnect(localPlayer.CharacterAdded, function()
            beginSpawnSortWindow()
        end)

        if localPlayer.Character then
            beginSpawnSortWindow()
        end

        pcall(function()
            if Toggles and Toggles.InventoryAutoSortEnabled and type(Toggles.InventoryAutoSortEnabled.OnChanged) == 'function' then
                Toggles.InventoryAutoSortEnabled:OnChanged(function()
                    if localPlayer.Character and shouldAutoSortOnSpawn() then
                        beginSpawnSortWindow()
                    end
                end)
            end
        end)

        pcall(function()
            if Toggles and Toggles.InventoryAutoSortOnSpawn and type(Toggles.InventoryAutoSortOnSpawn.OnChanged) == 'function' then
                Toggles.InventoryAutoSortOnSpawn:OnChanged(function()
                    if localPlayer.Character and shouldAutoSortOnSpawn() then
                        beginSpawnSortWindow()
                    end
                end)
            end
        end)
    end

    Library:OnUnload(function()
        disconnectConnection(backpackWatcher)
        disconnectConnection(backpackOwnerWatcher)
        backpackWatcher = nil
        backpackOwnerWatcher = nil
    end)
end

-- Insta Macro group: keybind that presses the game's "Get Sturdy 2" control and briefly equips [Knife]
local RightGroupbox = Tabs.Main:AddRightGroupbox('Insta Macro')
RightGroupbox:AddLabel('Insta Macro Key'):AddKeyPicker('InstaMacroKey', { Default = 'Insert', NoUI = false, Text = 'Insta Macro' })

-- Bind the keypicker to an action: when pressed, trigger the game's control at
-- Players.LocalPlayer.DataFolder.Information["Get Sturdy 2"].Value and briefly equip [Knife]
do
    local Players = game:GetService('Players')
    local UIS = game:GetService('UserInputService')
    local LocalPlayer = Players.LocalPlayer

    -- virtual input manager for simulating key presses (if available)
    local VirtualInputManager = nil
    pcall(function() VirtualInputManager = game:GetService('VirtualInputManager') end)

    local function findGetSturdyTarget()
        if not LocalPlayer then return nil end
        local ok, dataFolder = pcall(function() return LocalPlayer:FindFirstChild('DataFolder') end)
        if not ok or not dataFolder then return nil end
        local info = dataFolder:FindFirstChild('Information')
        if not info then return nil end
        local node = info:FindFirstChild('Get Sturdy 2')
        if not node then return nil end
        -- the Value stores the key name (single letter) to press
        return node.Value
    end

    local function findKnifeTool()
        if not LocalPlayer then return nil end
        local function search(container)
            for _, v in ipairs(container:GetChildren()) do
                if v:IsA('Tool') and v.Name == '[Knife]' then return v end
            end
            return nil
        end
        -- search character then backpack
        if LocalPlayer.Character then
            local t = search(LocalPlayer.Character)
            if t then return t end
        end
        local backpack = LocalPlayer:FindFirstChild('Backpack')
        if backpack then
            local t = search(backpack)
            if t then return t end
        end
        return nil
    end

    local function instaMacroAction()
        pcall(function()
            local keyToPress = findGetSturdyTarget()
            if keyToPress and type(keyToPress) == 'string' then
                -- try to simulate the key press via VirtualInputManager if present
                if VirtualInputManager and type(VirtualInputManager.SendKeyEvent) == 'function' then
                    pcall(function()
                        VirtualInputManager:SendKeyEvent(true, tostring(keyToPress), false, game)
                        task.wait(0.1)
                        VirtualInputManager:SendKeyEvent(false, tostring(keyToPress), false, game)
                    end)
                else
                    -- VirtualInputManager not available; silent
                end
            end

            -- equip knife briefly
            local hum = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
            if not hum then return end
            local prev = hum and LocalPlayer.Character:FindFirstChildOfClass('Tool')
            local knife = findKnifeTool()
            if not knife then return end

            -- equip
            pcall(function() hum:EquipTool(knife) end)
            -- wait 100 ms for the equip/action to register
            task.wait(0.1)
            -- restore previous tool or move knife back to backpack
            if prev and prev.Parent == LocalPlayer.Character and prev ~= knife then
                pcall(function() hum:EquipTool(prev) end)
            else
                local backpack = LocalPlayer:FindFirstChild('Backpack')
                if backpack then pcall(function() knife.Parent = backpack end) end
            end
        end)
    end

    -- input handler wired to the keypicker value
safeConnect(UIS.InputBegan, function(input, gameProcessed)
        if gameProcessed then return end
        if not Options or not Options.InstaMacroKey then return end
        local val = Options.InstaMacroKey.Value
        if not val then return end
        -- val may be an EnumItem (KeyCode or UserInputType) or string name
        local matched = false
        pcall(function()
            if typeof(val) == 'EnumItem' then
                -- prefer numeric value compare (some executors expose side buttons as KeyCode or UserInputType with numeric values)
                local ok, vval = pcall(function() return val.Value end)
                local ik = (input.KeyCode and input.KeyCode.Value) or nil
                local iu = (input.UserInputType and input.UserInputType.Value) or nil
                if ok and vval then
                    if ik and vval == ik then matched = true end
                    if iu and vval == iu then matched = true end
                end

                -- fallback to direct EnumItem equality if the above didn't match
                if not matched then
                    if val.EnumType == Enum.KeyCode then
                        matched = (val == input.KeyCode)
                    elseif val.EnumType == Enum.UserInputType then
                        matched = (val == input.UserInputType)
                    else
                        matched = (tostring(val) == tostring(input.KeyCode)) or (tostring(val) == tostring(input.UserInputType))
                    end
                end
            elseif type(val) == 'string' then
                -- compare to KeyCode name or UserInputType name
                local keyName = nil
                if input.KeyCode and input.KeyCode.Name then keyName = input.KeyCode.Name end
                local uitName = input.UserInputType and input.UserInputType.Name or nil
                matched = (val == keyName) or (val == uitName)
            end
        end)
        if matched then
            instaMacroAction()
        end
    end)
end

-- Keep the keybinds display window visible by default so users can toggle it on.
local function setKeybindFrameVisibleSafe(visible)
    if not Library then
        return false
    end

    local frame = nil
    local okGet = pcall(function()
        frame = Library.KeybindFrame
    end)
    if not okGet or frame == nil then
        return false
    end

    local state = visible and true or false
    local frameType = typeof(frame)

    if frameType == "Instance" then
        return pcall(function()
            frame.Visible = state
        end)
    end

    if type(frame) == "table" then
        local changed = false
        local okVisible = pcall(function()
            frame.Visible = state
        end)
        if okVisible then
            changed = true
        end
        if typeof(frame.Frame) == "Instance" then
            local ok = pcall(function() frame.Frame.Visible = state end)
            changed = changed or ok
        end
        if typeof(frame.Object) == "Instance" then
            local ok = pcall(function() frame.Object.Visible = state end)
            changed = changed or ok
        end
        if typeof(frame.Main) == "Instance" then
            local ok = pcall(function() frame.Main.Visible = state end)
            changed = changed or ok
        end
        if changed then
            return true
        end
    end

    return false
end

setKeybindFrameVisibleSafe(true)

Library:OnUnload(function()
    -- unloaded
    Library.Unloaded = true
end)

-- UI Settings
local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')

-- Visuals tab: ESP from AyuGram source, adapted for this script/Xeno.
do
    local VisualsTab = Tabs.Visuals
    if VisualsTab then
        local Left = VisualsTab:AddLeftGroupbox('ESP')
        Left:AddToggle('ESPEnabled', { Text = 'Enable ESP', Default = false })
        Left:AddToggle('ESPRainbow', { Text = 'Rainbow ESP', Default = false })
        Left:AddToggle('ESPFading', { Text = 'Fading ESP', Default = false })
        Left:AddToggle('ESPNames', { Text = 'Names', Default = true })
        Left:AddToggle('ESPChams', { Text = 'Chams', Default = false })
        Left:AddToggle('ESPTracers', { Text = 'Tracers', Default = false })
        Left:AddToggle('ESPBoxes', { Text = 'Box', Default = true })
        Left:AddToggle('ESPHealthBar', { Text = 'Health Bar', Default = true })
        Left:AddToggle('ESPTool', { Text = 'Tool', Default = false })
        Left:AddToggle('ESPDirection', { Text = 'Direction Arrow', Default = false })

        Left:AddLabel('Name Color'):AddColorPicker('ESPNameColor', { Default = Color3.fromRGB(255, 255, 255), Title = 'Name Color' })
        Left:AddLabel('Chams Color'):AddColorPicker('ESPChamsColor', { Default = Color3.fromRGB(255, 255, 255), Title = 'Chams Color' })
        Left:AddLabel('Tracer Color'):AddColorPicker('ESPTracerColor', { Default = Color3.fromRGB(255, 255, 255), Title = 'Tracer Color' })
        Left:AddLabel('Box Color'):AddColorPicker('ESPBoxColor', { Default = Color3.fromRGB(255, 255, 255), Title = 'Box Color' })
        Left:AddLabel('Box Outline Color'):AddColorPicker('ESPBoxOutlineColor', { Default = Color3.fromRGB(255, 255, 255), Title = 'Box Outline Color' })
        Left:AddLabel('Health Color'):AddColorPicker('ESPHPColor', { Default = Color3.fromRGB(0, 255, 0), Title = 'Health Color' })
        Left:AddLabel('Tool Color'):AddColorPicker('ESPToolColor', { Default = Color3.fromRGB(255, 200, 0), Title = 'Tool Color' })
        Left:AddLabel('Direction Color'):AddColorPicker('ESPDirectionColor', { Default = Color3.fromRGB(255, 0, 0), Title = 'Direction Color' })

        safeSpawn(function()
            local Players = game:GetService('Players')
            local RunService = game:GetService('RunService')
            local Camera = workspace.CurrentCamera
            local LocalPlayer = Players.LocalPlayer

            local espObjects = {} -- userId -> objects
            local espConnections = {}

            local function clearLegacyESPGui()
                local parent = (gethui and gethui()) or game:GetService('CoreGui')
                for _, child in ipairs(parent:GetChildren()) do
                    local name = tostring(child.Name or '')
                    if name:sub(1, 8) == 'ESP_GUI_'
                        or name:sub(1, 8) == 'RoleESP_'
                        or name:sub(1, 11) == 'VisOverlay_'
                        or name:sub(1, 10) == 'RoleVis_' then
                        pcall(function()
                            child:Destroy()
                        end)
                    end
                end
            end

            clearLegacyESPGui()

            local function trackConn(conn)
                if conn then
                    table.insert(espConnections, conn)
                end
                return conn
            end

            local function canUseDrawingObject(obj)
                if obj == nil or type(obj) == 'number' then
                    return false
                end
                return pcall(function()
                    local _ = obj.Visible
                end)
            end

            local function safeSetVisible(obj, state)
                if not canUseDrawingObject(obj) then
                    return
                end
                pcall(function()
                    obj.Visible = state and true or false
                end)
            end

            local function getOptColor(id, fallback)
                local c = fallback
                pcall(function()
                    if Options and Options[id] and typeof(Options[id].Value) == 'Color3' then
                        c = Options[id].Value
                    end
                end)
                return c
            end

            local function getToggle(id, fallback)
                local v = fallback
                pcall(function()
                    if Toggles and Toggles[id] then
                        v = Toggles[id].Value == true
                    end
                end)
                return v == true
            end

            local function color3ToHex(color)
                local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
                local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
                local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
                return string.format('#%02X%02X%02X', r, g, b)
            end

            local function getRainbowColor(offset)
                local h = ((tick() * 0.18) + (offset or 0)) % 1
                return Color3.fromHSV(h, 1, 1)
            end

            local function getFadingAlpha()
                return (math.sin(tick() * 2) + 1) / 2
            end

            local function getPlayerToolName(player)
                if not player or not player.Character then
                    return ''
                end
                local tool = player.Character:FindFirstChildOfClass('Tool')
                return tool and tool.Name or ''
            end

            local function computeOffscreenArrow(worldPos)
                local cam = workspace.CurrentCamera
                if not cam then
                    return nil, true
                end
                local pos, visible = cam:WorldToViewportPoint(worldPos)
                if visible then
                    return nil, true
                end
                local center = cam.ViewportSize / 2
                local dir = (Vector2.new(pos.X, pos.Y) - center).Unit
                local angle = math.atan2(dir.Y, dir.X)
                local tip = center + Vector2.new(math.cos(angle), math.sin(angle)) * (center.Magnitude - 40)
                local perp = Vector2.new(-math.sin(angle), math.cos(angle)) * 12
                local left = tip - dir * 18 + perp
                local right = tip - dir * 18 - perp
                return { tip, left, right }, false
            end

            local function applyEffects(element)
                local keyToOption = {
                    Names = 'ESPNameColor',
                                        Chams = 'ESPChamsColor',
                    Tracers = 'ESPTracerColor',
                    Box = 'ESPBoxColor',
                    HealthBar = 'ESPHPColor',
                    Tool = 'ESPToolColor',
                    Direction = 'ESPDirectionColor',
                }
                local fallback = Color3.fromRGB(255, 255, 255)
                if element == 'HealthBar' then
                    fallback = Color3.fromRGB(0, 255, 0)
                elseif element == 'Tool' then
                    fallback = Color3.fromRGB(255, 200, 0)
                elseif element == 'Direction' then
                    fallback = Color3.fromRGB(255, 0, 0)
                end
                local color = getOptColor(keyToOption[element], fallback)
                if getToggle('ESPRainbow', false) then
                    color = getRainbowColor()
                end
                local alpha = 1
                if getToggle('ESPFading', false) then
                    alpha = getFadingAlpha()
                end
                return color, alpha
            end

            local function clearESPForPlayer(player)
                if not player then
                    return
                end
                local objs = espObjects[player.UserId]
                if not objs then
                    return
                end
                pcall(function() if objs.LabelGui then objs.LabelGui:Destroy() end end)
                pcall(function() if objs.ChamFill and objs.ChamFill.Remove then objs.ChamFill.Visible = false; objs.ChamFill:Remove() end end)
                pcall(function() if objs.TracerLine and objs.TracerLine.Remove then objs.TracerLine.Visible = false; objs.TracerLine:Remove() end end)
                pcall(function() if objs.Box and objs.Box.Remove then objs.Box:Remove() end end)
                pcall(function() if objs.BoxOutline and objs.BoxOutline.Remove then objs.BoxOutline:Remove() end end)
                pcall(function() if objs.HealthBar and objs.HealthBar.Remove then objs.HealthBar:Remove() end end)
                pcall(function() if objs.HealthBarOutline and objs.HealthBarOutline.Remove then objs.HealthBarOutline:Remove() end end)
                if objs.DirectionLines then
                    for _, ln in ipairs(objs.DirectionLines) do
                        pcall(function()
                            if ln and ln.Remove then
                                ln.Visible = false
                                ln:Remove()
                            end
                        end)
                    end
                end
                -- Scrub leftover UKUSSIA/ExamsAC Highlight fingerprint from older sessions.
                pcall(function()
                    local char = player.Character
                    if char then
                        local old = char:FindFirstChild('ESP_Chams')
                        if old then
                            old:Destroy()
                        end
                        for _, ch in ipairs(char:GetChildren()) do
                            if ch:IsA('Highlight') then
                                ch:Destroy()
                            end
                        end
                    end
                end)
                espObjects[player.UserId] = nil
            end

            local function clearAllESP()
                for _, pl in ipairs(Players:GetPlayers()) do
                    clearESPForPlayer(pl)
                end
            end

            local function createBoxObjects(userId)
                local objects = espObjects[userId]
                if not objects then
                    return
                end
                local outline = Drawing.new('Square')
                outline.Visible = false
                outline.Color = getOptColor('ESPBoxOutlineColor', Color3.fromRGB(255, 255, 255))
                outline.Thickness = 2
                outline.Filled = false
                outline.Transparency = 1

                local box = Drawing.new('Square')
                box.Visible = false
                box.Color = getOptColor('ESPBoxColor', Color3.fromRGB(255, 255, 255))
                box.Thickness = 1
                box.Filled = false
                box.Transparency = 1

                local hbOutline = Drawing.new('Square')
                hbOutline.Visible = false
                hbOutline.Color = Color3.new(0, 0, 0)
                hbOutline.Thickness = 2
                hbOutline.Filled = false
                hbOutline.Transparency = 1

                local hb = Drawing.new('Square')
                hb.Visible = false
                hb.Color = getOptColor('ESPHPColor', Color3.fromRGB(0, 255, 0))
                hb.Thickness = 1
                hb.Filled = true
                hb.Transparency = 1

                local chamFill = Drawing.new('Square')
                chamFill.Visible = false
                chamFill.Color = getOptColor('ESPChamsColor', Color3.fromRGB(255, 255, 255))
                chamFill.Thickness = 1
                chamFill.Filled = true
                chamFill.Transparency = 0.45

                objects.BoxOutline = outline
                objects.Box = box
                objects.HealthBarOutline = hbOutline
                objects.HealthBar = hb
                objects.ChamFill = chamFill
            end

            -- No Instance Highlight / ESP_Chams (UKUSSIA fingerprint / ExamsAC). Drawing fill only.
            local function applyChams(player)
                local objs = player and espObjects[player.UserId]
                if not objs then
                    return
                end
                pcall(function()
                    local char = player.Character
                    if not char then
                        return
                    end
                    local old = char:FindFirstChild('ESP_Chams')
                    if old then
                        old:Destroy()
                    end
                    for _, ch in ipairs(char:GetChildren()) do
                        if ch:IsA('Highlight') then
                            ch:Destroy()
                        end
                    end
                end)
                if not objs.ChamFill then
                    local chamFill = Drawing.new('Square')
                    chamFill.Visible = false
                    chamFill.Filled = true
                    chamFill.Thickness = 1
                    chamFill.Transparency = 0.45
                    objs.ChamFill = chamFill
                end
            end

            local function createESPForPlayer(player)
                if not player or player == LocalPlayer then
                    return
                end
                clearESPForPlayer(player)
                espObjects[player.UserId] = {}

                local parent = (gethui and gethui()) or game:GetService('CoreGui')
                local screenGui = Instance.new('ScreenGui')
                screenGui.Name = 'VisOverlay_' .. player.Name
                screenGui.IgnoreGuiInset = true
                screenGui.ResetOnSpawn = false
                screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
                screenGui.DisplayOrder = 2000
                screenGui.Parent = parent

                local label = Instance.new('TextLabel')
                label.Size = UDim2.new(0, 170, 0, 54)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.Code
                label.TextSize = 14
                label.TextColor3 = Color3.new(1, 1, 1)
                label.TextStrokeTransparency = 0
                label.TextStrokeColor3 = Color3.new(0, 0, 0)
                label.TextXAlignment = Enum.TextXAlignment.Center
                label.TextYAlignment = Enum.TextYAlignment.Top
                label.RichText = true
                label.Text = ''
                label.Visible = false
                label.Parent = screenGui

                local toolLabel = Instance.new('TextLabel')
                toolLabel.Size = UDim2.new(0, 170, 0, 18)
                toolLabel.Position = UDim2.new(0, 0, 0, 36)
                toolLabel.BackgroundTransparency = 1
                toolLabel.Font = Enum.Font.Code
                toolLabel.TextSize = 14
                toolLabel.TextColor3 = getOptColor('ESPToolColor', Color3.fromRGB(255, 200, 0))
                toolLabel.TextStrokeTransparency = 0
                toolLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                toolLabel.TextXAlignment = Enum.TextXAlignment.Center
                toolLabel.TextYAlignment = Enum.TextYAlignment.Top
                toolLabel.RichText = true
                toolLabel.Text = ''
                toolLabel.Visible = false
                toolLabel.Parent = screenGui

                local dirLines = {}
                for _ = 1, 3 do
                    local ln = Drawing.new('Line')
                    ln.Visible = false
                    ln.Thickness = 2
                    ln.Transparency = 1
                    ln.Color = getOptColor('ESPDirectionColor', Color3.fromRGB(255, 0, 0))
                    table.insert(dirLines, ln)
                end

                local tracer = Drawing.new('Line')
                tracer.Visible = false
                tracer.Thickness = 1.5
                tracer.Transparency = 1
                tracer.Color = getOptColor('ESPTracerColor', Color3.fromRGB(255, 255, 255))

                espObjects[player.UserId].LabelGui = screenGui
                espObjects[player.UserId].Label = label
                espObjects[player.UserId].ToolLabel = toolLabel
                espObjects[player.UserId].DirectionLines = dirLines
                espObjects[player.UserId].TracerLine = tracer

                createBoxObjects(player.UserId)
                if getToggle('ESPChams', false) then
                    applyChams(player)
                end
            end

            local function updateESPForPlayer(player)
                local objs = espObjects[player.UserId]
                if not objs then
                    return
                end

                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass('Humanoid')
                local rootPart = character and (character:FindFirstChild('UpperTorso') or character:FindFirstChild('HumanoidRootPart'))
                local head = character and character:FindFirstChild('Head')

                if not Camera then
                    Camera = workspace.CurrentCamera
                end
                if not Camera or not rootPart then
                    if objs.Label then objs.Label.Visible = false end
                    if objs.ToolLabel then objs.ToolLabel.Visible = false end
                    if objs.TracerLine then objs.TracerLine.Visible = false end
                    if objs.ChamFill then objs.ChamFill.Visible = false end
                    if objs.Box then objs.Box.Visible = false end
                    if objs.BoxOutline then objs.BoxOutline.Visible = false end
                    if objs.HealthBar then objs.HealthBar.Visible = false end
                    if objs.HealthBarOutline then objs.HealthBarOutline.Visible = false end
                    if objs.DirectionLines then for _, ln in ipairs(objs.DirectionLines) do ln.Visible = false end end
                    return
                end

                local boxScreenPos, boxOnScreen = Camera:WorldToViewportPoint(rootPart.Position)
                local nameScreenPos, nameOnScreen = Camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2.5, 0))
                local distance = (Camera.CFrame.Position - rootPart.Position).Magnitude

                local showNames = getToggle('ESPNames', true)
                if getToggle('ESPDistance', false) then
                local info = ''

                if showNames then
                    local c, a = applyEffects('Names')
                    objs.Label.TextColor3 = c
                    objs.Label.TextTransparency = 1 - a
                    info = info .. string.format('<font color="%s">%s</font>\n', color3ToHex(c), (player.DisplayName or player.Name))
                end
                end

                if objs.Label then
                    if nameOnScreen and info ~= '' then
                        objs.Label.Text = info
                        objs.Label.Position = UDim2.new(0, nameScreenPos.X - 85, 0, nameScreenPos.Y - 30)
                        objs.Label.Visible = true
                    else
                        objs.Label.Visible = false
                    end
                end

                local showBox = getToggle('ESPBoxes', true)
                local showHealthBar = getToggle('ESPHealthBar', true)
                local showChams = getToggle('ESPChams', false)
                if head and (showBox or showHealthBar or showChams) and boxOnScreen then
                    local headPos = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local rootPos = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
                    local boxHeight = math.abs(headPos.Y - rootPos.Y)
                    if boxHeight < 10 then boxHeight = 10 end
                    local boxWidth = boxHeight / 2
                    local boxX = headPos.X - boxWidth / 2
                    local boxY = headPos.Y - boxHeight * 0.1

                    local boxColor, boxAlpha = applyEffects('Box')
                    objs.Box.Size = Vector2.new(boxWidth, boxHeight)
                    objs.Box.Position = Vector2.new(boxX, boxY)
                    objs.Box.Color = boxColor
                    objs.Box.Transparency = boxAlpha
                    objs.Box.Visible = showBox

                    objs.BoxOutline.Size = objs.Box.Size
                    objs.BoxOutline.Position = objs.Box.Position
                    objs.BoxOutline.Color = Color3.new(0, 0, 0)
                    objs.BoxOutline.Transparency = boxAlpha
                    objs.BoxOutline.Visible = showBox

                    if objs.ChamFill then
                        if showChams then
                            local chamColor, chamAlpha = applyEffects('Chams')
                            objs.ChamFill.Size = Vector2.new(boxWidth, boxHeight)
                            objs.ChamFill.Position = Vector2.new(boxX, boxY)
                            objs.ChamFill.Color = chamColor
                            objs.ChamFill.Transparency = math.clamp((chamAlpha or 1) * 0.45, 0.2, 0.55)
                            objs.ChamFill.Visible = true
                        else
                            objs.ChamFill.Visible = false
                        end
                    end

                    if showHealthBar and humanoid then
                        local maxHp = (humanoid.MaxHealth and humanoid.MaxHealth > 0) and humanoid.MaxHealth or 1
                        local hpRatio = math.clamp(humanoid.Health / maxHp, 0, 1)
                        local hbHeight = boxHeight * hpRatio
                        local hbColor, hbAlpha = applyEffects('HealthBar')
                        objs.HealthBar.Size = Vector2.new(2, hbHeight)
                        objs.HealthBar.Position = Vector2.new(boxX - 5, boxY + (boxHeight - hbHeight))
                        objs.HealthBar.Color = hbColor
                        objs.HealthBar.Transparency = hbAlpha
                        objs.HealthBar.Visible = true

                        objs.HealthBarOutline.Size = Vector2.new(2, boxHeight)
                        objs.HealthBarOutline.Position = Vector2.new(boxX - 5, boxY)
                        objs.HealthBarOutline.Color = Color3.new(0, 0, 0)
                        objs.HealthBarOutline.Transparency = hbAlpha
                        objs.HealthBarOutline.Visible = true
                    else
                        objs.HealthBar.Visible = false
                        objs.HealthBarOutline.Visible = false
                    end
                else
                    objs.Box.Visible = false
                    objs.BoxOutline.Visible = false
                    objs.HealthBar.Visible = false
                    objs.HealthBarOutline.Visible = false
                    if objs.ChamFill then
                        objs.ChamFill.Visible = false
                    end
                end

                if getToggle('ESPDirection', false) and objs.DirectionLines then
                    local arrowPoints, onScreen = computeOffscreenArrow(rootPart.Position)
                    if arrowPoints and not onScreen then
                        local dirColor, dirAlpha = applyEffects('Direction')
                        objs.DirectionLines[1].From = arrowPoints[1]
                        objs.DirectionLines[1].To = arrowPoints[2]
                        objs.DirectionLines[1].Color = dirColor
                        objs.DirectionLines[1].Transparency = dirAlpha
                        objs.DirectionLines[1].Visible = true
                        objs.DirectionLines[2].From = arrowPoints[2]
                        objs.DirectionLines[2].To = arrowPoints[3]
                        objs.DirectionLines[2].Color = dirColor
                        objs.DirectionLines[2].Transparency = dirAlpha
                        objs.DirectionLines[2].Visible = true
                        objs.DirectionLines[3].From = arrowPoints[3]
                        objs.DirectionLines[3].To = arrowPoints[1]
                        objs.DirectionLines[3].Color = dirColor
                        objs.DirectionLines[3].Transparency = dirAlpha
                        objs.DirectionLines[3].Visible = true
                    else
                        for _, ln in ipairs(objs.DirectionLines) do
                            ln.Visible = false
                        end
                    end
                elseif objs.DirectionLines then
                    for _, ln in ipairs(objs.DirectionLines) do
                        ln.Visible = false
                    end
                end

                if getToggle('ESPTracers', false) and objs.TracerLine and boxOnScreen then
                    local tracerColor, tracerAlpha = applyEffects('Tracers')
                    objs.TracerLine.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                    objs.TracerLine.To = Vector2.new(boxScreenPos.X, boxScreenPos.Y)
                    objs.TracerLine.Color = tracerColor
                    objs.TracerLine.Transparency = tracerAlpha
                    objs.TracerLine.Visible = true
                elseif objs.TracerLine then
                    objs.TracerLine.Visible = false
                end

                -- Scrub any leftover Highlight / ESP_Chams (never recreate).
                pcall(function()
                    local char = player.Character
                    if not char then
                        return
                    end
                    local old = char:FindFirstChild('ESP_Chams')
                    if old then
                        old:Destroy()
                    end
                end)

                if objs.ToolLabel then
                    if getToggle('ESPTool', false) and (nameOnScreen or boxOnScreen) then
                        local toolName = getPlayerToolName(player)
                        if toolName ~= '' then
                            local toolColor, toolAlpha = applyEffects('Tool')
                            objs.ToolLabel.Text = string.format('<font color="%s">%s</font>', color3ToHex(toolColor), toolName)
                            objs.ToolLabel.TextColor3 = toolColor
                            objs.ToolLabel.TextTransparency = 1 - toolAlpha
                            if nameOnScreen then
                                objs.ToolLabel.Position = UDim2.new(0, nameScreenPos.X - 85, 0, nameScreenPos.Y + 4)
                            else
                                objs.ToolLabel.Position = UDim2.new(0, boxScreenPos.X - 85, 0, boxScreenPos.Y + objs.Box.Size.Y + 4)
                            end
                            objs.ToolLabel.Visible = true
                        else
                            objs.ToolLabel.Visible = false
                        end
                    else
                        objs.ToolLabel.Visible = false
                    end
                end
            end

            local roleEspObjects = {}

            local function normalizeName(name)
                if type(name) ~= 'string' then
                    return ''
                end
                return string.lower((name:gsub('^%s+', ''):gsub('%s+$', '')))
            end

            local function extractSelectedName(value)
                if type(value) == 'string' then
                    return value
                end
                if type(value) ~= 'table' then
                    return ''
                end
                if type(value.Value) == 'string' then
                    return value.Value
                end
                if type(value[1]) == 'string' then
                    return value[1]
                end
                for k, v in pairs(value) do
                    if type(k) == 'string' and v == true then
                        return k
                    end
                    if type(v) == 'string' then
                        return v
                    end
                end
                return ''
            end

            local function isInSelection(optionId, player)
                if not player then
                    return false
                end
                local selected = {}
                pcall(function()
                    local opt = Options and Options[optionId]
                    if not opt or type(opt.Value) ~= 'table' then
                        return
                    end
                    for k, v in pairs(opt.Value) do
                        if type(k) == 'string' and v == true then
                            selected[normalizeName(k)] = true
                        elseif type(v) == 'string' then
                            selected[normalizeName(v)] = true
                        end
                    end
                end)
                return selected[normalizeName(player.Name)] == true
                    or selected[normalizeName(player.DisplayName or '')] == true
            end

            local function getPlayerRole(player)
                local shared = getSharedPlayerRole(player)
                if shared then
                    return shared
                end
                local targetName = ''
                pcall(function()
                    if Options and Options.AutoShotTargetPlayer then
                        targetName = extractSelectedName(Options.AutoShotTargetPlayer.Value)
                    end
                end)
                local targetNorm = normalizeName(targetName)
                local nameNorm = normalizeName(player and player.Name or '')
                local displayNorm = normalizeName(player and (player.DisplayName or '') or '')
                if targetNorm ~= '' and (targetNorm == nameNorm or targetNorm == displayNorm) then
                    return 'Target'
                end
                if isInSelection('TriggerWhitelist', player) then
                    return 'Friend'
                end
                return 'Neutral'
            end

            local function resolvePlayerByName(rawName)
                local needle = normalizeName(rawName)
                if needle == '' then
                    return nil
                end
                for _, pl in ipairs(Players:GetPlayers()) do
                    if normalizeName(pl.Name) == needle or normalizeName(pl.DisplayName or '') == needle then
                        return pl
                    end
                end
                return nil
            end

            local function applyRoleManagerSelection()
                local selectedName = ''
                local selectedRole = 'Neutral'
                pcall(function()
                    if Options and Options.RoleManagerPlayer then
                        selectedName = extractSelectedName(Options.RoleManagerPlayer.Value)
                    end
                    if Options and Options.RoleManagerRole then
                        selectedRole = tostring(Options.RoleManagerRole.Value or 'Neutral')
                    end
                end)
                local pl = resolvePlayerByName(selectedName)
                if not pl then
                    return
                end
                selectedRole = normalizeRoleText(selectedRole)
                setSharedPlayerRole(pl, selectedRole)
                if selectedRole == 'Target' then
                    pcall(function()
                        if Options and Options.AutoShotTargetPlayer and type(Options.AutoShotTargetPlayer.SetValue) == 'function' then
                            Options.AutoShotTargetPlayer:SetValue(pl.Name)
                        end
                    end)
                end
                if Options and Options.TriggerWhitelist and type(Options.TriggerWhitelist.SetValue) == 'function' then
                    pcall(function()
                        local current = Options.TriggerWhitelist.Value or {}
                        local newTable = {}
                        local changed = false
                        for k, v in pairs(current) do
                            if k ~= pl.Name then
                                newTable[k] = v
                            end
                        end
                        if selectedRole == 'Friend' then
                            newTable[pl.Name] = true
                            changed = true
                        elseif current[pl.Name] ~= nil then
                            changed = true
                        end
                        if changed then
                            Options.TriggerWhitelist:SetValue(newTable)
                        end
                    end)
                end
            end

            local function roleOptionId(role, suffix)
                return 'RoleESP' .. normalizeRoleText(role) .. suffix
            end

            local function getRoleColor(role)
                role = normalizeRoleText(role)
                if role == 'Target' then
                    return getOptColor(roleOptionId(role, 'Color'), getOptColor('RoleESPColorTarget', Color3.fromRGB(255, 70, 70)))
                end
                if role == 'Friend' then
                    return getOptColor(roleOptionId(role, 'Color'), getOptColor('RoleESPColorFriend', Color3.fromRGB(70, 255, 130)))
                end
                return getOptColor(roleOptionId(role, 'Color'), getOptColor('RoleESPColorNeutral', Color3.fromRGB(200, 200, 210)))
            end

            local function getRoleElementColor(role, suffix)
                local fallback = getRoleColor(role)
                return getOptColor(roleOptionId(role, suffix .. 'Color'), fallback)
            end

            local function getRoleToggle(role, suffix, fallback)
                role = normalizeRoleText(role)
                local id = roleOptionId(role, suffix)
                if Toggles and Toggles[id] ~= nil then
                    return Toggles[id].Value == true
                end

                if suffix == 'Enabled' then
                    if role == 'Target' and Toggles and Toggles.RoleESPShowTarget ~= nil then return Toggles.RoleESPShowTarget.Value == true end
                    if role == 'Friend' and Toggles and Toggles.RoleESPShowFriend ~= nil then return Toggles.RoleESPShowFriend.Value == true end
                    if Toggles and Toggles.RoleESPShowNeutral ~= nil then return Toggles.RoleESPShowNeutral.Value == true end
                    return fallback == true
                end

                local globalId = 'ESP' .. suffix
                if suffix == 'Box' then globalId = 'ESPBoxes' end
                if suffix == 'HealthBar' then globalId = 'ESPHealthBar' end
                if suffix == 'Tracers' then globalId = 'ESPTracers' end
                if suffix == 'Names' then globalId = 'ESPNames' end
                if Toggles and Toggles[globalId] ~= nil then
                    return Toggles[globalId].Value == true
                end
                return fallback == true
            end

            local ROLE_ARMOR_MAX = 130

            local function getRoleArmorMode(role)
                role = normalizeRoleText(role)
                local id = roleOptionId(role, 'ArmorMode')
                if Options and Options[id] then
                    local val = tostring(Options[id].Value or '')
                    if val == 'Bar' then
                        return 'Bar'
                    end
                    if val == 'Text' then
                        return 'Text'
                    end
                end
                if Options and Options.RoleESPArmorMode then
                    local val = tostring(Options.RoleESPArmorMode.Value or '')
                    if val == 'Bar' then
                        return 'Bar'
                    end
                end
                return 'Text'
            end

            local function getPlayerArmor(player)
                if not player then
                    return nil
                end

                local function readArmorFromContainer(container)
                    if not container then
                        return nil
                    end
                    local bodyEffects = container:FindFirstChild('BodyEffects')
                    if not bodyEffects then
                        return nil
                    end
                    local armorObj = bodyEffects:FindFirstChild('Armor')
                    if not armorObj then
                        return nil
                    end
                    if typeof(armorObj.Value) == 'number' then
                        return armorObj.Value
                    end
                    if armorObj:IsA('TextLabel') or armorObj:IsA('TextBox') then
                        return tonumber(armorObj.Text)
                    end
                    if armorObj:IsA('StringValue') then
                        return tonumber(armorObj.Value)
                    end
                    return nil
                end

                local armorValue = nil
                pcall(function()
                    local playersFolder = workspace:FindFirstChild('Players')
                    if playersFolder then
                        armorValue = readArmorFromContainer(playersFolder:FindFirstChild(player.Name))
                    end
                end)
                if armorValue == nil and player.Character then
                    pcall(function()
                        armorValue = readArmorFromContainer(player.Character)
                    end)
                end
                return armorValue
            end

            local function shouldShowRoleESP(player)
                if not player or player == LocalPlayer then
                    return false
                end
                if not getToggle('ESPEnabled', false) then
                    return false
                end
                local role = getPlayerRole(player)
                return getRoleToggle(role, 'Enabled', true)
            end

            local function clearRoleESPForPlayer(player)
                if not player then
                    return
                end
                local objs = roleEspObjects[player.UserId]
                if not objs then
                    return
                end
                pcall(function() if objs.gui then objs.gui:Destroy() end end)
                pcall(function() if objs.box and objs.box.Remove then objs.box:Remove() end end)
                pcall(function() if objs.boxOutline and objs.boxOutline.Remove then objs.boxOutline:Remove() end end)
                pcall(function() if objs.tracer and objs.tracer.Remove then objs.tracer.Visible = false; objs.tracer:Remove() end end)
                pcall(function() if objs.hbar and objs.hbar.Remove then objs.hbar:Remove() end end)
                pcall(function() if objs.hbarOutline and objs.hbarOutline.Remove then objs.hbarOutline:Remove() end end)
                pcall(function() if objs.abar and objs.abar.Remove then objs.abar:Remove() end end)
                pcall(function() if objs.abarOutline and objs.abarOutline.Remove then objs.abarOutline:Remove() end end)
                roleEspObjects[player.UserId] = nil
            end

            local function clearAllRoleESP()
                for _, pl in ipairs(Players:GetPlayers()) do
                    clearRoleESPForPlayer(pl)
                end
            end

            local function createRoleESPForPlayer(player)
                clearRoleESPForPlayer(player)
                if not shouldShowRoleESP(player) then
                    return
                end
                roleEspObjects[player.UserId] = {}
                local objs = roleEspObjects[player.UserId]

                local parent = (gethui and gethui()) or game:GetService('CoreGui')
                local g = Instance.new('ScreenGui')
                g.Name = 'RoleVis_' .. player.Name
                g.IgnoreGuiInset = true
                g.ResetOnSpawn = false
                g.ZIndexBehavior = Enum.ZIndexBehavior.Global
                g.DisplayOrder = 2001
                g.Parent = parent

                local nameLabel = Instance.new('TextLabel')
                nameLabel.Size = UDim2.new(0, 180, 0, 20)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.TextSize = 14
                nameLabel.TextStrokeTransparency = 0
                nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                nameLabel.TextXAlignment = Enum.TextXAlignment.Center
                nameLabel.Visible = false
                nameLabel.Parent = g

                local distLabel = Instance.new('TextLabel')
                distLabel.Size = UDim2.new(0, 180, 0, 16)
                distLabel.BackgroundTransparency = 1
                distLabel.Font = Enum.Font.Gotham
                distLabel.TextSize = 12
                distLabel.TextStrokeTransparency = 0
                distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                distLabel.TextXAlignment = Enum.TextXAlignment.Center
                distLabel.Visible = false
                distLabel.Parent = g

                local armorLabel = Instance.new('TextLabel')
                armorLabel.Size = UDim2.new(0, 180, 0, 16)
                armorLabel.BackgroundTransparency = 1
                armorLabel.Font = Enum.Font.Gotham
                armorLabel.TextSize = 12
                armorLabel.TextStrokeTransparency = 0
                armorLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                armorLabel.TextXAlignment = Enum.TextXAlignment.Center
                armorLabel.Visible = false
                armorLabel.Parent = g

                local boxOutline = Instance.new('Frame')
                boxOutline.Name = 'BoxOutline'
                boxOutline.BackgroundTransparency = 1
                boxOutline.BorderSizePixel = 0
                boxOutline.Visible = false
                boxOutline.Parent = g
                local boxOutStroke = Instance.new('UIStroke')
                boxOutStroke.Color = Color3.new(0, 0, 0)
                boxOutStroke.Thickness = 2
                boxOutStroke.Parent = boxOutline

                local box = Instance.new('Frame')
                box.Name = 'Box'
                box.BackgroundTransparency = 1
                box.BorderSizePixel = 0
                box.Visible = false
                box.Parent = g
                local boxInStroke = Instance.new('UIStroke')
                boxInStroke.Color = Color3.new(1, 1, 1)
                boxInStroke.Thickness = 1
                boxInStroke.Parent = box

                local tracer = Instance.new('Frame')
                tracer.Name = 'Tracer'
                tracer.AnchorPoint = Vector2.new(0, 0.5)
                tracer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                tracer.BorderSizePixel = 0
                tracer.Visible = false
                tracer.Parent = g

                local hbarOutline = Instance.new('Frame')
                hbarOutline.Name = 'HBarOutline'
                hbarOutline.BackgroundColor3 = Color3.new(0, 0, 0)
                hbarOutline.BorderSizePixel = 0
                hbarOutline.Visible = false
                hbarOutline.Parent = g

                local hbar = Instance.new('Frame')
                hbar.Name = 'HBar'
                hbar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                hbar.BorderSizePixel = 0
                hbar.Visible = false
                hbar.Parent = g

                local abarOutline = Instance.new('Frame')
                abarOutline.Name = 'ABarOutline'
                abarOutline.BackgroundColor3 = Color3.new(0, 0, 0)
                abarOutline.BorderSizePixel = 0
                abarOutline.Visible = false
                abarOutline.Parent = g

                local abar = Instance.new('Frame')
                abar.Name = 'ABar'
                abar.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
                abar.BorderSizePixel = 0
                abar.Visible = false
                abar.Parent = g

                objs.gui = g
                objs.nameLabel = nameLabel
                objs.distLabel = distLabel
                objs.armorLabel = armorLabel
                objs.box = box
                objs.boxStroke = boxInStroke
                objs.boxOutline = boxOutline
                objs.tracer = tracer
                objs.hbar = hbar
                objs.hbarOutline = hbarOutline
                objs.abar = abar
                objs.abarOutline = abarOutline
            end

            local function updateRoleESPForPlayer(player)
                local objs = roleEspObjects[player.UserId]
                if not objs then
                    return
                end
                if not shouldShowRoleESP(player) then
                    if objs.nameLabel then objs.nameLabel.Visible = false end
                    if objs.distLabel then objs.distLabel.Visible = false end
                    if objs.armorLabel then objs.armorLabel.Visible = false end
                    if objs.box then objs.box.Visible = false end
                    if objs.boxOutline then objs.boxOutline.Visible = false end
                    if objs.tracer then objs.tracer.Visible = false end
                    if objs.hbar then objs.hbar.Visible = false end
                    if objs.hbarOutline then objs.hbarOutline.Visible = false end
                    if objs.abar then objs.abar.Visible = false end
                    if objs.abarOutline then objs.abarOutline.Visible = false end
                    return
                end

                local char = player.Character
                local humanoid = char and char:FindFirstChildOfClass('Humanoid')
                local rootPart = char and (char:FindFirstChild('UpperTorso') or char:FindFirstChild('HumanoidRootPart'))
                local head = char and char:FindFirstChild('Head')
                if not Camera then
                    Camera = workspace.CurrentCamera
                end
                if not Camera or not rootPart then
                    return
                end

                local role = getPlayerRole(player)
                local namesColor = getRoleElementColor(role, 'Names')
                local distanceColor = getRoleElementColor(role, 'Distance')
                local boxColor = getRoleElementColor(role, 'Box')
                local tracersColor = getRoleElementColor(role, 'Tracers')
                local healthBarColor = getRoleElementColor(role, 'HealthBar')
                local armorColor = getRoleElementColor(role, 'Armor')
                local rootSP, rootOnScreen = Camera:WorldToViewportPoint(rootPart.Position)
                local nameSP, nameOnScreen = Camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2.5, 0))
                local dist = (Camera.CFrame.Position - rootPart.Position).Magnitude

                local bx, by, bw, bh
                if head and (rootOnScreen or nameOnScreen or (rootSP and rootSP.Z > 0)) then
                    local headSP, headVis = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local feetSP, feetVis = Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
                    if (headSP.Z > 0 or feetSP.Z > 0) and (headVis or feetVis or rootOnScreen or nameOnScreen) then
                        bh = math.max(math.abs(headSP.Y - feetSP.Y), 12)
                        bw = math.max(bh * 0.5, 6)
                        bx = headSP.X - bw * 0.5
                        by = headSP.Y - bh * 0.05
                    end
                end

                local labelCenterX = bx and (bx + (bw / 2) - 90) or (nameSP.X - 90)
                local showName = getRoleToggle(role, 'Names', true)
                local showArmor = getRoleToggle(role, 'Armor', true)
                local armorMode = getRoleArmorMode(role)
                local showArmorText = showArmor and armorMode == 'Text'
                local showArmorBar = showArmor and armorMode == 'Bar'
                local armorValue = showArmor and getPlayerArmor(player) or nil

                if objs.nameLabel then
                    if showName and (nameOnScreen or (nameSP and nameSP.Z > 0)) then
                        objs.nameLabel.Text = (player.DisplayName and player.DisplayName ~= '' and player.DisplayName or player.Name)
                        objs.nameLabel.TextColor3 = namesColor
                        local nameY = by and (showArmorText and (by - 38) or (by - 24)) or (showArmorText and (nameSP.Y - 38) or (nameSP.Y - 28))
                        objs.nameLabel.Position = UDim2.new(0, labelCenterX, 0, nameY)
                        objs.nameLabel.Visible = true
                    else
                        objs.nameLabel.Visible = false
                    end
                end

                if objs.armorLabel then
                    if showArmorText and (nameOnScreen or (nameSP and nameSP.Z > 0)) and armorValue ~= nil then
                        objs.armorLabel.Text = string.format('Armor: %d', math.floor(armorValue + 0.5))
                        objs.armorLabel.TextColor3 = armorColor
                        local armorY = by and (by - 20) or (nameSP.Y - 20)
                        objs.armorLabel.Position = UDim2.new(0, labelCenterX, 0, armorY)
                        objs.armorLabel.Visible = true
                    else
                        objs.armorLabel.Visible = false
                    end
                end

                if objs.distLabel then
                    if false then
                        objs.distLabel.Text = string.format('%.0f m', dist)
                        objs.distLabel.TextColor3 = distanceColor
                        objs.distLabel.Position = UDim2.new(0, labelCenterX, 0, nameSP.Y - 12)
                        objs.distLabel.Visible = true
                    else
                        objs.distLabel.Visible = false
                    end
                end

                if head and bx and by and bw and bh then
                    if getRoleToggle(role, 'Box', true) then
                        objs.box.Size = UDim2.fromOffset(bw, bh)
                        objs.box.Position = UDim2.fromOffset(bx, by)
                        if objs.boxStroke then objs.boxStroke.Color = boxColor end
                        objs.box.Visible = true

                        objs.boxOutline.Size = UDim2.fromOffset(bw, bh)
                        objs.boxOutline.Position = UDim2.fromOffset(bx, by)
                        objs.boxOutline.Visible = true
                    else
                        objs.box.Visible = false
                        objs.boxOutline.Visible = false
                    end

                    if getRoleToggle(role, 'HealthBar', true) and humanoid then
                        local maxHp = math.max(humanoid.MaxHealth or 100, 1)
                        local hp = math.clamp(humanoid.Health or maxHp, 0, maxHp)
                        local hpRatio = hp / maxHp
                        local hbh = math.max(bh * hpRatio, 2)
                        objs.hbar.Size = UDim2.fromOffset(2, hbh)
                        objs.hbar.Position = UDim2.fromOffset(bx - 5, by + (bh - hbh))
                        objs.hbar.BackgroundColor3 = healthBarColor
                        objs.hbar.Visible = true

                        objs.hbarOutline.Size = UDim2.fromOffset(4, bh + 2)
                        objs.hbarOutline.Position = UDim2.fromOffset(bx - 6, by - 1)
                        objs.hbarOutline.Visible = true
                    else
                        objs.hbar.Visible = false
                        objs.hbarOutline.Visible = false
                    end

                    if showArmorBar and armorValue ~= nil then
                        local armorRatio = math.clamp(armorValue / ROLE_ARMOR_MAX, 0, 1)
                        local abh = math.max(bh * armorRatio, 2)
                        objs.abar.Size = UDim2.fromOffset(2, abh)
                        objs.abar.Position = UDim2.fromOffset(bx + bw + 3, by + (bh - abh))
                        objs.abar.BackgroundColor3 = armorColor
                        objs.abar.Visible = true

                        objs.abarOutline.Size = UDim2.fromOffset(4, bh + 2)
                        objs.abarOutline.Position = UDim2.fromOffset(bx + bw + 2, by - 1)
                        objs.abarOutline.Visible = true
                    else
                        if objs.abar then objs.abar.Visible = false end
                        if objs.abarOutline then objs.abarOutline.Visible = false end
                    end
                else
                    if objs.box then objs.box.Visible = false end
                    if objs.boxOutline then objs.boxOutline.Visible = false end
                    if objs.hbar then objs.hbar.Visible = false end
                    if objs.hbarOutline then objs.hbarOutline.Visible = false end
                    if objs.abar then objs.abar.Visible = false end
                    if objs.abarOutline then objs.abarOutline.Visible = false end
                end

                if getRoleToggle(role, 'Tracers', false) and (rootOnScreen or nameOnScreen or (rootSP and rootSP.Z > 0)) then
                    local vp = Camera.ViewportSize
                    local from = Vector2.new(vp.X / 2, vp.Y)
                    local to = Vector2.new(rootSP.X, rootSP.Y)
                    local diff = to - from
                    local dist = diff.Magnitude
                    local angle = math.deg(math.atan2(diff.Y, diff.X))

                    objs.tracer.Size = UDim2.fromOffset(dist, 1.5)
                    objs.tracer.Position = UDim2.fromOffset(from.X, from.Y)
                    objs.tracer.Rotation = angle
                    objs.tracer.BackgroundColor3 = tracersColor
                    objs.tracer.Visible = true
                else
                    if objs.tracer then objs.tracer.Visible = false end
                end
            end

            local function refreshAllPlayers()
                for _, pl in ipairs(Players:GetPlayers()) do
                    if pl ~= LocalPlayer then
                        clearESPForPlayer(pl)
                        clearRoleESPForPlayer(pl)
                        if getToggle('ESPEnabled', false) then
                            createRoleESPForPlayer(pl)
                        end
                    end
                end
            end

            trackConn(safeConnect(RunService.RenderStepped, function()
                if not getToggle('ESPEnabled', false) then
                    return
                end
                for _, pl in ipairs(Players:GetPlayers()) do
                    if pl ~= LocalPlayer then
                        if not roleEspObjects[pl.UserId] then
                            createRoleESPForPlayer(pl)
                        end
                        pcall(updateRoleESPForPlayer, pl)
                    end
                end
            end))

            trackConn(safeConnect(Players.PlayerRemoving, function(pl)
                clearESPForPlayer(pl)
                clearRoleESPForPlayer(pl)
            end))

            trackConn(safeConnect(Players.PlayerAdded, function(pl)
                trackConn(safeConnect(pl.CharacterAdded, function()
                    task.wait(0.5)
                    if getToggle('ESPEnabled', false) then
                        createRoleESPForPlayer(pl)
                    end
                end))
            end))

            if Toggles and Toggles.ESPEnabled and type(Toggles.ESPEnabled.OnChanged) == 'function' then
                Toggles.ESPEnabled:OnChanged(function()
                    if getToggle('ESPEnabled', false) then
                        refreshAllPlayers()
                    else
                        clearAllESP()
                        clearAllRoleESP()
                    end
                end)
            end

            local refreshToggles = {
                'ESPChams', 'ESPRainbow', 'ESPFading', 'ESPNames',
                'ESPTracers', 'ESPBoxes', 'ESPHealthBar', 'ESPTool', 'ESPDirection',
                'RoleESPShowTarget', 'RoleESPShowFriend', 'RoleESPShowNeutral',
                'RoleESPShowNames', 'RoleESPShowBox', 'RoleESPShowTracers',
                'RoleESPShowHealthBar', 'RoleESPShowArmor',
                'RoleESPTargetEnabled', 'RoleESPTargetNames', 'RoleESPTargetBox', 'RoleESPTargetTracers',
                'RoleESPTargetHealthBar', 'RoleESPTargetArmor',
                'RoleESPFriendEnabled', 'RoleESPFriendNames', 'RoleESPFriendBox', 'RoleESPFriendTracers',
                'RoleESPFriendHealthBar', 'RoleESPFriendArmor',
                'RoleESPNeutralEnabled', 'RoleESPNeutralNames', 'RoleESPNeutralBox', 'RoleESPNeutralTracers',
                'RoleESPNeutralHealthBar', 'RoleESPNeutralArmor',
            }
            for _, id in ipairs(refreshToggles) do
                if Toggles and Toggles[id] and type(Toggles[id].OnChanged) == 'function' then
                    Toggles[id]:OnChanged(function()
                        if getToggle('ESPEnabled', false) then
                            refreshAllPlayers()
                        end
                    end)
                end
            end

            local refreshOptions = {
                'ESPNameColor', 'ESPChamsColor', 'ESPTracerColor',
                'ESPBoxColor', 'ESPHPColor', 'ESPToolColor', 'ESPDirectionColor',
                'RoleESPColorTarget', 'RoleESPColorFriend', 'RoleESPColorNeutral',
                'RoleESPTargetColor', 'RoleESPFriendColor', 'RoleESPNeutralColor',
                'RoleESPTargetNamesColor', 'RoleESPTargetBoxColor', 'RoleESPTargetTracersColor',
                'RoleESPTargetDistanceColor', 'RoleESPTargetHealthBarColor', 'RoleESPTargetArmorColor',
                'RoleESPFriendNamesColor', 'RoleESPFriendBoxColor', 'RoleESPFriendTracersColor',
                'RoleESPFriendDistanceColor', 'RoleESPFriendHealthBarColor', 'RoleESPFriendArmorColor',
                'RoleESPNeutralNamesColor', 'RoleESPNeutralBoxColor', 'RoleESPNeutralTracersColor',
                'RoleESPNeutralDistanceColor', 'RoleESPNeutralHealthBarColor', 'RoleESPNeutralArmorColor',
                'RoleESPArmorMode',
                'RoleESPTargetArmorMode', 'RoleESPFriendArmorMode', 'RoleESPNeutralArmorMode',
            }
            for _, id in ipairs(refreshOptions) do
                if Options and Options[id] and type(Options[id].OnChanged) == 'function' then
                    Options[id]:OnChanged(function()
                        if getToggle('ESPEnabled', false) then
                            refreshAllPlayers()
                        end
                    end)
                end
            end

            if Options and Options.RoleManagerPlayer and type(Options.RoleManagerPlayer.OnChanged) == 'function' then
                Options.RoleManagerPlayer:OnChanged(function()
                    applyRoleManagerSelection()
                    if getToggle('ESPEnabled', false) then
                        refreshAllPlayers()
                    end
                end)
            end
            if Options and Options.RoleManagerRole and type(Options.RoleManagerRole.OnChanged) == 'function' then
                Options.RoleManagerRole:OnChanged(function()
                    applyRoleManagerSelection()
                    if getToggle('ESPEnabled', false) then
                        refreshAllPlayers()
                    end
                end)
            end

            applyRoleManagerSelection()

            Library:OnUnload(function()
                clearAllESP()
                clearAllRoleESP()
                for _, conn in ipairs(espConnections) do
                    pcall(function()
                        if conn and conn.Disconnect then
                            conn:Disconnect()
                        end
                    end)
                end
            end)
        end)
    end
end

-- I set NoUI so it does not show up in the keybinds menu
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })

-- Optional keybinds list visibility toggle
MenuGroup:AddToggle('ShowKeybindsList', { Text = 'Show Keybinds List', Default = true })

-- Use the Toggles API for toggle change callbacks (AddToggle creates Toggles.ShowKeybindsList)
if Toggles and Toggles.ShowKeybindsList then
    Toggles.ShowKeybindsList:OnChanged(function()
        setKeybindFrameVisibleSafe(Toggles.ShowKeybindsList.Value)
    end)
    -- initialize visibility from the toggle at startup
    setKeybindFrameVisibleSafe(Toggles.ShowKeybindsList.Value)
end

-- Safely assign toggle keybind if Options are available
if Options and Options.MenuKeybind then
    Library.ToggleKeybind = Options.MenuKeybind -- Allows you to have a custom keybind for the menu
end

-- Addons:
-- SaveManager (Allows you to have a configuration system)
-- ThemeManager (Allows you to have a menu theme system)

-- Hand the library over to our managers
-- Hand the library over to our managers
-- Guard these optional manager calls. In some executor/runtime environments
-- ThemeManager/SaveManager internals may reference CoreGui/locales and can
-- produce repeated runtime errors. Wrap each call in pcall and do sanity checks
-- to avoid spamming the console.
pcall(function()
    if type(ThemeManager) == 'table' and type(ThemeManager.SetLibrary) == 'function' then
        pcall(function() ThemeManager:SetLibrary(Library) end)
    end
end)
pcall(function()
    if type(SaveManager) == 'table' and type(SaveManager.SetLibrary) == 'function' then
        pcall(function() SaveManager:SetLibrary(Library) end)
    end
end)

pcall(function()
    if type(SaveManager) == 'table' and type(SaveManager.IgnoreThemeSettings) == 'function' then
        pcall(function() SaveManager:IgnoreThemeSettings() end)
    end
end)

pcall(function()
    if type(SaveManager) == 'table' and type(SaveManager.SetIgnoreIndexes) == 'function' then
        pcall(function() SaveManager:SetIgnoreIndexes({ 'MenuKeybind' }) end)
    end
end)

pcall(function()
    if type(ThemeManager) == 'table' and type(ThemeManager.SetFolder) == 'function' then
        pcall(function() ThemeManager:SetFolder('BomzhoodHub') end)
    end
    if type(SaveManager) == 'table' and type(SaveManager.SetFolder) == 'function' then
        pcall(function() SaveManager:SetFolder('BomzhoodHub/BoomHood') end)
    end
end)

pcall(function()
    if type(SaveManager) == 'table' and type(SaveManager.BuildConfigSection) == 'function' and Tabs and Tabs['UI Settings'] then
        pcall(function() SaveManager:BuildConfigSection(Tabs['UI Settings']) end)
    end
end)

pcall(function()
    if type(ThemeManager) == 'table' and type(ThemeManager.ApplyToTab) == 'function' and Tabs and Tabs['UI Settings'] then
        pcall(function() ThemeManager:ApplyToTab(Tabs['UI Settings']) end)
    end
end)

-- You can use the SaveManager:LoadAutoloadConfig() to load a config
-- which has been marked to be one that auto loads!
pcall(function()
    if type(SaveManager) == 'table' and type(SaveManager.LoadAutoloadConfig) == 'function' then
        pcall(function() SaveManager:LoadAutoloadConfig() end)
    end
end)

-- (handler moved inside Trigger Bot block so it updates the local TriggerWhitelist used by the bot)

-- In-file modern GUI (no external UI library)
do
    local Players = game:GetService('Players')
    local UIS = game:GetService('UserInputService')
    local TweenService = game:GetService('TweenService')
    local RunService = game:GetService('RunService')
    local CoreGui = game:GetService('CoreGui')
    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then
        return
    end

    local State = {}
    local themeDefaults = {
        bg = Color3.fromHex("161616"),
        surface = Color3.fromHex("151515"),
        surfaceSoft = Color3.fromHex("1E1E1E"),
        surfaceElevated = Color3.fromHex("191919"),
        accent = Color3.fromHex("99bcff"),
        accentSoft = Color3.fromHex("557294"),
        accentWarm = Color3.fromHex("b4d0ff"),
        accentBar = Color3.fromHex("99bcff"),
        text = Color3.fromHex("FFFFFF"),
        textDim = Color3.fromHex("8C8F99"),
        success = Color3.fromHex("99bcff"),
        danger = Color3.fromHex("FF8585"),
        stroke = Color3.fromHex("393939"),
        strokeSoft = Color3.fromHex("252527"),
        shadow = Color3.fromHex("000105"),
        glass = Color3.fromHex("131313"),
    }

    local accentGradients = {}
    local function LightenAccent(C)
        return C:Lerp(Color3.fromRGB(255, 255, 255), 0.6)
    end
    local function updateAccentGradients()
        local curAcc = (Options and Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value)
            or (palette and palette.accent)
            or themeDefaults.accent
        local lightAcc = LightenAccent(curAcc)
        local seq = ColorSequence.new({
            ColorSequenceKeypoint.new(0, curAcc),
            ColorSequenceKeypoint.new(0.5, lightAcc),
            ColorSequenceKeypoint.new(1, curAcc),
        })
        for i = #accentGradients, 1, -1 do
            local G = accentGradients[i]
            if not G or not G.Parent then
                table.remove(accentGradients, i)
            else
                G.Color = seq
            end
        end
    end
    local function registerAccentGradient(Gradient)
        table.insert(accentGradients, Gradient)
        local curAcc = (Options and Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value)
            or (palette and palette.accent)
            or themeDefaults.accent
        Gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, curAcc),
            ColorSequenceKeypoint.new(0.5, LightenAccent(curAcc)),
            ColorSequenceKeypoint.new(1, curAcc),
        })
    end
    local AccentClock = 0
    safeConnect(RunService.Heartbeat, function(Dt)
        AccentClock = AccentClock + Dt * 0.4
        local Off = (AccentClock % 2) - 1
        local OffsetV = Vector2.new(Off, 0)
        for i = #accentGradients, 1, -1 do
            local G = accentGradients[i]
            if not G or not G.Parent then
                table.remove(accentGradients, i)
            else
                G.Offset = OffsetV
            end
        end
    end)

    local createCoincideLoader

    local themeOptionIds = {
        bg = 'ThemeBg',
        surface = 'ThemeSurface',
        surfaceSoft = 'ThemeSurfaceSoft',
        surfaceElevated = 'ThemeSurfaceElevated',
        accent = 'ThemeAccent',
        accentSoft = 'ThemeAccentSoft',
        accentWarm = 'ThemeAccentWarm',
        accentBar = 'ThemeAccentBar',
        text = 'ThemeText',
        textDim = 'ThemeTextDim',
        success = 'ThemeSuccess',
        danger = 'ThemeDanger',
        stroke = 'ThemeStroke',
        strokeSoft = 'ThemeStrokeSoft',
        shadow = 'ThemeShadow',
        glass = 'ThemeGlass',
    }

    local themePresets = {
        Default = themeDefaults,
        Pink = {
            bg = Color3.fromRGB(20, 12, 18),
            surface = Color3.fromRGB(30, 18, 28),
            surfaceSoft = Color3.fromRGB(42, 26, 38),
            surfaceElevated = Color3.fromRGB(55, 35, 50),
            accent = Color3.fromRGB(255, 95, 152),
            accentSoft = Color3.fromRGB(200, 70, 120),
            accentWarm = Color3.fromRGB(255, 120, 170),
            accentBar = Color3.fromRGB(255, 95, 152),
            text = Color3.fromRGB(255, 240, 245),
            textDim = Color3.fromRGB(180, 140, 160),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(255, 80, 120),
            stroke = Color3.fromRGB(80, 50, 70),
            strokeSoft = Color3.fromRGB(60, 38, 55),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(35, 22, 32),
        },
        Blue = {
            bg = Color3.fromRGB(8, 12, 22),
            surface = Color3.fromRGB(14, 20, 36),
            surfaceSoft = Color3.fromRGB(22, 30, 52),
            surfaceElevated = Color3.fromRGB(32, 42, 68),
            accent = Color3.fromRGB(60, 130, 255),
            accentSoft = Color3.fromRGB(40, 90, 200),
            accentWarm = Color3.fromRGB(80, 150, 255),
            accentBar = Color3.fromRGB(60, 130, 255),
            text = Color3.fromRGB(230, 240, 255),
            textDim = Color3.fromRGB(130, 150, 180),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(80, 120, 255),
            stroke = Color3.fromRGB(50, 65, 95),
            strokeSoft = Color3.fromRGB(38, 50, 75),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(18, 26, 44),
        },
        Green = {
            bg = Color3.fromRGB(8, 16, 10),
            surface = Color3.fromRGB(14, 26, 18),
            surfaceSoft = Color3.fromRGB(22, 38, 28),
            surfaceElevated = Color3.fromRGB(32, 52, 38),
            accent = Color3.fromRGB(50, 200, 100),
            accentSoft = Color3.fromRGB(35, 150, 75),
            accentWarm = Color3.fromRGB(70, 220, 120),
            accentBar = Color3.fromRGB(50, 200, 100),
            text = Color3.fromRGB(230, 255, 240),
            textDim = Color3.fromRGB(130, 170, 145),
            success = Color3.fromRGB(50, 200, 100),
            danger = Color3.fromRGB(200, 80, 80),
            stroke = Color3.fromRGB(45, 70, 52),
            strokeSoft = Color3.fromRGB(35, 55, 40),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(16, 28, 20),
        },
        Purple = {
            bg = Color3.fromRGB(14, 10, 22),
            surface = Color3.fromRGB(22, 16, 36),
            surfaceSoft = Color3.fromRGB(34, 24, 52),
            surfaceElevated = Color3.fromRGB(48, 34, 68),
            accent = Color3.fromRGB(160, 80, 255),
            accentSoft = Color3.fromRGB(120, 55, 200),
            accentWarm = Color3.fromRGB(180, 100, 255),
            accentBar = Color3.fromRGB(160, 80, 255),
            text = Color3.fromRGB(240, 235, 255),
            textDim = Color3.fromRGB(150, 140, 180),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(200, 80, 160),
            stroke = Color3.fromRGB(65, 50, 90),
            strokeSoft = Color3.fromRGB(50, 38, 72),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(26, 18, 40),
        },
        Orange = {
            bg = Color3.fromRGB(18, 12, 8),
            surface = Color3.fromRGB(28, 18, 12),
            surfaceSoft = Color3.fromRGB(42, 28, 18),
            surfaceElevated = Color3.fromRGB(55, 36, 24),
            accent = Color3.fromRGB(255, 130, 50),
            accentSoft = Color3.fromRGB(200, 95, 35),
            accentWarm = Color3.fromRGB(255, 155, 80),
            accentBar = Color3.fromRGB(255, 130, 50),
            text = Color3.fromRGB(255, 245, 235),
            textDim = Color3.fromRGB(180, 145, 120),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(255, 90, 60),
            stroke = Color3.fromRGB(80, 55, 40),
            strokeSoft = Color3.fromRGB(60, 42, 30),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(32, 22, 14),
        },
        Cyan = {
            bg = Color3.fromRGB(8, 16, 20),
            surface = Color3.fromRGB(12, 24, 30),
            surfaceSoft = Color3.fromRGB(18, 36, 44),
            surfaceElevated = Color3.fromRGB(26, 48, 58),
            accent = Color3.fromRGB(40, 200, 230),
            accentSoft = Color3.fromRGB(30, 150, 175),
            accentWarm = Color3.fromRGB(70, 220, 245),
            accentBar = Color3.fromRGB(40, 200, 230),
            text = Color3.fromRGB(230, 250, 255),
            textDim = Color3.fromRGB(120, 165, 180),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(60, 160, 200),
            stroke = Color3.fromRGB(40, 70, 80),
            strokeSoft = Color3.fromRGB(30, 55, 65),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(14, 28, 34),
        },
        Teal = {
            bg = Color3.fromRGB(8, 16, 16),
            surface = Color3.fromRGB(12, 26, 26),
            surfaceSoft = Color3.fromRGB(18, 38, 38),
            surfaceElevated = Color3.fromRGB(26, 50, 50),
            accent = Color3.fromRGB(40, 180, 160),
            accentSoft = Color3.fromRGB(30, 140, 125),
            accentWarm = Color3.fromRGB(60, 200, 180),
            accentBar = Color3.fromRGB(40, 180, 160),
            text = Color3.fromRGB(230, 255, 250),
            textDim = Color3.fromRGB(120, 165, 155),
            success = Color3.fromRGB(40, 180, 160),
            danger = Color3.fromRGB(200, 80, 80),
            stroke = Color3.fromRGB(40, 70, 65),
            strokeSoft = Color3.fromRGB(30, 55, 50),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(14, 28, 28),
        },
        Amber = {
            bg = Color3.fromRGB(16, 14, 8),
            surface = Color3.fromRGB(26, 22, 12),
            surfaceSoft = Color3.fromRGB(40, 34, 18),
            surfaceElevated = Color3.fromRGB(52, 44, 26),
            accent = Color3.fromRGB(240, 180, 50),
            accentSoft = Color3.fromRGB(190, 140, 35),
            accentWarm = Color3.fromRGB(255, 200, 80),
            accentBar = Color3.fromRGB(240, 180, 50),
            text = Color3.fromRGB(255, 250, 230),
            textDim = Color3.fromRGB(175, 155, 110),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(220, 120, 40),
            stroke = Color3.fromRGB(75, 65, 40),
            strokeSoft = Color3.fromRGB(55, 48, 30),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(30, 26, 14),
        },
        Gray = {
            bg = Color3.fromRGB(12, 12, 12),
            surface = Color3.fromRGB(20, 20, 20),
            surfaceSoft = Color3.fromRGB(30, 30, 30),
            surfaceElevated = Color3.fromRGB(42, 42, 42),
            accent = Color3.fromRGB(180, 180, 180),
            accentSoft = Color3.fromRGB(140, 140, 140),
            accentWarm = Color3.fromRGB(200, 200, 200),
            accentBar = Color3.fromRGB(180, 180, 180),
            text = Color3.fromRGB(235, 235, 235),
            textDim = Color3.fromRGB(130, 130, 130),
            success = Color3.fromRGB(170, 170, 170),
            danger = Color3.fromRGB(160, 160, 160),
            stroke = Color3.fromRGB(70, 70, 70),
            strokeSoft = Color3.fromRGB(50, 50, 50),
            shadow = Color3.fromRGB(0, 0, 0),
            glass = Color3.fromRGB(24, 24, 24),
        },
    }
    local themePresetNames = { 'Default', 'Pink', 'Blue', 'Green', 'Purple', 'Orange', 'Cyan', 'Teal', 'Amber', 'Gray', 'Custom' }

    local uiMetrics = {
        compact = false,
        headerH = 64,
        tabBarH = 40,
        bodyTop = 114,
        toggleH = 38,
        toggleDetailH = 52,
        sliderH = 50,
        cycleH = 36,
        sectionPad = 10,
        sectionPadSide = 12,
        rowGap = 8,
    }
    local compactTargets = {}

    local function registerCompactTarget(instance, property, normalValue, compactValue)
        if instance then
            table.insert(compactTargets, {
                instance = instance,
                property = property,
                normal = normalValue,
                compact = compactValue,
            })
        end
    end

    local palette = {}
    for key, color in pairs(themeDefaults) do
        palette[key] = color
    end

    local themeRefreshers = {}
    local onThemeAppliedCallbacks = {}
    local themeBindings = {}
    local accentBarTargets = {}
    local rangePanelGradient
    local missShotsUi = {
        open = false,
        panel = nil,
        body = nil,
        gradient = nil,
        syncPosition = nil,
        setVisible = nil,
    }
    local silentMissShotsUi = {
        open = false,
        panel = nil,
        body = nil,
        gradient = nil,
        syncPosition = nil,
        setVisible = nil,
    }
    local function registerThemeRefresher(fn)
        if type(fn) == 'function' then
            table.insert(themeRefreshers, fn)
        end
    end

    local function onThemeApplied(fn)
        if type(fn) == 'function' then
            table.insert(onThemeAppliedCallbacks, fn)
        end
    end

    local function bindTheme(instance, property, key)
        if not instance or not property or not key then
            return
        end
        table.insert(themeBindings, {
            instance = instance,
            property = property,
            key = key,
        })
        if palette[key] then
            instance[property] = palette[key]
        end
    end

    local function registerAccentBar(instance)
        if not instance then
            return
        end
        table.insert(accentBarTargets, instance)
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent or palette.accentBar
        instance.BackgroundColor3 = curAccent
    end

    local function syncPaletteFromTheme()
        for key, optionId in pairs(themeOptionIds) do
            local opt = Options[optionId]
            if opt and typeof(opt.Value) == 'Color3' then
                palette[key] = opt.Value
            end
        end
        if palette.accent then
            palette.accentBar = palette.accent
        end
    end

    local function applyThemeBindingsFromRegistry()
        for i = #themeBindings, 1, -1 do
            local entry = themeBindings[i]
            local inst = entry.instance
            if not inst or not inst.Parent then
                table.remove(themeBindings, i)
            elseif palette[entry.key] then
                inst[entry.property] = palette[entry.key]
            end
        end
    end

    local function applyAccentBarColors()
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent or palette.accentBar
        for i = #accentBarTargets, 1, -1 do
            local inst = accentBarTargets[i]
            if not inst or not inst.Parent then
                table.remove(accentBarTargets, i)
            else
                inst.BackgroundColor3 = curAccent
            end
        end
    end

    local applyTheme
    local applyThemePreset
    local isApplyingPreset = false

    applyThemePreset = function(name, silent)
        if isApplyingPreset then
            return
        end
        isApplyingPreset = true

        local presetName = type(name) == 'string' and name or 'Default'
        local optPreset = (type(State) == 'table' and State.ThemePreset) or (type(Options) == 'table' and Options.ThemePreset)

        if presetName == 'Custom' then
            if optPreset and optPreset.Value ~= 'Custom' then
                pcall(function() optPreset.Value = 'Custom' end)
            end
            isApplyingPreset = false
            if type(applyTheme) == 'function' then
                applyTheme()
            end
            return
        end

        local preset = themePresets[presetName] or themePresets.Default
        for key, optionId in pairs(themeOptionIds) do
            local opt = type(Options) == 'table' and Options[optionId]
            if opt and preset[key] then
                pcall(function()
                    opt:SetValue(preset[key])
                end)
            end
        end

        local curPreset = optPreset and optPreset.Value
        if curPreset ~= presetName and not silent and optPreset then
            if type(optPreset.SetValue) == 'function' then
                pcall(function() optPreset:SetValue(presetName) end)
            end
        end

        if type(applyTheme) == 'function' then
            applyTheme()
        end

        isApplyingPreset = false

        if not silent and type(requestSaveConfig) == 'function' then
            requestSaveConfig()
        end
    end

    applyTheme = function()
        syncPaletteFromTheme()
        applyThemeBindingsFromRegistry()
        applyAccentBarColors()
        if type(updateAccentGradients) == 'function' then
            updateAccentGradients()
        end
        if rangePanelGradient then
            rangePanelGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, palette.surface),
                ColorSequenceKeypoint.new(1, palette.bg),
            })
        end
        if missShotsUi.gradient then
            missShotsUi.gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, palette.surface),
                ColorSequenceKeypoint.new(1, palette.bg),
            })
        end
        if silentMissShotsUi.gradient then
            silentMissShotsUi.gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, palette.surface),
                ColorSequenceKeypoint.new(1, palette.bg),
            })
        end
        for _, fn in ipairs(themeRefreshers) do
            pcall(fn)
        end
        for _, fn in ipairs(onThemeAppliedCallbacks) do
            pcall(fn)
        end
    end

    local fonts = {
        display = Enum.Font.GothamBlack,
        title = Enum.Font.SourceSansBold,
        heading = Enum.Font.SourceSansBold,
        body = Enum.Font.SourceSans,
        mono = Enum.Font.Code,
    }

    local function applyCorner(obj, radius)
        local c = Instance.new('UICorner')
        c.CornerRadius = UDim.new(0, 0)
        c.Parent = obj
        return c
    end

    local function applyCoincideBorder(frame)
        local outer = Instance.new('UIStroke')
        outer.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        outer.Color = Color3.fromHex('000105')
        outer.Thickness = 1
        outer.Parent = frame

        local inner = Instance.new('Frame')
        inner.Name = 'CoincideInnerBorder'
        inner.Position = UDim2.new(0, 1, 0, 1)
        inner.Size = UDim2.new(1, -2, 1, -2)
        inner.BackgroundTransparency = 1
        inner.BorderSizePixel = 0
        inner.Parent = frame
        local innerStroke = Instance.new('UIStroke')
        innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        innerStroke.Color = Color3.fromHex('252527')
        innerStroke.Thickness = 1
        innerStroke.Parent = inner
        return outer, innerStroke
    end

    local function applyStroke(obj, colorKey, thickness, transparency)
        local s = Instance.new('UIStroke')
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        local key = type(colorKey) == 'string' and colorKey or nil
        local color = key and palette[key] or colorKey
        s.Color = color
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.Parent = obj
        if key then
            bindTheme(s, 'Color', key)
        end
        return s
    end


    local function tween(obj, time, props, style, direction)
        if not obj or type(props) ~= 'table' then
            return nil
        end
        local info = TweenInfo.new(
            time or 0.18,
            style or Enum.EasingStyle.Quad,
            direction or Enum.EasingDirection.Out
        )
        local tw = TweenService:Create(obj, info, props)
        tw:Play()
        return tw
    end

    local function getActiveAccent()
        return (Options and Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value)
            or (State and State.ThemeAccent and typeof(State.ThemeAccent.Value) == 'Color3' and State.ThemeAccent.Value)
            or (palette and palette.accent)
            or (themeDefaults and themeDefaults.accent)
            or Color3.fromHex('99bcff')
    end

    local function createCoincideWindow(opts)
        opts = opts or {}
        local width = opts.Width or 240
        local height = opts.Height or 300
        local titleText = opts.Title or 'Window'
        local parent = opts.Parent
        local hasClose = opts.HasClose == true

        local outer = Instance.new('Frame')
        outer.Name = opts.Name or 'CoincideWindow'
        outer.Size = UDim2.fromOffset(width, height)
        outer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        outer.BorderSizePixel = 0
        if parent then outer.Parent = parent end

        local grad = Instance.new('UIGradient')
        grad.Rotation = 90
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('212121')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('1A1A1A')),
        })
        grad.Parent = outer

        local outerStroke = Instance.new('UIStroke')
        outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        outerStroke.Color = Color3.fromHex('000000')
        outerStroke.Thickness = 1
        outerStroke.LineJoinMode = Enum.LineJoinMode.Miter
        outerStroke.Parent = outer

        local innerOutline = Instance.new('Frame')
        innerOutline.Name = 'InnerOutline'
        innerOutline.Position = UDim2.new(0, 1, 0, 1)
        innerOutline.Size = UDim2.new(1, -2, 1, -2)
        innerOutline.BackgroundTransparency = 1
        innerOutline.BorderSizePixel = 0
        innerOutline.Parent = outer

        local innerStroke = Instance.new('UIStroke')
        innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        innerStroke.Color = Color3.fromHex('393939')
        innerStroke.Thickness = 1
        innerStroke.LineJoinMode = Enum.LineJoinMode.Miter
        innerStroke.Parent = innerOutline

        local topLine = Instance.new('Frame')
        topLine.Name = 'TopAccentLine'
        topLine.Position = UDim2.new(0, 1, 0, 1)
        topLine.Size = UDim2.new(1, -2, 0, 1)
        topLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        topLine.BorderSizePixel = 0
        topLine.ZIndex = 10
        topLine.Parent = outer
        local topGrad = Instance.new('UIGradient')
        topGrad.Parent = topLine
        registerAccentGradient(topGrad)

        local header = Instance.new('Frame')
        header.Name = 'Header'
        header.Size = UDim2.new(1, 0, 0, 28)
        header.BackgroundTransparency = 1
        header.BorderSizePixel = 0
        header.Active = true
        header.Parent = outer

        local titleLbl = Instance.new('TextLabel')
        titleLbl.Name = 'Title'
        titleLbl.Position = UDim2.new(0, 8, 0, 6)
        titleLbl.Size = UDim2.new(1, hasClose and -36 or -16, 0, 16)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = titleText
        titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLbl.TextSize = 12
        titleLbl.Font = Enum.Font.Gotham
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextYAlignment = Enum.TextYAlignment.Center
        titleLbl.Parent = header

        local closeBtn = nil
        if hasClose then
            closeBtn = Instance.new('TextButton')
            closeBtn.Name = 'Close'
            closeBtn.AnchorPoint = Vector2.new(1, 0.5)
            closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
            closeBtn.Size = UDim2.fromOffset(16, 16)
            closeBtn.Font = Enum.Font.GothamBold
            closeBtn.TextSize = 10
            closeBtn.Text = 'X'
            closeBtn.TextColor3 = Color3.fromHex('8C8F99')
            closeBtn.BackgroundColor3 = Color3.fromHex('191919')
            closeBtn.AutoButtonColor = false
            closeBtn.BorderSizePixel = 0
            closeBtn.Parent = header
            closeBtn.ZIndex = 12

            local closeOuter = Instance.new('UIStroke')
            closeOuter.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            closeOuter.Color = Color3.fromHex('000105')
            closeOuter.Thickness = 1
            closeOuter.Parent = closeBtn

            safeConnect(closeBtn.MouseEnter, function()
                tween(closeBtn, 0.12, { BackgroundColor3 = Color3.fromHex('FF8585'), TextColor3 = Color3.fromRGB(255, 255, 255) })
            end)
            safeConnect(closeBtn.MouseLeave, function()
                tween(closeBtn, 0.18, { BackgroundColor3 = Color3.fromHex('191919'), TextColor3 = Color3.fromHex('8C8F99') })
            end)
        end

        local content = Instance.new('Frame')
        content.Name = 'Content'
        content.Position = UDim2.new(0, 5, 0, 28)
        content.Size = UDim2.new(1, -10, 1, -33)
        content.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        content.BorderSizePixel = 0
        content.Parent = outer

        local contentGrad = Instance.new('UIGradient')
        contentGrad.Rotation = 90
        contentGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('161616')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('101010')),
        })
        contentGrad.Parent = content

        local edgeOverlay = Instance.new('Frame')
        edgeOverlay.Name = 'EdgeOverlay'
        edgeOverlay.Position = content.Position
        edgeOverlay.Size = content.Size
        edgeOverlay.BackgroundTransparency = 1
        edgeOverlay.BorderSizePixel = 0
        edgeOverlay.ZIndex = 12
        edgeOverlay.Parent = outer

        local edgeOuterStroke = Instance.new('UIStroke')
        edgeOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        edgeOuterStroke.Color = Color3.fromHex('000000')
        edgeOuterStroke.Thickness = 1
        edgeOuterStroke.LineJoinMode = Enum.LineJoinMode.Miter
        edgeOuterStroke.Parent = edgeOverlay

        local edgeInnerOutline = Instance.new('Frame')
        edgeInnerOutline.Name = 'InnerBorder'
        edgeInnerOutline.Position = UDim2.new(0, 1, 0, 1)
        edgeInnerOutline.Size = UDim2.new(1, -2, 1, -2)
        edgeInnerOutline.BackgroundTransparency = 1
        edgeInnerOutline.BorderSizePixel = 0
        edgeInnerOutline.ZIndex = 12
        edgeInnerOutline.Parent = edgeOverlay

        local edgeInnerStroke = Instance.new('UIStroke')
        edgeInnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        edgeInnerStroke.Color = Color3.fromHex('393939')
        edgeInnerStroke.Thickness = 1
        edgeInnerStroke.LineJoinMode = Enum.LineJoinMode.Miter
        edgeInnerStroke.Parent = edgeInnerOutline

        safeConnect(content:GetPropertyChangedSignal('Size'), function()
            edgeOverlay.Size = content.Size
        end)
        safeConnect(content:GetPropertyChangedSignal('Position'), function()
            edgeOverlay.Position = content.Position
        end)

        return {
            Outer = outer,
            Header = header,
            Content = content,
            TitleLabel = titleLbl,
            CloseButton = closeBtn,
        }
    end

    local function addHover(frame, baseKey, hoverKey)
        if not frame then
            return
        end
        safeConnect(frame.MouseEnter, function()
            if palette[hoverKey] then
                tween(frame, 0.12, { BackgroundColor3 = palette[hoverKey] })
            end
        end)
        safeConnect(frame.MouseLeave, function()
            if palette[baseKey] then
                tween(frame, 0.18, { BackgroundColor3 = palette[baseKey] })
            end
        end)
    end

    local function runLater(seconds, fn)
        if type(fn) ~= 'function' then
            return
        end
        if type(task) == 'table' and type(task.delay) == 'function' then
            task.delay(seconds, fn)
        else
            delay(seconds, fn)
        end
    end

    local function createShadow(parent, size, position, radius, transparency)
        local shadow = Instance.new('Frame')
        shadow.Name = 'Shadow'
        shadow.BackgroundColor3 = palette.shadow
        shadow.BackgroundTransparency = transparency or 0.45
        shadow.BorderSizePixel = 0
        shadow.Size = size
        shadow.Position = position
        shadow.Active = false
        shadow.Selectable = false
        shadow.ZIndex = 0
        shadow.Parent = parent
        applyCorner(shadow, radius or 10)
        return shadow
    end

    local function resolveParent()
        local ok, hui = pcall(function()
            return gethui and gethui()
        end)
        if ok and hui then
            return hui
        end
        return CoreGui
    end

    local function ensureToggle(id, default)
        if not Toggles[id] then
            Toggles[id] = makeToggle(id, default == true)
        end
        return Toggles[id]
    end

    local function ensureOption(id, default)
        if not Options[id] then
            Options[id] = makeOption(id, default)
        end
        return Options[id]
    end

    local function normalizeSelection(value)
        local out = {}
        if type(value) ~= 'table' then
            return out
        end

        local hasNumeric = false
        for k, _ in pairs(value) do
            if type(k) == 'number' then
                hasNumeric = true
                break
            end
        end

        if hasNumeric then
            for _, v in pairs(value) do
                if type(v) == 'string' then
                    out[v] = true
                end
            end
            return out
        end

        for k, v in pairs(value) do
            if type(k) == 'string' and v then
                out[k] = true
            elseif type(v) == 'string' then
                out[v] = true
            end
        end

        return out
    end

    local function keyName(key)
        if type(key) == 'table' then
            key = key.Key or key[1]
        end
        if typeof(key) == 'EnumItem' then
            return key.Name
        end
        if key == nil then
            return 'None'
        end
        return tostring(key)
    end

    local function keyMatch(input, keyVal)
        if type(keyVal) == 'table' then
            keyVal = keyVal.Key or keyVal[1]
        end

        if typeof(keyVal) == 'EnumItem' then
            if keyVal.EnumType == Enum.KeyCode then
                return input.KeyCode == keyVal
            end
            if keyVal.EnumType == Enum.UserInputType then
                return input.UserInputType == keyVal
            end
        end

        if type(keyVal) == 'string' then
            local kc = Enum.KeyCode[keyVal]
            if kc then
                return input.KeyCode == kc
            end
            local ui = Enum.UserInputType[keyVal]
            if ui then
                return input.UserInputType == ui
            end
            return input.KeyCode.Name == keyVal or input.UserInputType.Name == keyVal
        end

        return false
    end

    local function normalizeMode(mode)
        mode = tostring(mode or 'Hold')
        if mode == 'Hold' or mode == 'Toggle' or mode == 'Always' then
            return mode
        end
        return 'Hold'
    end

    local function attachChangeListener(obj, callback)
        if type(obj) ~= 'table' or type(callback) ~= 'function' then
            return
        end

        if not obj.__modernWrapped then
            obj.__modernWrapped = true
            obj.__modernListeners = {}
            local previous = obj.__onchange
            obj.__onchange = function(...)
                if type(previous) == 'function' then
                    pcall(previous, ...)
                end
                for _, fn in ipairs(obj.__modernListeners) do
                    pcall(fn, ...)
                end
            end
        end

        table.insert(obj.__modernListeners, callback)
    end

    local KeybindOptions = {}
    local function ensureKeybind(id, defaultKey, defaultMode, storeModeInValue)
        local init = storeModeInValue and { defaultKey, defaultMode } or defaultKey
        local opt = ensureOption(id, init)

        if not opt.__kbInit then
            opt.__kbInit = true
            opt.__key = defaultKey
            opt.__mode = normalizeMode(defaultMode)
            opt.__down = false
            opt.__toggled = false
            opt.__storeMode = storeModeInValue == true
            local baseSet = opt.SetValue

            function opt:_compose()
                if self.__storeMode then
                    return { self.__key, self.__mode }
                end
                return self.__key
            end

            function opt:SetMode(m)
                self.__mode = normalizeMode(m)
                if self.__mode ~= 'Toggle' then
                    self.__toggled = false
                end
                baseSet(self, self:_compose())
            end

            function opt:SetValue(v)
                if type(v) == 'table' then
                    local k = v.Key or v[1]
                    local m = v.Mode or v[2]
                    if k ~= nil then
                        self.__key = k
                    end
                    if m ~= nil then
                        self.__mode = normalizeMode(m)
                    end
                elseif v ~= nil then
                    self.__key = v
                end
                baseSet(self, self:_compose())
            end

            function opt:GetState()
                if self.__mode == 'Always' then
                    return true
                end
                if self.__mode == 'Toggle' then
                    return self.__toggled == true
                end
                return self.__down == true
            end
        end

        if type(opt.Value) == 'table' then
            local k = opt.Value.Key or opt.Value[1]
            local m = opt.Value.Mode or opt.Value[2]
            if k ~= nil then
                opt.__key = k
            end
            if m ~= nil then
                opt.__mode = normalizeMode(m)
            end
        elseif opt.Value ~= nil then
            opt.__key = opt.Value
        end

        opt:SetValue(opt.__storeMode and { opt.__key, opt.__mode } or opt.__key)
        KeybindOptions[opt] = true
        return opt
    end

    State = State or {}
    do
    State.VestFixEnable = ensureToggle('VestFixEnable', false)
    State.AutoRev = ensureToggle('AutoRev', false)
    State.TriggerEnabled = ensureToggle('TriggerEnabled', false)
    State.TriggerTargetOnly = ensureToggle('TriggerTargetOnly', false)
    ensureToggle('TriggerThroughWalls', false)
    State.TriggerRevolverRange = ensureOption('TriggerRevolverRange', 165)
    State.TriggerDoubleBarrelRange = ensureOption('TriggerDoubleBarrelRange', 120)
    State.TriggerShotgunRange = ensureOption('TriggerShotgunRange', 95)
    State.TriggerTacticalShotgunRange = ensureOption('TriggerTacticalShotgunRange', 65)
    State.ESPEnabled = ensureToggle('ESPEnabled', false)
    State.ESPBoxes = ensureToggle('ESPBoxes', true)
    State.ESPNames = ensureToggle('ESPNames', true)
    State.ESPChams = ensureToggle('ESPChams', false)
    State.ESPTracers = ensureToggle('ESPTracers', false)
    State.ESPHealthBar = ensureToggle('ESPHealthBar', true)
    State.ESPTool = ensureToggle('ESPTool', false)
    State.ESPDirection = ensureToggle('ESPDirection', false)
    State.ESPRainbow = ensureToggle('ESPRainbow', false)
    State.ESPFading = ensureToggle('ESPFading', false)
    ensureToggle('RoleESPEnabled', false)
    ensureToggle('RoleESPShowTarget', true)
    ensureToggle('RoleESPShowFriend', true)
    ensureToggle('RoleESPShowNeutral', true)
    ensureToggle('RoleESPShowNames', true)
    ensureToggle('RoleESPShowBox', true)
    ensureToggle('RoleESPShowTracers', false)
    ensureToggle('RoleESPShowHealthBar', true)
    ensureToggle('RoleESPShowArmor', true)
    ensureOption('RoleESPArmorMode', 'Text')
    State.RoleESPGroupSettings = {
        Target = {
            Enabled = ensureToggle('RoleESPTargetEnabled', true),
            Names = ensureToggle('RoleESPTargetNames', true),
            NamesColor = ensureOption('RoleESPTargetNamesColor', Color3.fromRGB(255, 70, 70)),
            Box = ensureToggle('RoleESPTargetBox', true),
            BoxColor = ensureOption('RoleESPTargetBoxColor', Color3.fromRGB(255, 70, 70)),
            Tracers = ensureToggle('RoleESPTargetTracers', false),
            TracersColor = ensureOption('RoleESPTargetTracersColor', Color3.fromRGB(255, 70, 70)),
            HealthBar = ensureToggle('RoleESPTargetHealthBar', true),
            HealthBarColor = ensureOption('RoleESPTargetHealthBarColor', Color3.fromRGB(255, 70, 70)),
            Armor = ensureToggle('RoleESPTargetArmor', true),
            ArmorColor = ensureOption('RoleESPTargetArmorColor', Color3.fromRGB(255, 70, 70)),
            ArmorMode = ensureOption('RoleESPTargetArmorMode', 'Text'),
            Color = ensureOption('RoleESPTargetColor', Color3.fromRGB(255, 70, 70)),
        },
        Friend = {
            Enabled = ensureToggle('RoleESPFriendEnabled', true),
            Names = ensureToggle('RoleESPFriendNames', true),
            NamesColor = ensureOption('RoleESPFriendNamesColor', Color3.fromRGB(70, 255, 130)),
            Box = ensureToggle('RoleESPFriendBox', true),
            BoxColor = ensureOption('RoleESPFriendBoxColor', Color3.fromRGB(70, 255, 130)),
            Tracers = ensureToggle('RoleESPFriendTracers', false),
            TracersColor = ensureOption('RoleESPFriendTracersColor', Color3.fromRGB(70, 255, 130)),
            HealthBar = ensureToggle('RoleESPFriendHealthBar', true),
            HealthBarColor = ensureOption('RoleESPFriendHealthBarColor', Color3.fromRGB(70, 255, 130)),
            Armor = ensureToggle('RoleESPFriendArmor', true),
            ArmorColor = ensureOption('RoleESPFriendArmorColor', Color3.fromRGB(70, 255, 130)),
            ArmorMode = ensureOption('RoleESPFriendArmorMode', 'Text'),
            Color = ensureOption('RoleESPFriendColor', Color3.fromRGB(70, 255, 130)),
        },
        Neutral = {
            Enabled = ensureToggle('RoleESPNeutralEnabled', true),
            Names = ensureToggle('RoleESPNeutralNames', true),
            NamesColor = ensureOption('RoleESPNeutralNamesColor', Color3.fromRGB(200, 200, 210)),
            Box = ensureToggle('RoleESPNeutralBox', true),
            BoxColor = ensureOption('RoleESPNeutralBoxColor', Color3.fromRGB(200, 200, 210)),
            Tracers = ensureToggle('RoleESPNeutralTracers', false),
            TracersColor = ensureOption('RoleESPNeutralTracersColor', Color3.fromRGB(200, 200, 210)),
            HealthBar = ensureToggle('RoleESPNeutralHealthBar', true),
            HealthBarColor = ensureOption('RoleESPNeutralHealthBarColor', Color3.fromRGB(200, 200, 210)),
            Armor = ensureToggle('RoleESPNeutralArmor', true),
            ArmorColor = ensureOption('RoleESPNeutralArmorColor', Color3.fromRGB(200, 200, 210)),
            ArmorMode = ensureOption('RoleESPNeutralArmorMode', 'Text'),
            Color = ensureOption('RoleESPNeutralColor', Color3.fromRGB(200, 200, 210)),
        },
    }
    State.ESPUseHealthColor = ensureToggle('ESPUseHealthColor', true)
    State.InventoryAutoSortEnabled = ensureToggle('InventoryAutoSortEnabled', false)
    State.InventoryAutoSortOnSpawn = ensureToggle('InventoryAutoSortOnSpawn', true)
    State.ShowKeybindsList = ensureToggle('ShowKeybindsList', true)
    State.ShowTriggerInKeybinds = ensureToggle('ShowTriggerInKeybinds', true)
    State.ShowAutoShotInKeybinds = ensureToggle('ShowAutoShotInKeybinds', true)
    State.ShowAutoSortInKeybinds = ensureToggle('ShowAutoSortInKeybinds', true)
    State.ShowAimLockInKeybinds = ensureToggle('ShowAimLockInKeybinds', true)
    State.ShowBacktrackInKeybinds = ensureToggle('ShowBacktrackInKeybinds', true)
    State.SpectatorListEnabled = ensureToggle('SpectatorListEnabled', false)
    State.StaffDetectorEnabled = ensureToggle('StaffDetectorEnabled', true)
    State.AntiAimViewerEnabled = ensureToggle('AntiAimViewerEnabled', false)
    State.PanicMode = ensureToggle('PanicMode', false)
    State.ThemePreset = ensureOption('ThemePreset', 'Default')
    State.MenuWidth = ensureOption('MenuWidth', 600)
    State.MenuHeight = ensureOption('MenuHeight', 550)
    State.RangePanelWidth = ensureOption('RangePanelWidth', 248)
    State.RangePanelHeight = ensureOption('RangePanelHeight', 290)
    State.MissShotsPanelWidth = ensureOption('MissShotsPanelWidth', 248)
    State.MissShotsPanelHeight = ensureOption('MissShotsPanelHeight', 180)
    State.SilentMissShotsPanelWidth = ensureOption('SilentMissShotsPanelWidth', 248)
    State.SilentMissShotsPanelHeight = ensureOption('SilentMissShotsPanelHeight', 180)
    State.KeybindsPanelX = ensureOption('KeybindsPanelX', 16)
    State.KeybindsPanelY = ensureOption('KeybindsPanelY', 16)
    State.SpectatorListX = ensureOption('SpectatorListX', 16)
    State.SpectatorListY = ensureOption('SpectatorListY', 96)
    State.AutoShotEnabled = ensureToggle('AutoShotEnabled', true)
    State.AutoShotQuickSelectEnabled = ensureToggle('AutoShotQuickSelectEnabled', true)

    State.TriggerDelay = ensureOption('TriggerDelay', 0)
    State.TriggerMode = ensureOption('TriggerMode', 'Hitbox')
    State.TriggerMissEnabled = ensureToggle('TriggerMissEnabled', false)
    State.TriggerMissPercent = ensureOption('TriggerMissPercent', 0)
    State.TriggerMissRadius = ensureOption('TriggerMissRadius', 30)
    State.TriggerMissRevolverShots = ensureOption('TriggerMissRevolverShots', 3)
    State.TriggerMissShotgunShots = ensureOption('TriggerMissShotgunShots', 1)
    State.TriggerWhitelist = ensureOption('TriggerWhitelist', {})
    State.ESPBoxColor = ensureOption('ESPBoxColor', Color3.fromRGB(255, 255, 255))
    State.ESPNameColor = ensureOption('ESPNameColor', Color3.fromRGB(255, 255, 255))
    State.ESPChamsColor = ensureOption('ESPChamsColor', Color3.fromRGB(255, 255, 255))
    State.ESPTracerColor = ensureOption('ESPTracerColor', Color3.fromRGB(255, 255, 255))
    State.ESPHPColor = ensureOption('ESPHPColor', Color3.fromRGB(0, 255, 0))
    State.ESPToolColor = ensureOption('ESPToolColor', Color3.fromRGB(255, 200, 0))
    State.ESPDirectionColor = ensureOption('ESPDirectionColor', Color3.fromRGB(255, 0, 0))
    ensureOption('RoleESPColorTarget', Color3.fromRGB(255, 70, 70))
    ensureOption('RoleESPColorFriend', Color3.fromRGB(70, 255, 130))
    ensureOption('RoleESPColorNeutral', Color3.fromRGB(200, 200, 210))
    State.RoleESPGroup = ensureOption('RoleESPGroup', 'Neutral')
    ensureOption('RoleManagerPlayer', '')
    ensureOption('RoleManagerRole', 'Neutral')
    State.SelectedCrewTargets = ensureOption('SelectedCrewTargets', {})
    State.SelectedCrewFriends = ensureOption('SelectedCrewFriends', {})
    State.AutoShotMode = ensureOption('AutoShotMode', 'BURST')
    State.AutoShotTargetPlayer = ensureOption('AutoShotTargetPlayer', '')
    State.AutoShotDelayMin = ensureOption('AutoShotDelayMin', 130)
    State.AutoShotDelayMax = ensureOption('AutoShotDelayMax', 200)
    State.InventorySlots = {}

    State.AimLock = {
        Enabled = ensureToggle('AimLockEnabled', false),
        Smooth = ensureOption('AimLockSmooth', 10),
        FOV = ensureOption('AimLockFOV', 30),
        ShowFOV = ensureToggle('AimLockShowFOV', false),
        FOVColor = ensureOption('AimLockFOVColor', Color3.fromRGB(255, 255, 255)),
        AimMode = ensureOption('AimLockAimMode', 'Body Part'),
        BodyPart = ensureOption('AimLockBodyPart', 'Head'),
        HitboxJitter = ensureOption('AimLockHitboxJitter', 25),
        TargetSwitchDelay = ensureOption('AimLockTargetSwitchDelay', 0.1),
        TargetOnly = ensureToggle('AimLockTargetOnly', false),
        AutoShot = ensureToggle('AimLockAutoShot', false),
        AutoShotDelay = ensureOption('AimLockAutoShotDelay', 0),
        MissEnabled = ensureToggle('AimLockMissEnabled', false),
        MissPercent = ensureOption('AimLockMissPercent', 0),
        MissRevolverShots = ensureOption('AimLockMissRevolverShots', 3),
        MissShotgunShots = ensureOption('AimLockMissShotgunShots', 1),
        Connection = nil,
        FOVCircle = nil,
    }
    for i = 1, 9 do
        State.InventorySlots[i] = ensureOption('InventorySlot' .. i, '')
    end

    State.TriggerKey = ensureKeybind('TriggerKey', Enum.KeyCode.C, 'Hold', true)
    State.AutoShotKey = ensureKeybind('AutoShotKey', Enum.KeyCode.X, 'Hold', true)
    State.InventoryAutoSortKey = ensureKeybind('InventoryAutoSortKey', Enum.KeyCode.V, 'Hold', true)
    State.InstaKey = ensureKeybind('InstaMacroKey', Enum.KeyCode.Insert, 'Hold', false)
    State.MenuKey = ensureKeybind('MenuKeybind', Enum.KeyCode.End, 'Hold', false)
    State.AimLock.Key = ensureKeybind('AimLockKey', Enum.UserInputType.MouseButton2, 'Hold', true)
    State.AimLock.AutoShotKey = ensureKeybind('AimLockAutoShotKey', Enum.KeyCode.E, 'Hold', true)
    State.Backtrack = {
        Enabled = ensureToggle('BacktrackEnabled', false),
        TargetOnly = ensureToggle('BacktrackTargetOnly', false),
        ShowGhosts = ensureToggle('BacktrackShowGhosts', true),
        Delay = ensureOption('BacktrackDelay', 200),
        Chance = ensureOption('BacktrackChance', 100),
        SilentChance = ensureOption('BacktrackSilentChance', 100),
        TriggerChance = ensureOption('BacktrackTriggerChance', 100),
        Color = ensureOption('BacktrackColor', Color3.fromRGB(0, 220, 255)),
    }
    if State.Backtrack.Chance and type(State.Backtrack.Chance.OnChanged) == 'function' then
        State.Backtrack.Chance:OnChanged(function(v)
            if State.Backtrack.SilentChance then State.Backtrack.SilentChance.Value = v end
            if State.Backtrack.TriggerChance then State.Backtrack.TriggerChance.Value = v end
        end)
    end
    State.Backtrack.Key = ensureKeybind('BacktrackKey', Enum.KeyCode.Q, 'Toggle', true)
    for key, optionId in pairs(themeOptionIds) do
        State[optionId] = ensureOption(optionId, themeDefaults[key])
    end
    State.Watermark = ensureToggle('Watermark', true)
    State.WatermarkOpts = ensureOption('WatermarkOpts', 'Title | Fps | Ping | Game')
    State.WatermarkRate = ensureOption('WatermarkRate', 0.1)
    State.MenuEaseStyle = ensureOption('MenuEaseStyle', 'Quint')
    State.MenuEaseDir = ensureOption('MenuEaseDir', 'Out')
    State.TweeningSpeed = ensureOption('TweeningSpeed', 1.0)
    State.DraggingSpeed = ensureOption('DraggingSpeed', 0.05)
    State.ConfigName = ensureOption('ConfigName', 'default')
    State.ThemeName = ensureOption('ThemeName', 'default')
    end

    local isInitialLoaderActive = true
    local main, screen, keybindScreen, rangePanel, pagesRoot, menuGroup, keybindGroup, keybindWindow, spectatorListPanel, settingsWindow
    local header, closeBtn, tabBar, rangePanelBody, body, content, headerBackdrop
    local keybindConnections = {}
    local rangePanelOpen = false
    local syncRangePanelPosition, setRangePanelVisible, syncSettingsPosition
    local mainTargetSize, mainTargetPos
    local applyOverlayPanelPositions, requestSaveConfig, saveConfig, loadConfig, showNotification
    local listConfigs, deleteConfig, setAutoLoad, clearAutoLoad, listThemes, saveTheme, loadTheme, deleteTheme, saveRoles, loadRoles

    createCoincideLoader = function(title, onFinish)
        task.spawn(function()
            local pcallOk = pcall(function()
                local loaderParent = (type(resolveParent) == 'function' and resolveParent())
                    or (type(gethui) == 'function' and pcall(function() return gethui() end) and gethui())
                    or CoreGui
                    or (game:GetService('Players').LocalPlayer and game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui', 5))

                if not loaderParent then
                    if type(onFinish) == 'function' then onFinish() end
                    return
                end

                local loaderGui = Instance.new('ScreenGui')
                loaderGui.Name = 'BomzhoodHub_Loader'
                loaderGui.ResetOnSpawn = false
                loaderGui.IgnoreGuiInset = true
                loaderGui.DisplayOrder = 999999
                loaderGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
                loaderGui.Parent = loaderParent

                local isCanvasGroup = false
                local loaderWindow
                local okCg, cg = pcall(function()
                    return Instance.new('CanvasGroup')
                end)
                if okCg and cg and typeof(cg) == 'Instance' then
                    isCanvasGroup = true
                    loaderWindow = cg
                else
                    loaderWindow = Instance.new('Frame')
                end

                loaderWindow.Name = 'LoaderWindow'
                loaderWindow.AnchorPoint = Vector2.new(0.5, 0.5)
                loaderWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
                loaderWindow.Size = UDim2.fromOffset(380, 280)
                loaderWindow.BackgroundColor3 = Color3.fromHex('141414')
                loaderWindow.BorderSizePixel = 0
                loaderWindow.Parent = loaderGui
                if isCanvasGroup then
                    loaderWindow.GroupTransparency = 1
                end

                local winGrad = Instance.new('UIGradient')
                winGrad.Rotation = 90
                winGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('1A1A1A')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('101010')),
                })
                winGrad.Parent = loaderWindow

                local outerStroke = Instance.new('UIStroke')
                outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                outerStroke.Color = Color3.fromHex('000000')
                outerStroke.Thickness = 1
                outerStroke.LineJoinMode = Enum.LineJoinMode.Miter
                outerStroke.Parent = loaderWindow

                local innerBorder = Instance.new('Frame')
                innerBorder.Name = 'InnerBorder'
                innerBorder.Position = UDim2.fromOffset(1, 1)
                innerBorder.Size = UDim2.new(1, -2, 1, -2)
                innerBorder.BackgroundTransparency = 1
                innerBorder.BorderSizePixel = 0
                innerBorder.ZIndex = 20
                innerBorder.Parent = loaderWindow

                local innerStroke = Instance.new('UIStroke')
                innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                innerStroke.Color = Color3.fromHex('383838')
                innerStroke.Thickness = 1
                innerStroke.LineJoinMode = Enum.LineJoinMode.Miter
                innerStroke.Parent = innerBorder

                local topAccent = Instance.new('Frame')
                topAccent.Name = 'TopAccent'
                topAccent.Position = UDim2.new(0, 1, 0, 1)
                topAccent.Size = UDim2.new(1, -2, 0, 2)
                topAccent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                topAccent.BorderSizePixel = 0
                topAccent.ZIndex = 25
                topAccent.Parent = loaderWindow

                local topAccentGrad = Instance.new('UIGradient')
                topAccentGrad.Parent = topAccent
                if type(registerAccentGradient) == 'function' then
                    registerAccentGradient(topAccentGrad)
                else
                    local curAcc = (type(getActiveAccent) == 'function' and getActiveAccent()) or Color3.fromHex('99bcff')
                    topAccentGrad.Color = ColorSequence.new(curAcc)
                end

                local header = Instance.new('Frame')
                header.Name = 'Header'
                header.Position = UDim2.new(0, 2, 0, 3)
                header.Size = UDim2.new(1, -4, 0, 28)
                header.BackgroundColor3 = Color3.fromHex('171717')
                header.BorderSizePixel = 0
                header.ZIndex = 5
                header.Parent = loaderWindow

                local headerBottom = Instance.new('Frame')
                headerBottom.Name = 'HeaderBottom'
                headerBottom.Position = UDim2.new(0, 0, 1, -1)
                headerBottom.Size = UDim2.new(1, 0, 0, 1)
                headerBottom.BackgroundColor3 = Color3.fromHex('262626')
                headerBottom.BorderSizePixel = 0
                headerBottom.ZIndex = 6
                headerBottom.Parent = header

                local headerTitle = Instance.new('TextLabel')
                headerTitle.Name = 'Title'
                headerTitle.Position = UDim2.new(0, 10, 0, 0)
                headerTitle.Size = UDim2.new(0, 95, 1, 0)
                headerTitle.BackgroundTransparency = 1
                headerTitle.Font = Enum.Font.GothamBold
                headerTitle.TextSize = 12
                headerTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
                headerTitle.TextXAlignment = Enum.TextXAlignment.Left
                headerTitle.Text = title or 'Bomzhood Hub'
                headerTitle.ZIndex = 7
                headerTitle.Parent = header

                local emblemFrame = Instance.new('Frame')
                emblemFrame.Name = 'EmblemFrame'
                emblemFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                emblemFrame.Position = UDim2.new(0.5, 0, 0.44, 0)
                emblemFrame.Size = UDim2.fromOffset(88, 88)
                emblemFrame.BackgroundColor3 = Color3.fromHex('171717')
                emblemFrame.BorderSizePixel = 0
                emblemFrame.ZIndex = 8
                emblemFrame.Parent = loaderWindow

                local emblemGrad = Instance.new('UIGradient')
                emblemGrad.Rotation = 90
                emblemGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('202020')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
                })
                emblemGrad.Parent = emblemFrame

                local emblemOuterStroke = Instance.new('UIStroke')
                emblemOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                emblemOuterStroke.Color = Color3.fromHex('000000')
                emblemOuterStroke.Thickness = 1
                emblemOuterStroke.LineJoinMode = Enum.LineJoinMode.Miter
                emblemOuterStroke.Parent = emblemFrame

                local emblemInner = Instance.new('Frame')
                emblemInner.Name = 'Inner'
                emblemInner.Position = UDim2.fromOffset(1, 1)
                emblemInner.Size = UDim2.new(1, -2, 1, -2)
                emblemInner.BackgroundTransparency = 1
                emblemInner.BorderSizePixel = 0
                emblemInner.ZIndex = 9
                emblemInner.Parent = emblemFrame

                local emblemInnerStroke = Instance.new('UIStroke')
                emblemInnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                emblemInnerStroke.Color = Color3.fromHex('353535')
                emblemInnerStroke.Thickness = 1
                emblemInnerStroke.LineJoinMode = Enum.LineJoinMode.Miter
                emblemInnerStroke.Parent = emblemInner

                local emblemTop = Instance.new('Frame')
                emblemTop.Name = 'EmblemTop'
                emblemTop.Position = UDim2.new(0, 1, 0, 1)
                emblemTop.Size = UDim2.new(1, -2, 0, 1)
                emblemTop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                emblemTop.BorderSizePixel = 0
                emblemTop.ZIndex = 11
                emblemTop.Parent = emblemFrame
                local emblemTopGrad = Instance.new('UIGradient')
                emblemTopGrad.Parent = emblemTop
                if type(registerAccentGradient) == 'function' then
                    registerAccentGradient(emblemTopGrad)
                else
                    local curAcc = (type(getActiveAccent) == 'function' and getActiveAccent()) or Color3.fromHex('99bcff')
                    emblemTopGrad.Color = ColorSequence.new(curAcc)
                end

                local letterShadow = Instance.new('TextLabel')
                letterShadow.Name = 'LetterB_Shadow'
                letterShadow.Position = UDim2.fromOffset(0, 2)
                letterShadow.Size = UDim2.new(1, 0, 1, 0)
                letterShadow.BackgroundTransparency = 1
                letterShadow.Font = Enum.Font.GothamBold
                letterShadow.TextSize = 56
                letterShadow.Text = 'B'
                letterShadow.TextColor3 = (type(getActiveAccent) == 'function' and getActiveAccent()) or Color3.fromHex('99bcff')
                letterShadow.TextTransparency = 0.55
                letterShadow.ZIndex = 10
                letterShadow.Parent = emblemFrame

                local letterMain = Instance.new('TextLabel')
                letterMain.Name = 'LetterB_Main'
                letterMain.Position = UDim2.new(0, 0, 0, 0)
                letterMain.Size = UDim2.new(1, 0, 1, 0)
                letterMain.BackgroundTransparency = 1
                letterMain.Font = Enum.Font.GothamBold
                letterMain.TextSize = 56
                letterMain.Text = 'B'
                letterMain.TextColor3 = Color3.fromRGB(255, 255, 255)
                letterMain.ZIndex = 11
                letterMain.Parent = emblemFrame

                local brandTitle = Instance.new('TextLabel')
                brandTitle.Name = 'BrandTitle'
                brandTitle.Position = UDim2.new(0, 0, 0.44, 50)
                brandTitle.Size = UDim2.new(1, 0, 0, 14)
                brandTitle.BackgroundTransparency = 1
                brandTitle.Font = Enum.Font.GothamBold
                brandTitle.TextSize = 10
                brandTitle.TextColor3 = Color3.fromHex('C0C3CE')
                brandTitle.Text = 'B O M Z H O O D'
                brandTitle.ZIndex = 8
                brandTitle.Parent = loaderWindow

                local bottomFrame = Instance.new('Frame')
                bottomFrame.Name = 'BottomFrame'
                bottomFrame.Position = UDim2.new(0, 20, 1, -56)
                bottomFrame.Size = UDim2.new(1, -40, 0, 42)
                bottomFrame.BackgroundTransparency = 1
                bottomFrame.BorderSizePixel = 0
                bottomFrame.ZIndex = 8
                bottomFrame.Parent = loaderWindow

                local statusLabel = Instance.new('TextLabel')
                statusLabel.Name = 'StatusLabel'
                statusLabel.Position = UDim2.new(0, 0, 0, 0)
                statusLabel.Size = UDim2.new(1, -50, 0, 14)
                statusLabel.BackgroundTransparency = 1
                statusLabel.Font = Enum.Font.GothamMedium
                statusLabel.TextSize = 11
                statusLabel.TextColor3 = Color3.fromHex('989CA8')
                statusLabel.TextXAlignment = Enum.TextXAlignment.Left
                statusLabel.Text = 'Checking game environment...'
                statusLabel.ZIndex = 9
                statusLabel.Parent = bottomFrame

                local percentLabel = Instance.new('TextLabel')
                percentLabel.Name = 'PercentLabel'
                percentLabel.Position = UDim2.new(1, -50, 0, 0)
                percentLabel.Size = UDim2.new(0, 50, 0, 14)
                percentLabel.BackgroundTransparency = 1
                percentLabel.Font = Enum.Font.GothamBold
                percentLabel.TextSize = 11
                percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                percentLabel.TextXAlignment = Enum.TextXAlignment.Right
                percentLabel.Text = '0%'
                percentLabel.ZIndex = 9
                percentLabel.Parent = bottomFrame

                local barTrack = Instance.new('Frame')
                barTrack.Name = 'BarTrack'
                barTrack.Position = UDim2.new(0, 0, 0, 18)
                barTrack.Size = UDim2.new(1, 0, 0, 10)
                barTrack.BackgroundColor3 = Color3.fromHex('0F0F0F')
                barTrack.BorderSizePixel = 0
                barTrack.ZIndex = 9
                barTrack.Parent = bottomFrame

                local barTrackOuter = Instance.new('UIStroke')
                barTrackOuter.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                barTrackOuter.Color = Color3.fromHex('000000')
                barTrackOuter.Thickness = 1
                barTrackOuter.LineJoinMode = Enum.LineJoinMode.Miter
                barTrackOuter.Parent = barTrack

                local barTrackInner = Instance.new('Frame')
                barTrackInner.Name = 'Inner'
                barTrackInner.Position = UDim2.fromOffset(1, 1)
                barTrackInner.Size = UDim2.new(1, -2, 1, -2)
                barTrackInner.BackgroundTransparency = 1
                barTrackInner.BorderSizePixel = 0
                barTrackInner.ZIndex = 10
                barTrackInner.Parent = barTrack

                local barTrackInnerStroke = Instance.new('UIStroke')
                barTrackInnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                barTrackInnerStroke.Color = Color3.fromHex('2E2E2E')
                barTrackInnerStroke.Thickness = 1
                barTrackInnerStroke.LineJoinMode = Enum.LineJoinMode.Miter
                barTrackInnerStroke.Parent = barTrackInner

                local barFill = Instance.new('Frame')
                barFill.Name = 'BarFill'
                barFill.Position = UDim2.fromOffset(1, 1)
                barFill.Size = UDim2.new(0, 0, 1, -2)
                barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                barFill.BorderSizePixel = 0
                barFill.ZIndex = 12
                barFill.Parent = barTrack

                local barFillGrad = Instance.new('UIGradient')
                barFillGrad.Parent = barFill
                if type(registerAccentGradient) == 'function' then
                    registerAccentGradient(barFillGrad)
                else
                    local curAcc = (type(getActiveAccent) == 'function' and getActiveAccent()) or Color3.fromHex('99bcff')
                    barFillGrad.Color = ColorSequence.new(curAcc)
                end

                local TweenService = game:GetService('TweenService')
                if isCanvasGroup then
                    TweenService:Create(loaderWindow, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        GroupTransparency = 0
                    }):Play()
                end

                local stages = {
                    { targetPct = 0.18, text = 'Checking game environment & hooks...', dur = 0.70 },
                    { targetPct = 0.42, text = 'Bypassing integrity checks & memory scan...', dur = 0.85 },
                    { targetPct = 0.68, text = 'Decrypting Coincide core modules...', dur = 0.85 },
                    { targetPct = 0.88, text = 'Hooking weapon framework & backtrack...', dur = 0.90 },
                    { targetPct = 0.96, text = 'Synchronizing configurations & presets...', dur = 0.60 },
                    { targetPct = 1.00, text = 'Initialized successfully. Welcome!', dur = 0.60 },
                }

                local currentPct = 0
                for _, stage in ipairs(stages) do
                    statusLabel.Text = stage.text
                    local startPct = currentPct
                    local endPct = stage.targetPct
                    local stageDuration = stage.dur
                    local elapsed = 0

                    local targetWidthScale = math.clamp(endPct, 0, 1)
                    TweenService:Create(barFill, TweenInfo.new(stageDuration, Enum.EasingStyle.Linear), {
                        Size = UDim2.new(targetWidthScale, -math.floor(2 * (1 - targetWidthScale)), 1, -2)
                    }):Play()

                    while elapsed < stageDuration do
                        local dt = task.wait(0.03)
                        elapsed = elapsed + dt
                        local alpha = math.clamp(elapsed / stageDuration, 0, 1)
                        local curVal = math.floor((startPct + (endPct - startPct) * alpha) * 100)
                        percentLabel.Text = tostring(math.clamp(curVal, 0, 100)) .. '%'
                    end
                    currentPct = endPct
                    percentLabel.Text = tostring(math.floor(currentPct * 100)) .. '%'
                end

                barFill.Size = UDim2.new(1, -2, 1, -2)
                percentLabel.Text = '100%'
                statusLabel.Text = 'Welcome to Bomzhood Hub'
                task.wait(0.35)

                if isCanvasGroup then
                    local fadeTween = TweenService:Create(loaderWindow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                        GroupTransparency = 1
                    })
                    fadeTween:Play()
                    fadeTween.Completed:Wait()
                else
                    for i = 1, 10 do
                        loaderWindow.BackgroundTransparency = i / 10
                        task.wait(0.03)
                    end
                end

                pcall(function() loaderGui:Destroy() end)
            end)

            if type(onFinish) == 'function' then
                onFinish()
            end
        end)
    end
    ;(function()
    local parent = resolveParent()
    if not parent then
        return
    end

    pcall(function()
        for _, name in ipairs({
            'BomzhoodInlineMenu',
            'BomzhoodModernMenu',
            'BomzhoodModernKeybinds',
            'AuroraHub_Interface',
            'AuroraHub_Keybinds',
            'BomzhoodHub_Interface',
            'BomzhoodHub_Keybinds',
            'BomzhoodWatermark',
            'BomzhoodHub_Loader',
        }) do
            local oldUi = parent:FindFirstChild(name)
            if oldUi then
                oldUi:Destroy()
            end
        end
    end)

    screen = Instance.new('ScreenGui')
    screen.Name = 'BomzhoodHub_Interface'
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screen.DisplayOrder = 999
    screen.Enabled = false
    screen.Parent = parent

    menuGroup = Instance.new('Frame')
    menuGroup.Name = 'MenuGroup'
    menuGroup.BackgroundTransparency = 1
    menuGroup.Size = UDim2.new(1, 0, 1, 0)
    menuGroup.Parent = screen

    keybindScreen = Instance.new('ScreenGui')
    keybindScreen.Name = 'BomzhoodHub_Keybinds'
    keybindScreen.ResetOnSpawn = false
    keybindScreen.IgnoreGuiInset = true
    keybindScreen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    keybindScreen.DisplayOrder = 1000
    keybindScreen.Enabled = false
    keybindScreen.Parent = parent

    local notifScreen = Instance.new('ScreenGui')
    notifScreen.Name = 'BomzhoodHub_Notifications'
    notifScreen.ResetOnSpawn = false
    notifScreen.IgnoreGuiInset = true
    notifScreen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    notifScreen.DisplayOrder = 2000
    notifScreen.Parent = parent

    keybindGroup = Instance.new('Frame')
    keybindGroup.Name = 'KeybindGroup'
    keybindGroup.BackgroundTransparency = 1
    keybindGroup.Size = UDim2.new(1, 0, 1, 0)
    keybindGroup.Parent = keybindScreen

    local function trackKeybindConnection(conn)
        if conn then
            table.insert(keybindConnections, conn)
        end
        return conn
    end

    keybindWindow = Instance.new('Frame')
    keybindWindow.Name = 'Keybinds'
    keybindWindow.Size = UDim2.fromOffset(180, 0)
    keybindWindow.AutomaticSize = Enum.AutomaticSize.Y
    keybindWindow.Position = UDim2.fromOffset(
        tonumber(State.KeybindsPanelX and State.KeybindsPanelX.Value) or 16,
        tonumber(State.KeybindsPanelY and State.KeybindsPanelY.Value) or 16
    )
    keybindWindow.BackgroundColor3 = Color3.fromHex('FFFFFF')
    keybindWindow.BorderSizePixel = 0
    keybindWindow.Parent = keybindGroup

    local kbGrad = Instance.new('UIGradient')
    kbGrad.Rotation = 90
    kbGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromHex('1F1F1F')),
        ColorSequenceKeypoint.new(1, Color3.fromHex('141414')),
    })
    kbGrad.Parent = keybindWindow

    local function MakeKbEdge(Anchor, Pos, Sz, Col, ZIdx)
        local e = Instance.new('Frame')
        e.AnchorPoint = Anchor
        e.Position = Pos
        e.Size = Sz
        e.BackgroundColor3 = typeof(Col) == 'string' and Color3.fromHex(Col) or Col
        e.BorderSizePixel = 0
        e.ZIndex = ZIdx or 5
        e.Parent = keybindWindow
        return e
    end

    MakeKbEdge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(1, 0, 0, 1),  '000000')
    local kbTopLine = Instance.new('Frame')
    kbTopLine.Name = 'TopLine'
    kbTopLine.Position = UDim2.new(0, 0, 0, 1)
    kbTopLine.Size = UDim2.new(1, 0, 0, 1)
    kbTopLine.BackgroundColor3 = Color3.fromHex('FFFFFF')
    kbTopLine.BorderSizePixel = 0
    kbTopLine.ZIndex = 6
    kbTopLine.Parent = keybindWindow
    local kbTopGrad = Instance.new('UIGradient')
    kbTopGrad.Parent = kbTopLine
    registerAccentGradient(kbTopGrad)

    MakeKbEdge(Vector2.new(0, 1), UDim2.new(0, 0, 1, 0),  UDim2.new(1, 0, 0, 1),  '000000')
    MakeKbEdge(Vector2.new(0, 1), UDim2.new(0, 1, 1, -1), UDim2.new(1, -2, 0, 1), '393939')
    MakeKbEdge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(0, 1, 1, 0),  '000000')
    MakeKbEdge(Vector2.new(0, 0), UDim2.new(0, 1, 0, 2),  UDim2.new(0, 1, 1, -3), '393939')
    MakeKbEdge(Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  UDim2.new(0, 1, 1, 0),  '000000')
    MakeKbEdge(Vector2.new(1, 0), UDim2.new(1, -1, 0, 2), UDim2.new(0, 1, 1, -3), '393939')

    local keybindHeader = Instance.new('Frame')
    keybindHeader.Name = 'Header'
    keybindHeader.Size = UDim2.new(1, 0, 0, 20)
    keybindHeader.BackgroundTransparency = 1
    keybindHeader.BorderSizePixel = 0
    keybindHeader.Parent = keybindWindow

    local keybindTitle = Instance.new('TextLabel')
    keybindTitle.Name = 'Title'
    keybindTitle.BackgroundTransparency = 1
    keybindTitle.Position = UDim2.fromOffset(8, 4)
    keybindTitle.Size = UDim2.new(1, -16, 0, 14)
    keybindTitle.Font = Enum.Font.Gotham
    keybindTitle.TextColor3 = Color3.fromHex('FFFFFF')
    keybindTitle.TextSize = 12
    keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
    keybindTitle.TextYAlignment = Enum.TextYAlignment.Center
    keybindTitle.Text = 'Keybinds'
    keybindTitle.Parent = keybindHeader

    local keybindBody = Instance.new('Frame')
    keybindBody.Name = 'Entries'
    keybindBody.BackgroundTransparency = 1
    keybindBody.Position = UDim2.fromOffset(8, 20)
    keybindBody.Size = UDim2.new(1, -16, 0, 0)
    keybindBody.AutomaticSize = Enum.AutomaticSize.Y
    keybindBody.Parent = keybindWindow

    local keybindBodyPad = Instance.new('UIPadding')
    keybindBodyPad.PaddingTop = UDim.new(0, 2)
    keybindBodyPad.PaddingBottom = UDim.new(0, 6)
    keybindBodyPad.Parent = keybindBody

    local keybindBodyList = Instance.new('UIListLayout')
    keybindBodyList.Padding = UDim.new(0, 2)
    keybindBodyList.Parent = keybindBody

    local keybindRows = {}
    local function createKeybindListRow(labelText, optionObj, visibleToggle)
        local row = Instance.new('Frame')
        row.Name = 'Entry'
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 14)
        row.Parent = keybindBody

        local label = Instance.new('TextLabel')
        label.Name = 'NameLabel'
        label.BackgroundTransparency = 1
        label.AnchorPoint = Vector2.new(0, 0.5)
        label.Position = UDim2.new(0, 0, 0.5, 0)
        label.Size = UDim2.new(1, -50, 1, 0)
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromHex('BFC4CC')
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Text = labelText
        label.Parent = row

        local value = Instance.new('TextLabel')
        value.Name = 'KeyLabel'
        value.BackgroundTransparency = 1
        value.AnchorPoint = Vector2.new(1, 0.5)
        value.Position = UDim2.new(1, 0, 0.5, 0)
        value.Size = UDim2.new(0, 48, 1, 0)
        value.Font = Enum.Font.Gotham
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
        value.TextColor3 = curAccent
        value.TextSize = 11
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.TextYAlignment = Enum.TextYAlignment.Center
        value.Text = ''
        value.Parent = row

        table.insert(keybindRows, {
            frame = row,
            option = optionObj,
            label = label,
            value = value,
            visibleToggle = visibleToggle,
        })
    end

    createKeybindListRow('Trigger', State.TriggerKey, State.ShowTriggerInKeybinds)
    createKeybindListRow('AutoShot', State.AutoShotKey, State.ShowAutoShotInKeybinds)
    createKeybindListRow('AutoSort', State.InventoryAutoSortKey, State.ShowAutoSortInKeybinds)
    createKeybindListRow('pSilent', State.AimLock.Key, State.ShowAimLockInKeybinds)
    createKeybindListRow('Silent Auto-Shot', State.AimLock.AutoShotKey, State.ShowAimLockInKeybinds)
    createKeybindListRow('Backtrack', State.Backtrack.Key, State.ShowBacktrackInKeybinds)

    local function keybindIsActive(optionObj)
        local mode = tostring(optionObj.__mode or 'Hold')
        if mode == 'Always' then
            return true
        end
        if mode == 'Toggle' then
            return optionObj.__toggled == true
        end
        return optionObj.__down == true
    end

    local function refreshKeybindWindow()
        if keybindWindow and keybindWindow.Visible == false then
            return
        end
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
        for _, row in ipairs(keybindRows) do
            local showRow = not row.visibleToggle or row.visibleToggle.Value == true
            row.frame.Visible = showRow
            if not showRow then
                row.value.Text = ''
            else
                local mode = tostring(row.option.__mode or 'Hold')
                local active = keybindIsActive(row.option)
                row.value.Text = keyName(row.option.Value)
                row.value.TextColor3 = curAccent
                row.label.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromHex('BFC4CC')
            end
        end
    end

    local function setKeybindWindowVisible()
        if isInitialLoaderActive then
            keybindWindow.Visible = false
            if keybindScreen then
                keybindScreen.Enabled = false
            end
            return
        end
        local show = State.ShowKeybindsList and State.ShowKeybindsList.Value == true
        if keybindScreen then
            keybindScreen.Enabled = show
        end
        if show then
            keybindWindow.Visible = true
            keybindGroup.BackgroundTransparency = 1
            if type(applyOverlayPanelPositions) == 'function' then
                applyOverlayPanelPositions()
            end
            refreshKeybindWindow()
        else
            runLater(0.15, function()
                if not (State.ShowKeybindsList and State.ShowKeybindsList.Value == true) then
                    keybindWindow.Visible = false
                    if keybindScreen then
                        keybindScreen.Enabled = false
                    end
                end
            end)
        end
    end

    attachChangeListener(State.ShowTriggerInKeybinds, refreshKeybindWindow)
    attachChangeListener(State.ShowAutoShotInKeybinds, refreshKeybindWindow)
    attachChangeListener(State.ShowAutoSortInKeybinds, refreshKeybindWindow)
    attachChangeListener(State.ShowAimLockInKeybinds, refreshKeybindWindow)
    attachChangeListener(State.ShowBacktrackInKeybinds, refreshKeybindWindow)
    attachChangeListener(State.ShowKeybindsList, setKeybindWindowVisible)
    if State.KeybindsPanelX then
        attachChangeListener(State.KeybindsPanelX, function()
            if type(applyOverlayPanelPositions) == 'function' then
                applyOverlayPanelPositions()
            end
        end)
    end
    if State.KeybindsPanelY then
        attachChangeListener(State.KeybindsPanelY, function()
            if type(applyOverlayPanelPositions) == 'function' then
                applyOverlayPanelPositions()
            end
        end)
    end
    setKeybindWindowVisible()
    refreshKeybindWindow()
    registerThemeRefresher(refreshKeybindWindow)

    local nextKeybindRefresh = 0
    trackKeybindConnection(safeConnect(RunService.Heartbeat, function()
        if not State.ShowKeybindsList or State.ShowKeybindsList.Value ~= true then
            return
        end
        local now = os.clock()
        if now < nextKeybindRefresh then
            return
        end
        nextKeybindRefresh = now + 0.1
        refreshKeybindWindow()
    end))

    local kbDragging = false
    local kbDragInput = nil
    local kbDragStart = nil
    local kbStartPos = nil

    safeConnect(keybindHeader.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            kbDragging = true
            kbDragStart = input.Position
            kbStartPos = keybindWindow.Position
            safeConnect(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    kbDragging = false
                    if keybindWindow and State.KeybindsPanelX and State.KeybindsPanelY then
                        local pos = keybindWindow.Position
                        pcall(function()
                            State.KeybindsPanelX:SetValue(math.floor(pos.X.Offset + 0.5))
                            State.KeybindsPanelY:SetValue(math.floor(pos.Y.Offset + 0.5))
                        end)
                        if type(requestSaveConfig) == 'function' then
                            requestSaveConfig()
                        end
                    end
                end
            end)
        end
    end)

    safeConnect(keybindHeader.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            kbDragInput = input
        end
    end)

    trackKeybindConnection(safeConnect(UIS.InputChanged, function(input)
        if kbDragging and input == kbDragInput then
            local delta = input.Position - kbDragStart
            keybindWindow.Position = UDim2.new(
                kbStartPos.X.Scale,
                kbStartPos.X.Offset + delta.X,
                kbStartPos.Y.Scale,
                kbStartPos.Y.Offset + delta.Y
            )
        end
    end))


    main = Instance.new('Frame')
    main.Name = 'Main'
    main.Size = UDim2.fromOffset(600, 550)
    main.Position = UDim2.new(0.5, -300, 0.5, -275)
    main.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    main.BorderSizePixel = 0
    main.Visible = false
    main.Parent = menuGroup

    local mainGrad = Instance.new('UIGradient')
    mainGrad.Rotation = 90
    mainGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromHex('212121')),
        ColorSequenceKeypoint.new(1, Color3.fromHex('1A1A1A')),
    })
    mainGrad.Parent = main

    local mainOuterStroke = Instance.new('UIStroke')
    mainOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainOuterStroke.Color = Color3.fromHex('000000')
    mainOuterStroke.Thickness = 1
    mainOuterStroke.LineJoinMode = Enum.LineJoinMode.Miter
    mainOuterStroke.Parent = main

    local mainInner = Instance.new('Frame')
    mainInner.Position = UDim2.new(0, 1, 0, 1)
    mainInner.Size = UDim2.new(1, -2, 1, -2)
    mainInner.BackgroundTransparency = 1
    mainInner.BorderSizePixel = 0
    mainInner.Parent = main

    local mainInnerStroke = Instance.new('UIStroke')
    mainInnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainInnerStroke.Color = Color3.fromHex('393939')
    mainInnerStroke.Thickness = 1
    mainInnerStroke.LineJoinMode = Enum.LineJoinMode.Miter
    mainInnerStroke.Parent = mainInner

    local headerTopLine = Instance.new('Frame')
    headerTopLine.Name = 'TopAccentLine'
    headerTopLine.Size = UDim2.new(1, -2, 0, 1)
    headerTopLine.Position = UDim2.new(0, 1, 0, 1)
    headerTopLine.BorderSizePixel = 0
    headerTopLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    headerTopLine.ZIndex = 10
    headerTopLine.Parent = main
    local headerGradient = Instance.new('UIGradient')
    headerGradient.Parent = headerTopLine
    registerAccentGradient(headerGradient)

    mainTargetSize = main.Size
    mainTargetPos = main.Position

    header = Instance.new('Frame')
    header.Name = 'Header'
    header.Size = UDim2.new(1, 0, 0, 32)
    header.BackgroundTransparency = 1
    header.BorderSizePixel = 0
    header.Parent = main

    headerBackdrop = header

    local title = Instance.new('TextLabel')
    title.Name = 'Title'
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(10, 8)
    title.Size = UDim2.new(0, 200, 0, 18)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Center
    title.Text = 'Bomzhood Hub'
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = header
    title.ZIndex = 2

    local subtitle = Instance.new('TextLabel')
    subtitle.Name = 'Subtitle'
    subtitle.BackgroundTransparency = 1
    subtitle.Position = UDim2.fromOffset(105, 9)
    subtitle.Size = UDim2.new(0, 120, 0, 16)
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextColor3 = Color3.fromHex('8C8F99')
    subtitle.TextSize = 11
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.TextYAlignment = Enum.TextYAlignment.Center
    subtitle.Text = ''
    subtitle.Visible = false
    subtitle.Parent = header
    subtitle.ZIndex = 2

    closeBtn = Instance.new('TextButton')
    closeBtn.Name = 'Close'
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.Position = UDim2.new(1, -8, 0, 8)
    closeBtn.Size = UDim2.fromOffset(16, 16)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 10
    closeBtn.Text = 'X'
    closeBtn.TextColor3 = Color3.fromHex('8C8F99')
    closeBtn.BackgroundColor3 = Color3.fromHex('191919')
    closeBtn.AutoButtonColor = false
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = header
    closeBtn.ZIndex = 3

    local closeOuter = Instance.new('UIStroke')
    closeOuter.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    closeOuter.Color = Color3.fromHex('000105')
    closeOuter.Thickness = 1
    closeOuter.Parent = closeBtn

    safeConnect(closeBtn.MouseEnter, function()
        tween(closeBtn, 0.12, { BackgroundColor3 = Color3.fromHex('FF8585'), TextColor3 = Color3.fromRGB(255, 255, 255) })
    end)
    safeConnect(closeBtn.MouseLeave, function()
        tween(closeBtn, 0.18, { BackgroundColor3 = Color3.fromHex('191919'), TextColor3 = Color3.fromHex('8C8F99') })
    end)

    content = Instance.new('Frame')
    content.Name = 'Content'
    content.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    content.BackgroundTransparency = 0
    content.Position = UDim2.new(0, 5, 0, 32)
    content.Size = UDim2.new(1, -10, 1, -37)
    content.BorderSizePixel = 0
    content.Parent = main

    local contentGrad = Instance.new('UIGradient')
    contentGrad.Rotation = 90
    contentGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromHex('161616')),
        ColorSequenceKeypoint.new(1, Color3.fromHex('101010')),
    })
    contentGrad.Parent = content

    local function MakeContentEdge(anchor, pos, sz, col, zidx)
        local e = Instance.new('Frame')
        e.AnchorPoint = anchor
        e.Position = pos
        e.Size = sz
        e.BackgroundColor3 = Color3.fromHex(col)
        e.BorderSizePixel = 0
        e.ZIndex = zidx or 10
        e.Parent = content
    end
    MakeContentEdge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(0, 1, 1, 0),   '000000', 10)
    MakeContentEdge(Vector2.new(0, 0), UDim2.new(0, 1, 0, 1),  UDim2.new(0, 1, 1, -2),  '393939', 10)
    MakeContentEdge(Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  UDim2.new(0, 1, 1, 0),   '000000', 10)
    MakeContentEdge(Vector2.new(1, 0), UDim2.new(1, -1, 0, 1), UDim2.new(0, 1, 1, -2),  '393939', 10)
    MakeContentEdge(Vector2.new(0, 1), UDim2.new(0, 0, 1, 0),  UDim2.new(1, 0, 0, 1),   '000000', 10)
    MakeContentEdge(Vector2.new(0, 1), UDim2.new(0, 1, 1, -1), UDim2.new(1, -2, 0, 1),  '393939', 10)

    body = content

    tabBar = Instance.new('Frame')
    tabBar.Name = 'TabBar'
    tabBar.Position = UDim2.new(0, 0, 0, 0)
    tabBar.Size = UDim2.new(1, 0, 0, 24)
    tabBar.BorderSizePixel = 0
    tabBar.BackgroundTransparency = 1
    tabBar.ZIndex = 5
    tabBar.Parent = content

    local tabBarLayout = Instance.new('UIListLayout')
    tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
    tabBarLayout.Padding = UDim.new(0, 0)
    tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    tabBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabBarLayout.Parent = tabBar

    pagesRoot = Instance.new('Frame')
    pagesRoot.Name = 'Pages'
    pagesRoot.BackgroundTransparency = 1
    pagesRoot.Position = UDim2.new(0, 0, 0, 24)
    pagesRoot.Size = UDim2.new(1, 0, 1, -24)
    pagesRoot.BorderSizePixel = 0
    pagesRoot.Parent = content

    local rWindow = createCoincideWindow({
        Name = 'TriggerRangePanel',
        Title = 'Weapon Range',
        Width = 248,
        Height = 290,
        HasClose = true,
        Parent = menuGroup,
    })
    rangePanel = rWindow.Outer
    rangePanel.Visible = false
    local rangePanelClose = rWindow.CloseButton
    local rangePanelHeader = rWindow.Header
    local rangePanelTitle = rWindow.TitleLabel

    rangePanelBody = Instance.new('Frame')
    rangePanelBody.Name = 'Body'
    rangePanelBody.BackgroundTransparency = 1
    rangePanelBody.Position = UDim2.fromOffset(0, 0)
    rangePanelBody.Size = UDim2.new(1, 0, 1, 0)
    rangePanelBody.Parent = rWindow.Content

    local rangePanelPad = Instance.new('UIPadding')
    rangePanelPad.PaddingTop = UDim.new(0, 8)
    rangePanelPad.PaddingLeft = UDim.new(0, 8)
    rangePanelPad.PaddingRight = UDim.new(0, 8)
    rangePanelPad.PaddingBottom = UDim.new(0, 8)
    rangePanelPad.Parent = rangePanelBody

    local rangePanelLayout = Instance.new('UIListLayout')
    rangePanelLayout.Padding = UDim.new(0, 8)
    rangePanelLayout.Parent = rangePanelBody

    local RANGE_PANEL_GAP = 6

    syncRangePanelPosition = function()
        rangePanel.Position = UDim2.new(
            main.Position.X.Scale,
            main.Position.X.Offset + main.Size.X.Offset + RANGE_PANEL_GAP,
            main.Position.Y.Scale,
            main.Position.Y.Offset
        )
    end

    setRangePanelVisible = function(show)
        rangePanelOpen = show == true
        rangePanel.Visible = rangePanelOpen
        if rangePanelOpen then
            syncRangePanelPosition()
        end
        if missShotsUi.open and missShotsUi.syncPosition then
            missShotsUi.syncPosition()
        end
        if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
            silentMissShotsUi.syncPosition()
        end
    end

    safeConnect(rangePanelClose.MouseButton1Click, function()
        setRangePanelVisible(false)
    end)
    safeConnect(main:GetPropertyChangedSignal('Position'), function()
        if rangePanelOpen then
            syncRangePanelPosition()
        end
        if missShotsUi.open and missShotsUi.syncPosition then
            missShotsUi.syncPosition()
        end
        if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
            silentMissShotsUi.syncPosition()
        end
    end)
    safeConnect(main:GetPropertyChangedSignal('Size'), function()
        if rangePanelOpen then
            syncRangePanelPosition()
        end
        if missShotsUi.open and missShotsUi.syncPosition then
            missShotsUi.syncPosition()
        end
        if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
            silentMissShotsUi.syncPosition()
        end
    end)

    do
        local mWindow = createCoincideWindow({
            Name = 'TriggerMissShotsPanel',
            Title = 'Miss Shots',
            Width = 248,
            Height = 160,
            HasClose = true,
            Parent = menuGroup,
        })
        local panel = mWindow.Outer
        panel.Visible = false
        missShotsUi.panel = panel

        local body = Instance.new('Frame')
        body.Name = 'Body'
        body.BackgroundTransparency = 1
        body.Position = UDim2.fromOffset(0, 0)
        body.Size = UDim2.new(1, 0, 1, 0)
        body.Parent = mWindow.Content
        missShotsUi.body = body

        local pad = Instance.new('UIPadding')
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.Parent = body

        local layout = Instance.new('UIListLayout')
        layout.Padding = UDim.new(0, 8)
        layout.Parent = body

        local GAP = 6
        missShotsUi.syncPosition = function()
            local yOffset = main.Position.Y.Offset
            if rangePanelOpen and rangePanel then
                yOffset = yOffset + rangePanel.Size.Y.Offset + GAP
            end
            panel.Position = UDim2.new(
                main.Position.X.Scale,
                main.Position.X.Offset + main.Size.X.Offset + GAP,
                main.Position.Y.Scale,
                yOffset
            )
        end

        missShotsUi.setVisible = function(show)
            missShotsUi.open = show == true
            panel.Visible = missShotsUi.open
            if missShotsUi.open then
                missShotsUi.syncPosition()
            end
            if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                silentMissShotsUi.syncPosition()
            end
        end

        safeConnect(mWindow.CloseButton.MouseButton1Click, function()
            missShotsUi.setVisible(false)
        end)
    end

    do
        local smWindow = createCoincideWindow({
            Name = 'SilentMissShotsPanel',
            Title = 'pSilent Miss Shots',
            Width = 248,
            Height = 160,
            HasClose = true,
            Parent = menuGroup,
        })
        local panel = smWindow.Outer
        panel.Visible = false
        silentMissShotsUi.panel = panel

        local body = Instance.new('Frame')
        body.Name = 'Body'
        body.BackgroundTransparency = 1
        body.Position = UDim2.fromOffset(0, 0)
        body.Size = UDim2.new(1, 0, 1, 0)
        body.Parent = smWindow.Content
        silentMissShotsUi.body = body

        local pad = Instance.new('UIPadding')
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.Parent = body

        local layout = Instance.new('UIListLayout')
        layout.Padding = UDim.new(0, 8)
        layout.Parent = body

        local GAP = 6
        silentMissShotsUi.syncPosition = function()
            local yOffset = main.Position.Y.Offset
            if rangePanelOpen and rangePanel then
                yOffset = yOffset + rangePanel.Size.Y.Offset + GAP
            end
            if missShotsUi.open and missShotsUi.panel then
                yOffset = yOffset + missShotsUi.panel.Size.Y.Offset + GAP
            end
            panel.Position = UDim2.new(
                main.Position.X.Scale,
                main.Position.X.Offset + main.Size.X.Offset + GAP,
                main.Position.Y.Scale,
                yOffset
            )
        end

        silentMissShotsUi.setVisible = function(show)
            silentMissShotsUi.open = show == true
            panel.Visible = silentMissShotsUi.open
            if silentMissShotsUi.open then
                silentMissShotsUi.syncPosition()
            end
        end

        safeConnect(smWindow.CloseButton.MouseButton1Click, function()
            silentMissShotsUi.setVisible(false)
        end)
    end

    -- Animated Notifications Container (Right Center)
    local notifContainer = Instance.new('Frame')
    notifContainer.Name = 'NotificationContainer'
    notifContainer.AnchorPoint = Vector2.new(1, 0.5)
    notifContainer.Position = UDim2.new(1, -20, 0.5, 0)
    notifContainer.Size = UDim2.fromOffset(330, 420)
    notifContainer.BackgroundTransparency = 1
    notifContainer.Parent = notifScreen

    local notifLayout = Instance.new('UIListLayout')
    notifLayout.FillDirection = Enum.FillDirection.Vertical
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    notifLayout.Padding = UDim.new(0, 8)
    notifLayout.Parent = notifContainer

    showNotification = function(titleText, messageText, duration)
        duration = duration or 3.5
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent

        local wrapper = Instance.new('Frame')
        wrapper.Name = 'NotifWrapper'
        wrapper.Size = UDim2.new(0, 0, 0, 0)
        wrapper.AutomaticSize = Enum.AutomaticSize.XY
        wrapper.BackgroundTransparency = 1
        wrapper.BorderSizePixel = 0
        wrapper.Parent = notifContainer

        local outer = Instance.new('Frame')
        outer.Name = 'Notification'
        outer.AnchorPoint = Vector2.new(1, 0)
        outer.Position = UDim2.new(1, 80, 0, 0)
        outer.Size = UDim2.new(0, 0, 0, 0)
        outer.AutomaticSize = Enum.AutomaticSize.XY
        outer.BackgroundColor3 = Color3.fromHex('000000')
        outer.BorderSizePixel = 0
        outer.Parent = wrapper

        local inline = Instance.new('Frame')
        inline.Name = 'Inline'
        inline.Position = UDim2.new(0, 1, 0, 1)
        inline.Size = UDim2.new(1, -2, 1, -2)
        inline.AutomaticSize = Enum.AutomaticSize.XY
        inline.BackgroundColor3 = Color3.fromHex('393939')
        inline.BorderSizePixel = 0
        inline.Parent = outer

        local bg = Instance.new('Frame')
        bg.Name = 'Background'
        bg.Position = UDim2.new(0, 1, 0, 1)
        bg.Size = UDim2.new(1, -2, 1, -2)
        bg.AutomaticSize = Enum.AutomaticSize.XY
        bg.BackgroundColor3 = Color3.fromHex('FFFFFF')
        bg.BorderSizePixel = 0
        bg.Parent = inline

        local grad = Instance.new('UIGradient')
        grad.Rotation = 90
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('262626')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('191919')),
        })
        grad.Parent = bg

        local liner = Instance.new('Frame')
        liner.Name = 'Liner'
        liner.Position = UDim2.new(0, 2, 0, 2)
        liner.Size = UDim2.new(0, 2, 1, -4)
        liner.BackgroundColor3 = curAccent
        liner.BorderSizePixel = 0
        liner.ZIndex = 5
        liner.Parent = outer

        local durationLiner = Instance.new('Frame')
        durationLiner.Name = 'DurationLiner'
        durationLiner.Position = UDim2.new(0, 2, 1, -2)
        durationLiner.Size = UDim2.new(1, -4, 0, 1)
        durationLiner.BackgroundColor3 = curAccent
        durationLiner.BorderSizePixel = 0
        durationLiner.ZIndex = 6
        durationLiner.Parent = outer

        local contentFrame = Instance.new('Frame')
        contentFrame.Name = 'Content'
        contentFrame.Position = UDim2.new(0, 8, 0, 4)
        contentFrame.Size = UDim2.new(0, 0, 0, 0)
        contentFrame.AutomaticSize = Enum.AutomaticSize.XY
        contentFrame.BackgroundTransparency = 1
        contentFrame.BorderSizePixel = 0
        contentFrame.Parent = bg

        local cPad = Instance.new('UIPadding')
        cPad.PaddingTop = UDim.new(0, 2)
        cPad.PaddingBottom = UDim.new(0, 6)
        cPad.PaddingLeft = UDim.new(0, 2)
        cPad.PaddingRight = UDim.new(0, 14)
        cPad.Parent = contentFrame

        local cList = Instance.new('UIListLayout')
        cList.FillDirection = Enum.FillDirection.Vertical
        cList.Padding = UDim.new(0, 2)
        cList.Parent = contentFrame

        local titleLabel = Instance.new('TextLabel')
        titleLabel.Name = 'Title'
        titleLabel.BackgroundTransparency = 1
        titleLabel.Size = UDim2.new(0, 0, 0, 16)
        titleLabel.AutomaticSize = Enum.AutomaticSize.X
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 12
        titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.RichText = true
        titleLabel.Text = titleText or 'Notification'
        titleLabel.Parent = contentFrame

        if messageText and messageText ~= '' then
            local msgLabel = Instance.new('TextLabel')
            msgLabel.Name = 'Message'
            msgLabel.BackgroundTransparency = 1
            msgLabel.Size = UDim2.new(0, 0, 0, 14)
            msgLabel.AutomaticSize = Enum.AutomaticSize.XY
            msgLabel.Font = Enum.Font.Gotham
            msgLabel.TextSize = 11
            msgLabel.TextColor3 = Color3.fromHex('A0A0A0')
            msgLabel.TextXAlignment = Enum.TextXAlignment.Left
            msgLabel.RichText = true
            msgLabel.Text = messageText
            msgLabel.Parent = contentFrame
        end

        -- Slide In
        tween(outer, 0.22, { Position = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        -- Progress bar countdown
        task.delay(0.05, function()
            if durationLiner and durationLiner.Parent then
                tween(durationLiner, duration, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
            end
        end)

        -- Slide out and destroy
        runLater(duration + 0.05, function()
            if outer and outer.Parent then
                tween(outer, 0.18, { Position = UDim2.new(1, 80, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                runLater(0.2, function()
                    pcall(function() wrapper:Destroy() end)
                end)
            end
        end)
    end

    -- Automatic Staff/Admin Detection Notification
    task.spawn(function()
        local Players = game:GetService('Players')
        local GroupService = game:GetService('GroupService')
        local LocalPlayer = Players.LocalPlayer or Players:WaitForChild('LocalPlayer', 10)
        local ADMIN_GROUPS = { 605595634, 925309458, 35897948 }
        local ADMIN_USERIDS = {
            [731857328] = true,
            [1786831293] = true,
            [541093005] = true,
            [9467396201] = true,
        }

        local STAFF_ROLES_KEYWORDS = {
            ['owner'] = 'OWNER',
            ['developer'] = 'DEVELOPER',
            ['dev'] = 'DEVELOPER',
            ['ceo'] = 'CEO',
            ['staff director'] = 'STAFF DIRECTOR',
            ['staffdirector'] = 'STAFF DIRECTOR',
            ['executive'] = 'EXECUTIVE',
            ['manager'] = 'MANAGER',
            ['admin'] = 'ADMIN',
            ['administrator'] = 'ADMIN',
            ['staff'] = 'STAFF',
            ['head admin'] = 'HEAD ADMIN',
            ['senior admin'] = 'SENIOR ADMIN',
            ['moderator'] = 'MODERATOR',
            ['mod'] = 'MODERATOR',
        }

        local IGNORED_KEYWORDS = {
            'content creator', 'creator', 'vip', 'member', 'guest', 'media', 'youtuber', 'streamer'
        }

        local function isIgnored(roleName)
            if type(roleName) ~= 'string' then return true end
            local lower = string.lower(roleName)
            for _, kw in ipairs(IGNORED_KEYWORDS) do
                if string.find(lower, kw, 1, true) then
                    return true
                end
            end
            return false
        end

        local staffCache = {}

        local function getPlayerStaffRole(plr)
            if not plr or plr == LocalPlayer then
                return nil
            end
            if ADMIN_USERIDS[plr.UserId] then
                return 'OWNER'
            end
            if staffCache[plr.UserId] ~= nil then
                return staffCache[plr.UserId] or nil
            end

            -- Check player attributes for assigned staff tags/roles
            pcall(function()
                for _, attrName in ipairs({ 'StaffRole', 'Role', 'Rank', 'Tag', 'Title', 'AdminRole' }) do
                    local val = plr:GetAttribute(attrName)
                    if type(val) == 'string' and val ~= '' and not isIgnored(val) then
                        local lower = string.lower(val)
                        for kw, label in pairs(STAFF_ROLES_KEYWORDS) do
                            if string.find(lower, kw, 1, true) then
                                staffCache[plr.UserId] = label
                                return label
                            end
                        end
                    end
                end
            end)

            -- Check Roblox group ranks and role names via GetRoleInGroup
            for _, groupId in ipairs(ADMIN_GROUPS) do
                local okRole, role = pcall(function() return plr:GetRoleInGroup(groupId) end)
                if okRole and type(role) == 'string' and role ~= '' and not isIgnored(role) and not string.find(role, 'Loading') then
                    local lowerRole = string.lower(role)
                    for kw, label in pairs(STAFF_ROLES_KEYWORDS) do
                        if string.find(lowerRole, kw, 1, true) then
                            staffCache[plr.UserId] = label
                            return label
                        end
                    end
                    local okRank, rank = pcall(function() return plr:GetRankInGroup(groupId) end)
                    if okRank and type(rank) == 'number' and rank >= 10 then
                        local uRole = string.upper(role)
                        staffCache[plr.UserId] = uRole
                        return uRole
                    end
                end
            end

            -- Asynchronous / Fallback check via GroupService:GetGroupsAsync
            local okAsync, groups = pcall(function() return GroupService:GetGroupsAsync(plr.UserId) end)
            if okAsync and type(groups) == 'table' then
                for _, g in ipairs(groups) do
                    local gId = g.Id
                    local gName = string.lower(tostring(g.Name or ''))
                    local roleName = tostring(g.Role or '')
                    local lowerRole = string.lower(roleName)

                    if not isIgnored(roleName) then
                        local isTargetGroup = false
                        for _, targetId in ipairs(ADMIN_GROUPS) do
                            if gId == targetId then
                                isTargetGroup = true
                                break
                            end
                        end
                        if not isTargetGroup then
                            if string.find(gName, 'staff') or string.find(gName, 'admin') then
                                isTargetGroup = true
                            end
                        end

                        if isTargetGroup then
                            for kw, label in pairs(STAFF_ROLES_KEYWORDS) do
                                if string.find(lowerRole, kw, 1, true) then
                                    staffCache[plr.UserId] = label
                                    return label
                                end
                            end
                            if g.Rank and g.Rank >= 10 then
                                local uRole = string.upper(roleName)
                                staffCache[plr.UserId] = uRole
                                return uRole
                            end
                        end
                    end
                end
            end

            staffCache[plr.UserId] = false
            return nil
        end

        local function notifyStaffOnServer()
            if State.StaffDetectorEnabled and State.StaffDetectorEnabled.Value == false then
                return
            end
            local staffEntries = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local role = getPlayerStaffRole(plr)
                    if role then
                        local display = tostring(plr.DisplayName or plr.Name)
                        table.insert(staffEntries, string.format('%s(<b>%s</b>)', display, string.upper(role)))
                    end
                end
            end

            if #staffEntries > 0 then
                local message = 'На сервере обнаружен стафф ' .. table.concat(staffEntries, ', ') .. '!'
                if type(showNotification) == 'function' then
                    showNotification('Staff Alert', message, 6.0)
                end
            end
        end

        task.spawn(function()
            task.wait(1.0)
            notifyStaffOnServer()
        end)

        safeConnect(Players.PlayerAdded, function(plr)
            if State.StaffDetectorEnabled and State.StaffDetectorEnabled.Value == false then
                return
            end
            task.wait(1)
            local role = getPlayerStaffRole(plr)
            if role then
                local display = tostring(plr.DisplayName or plr.Name)
                local message = string.format('На сервере обнаружен стафф %s(<b>%s</b>)!', display, string.upper(role))
                if type(showNotification) == 'function' then
                    showNotification('Staff Alert', message, 6.0)
                end
            end
        end)

        safeConnect(Players.PlayerRemoving, function(plr)
            if plr then
                staffCache[plr.UserId] = nil
            end
        end)

        attachChangeListener(State.StaffDetectorEnabled, function(val)
            if val == true then
                task.spawn(notifyStaffOnServer)
            end
        end)
    end)

    end)()

    local applyLayoutSizes
    local createPage, createSection, createThemeGroup, createToggle, createSlider, createColorRow
    local createToggleColorRow, createWhitelistDropdown, createSinglePlayerDropdown, createStringDropdown, createCycleOptionRow
    local createInventorySlotDropdownRow, createKeybindProp, createButton, pages
    local refreshRows

    local runtimeConnections = {}
    local function trackConnection(conn)
        if conn then
            table.insert(runtimeConnections, conn)
        end
        return conn
    end
    local keybindCapture = nil

    ;(function()
    createPage = function(name)
        local page = Instance.new('Frame')
        page.Name = 'Page_' .. (name or 'Page')
        page.BackgroundTransparency = 1
        page.Position = UDim2.new(0, 0, 0, 0)
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BorderSizePixel = 0
        page.Visible = false
        page.Parent = pagesRoot

        local pagePad = Instance.new('UIPadding')
        pagePad.PaddingLeft = UDim.new(0, 6)
        pagePad.PaddingRight = UDim.new(0, 6)
        pagePad.PaddingTop = UDim.new(0, 11)
        pagePad.PaddingBottom = UDim.new(0, 6)
        pagePad.Parent = page

        local leftCol = Instance.new('ScrollingFrame')
        leftCol.Name = 'Left'
        leftCol.BackgroundTransparency = 1
        leftCol.BorderSizePixel = 0
        leftCol.Position = UDim2.new(0, 0, 0, -2)
        leftCol.Size = UDim2.new(0.5, -3, 1, 2)
        leftCol.ScrollBarThickness = 0
        leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
        leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
        leftCol.ClipsDescendants = true
        leftCol.Parent = page

        local leftLayout = Instance.new('UIListLayout')
        leftLayout.Padding = UDim.new(0, 6)
        leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
        leftLayout.Parent = leftCol

        local leftPad = Instance.new('UIPadding')
        leftPad.PaddingTop = UDim.new(0, 4)
        leftPad.PaddingBottom = UDim.new(0, 6)
        leftPad.Parent = leftCol

        local rightCol = Instance.new('ScrollingFrame')
        rightCol.Name = 'Right'
        rightCol.BackgroundTransparency = 1
        rightCol.BorderSizePixel = 0
        rightCol.AnchorPoint = Vector2.new(1, 0)
        rightCol.Position = UDim2.new(1, 0, 0, -2)
        rightCol.Size = UDim2.new(0.5, -3, 1, 2)
        rightCol.ScrollBarThickness = 0
        rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
        rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
        rightCol.ClipsDescendants = true
        rightCol.Parent = page

        local rightLayout = Instance.new('UIListLayout')
        rightLayout.Padding = UDim.new(0, 6)
        rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rightLayout.Parent = rightCol

        local rightPad = Instance.new('UIPadding')
        rightPad.PaddingTop = UDim.new(0, 4)
        rightPad.PaddingBottom = UDim.new(0, 6)
        rightPad.Parent = rightCol

        return {
            root = page,
            left = leftCol,
            right = rightCol,
            nextColumn = 1
        }
    end

    createSection = function(page, heading, column, opts)
        opts = type(opts) == 'table' and opts or nil
        local pageObj = page
        local targetColumn = pageObj.left
        if column == 'right' then
            targetColumn = pageObj.right
        elseif column == 'left' then
            targetColumn = pageObj.left
        elseif pageObj.nextColumn == 2 then
            targetColumn = pageObj.right
        end
        if not column then
            pageObj.nextColumn = pageObj.nextColumn == 1 and 2 or 1
        end

        local section = Instance.new('Frame')
        section.Name = 'Section_' .. tostring(heading)
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.BackgroundTransparency = 1
        section.BorderSizePixel = 0
        section.Parent = targetColumn

        local function Edge(Anchor, Pos, Sz, Col, ZIdx)
            local ed = Instance.new('Frame')
            ed.Parent = section
            ed.AnchorPoint = Anchor
            ed.Position = Pos
            ed.Size = Sz
            ed.BackgroundColor3 = typeof(Col) == 'string' and Color3.fromHex(Col) or Col
            ed.BorderSizePixel = 0
            ed.ZIndex = ZIdx or 5
        end

        Edge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(1, 0, 0, 1),  '000000', 5)
        local topLine = Instance.new('Frame')
        topLine.Name = 'TopLine'
        topLine.Parent = section
        topLine.AnchorPoint = Vector2.new(0, 0)
        topLine.Position = UDim2.new(0, 0, 0, 1)
        topLine.Size = UDim2.new(1, 0, 0, 1)
        topLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        topLine.BorderSizePixel = 0
        topLine.ZIndex = 5
        local secTopGrad = Instance.new('UIGradient')
        secTopGrad.Parent = topLine
        registerAccentGradient(secTopGrad)

        Edge(Vector2.new(0, 1), UDim2.new(0, 0, 1, 0),  UDim2.new(1, 0, 0, 1),  '000000', 5)
        Edge(Vector2.new(0, 1), UDim2.new(0, 1, 1, -1), UDim2.new(1, -2, 0, 1), '393939', 5)
        Edge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(0, 1, 1, 0),  '000000', 5)
        Edge(Vector2.new(0, 0), UDim2.new(0, 1, 0, 2),  UDim2.new(0, 1, 1, -3), '393939', 5)
        Edge(Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  UDim2.new(0, 1, 1, 0),  '000000', 5)
        Edge(Vector2.new(1, 0), UDim2.new(1, -1, 0, 2), UDim2.new(0, 1, 1, -3), '393939', 5)

        local titleCover = Instance.new('Frame')
        titleCover.Name = 'TitleCover'
        titleCover.Position = UDim2.new(0, 7, 0, 0)
        titleCover.Size = UDim2.new(0, 0, 0, 2)
        titleCover.BackgroundColor3 = Color3.fromHex('161616')
        titleCover.BorderSizePixel = 0
        titleCover.ZIndex = 6
        titleCover.Parent = section

        local titleLabel = Instance.new('TextLabel')
        titleLabel.Name = 'Title'
        titleLabel.BackgroundTransparency = 1
        titleLabel.AnchorPoint = Vector2.new(0, 0.5)
        titleLabel.Position = UDim2.new(0, 11, 0, 2)
        titleLabel.Size = UDim2.new(0, 0, 0, 14)
        titleLabel.AutomaticSize = Enum.AutomaticSize.X
        titleLabel.Font = Enum.Font.Gotham
        titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLabel.TextSize = 12
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextYAlignment = Enum.TextYAlignment.Center
        titleLabel.Text = tostring(heading)
        titleLabel.Parent = section
        titleLabel.ZIndex = 7

        local function updateCover()
            titleCover.Size = UDim2.new(0, titleLabel.AbsoluteSize.X + 8, 0, 2)
        end
        titleLabel:GetPropertyChangedSignal('AbsoluteSize'):Connect(updateCover)
        task.defer(updateCover)

        if opts and opts.headerDropdown then
            local hd = opts.headerDropdown
            createStringDropdown(section, hd.caption, hd.option, hd.values, { header = true })
        end

        local content = Instance.new('Frame')
        content.Name = 'Body'
        content.BackgroundTransparency = 1
        content.Position = UDim2.new(0, 8, 0, 12)
        content.Size = UDim2.new(1, -16, 0, 0)
        content.AutomaticSize = Enum.AutomaticSize.Y
        content.Parent = section

        local layout = Instance.new('UIListLayout')
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = content

        local pad = Instance.new('UIPadding')
        pad.PaddingBottom = UDim.new(0, 8)
        pad.Parent = content

        return content
    end

    createThemeGroup = function(parent, title)
        local wrap = Instance.new('Frame')
        wrap.BackgroundTransparency = 1
        wrap.Size = UDim2.new(1, 0, 0, 0)
        wrap.AutomaticSize = Enum.AutomaticSize.Y
        wrap.Parent = parent

        local layout = Instance.new('UIListLayout')
        layout.Padding = UDim.new(0, 6)
        layout.Parent = wrap

        local header = Instance.new('TextLabel')
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, 0, 0, 16)
        header.Font = Enum.Font.Gotham
        header.TextColor3 = Color3.fromHex('8C8F99')
        header.TextSize = 10
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Text = string.upper(title)
        header.Parent = wrap

        local body = Instance.new('Frame')
        body.Name = 'ThemeGroupBody'
        body.BackgroundTransparency = 1
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.Parent = wrap

        local bodyLayout = Instance.new('UIListLayout')
        bodyLayout.Padding = UDim.new(0, 6)
        bodyLayout.Parent = body

        return body
    end

    createToggle = function(parent, caption, toggleObj, detail)
        local row = Instance.new('TextButton')
        row.Name = 'Toggle_' .. tostring(caption)
        row.Size = UDim2.new(1, 0, 0, 16)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = ''
        row.Parent = parent

        local box = Instance.new('Frame')
        box.Name = 'Box'
        box.AnchorPoint = Vector2.new(0, 0.5)
        box.Position = UDim2.new(0, 0, 0.5, 0)
        box.Size = UDim2.fromOffset(14, 14)
        box.BackgroundColor3 = Color3.fromHex('000000')
        box.BorderSizePixel = 0
        box.Parent = row

        local boxGray = Instance.new('Frame')
        boxGray.Name = 'Gray'
        boxGray.Position = UDim2.new(0, 1, 0, 1)
        boxGray.Size = UDim2.new(1, -2, 1, -2)
        boxGray.BackgroundColor3 = Color3.fromHex('393939')
        boxGray.BorderSizePixel = 0
        boxGray.Parent = box

        local boxInside = Instance.new('Frame')
        boxInside.Name = 'Inside'
        boxInside.Position = UDim2.new(0, 1, 0, 1)
        boxInside.Size = UDim2.new(1, -2, 1, -2)
        boxInside.BackgroundColor3 = Color3.fromHex('131313')
        boxInside.BorderSizePixel = 0
        boxInside.Parent = boxGray

        local fill = Instance.new('Frame')
        fill.Name = 'Fill'
        fill.AnchorPoint = Vector2.new(0.5, 0.5)
        fill.Position = UDim2.new(0.5, 0, 0.5, 0)
        fill.Size = UDim2.new(0, 0, 0, 0)
        fill.BackgroundColor3 = palette.accent
        fill.BackgroundTransparency = 1
        fill.BorderSizePixel = 0
        fill.Parent = boxInside
        registerAccentBar(fill)

        local label = Instance.new('TextLabel')
        label.Name = 'Label'
        label.AnchorPoint = Vector2.new(0, 0.5)
        label.Position = UDim2.new(0, 20, 0.5, 0)
        label.Size = UDim2.new(1, -20, 1, 0)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextColor3 = Color3.fromHex('8C8F99')
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Text = caption
        label.Parent = row

        local function render()
            local state = toggleObj.Value == true
            fill.BackgroundColor3 = palette.accent
            fill.BackgroundTransparency = state and 0 or 1
            fill.Size = state and UDim2.new(1, -2, 1, -2) or UDim2.new(0, 0, 0, 0)
            label.TextColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromHex('8C8F99')
        end

        safeConnect(row.MouseButton1Click, function()
            toggleObj:SetValue(not (toggleObj.Value == true))
            render()
        end)

        attachChangeListener(toggleObj, render)
        render()
        registerThemeRefresher(render)
        return row
    end

    local function roundStep(value, minValue, maxValue, step)
        local v = math.clamp(value, minValue, maxValue)
        local s = step or 1
        if s > 0 then
            v = math.floor((v / s) + 0.5) * s
        end
        return math.clamp(v, minValue, maxValue)
    end

    createSlider = function(parent, caption, optionObj, minValue, maxValue, step, suffix)
        local container = Instance.new('Frame')
        container.Name = 'Slider_' .. tostring(caption)
        container.Size = UDim2.new(1, 0, 0, 26)
        container.BackgroundTransparency = 1
        container.BorderSizePixel = 0
        container.Parent = parent

        local label = Instance.new('TextLabel')
        label.Name = 'Label'
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 0, 0, 0)
        label.Size = UDim2.new(1, -60, 0, 14)
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Text = caption
        label.Parent = container

        local valLbl = Instance.new('TextLabel')
        valLbl.Name = 'Value'
        valLbl.AnchorPoint = Vector2.new(1, 0)
        valLbl.Position = UDim2.new(1, -26, 0, 0)
        valLbl.Size = UDim2.new(0, 30, 0, 14)
        valLbl.BackgroundTransparency = 1
        valLbl.Font = Enum.Font.Gotham
        valLbl.TextSize = 12
        valLbl.TextColor3 = Color3.fromHex('8C8F99')
        valLbl.TextXAlignment = Enum.TextXAlignment.Right
        valLbl.TextYAlignment = Enum.TextYAlignment.Center
        valLbl.Parent = container

        local btnContainer = Instance.new('Frame')
        btnContainer.Name = 'Buttons'
        btnContainer.AnchorPoint = Vector2.new(1, 0)
        btnContainer.Position = UDim2.new(1, 0, 0, 0)
        btnContainer.Size = UDim2.new(0, 24, 0, 14)
        btnContainer.BackgroundTransparency = 1
        btnContainer.Parent = container

        local minusBtn = Instance.new('TextButton')
        minusBtn.Size = UDim2.new(0, 11, 1, 0)
        minusBtn.BackgroundTransparency = 1
        minusBtn.Text = '−'
        minusBtn.Font = Enum.Font.Gotham
        minusBtn.TextSize = 12
        minusBtn.TextColor3 = Color3.fromHex('8C8F99')
        minusBtn.Parent = btnContainer

        local plusBtn = Instance.new('TextButton')
        plusBtn.Position = UDim2.new(0, 13, 0, 0)
        plusBtn.Size = UDim2.new(0, 11, 1, 0)
        plusBtn.BackgroundTransparency = 1
        plusBtn.Text = '+'
        plusBtn.Font = Enum.Font.Gotham
        plusBtn.TextSize = 12
        plusBtn.TextColor3 = Color3.fromHex('8C8F99')
        plusBtn.Parent = btnContainer

        local track = Instance.new('TextButton')
        track.Name = 'Track'
        track.AnchorPoint = Vector2.new(0, 1)
        track.Position = UDim2.new(0, 0, 1, 0)
        track.Size = UDim2.new(1, 0, 0, 10)
        track.BackgroundColor3 = Color3.fromHex('000000')
        track.BorderSizePixel = 0
        track.AutoButtonColor = false
        track.Text = ''
        track.Parent = container

        local trackGray = Instance.new('Frame')
        trackGray.Position = UDim2.new(0, 1, 0, 1)
        trackGray.Size = UDim2.new(1, -2, 1, -2)
        trackGray.BackgroundColor3 = Color3.fromHex('393939')
        trackGray.BorderSizePixel = 0
        trackGray.Parent = track

        local trackInside = Instance.new('Frame')
        trackInside.Position = UDim2.new(0, 1, 0, 1)
        trackInside.Size = UDim2.new(1, -2, 1, -2)
        trackInside.BackgroundColor3 = Color3.fromHex('131313')
        trackInside.BorderSizePixel = 0
        trackInside.Parent = trackGray

        local fill = Instance.new('Frame')
        fill.Name = 'Fill'
        fill.Position = UDim2.new(0, 1, 0, 1)
        fill.Size = UDim2.new(0, 0, 1, -2)
        fill.BackgroundColor3 = palette.accent
        fill.BorderSizePixel = 0
        fill.Parent = trackInside
        registerAccentBar(fill)

        local function setValue(val, skipSet)
            val = roundStep(val, minValue, maxValue, step)
            local range = maxValue - minValue
            local pct = range > 0 and math.clamp((val - minValue) / range, 0, 1) or 0
            fill.Size = UDim2.new(pct, -2, 1, -2)
            fill.BackgroundColor3 = palette.accent
            valLbl.Text = tostring(val) .. (suffix or '')
            if not skipSet then
                optionObj:SetValue(val)
            end
        end

        safeConnect(minusBtn.MouseButton1Click, function()
            setValue((optionObj.Value or minValue) - (step or 1))
        end)
        safeConnect(plusBtn.MouseButton1Click, function()
            setValue((optionObj.Value or minValue) + (step or 1))
        end)

        local dragging = false
        local function updateDrag(input)
            local absX = trackInside.AbsolutePosition.X
            local absW = trackInside.AbsoluteSize.X
            if absW > 0 then
                local pct = math.clamp((input.Position.X - absX) / absW, 0, 1)
                setValue(minValue + pct * (maxValue - minValue))
            end
        end
        safeConnect(track.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                updateDrag(input)
            end
        end)
        safeConnect(UIS.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        safeConnect(UIS.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                updateDrag(input)
            end
        end)

        setValue(optionObj.Value or minValue, true)
        attachChangeListener(optionObj, function(v) setValue(v, true) end)
        registerThemeRefresher(function()
            fill.BackgroundColor3 = palette.accent
        end)
        return container
    end
    end)()

    ;(function()
    local function colorToRGB(color)
        local c = typeof(color) == 'Color3' and color or Color3.fromRGB(255, 255, 255)
        return {
            r = math.floor(c.R * 255 + 0.5),
            g = math.floor(c.G * 255 + 0.5),
            b = math.floor(c.B * 255 + 0.5)
        }
    end

    local function rgbToColor(ch)
        local r = math.clamp(math.floor((tonumber(ch.r) or 0) + 0.5), 0, 255)
        local g = math.clamp(math.floor((tonumber(ch.g) or 0) + 0.5), 0, 255)
        local b = math.clamp(math.floor((tonumber(ch.b) or 0) + 0.5), 0, 255)
        return Color3.fromRGB(r, g, b)
    end

    local function colorToHex(color)
        local c = colorToRGB(color)
        return string.format('#%02X%02X%02X', c.r, c.g, c.b)
    end

    local function hexToColor(text)
        if type(text) ~= 'string' then
            return nil
        end
        local hex = text:gsub('%s+', ''):gsub('#', '')
        if #hex == 3 then
            hex = string.format('%s%s%s%s%s%s',
                hex:sub(1, 1), hex:sub(1, 1),
                hex:sub(2, 2), hex:sub(2, 2),
                hex:sub(3, 3), hex:sub(3, 3))
        end
        if #hex ~= 6 then
            return nil
        end
        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        if not r or not g or not b then
            return nil
        end
        return Color3.fromRGB(r, g, b)
    end

    local activeColorPanel = nil

    createColorRow = function(parent, caption, optionObj)
        local function safeColorOp(fn, ...)
            if type(fn) ~= 'function' then
                return nil
            end
            local args = { ... }
            local ok, result = xpcall(function()
                return fn(table.unpack(args))
            end, function() end)
            if ok then
                return result
            end
            return nil
        end

        local function isGuiAlive(gui)
            return gui ~= nil and gui.Parent ~= nil
        end

        local wrap = Instance.new('Frame')
        wrap.Name = 'ColorRow_' .. tostring(caption)
        wrap.BackgroundTransparency = 1
        wrap.Size = UDim2.new(1, 0, 0, 18)
        wrap.AutomaticSize = Enum.AutomaticSize.Y
        wrap.BorderSizePixel = 0
        wrap.Parent = parent

        local pad = Instance.new('UIPadding')
        pad.PaddingTop = UDim.new(0, 0)
        pad.PaddingBottom = UDim.new(0, 0)
        pad.PaddingLeft = UDim.new(0, 0)
        pad.PaddingRight = UDim.new(0, 0)
        pad.Parent = wrap

        local stack = Instance.new('UIListLayout')
        stack.Padding = UDim.new(0, 4)
        stack.Parent = wrap

        local headerRow = Instance.new('Frame')
        headerRow.BackgroundTransparency = 1
        headerRow.Size = UDim2.new(1, 0, 0, 18)
        headerRow.BorderSizePixel = 0
        headerRow.Parent = wrap

        local label = Instance.new('TextLabel')
        label.AnchorPoint = Vector2.new(0, 0.5)
        label.Position = UDim2.new(0, 0, 0.5, 0)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, -110, 1, 0)
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromHex('8C8F99')
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Text = caption
        label.Parent = headerRow

        local hexLabel = Instance.new('TextLabel')
        hexLabel.BackgroundTransparency = 1
        hexLabel.AnchorPoint = Vector2.new(1, 0.5)
        hexLabel.Position = UDim2.new(1, -28, 0.5, 0)
        hexLabel.Size = UDim2.fromOffset(60, 16)
        hexLabel.Font = Enum.Font.Gotham
        hexLabel.TextColor3 = Color3.fromHex('8C8F99')
        hexLabel.TextSize = 11
        hexLabel.TextXAlignment = Enum.TextXAlignment.Right
        hexLabel.TextYAlignment = Enum.TextYAlignment.Center
        hexLabel.Text = '#FFFFFF'
        hexLabel.Parent = headerRow

        local colorButton = Instance.new('TextButton')
        colorButton.AutoButtonColor = false
        colorButton.AnchorPoint = Vector2.new(1, 0.5)
        colorButton.Position = UDim2.new(1, 0, 0.5, 0)
        colorButton.Size = UDim2.fromOffset(24, 14)
        colorButton.BackgroundColor3 = Color3.fromHex('000000')
        colorButton.BorderSizePixel = 0
        colorButton.Text = ''
        colorButton.Parent = headerRow

        local cbGray = Instance.new('Frame')
        cbGray.Position = UDim2.new(0, 1, 0, 1)
        cbGray.Size = UDim2.new(1, -2, 1, -2)
        cbGray.BackgroundColor3 = Color3.fromHex('393939')
        cbGray.BorderSizePixel = 0
        cbGray.Parent = colorButton

        local colorBoxFill = Instance.new('Frame')
        colorBoxFill.Name = 'ColorFill'
        colorBoxFill.Position = UDim2.new(0, 1, 0, 1)
        colorBoxFill.Size = UDim2.new(1, -2, 1, -2)
        colorBoxFill.BackgroundColor3 = typeof(optionObj.Value) == 'Color3' and optionObj.Value or Color3.fromRGB(255, 255, 255)
        colorBoxFill.BorderSizePixel = 0
        colorBoxFill.Parent = cbGray

        local panel = Instance.new('Frame')
        panel.BackgroundColor3 = palette.surface
        panel.Size = UDim2.new(1, 0, 0, 0)
        panel.AutomaticSize = Enum.AutomaticSize.Y
        panel.ClipsDescendants = true
        panel.Visible = false
        panel.Parent = wrap
        applyCorner(panel, 6)
        applyStroke(panel, 'strokeSoft', 1, 0.5)

        local panelBaseTransparency = panel.BackgroundTransparency

        local function showPanel()
            panel.Visible = true
            panel.BackgroundTransparency = 1
            tween(panel, 0.14, { BackgroundTransparency = panelBaseTransparency })
        end

        local function hidePanel()
            tween(panel, 0.12, { BackgroundTransparency = 1 })
            runLater(0.13, function()
                safeColorOp(function()
                    if not isGuiAlive(panel) then
                        return
                    end
                    panel.Visible = false
                    panel.BackgroundTransparency = panelBaseTransparency
                end)
            end)
        end

        local panelPad = Instance.new('UIPadding')
        panelPad.PaddingTop = UDim.new(0, 8)
        panelPad.PaddingBottom = UDim.new(0, 8)
        panelPad.PaddingLeft = UDim.new(0, 8)
        panelPad.PaddingRight = UDim.new(0, 8)
        panelPad.Parent = panel

        local panelLayout = Instance.new('UIListLayout')
        panelLayout.Padding = UDim.new(0, 8)
        panelLayout.Parent = panel

        local pickerRow = Instance.new('Frame')
        pickerRow.BackgroundTransparency = 1
        pickerRow.Size = UDim2.new(1, 0, 0, 168)
        pickerRow.Parent = panel

        local wheelWrap = Instance.new('Frame')
        wheelWrap.BackgroundColor3 = palette.surfaceSoft
        wheelWrap.Position = UDim2.fromOffset(0, 0)
        wheelWrap.Size = UDim2.fromOffset(168, 168)
        wheelWrap.Parent = pickerRow
        applyCorner(wheelWrap, 8)

        local wheelImage = Instance.new('ImageLabel')
        wheelImage.BackgroundTransparency = 1
        wheelImage.Position = UDim2.fromOffset(6, 6)
        wheelImage.Size = UDim2.fromOffset(156, 156)
        wheelImage.Image = 'rbxassetid://6020299385'
        wheelImage.ScaleType = Enum.ScaleType.Stretch
        wheelImage.Parent = wheelWrap

        local wheelCursor = Instance.new('Frame')
        wheelCursor.AnchorPoint = Vector2.new(0.5, 0.5)
        wheelCursor.Size = UDim2.fromOffset(16, 16)
        wheelCursor.BackgroundColor3 = Color3.new(0, 0, 0)
        wheelCursor.BackgroundTransparency = 0.25
        wheelCursor.Parent = wheelImage
        applyCorner(wheelCursor, 8)
        applyStroke(wheelCursor, Color3.fromRGB(235, 240, 250), 2, 0)

        local valueWrap = Instance.new('Frame')
        valueWrap.BackgroundColor3 = palette.surfaceSoft
        valueWrap.AnchorPoint = Vector2.new(1, 0)
        valueWrap.Position = UDim2.new(1, 0, 0, 0)
        valueWrap.Size = UDim2.fromOffset(26, 168)
        valueWrap.Parent = pickerRow
        applyCorner(valueWrap, 8)

        local valueBar = Instance.new('Frame')
        valueBar.BackgroundColor3 = Color3.new(1, 1, 1)
        valueBar.Position = UDim2.fromOffset(6, 6)
        valueBar.Size = UDim2.fromOffset(14, 156)
        valueBar.Parent = valueWrap
        applyCorner(valueBar, 6)

        local valueGradient = Instance.new('UIGradient')
        valueGradient.Rotation = 90
        valueGradient.Parent = valueBar

        local valueKnob = Instance.new('Frame')
        valueKnob.AnchorPoint = Vector2.new(0.5, 0.5)
        valueKnob.Size = UDim2.fromOffset(24, 6)
        valueKnob.Position = UDim2.new(0.5, 0, 0, 6)
        valueKnob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
        valueKnob.Parent = valueWrap
        applyCorner(valueKnob, 3)
        applyStroke(valueKnob, Color3.fromRGB(50, 60, 80), 1, 0.2)

        local function layoutPicker()
            local availableWidth = pickerRow.AbsoluteSize.X
            if availableWidth <= 0 then
                availableWidth = 200
            end

            local sliderWidth = 26
            local gap = 8
            local wheelOuter = availableWidth - sliderWidth - gap
            wheelOuter = math.clamp(wheelOuter, 96, 212)

            pickerRow.Size = UDim2.new(1, 0, 0, wheelOuter)
            wheelWrap.Size = UDim2.fromOffset(wheelOuter, wheelOuter)
            wheelWrap.Position = UDim2.fromOffset(0, 0)

            local wheelInner = math.max(24, wheelOuter - 12)
            local wheelInset = math.floor((wheelOuter - wheelInner) / 2)
            wheelImage.Position = UDim2.fromOffset(wheelInset, wheelInset)
            wheelImage.Size = UDim2.fromOffset(wheelInner, wheelInner)

            valueWrap.Size = UDim2.fromOffset(sliderWidth, wheelOuter)
            valueWrap.Position = UDim2.new(1, 0, 0, 0)

            local valueBarHeight = math.max(24, wheelOuter - 12)
            local valueBarOffset = math.floor((wheelOuter - valueBarHeight) / 2)
            valueBar.Position = UDim2.fromOffset(6, valueBarOffset)
            valueBar.Size = UDim2.fromOffset(14, valueBarHeight)
        end

        local controlsRow = Instance.new('Frame')
        controlsRow.BackgroundTransparency = 1
        controlsRow.Size = UDim2.new(1, 0, 0, 34)
        controlsRow.Parent = panel

        local preview = Instance.new('Frame')
        preview.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        preview.Size = UDim2.fromOffset(34, 34)
        preview.Parent = controlsRow
        applyCorner(preview, 10)

        local okBtn = Instance.new('TextButton')
        okBtn.AutoButtonColor = false
        okBtn.Position = UDim2.fromOffset(42, 0)
        okBtn.Size = UDim2.fromOffset(34, 34)
        okBtn.BackgroundColor3 = palette.surfaceSoft
        okBtn.Font = Enum.Font.GothamBold
        okBtn.TextSize = 18
        okBtn.TextColor3 = palette.text
        okBtn.Text = 'OK'
        okBtn.Parent = controlsRow
        applyCorner(okBtn, 8)

        local cancelBtn = Instance.new('TextButton')
        cancelBtn.AutoButtonColor = false
        cancelBtn.Position = UDim2.fromOffset(82, 0)
        cancelBtn.Size = UDim2.fromOffset(34, 34)
        cancelBtn.BackgroundColor3 = palette.surfaceSoft
        cancelBtn.Font = Enum.Font.GothamBold
        cancelBtn.TextSize = 18
        cancelBtn.TextColor3 = palette.text
        cancelBtn.Text = 'X'
        cancelBtn.Parent = controlsRow
        applyCorner(cancelBtn, 8)

        local hexBox = Instance.new('TextBox')
        hexBox.BackgroundColor3 = palette.surfaceSoft
        hexBox.AnchorPoint = Vector2.new(1, 0)
        hexBox.Position = UDim2.new(1, 0, 0, 0)
        hexBox.Size = UDim2.fromOffset(142, 34)
        hexBox.Font = Enum.Font.GothamSemibold
        hexBox.TextColor3 = palette.text
        hexBox.TextSize = 12
        hexBox.ClearTextOnFocus = false
        hexBox.Text = '#FFFFFF'
        hexBox.Parent = controlsRow
        applyCorner(hexBox, 8)

        local valuesWrap = Instance.new('Frame')
        valuesWrap.BackgroundColor3 = palette.surfaceSoft
        valuesWrap.Size = UDim2.new(1, 0, 0, 78)
        valuesWrap.Parent = panel
        applyCorner(valuesWrap, 8)

        local valuesPad = Instance.new('UIPadding')
        valuesPad.PaddingTop = UDim.new(0, 6)
        valuesPad.PaddingBottom = UDim.new(0, 6)
        valuesPad.PaddingLeft = UDim.new(0, 8)
        valuesPad.PaddingRight = UDim.new(0, 8)
        valuesPad.Parent = valuesWrap

        local valuesStack = Instance.new('UIListLayout')
        valuesStack.Padding = UDim.new(0, 6)
        valuesStack.Parent = valuesWrap

        local function createValueLine(keys)
            local line = Instance.new('Frame')
            line.BackgroundTransparency = 1
            line.Size = UDim2.new(1, 0, 0, 30)
            line.Parent = valuesWrap

            local lineList = Instance.new('UIListLayout')
            lineList.FillDirection = Enum.FillDirection.Horizontal
            lineList.Padding = UDim.new(0, 8)
            lineList.Parent = line

            local fields = {}
            for _, item in ipairs(keys) do
                local chunk = Instance.new('Frame')
                chunk.BackgroundTransparency = 1
                chunk.Size = UDim2.new(1 / 3, -6, 1, 0)
                chunk.Parent = line

                local keyLabel = Instance.new('TextLabel')
                keyLabel.BackgroundTransparency = 1
                keyLabel.Position = UDim2.fromOffset(0, 0)
                keyLabel.Size = UDim2.fromOffset(14, 30)
                keyLabel.Font = Enum.Font.GothamSemibold
                keyLabel.TextColor3 = palette.text
                keyLabel.TextSize = 12
                keyLabel.TextXAlignment = Enum.TextXAlignment.Left
                keyLabel.Text = item
                keyLabel.Parent = chunk

                local keyBox = Instance.new('TextBox')
                keyBox.BackgroundColor3 = palette.surfaceElevated
                keyBox.Position = UDim2.fromOffset(18, 0)
                keyBox.Size = UDim2.new(1, -18, 1, 0)
                keyBox.Font = Enum.Font.Gotham
                keyBox.TextColor3 = palette.text
                keyBox.TextSize = 12
                keyBox.ClearTextOnFocus = false
                keyBox.Text = '0'
                keyBox.Parent = chunk
                applyCorner(keyBox, 7)

                fields[item] = keyBox
            end
            return fields
        end

        local rgbFields = createValueLine({ 'R', 'G', 'B' })
        local hsvFields = createValueLine({ 'H', 'S', 'V' })

        local committedColor = typeof(optionObj.Value) == 'Color3' and optionObj.Value or Color3.fromRGB(255, 255, 255)
        local hue, sat, val = committedColor:ToHSV()
        local suppressExternal = false
        local dragMode = nil

        local function getCurrentColor()
            return Color3.fromHSV(hue, sat, val)
        end

        local function updateSelectors()
            if not (isGuiAlive(wheelImage) and isGuiAlive(valueBar) and isGuiAlive(valueKnob)) then
                return
            end
            local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2
            if radius <= 0 then
                return
            end
            local centerX = wheelImage.AbsoluteSize.X / 2
            local centerY = wheelImage.AbsoluteSize.Y / 2
            -- Match ColorWheelHandler orientation:
            -- h = (pi - atan2(dy, dx)) / (2*pi)
            local angle = math.pi - (hue * 2 * math.pi)
            local dist = sat * radius
            local x = centerX + math.cos(angle) * dist
            local y = centerY + math.sin(angle) * dist
            wheelCursor.Position = UDim2.fromOffset(x, y)

            local yPct = 1 - val
            local barOffset = valueBar.Position.Y.Offset
            local barHeight = valueBar.AbsoluteSize.Y
            valueKnob.Position = UDim2.new(0.5, 0, 0, barOffset + (barHeight * yPct))

            local topColor = Color3.fromHSV(hue, sat, 1)
            valueGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, topColor),
                ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0))
            })
        end

        local function syncFields()
            if not (isGuiAlive(colorButton) and isGuiAlive(preview) and isGuiAlive(hexLabel)) then
                return
            end
            local c = getCurrentColor()
            local rgb = colorToRGB(c)
            if not rgbFields.R:IsFocused() then rgbFields.R.Text = tostring(rgb.r) end
            if not rgbFields.G:IsFocused() then rgbFields.G.Text = tostring(rgb.g) end
            if not rgbFields.B:IsFocused() then rgbFields.B.Text = tostring(rgb.b) end
            if not hsvFields.H:IsFocused() then hsvFields.H.Text = tostring(math.floor((hue * 360) + 0.5)) end
            if not hsvFields.S:IsFocused() then hsvFields.S.Text = string.format('%.2f', sat) end
            if not hsvFields.V:IsFocused() then hsvFields.V.Text = string.format('%.2f', val) end
            if not hexBox:IsFocused() then hexBox.Text = colorToHex(c) end
            if isGuiAlive(colorBoxFill) then colorBoxFill.BackgroundColor3 = c end
            preview.BackgroundColor3 = c
            hexLabel.Text = colorToHex(c)
        end

        local function pushOption()
            suppressExternal = true
            optionObj:SetValue(getCurrentColor())
            suppressExternal = false
            if type(requestSaveConfig) == 'function' then
                requestSaveConfig()
            end
        end

        local function render(push)
            updateSelectors()
            syncFields()
            if push then
                pushOption()
            end
        end

        local function setFromColor(color, push)
            local c = typeof(color) == 'Color3' and color or Color3.fromRGB(255, 255, 255)
            hue, sat, val = c:ToHSV()
            render(push)
        end

        local function setFromWheel(px, py)
            if not isGuiAlive(wheelImage) then
                return
            end
            local centerX = wheelImage.AbsolutePosition.X + (wheelImage.AbsoluteSize.X / 2)
            local centerY = wheelImage.AbsolutePosition.Y + (wheelImage.AbsoluteSize.Y / 2)
            local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2
            if radius <= 0 then
                return
            end
            local dx = px - centerX
            local dy = py - centerY
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist > radius and dist > 0 then
                local m = radius / dist
                dx = dx * m
                dy = dy * m
                dist = radius
            end
            sat = math.clamp(dist / radius, 0, 1)
            if sat > 0 then
                hue = (math.pi - math.atan2(dy, dx)) / (2 * math.pi)
                hue = math.clamp(hue, 0, 1)
            end
            render(true)
        end

        local function setFromValue(py)
            if not isGuiAlive(valueBar) then
                return
            end
            local top = valueBar.AbsolutePosition.Y
            local size = valueBar.AbsoluteSize.Y
            local pct = 0
            if size > 0 then
                pct = math.clamp((py - top) / size, 0, 1)
            end
            val = 1 - pct
            render(true)
        end

safeConnect(wheelImage.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = 'wheel'
                setFromWheel(input.Position.X, input.Position.Y)
            end
        end)
safeConnect(wheelImage.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

safeConnect(valueBar.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = 'value'
                setFromValue(input.Position.Y)
            end
        end)
safeConnect(valueBar.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

        -- Track pointer globally while dragging so selection remains accurate
        -- even when cursor goes outside wheel/slider bounds.
safeConnect(UIS.InputChanged, function(input)
            if dragMode == nil then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if dragMode == 'wheel' then
                setFromWheel(input.Position.X, input.Position.Y)
            elseif dragMode == 'value' then
                setFromValue(input.Position.Y)
            end
        end)

safeConnect(UIS.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

safeConnect(rgbFields.R.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)
safeConnect(rgbFields.G.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)
safeConnect(rgbFields.B.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)

safeConnect(hsvFields.H.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)
safeConnect(hsvFields.S.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)
safeConnect(hsvFields.V.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)

        local function applyHex()
            local parsed = hexToColor(hexBox.Text)
            if parsed then
                setFromColor(parsed, true)
            else
                hexBox.Text = colorToHex(getCurrentColor())
            end
        end
safeConnect(hexBox.FocusLost, function(enterPressed)
            applyHex()
        end)

safeConnect(okBtn.MouseButton1Click, function()
            applyHex()
            committedColor = getCurrentColor()
            setFromColor(committedColor, true)
            hidePanel()
            if activeColorPanel == panel then
                activeColorPanel = nil
            end
        end)
safeConnect(cancelBtn.MouseButton1Click, function()
            setFromColor(committedColor, true)
            hidePanel()
            if activeColorPanel == panel then
                activeColorPanel = nil
            end
        end)
safeConnect(colorButton.MouseButton1Click, function()
            if panel.Visible then
                hidePanel()
                if activeColorPanel == panel then
                    activeColorPanel = nil
                end
                return
            end

            if activeColorPanel and activeColorPanel ~= panel then
                activeColorPanel.Visible = false
            end

            setFromColor(optionObj.Value, false)
            committedColor = typeof(optionObj.Value) == 'Color3' and optionObj.Value or getCurrentColor()
            showPanel()
            activeColorPanel = panel
            task.defer(function()
                safeColorOp(function()
                    if not isGuiAlive(panel) then
                        return
                    end
                    layoutPicker()
                    render(false)
                end)
            end)
        end)

        attachChangeListener(optionObj, function()
            if suppressExternal then
                return
            end
            local external = typeof(optionObj.Value) == 'Color3' and optionObj.Value or Color3.fromRGB(255, 255, 255)
            committedColor = external
            setFromColor(external, false)
        end)

safeConnect(pickerRow:GetPropertyChangedSignal('AbsoluteSize'), function()
            if panel.Visible then
                layoutPicker()
                render(false)
            end
        end)

        safeColorOp(layoutPicker)
        safeColorOp(setFromColor, committedColor, false)
        bindTheme(wrap, 'BackgroundColor3', 'surfaceElevated')
        bindTheme(label, 'TextColor3', 'text')
        bindTheme(hexLabel, 'TextColor3', 'textDim')
        bindTheme(panel, 'BackgroundColor3', 'surface')
        bindTheme(wheelWrap, 'BackgroundColor3', 'surfaceSoft')
        bindTheme(valueWrap, 'BackgroundColor3', 'surfaceSoft')
        bindTheme(okBtn, 'BackgroundColor3', 'surfaceSoft')
        bindTheme(okBtn, 'TextColor3', 'text')
        bindTheme(cancelBtn, 'BackgroundColor3', 'surfaceSoft')
        bindTheme(cancelBtn, 'TextColor3', 'text')
        bindTheme(hexBox, 'BackgroundColor3', 'surfaceSoft')
        bindTheme(hexBox, 'TextColor3', 'text')
        bindTheme(valuesWrap, 'BackgroundColor3', 'surfaceSoft')
        return wrap
    end

    createToggleColorRow = function(parent, caption, toggleObj, colorObj, modeOption, modeValues)
        local function safeColorOp(fn, ...)
            if type(fn) ~= 'function' then
                return nil
            end
            local args = { ... }
            local ok, result = xpcall(function()
                return fn(table.unpack(args))
            end, function() end)
            if ok then
                return result
            end
            return nil
        end

        local function isGuiAlive(gui)
            return gui ~= nil and gui.Parent ~= nil
        end

        local row = Instance.new('Frame')
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, 0, 0, 20)
        row.AutomaticSize = Enum.AutomaticSize.Y
        row.BorderSizePixel = 0
        row.Parent = parent

        local stack = Instance.new('UIListLayout')
        stack.Padding = UDim.new(0, 4)
        stack.Parent = row

        local top = Instance.new('Frame')
        top.BackgroundTransparency = 1
        top.Size = UDim2.new(1, 0, 0, 18)
        top.BorderSizePixel = 0
        top.Parent = row

        local switch = Instance.new('TextButton')
        switch.Name = 'Box'
        switch.AutoButtonColor = false
        switch.AnchorPoint = Vector2.new(0, 0.5)
        switch.Position = UDim2.new(0, 0, 0.5, 0)
        switch.Size = UDim2.fromOffset(14, 14)
        switch.BackgroundColor3 = Color3.fromHex('000000')
        switch.BorderSizePixel = 0
        switch.Text = ''
        switch.Parent = top

        local swGray = Instance.new('Frame')
        swGray.Position = UDim2.new(0, 1, 0, 1)
        swGray.Size = UDim2.new(1, -2, 1, -2)
        swGray.BackgroundColor3 = Color3.fromHex('393939')
        swGray.BorderSizePixel = 0
        swGray.Parent = switch

        local swInside = Instance.new('Frame')
        swInside.Position = UDim2.new(0, 1, 0, 1)
        swInside.Size = UDim2.new(1, -2, 1, -2)
        swInside.BackgroundColor3 = Color3.fromHex('131313')
        swInside.BorderSizePixel = 0
        swInside.Parent = swGray

        local checkFill = Instance.new('Frame')
        checkFill.Name = 'Fill'
        checkFill.AnchorPoint = Vector2.new(0.5, 0.5)
        checkFill.Position = UDim2.new(0.5, 0, 0.5, 0)
        checkFill.Size = UDim2.new(0, 0, 0, 0)
        checkFill.BackgroundColor3 = palette.accent
        checkFill.BackgroundTransparency = 1
        checkFill.BorderSizePixel = 0
        checkFill.Parent = swInside
        registerAccentBar(checkFill)

        local switchCheck = checkFill
        local switchCheckStem = Instance.new('Frame')
        local switchCheckArm = Instance.new('Frame')

        local label = Instance.new('TextLabel')
        label.Name = 'Label'
        label.BackgroundTransparency = 1
        label.AnchorPoint = Vector2.new(0, 0.5)
        label.Position = UDim2.new(0, 20, 0.5, 0)
        label.Size = UDim2.new(1, -90, 1, 0)
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromHex('8C8F99')
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Text = caption
        label.Parent = top

        local modeButton
        if modeOption then
            modeValues = type(modeValues) == 'table' and modeValues or { 'Text', 'Bar' }

            modeButton = Instance.new('TextButton')
            modeButton.AutoButtonColor = false
            modeButton.AnchorPoint = Vector2.new(1, 0.5)
            modeButton.Position = UDim2.new(1, -34, 0.5, 0)
            modeButton.Size = UDim2.fromOffset(46, 16)
            modeButton.BackgroundColor3 = Color3.fromHex('161616')
            modeButton.BorderSizePixel = 0
            modeButton.Font = Enum.Font.Gotham
            modeButton.TextColor3 = Color3.fromHex('8C8F99')
            modeButton.TextSize = 10
            modeButton.Parent = top
            local mbOuter = Instance.new('UIStroke')
            mbOuter.Color = Color3.fromHex('000105')
            mbOuter.Thickness = 1
            mbOuter.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            mbOuter.Parent = modeButton
        end

        local colorButton = Instance.new('TextButton')
        colorButton.AutoButtonColor = false
        colorButton.AnchorPoint = Vector2.new(1, 0.5)
        colorButton.Position = UDim2.new(1, 0, 0.5, 0)
        colorButton.Size = UDim2.fromOffset(25, 14)
        colorButton.Text = ''
        colorButton.BackgroundColor3 = Color3.fromHex('000105')
        colorButton.BorderSizePixel = 0
        colorButton.Parent = top

        local cbInline = Instance.new('Frame')
        cbInline.Position = UDim2.new(0, 1, 0, 1)
        cbInline.Size = UDim2.new(1, -2, 1, -2)
        cbInline.BackgroundColor3 = Color3.fromHex('252527')
        cbInline.BorderSizePixel = 0
        cbInline.Parent = colorButton

        local cbHandle = Instance.new('Frame')
        cbHandle.Position = UDim2.new(0, 1, 0, 1)
        cbHandle.Size = UDim2.new(1, -2, 1, -2)
        cbHandle.BackgroundColor3 = typeof(colorObj.Value) == 'Color3' and colorObj.Value or Color3.fromRGB(255, 255, 255)
        cbHandle.BorderSizePixel = 0
        cbHandle.Parent = cbInline

        local panel = Instance.new('Frame')
        panel.BackgroundColor3 = palette.surface
        panel.Size = UDim2.new(1, 0, 0, 0)
        panel.AutomaticSize = Enum.AutomaticSize.Y
        panel.ClipsDescendants = true
        panel.Visible = false
        panel.Parent = row
        applyCorner(panel, 8)
        applyStroke(panel, 'strokeSoft', 1, 0.45)

        local panelBaseTransparency = panel.BackgroundTransparency

        local function showPanel()
            panel.Visible = true
            panel.BackgroundTransparency = 1
            tween(panel, 0.14, { BackgroundTransparency = panelBaseTransparency })
        end

        local function hidePanel()
            tween(panel, 0.12, { BackgroundTransparency = 1 })
            runLater(0.13, function()
                safeColorOp(function()
                    if not isGuiAlive(panel) then
                        return
                    end
                    panel.Visible = false
                    panel.BackgroundTransparency = panelBaseTransparency
                end)
            end)
        end

        local panelPad = Instance.new('UIPadding')
        panelPad.PaddingTop = UDim.new(0, 8)
        panelPad.PaddingBottom = UDim.new(0, 8)
        panelPad.PaddingLeft = UDim.new(0, 8)
        panelPad.PaddingRight = UDim.new(0, 8)
        panelPad.Parent = panel

        local panelLayout = Instance.new('UIListLayout')
        panelLayout.Padding = UDim.new(0, 8)
        panelLayout.Parent = panel

        local pickerRow = Instance.new('Frame')
        pickerRow.BackgroundTransparency = 1
        pickerRow.Size = UDim2.new(1, 0, 0, 168)
        pickerRow.Parent = panel

        local wheelWrap = Instance.new('Frame')
        wheelWrap.BackgroundColor3 = palette.surfaceSoft
        wheelWrap.Position = UDim2.fromOffset(0, 0)
        wheelWrap.Size = UDim2.fromOffset(168, 168)
        wheelWrap.Parent = pickerRow
        applyCorner(wheelWrap, 8)

        local wheelImage = Instance.new('ImageLabel')
        wheelImage.BackgroundTransparency = 1
        wheelImage.Position = UDim2.fromOffset(6, 6)
        wheelImage.Size = UDim2.fromOffset(156, 156)
        wheelImage.Image = 'rbxassetid://6020299385'
        wheelImage.ScaleType = Enum.ScaleType.Stretch
        wheelImage.Parent = wheelWrap

        local wheelCursor = Instance.new('Frame')
        wheelCursor.AnchorPoint = Vector2.new(0.5, 0.5)
        wheelCursor.Size = UDim2.fromOffset(16, 16)
        wheelCursor.BackgroundColor3 = Color3.new(0, 0, 0)
        wheelCursor.BackgroundTransparency = 0.25
        wheelCursor.Parent = wheelImage
        applyCorner(wheelCursor, 8)
        applyStroke(wheelCursor, Color3.fromRGB(235, 240, 250), 2, 0)

        local valueWrap = Instance.new('Frame')
        valueWrap.BackgroundColor3 = palette.surfaceSoft
        valueWrap.AnchorPoint = Vector2.new(1, 0)
        valueWrap.Position = UDim2.new(1, 0, 0, 0)
        valueWrap.Size = UDim2.fromOffset(26, 168)
        valueWrap.Parent = pickerRow
        applyCorner(valueWrap, 8)

        local valueBar = Instance.new('Frame')
        valueBar.BackgroundColor3 = Color3.new(1, 1, 1)
        valueBar.Position = UDim2.fromOffset(6, 6)
        valueBar.Size = UDim2.fromOffset(14, 156)
        valueBar.Parent = valueWrap
        applyCorner(valueBar, 6)

        local valueGradient = Instance.new('UIGradient')
        valueGradient.Rotation = 90
        valueGradient.Parent = valueBar

        local valueKnob = Instance.new('Frame')
        valueKnob.AnchorPoint = Vector2.new(0.5, 0.5)
        valueKnob.Size = UDim2.fromOffset(24, 6)
        valueKnob.Position = UDim2.new(0.5, 0, 0, 6)
        valueKnob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
        valueKnob.Parent = valueWrap
        applyCorner(valueKnob, 3)
        applyStroke(valueKnob, Color3.fromRGB(50, 60, 80), 1, 0.2)

        local function layoutPicker()
            local availableWidth = pickerRow.AbsoluteSize.X
            if availableWidth <= 0 then
                availableWidth = 200
            end

            local sliderWidth = 26
            local gap = 8
            local wheelOuter = availableWidth - sliderWidth - gap
            wheelOuter = math.clamp(wheelOuter, 96, 212)

            pickerRow.Size = UDim2.new(1, 0, 0, wheelOuter)
            wheelWrap.Size = UDim2.fromOffset(wheelOuter, wheelOuter)
            wheelWrap.Position = UDim2.fromOffset(0, 0)

            local wheelInner = math.max(24, wheelOuter - 12)
            local wheelInset = math.floor((wheelOuter - wheelInner) / 2)
            wheelImage.Position = UDim2.fromOffset(wheelInset, wheelInset)
            wheelImage.Size = UDim2.fromOffset(wheelInner, wheelInner)

            valueWrap.Size = UDim2.fromOffset(sliderWidth, wheelOuter)
            valueWrap.Position = UDim2.new(1, 0, 0, 0)

            local valueBarHeight = math.max(24, wheelOuter - 12)
            local valueBarOffset = math.floor((wheelOuter - valueBarHeight) / 2)
            valueBar.Position = UDim2.fromOffset(6, valueBarOffset)
            valueBar.Size = UDim2.fromOffset(14, valueBarHeight)
        end

        local controlsRow = Instance.new('Frame')
        controlsRow.BackgroundTransparency = 1
        controlsRow.Size = UDim2.new(1, 0, 0, 34)
        controlsRow.Parent = panel

        local preview = Instance.new('Frame')
        preview.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        preview.Size = UDim2.fromOffset(34, 34)
        preview.Parent = controlsRow
        applyCorner(preview, 10)

        local okBtn = Instance.new('TextButton')
        okBtn.AutoButtonColor = false
        okBtn.Position = UDim2.fromOffset(42, 0)
        okBtn.Size = UDim2.fromOffset(34, 34)
        okBtn.BackgroundColor3 = palette.surfaceSoft
        okBtn.Font = Enum.Font.GothamBold
        okBtn.TextSize = 18
        okBtn.TextColor3 = palette.text
        okBtn.Text = 'OK'
        okBtn.Parent = controlsRow
        applyCorner(okBtn, 8)

        local cancelBtn = Instance.new('TextButton')
        cancelBtn.AutoButtonColor = false
        cancelBtn.Position = UDim2.fromOffset(82, 0)
        cancelBtn.Size = UDim2.fromOffset(34, 34)
        cancelBtn.BackgroundColor3 = palette.surfaceSoft
        cancelBtn.Font = Enum.Font.GothamBold
        cancelBtn.TextSize = 18
        cancelBtn.TextColor3 = palette.text
        cancelBtn.Text = 'X'
        cancelBtn.Parent = controlsRow
        applyCorner(cancelBtn, 8)

        local hexBox = Instance.new('TextBox')
        hexBox.BackgroundColor3 = palette.surfaceSoft
        hexBox.AnchorPoint = Vector2.new(1, 0)
        hexBox.Position = UDim2.new(1, 0, 0, 0)
        hexBox.Size = UDim2.fromOffset(142, 34)
        hexBox.Font = Enum.Font.GothamSemibold
        hexBox.TextColor3 = palette.text
        hexBox.TextSize = 12
        hexBox.ClearTextOnFocus = false
        hexBox.Text = '#FFFFFF'
        hexBox.Parent = controlsRow
        applyCorner(hexBox, 8)

        local valuesWrap = Instance.new('Frame')
        valuesWrap.BackgroundColor3 = palette.surfaceSoft
        valuesWrap.Size = UDim2.new(1, 0, 0, 78)
        valuesWrap.Parent = panel
        applyCorner(valuesWrap, 8)

        local valuesPad = Instance.new('UIPadding')
        valuesPad.PaddingTop = UDim.new(0, 6)
        valuesPad.PaddingBottom = UDim.new(0, 6)
        valuesPad.PaddingLeft = UDim.new(0, 8)
        valuesPad.PaddingRight = UDim.new(0, 8)
        valuesPad.Parent = valuesWrap

        local valuesStack = Instance.new('UIListLayout')
        valuesStack.Padding = UDim.new(0, 6)
        valuesStack.Parent = valuesWrap

        local function createValueLine(keys)
            local line = Instance.new('Frame')
            line.BackgroundTransparency = 1
            line.Size = UDim2.new(1, 0, 0, 30)
            line.Parent = valuesWrap

            local lineList = Instance.new('UIListLayout')
            lineList.FillDirection = Enum.FillDirection.Horizontal
            lineList.Padding = UDim.new(0, 8)
            lineList.Parent = line

            local fields = {}
            for _, item in ipairs(keys) do
                local chunk = Instance.new('Frame')
                chunk.BackgroundTransparency = 1
                chunk.Size = UDim2.new(1 / 3, -6, 1, 0)
                chunk.Parent = line

                local keyLabel = Instance.new('TextLabel')
                keyLabel.BackgroundTransparency = 1
                keyLabel.Position = UDim2.fromOffset(0, 0)
                keyLabel.Size = UDim2.fromOffset(14, 30)
                keyLabel.Font = Enum.Font.GothamSemibold
                keyLabel.TextColor3 = palette.text
                keyLabel.TextSize = 12
                keyLabel.TextXAlignment = Enum.TextXAlignment.Left
                keyLabel.Text = item
                keyLabel.Parent = chunk

                local keyBox = Instance.new('TextBox')
                keyBox.BackgroundColor3 = palette.surfaceElevated
                keyBox.Position = UDim2.fromOffset(18, 0)
                keyBox.Size = UDim2.new(1, -18, 1, 0)
                keyBox.Font = Enum.Font.Gotham
                keyBox.TextColor3 = palette.text
                keyBox.TextSize = 12
                keyBox.ClearTextOnFocus = false
                keyBox.Text = '0'
                keyBox.Parent = chunk
                applyCorner(keyBox, 7)

                fields[item] = keyBox
            end
            return fields
        end

        local rgbFields = createValueLine({ 'R', 'G', 'B' })
        local hsvFields = createValueLine({ 'H', 'S', 'V' })

        local committedColor = typeof(colorObj.Value) == 'Color3' and colorObj.Value or Color3.fromRGB(255, 255, 255)
        local hue, sat, val = committedColor:ToHSV()
        local suppressExternal = false
        local dragMode = nil

        local function getCurrentColor()
            return Color3.fromHSV(hue, sat, val)
        end

        local function updateSelectors()
            if not (isGuiAlive(wheelImage) and isGuiAlive(valueBar) and isGuiAlive(valueKnob)) then
                return
            end
            local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2
            if radius <= 0 then
                return
            end
            local centerX = wheelImage.AbsoluteSize.X / 2
            local centerY = wheelImage.AbsoluteSize.Y / 2
            local angle = math.pi - (hue * 2 * math.pi)
            local dist = sat * radius
            local x = centerX + math.cos(angle) * dist
            local y = centerY + math.sin(angle) * dist
            wheelCursor.Position = UDim2.fromOffset(x, y)

            local yPct = 1 - val
            local barOffset = valueBar.Position.Y.Offset
            local barHeight = valueBar.AbsoluteSize.Y
            valueKnob.Position = UDim2.new(0.5, 0, 0, barOffset + (barHeight * yPct))

            local topColor = Color3.fromHSV(hue, sat, 1)
            valueGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, topColor),
                ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0))
            })
        end

        local function syncFields()
            if not (isGuiAlive(colorButton) and isGuiAlive(preview)) then
                return
            end
            local c = getCurrentColor()
            local rgb = colorToRGB(c)
            if not rgbFields.R:IsFocused() then rgbFields.R.Text = tostring(rgb.r) end
            if not rgbFields.G:IsFocused() then rgbFields.G.Text = tostring(rgb.g) end
            if not rgbFields.B:IsFocused() then rgbFields.B.Text = tostring(rgb.b) end
            if not hsvFields.H:IsFocused() then hsvFields.H.Text = tostring(math.floor((hue * 360) + 0.5)) end
            if not hsvFields.S:IsFocused() then hsvFields.S.Text = string.format('%.2f', sat) end
            if not hsvFields.V:IsFocused() then hsvFields.V.Text = string.format('%.2f', val) end
            if not hexBox:IsFocused() then hexBox.Text = colorToHex(c) end
            if isGuiAlive(cbHandle) then cbHandle.BackgroundColor3 = c end
            preview.BackgroundColor3 = c
        end

        local function pushOption()
            suppressExternal = true
            colorObj:SetValue(getCurrentColor())
            suppressExternal = false
            if type(requestSaveConfig) == 'function' then
                requestSaveConfig()
            end
        end

        local function render(push)
            updateSelectors()
            syncFields()
            if push then
                pushOption()
            end
        end

        local function setFromColor(color, push)
            local c = typeof(color) == 'Color3' and color or Color3.fromRGB(255, 255, 255)
            hue, sat, val = c:ToHSV()
            render(push)
        end

        local function setFromWheel(px, py)
            if not isGuiAlive(wheelImage) then
                return
            end
            local centerX = wheelImage.AbsolutePosition.X + (wheelImage.AbsoluteSize.X / 2)
            local centerY = wheelImage.AbsolutePosition.Y + (wheelImage.AbsoluteSize.Y / 2)
            local radius = math.min(wheelImage.AbsoluteSize.X, wheelImage.AbsoluteSize.Y) / 2
            if radius <= 0 then
                return
            end
            local dx = px - centerX
            local dy = py - centerY
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist > radius and dist > 0 then
                local m = radius / dist
                dx = dx * m
                dy = dy * m
                dist = radius
            end
            sat = math.clamp(dist / radius, 0, 1)
            if sat > 0 then
                hue = (math.pi - math.atan2(dy, dx)) / (2 * math.pi)
                hue = math.clamp(hue, 0, 1)
            end
            render(true)
        end

        local function setFromValue(py)
            if not isGuiAlive(valueBar) then
                return
            end
            local top = valueBar.AbsolutePosition.Y
            local size = valueBar.AbsoluteSize.Y
            local pct = 0
            if size > 0 then
                pct = math.clamp((py - top) / size, 0, 1)
            end
            val = 1 - pct
            render(true)
        end

        safeConnect(wheelImage.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = 'wheel'
                setFromWheel(input.Position.X, input.Position.Y)
            end
        end)
        safeConnect(wheelImage.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

        safeConnect(valueBar.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = 'value'
                setFromValue(input.Position.Y)
            end
        end)
        safeConnect(valueBar.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

        safeConnect(UIS.InputChanged, function(input)
            if dragMode == nil then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if dragMode == 'wheel' then
                setFromWheel(input.Position.X, input.Position.Y)
            elseif dragMode == 'value' then
                setFromValue(input.Position.Y)
            end
        end)

        safeConnect(UIS.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragMode = nil
            end
        end)

        safeConnect(rgbFields.R.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)
        safeConnect(rgbFields.G.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)
        safeConnect(rgbFields.B.FocusLost, function()
            local r = math.clamp(math.floor((tonumber(rgbFields.R.Text) or 0) + 0.5), 0, 255)
            local g = math.clamp(math.floor((tonumber(rgbFields.G.Text) or 0) + 0.5), 0, 255)
            local b = math.clamp(math.floor((tonumber(rgbFields.B.Text) or 0) + 0.5), 0, 255)
            setFromColor(Color3.fromRGB(r, g, b), true)
        end)

        safeConnect(hsvFields.H.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)
        safeConnect(hsvFields.S.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)
        safeConnect(hsvFields.V.FocusLost, function()
            local hNum = tonumber(hsvFields.H.Text) or (hue * 360)
            local sNum = tonumber(hsvFields.S.Text) or sat
            local vNum = tonumber(hsvFields.V.Text) or val
            hue = (hNum % 360) / 360
            sat = math.clamp(sNum, 0, 1)
            val = math.clamp(vNum, 0, 1)
            render(true)
        end)

        local function applyHex()
            local parsed = hexToColor(hexBox.Text)
            if parsed then
                setFromColor(parsed, true)
            else
                hexBox.Text = colorToHex(getCurrentColor())
            end
        end
        safeConnect(hexBox.FocusLost, function(enterPressed)
            if enterPressed then
                applyHex()
            end
        end)

        safeConnect(okBtn.MouseButton1Click, function()
            committedColor = getCurrentColor()
            hidePanel()
            if activeColorPanel == panel then
                activeColorPanel = nil
            end
        end)
        safeConnect(cancelBtn.MouseButton1Click, function()
            setFromColor(committedColor, true)
            hidePanel()
            if activeColorPanel == panel then
                activeColorPanel = nil
            end
        end)

        local function renderToggle()
            local state = toggleObj.Value == true
            checkFill.BackgroundColor3 = palette.accent
            checkFill.BackgroundTransparency = state and 0 or 1
            checkFill.Size = state and UDim2.new(1, -2, 1, -2) or UDim2.new(0, 0, 0, 0)
            label.TextColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromHex('8C8F99')
        end

        local function renderColor()
            local c = typeof(colorObj.Value) == 'Color3' and colorObj.Value or Color3.fromRGB(255, 255, 255)
            if isGuiAlive(cbHandle) then cbHandle.BackgroundColor3 = c end
            preview.BackgroundColor3 = c
        end

        local function currentModeIndex()
            if not modeOption then
                return 1
            end
            local current = type(modeOption.Value) == 'string' and modeOption.Value or tostring(modeValues[1] or '')
            for i, v in ipairs(modeValues) do
                if tostring(v) == current then
                    return i
                end
            end
            return 1
        end

        local function renderMode()
            if modeButton then
                modeButton.Text = tostring(modeValues[currentModeIndex()] or '')
            end
        end

        safeConnect(switch.MouseButton1Click, function()
            toggleObj:SetValue(not (toggleObj.Value == true))
            renderToggle()
        end)

        safeConnect(colorButton.MouseButton1Click, function()
            if panel.Visible then
                hidePanel()
                if activeColorPanel == panel then
                    activeColorPanel = nil
                end
                return
            end

            if activeColorPanel and activeColorPanel ~= panel then
                activeColorPanel.Visible = false
            end

            setFromColor(colorObj.Value, false)
            committedColor = typeof(colorObj.Value) == 'Color3' and colorObj.Value or getCurrentColor()
            showPanel()
            activeColorPanel = panel
            task.defer(function()
                safeColorOp(function()
                    if not isGuiAlive(panel) then
                        return
                    end
                    layoutPicker()
                    render(false)
                end)
            end)
        end)

        if modeButton then
            safeConnect(modeButton.MouseButton1Click, function()
                local idx = currentModeIndex() + 1
                if idx > #modeValues then
                    idx = 1
                end
                modeOption:SetValue(tostring(modeValues[idx]))
                renderMode()
            end)
            attachChangeListener(modeOption, renderMode)
        end

        attachChangeListener(toggleObj, renderToggle)
        attachChangeListener(colorObj, function()
            if suppressExternal then
                return
            end
            local external = typeof(colorObj.Value) == 'Color3' and colorObj.Value or Color3.fromRGB(255, 255, 255)
            committedColor = external
            setFromColor(external, false)
        end)

        safeConnect(pickerRow:GetPropertyChangedSignal('AbsoluteSize'), function()
            if panel.Visible then
                layoutPicker()
                render(false)
            end
        end)

        safeColorOp(layoutPicker)
        safeColorOp(setFromColor, committedColor, false)
        renderToggle()
        renderColor()
        renderMode()
        registerThemeRefresher(renderToggle)
        return row
    end
    end)()

    ;(function()
    local function getPlayerNamesLive()
        local raw = {}
        local displayCounts = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer then
                local display = tostring(pl.DisplayName or pl.Name)
                displayCounts[display] = (displayCounts[display] or 0) + 1
                table.insert(raw, { username = pl.Name, display = display })
            end
        end

        local out = {}
        for _, item in ipairs(raw) do
            local label = item.display
            if displayCounts[item.display] and displayCounts[item.display] > 1 then
                label = string.format('%s (@%s)', item.display, item.username)
            end
            table.insert(out, {
                username = item.username,
                label = label
            })
        end

        table.sort(out, function(a, b)
            return string.lower(a.label) < string.lower(b.label)
        end)
        return out
    end

    createWhitelistDropdown = function(parent, caption, optionObj)
        local block = Instance.new('Frame')
        block.BackgroundColor3 = palette.surfaceElevated
        block.Size = UDim2.new(1, 0, 0, 44)
        block.AutomaticSize = Enum.AutomaticSize.Y
        block.Parent = parent
        applyCorner(block, 6)
        addHover(block, 'surfaceElevated', 'surfaceSoft')

        local pad = Instance.new('UIPadding')
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = block

        local list = Instance.new('UIListLayout')
        list.Padding = UDim.new(0, 6)
        list.Parent = block

        local dropdownBtn = Instance.new('TextButton')
        dropdownBtn.AutoButtonColor = false
        dropdownBtn.BackgroundColor3 = palette.surface
        dropdownBtn.Size = UDim2.new(1, 0, 0, 28)
        dropdownBtn.Font = Enum.Font.GothamSemibold
        dropdownBtn.TextColor3 = palette.text
        dropdownBtn.TextSize = 12
        dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
        dropdownBtn.Text = '  ' .. caption
        dropdownBtn.Parent = block
        applyCorner(dropdownBtn, 8)
        applyStroke(dropdownBtn, 'stroke', 1, 0.6)
        addHover(dropdownBtn, 'surface', 'surfaceSoft')

        local listFrame = Instance.new('Frame')
        listFrame.BackgroundColor3 = palette.surface
        listFrame.Size = UDim2.new(1, 0, 0, 0)
        listFrame.AutomaticSize = Enum.AutomaticSize.Y
        listFrame.Visible = false
        listFrame.Parent = block
        applyCorner(listFrame, 8)
        local listStroke = applyStroke(listFrame, 'stroke', 1, 0.6)
        local listBaseTransparency = listFrame.BackgroundTransparency
        local listStrokeBaseTransparency = listStroke.Transparency

        local listPad = Instance.new('UIPadding')
        listPad.PaddingTop = UDim.new(0, 6)
        listPad.PaddingBottom = UDim.new(0, 6)
        listPad.PaddingLeft = UDim.new(0, 6)
        listPad.PaddingRight = UDim.new(0, 6)
        listPad.Parent = listFrame

        local listLayout = Instance.new('UIListLayout')
        listLayout.Padding = UDim.new(0, 4)
        listLayout.Parent = listFrame

        local selected = normalizeSelection(optionObj.Value)
        local opened = false
        local rows = {}

        local function getListHeight()
            local padH = listPad.PaddingTop.Offset + listPad.PaddingBottom.Offset
            local contentH = listLayout.AbsoluteContentSize.Y
            return math.max(0, contentH + padH)
        end

        local function syncListHeight(instant)
            if not opened then
                return
            end
            local h = getListHeight()
            local size = UDim2.new(1, 0, 0, h)
            if instant then
                listFrame.Size = size
            else
                tween(listFrame, 0.14, { Size = size })
            end
        end

        local function showList()
            opened = true
            listFrame.Visible = true
            listFrame.AutomaticSize = Enum.AutomaticSize.None
            listFrame.Size = UDim2.new(1, 0, 0, 0)
            listFrame.BackgroundTransparency = 1
            listStroke.Transparency = 1
            tween(listFrame, 0.14, { BackgroundTransparency = listBaseTransparency })
            tween(listStroke, 0.14, { Transparency = listStrokeBaseTransparency })
            runLater(0, function()
                syncListHeight(false)
            end)
        end

        local function hideList()
            opened = false
            tween(listFrame, 0.12, { Size = UDim2.new(1, 0, 0, 0) })
            tween(listFrame, 0.12, { BackgroundTransparency = 1 })
            tween(listStroke, 0.12, { Transparency = 1 })
            runLater(0.13, function()
                listFrame.Visible = false
                listFrame.BackgroundTransparency = listBaseTransparency
                listStroke.Transparency = listStrokeBaseTransparency
                listFrame.AutomaticSize = Enum.AutomaticSize.Y
            end)
        end

        local function selectedCount()
            local count = 0
            for _, state in pairs(selected) do
                if state then
                    count = count + 1
                end
            end
            return count
        end

        local function updateHeader()
            local count = selectedCount()
            if count > 0 then
                dropdownBtn.Text = string.format('  %s (%d)', caption, count)
            else
                dropdownBtn.Text = string.format('  %s (none)', caption)
            end
        end

        local function setSelectedAndSync(newMap)
            selected = newMap
            optionObj:SetValue(newMap)
            updateHeader()
            for _, row in ipairs(rows) do
                local on = selected[row.key] == true
                row.check.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                row.nameLabel.TextColor3 = on and palette.text or palette.textDim
            end
        end

        local function clearRows()
            for _, row in ipairs(rows) do
                if row.button then
                    row.button:Destroy()
                end
            end
            rows = {}
        end

        local function refreshRows()
            clearRows()
            local entries = getPlayerNamesLive()
            local valid = {}
            for _, entry in ipairs(entries) do
                valid[entry.username] = true
            end

            local changed = false
            for name, state in pairs(selected) do
                if state and not valid[name] then
                    selected[name] = nil
                    changed = true
                end
            end
            if changed then
                optionObj:SetValue(selected)
            end

            if #entries == 0 then
                local empty = Instance.new('TextLabel')
                empty.BackgroundTransparency = 1
                empty.Size = UDim2.new(1, 0, 0, 20)
                empty.Font = Enum.Font.Gotham
                empty.TextColor3 = palette.textDim
                empty.TextSize = 11
                empty.TextXAlignment = Enum.TextXAlignment.Left
                empty.Text = 'No other players in server'
                empty.Parent = listFrame
                rows[1] = {
                    button = empty,
                    key = '__empty__',
                    check = { BackgroundColor3 = palette.surface },
                    nameLabel = empty
                }
                updateHeader()
                return
            end

            for _, entry in ipairs(entries) do
                local rowBtn = Instance.new('TextButton')
                rowBtn.AutoButtonColor = false
                rowBtn.BackgroundColor3 = palette.surfaceSoft
                rowBtn.Size = UDim2.new(1, 0, 0, 26)
                rowBtn.Text = ''
                rowBtn.Parent = listFrame
                applyCorner(rowBtn, 7)

                local check = Instance.new('Frame')
                check.Size = UDim2.fromOffset(14, 14)
                check.Position = UDim2.new(0, 6, 0.5, -7)
                check.BackgroundColor3 = palette.surfaceElevated
                check.Parent = rowBtn
                applyCorner(check, 4)
        applyStroke(check, 'strokeSoft', 1, 0.45)

                local nameLabel = Instance.new('TextLabel')
                nameLabel.BackgroundTransparency = 1
                nameLabel.Position = UDim2.fromOffset(28, 0)
                nameLabel.Size = UDim2.new(1, -30, 1, 0)
                nameLabel.Font = Enum.Font.Gotham
                nameLabel.TextSize = 12
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.Text = entry.label
                nameLabel.Parent = rowBtn

                local rowEntry = {
                    button = rowBtn,
                    key = entry.username,
                    check = check,
                    nameLabel = nameLabel,
                }
                table.insert(rows, rowEntry)

                local function renderRow()
                    local on = selected[entry.username] == true
                    check.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                    nameLabel.TextColor3 = on and palette.text or palette.textDim
                end

safeConnect(rowBtn.MouseButton1Click, function()
                    local newMap = normalizeSelection(selected)
                    if newMap[entry.username] then
                        newMap[entry.username] = nil
                    else
                        newMap[entry.username] = true
                    end
                    setSelectedAndSync(newMap)
                end)

                renderRow()
            end

            updateHeader()
            if opened then
                runLater(0, function()
                    syncListHeight(false)
                end)
            end
        end

safeConnect(dropdownBtn.MouseButton1Click, function()
            if opened then
                hideList()
            else
                showList()
            end
            updateHeader()
        end)

        attachChangeListener(optionObj, function()
            selected = normalizeSelection(optionObj.Value)
            refreshRows()
        end)

        safeConnect(listLayout:GetPropertyChangedSignal('AbsoluteContentSize'), function()
            if opened then
                syncListHeight(false)
            end
        end)

trackConnection(safeConnect(Players.PlayerAdded, function()
            refreshRows()
        end))
trackConnection(safeConnect(Players.PlayerRemoving, function()
            refreshRows()
        end))

        refreshRows()
        updateHeader()
    end

    createSinglePlayerDropdown = function(parent, caption, optionObj)
        local container = Instance.new('Frame')
        container.Name = 'Dropdown_' .. tostring(caption)
        container.Size = UDim2.new(1, 0, 0, 36)
        container.BackgroundTransparency = 1
        container.BorderSizePixel = 0
        container.Parent = parent

        local lbl = Instance.new('TextLabel')
        lbl.Name = 'Label'
        lbl.Position = UDim2.new(0, 0, 0, 0)
        lbl.Size = UDim2.new(1, 0, 0, 12)
        lbl.BackgroundTransparency = 1
        lbl.Text = tostring(caption)
        lbl.TextColor3 = Color3.fromHex('FFFFFF')
        lbl.TextSize = 12
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.Parent = container

        local btn = Instance.new('TextButton')
        btn.Name = 'Btn'
        btn.AnchorPoint = Vector2.new(0, 1)
        btn.Position = UDim2.new(0, 0, 1, 0)
        btn.Size = UDim2.new(1, 0, 0, 21)
        btn.BackgroundColor3 = Color3.fromHex('000000')
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Text = ''
        btn.Parent = container

        local bGray = Instance.new('Frame')
        bGray.Position = UDim2.new(0, 1, 0, 1)
        bGray.Size = UDim2.new(1, -2, 1, -2)
        bGray.BackgroundColor3 = Color3.fromHex('393939')
        bGray.BorderSizePixel = 0
        bGray.Parent = btn

        local bInside = Instance.new('Frame')
        bInside.Position = UDim2.new(0, 1, 0, 1)
        bInside.Size = UDim2.new(1, -2, 1, -2)
        bInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        bInside.BorderSizePixel = 0
        bInside.Parent = bGray

        local bGrad = Instance.new('UIGradient')
        bGrad.Rotation = 90
        bGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
        })
        bGrad.Parent = bInside

        local valLbl = Instance.new('TextLabel')
        valLbl.Name = 'Value'
        valLbl.Position = UDim2.new(0, 6, 0, 0)
        valLbl.Size = UDim2.new(1, -24, 1, 0)
        valLbl.BackgroundTransparency = 1
        valLbl.BorderSizePixel = 0
        valLbl.TextColor3 = Color3.fromHex('FFFFFF')
        valLbl.TextSize = 12
        valLbl.Font = Enum.Font.Gotham
        valLbl.TextXAlignment = Enum.TextXAlignment.Left
        valLbl.TextYAlignment = Enum.TextYAlignment.Center
        valLbl.TextTruncate = Enum.TextTruncate.AtEnd
        valLbl.ClipsDescendants = true
        valLbl.Parent = bInside

        local arrow = Instance.new('TextLabel')
        arrow.Name = 'Arrow'
        arrow.AnchorPoint = Vector2.new(1, 0)
        arrow.Position = UDim2.new(1, -4, 0, 0)
        arrow.Size = UDim2.new(0, 16, 1, 0)
        arrow.BackgroundTransparency = 1
        arrow.BorderSizePixel = 0
        arrow.TextColor3 = Color3.fromHex('8C8F99')
        arrow.TextSize = 10
        arrow.Font = Enum.Font.Gotham
        arrow.Text = 'v'
        arrow.TextXAlignment = Enum.TextXAlignment.Center
        arrow.TextYAlignment = Enum.TextYAlignment.Center
        arrow.Parent = bInside

        local popup = Instance.new('Frame')
        popup.Name = 'DropdownPopup_' .. tostring(caption)
        popup.BackgroundColor3 = Color3.fromHex('000000')
        popup.BorderSizePixel = 0
        popup.Visible = false
        popup.ZIndex = 200
        popup.Parent = menuGroup or parent

        local pGray = Instance.new('Frame')
        pGray.Position = UDim2.new(0, 1, 0, 1)
        pGray.Size = UDim2.new(1, -2, 1, -2)
        pGray.BackgroundColor3 = Color3.fromHex('393939')
        pGray.BorderSizePixel = 0
        pGray.ZIndex = 201
        pGray.Parent = popup

        local pInside = Instance.new('Frame')
        pInside.Position = UDim2.new(0, 1, 0, 1)
        pInside.Size = UDim2.new(1, -2, 1, -2)
        pInside.BackgroundColor3 = Color3.fromHex('131313')
        pInside.BorderSizePixel = 0
        pInside.ZIndex = 202
        pInside.Parent = pGray

        local scroll = Instance.new('ScrollingFrame')
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.Position = UDim2.new(0, 1, 0, 1)
        scroll.Size = UDim2.new(1, -2, 1, -2)
        scroll.ScrollBarThickness = 2
        scroll.ScrollBarImageColor3 = getActiveAccent()
        scroll.CanvasSize = UDim2.fromOffset(0, 0)
        scroll.ZIndex = 203
        scroll.Parent = pInside
        bindTheme(scroll, 'ScrollBarImageColor3', 'accent')

        local scrollList = Instance.new('UIListLayout')
        scrollList.Padding = UDim.new(0, 1)
        scrollList.SortOrder = Enum.SortOrder.LayoutOrder
        scrollList.Parent = scroll

        local selected = type(optionObj.Value) == 'string' and optionObj.Value or ''
        local opened = false

        local function getSelectedDisplay()
            if selected == nil or selected == '' then
                return '(none)'
            end
            local entries = getPlayerNamesLive()
            for _, entry in ipairs(entries) do
                if entry.username == selected then
                    return entry.label
                end
            end
            return selected
        end

        local function updateHeader()
            local disp = getSelectedDisplay()
            valLbl.Text = disp
            if selected == '' or selected == nil then
                valLbl.TextColor3 = Color3.fromHex('8C8F99')
            else
                valLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end

        local function closePopup()
            if not opened then
                return
            end
            opened = false
            popup.Visible = false
            arrow.Text = 'v'
            arrow.TextColor3 = Color3.fromHex('8C8F99')
        end

        local function openPopup()
            opened = true
            for _, ch in ipairs(scroll:GetChildren()) do
                if ch:IsA('TextButton') then
                    pcall(function() ch:Destroy() end)
                end
            end

            local entries = getPlayerNamesLive()
            local allOptions = {
                { username = '', label = '(none)' }
            }
            for _, e in ipairs(entries) do
                table.insert(allOptions, e)
            end

            for i, opt in ipairs(allOptions) do
                local optBtn = Instance.new('TextButton')
                optBtn.Name = 'Option_' .. tostring(opt.username)
                optBtn.LayoutOrder = i
                optBtn.Size = UDim2.new(1, 0, 0, 18)
                optBtn.BackgroundTransparency = 1
                optBtn.BackgroundColor3 = Color3.fromHex('1E1E1E')
                optBtn.AutoButtonColor = false
                optBtn.BorderSizePixel = 0
                optBtn.Text = ''
                optBtn.ZIndex = 204
                optBtn.Parent = scroll

                local optLbl = Instance.new('TextLabel')
                optLbl.BackgroundTransparency = 1
                optLbl.Position = UDim2.new(0, 6, 0, 0)
                optLbl.Size = UDim2.new(1, -12, 1, 0)
                optLbl.Font = Enum.Font.Gotham
                optLbl.TextSize = 11
                optLbl.TextXAlignment = Enum.TextXAlignment.Left
                optLbl.TextYAlignment = Enum.TextYAlignment.Center
                optLbl.TextTruncate = Enum.TextTruncate.AtEnd
                optLbl.Text = opt.label
                optLbl.ZIndex = 205

                local isCur = (opt.username == selected) or (opt.username == '' and (selected == '' or selected == nil))
                optLbl.TextColor3 = isCur and getActiveAccent() or Color3.fromHex('D5D5D5')
                optLbl.Parent = optBtn

                safeConnect(optBtn.MouseEnter, function()
                    optBtn.BackgroundTransparency = 0
                    if not isCur then
                        optLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                    end
                end)
                safeConnect(optBtn.MouseLeave, function()
                    optBtn.BackgroundTransparency = 1
                    if not isCur then
                        optLbl.TextColor3 = Color3.fromHex('D5D5D5')
                    end
                end)

                safeConnect(optBtn.MouseButton1Click, function()
                    selected = opt.username
                    optionObj:SetValue(opt.username)
                    updateHeader()
                    closePopup()
                    if type(requestSaveConfig) == 'function' then
                        requestSaveConfig()
                    end
                end)
            end

            local totalH = #allOptions * 19
            local visibleH = math.clamp(totalH + 4, 22, 136)
            scroll.CanvasSize = UDim2.fromOffset(0, totalH)
            scroll.ScrollBarImageColor3 = getActiveAccent()

            local absPos = btn.AbsolutePosition
            local absSize = btn.AbsoluteSize
            popup.Size = UDim2.fromOffset(absSize.X, visibleH)
            popup.Position = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 2)
            popup.Visible = true
            arrow.Text = '^'
            arrow.TextColor3 = getActiveAccent()
        end

        safeConnect(btn.MouseEnter, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('262626')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
            })
        end)
        safeConnect(btn.MouseLeave, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
        end)

        safeConnect(btn.MouseButton1Click, function()
            if opened then
                closePopup()
            else
                openPopup()
            end
        end)

        safeConnect(UIS.InputBegan, function(input)
            if not opened then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local pos = input.Position
                local function inside(inst)
                    if not inst or not inst.Parent then
                        return false
                    end
                    local p = inst.AbsolutePosition
                    local s = inst.AbsoluteSize
                    return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
                end
                if not inside(btn) and not inside(popup) then
                    closePopup()
                end
            end
        end)

        if main then
            safeConnect(main:GetPropertyChangedSignal('Position'), function()
                if opened then
                    closePopup()
                end
            end)
            safeConnect(main:GetPropertyChangedSignal('Size'), function()
                if opened then
                    closePopup()
                end
            end)
        end

        attachChangeListener(optionObj, function()
            local value = optionObj.Value
            if type(value) ~= 'string' then
                value = ''
            end
            selected = value
            updateHeader()
        end)

        local function refreshScrollAccent()
            if isGuiAlive(scroll) then
                scroll.ScrollBarImageColor3 = getActiveAccent()
            end
            if isGuiAlive(arrow) and opened then
                arrow.TextColor3 = getActiveAccent()
            end
        end

        registerThemeRefresher(refreshScrollAccent)
        if State and State.ThemeAccent then
            attachChangeListener(State.ThemeAccent, refreshScrollAccent)
        end
        if Options and Options.ThemeAccent then
            attachChangeListener(Options.ThemeAccent, refreshScrollAccent)
        end

        safeConnect(container.AncestryChanged, function()
            if not container:IsDescendantOf(game) then
                pcall(function() popup:Destroy() end)
            end
        end)

        trackConnection(safeConnect(Players.PlayerAdded, function()
            updateHeader()
        end))
        trackConnection(safeConnect(Players.PlayerRemoving, function(pl)
            if pl and pl.Name == selected then
                selected = ''
                optionObj:SetValue('')
            end
            updateHeader()
        end))

        updateHeader()
        return container
    end

    createStringDropdown = function(parent, caption, optionObj, values, dropdownOpts)
        dropdownOpts = type(dropdownOpts) == 'table' and dropdownOpts or {}
        local headerMode = dropdownOpts.header == true
        local valuesList = type(values) == 'table' and values or {}
        local overlayParent = (headerMode and menuGroup) or parent
        local block = Instance.new('Frame')
        block.Name = 'StringDropdown'
        if headerMode then
            block.BackgroundTransparency = 1
            block.AnchorPoint = Vector2.new(1, 0)
            block.Position = UDim2.new(1, -uiMetrics.sectionPadSide, 0, uiMetrics.sectionPad)
            block.Size = UDim2.fromOffset(210, 26)
            block.ZIndex = 50
        else
            block.BackgroundColor3 = palette.surfaceElevated
            block.BackgroundTransparency = 0.3
            block.Size = UDim2.new(1, 0, 0, 40)
            block.AutomaticSize = Enum.AutomaticSize.Y
        end
        block.BorderSizePixel = 0
        block.Parent = parent
        if not headerMode then
            applyCorner(block, 5)
            addHover(block, 'surfaceElevated', 'surfaceSoft')
        end

        local clickBlocker
        if headerMode and overlayParent then
            clickBlocker = Instance.new('TextButton')
            clickBlocker.Name = 'DropdownBlocker'
            clickBlocker.AutoButtonColor = false
            clickBlocker.BackgroundTransparency = 1
            clickBlocker.Size = UDim2.new(1, 0, 1, 0)
            clickBlocker.Text = ''
            clickBlocker.Visible = false
            clickBlocker.ZIndex = 49
            clickBlocker.Parent = overlayParent
        end

        local pad
        if not headerMode then
            pad = Instance.new('UIPadding')
            pad.PaddingTop = UDim.new(0, 6)
            pad.PaddingBottom = UDim.new(0, 6)
            pad.PaddingLeft = UDim.new(0, 8)
            pad.PaddingRight = UDim.new(0, 8)
            pad.Parent = block

            local list = Instance.new('UIListLayout')
            list.Padding = UDim.new(0, 5)
            list.Parent = block
        end

        local dropdownBtn = Instance.new('TextButton')
        dropdownBtn.AutoButtonColor = false
        dropdownBtn.BackgroundColor3 = palette.surface
        dropdownBtn.Size = headerMode and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0, 26)
        dropdownBtn.Font = Enum.Font.GothamSemibold
        dropdownBtn.TextColor3 = palette.text
        dropdownBtn.TextSize = 12
        dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
        dropdownBtn.Text = '  ' .. caption
        dropdownBtn.BorderSizePixel = 0
        dropdownBtn.ZIndex = headerMode and 51 or 7
        dropdownBtn.Parent = block
        applyCorner(dropdownBtn, 5)
        applyStroke(dropdownBtn, 'strokeSoft', 1, 0.55)
        addHover(dropdownBtn, 'surface', 'surfaceSoft')

        local listFrame = Instance.new('Frame')
        listFrame.Name = 'DropdownList'
        listFrame.BackgroundColor3 = palette.surface
        listFrame.BackgroundTransparency = 0
        listFrame.Size = UDim2.new(1, 0, 0, 0)
        listFrame.Visible = false
        listFrame.BorderSizePixel = 0
        listFrame.Active = true
        listFrame.ClipsDescendants = true
        listFrame.ZIndex = headerMode and 52 or 8
        listFrame.Parent = headerMode and overlayParent or block
        if headerMode then
            listFrame.AnchorPoint = Vector2.new(1, 0)
            listFrame.Size = UDim2.fromOffset(210, 0)
        end
        applyCorner(listFrame, 5)
        local listStroke = applyStroke(listFrame, 'stroke', 1, 0.6)
        local listBaseTransparency = listFrame.BackgroundTransparency
        local listStrokeBaseTransparency = listStroke.Transparency

        local listPad = Instance.new('UIPadding')
        listPad.PaddingTop = UDim.new(0, 6)
        listPad.PaddingBottom = UDim.new(0, 6)
        listPad.PaddingLeft = UDim.new(0, 6)
        listPad.PaddingRight = UDim.new(0, 6)
        listPad.Parent = listFrame

        local listLayout = Instance.new('UIListLayout')
        listLayout.Padding = UDim.new(0, 4)
        listLayout.Parent = listFrame

        local selected = type(optionObj.Value) == 'string' and optionObj.Value or tostring(valuesList[1] or '')
        local opened = false
        local rows = {}

        local function syncFloatingPosition()
            if not headerMode or not overlayParent or not dropdownBtn or not listFrame then
                return
            end
            local btnPos = dropdownBtn.AbsolutePosition
            local btnSize = dropdownBtn.AbsoluteSize
            local overlayPos = overlayParent.AbsolutePosition
            listFrame.Position = UDim2.fromOffset(
                btnPos.X + btnSize.X - overlayPos.X,
                btnPos.Y + btnSize.Y + 4 - overlayPos.Y
            )
        end

        local function getListHeight()
            local padH = listPad.PaddingTop.Offset + listPad.PaddingBottom.Offset
            local contentH = listLayout.AbsoluteContentSize.Y
            return math.max(0, contentH + padH)
        end

        local function syncListHeight(instant)
            if not opened then
                return
            end
            local h = getListHeight()
            local size = headerMode and UDim2.fromOffset(210, h) or UDim2.new(1, 0, 0, h)
            if instant then
                listFrame.Size = size
            else
                tween(listFrame, 0.14, { Size = size })
            end
        end

        local function showList()
            opened = true
            if clickBlocker then
                clickBlocker.Visible = true
            end
            if headerMode then
                syncFloatingPosition()
            end
            listFrame.Visible = true
            listFrame.AutomaticSize = Enum.AutomaticSize.None
            listFrame.Size = headerMode and UDim2.fromOffset(210, 0) or UDim2.new(1, 0, 0, 0)
            listFrame.BackgroundTransparency = headerMode and 0 or 1
            listStroke.Transparency = headerMode and listStrokeBaseTransparency or 1
            if not headerMode then
                tween(listFrame, 0.14, { BackgroundTransparency = listBaseTransparency })
                tween(listStroke, 0.14, { Transparency = listStrokeBaseTransparency })
            end
            runLater(0, function()
                if headerMode then
                    syncFloatingPosition()
                end
                syncListHeight(false)
            end)
        end

        local function hideList()
            opened = false
            if clickBlocker then
                clickBlocker.Visible = false
            end
            local closedSize = headerMode and UDim2.fromOffset(210, 0) or UDim2.new(1, 0, 0, 0)
            if headerMode then
                listFrame.Size = closedSize
                listFrame.Visible = false
                listFrame.BackgroundTransparency = 0
                listStroke.Transparency = listStrokeBaseTransparency
            else
                tween(listFrame, 0.12, { Size = closedSize })
                tween(listFrame, 0.12, { BackgroundTransparency = 1 })
                tween(listStroke, 0.12, { Transparency = 1 })
                runLater(0.13, function()
                    listFrame.Visible = false
                    listFrame.BackgroundTransparency = listBaseTransparency
                    listStroke.Transparency = listStrokeBaseTransparency
                    listFrame.AutomaticSize = Enum.AutomaticSize.Y
                end)
            end
        end

        local function updateHeader()
            dropdownBtn.Text = string.format('  %s (%s)', caption, selected ~= '' and selected or 'none')
        end

        local function clearRows()
            for _, row in ipairs(rows) do
                if row.button then
                    row.button:Destroy()
                end
            end
            rows = {}
        end

        local function renderRows()
            clearRows()
            for _, value in ipairs(valuesList) do
                local name = tostring(value)
                local rowBtn = Instance.new('TextButton')
                rowBtn.AutoButtonColor = false
                rowBtn.BackgroundColor3 = palette.surfaceElevated
                rowBtn.BackgroundTransparency = 0.35
                rowBtn.Size = UDim2.new(1, 0, 0, 24)
                rowBtn.Font = Enum.Font.GothamSemibold
                rowBtn.TextSize = 12
                rowBtn.TextXAlignment = Enum.TextXAlignment.Left
                rowBtn.Text = '  ' .. name
                rowBtn.TextColor3 = palette.text
                rowBtn.BorderSizePixel = 0
                rowBtn.ZIndex = headerMode and 53 or 9
                rowBtn.Parent = listFrame
                applyCorner(rowBtn, 7)
                bindTheme(rowBtn, 'TextColor3', 'text')

                local rowEntry = {
                    button = rowBtn,
                    key = name,
                }
                table.insert(rows, rowEntry)

                local function renderRow()
                    local on = selected == name
                    rowBtn.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                    rowBtn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or palette.text
                end

                safeConnect(rowBtn.MouseButton1Click, function()
                    selected = name
                    optionObj:SetValue(name)
                    if type(applyThemePreset) == 'function' and caption == 'Theme Preset' then
                        applyThemePreset(name)
                    elseif type(requestSaveConfig) == 'function' then
                        requestSaveConfig()
                    end
                    updateHeader()
                    for _, row in ipairs(rows) do
                        local on = selected == row.key
                        row.button.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                        row.button.TextColor3 = on and Color3.fromRGB(255, 255, 255) or palette.text
                    end
                    hideList()
                end)

                renderRow()
            end
            updateHeader()
            if opened then
                runLater(0, function()
                    syncListHeight(false)
                end)
            end
        end

        safeConnect(dropdownBtn.MouseButton1Click, function()
            if opened then
                hideList()
            else
                showList()
            end
            updateHeader()
        end)

        if clickBlocker then
            safeConnect(clickBlocker.MouseButton1Click, function()
                hideList()
            end)
        end

        attachChangeListener(optionObj, function()
            local value = optionObj.Value
            if type(value) ~= 'string' then
                value = tostring(valuesList[1] or '')
            end
            selected = value
            updateHeader()
            for _, row in ipairs(rows) do
                local on = selected == row.key
                row.button.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                row.button.TextColor3 = on and Color3.fromRGB(255, 255, 255) or palette.text
            end
        end)

        safeConnect(listLayout:GetPropertyChangedSignal('AbsoluteContentSize'), function()
            if opened then
                syncListHeight(false)
            end
        end)

        bindTheme(block, 'BackgroundColor3', 'surfaceElevated')
        bindTheme(dropdownBtn, 'BackgroundColor3', 'surface')
        bindTheme(dropdownBtn, 'TextColor3', 'text')
        bindTheme(listFrame, 'BackgroundColor3', 'surface')
        if headerMode then
            block.BackgroundTransparency = 1
        end

        renderRows()
        updateHeader()
        return block
    end

    createCycleOptionRow = function(parent, caption, optionObj, values)
        local row = Instance.new('Frame')
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, 0, 0, 21)
        row.BorderSizePixel = 0
        row.Parent = parent

        local label = Instance.new('TextLabel')
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(0, 0)
        label.Size = UDim2.new(1, -125, 1, 0)
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromHex('8C8F99')
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Text = caption
        label.Parent = row

        local bOuter = Instance.new('Frame')
        bOuter.AnchorPoint = Vector2.new(1, 0.5)
        bOuter.Position = UDim2.new(1, 0, 0.5, 0)
        bOuter.Size = UDim2.fromOffset(120, 21)
        bOuter.BackgroundColor3 = Color3.fromHex('000000')
        bOuter.BorderSizePixel = 0
        bOuter.Parent = row

        local bGray = Instance.new('Frame')
        bGray.Position = UDim2.new(0, 1, 0, 1)
        bGray.Size = UDim2.new(1, -2, 1, -2)
        bGray.BackgroundColor3 = Color3.fromHex('393939')
        bGray.BorderSizePixel = 0
        bGray.Parent = bOuter

        local bInside = Instance.new('Frame')
        bInside.Position = UDim2.new(0, 1, 0, 1)
        bInside.Size = UDim2.new(1, -2, 1, -2)
        bInside.BackgroundColor3 = Color3.fromRGB(27, 27, 27)
        bInside.BorderSizePixel = 0
        bInside.Parent = bGray

        local bGrad = Instance.new('UIGradient')
        bGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 27)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 18))
        })
        bGrad.Rotation = 90
        bGrad.Parent = bInside

        local button = Instance.new('TextButton')
        button.AutoButtonColor = false
        button.BackgroundTransparency = 1
        button.Size = UDim2.new(1, 0, 1, 0)
        button.Font = Enum.Font.Gotham
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 11
        button.BorderSizePixel = 0
        button.Parent = bInside

        local function currentIndex()
            local current = type(optionObj.Value) == 'string' and optionObj.Value or tostring(values[1] or '')
            for i, v in ipairs(values) do
                if tostring(v) == current then
                    return i
                end
            end
            return 1
        end

        local function render()
            local idx = currentIndex()
            button.Text = tostring(values[idx] or '')
        end

        safeConnect(button.MouseEnter, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 38, 38)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 24))
            })
        end)
        safeConnect(button.MouseLeave, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 27)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 18))
            })
        end)

        safeConnect(button.MouseButton1Click, function()
            local idx = currentIndex() + 1
            if idx > #values then
                idx = 1
            end
            optionObj:SetValue(tostring(values[idx]))
            render()
        end)

        attachChangeListener(optionObj, function()
            render()
        end)

        render()
        return row
    end

    createInventorySlotDropdownRow = function(parent, caption, optionObj)
        local block = Instance.new('Frame')
        block.BackgroundColor3 = palette.surfaceElevated
        block.BackgroundTransparency = 0.3
        block.Size = UDim2.new(1, 0, 0, 40)
        block.AutomaticSize = Enum.AutomaticSize.Y
        block.BorderSizePixel = 0
        block.Parent = parent
        applyCorner(block, 5)
        addHover(block, 'surfaceElevated', 'surfaceSoft')

        local pad = Instance.new('UIPadding')
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 6)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = block

        local list = Instance.new('UIListLayout')
        list.Padding = UDim.new(0, 5)
        list.Parent = block

        local dropdownBtn = Instance.new('TextButton')
        dropdownBtn.AutoButtonColor = false
        dropdownBtn.BackgroundColor3 = palette.surface
        dropdownBtn.Size = UDim2.new(1, 0, 0, 26)
        dropdownBtn.Font = Enum.Font.GothamSemibold
        dropdownBtn.TextColor3 = palette.text
        dropdownBtn.TextSize = 12
        dropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
        dropdownBtn.Text = '  ' .. caption
        dropdownBtn.BorderSizePixel = 0
        dropdownBtn.Parent = block
        applyCorner(dropdownBtn, 5)
        addHover(dropdownBtn, 'surface', 'surfaceSoft')

        local listFrame = Instance.new('Frame')
        listFrame.BackgroundColor3 = palette.surface
        listFrame.Size = UDim2.new(1, 0, 0, 0)
        listFrame.AutomaticSize = Enum.AutomaticSize.Y
        listFrame.Visible = false
        listFrame.BorderSizePixel = 0
        listFrame.Parent = block
        applyCorner(listFrame, 5)
        local listStroke = applyStroke(listFrame, 'stroke', 1, 0.6)
        local listBaseTransparency = listFrame.BackgroundTransparency
        local listStrokeBaseTransparency = listStroke.Transparency

        local listPad = Instance.new('UIPadding')
        listPad.PaddingTop = UDim.new(0, 6)
        listPad.PaddingBottom = UDim.new(0, 6)
        listPad.PaddingLeft = UDim.new(0, 6)
        listPad.PaddingRight = UDim.new(0, 6)
        listPad.Parent = listFrame

        local listLayout = Instance.new('UIListLayout')
        listLayout.Padding = UDim.new(0, 4)
        listLayout.Parent = listFrame

        local selected = type(optionObj.Value) == 'string' and optionObj.Value or ''
        local opened = false
        local rows = {}

        local function getListHeight()
            local padH = listPad.PaddingTop.Offset + listPad.PaddingBottom.Offset
            local contentH = listLayout.AbsoluteContentSize.Y
            return math.max(0, contentH + padH)
        end

        local function syncListHeight(instant)
            if not opened then
                return
            end
            local h = getListHeight()
            local size = UDim2.new(1, 0, 0, h)
            if instant then
                listFrame.Size = size
            else
                tween(listFrame, 0.14, { Size = size })
            end
        end

        local function showList()
            opened = true
            listFrame.Visible = true
            listFrame.AutomaticSize = Enum.AutomaticSize.None
            listFrame.Size = UDim2.new(1, 0, 0, 0)
            listFrame.BackgroundTransparency = 1
            listStroke.Transparency = 1
            tween(listFrame, 0.14, { BackgroundTransparency = listBaseTransparency })
            tween(listStroke, 0.14, { Transparency = listStrokeBaseTransparency })
            runLater(0, function()
                syncListHeight(false)
            end)
        end

        local function hideList()
            opened = false
            tween(listFrame, 0.12, { Size = UDim2.new(1, 0, 0, 0) })
            tween(listFrame, 0.12, { BackgroundTransparency = 1 })
            tween(listStroke, 0.12, { Transparency = 1 })
            runLater(0.13, function()
                listFrame.Visible = false
                listFrame.BackgroundTransparency = listBaseTransparency
                listStroke.Transparency = listStrokeBaseTransparency
                listFrame.AutomaticSize = Enum.AutomaticSize.Y
            end)
        end

        local function updateHeader()
            if selected ~= '' then
                dropdownBtn.Text = string.format('  %s (%s)', caption, selected)
            else
                dropdownBtn.Text = string.format('  %s (none)', caption)
            end
        end

        local function clearRows()
            for _, row in ipairs(rows) do
                if row.button then
                    row.button:Destroy()
                end
            end
            rows = {}
        end

        local function renderRows()
            for _, row in ipairs(rows) do
                local on = selected ~= '' and row.key == selected
                row.check.BackgroundColor3 = on and palette.accent or palette.surfaceElevated
                row.nameLabel.TextColor3 = on and palette.text or palette.textDim
            end
        end

        local function setSelected(value, syncOption)
            local normalized = value
            if type(normalized) ~= 'string' then
                normalized = ''
            end
            selected = normalized
            if syncOption ~= false then
                optionObj:SetValue(selected)
            end
            updateHeader()
            renderRows()
        end

        local function addRow(displayText, key)
            local rowBtn = Instance.new('TextButton')
            rowBtn.AutoButtonColor = false
            rowBtn.BackgroundColor3 = palette.surfaceSoft
            rowBtn.Size = UDim2.new(1, 0, 0, 26)
            rowBtn.Text = ''
            rowBtn.Parent = listFrame
            applyCorner(rowBtn, 7)

            local check = Instance.new('Frame')
            check.Size = UDim2.fromOffset(14, 14)
            check.Position = UDim2.new(0, 6, 0.5, -7)
            check.BackgroundColor3 = palette.surfaceElevated
            check.Parent = rowBtn
            applyCorner(check, 4)
            applyStroke(check, 'strokeSoft', 1, 0.45)

            local nameLabel = Instance.new('TextLabel')
            nameLabel.BackgroundTransparency = 1
            nameLabel.Position = UDim2.fromOffset(28, 0)
            nameLabel.Size = UDim2.new(1, -30, 1, 0)
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextSize = 12
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Text = displayText
            nameLabel.Parent = rowBtn

            local rowEntry = {
                button = rowBtn,
                key = key,
                check = check,
                nameLabel = nameLabel,
            }
            table.insert(rows, rowEntry)

            safeConnect(rowBtn.MouseButton1Click, function()
                setSelected(key)
                if opened then
                    hideList()
                end
            end)
        end

        local function refreshRows()
            clearRows()
            addRow('(none)', '')

            local entries = getInventoryToolNames()
            local selectedStillValid = (selected == '')
            for _, toolName in ipairs(entries) do
                if toolName == selected then
                    selectedStillValid = true
                end
                addRow(toolName, toolName)
            end

            if not selectedStillValid then
                setSelected('', true)
            else
                updateHeader()
                renderRows()
            end

            if opened then
                runLater(0, function()
                    syncListHeight(false)
                end)
            end
        end

        safeConnect(dropdownBtn.MouseButton1Click, function()
            if opened then
                hideList()
            else
                refreshRows()
                showList()
            end
            updateHeader()
        end)

        attachChangeListener(optionObj, function()
            local value = optionObj.Value
            if type(value) ~= 'string' then
                value = ''
            end
            selected = value
            refreshRows()
        end)

        safeConnect(listLayout:GetPropertyChangedSignal('AbsoluteContentSize'), function()
            if opened then
                syncListHeight(false)
            end
        end)

        refreshRows()
        updateHeader()

        local handle = { row = block }
        function handle:setVisible(visible)
            block.Visible = visible == true
        end
        return handle
    end

    local function beginCapture(optionObj, button)
        keybindCapture = {
            option = optionObj,
            button = button,
            startedAt = os.clock()
        }
        button.Text = '...'
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    createKeybindRow = function(parent, caption, optionObj)
        local row = Instance.new('Frame')
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BorderSizePixel = 0
        row.ClipsDescendants = false
        row.Parent = parent

        local label = Instance.new('TextLabel')
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(4, 0)
        label.Size = UDim2.new(1, -70, 1, 0)
        label.Font = fonts.body
        label.TextColor3 = palette.text
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = caption
        label.Parent = row
        bindTheme(label, 'TextColor3', 'text')

        local button = Instance.new('TextButton')
        button.AutoButtonColor = false
        button.AnchorPoint = Vector2.new(1, 0.5)
        button.Position = UDim2.new(1, -4, 0.5, 0)
        button.Size = UDim2.fromOffset(56, 16)
        button.BackgroundColor3 = palette.surface
        button.Font = fonts.mono
        button.TextColor3 = palette.accent
        button.TextSize = 10
        button.Text = keyName(optionObj.Value)
        button.BorderSizePixel = 0
        button.Parent = row
        applyCorner(button, 8)
        applyStroke(button, 'strokeSoft', 1, 0.5)
        bindTheme(button, 'BackgroundColor3', 'surface')
        bindTheme(button, 'TextColor3', 'accent')

        local modeMenu = Instance.new('Frame')
        modeMenu.Name = 'ModeMenu'
        modeMenu.Visible = false
        modeMenu.AnchorPoint = Vector2.new(1, 0)
        modeMenu.Position = UDim2.new(1, -4, 1, 2)
        modeMenu.BackgroundColor3 = palette.surface
        modeMenu.BorderSizePixel = 0
        modeMenu.ZIndex = 20
        modeMenu.AutomaticSize = Enum.AutomaticSize.Y
        modeMenu.Size = UDim2.fromOffset(90, 0)
        modeMenu.ClipsDescendants = true
        modeMenu.Parent = row
        applyCorner(modeMenu, 8)
        applyStroke(modeMenu, 'strokeSoft', 1, 0.3)
        bindTheme(modeMenu, 'BackgroundColor3', 'surface')

        local modeList = Instance.new('UIListLayout')
        modeList.Padding = UDim.new(0, 1)
        modeList.SortOrder = Enum.SortOrder.LayoutOrder
        modeList.Parent = modeMenu
        local modePad = Instance.new('UIPadding')
        modePad.PaddingTop = UDim.new(0, 3)
        modePad.PaddingBottom = UDim.new(0, 3)
        modePad.PaddingLeft = UDim.new(0, 3)
        modePad.PaddingRight = UDim.new(0, 3)
        modePad.Parent = modeMenu

        local function refreshButtonText()
            button.Text = keyName(optionObj.Value)
            button.TextColor3 = palette.accent
        end

        safeConnect(button.MouseButton1Click, function()
            modeMenu.Visible = false
            beginCapture(optionObj, button)
        end)

        safeConnect(button.MouseButton2Click, function()
            modeMenu.Visible = not modeMenu.Visible
        end)

        for _, m in ipairs({ 'Hold', 'Toggle', 'Always' }) do
            local mb = Instance.new('TextButton')
            mb.AutoButtonColor = false
            mb.Size = UDim2.new(1, 0, 0, 18)
            mb.BackgroundColor3 = palette.surfaceElevated
            mb.BackgroundTransparency = 0.3
            mb.BorderSizePixel = 0
            mb.Font = fonts.body
            mb.TextSize = 11
            mb.TextColor3 = palette.textDim
            mb.Text = m
            mb.ZIndex = 21
            mb.Parent = modeMenu
            applyCorner(mb, 6)
            bindTheme(mb, 'BackgroundColor3', 'surfaceElevated')
            bindTheme(mb, 'TextColor3', 'textDim')
            safeConnect(mb.MouseButton1Click, function()
                if type(optionObj.SetMode) == 'function' then
                    optionObj:SetMode(m)
                end
                modeMenu.Visible = false
                refreshButtonText()
            end)
            safeConnect(mb.MouseEnter, function()
                mb.BackgroundTransparency = 0
                mb.TextColor3 = palette.text
            end)
            safeConnect(mb.MouseLeave, function()
                mb.BackgroundTransparency = 0.3
                mb.TextColor3 = palette.textDim
            end)
        end

        attachChangeListener(optionObj, refreshButtonText)
        refreshButtonText()
        return row
    end

    createButton = function(parent, text, callback)
        local bOuter = Instance.new('Frame')
        bOuter.Size = UDim2.new(1, 0, 0, 21)
        bOuter.BackgroundColor3 = Color3.fromHex('000000')
        bOuter.BorderSizePixel = 0
        bOuter.Parent = parent

        local bGray = Instance.new('Frame')
        bGray.Position = UDim2.new(0, 1, 0, 1)
        bGray.Size = UDim2.new(1, -2, 1, -2)
        bGray.BackgroundColor3 = Color3.fromHex('393939')
        bGray.BorderSizePixel = 0
        bGray.Parent = bOuter

        local bInside = Instance.new('Frame')
        bInside.Position = UDim2.new(0, 1, 0, 1)
        bInside.Size = UDim2.new(1, -2, 1, -2)
        bInside.BackgroundColor3 = Color3.fromRGB(27, 27, 27)
        bInside.BorderSizePixel = 0
        bInside.Parent = bGray

        local bGrad = Instance.new('UIGradient')
        bGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 27)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 18))
        })
        bGrad.Rotation = 90
        bGrad.Parent = bInside

        local btn = Instance.new('TextButton')
        btn.AutoButtonColor = false
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.Font = Enum.Font.Gotham
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 11
        btn.Text = text
        btn.Parent = bInside

        safeConnect(btn.MouseEnter, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 38, 38)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 24))
            })
        end)
        safeConnect(btn.MouseLeave, function()
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 27, 27)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 18))
            })
        end)

        safeConnect(btn.MouseButton1Click, safeCallback(callback))
        return bOuter
    end
    end)()

    ;(function()
    local folderPath = "BomzhoodHub"
    local configDir = "BomzhoodHub/Configs"
    local filePath = "BomzhoodHub/config.json"
    local autoLoadFile = "BomzhoodHub/Autoload.txt"
    local rolesFilePath = "BomzhoodHub/roles.json"

    pcall(function()
        if makefolder then
            if not (isfolder and isfolder(folderPath)) then makefolder(folderPath) end
            if not (isfolder and isfolder(configDir)) then makefolder(configDir) end
        end
    end)

    local knownConfigs = { 'default' }

    local function getConfigFilePath(name)
        local clean = type(name) == 'string' and name or (type(name) == 'table' and (name.Value or name.Name or name.Text)) or nil
        if clean and clean ~= '' and not string.find(tostring(clean), '^table:%s*0x') then
            return configDir .. "/" .. tostring(clean) .. ".json"
        end
        return filePath
    end

    listConfigs = function()
        local out = {}
        local seen = {}
        local function addName(nm)
            local clean = type(nm) == 'string' and nm or (type(nm) == 'table' and (nm.Value or nm.Name or nm.Text)) or nil
            if clean and clean ~= '' and not seen[clean] and not string.match(string.lower(clean), '^autoload') and not string.find(clean, '^table:%s*0x') then
                seen[clean] = true
                table.insert(out, clean)
            end
        end

        for _, nm in ipairs(knownConfigs) do
            addName(nm)
        end

        pcall(function()
            if isfolder and isfolder(configDir) and listfiles then
                for _, f in ipairs(listfiles(configDir)) do
                    if string.find(f, "%.json$") then
                        local nm = tostring(f):gsub(".*[/\\]", ""):gsub("%.json$", "")
                        addName(nm)
                    end
                end
            end
        end)

        if #out == 0 then table.insert(out, "default") end
        table.sort(out)
        return out
    end

    deleteConfig = function(name)
        local clean = type(name) == 'string' and name or (type(name) == 'table' and (name.Value or name.Name or name.Text)) or nil
        if not clean or clean == '' or string.find(clean, '^table:%s*0x') then return end
        pcall(function()
            local p = configDir .. "/" .. tostring(clean) .. ".json"
            if isfile and isfile(p) and delfile then
                delfile(p)
            end
        end)
        for i = #knownConfigs, 1, -1 do
            if knownConfigs[i] == clean then
                table.remove(knownConfigs, i)
            end
        end
    end

    setAutoLoad = function(name)
        pcall(function()
            if writefile then
                writefile(autoLoadFile, tostring(name))
            end
        end)
    end

    clearAutoLoad = function()
        pcall(function()
            if isfile and isfile(autoLoadFile) and delfile then
                delfile(autoLoadFile)
            elseif writefile then
                writefile(autoLoadFile, "")
            end
        end)
    end

    listThemes = function()
        local out = {}
        pcall(function()
            if isfolder and isfolder(themeDir) and listfiles then
                for _, f in ipairs(listfiles(themeDir)) do
                    if string.find(f, "%.json$") then
                        local nm = string.gsub(f, ".*[/\\]", ""):gsub("%.json$", "")
                        table.insert(out, nm)
                    end
                end
            end
        end)
        if #out == 0 then table.insert(out, "default") end
        return out
    end

    saveTheme = function(name)
        if not name or name == '' then return end
        pcall(function()
            local themeData = {
                Accent = palette.accent and palette.accent:ToHex() or '99bcff',
                Preset = State.ThemePreset and State.ThemePreset.Value or 'Default',
                Colors = {}
            }
            for key, optionId in pairs(themeOptionIds) do
                if Options[optionId] and typeof(Options[optionId].Value) == 'Color3' then
                    themeData.Colors[optionId] = Options[optionId].Value:ToHex()
                end
            end
            if not isfolder(themeDir) then makefolder(themeDir) end
            writefile(themeDir .. "\\" .. tostring(name) .. ".json", game:GetService('HttpService'):JSONEncode(themeData))
        end)
    end

    loadTheme = function(name)
        local path = themeDir .. "\\" .. tostring(name) .. ".json"
        local ok, content = pcall(function()
            if isfile and isfile(path) and readfile then
                return readfile(path)
            end
        end)
        if not (ok and content and content ~= '') then return false end
        local ok2, data = pcall(function()
            return game:GetService('HttpService'):JSONDecode(content)
        end)
        if not (ok2 and type(data) == 'table') then return false end
        if data.Accent and Options.ThemeAccent then
            Options.ThemeAccent:SetValue(Color3.fromHex(data.Accent))
        end
        if data.Colors and type(data.Colors) == 'table' then
            for optionId, hex in pairs(data.Colors) do
                if Options[optionId] and type(hex) == 'string' then
                    Options[optionId]:SetValue(Color3.fromHex(hex))
                end
            end
        end
        if data.Preset and Options.ThemePreset then
            Options.ThemePreset:SetValue(data.Preset)
        end
        applyTheme()
        return true
    end

    deleteTheme = function(name)
        pcall(function()
            local p = themeDir .. "\\" .. tostring(name) .. ".json"
            if isfile and isfile(p) and delfile then
                delfile(p)
            end
        end)
    end

    saveRoles = function()
        pcall(function()
            if not writefile then return end
            local store = getSharedRoleStore()
            local rolesData = {
                PlayerRoles = {},
                ByUserId = {}
            }
            local userIdToName = store.byUserIdToName or {}
            for userId, role in pairs(store.byUserId or {}) do
                if role == 'Friend' or role == 'Target' then
                    rolesData.ByUserId[tostring(userId)] = role
                    local resolvedName = userIdToName[userId]
                    if not resolvedName then
                        local player = Players:GetPlayerByUserId(userId)
                        if player then resolvedName = player.Name end
                    end
                    if resolvedName then
                        rolesData.PlayerRoles[resolvedName] = role
                    end
                end
            end
            for key, role in pairs(store.byName or {}) do
                if role == 'Friend' or role == 'Target' then
                    local alreadySaved = false
                    for savedName, _ in pairs(rolesData.PlayerRoles) do
                        if normalizePlayerNameText(savedName) == normalizePlayerNameText(key) then
                            alreadySaved = true
                            break
                        end
                    end
                    if not alreadySaved then
                        rolesData.PlayerRoles[key] = role
                    end
                end
            end
            if makefolder and not (isfolder and isfolder(folderPath)) then
                makefolder(folderPath)
            end
            writefile(rolesFilePath, game:GetService('HttpService'):JSONEncode(rolesData))
        end)
    end

    loadRoles = function()
        pcall(function()
            if not (isfile and isfile(rolesFilePath) and readfile) then return end
            local content = readfile(rolesFilePath)
            if not (content and content ~= '') then return end
            local data = game:GetService('HttpService'):JSONDecode(content)
            if type(data) ~= 'table' then return end

            local store = getSharedRoleStore()
            local rolesMap = data.PlayerRoles or (not data.ByUserId and data) or {}
            if type(rolesMap) == 'table' then
                for rName, role in pairs(rolesMap) do
                    if role == 'Friend' or role == 'Target' then
                        setSharedPlayerRole(rName, role, true)
                    end
                end
            end
            if type(data.ByUserId) == 'table' then
                for uIdStr, role in pairs(data.ByUserId) do
                    local uId = tonumber(uIdStr)
                    if uId and (role == 'Friend' or role == 'Target') then
                        store.byUserId[uId] = normalizeRoleText(role)
                    end
                end
            end
            if refreshRows then
                pcall(refreshRows)
            end
        end)
    end

    local pendingRolesSave = false
    requestSaveRoles = function()
        if pendingRolesSave then return end
        pendingRolesSave = true
        runLater(0.3, function()
            pendingRolesSave = false
            saveRoles()
        end)
    end

    pcall(loadRoles)

    task.spawn(function()
        while true do
            task.wait(60)
            if type(saveRoles) == 'function' then
                pcall(saveRoles)
            end
        end
    end)

    local weaponRangeOptionIds = {
        'TriggerRevolverRange',
        'TriggerDoubleBarrelRange',
        'TriggerShotgunRange',
        'TriggerTacticalShotgunRange',
    }

    local layoutOptionIds = {
        'MenuWidth',
        'MenuHeight',
        'RangePanelWidth',
        'RangePanelHeight',
        'MissShotsPanelWidth',
        'MissShotsPanelHeight',
        'SilentMissShotsPanelWidth',
        'SilentMissShotsPanelHeight',
        'KeybindsPanelX',
        'KeybindsPanelY',
        'SpectatorListX',
        'SpectatorListY',
    }

    saveConfig = function(name)
        local config = {
            Toggles = {},
            Options = {}
        }

        for id, toggle in pairs(Toggles) do
            config.Toggles[id] = toggle.Value
        end

        for id, opt in pairs(Options) do
            local val = opt.Value
            if KeybindOptions[opt] then
                config.Options[id] = {
                    __type = 'Keybind',
                    Key = { __type = 'EnumItem', value = tostring(opt.__key) },
                    Mode = opt.__mode
                }
            elseif typeof(val) == 'Color3' then
                config.Options[id] = { __type = 'Color3', r = val.R, g = val.G, b = val.B }
            elseif typeof(val) == 'EnumItem' then
                config.Options[id] = { __type = 'EnumItem', value = tostring(val) }
            else
                config.Options[id] = val
            end
        end

        for _, id in ipairs(weaponRangeOptionIds) do
            if Options[id] then
                config.Options[id] = tonumber(Options[id].Value) or Options[id].Value
            end
        end

        for _, id in ipairs(layoutOptionIds) do
            if Options[id] then
                config.Options[id] = tonumber(Options[id].Value) or Options[id].Value
            end
        end

        if type(saveRoles) == 'function' then
            saveRoles()
        end

        local targetFile = getConfigFilePath(name)
        pcall(function()
            if makefolder then
                if not (isfolder and isfolder(folderPath)) then
                    makefolder(folderPath)
                end
                if not (isfolder and isfolder(configDir)) then
                    makefolder(configDir)
                end
            end
            local encoded = game:GetService('HttpService'):JSONEncode(config)
            if writefile then
                writefile(targetFile, encoded)
                if targetFile ~= filePath then
                    writefile(filePath, encoded)
                end
            end
        end)
        local cleanName = type(name) == 'string' and name or (type(name) == 'table' and (name.Value or name.Name or name.Text)) or nil
        if cleanName and cleanName ~= '' and not string.find(tostring(cleanName), '^table:%s*0x') then
            local found = false
            for _, k in ipairs(knownConfigs) do
                if k == cleanName then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(knownConfigs, cleanName)
            end
        end
    end

    loadConfig = function(name)
        local targetFile = getConfigFilePath(name)
        if not (isfile and isfile(targetFile)) then
            targetFile = filePath
            if not (isfile and isfile(targetFile)) then return false, 'Config file not found' end
        end
        
        local ok, content = pcall(readfile, targetFile)
        if not (ok and content) then return false, 'Failed to read file' end

        local ok2, data = pcall(function() return game:GetService('HttpService'):JSONDecode(content) end)
        if not (ok2 and type(data) == 'table') then return false, 'Failed to decode json' end

        if type(data.Toggles) == 'table' then
            for id, val in pairs(data.Toggles) do
                if Toggles[id] and type(Toggles[id].SetValue) == 'function' then
                    pcall(function() Toggles[id]:SetValue(val) end)
                end
            end
        end

        if type(data.Options) == 'table' then
            for id, val in pairs(data.Options) do
                if Options[id] and type(Options[id].SetValue) == 'function' then
                    pcall(function()
                        if type(val) == 'table' and val.__type == 'Keybind' then
                            local restoredKey = nil
                            if type(val.Key) == 'table' and val.Key.__type == 'EnumItem' then
                                restoredKey = enumFromString(val.Key.value)
                            end
                            if restoredKey then
                                Options[id]:SetValue({
                                    Key = restoredKey,
                                    Mode = val.Mode or 'Hold'
                                })
                            end
                        elseif type(val) == 'table' and val.__type == 'Color3' then
                            Options[id]:SetValue(Color3.new(val.r, val.g, val.b))
                        elseif type(val) == 'table' and val.__type == 'EnumItem' then
                            Options[id]:SetValue(enumFromString(val.value) or val.value)
                        elseif id == 'TriggerRevolverRange'
                            or id == 'TriggerDoubleBarrelRange'
                            or id == 'TriggerShotgunRange'
                            or id == 'TriggerTacticalShotgunRange'
                            or id == 'TriggerMissRevolverShots'
                            or id == 'TriggerMissShotgunShots'
                            or id == 'MenuWidth'
                            or id == 'MenuHeight'
                            or id == 'RangePanelWidth'
                            or id == 'RangePanelHeight'
                            or id == 'MissShotsPanelWidth'
                            or id == 'MissShotsPanelHeight'
                            or id == 'SilentMissShotsPanelWidth'
                            or id == 'SilentMissShotsPanelHeight'
                            or id == 'KeybindsPanelX'
                            or id == 'KeybindsPanelY'
                            or id == 'SpectatorListX'
                            or id == 'SpectatorListY' then
                            Options[id]:SetValue(tonumber(val) or Options[id].Value)
                        else
                            Options[id]:SetValue(val)
                        end
                    end)
                end
            end
        end

        pcall(function()
            if type(applyOverlayPanelPositions) == 'function' then
                applyOverlayPanelPositions()
            end
            if type(setKeybindWindowVisible) == 'function' then
                setKeybindWindowVisible()
            end
            if type(refreshKeybindWindow) == 'function' then
                refreshKeybindWindow()
            end
            if type(syncWmVisibility) == 'function' then
                syncWmVisibility()
            end
        end)

        return true
    end

    local pendingConfigSave = false
    requestSaveConfig = function()
        if pendingConfigSave then
            return
        end
        pendingConfigSave = true
        runLater(0.4, function()
            pendingConfigSave = false
            saveConfig()
        end)
    end

    pages = {
        Combat = createPage('Combat'),
        pSilent = createPage('pSilent'),
        Backtrack = createPage('Backtrack'),
        Visuals = createPage('Visuals'),
        Roles = createPage('Roles'),
        Inventory = createPage('Inventory'),
    }
    end)()

    ;(function()
        local vestSection = createSection(pages.Combat, 'Vest Fix')
        createToggle(vestSection, 'Enable Vest Fix', State.VestFixEnable)
    end)()

    ;(function()
        local triggerSection = createSection(pages.Combat, 'Trigger Bot')
        createToggle(triggerSection, 'Enable Trigger Bot', State.TriggerEnabled)
        createToggle(triggerSection, 'Target Only', State.TriggerTargetOnly)
        createCycleOptionRow(triggerSection, 'Trigger Mode', State.TriggerMode, { 'Hitbox', 'Model' })
        createSlider(triggerSection, 'Trigger Delay (ms)', State.TriggerDelay, 0, 500, 1, ' ms')
        local missRow = createToggle(triggerSection, 'Enable Miss Chance', State.TriggerMissEnabled)
        local missSlider = createSlider(triggerSection, 'Miss Chance (%)', State.TriggerMissPercent, 0, 100, 1, '%')
        local missRadiusSlider = createSlider(triggerSection, 'Miss Radius (px)', State.TriggerMissRadius, 5, 150, 1, ' px')
        local missShotsBtn = createButton(triggerSection, 'Miss Shots Settings', function()
            if missShotsUi.setVisible then
                missShotsUi.setVisible(not missShotsUi.open)
            end
        end)
        createButton(triggerSection, 'Weapon Range Settings', function()
            setRangePanelVisible(not rangePanelOpen)
        end)
        local function updateMissVisibility()
            local isHitbox = tostring(State.TriggerMode.Value) == 'Hitbox'
            local missEnabled = State.TriggerMissEnabled.Value == true
            missRow.Visible = isHitbox
            missSlider.Visible = isHitbox and missEnabled
            missRadiusSlider.Visible = isHitbox and missEnabled
            missShotsBtn.Visible = isHitbox and missEnabled
            if not (isHitbox and missEnabled) and missShotsUi.setVisible then
                missShotsUi.setVisible(false)
            end
        end
        attachChangeListener(State.TriggerMode, updateMissVisibility)
        attachChangeListener(State.TriggerMissEnabled, updateMissVisibility)
        updateMissVisibility()
        createKeybindRow(triggerSection, 'Trigger Bot Keybind', State.TriggerKey)

        createSlider(rangePanelBody, 'Revolver Max Distance', State.TriggerRevolverRange, 0, 165, 1, ' st')
        createSlider(rangePanelBody, 'DB Max Distance', State.TriggerDoubleBarrelRange, 0, 120, 1, ' st')
        createSlider(rangePanelBody, 'Shotgun Max Distance', State.TriggerShotgunRange, 0, 95, 1, ' st')
        createSlider(rangePanelBody, 'Tactical Shotgun Max Distance', State.TriggerTacticalShotgunRange, 0, 65, 1, ' st')

        if missShotsUi.body then
            createSlider(missShotsUi.body, 'Revolver Miss Shots', State.TriggerMissRevolverShots, 1, 6, 1, '')
            createSlider(missShotsUi.body, 'Shotgun Miss Shots', State.TriggerMissShotgunShots, 1, 3, 1, '')
        end
    end)()

    ;(function()
        local autoShotSection = createSection(pages.Combat, 'Auto-Shot')
        createToggle(autoShotSection, 'Enable Auto-Shot', State.AutoShotEnabled)
        createKeybindRow(autoShotSection, 'Auto-Shot Keybind', State.AutoShotKey)
        createToggle(autoShotSection, 'Auto-Shot Quick Select (LeftAlt)', State.AutoShotQuickSelectEnabled)
        createCycleOptionRow(autoShotSection, 'Auto-Shot Mode', State.AutoShotMode, { 'SINGLE', 'BURST' })
        createSinglePlayerDropdown(autoShotSection, 'Auto-Shot Target', State.AutoShotTargetPlayer)
        createSlider(autoShotSection, 'Auto-Shot Min Delay (ms)', State.AutoShotDelayMin, 0, 500, 1, ' ms')
        createSlider(autoShotSection, 'Auto-Shot Max Delay (ms)', State.AutoShotDelayMax, 0, 500, 1, ' ms')
    end)()

    ;(function()
        local weaponSection = createSection(pages.Combat, 'Weapon Helpers')
        createToggle(weaponSection, 'Auto Fire', State.AutoRev)
        createKeybindRow(weaponSection, 'Insta Macro Keybind', State.InstaKey)
    end)()

    ;(function()
        local aimlockSection = createSection(pages.pSilent, 'pSilent')
        createToggle(aimlockSection, 'Enable pSilent', State.AimLock.Enabled)
        createToggle(aimlockSection, 'Target Only', State.AimLock.TargetOnly)
        createCycleOptionRow(aimlockSection, 'Aim Mode', State.AimLock.AimMode, { 'Body Part', 'Closest Hitbox' })
        local bodyPartRow = createCycleOptionRow(aimlockSection, 'Body Part', State.AimLock.BodyPart, {
            'Head',
            'HumanoidRootPart',
            'UpperTorso',
            'LowerTorso',
            'Left Arm',
            'Right Arm',
            'Left Leg',
            'Right Leg',
        })
        local hitboxJitterRow = createSlider(aimlockSection, 'Hitbox Jitter %', State.AimLock.HitboxJitter, 0, 100, 1, '%')
        createSlider(aimlockSection, 'FOV', State.AimLock.FOV, 5, 180, 1, '�')
        createSlider(aimlockSection, 'Target Switch Delay', State.AimLock.TargetSwitchDelay, 0.1, 2, 0.1, ' s')
        createToggle(aimlockSection, 'Show FOV Circle', State.AimLock.ShowFOV)
        createColorRow(aimlockSection, 'FOV Circle Color', State.AimLock.FOVColor)
        createToggle(aimlockSection, 'Enable Auto-Shot', State.AimLock.AutoShot, 'Automatically shoots closest target in FOV')
        createKeybindRow(aimlockSection, 'Auto-Shot Keybind', State.AimLock.AutoShotKey)
        createSlider(aimlockSection, 'Auto-Shot Delay (ms)', State.AimLock.AutoShotDelay, 0, 500, 10, ' ms')
        local missRow = createToggle(aimlockSection, 'Enable Miss Chance', State.AimLock.MissEnabled)
        local missSlider = createSlider(aimlockSection, 'Miss Chance (%)', State.AimLock.MissPercent, 0, 100, 1, '%')
        local missShotsBtn = createButton(aimlockSection, 'Miss Shots Settings', function()
            if silentMissShotsUi.setVisible then
                silentMissShotsUi.setVisible(not silentMissShotsUi.open)
            end
        end)
        createKeybindRow(aimlockSection, 'pSilent Keybind', State.AimLock.Key)

        local function syncAimModeRows()
            local mode = tostring(State.AimLock.AimMode.Value)
            local isBodyPart = mode == 'Body Part'
            local isClosest = mode == 'Closest Hitbox'
            if bodyPartRow then
                bodyPartRow.Visible = isBodyPart
            end
            if hitboxJitterRow then
                hitboxJitterRow.Visible = isClosest
            end
        end
        local function syncMissVisibility()
            local missEnabled = State.AimLock.MissEnabled.Value == true
            if missSlider then missSlider.Visible = missEnabled end
            if missShotsBtn then missShotsBtn.Visible = missEnabled end
            if not missEnabled and silentMissShotsUi.setVisible then
                silentMissShotsUi.setVisible(false)
            end
        end
        attachChangeListener(State.AimLock.AimMode, syncAimModeRows)
        attachChangeListener(State.AimLock.MissEnabled, syncMissVisibility)
        syncAimModeRows()
        syncMissVisibility()

        if silentMissShotsUi.body then
            createSlider(silentMissShotsUi.body, 'Revolver Miss Shots', State.AimLock.MissRevolverShots, 1, 6, 1, '')
            createSlider(silentMissShotsUi.body, 'Shotgun Miss Shots', State.AimLock.MissShotgunShots, 1, 3, 1, '')
        end
    end)()

    ;(function()
        local btSection = createSection(pages.Backtrack, 'Backtrack')
        createToggle(btSection, 'Enable Backtrack', State.Backtrack.Enabled, 'Records delayed hitboxes')
        createToggle(btSection, 'Target Only', State.Backtrack.TargetOnly)
        createSlider(btSection, 'Delay (ms)', State.Backtrack.Delay, 50, 400, 1, ' ms')
        createToggle(btSection, 'Show Ghosts', State.Backtrack.ShowGhosts)
        createColorRow(btSection, 'Ghost Color', State.Backtrack.Color)
        createKeybindRow(btSection, 'Backtrack Keybind', State.Backtrack.Key)

        local btSilentSection = createSection(pages.Backtrack, 'Silent / Trigger')
        createSlider(btSilentSection, 'Backtrack Chance (%)', State.Backtrack.Chance, 0, 100, 1, '%')
        do
            local hint = Instance.new('TextLabel')
            hint.BackgroundTransparency = 1
            hint.Size = UDim2.new(1, 0, 0, 32)
            hint.Font = fonts.body
            hint.TextColor3 = palette.textDim
            hint.TextSize = 10
            hint.TextXAlignment = Enum.TextXAlignment.Left
            hint.TextYAlignment = Enum.TextYAlignment.Top
            hint.TextWrapped = true
            hint.Text = 'Вероятность срабатывания выстрелов по бэктреку (работает для Silent Aim и Triggerbot).'
            hint.Parent = btSilentSection
            bindTheme(hint, 'TextColor3', 'textDim')
        end
    end)()

    ;(function()
        local espSection = createSection(pages.Visuals, 'ESP')
        createToggle(espSection, 'Enable ESP', State.ESPEnabled)
        createCycleOptionRow(espSection, 'Settings Group', State.RoleESPGroup, { 'Target', 'Friend', 'Neutral' })

        local groupRows = {}
        local groupRowSizes = {}
        local groupRowAutomaticSizes = {}
        local function rememberRoleSettingRow(row)
            if row then
                groupRowSizes[row] = row.Size
                groupRowAutomaticSizes[row] = row.AutomaticSize
            end
            return row
        end

        local function addGroupRows(role)
            local settings = State.RoleESPGroupSettings[role]
            local rows = {}
            rows[#rows + 1] = rememberRoleSettingRow(createToggle(espSection, 'Show Group', settings.Enabled))
            rows[#rows + 1] = rememberRoleSettingRow(createToggleColorRow(espSection, 'Names', settings.Names, settings.NamesColor))
            rows[#rows + 1] = rememberRoleSettingRow(createToggleColorRow(espSection, 'Box', settings.Box, settings.BoxColor))
            rows[#rows + 1] = rememberRoleSettingRow(createToggleColorRow(espSection, 'Tracers', settings.Tracers, settings.TracersColor))
            rows[#rows + 1] = rememberRoleSettingRow(createToggleColorRow(espSection, 'Health Bar', settings.HealthBar, settings.HealthBarColor))
            rows[#rows + 1] = rememberRoleSettingRow(createToggleColorRow(espSection, 'Armor', settings.Armor, settings.ArmorColor, settings.ArmorMode, { 'Text', 'Bar' }))
            groupRows[role] = rows
        end

        addGroupRows('Target')
        addGroupRows('Friend')
        addGroupRows('Neutral')

        local function syncVisibleRoleSettings()
            local selectedRole = normalizeRoleText(State.RoleESPGroup.Value)
            for role, rows in pairs(groupRows) do
                local visible = role == selectedRole
                for _, row in ipairs(rows) do
                    if row then
                        row.Visible = visible
                        row.AutomaticSize = visible and (groupRowAutomaticSizes[row] or Enum.AutomaticSize.None) or Enum.AutomaticSize.None
                        row.Size = visible and (groupRowSizes[row] or row.Size) or UDim2.new(1, 0, 0, 0)
                    end
                end
            end
        end

        attachChangeListener(State.RoleESPGroup, syncVisibleRoleSettings)
        syncVisibleRoleSettings()
    end)()

    ;(function()
        pages.Roles.left.Visible = false
        pages.Roles.right.Visible = false

        -- Initialize global role tables for Coincide & Dahood compat
        if not getgenv().friendlys or type(getgenv().friendlys) ~= 'table' then
            getgenv().friendlys = {}
        end
        if not getgenv().prioritys or type(getgenv().prioritys) ~= 'table' then
            getgenv().prioritys = {}
        end

        local function IsInTable(tbl, playerName)
            if not tbl or type(tbl) ~= 'table' then return false end
            for _, name in pairs(tbl) do
                if type(name) == 'string' and string.lower(name) == string.lower(playerName) then
                    return true
                end
            end
            return false
        end

        local function RemoveFromTable(tbl, playerName)
            if not tbl or type(tbl) ~= 'table' then return end
            for i = #tbl, 1, -1 do
                if type(tbl[i]) == 'string' and string.lower(tbl[i]) == string.lower(playerName) then
                    table.remove(tbl, i)
                end
            end
        end

        local function AddToTable(tbl, playerName)
            if not tbl or type(tbl) ~= 'table' then return end
            if not IsInTable(tbl, playerName) then
                table.insert(tbl, playerName)
            end
        end

        local function GetPlayerState(player)
            local shared = normalizeRoleText(getSharedPlayerRole(player) or 'Neutral')
            if shared == 'Friend' or IsInTable(getgenv().friendlys, player.Name) then
                return 'Friendly'
            elseif shared == 'Target' or IsInTable(getgenv().prioritys, player.Name) then
                return 'Priority'
            end
            return 'Neutral'
        end

        local function GetStateColor(player, stateName)
            local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
            if player == LocalPlayer then return curAccent end
            if stateName == 'Friendly' then return Color3.fromRGB(0, 200, 0) end
            if stateName == 'Priority' then return Color3.fromRGB(210, 0, 0) end
            return Color3.fromHex('A0A0A0')
        end

        local function GetStateText(player, stateName)
            if player == LocalPlayer then return 'LocalPlayer' end
            return stateName or 'Neutral'
        end

        local function IsModerator(player)
            local moderators = getgenv().moderators
            if not moderators or type(moderators) ~= 'table' then return false end
            for _, modName in pairs(moderators) do
                if type(modName) == 'string' and string.lower(modName) == string.lower(player.Name) then
                    return true
                end
            end
            return false
        end

        -- Left Side: Coincide Players Window matching screenshot 1:1
        local playersWin = createCoincideWindow({
            Name = 'PlayersWindow',
            Title = 'Players',
            Width = 265,
            Height = 330,
            HasClose = false,
            Parent = pages.Roles.root,
        })
        playersWin.Outer.Position = UDim2.new(0, 0, 0, 0)
        playersWin.Outer.Size = UDim2.new(0.53, -4, 1, 0)
        playersWin.Content.Size = UDim2.new(1, -10, 1, -56)

        -- Bottom search box (matching screenshot: "Type here..")
        local searchOuter = Instance.new('Frame')
        searchOuter.Name = 'SearchBox'
        searchOuter.AnchorPoint = Vector2.new(0, 1)
        searchOuter.Position = UDim2.new(0, 5, 1, -5)
        searchOuter.Size = UDim2.new(1, -10, 0, 21)
        searchOuter.BackgroundColor3 = Color3.fromHex('000000')
        searchOuter.BorderSizePixel = 0
        searchOuter.Parent = playersWin.Outer

        local searchInline = Instance.new('Frame')
        searchInline.Position = UDim2.new(0, 1, 0, 1)
        searchInline.Size = UDim2.new(1, -2, 1, -2)
        searchInline.BackgroundColor3 = Color3.fromHex('393939')
        searchInline.BorderSizePixel = 0
        searchInline.Parent = searchOuter

        local searchInside = Instance.new('Frame')
        searchInside.Position = UDim2.new(0, 1, 0, 1)
        searchInside.Size = UDim2.new(1, -2, 1, -2)
        searchInside.BackgroundColor3 = Color3.fromHex('FFFFFF')
        searchInside.BorderSizePixel = 0
        searchInside.Parent = searchInline

        local searchGrad = Instance.new('UIGradient')
        searchGrad.Rotation = 90
        searchGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
        })
        searchGrad.Parent = searchInside

        local searchBox = Instance.new('TextBox')
        searchBox.Name = 'SearchInput'
        searchBox.Position = UDim2.new(0, 4, 0, 0)
        searchBox.Size = UDim2.new(1, -8, 1, 0)
        searchBox.BackgroundTransparency = 1
        searchBox.BorderSizePixel = 0
        searchBox.ClearTextOnFocus = false
        searchBox.Text = ''
        searchBox.PlaceholderText = 'Type here..'
        searchBox.PlaceholderColor3 = Color3.fromHex('5E626B')
        searchBox.TextColor3 = Color3.fromHex('FFFFFF')
        searchBox.TextSize = 12
        searchBox.Font = Enum.Font.Gotham
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.TextYAlignment = Enum.TextYAlignment.Center
        searchBox.ClipsDescendants = true
        searchBox.Parent = searchInside

        -- Scrolling player list inside Content
        local playerListScroll = Instance.new('ScrollingFrame')
        playerListScroll.Name = 'PlayerListScroll'
        playerListScroll.Position = UDim2.new(0, 2, 0, 2)
        playerListScroll.Size = UDim2.new(1, -4, 1, -4)
        playerListScroll.BackgroundTransparency = 1
        playerListScroll.BorderSizePixel = 0
        playerListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        playerListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        playerListScroll.ScrollBarThickness = 2
        local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
        playerListScroll.ScrollBarImageColor3 = curAccent
        playerListScroll.ScrollingDirection = Enum.ScrollingDirection.Y
        playerListScroll.ClipsDescendants = true
        playerListScroll.Parent = playersWin.Content
        registerThemeRefresher(function()
            if playerListScroll and playerListScroll.Parent then
                playerListScroll.ScrollBarImageColor3 = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
            end
        end)

        local plLayout = Instance.new('UIListLayout')
        plLayout.FillDirection = Enum.FillDirection.Vertical
        plLayout.SortOrder = Enum.SortOrder.LayoutOrder
        plLayout.Padding = UDim.new(0, 1)
        plLayout.Parent = playerListScroll

        local plPad = Instance.new('UIPadding')
        plPad.PaddingTop = UDim.new(0, 2)
        plPad.PaddingBottom = UDim.new(0, 6)
        plPad.Parent = playerListScroll

        -- Right Side: Crew Roles & Settings Panel
        local crewWin = createCoincideWindow({
            Name = 'CrewRolesWindow',
            Title = 'Crew Roles',
            Width = 240,
            Height = 330,
            HasClose = false,
            Parent = pages.Roles.root,
        })
        crewWin.Outer.AnchorPoint = Vector2.new(1, 0)
        crewWin.Outer.Position = UDim2.new(1, 0, 0, 0)
        crewWin.Outer.Size = UDim2.new(0.47, -4, 1, 0)

        local crewContentPad = Instance.new('UIPadding')
        crewContentPad.PaddingTop = UDim.new(0, 8)
        crewContentPad.PaddingBottom = UDim.new(0, 8)
        crewContentPad.PaddingLeft = UDim.new(0, 8)
        crewContentPad.PaddingRight = UDim.new(0, 8)
        crewContentPad.Parent = crewWin.Content

        local crewContentLayout = Instance.new('UIListLayout')
        crewContentLayout.Padding = UDim.new(0, 6)
        crewContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
        crewContentLayout.Parent = crewWin.Content

        local crewDescLbl = Instance.new('TextLabel')
        crewDescLbl.BackgroundTransparency = 1
        crewDescLbl.Size = UDim2.new(1, 0, 0, 16)
        crewDescLbl.Font = Enum.Font.Gotham
        crewDescLbl.TextSize = 11
        crewDescLbl.TextColor3 = Color3.fromHex('8C8F99')
        crewDescLbl.TextXAlignment = Enum.TextXAlignment.Left
        crewDescLbl.Text = 'Quick crew relation panels:'
        crewDescLbl.Parent = crewWin.Content

        local function makeCoincideButton(parent, text)
            local btn = Instance.new('TextButton')
            btn.Size = UDim2.new(1, 0, 0, 28)
            btn.BackgroundColor3 = Color3.fromHex('1A1A1A')
            btn.AutoButtonColor = false
            btn.Font = Enum.Font.GothamSemibold
            btn.TextSize = 12
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Text = text
            btn.BorderSizePixel = 0
            btn.Parent = parent

            local stroke1 = Instance.new('UIStroke')
            stroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke1.Color = Color3.fromHex('000000')
            stroke1.Thickness = 1
            stroke1.Parent = btn

            local innerStrokeF = Instance.new('Frame')
            innerStrokeF.Position = UDim2.new(0, 1, 0, 1)
            innerStrokeF.Size = UDim2.new(1, -2, 1, -2)
            innerStrokeF.BackgroundTransparency = 1
            innerStrokeF.BorderSizePixel = 0
            innerStrokeF.Parent = btn

            local stroke2 = Instance.new('UIStroke')
            stroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke2.Color = Color3.fromHex('393939')
            stroke2.Thickness = 1
            stroke2.Parent = innerStrokeF

            safeConnect(btn.MouseEnter, function()
                tween(btn, 0.12, { BackgroundColor3 = Color3.fromHex('262626') })
            end)
            safeConnect(btn.MouseLeave, function()
                tween(btn, 0.18, { BackgroundColor3 = Color3.fromHex('1A1A1A') })
            end)

            return btn
        end

        local crewsTargetsBtn = makeCoincideButton(crewWin.Content, 'Crew Targets')
        local crewsFriendsBtn = makeCoincideButton(crewWin.Content, 'Crew Friends')

        local crewSep = Instance.new('Frame')
        crewSep.Size = UDim2.new(1, 0, 0, 1)
        crewSep.BackgroundColor3 = Color3.fromHex('252525')
        crewSep.BorderSizePixel = 0
        crewSep.Parent = crewWin.Content

        local infoLegend = Instance.new('TextLabel')
        infoLegend.BackgroundTransparency = 1
        infoLegend.Size = UDim2.new(1, 0, 0, 72)
        infoLegend.Font = Enum.Font.Gotham
        infoLegend.TextSize = 11
        infoLegend.TextColor3 = Color3.fromHex('8C8F99')
        infoLegend.TextXAlignment = Enum.TextXAlignment.Left
        infoLegend.TextYAlignment = Enum.TextYAlignment.Top
        infoLegend.RichText = true
        infoLegend.Text = 'Click any player row to cycle:<br/>' ..
            '• <font color="#A0A0A0">Neutral</font> (default)<br/>' ..
            '• <font color="#00C800">Friendly</font> (whitelisted)<br/>' ..
            '• <font color="#D20000">Priority</font> (targeted)'
        infoLegend.Parent = crewWin.Content

        -- Popout floating playerlist window support
        local floatingPlayerWin = nil
        local floatingVisible = false

        local function ensureFloatingPlayerlist()
            if floatingPlayerWin then return floatingPlayerWin end
            floatingPlayerWin = createCoincideWindow({
                Name = 'FloatingPlayerlist',
                Title = 'Players',
                Width = 240,
                Height = 380,
                HasClose = true,
                Parent = menuGroup,
            })
            floatingPlayerWin.Outer.Visible = false
            floatingPlayerWin.Outer.Active = true
            floatingPlayerWin.Content.Size = UDim2.new(1, -10, 1, -56)

            -- Search Box at bottom of floating window
            local fSearchOuter = Instance.new('Frame')
            fSearchOuter.Name = 'SearchBox'
            fSearchOuter.AnchorPoint = Vector2.new(0, 1)
            fSearchOuter.Position = UDim2.new(0, 5, 1, -5)
            fSearchOuter.Size = UDim2.new(1, -10, 0, 21)
            fSearchOuter.BackgroundColor3 = Color3.fromHex('000000')
            fSearchOuter.BorderSizePixel = 0
            fSearchOuter.Parent = floatingPlayerWin.Outer

            local fSearchInline = Instance.new('Frame')
            fSearchInline.Position = UDim2.new(0, 1, 0, 1)
            fSearchInline.Size = UDim2.new(1, -2, 1, -2)
            fSearchInline.BackgroundColor3 = Color3.fromHex('393939')
            fSearchInline.BorderSizePixel = 0
            fSearchInline.Parent = fSearchOuter

            local fSearchInside = Instance.new('Frame')
            fSearchInside.Position = UDim2.new(0, 1, 0, 1)
            fSearchInside.Size = UDim2.new(1, -2, 1, -2)
            fSearchInside.BackgroundColor3 = Color3.fromHex('FFFFFF')
            fSearchInside.BorderSizePixel = 0
            fSearchInside.Parent = fSearchInline

            local fSearchGrad = Instance.new('UIGradient')
            fSearchGrad.Rotation = 90
            fSearchGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
            fSearchGrad.Parent = fSearchInside

            local fSearchBox = Instance.new('TextBox')
            fSearchBox.Name = 'SearchInput'
            fSearchBox.Position = UDim2.new(0, 4, 0, 0)
            fSearchBox.Size = UDim2.new(1, -8, 1, 0)
            fSearchBox.BackgroundTransparency = 1
            fSearchBox.BorderSizePixel = 0
            fSearchBox.ClearTextOnFocus = false
            fSearchBox.Text = ''
            fSearchBox.PlaceholderText = 'Type here..'
            fSearchBox.PlaceholderColor3 = Color3.fromHex('5E626B')
            fSearchBox.TextColor3 = Color3.fromHex('FFFFFF')
            fSearchBox.TextSize = 12
            fSearchBox.Font = Enum.Font.Gotham
            fSearchBox.TextXAlignment = Enum.TextXAlignment.Left
            fSearchBox.TextYAlignment = Enum.TextYAlignment.Center
            fSearchBox.ClipsDescendants = true
            fSearchBox.Parent = fSearchInside

            local fScroll = Instance.new('ScrollingFrame')
            fScroll.Name = 'FloatingPlayerScroll'
            fScroll.Position = UDim2.new(0, 2, 0, 2)
            fScroll.Size = UDim2.new(1, -4, 1, -4)
            fScroll.BackgroundTransparency = 1
            fScroll.BorderSizePixel = 0
            fScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            fScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            fScroll.ScrollBarThickness = 2
            fScroll.ScrollBarImageColor3 = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent
            fScroll.ScrollingDirection = Enum.ScrollingDirection.Y
            fScroll.ClipsDescendants = true
            fScroll.Parent = floatingPlayerWin.Content

            local fLayout = Instance.new('UIListLayout')
            fLayout.FillDirection = Enum.FillDirection.Vertical
            fLayout.SortOrder = Enum.SortOrder.LayoutOrder
            fLayout.Padding = UDim.new(0, 1)
            fLayout.Parent = fScroll

            local fPad = Instance.new('UIPadding')
            fPad.PaddingTop = UDim.new(0, 2)
            fPad.PaddingBottom = UDim.new(0, 6)
            fPad.Parent = fScroll

            local function syncFloatPos()
                if main then
                    floatingPlayerWin.Outer.Position = UDim2.new(
                        main.Position.X.Scale,
                        main.Position.X.Offset - floatingPlayerWin.Outer.Size.X.Offset - 6,
                        main.Position.Y.Scale,
                        main.Position.Y.Offset
                    )
                end
            end
            syncFloatPos()
            safeConnect(main:GetPropertyChangedSignal('Position'), function()
                if floatingVisible then syncFloatPos() end
            end)

            safeConnect(floatingPlayerWin.CloseButton.MouseButton1Click, function()
                floatingVisible = false
                floatingPlayerWin.Outer.Visible = false
            end)

            safeConnect(fSearchBox:GetPropertyChangedSignal('Text'), function()
                searchBox.Text = fSearchBox.Text
            end)

            floatingPlayerWin.Scroll = fScroll
            return floatingPlayerWin
        end

        -- Row builder & manager
        local rowRefs = {}
        local fRowRefs = {}

        local function clearRows()
            for _, r in ipairs(rowRefs) do
                pcall(function() r:Destroy() end)
            end
            rowRefs = {}
            for _, r in ipairs(fRowRefs) do
                pcall(function() r:Destroy() end)
            end
            fRowRefs = {}
        end

        local function setRoleForPlayer(player, role)
            if not player then
                return
            end
            role = normalizeRoleText(role)
            setSharedPlayerRole(player, role)
            if role == 'Target' and player ~= LocalPlayer then
                pcall(function()
                    if State.AutoShotTargetPlayer and type(State.AutoShotTargetPlayer.SetValue) == 'function' then
                        State.AutoShotTargetPlayer:SetValue(player.Name)
                    end
                end)
            end

            -- Automatically synchronize whitelists when a role is changed in the UI list
            if Options then
                if Options.TriggerWhitelist and type(Options.TriggerWhitelist.SetValue) == 'function' then
                    pcall(function()
                        local current = Options.TriggerWhitelist.Value or {}
                        local newTable = {}
                        local changed = false
                        for k, v in pairs(current) do
                            if k ~= player.Name then
                                newTable[k] = v
                            end
                        end
                        if role == 'Friend' then
                            newTable[player.Name] = true
                            changed = true
                        elseif current[player.Name] ~= nil then
                            changed = true
                        end
                        if changed then
                            Options.TriggerWhitelist:SetValue(newTable)
                        end
                    end)
                end
            end

            -- Synchronize Dahood / Coincide global tables
            RemoveFromTable(getgenv().friendlys, player.Name)
            RemoveFromTable(getgenv().prioritys, player.Name)
            if role == 'Friend' then
                AddToTable(getgenv().friendlys, player.Name)
            elseif role == 'Target' then
                AddToTable(getgenv().prioritys, player.Name)
            end

            saveRoles()
            refreshRows()
        end

        local function buildPlayerRow(parentList, player, idx)
            local stateName = GetPlayerState(player)
            local isMod = IsModerator(player)
            local curAccent = (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value) or palette.accent

            local row = Instance.new('Frame')
            row.Name = 'Row_' .. player.Name
            row.Size = UDim2.new(1, 0, 0, 20)
            row.BackgroundColor3 = Color3.fromHex('1E1E1E')
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.LayoutOrder = idx
            row.Parent = parentList

            local sep = Instance.new('Frame')
            sep.AnchorPoint = Vector2.new(0, 1)
            sep.Position = UDim2.new(0, 0, 1, 0)
            sep.Size = UDim2.new(1, 0, 0, 1)
            sep.BackgroundColor3 = Color3.fromHex('222222')
            sep.BorderSizePixel = 0
            sep.ZIndex = 2
            sep.Parent = row

            local btn = Instance.new('TextButton')
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.BorderSizePixel = 0
            btn.AutoButtonColor = false
            btn.Text = ''
            btn.ZIndex = 4
            btn.Parent = row

            local nameLbl = Instance.new('TextLabel')
            nameLbl.AnchorPoint = Vector2.new(0, 0.5)
            nameLbl.Position = UDim2.new(0, 4, 0.5, 0)
            nameLbl.Size = UDim2.new(0.48, 0, 1, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = player.Name
            nameLbl.TextColor3 = Color3.fromHex('FFFFFF')
            nameLbl.TextSize = 12
            nameLbl.Font = Enum.Font.Gotham
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextYAlignment = Enum.TextYAlignment.Center
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.ZIndex = 5
            nameLbl.Parent = row

            local modLbl = Instance.new('TextLabel')
            modLbl.Name = 'ModLbl'
            modLbl.AnchorPoint = Vector2.new(0, 0.5)
            modLbl.Position = UDim2.new(0.48, 2, 0.5, 0)
            modLbl.Size = UDim2.new(0.10, 0, 1, 0)
            modLbl.BackgroundTransparency = 1
            modLbl.Text = ''
            modLbl.TextColor3 = Color3.fromHex('FFFFFF')
            modLbl.TextSize = 12
            modLbl.Font = Enum.Font.Gotham
            modLbl.TextXAlignment = Enum.TextXAlignment.Left
            modLbl.TextYAlignment = Enum.TextYAlignment.Center
            modLbl.ZIndex = 5
            modLbl.Parent = row

            if isMod then
                modLbl.RichText = true
                modLbl.Text = '[<font color="#' .. curAccent:ToHex() .. '">M</font>]'
            end

            local stateLbl = Instance.new('TextLabel')
            stateLbl.Name = 'StateLbl'
            stateLbl.AnchorPoint = Vector2.new(1, 0.5)
            stateLbl.Position = UDim2.new(1, -4, 0.5, 0)
            stateLbl.Size = UDim2.new(0.42, 0, 1, 0)
            stateLbl.BackgroundTransparency = 1
            stateLbl.Text = GetStateText(player, stateName)
            stateLbl.TextColor3 = GetStateColor(player, stateName)
            stateLbl.TextSize = 12
            stateLbl.Font = Enum.Font.Gotham
            stateLbl.TextXAlignment = Enum.TextXAlignment.Right
            stateLbl.TextYAlignment = Enum.TextYAlignment.Center
            stateLbl.ZIndex = 5
            stateLbl.Parent = row

            safeConnect(btn.MouseEnter, function()
                tween(row, 0.1, { BackgroundTransparency = 0.7 })
            end)
            safeConnect(btn.MouseLeave, function()
                tween(row, 0.1, { BackgroundTransparency = 1 })
            end)

            if player ~= LocalPlayer then
                safeConnect(btn.MouseButton1Click, function()
                    local cur = GetPlayerState(player)
                    local nxt = (cur == 'Neutral' and 'Friendly') or (cur == 'Friendly' and 'Priority') or 'Neutral'
                    local roleCode = (nxt == 'Friendly' and 'Friend') or (nxt == 'Priority' and 'Target') or 'Neutral'

                    setRoleForPlayer(player, roleCode)

                    tween(row, 0.08, { BackgroundTransparency = 0.25 })
                    task.delay(0.1, function()
                        if row and row.Parent then
                            tween(row, 0.14, { BackgroundTransparency = 1 })
                        end
                    end)

                    stateLbl.Text = GetStateText(player, nxt)
                    stateLbl.TextColor3 = GetStateColor(player, nxt)
                end)
            end

            return row
        end

        refreshRows = function()
            clearRows()
            local searchText = string.lower(searchBox.Text:gsub('^%s+', ''):gsub('%s+$', ''))
            local idx = 0

            if LocalPlayer and (searchText == '' or string.find(string.lower(LocalPlayer.Name), searchText, 1, true)) then
                table.insert(rowRefs, buildPlayerRow(playerListScroll, LocalPlayer, idx))
                if floatingPlayerWin and floatingPlayerWin.Scroll then
                    table.insert(fRowRefs, buildPlayerRow(floatingPlayerWin.Scroll, LocalPlayer, idx))
                end
                idx = idx + 1
            end

            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer then
                    if searchText == '' or string.find(string.lower(pl.Name), searchText, 1, true) or string.find(string.lower(pl.DisplayName or ''), searchText, 1, true) then
                        table.insert(rowRefs, buildPlayerRow(playerListScroll, pl, idx))
                        if floatingPlayerWin and floatingPlayerWin.Scroll then
                            table.insert(fRowRefs, buildPlayerRow(floatingPlayerWin.Scroll, pl, idx))
                        end
                        idx = idx + 1
                    end
                end
            end
        end

        local function renderAllRows()
            refreshRows()
        end

        refreshRows()
        safeConnect(Players.PlayerAdded, function() refreshRows() end)
        safeConnect(Players.PlayerRemoving, function(pl)
            RemoveFromTable(getgenv().friendlys, pl.Name)
            RemoveFromTable(getgenv().prioritys, pl.Name)
            refreshRows()
        end)
        safeConnect(searchBox:GetPropertyChangedSignal('Text'), function()
            refreshRows()
        end)
        attachChangeListener(State.RoleESPGroupSettings.Neutral.NamesColor, renderAllRows)
        attachChangeListener(State.RoleESPGroupSettings.Target.NamesColor, renderAllRows)
        attachChangeListener(State.RoleESPGroupSettings.Friend.NamesColor, renderAllRows)

        ----------------------------------------------------------------
        -- Crew Targets / Friends panels (DataFolder.Information.Crew)
        ----------------------------------------------------------------
        local GroupService = game:GetService('GroupService')
        local crewNameCache = {} -- [id] = name string
        local crewWatchConnections = {}
        local crewSyncedByUserId = {} -- [userId] = 'Target'|'Friend' when role was applied by crew sync
        local syncCrewRoles
        local applyCrewRoleForPlayer
        local watchPlayerCrew
        local targetsPanelApi
        local friendsPanelApi

        local function getCrewOptionMap(opt)
            local v = opt and opt.Value
            if type(v) ~= 'table' then
                return {}
            end
            return v
        end

        local function mapHasCrew(map, crewId)
            if not crewId or type(map) ~= 'table' then
                return false
            end
            return map[tostring(crewId)] == true or map[crewId] == true
        end

        local function isCrewTargetSelected(crewId)
            return mapHasCrew(getCrewOptionMap(State.SelectedCrewTargets), crewId)
        end

        local function isCrewFriendSelected(crewId)
            return mapHasCrew(getCrewOptionMap(State.SelectedCrewFriends), crewId)
        end

        local function cloneEnabledMap(map)
            local nextMap = {}
            for k, v in pairs(map or {}) do
                if v == true then
                    nextMap[tostring(k)] = true
                end
            end
            return nextMap
        end

        local function setCrewInOption(opt, crewId, enabled)
            if not opt or not crewId or type(opt.SetValue) ~= 'function' then
                return
            end
            local currentMap = getCrewOptionMap(opt)
            local key = tostring(crewId)
            local currentlyOn = mapHasCrew(currentMap, crewId)
            local wantOn = enabled == true
            if currentlyOn == wantOn then
                return
            end
            local nextMap = cloneEnabledMap(currentMap)
            if wantOn then
                nextMap[key] = true
            else
                nextMap[key] = nil
                nextMap[tonumber(crewId) or -1] = nil
            end
            opt:SetValue(nextMap)
        end

        local function readPlayerCrewId(player)
            if not player then
                return nil
            end
            local ok, crewId = pcall(function()
                local df = player:FindFirstChild('DataFolder')
                local info = df and df:FindFirstChild('Information')
                local crew = info and info:FindFirstChild('Crew')
                if not crew then
                    return nil
                end
                local raw = nil
                if crew:IsA('ValueBase') then
                    raw = crew.Value
                end
                if typeof(raw) == 'number' then
                    return raw > 0 and math.floor(raw) or nil
                end
                if typeof(raw) == 'string' then
                    local n = tonumber(raw)
                    if n and n > 0 then
                        return math.floor(n)
                    end
                end
                return nil
            end)
            if ok then
                return crewId
            end
            return nil
        end

        local function demoteCrewMembers(crewId, expectedRole)
            if not crewId then
                return
            end
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer and readPlayerCrewId(pl) == crewId then
                    local role = normalizeRoleText(getSharedPlayerRole(pl) or 'Neutral')
                    if role == expectedRole then
                        setRoleForPlayer(pl, 'Neutral')
                    end
                    if pl.UserId then
                        crewSyncedByUserId[pl.UserId] = nil
                    end
                end
            end
            renderAllRows()
        end

        local function setCrewTargetSelected(crewId, enabled)
            if enabled then
                setCrewInOption(State.SelectedCrewFriends, crewId, false)
                setCrewInOption(State.SelectedCrewTargets, crewId, true)
            else
                setCrewInOption(State.SelectedCrewTargets, crewId, false)
                demoteCrewMembers(crewId, 'Target')
            end
        end

        local function setCrewFriendSelected(crewId, enabled)
            if enabled then
                setCrewInOption(State.SelectedCrewTargets, crewId, false)
                setCrewInOption(State.SelectedCrewFriends, crewId, true)
            else
                setCrewInOption(State.SelectedCrewFriends, crewId, false)
                demoteCrewMembers(crewId, 'Friend')
            end
        end

        local function getCrewDisplayName(crewId)
            if not crewId then
                return 'Unknown'
            end
            local cached = crewNameCache[crewId]
            if cached then
                return cached
            end
            local ok, info = pcall(function()
                return GroupService:GetGroupInfoAsync(crewId)
            end)
            local name = (ok and type(info) == 'table' and type(info.Name) == 'string' and info.Name ~= '')
                and info.Name
                or ('Crew ' .. tostring(crewId))
            crewNameCache[crewId] = name
            return name
        end

        local function collectServerCrews()
            local byId = {}
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer then
                    local id = readPlayerCrewId(pl)
                    if id then
                        local entry = byId[id]
                        if not entry then
                            entry = { id = id, count = 0 }
                            byId[id] = entry
                        end
                        entry.count = entry.count + 1
                    end
                end
            end
            local list = {}
            for _, entry in pairs(byId) do
                table.insert(list, entry)
            end
            table.sort(list, function(a, b)
                return a.id < b.id
            end)
            return list
        end

        -- Promote selected crews only. Never mass-Neutralize (that wiped manual roles on join).
        applyCrewRoleForPlayer = function(player)
            if not player or player == LocalPlayer then
                return
            end
            local userId = player.UserId
            local crewId = readPlayerCrewId(player)
            if isCrewFriendSelected(crewId) then
                setRoleForPlayer(player, 'Friend')
                if userId then
                    crewSyncedByUserId[userId] = 'Friend'
                end
            elseif isCrewTargetSelected(crewId) then
                setSharedPlayerRole(player, 'Target')
                if userId then
                    crewSyncedByUserId[userId] = 'Target'
                end
            elseif userId and crewSyncedByUserId[userId] then
                -- Left a crew-synced crew: clear only roles we applied via crew sync
                setRoleForPlayer(player, 'Neutral')
                crewSyncedByUserId[userId] = nil
            end
        end

        syncCrewRoles = function()
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer then
                    local crewId = readPlayerCrewId(pl)
                    if isCrewFriendSelected(crewId) then
                        setRoleForPlayer(pl, 'Friend')
                        if pl.UserId then
                            crewSyncedByUserId[pl.UserId] = 'Friend'
                        end
                    elseif isCrewTargetSelected(crewId) then
                        setSharedPlayerRole(pl, 'Target')
                        if pl.UserId then
                            crewSyncedByUserId[pl.UserId] = 'Target'
                        end
                    end
                end
            end
            renderAllRows()
        end

        local function refreshOpenCrewPanels()
            if targetsPanelApi and targetsPanelApi.isOpen() then
                targetsPanelApi.refresh()
            end
            if friendsPanelApi and friendsPanelApi.isOpen() then
                friendsPanelApi.refresh()
            end
        end

        local function makeCrewRolePanel(cfg)
            local panelOpen = false
            local rowByCrewId = {}
            local emptyLabel = nil
            local wasDragged = false

            local cWin = createCoincideWindow({
                Name = cfg.panelName,
                Title = cfg.title,
                Width = 260,
                Height = 320,
                HasClose = true,
                Parent = menuGroup,
            })
            local panel = cWin.Outer
            panel.Visible = false
            local closeBtn = cWin.CloseButton

            local cpDragging = false
            local cpDragStart = nil
            local cpStartPos = nil
            local cpDragInput = nil

            safeConnect(cWin.Header.InputBegan, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    cpDragging = true
                    wasDragged = true
                    cpDragStart = input.Position
                    cpStartPos = panel.Position
                    safeConnect(input.Changed, function()
                        if input.UserInputState == Enum.UserInputState.End then
                            cpDragging = false
                        end
                    end)
                end
            end)

            safeConnect(cWin.Header.InputChanged, function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    cpDragInput = input
                end
            end)

            safeConnect(UIS.InputChanged, function(input)
                if cpDragging and input == cpDragInput then
                    local delta = input.Position - cpDragStart
                    panel.Position = UDim2.new(
                        cpStartPos.X.Scale,
                        cpStartPos.X.Offset + delta.X,
                        cpStartPos.Y.Scale,
                        cpStartPos.Y.Offset + delta.Y
                    )
                end
            end)

            local body = Instance.new('ScrollingFrame')
            body.Name = 'Body'
            body.BackgroundTransparency = 1
            body.BorderSizePixel = 0
            body.Position = UDim2.new(0, 3, 0, 3)
            body.Size = UDim2.new(1, -6, 1, -6)
            body.ScrollBarThickness = 2
            body.ScrollBarImageColor3 = getActiveAccent()
            body.CanvasSize = UDim2.fromOffset(0, 0)
            body.AutomaticCanvasSize = Enum.AutomaticSize.Y
            body.Parent = cWin.Content

            local bodyPad = Instance.new('UIPadding')
            bodyPad.PaddingTop = UDim.new(0, 3)
            bodyPad.PaddingBottom = UDim.new(0, 6)
            bodyPad.PaddingLeft = UDim.new(0, 3)
            bodyPad.PaddingRight = UDim.new(0, 3)
            bodyPad.Parent = body

            local bodyList = Instance.new('UIListLayout')
            bodyList.Padding = UDim.new(0, 2)
            bodyList.Parent = body

            local function syncPosition()
                if not main or wasDragged then
                    return
                end
                panel.Position = UDim2.new(
                    main.Position.X.Scale,
                    main.Position.X.Offset + main.Size.X.Offset + 6,
                    main.Position.Y.Scale,
                    main.Position.Y.Offset
                )
            end

            local function showEmpty(text)
                if not emptyLabel then
                    emptyLabel = Instance.new('TextLabel')
                    emptyLabel.Name = 'EmptyNotice'
                    emptyLabel.BackgroundTransparency = 1
                    emptyLabel.Size = UDim2.new(1, 0, 0, 24)
                    emptyLabel.Font = Enum.Font.Gotham
                    emptyLabel.TextColor3 = Color3.fromHex('8C8F99')
                    emptyLabel.TextSize = 11
                    emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
                    emptyLabel.TextYAlignment = Enum.TextYAlignment.Center
                    emptyLabel.Parent = body
                end
                emptyLabel.Text = text or 'No crews found on server'
                emptyLabel.Visible = true
            end

            local function hideEmpty()
                if emptyLabel then
                    emptyLabel.Visible = false
                end
            end

            local function destroyRow(r)
                if not r then
                    return
                end
                if r.Frame then
                    r.Frame.Visible = false
                    r.Frame.Parent = nil
                    pcall(function()
                        r.Frame:Destroy()
                    end)
                end
            end

            local function createRow(entry)
                local strId = tostring(entry.id)
                local row = Instance.new('Frame')
                row.Name = 'CrewRow_' .. strId
                row.BackgroundColor3 = Color3.fromHex('1E1E1E')
                row.BackgroundTransparency = 1
                row.Size = UDim2.new(1, 0, 0, 24)
                row.BorderSizePixel = 0
                row.Parent = body

                local rowBottom = Instance.new('Frame')
                rowBottom.AnchorPoint = Vector2.new(0, 1)
                rowBottom.Position = UDim2.new(0, 0, 1, 0)
                rowBottom.Size = UDim2.new(1, 0, 0, 1)
                rowBottom.BackgroundColor3 = Color3.fromHex('202020')
                rowBottom.BorderSizePixel = 0
                rowBottom.Parent = row

                local cbOuter = Instance.new('Frame')
                cbOuter.Name = 'CbOuter'
                cbOuter.AnchorPoint = Vector2.new(0, 0.5)
                cbOuter.Position = UDim2.new(0, 5, 0.5, 0)
                cbOuter.Size = UDim2.fromOffset(13, 13)
                cbOuter.BackgroundColor3 = Color3.fromHex('000000')
                cbOuter.BorderSizePixel = 0
                cbOuter.Parent = row

                local cbInner = Instance.new('Frame')
                cbInner.Position = UDim2.new(0, 1, 0, 1)
                cbInner.Size = UDim2.new(1, -2, 1, -2)
                cbInner.BackgroundColor3 = Color3.fromHex('393939')
                cbInner.BorderSizePixel = 0
                cbInner.Parent = cbOuter

                local cbInside = Instance.new('Frame')
                cbInside.Position = UDim2.new(0, 1, 0, 1)
                cbInside.Size = UDim2.new(1, -2, 1, -2)
                cbInside.BackgroundColor3 = Color3.fromHex('131313')
                cbInside.BorderSizePixel = 0
                cbInside.Parent = cbInner

                local cbFill = Instance.new('Frame')
                cbFill.Name = 'Fill'
                cbFill.Position = UDim2.new(0, 1, 0, 1)
                cbFill.Size = UDim2.new(1, -2, 1, -2)
                cbFill.BackgroundColor3 = getActiveAccent()
                cbFill.BorderSizePixel = 0
                cbFill.Visible = false
                cbFill.Parent = cbInside

                local nameLabel = Instance.new('TextLabel')
                nameLabel.BackgroundTransparency = 1
                nameLabel.Position = UDim2.fromOffset(26, 0)
                nameLabel.Size = UDim2.new(1, -30, 1, 0)
                nameLabel.Font = Enum.Font.Gotham
                nameLabel.TextColor3 = Color3.fromHex('8C8F99')
                nameLabel.TextSize = 11
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextYAlignment = Enum.TextYAlignment.Center
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.Text = 'Loading...'
                nameLabel.Parent = row

                local clickBtn = Instance.new('TextButton')
                clickBtn.Name = 'ClickArea'
                clickBtn.Size = UDim2.new(1, 0, 1, 0)
                clickBtn.BackgroundTransparency = 1
                clickBtn.Text = ''
                clickBtn.AutoButtonColor = false
                clickBtn.BorderSizePixel = 0
                clickBtn.ZIndex = 5
                clickBtn.Parent = row

                local function paint(on)
                    local state = on == true
                    cbFill.Visible = state
                    cbFill.BackgroundColor3 = getActiveAccent()
                    nameLabel.TextColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromHex('8C8F99')
                end

                local currentCount = entry.count or 0
                local function updateLabel(newCount)
                    if newCount ~= nil then
                        currentCount = newCount
                    end
                    local cached = crewNameCache[entry.id]
                    if cached then
                        nameLabel.Text = string.format('%s (%d)', cached, currentCount)
                    else
                        nameLabel.Text = string.format('Crew %s (%d)', strId, currentCount)
                        task.spawn(function()
                            local display = getCrewDisplayName(entry.id)
                            if nameLabel and nameLabel.Parent then
                                nameLabel.Text = string.format('%s (%d)', display, currentCount)
                            end
                        end)
                    end
                end

                paint(cfg.isSelected(entry.id))
                updateLabel(entry.count)

                safeConnect(clickBtn.MouseEnter, function()
                    row.BackgroundTransparency = 0.5
                end)
                safeConnect(clickBtn.MouseLeave, function()
                    row.BackgroundTransparency = 1
                end)

                safeConnect(clickBtn.MouseButton1Click, function()
                    local nextOn = not cfg.isSelected(entry.id)
                    paint(nextOn)
                    cfg.setSelected(entry.id, nextOn)
                    if type(requestSaveConfig) == 'function' then
                        requestSaveConfig()
                    end
                end)

                local item = {
                    Frame = row,
                    Paint = paint,
                    UpdateLabel = updateLabel,
                }
                return item
            end

            local function refresh()
                local crews = collectServerCrews()
                if #crews == 0 then
                    for strId, r in pairs(rowByCrewId) do
                        destroyRow(r)
                    end
                    rowByCrewId = {}
                    showEmpty('No crews found on server')
                    return
                end

                hideEmpty()

                local activeIds = {}
                for _, entry in ipairs(crews) do
                    local strId = tostring(entry.id)
                    activeIds[strId] = true

                    local existing = rowByCrewId[strId]
                    if existing and existing.Frame and existing.Frame.Parent == body then
                        existing.UpdateLabel(entry.count)
                        existing.Paint(cfg.isSelected(entry.id))
                    else
                        if existing then
                            destroyRow(existing)
                        end
                        rowByCrewId[strId] = createRow(entry)
                    end
                end

                for strId, r in pairs(rowByCrewId) do
                    if not activeIds[strId] then
                        destroyRow(r)
                        rowByCrewId[strId] = nil
                    end
                end

                -- Orphan pass: remove any unexpected frames or duplicate elements in body
                for _, child in ipairs(body:GetChildren()) do
                    if child ~= bodyPad and child ~= bodyList and child ~= emptyLabel then
                        local isKnown = false
                        for _, r in pairs(rowByCrewId) do
                            if r.Frame == child then
                                isKnown = true
                                break
                            end
                        end
                        if not isKnown then
                            child.Visible = false
                            child.Parent = nil
                            pcall(function() child:Destroy() end)
                        end
                    end
                end
            end

            registerThemeRefresher(function()
                if body and body.Parent then
                    body.ScrollBarImageColor3 = getActiveAccent()
                end
                for strId, r in pairs(rowByCrewId) do
                    if r and r.Paint then
                        r.Paint(cfg.isSelected(strId))
                    end
                end
            end)

            local api = {}

            function api.isOpen()
                return panelOpen
            end

            function api.refresh()
                refresh()
            end

            function api.syncPosition()
                if panelOpen then
                    syncPosition()
                end
            end

            function api.setVisible(show)
                panelOpen = show == true
                panel.Visible = panelOpen
                if panelOpen then
                    if cfg.onOpen then
                        cfg.onOpen()
                    end
                    syncPosition()
                    refresh()
                end
            end

            safeConnect(closeBtn.MouseButton1Click, function()
                api.setVisible(false)
            end)

            return api
        end

        targetsPanelApi = makeCrewRolePanel({
            panelName = 'CrewTargetsPanel',
            title = 'Crew Targets',
            isSelected = isCrewTargetSelected,
            setSelected = setCrewTargetSelected,
            onOpen = function()
                if friendsPanelApi then
                    friendsPanelApi.setVisible(false)
                end
            end,
        })

        friendsPanelApi = makeCrewRolePanel({
            panelName = 'CrewFriendsPanel',
            title = 'Crew Friends',
            isSelected = isCrewFriendSelected,
            setSelected = setCrewFriendSelected,
            onOpen = function()
                if targetsPanelApi then
                    targetsPanelApi.setVisible(false)
                end
            end,
        })

        watchPlayerCrew = function(player)
            if not player or crewWatchConnections[player] then
                return
            end
            local conns = {}
            local function onCrewChanged()
                applyCrewRoleForPlayer(player)
                renderAllRows()
                refreshOpenCrewPanels()
            end
            local function bindCrewValue(crewInst)
                if not crewInst or not crewInst:IsA('ValueBase') then
                    return
                end
                table.insert(conns, crewInst:GetPropertyChangedSignal('Value'):Connect(onCrewChanged))
            end
            local function bindInfo(info)
                if not info then
                    return
                end
                bindCrewValue(info:FindFirstChild('Crew'))
                table.insert(conns, info.ChildAdded:Connect(function(ch)
                    if ch.Name == 'Crew' then
                        bindCrewValue(ch)
                        onCrewChanged()
                    end
                end))
            end
            local function bindDataFolder(df)
                if not df then
                    return
                end
                bindInfo(df:FindFirstChild('Information'))
                table.insert(conns, df.ChildAdded:Connect(function(ch)
                    if ch.Name == 'Information' then
                        bindInfo(ch)
                        onCrewChanged()
                    end
                end))
            end
            bindDataFolder(player:FindFirstChild('DataFolder'))
            table.insert(conns, player.ChildAdded:Connect(function(ch)
                if ch.Name == 'DataFolder' then
                    bindDataFolder(ch)
                    onCrewChanged()
                end
            end))
            crewWatchConnections[player] = conns
        end

        for _, pl in ipairs(Players:GetPlayers()) do
            watchPlayerCrew(pl)
        end

        trackConnection(safeConnect(Players.PlayerAdded, function(pl)
            refreshRows()
            watchPlayerCrew(pl)
            syncCrewRoles()
            refreshOpenCrewPanels()
        end))
        trackConnection(safeConnect(Players.PlayerRemoving, function(pl)
            if pl then
                if pl.UserId then
                    crewSyncedByUserId[pl.UserId] = nil
                end
                if crewWatchConnections[pl] then
                    for _, c in ipairs(crewWatchConnections[pl]) do
                        pcall(function()
                            if c and c.Disconnect then
                                c:Disconnect()
                            end
                        end)
                    end
                    crewWatchConnections[pl] = nil
                end
            end
            refreshRows()
            refreshOpenCrewPanels()
        end))

        safeConnect(crewsTargetsBtn.MouseButton1Click, function()
            targetsPanelApi.setVisible(not targetsPanelApi.isOpen())
        end)
        safeConnect(crewsFriendsBtn.MouseButton1Click, function()
            friendsPanelApi.setVisible(not friendsPanelApi.isOpen())
        end)

        if main then
            safeConnect(main:GetPropertyChangedSignal('Position'), function()
                targetsPanelApi.syncPosition()
                friendsPanelApi.syncPosition()
            end)
            safeConnect(main:GetPropertyChangedSignal('Size'), function()
                targetsPanelApi.syncPosition()
                friendsPanelApi.syncPosition()
            end)
        end

        local function onCrewOptionChanged()
            syncCrewRoles()
            refreshOpenCrewPanels()
        end
        attachChangeListener(State.SelectedCrewTargets, onCrewOptionChanged)
        attachChangeListener(State.SelectedCrewFriends, onCrewOptionChanged)

        syncCrewRoles()
        refreshRows()
    end)()


    ;(function()
        local sorterSection = createSection(pages.Inventory, 'Inventory Sorter')
        createToggle(sorterSection, 'Auto Sort', State.InventoryAutoSortEnabled)
        createToggle(sorterSection, 'Auto Sort On Spawn', State.InventoryAutoSortOnSpawn)
        createKeybindRow(sorterSection, 'Auto Sort Keybind', State.InventoryAutoSortKey)

        local slotRows = {}
        for i = 1, 9 do
            slotRows[i] = createInventorySlotDropdownRow(
                sorterSection,
                'Slot ' .. i,
                State.InventorySlots[i]
            )
        end

        local function syncSlotVisibility()
            local visible = State.InventoryAutoSortEnabled.Value == true
            for i = 1, #slotRows do
                slotRows[i]:setVisible(visible)
            end
        end

        attachChangeListener(State.InventoryAutoSortEnabled, syncSlotVisibility)
        syncSlotVisibility()
    end)()

    ;(function()
        local function notify(msg, dur)
            if type(showNotification) == 'function' then
                showNotification('Settings', tostring(msg), dur or 3)
            end
        end

        settingsWindow = Instance.new('Frame')
        settingsWindow.Name = 'SettingsWindow'
        settingsWindow.AnchorPoint = Vector2.new(1, 0)
        settingsWindow.Size = UDim2.fromOffset(240, (main and main.Size.Y.Offset) or 550)
        if main then
            settingsWindow.Position = UDim2.new(main.Position.X.Scale, main.Position.X.Offset - 2, main.Position.Y.Scale, main.Position.Y.Offset)
        else
            settingsWindow.Position = UDim2.new(0.5, -302, 0.5, -275)
        end
        settingsWindow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        settingsWindow.BorderSizePixel = 0
        settingsWindow.Visible = false
        settingsWindow.Parent = menuGroup

        local swGrad = Instance.new('UIGradient')
        swGrad.Rotation = 90
        swGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('212121')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('1A1A1A')),
        })
        swGrad.Parent = settingsWindow

        local swOuterStroke = Instance.new('UIStroke')
        swOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        swOuterStroke.Color = Color3.fromHex('000000')
        swOuterStroke.Thickness = 1
        swOuterStroke.LineJoinMode = Enum.LineJoinMode.Miter
        swOuterStroke.Parent = settingsWindow

        local swInner = Instance.new('Frame')
        swInner.Name = 'InnerOutline'
        swInner.Position = UDim2.new(0, 1, 0, 1)
        swInner.Size = UDim2.new(1, -2, 1, -2)
        swInner.BackgroundTransparency = 1
        swInner.BorderSizePixel = 0
        swInner.Parent = settingsWindow

        local swInnerStroke = Instance.new('UIStroke')
        swInnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        swInnerStroke.Color = Color3.fromHex('393939')
        swInnerStroke.Thickness = 1
        swInnerStroke.LineJoinMode = Enum.LineJoinMode.Miter
        swInnerStroke.Parent = swInner

        local swTopLine = Instance.new('Frame')
        swTopLine.Name = 'TopAccentLine'
        swTopLine.Position = UDim2.new(0, 1, 0, 1)
        swTopLine.Size = UDim2.new(1, -2, 0, 1)
        swTopLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        swTopLine.BorderSizePixel = 0
        swTopLine.ZIndex = 10
        swTopLine.Parent = settingsWindow
        local swTopGrad = Instance.new('UIGradient')
        swTopGrad.Parent = swTopLine
        registerAccentGradient(swTopGrad)

        local swTitle = Instance.new('TextLabel')
        swTitle.Name = 'Title'
        swTitle.Position = UDim2.new(0, 6, 0, 9)
        swTitle.Size = UDim2.new(0, 200, 0, 18)
        swTitle.BackgroundTransparency = 1
        swTitle.Text = 'Settings'
        swTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        swTitle.TextSize = 12
        swTitle.Font = Enum.Font.Gotham
        swTitle.TextXAlignment = Enum.TextXAlignment.Left
        swTitle.TextYAlignment = Enum.TextYAlignment.Center
        swTitle.Parent = settingsWindow

        local swContent = Instance.new('Frame')
        swContent.Name = 'Content'
        swContent.Position = UDim2.new(0, 5, 0, 34)
        swContent.Size = UDim2.new(1, -10, 1, -39)
        swContent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        swContent.BorderSizePixel = 0
        swContent.Parent = settingsWindow

        local swContentGrad = Instance.new('UIGradient')
        swContentGrad.Rotation = 90
        swContentGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('161616')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('101010')),
        })
        swContentGrad.Parent = swContent

        local function swContentEdge(anchor, pos, sz, col)
            local ce = Instance.new('Frame')
            ce.AnchorPoint = anchor
            ce.Position = pos
            ce.Size = sz
            ce.BackgroundColor3 = Color3.fromHex(col)
            ce.BorderSizePixel = 0
            ce.ZIndex = 10
            ce.Parent = swContent
        end
        swContentEdge(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(0, 1, 1, 0),   '000000')
        swContentEdge(Vector2.new(0, 0), UDim2.new(0, 1, 0, 1),  UDim2.new(0, 1, 1, -2),  '393939')
        swContentEdge(Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  UDim2.new(0, 1, 1, 0),   '000000')
        swContentEdge(Vector2.new(1, 0), UDim2.new(1, -1, 0, 1), UDim2.new(0, 1, 1, -2),  '393939')
        swContentEdge(Vector2.new(0, 1), UDim2.new(0, 0, 1, 0),  UDim2.new(1, 0, 0, 1),   '000000')
        swContentEdge(Vector2.new(0, 1), UDim2.new(0, 1, 1, -1), UDim2.new(1, -2, 0, 1),  '393939')

        local swPage = Instance.new('Frame')
        swPage.Name = 'Page'
        swPage.Position = UDim2.new(0, 2, 0, 2)
        swPage.Size = UDim2.new(1, -4, 1, -4)
        swPage.BackgroundTransparency = 1
        swPage.BorderSizePixel = 0
        swPage.Parent = swContent

        local swPagePad = Instance.new('UIPadding')
        swPagePad.PaddingLeft = UDim.new(0, 6)
        swPagePad.PaddingRight = UDim.new(0, 6)
        swPagePad.PaddingTop = UDim.new(0, 9)
        swPagePad.PaddingBottom = UDim.new(0, 4)
        swPagePad.Parent = swPage

        local swColumn = Instance.new('ScrollingFrame')
        swColumn.Name = 'Column'
        swColumn.Position = UDim2.new(0, 0, 0, -2)
        swColumn.Size = UDim2.new(1, 0, 1, 2)
        swColumn.BackgroundTransparency = 1
        swColumn.BorderSizePixel = 0
        swColumn.CanvasSize = UDim2.new(0, 0, 0, 0)
        swColumn.AutomaticCanvasSize = Enum.AutomaticSize.Y
        swColumn.ScrollBarThickness = 2
        swColumn.ScrollBarImageColor3 = palette.accent
        swColumn.ScrollingDirection = Enum.ScrollingDirection.Y
        swColumn.ClipsDescendants = true
        swColumn.Parent = swPage

        bindTheme(swColumn, 'ScrollBarImageColor3', 'accent')

        local swColLayout = Instance.new('UIListLayout')
        swColLayout.FillDirection = Enum.FillDirection.Vertical
        swColLayout.SortOrder = Enum.SortOrder.LayoutOrder
        swColLayout.Padding = UDim.new(0, 6)
        swColLayout.Parent = swColumn

        local swColPad = Instance.new('UIPadding')
        swColPad.PaddingTop = UDim.new(0, 4)
        swColPad.PaddingBottom = UDim.new(0, 6)
        swColPad.Parent = swColumn

        syncSettingsPosition = function()
            if settingsWindow and main then
                settingsWindow.Size = UDim2.fromOffset(240, main.Size.Y.Offset)
                settingsWindow.Position = UDim2.new(main.Position.X.Scale, main.Position.X.Offset - 2, main.Position.Y.Scale, main.Position.Y.Offset)
            end
        end

        local function createCoincideButtonRow(parent, buttons)
            local row = Instance.new('Frame')
            row.Name = 'CoincideButtonRow'
            row.Size = UDim2.new(1, 0, 0, 21)
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.Parent = parent

            local layout = Instance.new('UIListLayout')
            layout.FillDirection = Enum.FillDirection.Horizontal
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 4)
            layout.Parent = row

            local n = #buttons
            local gap = 4 * (n - 1)
            for i, b in ipairs(buttons) do
                local btn = Instance.new('TextButton')
                btn.Name = 'Btn_' .. tostring(b.name or b.text or i)
                btn.Size = UDim2.new(1 / n, -(gap / n), 1, 0)
                btn.BackgroundColor3 = Color3.fromHex('000000')
                btn.BorderSizePixel = 0
                btn.AutoButtonColor = false
                btn.Text = ''
                btn.LayoutOrder = i
                btn.Parent = row

                local bGray = Instance.new('Frame')
                bGray.Position = UDim2.new(0, 1, 0, 1)
                bGray.Size = UDim2.new(1, -2, 1, -2)
                bGray.BackgroundColor3 = Color3.fromHex('393939')
                bGray.BorderSizePixel = 0
                bGray.Parent = btn

                local bInside = Instance.new('Frame')
                bInside.Position = UDim2.new(0, 1, 0, 1)
                bInside.Size = UDim2.new(1, -2, 1, -2)
                bInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                bInside.BorderSizePixel = 0
                bInside.Parent = bGray

                local bGrad = Instance.new('UIGradient')
                bGrad.Rotation = 90
                bGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
                })
                bGrad.Parent = bInside

                local lbl = Instance.new('TextLabel')
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.BorderSizePixel = 0
                lbl.Text = tostring(b.name or b.text or '')
                lbl.TextColor3 = Color3.fromHex('FFFFFF')
                lbl.TextSize = 12
                lbl.Font = Enum.Font.Gotham
                lbl.TextXAlignment = Enum.TextXAlignment.Center
                lbl.TextYAlignment = Enum.TextYAlignment.Center
                lbl.Parent = bInside

                safeConnect(btn.MouseEnter, function()
                    bGrad.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromHex('262626')),
                        ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
                    })
                end)
                safeConnect(btn.MouseLeave, function()
                    bGrad.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                        ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
                    })
                end)

                local confirmArmed = false
                safeConnect(btn.MouseButton1Click, function()
                    if b.confirm and not confirmArmed then
                        confirmArmed = true
                        local origText = lbl.Text
                        lbl.Text = 'Confirm?'
                        lbl.TextColor3 = Color3.fromRGB(255, 90, 90)
                        task.delay(2.5, function()
                            if confirmArmed then
                                confirmArmed = false
                                lbl.Text = origText
                                lbl.TextColor3 = Color3.fromHex('FFFFFF')
                            end
                        end)
                        return
                    end
                    confirmArmed = false
                    if b.confirm then
                        lbl.Text = tostring(b.name or b.text or '')
                        lbl.TextColor3 = Color3.fromHex('FFFFFF')
                    end
                    if type(b.callback) == 'function' then
                        b.callback()
                    end
                end)
            end
            return row
        end

        local function createCoincideButton(parent, text, callback, confirm)
            return createCoincideButtonRow(parent, { { name = text, callback = callback, confirm = confirm } })
        end

        local function createCoincideDropdown(parent, caption, optionObj, values, callback)
            local container = Instance.new('Frame')
            container.Name = 'Dropdown_' .. tostring(caption)
            container.Size = UDim2.new(1, 0, 0, 36)
            container.BackgroundTransparency = 1
            container.BorderSizePixel = 0
            container.Parent = parent

            local lbl = Instance.new('TextLabel')
            lbl.Name = 'Label'
            lbl.Position = UDim2.new(0, 0, 0, 0)
            lbl.Size = UDim2.new(1, 0, 0, 12)
            lbl.BackgroundTransparency = 1
            lbl.Text = tostring(caption)
            lbl.TextColor3 = Color3.fromHex('FFFFFF')
            lbl.TextSize = 12
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.Parent = container

            local btn = Instance.new('TextButton')
            btn.Name = 'Btn'
            btn.AnchorPoint = Vector2.new(0, 1)
            btn.Position = UDim2.new(0, 0, 1, 0)
            btn.Size = UDim2.new(1, 0, 0, 21)
            btn.BackgroundColor3 = Color3.fromHex('000000')
            btn.BorderSizePixel = 0
            btn.AutoButtonColor = false
            btn.Text = ''
            btn.Parent = container

            local bGray = Instance.new('Frame')
            bGray.Position = UDim2.new(0, 1, 0, 1)
            bGray.Size = UDim2.new(1, -2, 1, -2)
            bGray.BackgroundColor3 = Color3.fromHex('393939')
            bGray.BorderSizePixel = 0
            bGray.Parent = btn

            local bInside = Instance.new('Frame')
            bInside.Position = UDim2.new(0, 1, 0, 1)
            bInside.Size = UDim2.new(1, -2, 1, -2)
            bInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            bInside.BorderSizePixel = 0
            bInside.Parent = bGray

            local bGrad = Instance.new('UIGradient')
            bGrad.Rotation = 90
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
            bGrad.Parent = bInside

            local valLbl = Instance.new('TextLabel')
            valLbl.Name = 'Value'
            valLbl.Position = UDim2.new(0, 6, 0, 0)
            valLbl.Size = UDim2.new(1, -24, 1, 0)
            valLbl.BackgroundTransparency = 1
            valLbl.BorderSizePixel = 0
            valLbl.TextColor3 = Color3.fromHex('FFFFFF')
            valLbl.TextSize = 12
            valLbl.Font = Enum.Font.Gotham
            valLbl.TextXAlignment = Enum.TextXAlignment.Left
            valLbl.TextYAlignment = Enum.TextYAlignment.Center
            valLbl.ClipsDescendants = true
            valLbl.Parent = bInside

            local arrow = Instance.new('TextLabel')
            arrow.Name = 'Arrow'
            arrow.AnchorPoint = Vector2.new(1, 0)
            arrow.Position = UDim2.new(1, -4, 0, 0)
            arrow.Size = UDim2.new(0, 16, 1, 0)
            arrow.BackgroundTransparency = 1
            arrow.BorderSizePixel = 0
            arrow.TextColor3 = Color3.fromHex('8C8F99')
            arrow.TextSize = 10
            arrow.Font = Enum.Font.Gotham
            arrow.Text = 'v'
            arrow.TextXAlignment = Enum.TextXAlignment.Center
            arrow.TextYAlignment = Enum.TextYAlignment.Center
            arrow.Parent = bInside

            local function currentIndex()
                local current = type(optionObj.Value) == 'string' and optionObj.Value or tostring(values[1] or '')
                for i, v in ipairs(values) do
                    if tostring(v) == current then return i end
                end
                return 1
            end

            local function render()
                local cur = optionObj and optionObj.Value
                if cur ~= nil and cur ~= '' then
                    valLbl.Text = tostring(cur)
                else
                    local idx = currentIndex()
                    valLbl.Text = tostring(values[idx] or '')
                end
            end

            safeConnect(btn.MouseEnter, function()
                bGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('262626')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
                })
            end)
            safeConnect(btn.MouseLeave, function()
                bGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
                })
            end)

            safeConnect(btn.MouseButton1Click, function()
                local idx = currentIndex() + 1
                if idx > #values then idx = 1 end
                local nextVal = tostring(values[idx])
                optionObj:SetValue(nextVal)
                render()
            end)

            attachChangeListener(optionObj, function()
                render()
                if isApplyingPreset then
                    return
                end
                if type(callback) == 'function' then
                    callback(tostring(optionObj.Value))
                end
            end)

            render()
            return container
        end

        local function createCoincideTextbox(parent, name, defaultVal, placeholder, onCommit)
            local container = Instance.new('Frame')
            container.Name = 'Textbox_' .. tostring(name)
            container.Size = UDim2.new(1, 0, 0, 36)
            container.BackgroundTransparency = 1
            container.BorderSizePixel = 0
            container.Parent = parent

            local lbl = Instance.new('TextLabel')
            lbl.Name = 'Label'
            lbl.Position = UDim2.new(0, 0, 0, 0)
            lbl.Size = UDim2.new(1, 0, 0, 12)
            lbl.BackgroundTransparency = 1
            lbl.Text = tostring(name)
            lbl.TextColor3 = Color3.fromHex('FFFFFF')
            lbl.TextSize = 12
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.Parent = container

            local box = Instance.new('Frame')
            box.Name = 'Box'
            box.AnchorPoint = Vector2.new(0, 1)
            box.Position = UDim2.new(0, 0, 1, 0)
            box.Size = UDim2.new(1, 0, 0, 21)
            box.BackgroundColor3 = Color3.fromHex('000000')
            box.BorderSizePixel = 0
            box.Parent = container

            local boxGray = Instance.new('Frame')
            boxGray.Position = UDim2.new(0, 1, 0, 1)
            boxGray.Size = UDim2.new(1, -2, 1, -2)
            boxGray.BackgroundColor3 = Color3.fromHex('393939')
            boxGray.BorderSizePixel = 0
            boxGray.Parent = box

            local boxInside = Instance.new('Frame')
            boxInside.Position = UDim2.new(0, 1, 0, 1)
            boxInside.Size = UDim2.new(1, -2, 1, -2)
            boxInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            boxInside.BorderSizePixel = 0
            boxInside.Parent = boxGray

            local bGrad = Instance.new('UIGradient')
            bGrad.Rotation = 90
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
            bGrad.Parent = boxInside

            local input = Instance.new('TextBox')
            input.Name = 'Input'
            input.Position = UDim2.new(0, 4, 0, 0)
            input.Size = UDim2.new(1, -8, 1, 0)
            input.BackgroundTransparency = 1
            input.BorderSizePixel = 0
            input.ClearTextOnFocus = false
            input.Text = tostring(defaultVal or '')
            input.PlaceholderText = tostring(placeholder or '...')
            input.PlaceholderColor3 = Color3.fromHex('5E626B')
            input.TextColor3 = Color3.fromHex('FFFFFF')
            input.TextSize = 12
            input.Font = Enum.Font.Gotham
            input.TextXAlignment = Enum.TextXAlignment.Left
            input.TextYAlignment = Enum.TextYAlignment.Center
            input.ClipsDescendants = true
            input.Parent = boxInside

            safeConnect(input.FocusLost, function(enterPressed)
                if type(onCommit) == 'function' then
                    onCommit(input.Text)
                end
            end)

            local tbObj = {
                Container = container,
                Input = input,
            }

            local function resolveTbVal(a, b)
                if a == tbObj or (type(a) == 'table' and a.Input == input) then
                    return b
                end
                if b ~= nil then
                    return b
                end
                return a
            end

            tbObj.Get = function(self)
                return input.Text
            end

            tbObj.Set = function(a, b)
                local val = resolveTbVal(a, b)
                if type(val) == 'table' then
                    val = val.Value or val.Name or val.Text or val[1] or ''
                end
                local s = tostring(val or '')
                if s:find('^table:%s*0x') then
                    return
                end
                input.Text = s
            end

            return tbObj
        end

        local function createCoincideList(parent, name, items, defaultVal, height, onSelect)
            height = tonumber(height) or 90
            local container = Instance.new('Frame')
            container.Name = 'List_' .. tostring(name)
            container.Size = UDim2.new(1, 0, 0, height + 16)
            container.BackgroundTransparency = 1
            container.BorderSizePixel = 0
            container.ZIndex = 15
            container.Parent = parent

            local lbl = Instance.new('TextLabel')
            lbl.Name = 'Label'
            lbl.Position = UDim2.new(0, 0, 0, 0)
            lbl.Size = UDim2.new(1, 0, 0, 12)
            lbl.BackgroundTransparency = 1
            lbl.Text = tostring(name)
            lbl.TextColor3 = Color3.fromHex('FFFFFF')
            lbl.TextSize = 12
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextYAlignment = Enum.TextYAlignment.Center
            lbl.ZIndex = 16
            lbl.Parent = container

            local box = Instance.new('Frame')
            box.Name = 'Box'
            box.AnchorPoint = Vector2.new(0, 1)
            box.Position = UDim2.new(0, 0, 1, 0)
            box.Size = UDim2.new(1, 0, 0, height)
            box.BackgroundColor3 = Color3.fromHex('000000')
            box.BorderSizePixel = 0
            box.ZIndex = 16
            box.Parent = container

            local boxGray = Instance.new('Frame')
            boxGray.Position = UDim2.new(0, 1, 0, 1)
            boxGray.Size = UDim2.new(1, -2, 1, -2)
            boxGray.BackgroundColor3 = Color3.fromHex('393939')
            boxGray.BorderSizePixel = 0
            boxGray.ZIndex = 17
            boxGray.Parent = box

            local boxInside = Instance.new('Frame')
            boxInside.Position = UDim2.new(0, 1, 0, 1)
            boxInside.Size = UDim2.new(1, -2, 1, -2)
            boxInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            boxInside.BorderSizePixel = 0
            boxInside.ZIndex = 18
            boxInside.Parent = boxGray

            local bGrad = Instance.new('UIGradient')
            bGrad.Rotation = 90
            bGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
            bGrad.Parent = boxInside

            local scroller = Instance.new('ScrollingFrame')
            scroller.Name = 'Scroller'
            scroller.Size = UDim2.new(1, 0, 1, 0)
            scroller.BackgroundTransparency = 1
            scroller.BorderSizePixel = 0
            scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
            scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
            scroller.ScrollBarThickness = 2
            scroller.ScrollBarImageColor3 = palette.accent
            scroller.ScrollingDirection = Enum.ScrollingDirection.Y
            scroller.ClipsDescendants = true
            scroller.ZIndex = 19
            scroller.Parent = boxInside

            bindTheme(scroller, 'ScrollBarImageColor3', 'accent')

            local listLayout = Instance.new('UIListLayout')
            listLayout.FillDirection = Enum.FillDirection.Vertical
            listLayout.SortOrder = Enum.SortOrder.LayoutOrder
            listLayout.Parent = scroller

            local pad = Instance.new('UIPadding')
            pad.PaddingTop = UDim.new(0, 2)
            pad.PaddingBottom = UDim.new(0, 2)
            pad.Parent = scroller

            local currentVal = tostring(defaultVal or (items and items[1]) or '')
            local currentItems = type(items) == 'table' and items or {}
            local optionButtons = {}

            local function refreshHighlights()
                local curAcc = getActiveAccent()
                for _, btn in ipairs(optionButtons) do
                    local isSel = (btn.Text == currentVal)
                    btn.TextColor3 = isSel and curAcc or Color3.fromHex('A0A0A0')
                    btn.BackgroundColor3 = isSel and Color3.fromHex('222222') or Color3.fromHex('000000')
                    btn.BackgroundTransparency = isSel and 0.5 or 1
                end
            end

            local function buildList(newItems)
                if newItems and type(newItems) == 'table' and newItems ~= scroller then
                    local cleaned = {}
                    for _, item in ipairs(newItems) do
                        local s = type(item) == 'string' and item or (type(item) == 'table' and (item.Value or item.Name or item.Text)) or tostring(item or '')
                        if s ~= '' and not string.find(s, '^table:%s*0x') then
                            table.insert(cleaned, s)
                        end
                    end
                    currentItems = cleaned
                end
                for _, ch in ipairs(scroller:GetChildren()) do
                    if ch:IsA('TextButton') then
                        ch:Destroy()
                    end
                end
                table.clear(optionButtons)
                for idx, item in ipairs(currentItems) do
                    local str = tostring(item)
                    local optBtn = Instance.new('TextButton')
                    optBtn.Name = 'Opt_' .. str
                    optBtn.Size = UDim2.new(1, 0, 0, 18)
                    optBtn.BackgroundTransparency = 1
                    optBtn.BorderSizePixel = 0
                    optBtn.AutoButtonColor = false
                    optBtn.Text = str
                    optBtn.TextColor3 = (str == currentVal) and getActiveAccent() or Color3.fromHex('C0C0C0')
                    optBtn.TextSize = 12
                    optBtn.Font = Enum.Font.Gotham
                    optBtn.TextXAlignment = Enum.TextXAlignment.Left
                    optBtn.LayoutOrder = idx
                    optBtn.ZIndex = 20
                    optBtn.ClipsDescendants = true
                    optBtn.Visible = true
                    optBtn.Parent = scroller

                    local optPad = Instance.new('UIPadding')
                    optPad.PaddingLeft = UDim.new(0, 6)
                    optPad.Parent = optBtn

                    safeConnect(optBtn.MouseEnter, function()
                        if optBtn.Text ~= currentVal then
                            optBtn.TextColor3 = Color3.fromHex('FFFFFF')
                        end
                    end)
                    safeConnect(optBtn.MouseLeave, function()
                        if optBtn.Text ~= currentVal then
                            optBtn.TextColor3 = Color3.fromHex('C0C0C0')
                        else
                            optBtn.TextColor3 = getActiveAccent()
                        end
                    end)

                    safeConnect(optBtn.MouseButton1Click, function()
                        currentVal = str
                        refreshHighlights()
                        if type(onSelect) == 'function' then
                            onSelect(currentVal)
                        end
                    end)
                    table.insert(optionButtons, optBtn)
                end
                scroller.CanvasSize = UDim2.new(0, 0, 0, math.max(height, #currentItems * 18 + 6))
                refreshHighlights()
            end

            buildList()
            if Options.ThemeAccent then
                attachChangeListener(Options.ThemeAccent, function()
                    refreshHighlights()
                end)
            end
            if State and State.ThemeAccent and State.ThemeAccent ~= Options.ThemeAccent then
                attachChangeListener(State.ThemeAccent, function()
                    refreshHighlights()
                end)
            end
            registerThemeRefresher(function()
                if scroller and scroller.Parent then
                    scroller.ScrollBarImageColor3 = getActiveAccent()
                end
                refreshHighlights()
            end)

            local listObj = {
                Container = container,
            }

            local function resolveListVal(a, b)
                if a == listObj or (type(a) == 'table' and a.Container == container) then
                    return b
                end
                if b ~= nil then
                    return b
                end
                return a
            end

            listObj.Get = function(self)
                return currentVal
            end

            listObj.Set = function(a, b)
                local val = resolveListVal(a, b)
                if type(val) == 'table' then
                    val = val.Value or val.Name or val.Text or val[1] or ''
                end
                local s = tostring(val or '')
                if not string.find(s, '^table:%s*0x') then
                    currentVal = s
                    refreshHighlights()
                end
            end

            listObj.SetOptions = function(a, b)
                local items = resolveListVal(a, b)
                if type(items) == 'table' then
                    buildList(items)
                end
            end

            return listObj
        end

        local settingsHost = { left = swColumn, right = swColumn, nextColumn = 1 }

        -- Section 1: Configuration
        local secCfg = createSection(settingsHost, 'Configuration')

        local configNameBox
        local configList
        configList = createCoincideList(secCfg, 'Configs', listConfigs(), 'default', 90, function(val)
            local cleanName = type(val) == 'string' and val or (type(val) == 'table' and (val.Value or val.Name or val.Text)) or tostring(val or '')
            if string.find(cleanName, '^table:%s*0x') then cleanName = 'default' end
            if State.ConfigName then
                State.ConfigName:SetValue(cleanName)
            end
            if configNameBox then
                configNameBox:Set(cleanName)
            end
        end)

        configNameBox = createCoincideTextbox(secCfg, 'Config Name', State.ConfigName and State.ConfigName.Value or 'default', 'name...', function(val)
            local cleanName = type(val) == 'string' and val or (type(val) == 'table' and (val.Value or val.Name or val.Text)) or tostring(val or '')
            if string.find(cleanName, '^table:%s*0x') then cleanName = 'default' end
            if State.ConfigName then
                State.ConfigName:SetValue(cleanName)
            end
        end)

        createCoincideButtonRow(secCfg, {
            {
                name = 'Save',
                callback = function()
                    local rawNm = configNameBox:Get()
                    local nm = tostring(rawNm or ''):gsub('^%s+', ''):gsub('%s+$', '')
                    if nm == '' or string.find(nm, '^table:%s*0x') then
                        notify('Enter a valid config name first', 3)
                        return
                    end
                    saveConfig(nm)
                    local updated = listConfigs()
                    configList:SetOptions(updated)
                    configList:Set(nm)
                    notify('Saved config: ' .. nm, 3)
                end,
            },
            {
                name = 'Load',
                callback = function()
                    local nm = tostring(configList:Get() or '')
                    if nm == '' or string.find(nm, '^table:%s*0x') then
                        notify('Select a valid config first', 3)
                        return
                    end
                    local ok, err = loadConfig(nm)
                    if ok ~= false then
                        applyThemePreset(State.ThemePreset and State.ThemePreset.Value or 'Default', true)
                        if type(applyLayoutSizes) == 'function' then
                            applyLayoutSizes()
                        end
                        applyTheme()
                        if configNameBox then
                            configNameBox:Set(nm)
                        end
                        notify('Loaded: ' .. nm, 3)
                    else
                        notify(tostring(err or 'Failed to load'), 3)
                    end
                end,
            },
        })

        createCoincideButtonRow(secCfg, {
            {
                name = 'Delete',
                confirm = true,
                callback = function()
                    local nm = tostring(configList:Get() or '')
                    if nm == '' or string.find(nm, '^table:%s*0x') then
                        notify('Select a valid config first', 3)
                        return
                    end
                    deleteConfig(nm)
                    local updated = listConfigs()
                    configList:SetOptions(updated)
                    if #updated > 0 then
                        configList:Set(updated[1])
                        if configNameBox then configNameBox:Set(updated[1]) end
                    end
                    notify('Deleted: ' .. nm, 3)
                end,
            },
            {
                name = 'Refresh',
                callback = function()
                    local updated = listConfigs()
                    configList:SetOptions(updated)
                    notify('Refreshed configs', 2)
                end,
            },
        })

        createCoincideButton(secCfg, 'Set As Auto Load', function()
            local nm = tostring(configList:Get() or '')
            if nm == '' or string.find(nm, '^table:%s*0x') then
                notify('Select a valid config first', 3)
                return
            end
            setAutoLoad(nm)
            notify('Auto-load: ' .. nm, 3)
        end)

        createCoincideButton(secCfg, 'Remove Auto Load', function()
            clearAutoLoad()
            notify('Auto-load cleared', 3)
        end, true)

        createCoincideButton(secCfg, 'Test Notification', function()
            notify('Hello there', 4)
        end)

        -- Section 2: Menu
        local secMenu = createSection(settingsHost, 'Menu')

        createCoincideDropdown(secMenu, 'Easing Style', State.MenuEaseStyle, {
            'Linear', 'Cubic', 'Quad', 'Quart', 'Quint', 'Sine', 'Exponential', 'Circular', 'Back', 'Elastic', 'Bounce'
        })
        createCoincideDropdown(secMenu, 'Easing Direction', State.MenuEaseDir, { 'In', 'Out', 'InOut' })
        createSlider(secMenu, 'Tweening Speed', State.TweeningSpeed, 0.05, 2, 0.05, ' s')
        createSlider(secMenu, 'Dragging Speed', State.DraggingSpeed, 0, 2, 0.05, ' s')
        createKeybindRow(secMenu, 'Menu Keybind', State.MenuKey)
        createCoincideButton(secMenu, 'Unload', function()
            Library:Unload()
        end)

        -- Section 3: HUD
        local secHud = createSection(settingsHost, 'HUD')

        createToggle(secHud, 'Watermark', State.Watermark)
        createCoincideDropdown(secHud, 'Watermark Options', State.WatermarkOpts, {
            'Title | Fps | Ping | Game',
            'Title | Fps | Ping',
            'Title | Fps',
            'Full Info',
        })
        createSlider(secHud, 'Refresh Rate', State.WatermarkRate, 0.05, 2, 0.05, ' s')

        local showKeybindsRow = createToggle(secHud, 'Keybind List', State.ShowKeybindsList)
        do
            local label = showKeybindsRow:FindFirstChild('Label')
            local switch = showKeybindsRow:FindFirstChild('Switch')
            if label and label:IsA('TextLabel') then
                label.Size = UDim2.new(1, -84, 0, 18)
            end
            if switch and switch:IsA('TextButton') then
                switch.Position = UDim2.new(1, -38, 0.5, 0)
            end

            local expandButton = Instance.new('TextButton')
            expandButton.Name = 'KeybindListExpand'
            expandButton.AutoButtonColor = false
            expandButton.AnchorPoint = Vector2.new(1, 0.5)
            expandButton.Position = UDim2.new(1, -12, 0.5, 0)
            expandButton.Size = UDim2.fromOffset(18, 18)
            expandButton.BackgroundColor3 = palette.surface
            expandButton.BackgroundTransparency = 0.2
            expandButton.BorderSizePixel = 0
            expandButton.Font = fonts.mono
            expandButton.TextSize = 12
            expandButton.TextColor3 = palette.textDim
            expandButton.Text = '>'
            expandButton.Parent = showKeybindsRow
            applyCorner(expandButton, 5)
            applyStroke(expandButton, 'strokeSoft', 1, 0.45)
            addHover(expandButton, 'surface', 'surfaceElevated')
            bindTheme(expandButton, 'BackgroundColor3', 'surface')
            bindTheme(expandButton, 'TextColor3', 'textDim')

            local keybindPickerWrap = Instance.new('Frame')
            keybindPickerWrap.Name = 'KeybindListPicker'
            keybindPickerWrap.BackgroundColor3 = palette.surface
            keybindPickerWrap.BackgroundTransparency = 0.25
            keybindPickerWrap.Size = UDim2.new(1, 0, 0, 0)
            keybindPickerWrap.AutomaticSize = Enum.AutomaticSize.Y
            keybindPickerWrap.BorderSizePixel = 0
            keybindPickerWrap.Visible = false
            keybindPickerWrap.Parent = secHud
            applyCorner(keybindPickerWrap, 10)
            applyStroke(keybindPickerWrap, 'strokeSoft', 1, 0.45)
            bindTheme(keybindPickerWrap, 'BackgroundColor3', 'surface')

            local keybindPickerPad = Instance.new('UIPadding')
            keybindPickerPad.PaddingTop = UDim.new(0, 8)
            keybindPickerPad.PaddingBottom = UDim.new(0, 8)
            keybindPickerPad.PaddingLeft = UDim.new(0, 8)
            keybindPickerPad.PaddingRight = UDim.new(0, 8)
            keybindPickerPad.Parent = keybindPickerWrap

            local keybindPickerBody = Instance.new('Frame')
            keybindPickerBody.BackgroundTransparency = 1
            keybindPickerBody.Size = UDim2.new(1, 0, 0, 0)
            keybindPickerBody.AutomaticSize = Enum.AutomaticSize.Y
            keybindPickerBody.Parent = keybindPickerWrap

            local keybindPickerLayout = Instance.new('UIListLayout')
            keybindPickerLayout.Padding = UDim.new(0, 6)
            keybindPickerLayout.Parent = keybindPickerBody

            createToggle(keybindPickerBody, 'Trigger', State.ShowTriggerInKeybinds)
            createToggle(keybindPickerBody, 'AutoShot', State.ShowAutoShotInKeybinds)
            createToggle(keybindPickerBody, 'AutoSort', State.ShowAutoSortInKeybinds)
            createToggle(keybindPickerBody, 'pSilent', State.ShowAimLockInKeybinds)
            createToggle(keybindPickerBody, 'Backtrack', State.ShowBacktrackInKeybinds)

            local keybindPickerOpen = false
            local function setKeybindPickerVisible(open)
                keybindPickerOpen = open == true
                keybindPickerWrap.Visible = keybindPickerOpen
                expandButton.Text = keybindPickerOpen and 'v' or '>'
            end

            safeConnect(expandButton.MouseButton1Click, function()
                setKeybindPickerVisible(not keybindPickerOpen)
            end)
        end

        createToggle(secHud, 'Anti-AimViewer', State.AntiAimViewerEnabled)
        createToggle(secHud, 'Spectator List', State.SpectatorListEnabled)
        createToggle(secHud, 'Staff Detector', State.StaffDetectorEnabled)
        createToggle(secHud, 'Panic Mode', State.PanicMode)

        -- Spectator detector (admin spectate) & Panic Mode suppression
        do
            local panicSpectating = false
            local panicSaved = nil
            local panicApplying = false

            local function setToggleSafe(toggle, value)
                if type(toggle) ~= 'table' or type(toggle.SetValue) ~= 'function' then
                    return
                end
                local want = value == true
                if toggle.Value == want then
                    return
                end
                pcall(function()
                    toggle:SetValue(want)
                end)
            end

            local function syncPanicSuppress()
                if panicApplying then
                    return
                end
                local modeOn = State.PanicMode and State.PanicMode.Value == true
                local should = modeOn and panicSpectating
                panicApplying = true
                pcall(function()
                    if should then
                        if not panicSaved then
                            panicSaved = {
                                silent = State.AimLock and State.AimLock.Enabled and State.AimLock.Enabled.Value == true,
                                backtrack = State.Backtrack and State.Backtrack.Enabled and State.Backtrack.Enabled.Value == true,
                            }
                        end
                        setToggleSafe(State.AimLock and State.AimLock.Enabled, false)
                        setToggleSafe(State.Backtrack and State.Backtrack.Enabled, false)
                        if BacktrackApi and type(BacktrackApi.clearAll) == 'function' then
                            pcall(BacktrackApi.clearAll)
                        end
                    elseif panicSaved then
                        local saved = panicSaved
                        panicSaved = nil
                        setToggleSafe(State.AimLock and State.AimLock.Enabled, saved.silent)
                        setToggleSafe(State.Backtrack and State.Backtrack.Enabled, saved.backtrack)
                    end
                end)
                panicApplying = false
            end

            local function onSpectateActiveChanged(active)
                panicSpectating = active == true
                syncPanicSuppress()
            end

            attachChangeListener(State.PanicMode, function()
                syncPanicSuppress()
            end)

            local function guardWhilePanicked()
                if panicApplying then
                    return
                end
                if State.PanicMode and State.PanicMode.Value == true and panicSpectating then
                    syncPanicSuppress()
                end
            end
            if State.AimLock and State.AimLock.Enabled then
                attachChangeListener(State.AimLock.Enabled, guardWhilePanicked)
            end
            if State.Backtrack and State.Backtrack.Enabled then
                attachChangeListener(State.Backtrack.Enabled, guardWhilePanicked)
            end
            local Players = game:GetService('Players')
            local ReplicatedStorage = game:GetService('ReplicatedStorage')
            local UIS = game:GetService('UserInputService')

            local LocalPlayer = Players.LocalPlayer
            if LocalPlayer then
                local spectatorGui = Instance.new('ScreenGui')
                spectatorGui.Name = 'SpectatorListMini'
                spectatorGui.ResetOnSpawn = false
                spectatorGui.IgnoreGuiInset = true
                spectatorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                spectatorGui.DisplayOrder = 999
                local _guiParent = (type(gethui) == 'function' and pcall(function() return gethui() end) and gethui()) or game:GetService('CoreGui') or LocalPlayer:FindFirstChild('PlayerGui')
                spectatorGui.Parent = _guiParent

                local specWin = createCoincideWindow({
                    Name = 'SpectatorListMiniPanel',
                    Title = 'Spectator List',
                    Width = 260,
                    Height = 58,
                    HasClose = false,
                    Parent = spectatorGui,
                })
                local panel = specWin.Outer
                panel.Position = UDim2.fromOffset(
                    tonumber(State.SpectatorListX and State.SpectatorListX.Value) or 16,
                    tonumber(State.SpectatorListY and State.SpectatorListY.Value) or 96
                )
                panel.Visible = false
                panel.Active = true
                spectatorListPanel = panel

                local panelHeader = specWin.Header
                local title = specWin.TitleLabel
                title.Text = 'Spectator List'

                local panelBody = specWin.Content

                local statusRow = Instance.new('Frame')
                statusRow.Name = 'StatusRow'
                statusRow.Position = UDim2.new(0, 0, 0, 0)
                statusRow.Size = UDim2.new(1, 0, 1, 0)
                statusRow.BackgroundTransparency = 1
                statusRow.BorderSizePixel = 0
                statusRow.Parent = panelBody

                local statusLabel = Instance.new('TextLabel')
                statusLabel.Name = 'StatusLabel'
                statusLabel.BackgroundTransparency = 1
                statusLabel.Position = UDim2.new(0, 8, 0, 0)
                statusLabel.Size = UDim2.new(0, 68, 1, 0)
                statusLabel.Font = Enum.Font.Gotham
                statusLabel.TextColor3 = Color3.fromHex('8C8F99')
                statusLabel.TextSize = 11
                statusLabel.TextXAlignment = Enum.TextXAlignment.Left
                statusLabel.TextYAlignment = Enum.TextYAlignment.Center
                statusLabel.Text = 'Spectating'
                statusLabel.Parent = statusRow

                local statusValue = Instance.new('TextLabel')
                statusValue.Name = 'StatusValue'
                statusValue.BackgroundTransparency = 1
                statusValue.Position = UDim2.new(0, 78, 0, 0)
                statusValue.Size = UDim2.new(1, -84, 1, 0)
                statusValue.Font = Enum.Font.GothamSemibold
                statusValue.TextColor3 = Color3.fromRGB(255, 255, 255)
                statusValue.TextSize = 11
                statusValue.TextXAlignment = Enum.TextXAlignment.Left
                statusValue.TextYAlignment = Enum.TextYAlignment.Center
                statusValue.TextTruncate = Enum.TextTruncate.None
                statusValue.Text = 'No'
                statusValue.Parent = statusRow

                local spectatorStarted = false
                local namecallUnhook = nil

                local ADMIN_GROUP = 925309458
                local ADMIN_MIN_RANK = 249
                local ADMIN_USERIDS = {
                    [731857328] = true,
                    [1786831293] = true,
                    [541093005] = true,
                    [9467396201] = true,
                }

                local state = {
                    active = false,
                    spectator = nil,
                    reason = 'idle',
                    specActiveAttr = false,
                    lastConfirm = 0,
                    telemStreaming = false,
                    remoteHit = false,
                }

                local function refreshUi()
                    if state.active then
                        statusValue.Text = 'Might be spectating you'
                        statusValue.TextColor3 = Color3.fromRGB(255, 70, 70)
                    else
                        statusValue.Text = 'No'
                        statusValue.TextColor3 = Color3.fromRGB(255, 255, 255)
                    end
                end

                local spDragging = false
                local spDragInput = nil
                local spDragStart = nil
                local spStartPos = nil

                safeConnect(panelHeader.InputBegan, function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        spDragging = true
                        spDragStart = input.Position
                        spStartPos = panel.Position
                        safeConnect(input.Changed, function()
                            if input.UserInputState == Enum.UserInputState.End then
                                spDragging = false
                                if panel and State.SpectatorListX and State.SpectatorListY then
                                    local pos = panel.Position
                                    pcall(function()
                                        State.SpectatorListX:SetValue(math.floor(pos.X.Offset + 0.5))
                                        State.SpectatorListY:SetValue(math.floor(pos.Y.Offset + 0.5))
                                    end)
                                    if type(requestSaveConfig) == 'function' then
                                        requestSaveConfig()
                                    end
                                end
                            end
                        end)
                    end
                end)

                safeConnect(panelHeader.InputChanged, function(input)
                    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                        spDragInput = input
                    end
                end)

                safeConnect(UIS.InputChanged, function(input)
                    if spDragging and input == spDragInput then
                        local delta = input.Position - spDragStart
                        panel.Position = UDim2.new(
                            spStartPos.X.Scale,
                            spStartPos.X.Offset + delta.X,
                            spStartPos.Y.Scale,
                            spStartPos.Y.Offset + delta.Y
                        )
                    end
                end)

                local rankCache = {}

                local function getGroupRank(player)
                    local cached = rankCache[player.UserId]
                    if cached and (tick() - cached.t) < 60 then
                        return cached.rank or 0
                    end
                    local ok, rank = pcall(function()
                        return player:GetRankInGroup(ADMIN_GROUP)
                    end)
                    local r = (ok and typeof(rank) == 'number') and rank or 0
                    rankCache[player.UserId] = { rank = r, t = tick() }
                    return r
                end

                local function isAdminPlayer(player)
                    if not player or player == LocalPlayer then
                        return false
                    end
                    if ADMIN_USERIDS[player.UserId] then
                        return true
                    end
                    return getGroupRank(player) >= ADMIN_MIN_RANK
                end

                local function listAdmins()
                    local list = {}
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if isAdminPlayer(plr) then
                            table.insert(list, plr)
                        end
                    end
                    return list
                end

                local function mentionsLocal(value)
                    if value == nil or value == false then return false end
                    if value == true then return true end
                    if typeof(value) == 'Instance' then
                        if value:IsA('Player') then
                            return value == LocalPlayer
                        end
                        if value:IsA('Model') then
                            return Players:GetPlayerFromCharacter(value) == LocalPlayer
                        end
                        if value:IsA('Humanoid') then
                            local model = value.Parent
                            return model and Players:GetPlayerFromCharacter(model) == LocalPlayer
                        end
                        return false
                    end
                    if typeof(value) == 'number' then
                        return value == LocalPlayer.UserId
                    end
                    if typeof(value) == 'string' then
                        local s = string.lower(value)
                        return s == string.lower(LocalPlayer.Name) or s == tostring(LocalPlayer.UserId) or s == 'me' or s == 'localplayer'
                    end
                    return false
                end

                local function findAdminInArgs(args)
                    for _, v in ipairs(args) do
                        if typeof(v) == 'Instance' and v:IsA('Player') and isAdminPlayer(v) then
                            return v
                        end
                        if typeof(v) == 'number' then
                            local plr = Players:GetPlayerByUserId(v)
                            if plr and isAdminPlayer(plr) then
                                return plr
                            end
                        end
                        if typeof(v) == 'string' then
                            local plr = Players:FindFirstChild(v)
                            if plr and plr:IsA('Player') and isAdminPlayer(plr) then
                                return plr
                            end
                        end
                    end
                    return nil
                end

                local function isStopArgs(args)
                    if #args == 0 then return true end
                    for _, v in ipairs(args) do
                        if v == false or v == nil then return true end
                        if typeof(v) == 'string' then
                            local s = string.lower(v)
                            if s == 'stop' or s == 'end' or s == 'off' or s == 'unspectate' or s == 'nil' or s == '' then
                                return true
                            end
                        end
                    end
                    return false
                end

                local function isStartArgs(args)
                    for _, v in ipairs(args) do
                        if v == true then return true end
                        if typeof(v) == 'string' then
                            local s = string.lower(v)
                            if s == 'start' or s == 'spectate' or s == 'on' or s == 'watch' or s == 'ghost' then
                                return true
                            end
                        end
                    end
                    return false
                end

                local function setActive(active, spectator, reason)
                    if active then
                        state.active = true
                        state.spectator = spectator
                        state.reason = reason or state.reason
                        state.lastConfirm = tick()
                    else
                        state.active = false
                        state.spectator = nil
                        state.reason = reason or 'idle'
                        state.remoteHit = false
                    end
                    refreshUi()
                    onSpectateActiveChanged(state.active == true)
                end

                local function confirm(spectator, reason)
                    state.remoteHit = true
                    state.specActiveAttr = state.specActiveAttr or ReplicatedStorage:FindFirstChild('AdminRemotes') and ReplicatedStorage.AdminRemotes:GetAttribute('SpecActive') == true
                    setActive(true, spectator, reason)
                end

                local function adminLooksGhosted(plr)
                    if not plr or plr == LocalPlayer then return false end
                    local char = plr.Character
                    if not char then return true end
                    if not char.Parent then return true end
                    local inWorkspace = char:IsDescendantOf(workspace)
                    if not inWorkspace then return true end
                    local hrp = char:FindFirstChild('HumanoidRootPart')
                    if not hrp then return true end
                    return false
                end

                local function startSpectatorDetector()
                    if spectatorStarted then return end
                    spectatorStarted = true

                    refreshUi()

                    task.spawn(function()
                        local AdminRemotes = ReplicatedStorage:WaitForChild('AdminRemotes', 120)
                        if not AdminRemotes then
                            return
                        end

                        local Spectate = AdminRemotes:WaitForChild('Spectate', 30)
                        local SpecData = AdminRemotes:FindFirstChild('SpecData')
                        local Telem = AdminRemotes:FindFirstChild('Telem')
                        local Ghosted = AdminRemotes:FindFirstChild('Ghosted')

                        state.specActiveAttr = AdminRemotes:GetAttribute('SpecActive') == true
                        refreshUi()

                        local okAttrConn = nil
                        okAttrConn = AdminRemotes:GetAttributeChangedSignal('SpecActive'):Connect(function()
                            state.specActiveAttr = AdminRemotes:GetAttribute('SpecActive') == true
                            state.telemStreaming = state.specActiveAttr
                            if state.specActiveAttr then
                                setActive(true, findAdminInArgs({}), 'SpecActive')
                            else
                                if not state.remoteHit then
                                    setActive(false, nil, 'SpecActive off')
                                end
                            end
                            refreshUi()
                        end)

                        local connections = {}
                        local function track(c)
                            connections[#connections + 1] = c
                            return c
                        end

                        local function onSpectatePacket(...)
                            local args = { ... }
                            if isStopArgs(args) then
                                local targetsMe = false
                                for _, v in ipairs(args) do
                                    if mentionsLocal(v) then
                                        targetsMe = true
                                        break
                                    end
                                end
                                if not targetsMe then
                                    state.remoteHit = false
                                end
                                return
                            end
                            local targetsMe = false
                            for _, v in ipairs(args) do
                                if mentionsLocal(v) then
                                    targetsMe = true
                                    break
                                end
                            end
                            if targetsMe or isStartArgs(args) or #args > 0 then
                                confirm(findAdminInArgs(args), 'spectate packet')
                            end
                        end

                        if Spectate and Spectate:IsA('RemoteEvent') then
                            track(Spectate.OnClientEvent:Connect(function(...)
                                pcall(onSpectatePacket, ...)
                            end))
                        end
                        if SpecData and SpecData:IsA('RemoteEvent') then
                            track(SpecData.OnClientEvent:Connect(function(...)
                                local args = { ... }
                                local targetsMe = false
                                for _, v in ipairs(args) do
                                    if mentionsLocal(v) then
                                        targetsMe = true
                                        break
                                    end
                                end
                                if targetsMe or isStartArgs(args) then
                                    confirm(findAdminInArgs(args), 'SpecData')
                                end
                            end))
                        end
                        if Ghosted and Ghosted:IsA('RemoteEvent') then
                            track(Ghosted.OnClientEvent:Connect(function(...)
                                local args = { ... }
                                if isStopArgs(args) then return end
                                local admin = findAdminInArgs(args)
                                if admin or isStartArgs(args) then
                                    confirm(admin, 'Ghosted')
                                elseif #args > 0 and mentionsLocal(args[1]) then
                                    confirm(findAdminInArgs(args), 'Ghosted packet')
                                end
                            end))
                        end

                        if Telem and Telem:IsA('RemoteEvent') then
                            track(Telem.OnClientEvent:Connect(function(...)
                                local args = { ... }
                                pcall(function()
                                    state.telemStreaming = true
                                    state.lastConfirm = tick()
                                    state.specActiveAttr = AdminRemotes:GetAttribute('SpecActive') == true
                                    if state.specActiveAttr then
                                        confirm(state.spectator, 'Telem stream')
                                    end
                                end)
                            end))
                            namecallUnhook = function() end
                        end

                        task.spawn(function()
                            while panel and panel.Parent do
                                local attr = AdminRemotes:GetAttribute('SpecActive') == true
                                state.specActiveAttr = attr

                                if attr then
                                    local ghostAdmin = nil
                                    for _, admin in ipairs(listAdmins()) do
                                        if adminLooksGhosted(admin) then
                                            ghostAdmin = admin
                                            break
                                        end
                                    end
                                    if ghostAdmin then
                                        confirm(ghostAdmin, 'admin ghosted')
                                    elseif not state.active then
                                        setActive(true, nil, 'SpecActive')
                                    else
                                        state.lastConfirm = tick()
                                    end
                                end

                                if state.active and not attr and not state.remoteHit then
                                    if tick() - state.lastConfirm > 4.5 then
                                        setActive(false, nil, 'timeout')
                                    end
                                elseif state.active and not attr and state.remoteHit then
                                    if tick() - state.lastConfirm > 4.5 then
                                        setActive(false, nil, 'timeout')
                                    end
                                end

                                if not attr then
                                    state.telemStreaming = false
                                end

                                refreshUi()
                                task.wait(0.35)
                            end
                        end)

                        Library:OnUnload(function()
                            pcall(function()
                                if okAttrConn and okAttrConn.Disconnect then okAttrConn:Disconnect() end
                                for _, c in ipairs(connections) do
                                    pcall(function()
                                        if c and c.Disconnect then c:Disconnect() end
                                    end)
                                end
                                if namecallUnhook then pcall(namecallUnhook) end
                                if spectatorGui and spectatorGui.Parent then spectatorGui:Destroy() end
                            end)
                        end)
                    end)
                end

                local function ensureDetectorRunning()
                    if State.SpectatorListEnabled.Value == true or State.PanicMode.Value == true then
                        startSpectatorDetector()
                    end
                end

                attachChangeListener(State.SpectatorListEnabled, function()
                    local enabled = State.SpectatorListEnabled.Value == true
                    panel.Visible = enabled
                    ensureDetectorRunning()
                end)
                attachChangeListener(State.PanicMode, function()
                    ensureDetectorRunning()
                    syncPanicSuppress()
                end)
                panel.Visible = State.SpectatorListEnabled.Value == true
                ensureDetectorRunning()

                refreshUi()
                syncPanicSuppress()

                Library:OnUnload(function()
                    pcall(function()
                        panicSpectating = false
                        syncPanicSuppress()
                        if spectatorGui and spectatorGui.Parent then
                            spectatorGui:Destroy()
                        end
                    end)
                end)
            end
        end

        -- Section 4: Theming
        local secTheme = createSection(settingsHost, 'Theming')

        createColorRow(secTheme, 'Accent', Options.ThemeAccent)
        if Options.ThemeAccent then
            attachChangeListener(Options.ThemeAccent, function(newCol)
                if isApplyingPreset then return end
                if Options.ThemePreset and Options.ThemePreset.Value ~= 'Custom' then
                    Options.ThemePreset:SetValue('Custom')
                end
                if State.ThemePreset and State.ThemePreset.Value ~= 'Custom' then
                    State.ThemePreset:SetValue('Custom')
                end
                local col = (typeof(newCol) == 'Color3' and newCol) or (Options.ThemeAccent and typeof(Options.ThemeAccent.Value) == 'Color3' and Options.ThemeAccent.Value)
                if col then
                    palette.accent = col
                    palette.accentBar = col
                end
                applyTheme()
                if type(updateAccentGradients) == 'function' then
                    updateAccentGradients()
                end
                requestSaveConfig()
            end)
        end

        createCoincideDropdown(secTheme, 'Theme Preset', State.ThemePreset, themePresetNames, function(presetName)
            if isApplyingPreset then return end
            if presetName and presetName ~= 'Custom' then
                applyThemePreset(presetName)
            end
        end)

        local themeGroups = {
            {
                title = 'Surfaces',
                rows = {
                    { 'ThemeBg', 'Background' },
                    { 'ThemeSurface', 'Panel' },
                    { 'ThemeSurfaceSoft', 'Cards' },
                    { 'ThemeSurfaceElevated', 'Rows' },
                    { 'ThemeGlass', 'Glass' },
                    { 'ThemeShadow', 'Shadow' },
                },
            },
            {
                title = 'Accent Details',
                rows = {
                    { 'ThemeAccentSoft', 'Accent Soft' },
                    { 'ThemeAccentWarm', 'Accent Warm' },
                    { 'ThemeAccentBar', 'Tab & Section Bars' },
                },
            },
            {
                title = 'Text',
                rows = {
                    { 'ThemeText', 'Text' },
                    { 'ThemeTextDim', 'Muted Text' },
                    { 'ThemeSuccess', 'Success' },
                    { 'ThemeDanger', 'Danger' },
                },
            },
            {
                title = 'Borders',
                rows = {
                    { 'ThemeStroke', 'Border' },
                    { 'ThemeStrokeSoft', 'Border Soft' },
                },
            },
        }

        local function createCollapsibleThemeGroup(parent, title, count)
            local wrap = Instance.new('Frame')
            wrap.Name = 'Group_' .. tostring(title)
            wrap.BackgroundTransparency = 1
            wrap.BorderSizePixel = 0
            wrap.Size = UDim2.new(1, 0, 0, 0)
            wrap.AutomaticSize = Enum.AutomaticSize.Y
            wrap.Parent = parent

            local groupLayout = Instance.new('UIListLayout')
            groupLayout.FillDirection = Enum.FillDirection.Vertical
            groupLayout.Padding = UDim.new(0, 4)
            groupLayout.Parent = wrap

            local headerBtn = Instance.new('TextButton')
            headerBtn.Name = 'Header'
            headerBtn.Size = UDim2.new(1, 0, 0, 21)
            headerBtn.BackgroundColor3 = Color3.fromHex('000000')
            headerBtn.BorderSizePixel = 0
            headerBtn.AutoButtonColor = false
            headerBtn.Text = ''
            headerBtn.Parent = wrap

            local hGray = Instance.new('Frame')
            hGray.Position = UDim2.new(0, 1, 0, 1)
            hGray.Size = UDim2.new(1, -2, 1, -2)
            hGray.BackgroundColor3 = Color3.fromHex('393939')
            hGray.BorderSizePixel = 0
            hGray.Parent = headerBtn

            local hInside = Instance.new('Frame')
            hInside.Position = UDim2.new(0, 1, 0, 1)
            hInside.Size = UDim2.new(1, -2, 1, -2)
            hInside.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            hInside.BorderSizePixel = 0
            hInside.Parent = hGray

            local hGrad = Instance.new('UIGradient')
            hGrad.Rotation = 90
            hGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
            })
            hGrad.Parent = hInside

            local titleLbl = Instance.new('TextLabel')
            titleLbl.Position = UDim2.new(0, 8, 0, 0)
            titleLbl.Size = UDim2.new(1, -30, 1, 0)
            titleLbl.BackgroundTransparency = 1
            titleLbl.BorderSizePixel = 0
            titleLbl.TextColor3 = Color3.fromHex('D0D0D0')
            titleLbl.TextSize = 11
            titleLbl.Font = Enum.Font.GothamSemibold
            titleLbl.TextXAlignment = Enum.TextXAlignment.Left
            titleLbl.TextYAlignment = Enum.TextYAlignment.Center
            titleLbl.Text = string.format('%s (%d)', title, count or 0)
            titleLbl.Parent = hInside

            local chevLbl = Instance.new('TextLabel')
            chevLbl.AnchorPoint = Vector2.new(1, 0)
            chevLbl.Position = UDim2.new(1, -6, 0, 0)
            chevLbl.Size = UDim2.new(0, 16, 1, 0)
            chevLbl.BackgroundTransparency = 1
            chevLbl.BorderSizePixel = 0
            chevLbl.TextColor3 = Color3.fromHex('8C8F99')
            chevLbl.TextSize = 10
            chevLbl.Font = Enum.Font.Gotham
            chevLbl.Text = '>'
            chevLbl.TextXAlignment = Enum.TextXAlignment.Center
            chevLbl.TextYAlignment = Enum.TextYAlignment.Center
            chevLbl.Parent = hInside

            local body = Instance.new('Frame')
            body.Name = 'Body'
            body.BackgroundTransparency = 1
            body.BorderSizePixel = 0
            body.Size = UDim2.new(1, 0, 0, 0)
            body.AutomaticSize = Enum.AutomaticSize.Y
            body.Visible = false
            body.Parent = wrap

            local bodyLayout = Instance.new('UIListLayout')
            bodyLayout.FillDirection = Enum.FillDirection.Vertical
            bodyLayout.Padding = UDim.new(0, 4)
            bodyLayout.Parent = body

            local isExpanded = false
            local function toggleExpand()
                isExpanded = not isExpanded
                body.Visible = isExpanded
                chevLbl.Text = isExpanded and 'v' or '>'
                titleLbl.TextColor3 = isExpanded and Color3.fromHex('FFFFFF') or Color3.fromHex('D0D0D0')
            end

            safeConnect(headerBtn.MouseButton1Click, toggleExpand)

            safeConnect(headerBtn.MouseEnter, function()
                hGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('262626')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
                })
            end)
            safeConnect(headerBtn.MouseLeave, function()
                hGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('1B1B1B')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('121212')),
                })
            end)

            return body
        end

        for _, group in ipairs(themeGroups) do
            local groupBody = createCollapsibleThemeGroup(secTheme, group.title, #group.rows)
            for _, row in ipairs(group.rows) do
                local optionId, label = row[1], row[2]
                createColorRow(groupBody, label, Options[optionId])
                attachChangeListener(Options[optionId], function()
                    if isApplyingPreset then return end
                    if Options.ThemePreset and Options.ThemePreset.Value ~= 'Custom' then
                        Options.ThemePreset:SetValue('Custom')
                    end
                    if State.ThemePreset and State.ThemePreset.Value ~= 'Custom' then
                        State.ThemePreset:SetValue('Custom')
                    end
                    applyTheme()
                    requestSaveConfig()
                end)
            end
        end

        createCoincideButton(secTheme, 'Reset Theme Colors', function()
            applyThemePreset('Default')
        end)

        syncSettingsPosition()
    end)()

    -- ?????? ??????
    ;(function(AimLock, safeConnect, Library, isSharedTargetRole, isSharedFriendRole, Toggles, Options)
        -- pSilent from 123.lua Aim FOV (GunModule.getAim redirect), keeps Enable / FOV / Keybind / FOV circle
        local Players = game:GetService('Players')
        local ReplicatedStorage = game:GetService('ReplicatedStorage')
        local RunService = game:GetService('RunService')
        local UserInputService = game:GetService('UserInputService')
        local Workspace = game:GetService('Workspace')
        local LocalPlayer = Players.LocalPlayer

        local originalRanges = {}
        local oldGetAim = nil
        local hooked = false
        local packFireHooked = false
        local camera = Workspace.CurrentCamera
        local lastSilentTarget = nil
        local lastSilentHrp = nil
        local lastSilentPlayer = nil
        local lastResolveClock = 0
        local lockedPlayer = nil
        local lockClock = 0
        local nextAcquireAt = 0
        -- After KO/invalid lock: short acquire CD only (Target Switch Delay).
        -- Do NOT gate on LMB hold � that blocked locking the next player who
        -- walks into FOV while still spraying.
        local bypassShotsLeft = 0
        local pendingSkip = nil -- nil | true | false; cleared by packFire

        -- Revolver: when target horiz speed > 55 (macro-tier), aim at a delayed model position.
        local SPEED_LAG_THRESHOLD = 55
        local SPEED_LAG_HISTORY_SEC = 0.22
        local SPEED_LAG_MAX_SAMPLES = 12
        local lagPosHistory = {} -- [Player] = { { t, pos }, ... }

        local function clearLagHistory(plr)
            if plr then
                lagPosHistory[plr] = nil
            else
                lagPosHistory = {}
            end
        end

        local function pushLagSample(plr, pos)
            if not plr or typeof(pos) ~= 'Vector3' then
                return
            end
            local now = os.clock()
            local hist = lagPosHistory[plr]
            if not hist then
                hist = {}
                lagPosHistory[plr] = hist
            end
            hist[#hist + 1] = { t = now, pos = pos }
            local cutoff = now - SPEED_LAG_HISTORY_SEC
            while #hist > 0 and (hist[1].t < cutoff or #hist > SPEED_LAG_MAX_SAMPLES) do
                table.remove(hist, 1)
            end
        end

        local function getDelayedAimPos(plr, lookbackSec)
            local hist = lagPosHistory[plr]
            if not hist or #hist == 0 then
                return nil
            end
            local targetT = os.clock() - math.max(0, tonumber(lookbackSec) or 0)
            local prev = hist[1]
            for i = 1, #hist do
                local s = hist[i]
                if s.t <= targetT then
                    prev = s
                else
                    if prev and prev.t < s.t then
                        local alpha = (targetT - prev.t) / (s.t - prev.t)
                        return prev.pos:Lerp(s.pos, math.clamp(alpha, 0, 1))
                    end
                    return prev.pos
                end
            end
            return prev and prev.pos or nil
        end

        local function applySpeedLagAim(aimPos, plr, weaponName)
            if typeof(aimPos) ~= 'Vector3' or not plr then
                return aimPos
            end
            pushLagSample(plr, aimPos)
            if weaponName ~= '[Revolver]' then
                return aimPos
            end
            local char = plr.Character
            local hrp = char and char:FindFirstChild('HumanoidRootPart')
            if not hrp or not hrp:IsA('BasePart') then
                return aimPos
            end
            local vel = hrp.AssemblyLinearVelocity
            local horiz = Vector3.new(vel.X, 0, vel.Z)
            local speed = horiz.Magnitude
            if speed <= SPEED_LAG_THRESHOLD then
                return aimPos
            end
            -- Milder lookback only for macro-tier speeds (clamp ~50�150ms).
            local excess = speed - SPEED_LAG_THRESHOLD
            local lookback = math.clamp(0.05 + excess * 0.001, 0.05, 0.15)
            local hist = lagPosHistory[plr]
            local histSpan = (hist and #hist >= 2) and (os.clock() - hist[1].t) or 0
            if histSpan >= lookback * 0.5 then
                local delayed = getDelayedAimPos(plr, lookback)
                if delayed then
                    return delayed
                end
            end
            return aimPos - horiz * lookback
        end

        local function isKeybindActive(bindOption)
            if not bindOption then return false end
            local ok, state = pcall(function()
                if type(bindOption.GetState) == 'function' then
                    return bindOption:GetState()
                end
                return nil
            end)
            if ok and state ~= nil then return state == true end

            local keyVal = bindOption.Value
            if type(keyVal) == 'table' then
                local mode = keyVal.Mode or keyVal[2]
                if type(mode) == 'string' and string.lower(mode) == 'always' then
                    return true
                end
                keyVal = keyVal.Key or keyVal[1]
            end

            local function isPressed(raw)
                if typeof(raw) == 'EnumItem' then
                    if raw.EnumType == Enum.KeyCode then
                        local ok2, down = pcall(function() return UserInputService:IsKeyDown(raw) end)
                        return ok2 and down
                    end
                    if raw.EnumType == Enum.UserInputType then
                        local ok2, down = pcall(function() return UserInputService:IsMouseButtonPressed(raw) end)
                        return ok2 and down
                    end
                end
                if type(raw) == 'string' then
                    local kc = Enum.KeyCode[raw]
                    if kc then
                        local ok2, down = pcall(function() return UserInputService:IsKeyDown(kc) end)
                        return ok2 and down
                    end
                    local ui = Enum.UserInputType[raw]
                    if ui then
                        local ok2, down = pcall(function() return UserInputService:IsMouseButtonPressed(ui) end)
                        return ok2 and down
                    end
                end
                return false
            end

            return isPressed(keyVal)
        end

        local function IsAimKeyActive()
            return isKeybindActive(AimLock.Key)
        end

        local function isSilentAutoShotActive()
            if AimLock.Enabled.Value ~= true then return false end
            if not (AimLock.AutoShot and AimLock.AutoShot.Value == true) then return false end
            return isKeybindActive(AimLock.AutoShotKey)
        end

        local function isAimFovActive()
            if AimLock.Enabled.Value ~= true then return false end
            return IsAimKeyActive() or isSilentAutoShotActive()
        end

        local function getEquippedWeaponName()
            local char = LocalPlayer and LocalPlayer.Character
            if not char then return nil end
            local tool = char:FindFirstChildOfClass('Tool')
            return tool and tool.Name or nil
        end

        local function getSilentMissBudget(toolName)
            if toolName == '[Revolver]' then
                local shots = tonumber(AimLock.MissRevolverShots and AimLock.MissRevolverShots.Value) or 3
                return math.clamp(math.floor(shots), 1, 6)
            end
            local shots = tonumber(AimLock.MissShotgunShots and AimLock.MissShotgunShots.Value) or 1
            return math.clamp(math.floor(shots), 1, 3)
        end

        -- Miss Chance: skip silent for N shots (not a timed disable).
        -- getAim may set pendingSkip; packFire consumes and clears it so Auto Fire
        -- shots after the miss streak always re-decide (no sticky 40ms skip).
        local function decideSkipSilentShot()
            if not (AimLock.MissEnabled and AimLock.MissEnabled.Value == true) then
                bypassShotsLeft = 0
                return false
            end
            local chance = math.clamp(tonumber(AimLock.MissPercent and AimLock.MissPercent.Value) or 0, 0, 100)
            if chance <= 0 then
                bypassShotsLeft = 0
                return false
            end
            if bypassShotsLeft > 0 then
                bypassShotsLeft = bypassShotsLeft - 1
                return true
            end
            if math.random(1, 100) <= chance then
                local budget = getSilentMissBudget(getEquippedWeaponName())
                bypassShotsLeft = math.max(0, budget - 1)
                return true
            end
            return false
        end

        -- Used by getAim: reuse pending decision for the same shot if packFire not yet run.
        local function peekSkipSilentThisShot()
            if pendingSkip == nil then
                pendingSkip = decideSkipSilentShot()
            end
            return pendingSkip == true
        end

        -- Used by packFire: take pending from getAim or decide; always clear pending.
        local function consumeSkipSilentThisShot()
            local skip
            if pendingSkip ~= nil then
                skip = pendingSkip == true
                pendingSkip = nil
            else
                skip = decideSkipSilentShot()
            end
            return skip
        end

        local BODY_PART_ALIASES = {
            Head = { 'Head' },
            HumanoidRootPart = { 'HumanoidRootPart' },
            UpperTorso = { 'UpperTorso', 'Torso' },
            LowerTorso = { 'LowerTorso', 'Torso' },
            ['Left Arm'] = { 'LeftUpperArm', 'LeftLowerArm', 'LeftHand', 'Left Arm' },
            ['Right Arm'] = { 'RightUpperArm', 'RightLowerArm', 'RightHand', 'Right Arm' },
            ['Left Leg'] = { 'LeftUpperLeg', 'LeftLowerLeg', 'LeftFoot', 'Left Leg' },
            ['Right Leg'] = { 'RightUpperLeg', 'RightLowerLeg', 'RightFoot', 'Right Leg' },
        }

        local function resolveBodyPart(char, partName)
            if not char then
                return nil
            end
            local aliases = BODY_PART_ALIASES[tostring(partName or 'Head')] or { 'Head', 'HumanoidRootPart' }
            for _, name in ipairs(aliases) do
                local part = char:FindFirstChild(name)
                if part and part:IsA('BasePart') then
                    return part
                end
            end
            return char:FindFirstChild('Head') or char:FindFirstChild('HumanoidRootPart')
        end

        local function mouseWorldRay()
            camera = Workspace.CurrentCamera or camera
            if not camera then
                return nil, nil
            end
            local mouse = UserInputService:GetMouseLocation()
            local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
            return ray.Origin, ray.Direction.Unit
        end

        -- Closest point on oriented box (part.CFrame + part.Size) to a world point.
        local function closestPointOnPartOBB(part, worldPoint)
            if not part or typeof(worldPoint) ~= 'Vector3' then
                return nil
            end
            local cf = part.CFrame
            local half = part.Size * 0.5
            local localPoint = cf:PointToObjectSpace(worldPoint)
            local clamped = Vector3.new(
                math.clamp(localPoint.X, -half.X, half.X),
                math.clamp(localPoint.Y, -half.Y, half.Y),
                math.clamp(localPoint.Z, -half.Z, half.Z)
            )
            return cf:PointToWorldSpace(clamped)
        end

        -- Closest point on part OBB to an infinite ray (origin + t*dir, t>=0).
        local function closestPointOnPartToRay(part, rayOrigin, rayDir)
            if not part or typeof(rayOrigin) ~= 'Vector3' or typeof(rayDir) ~= 'Vector3' then
                return nil
            end
            local dir = rayDir.Unit
            -- Seed with closest point to a point along the ray near the part.
            local toPart = part.Position - rayOrigin
            local t = math.max(0, toPart:Dot(dir))
            local seed = rayOrigin + dir * t
            local onBox = closestPointOnPartOBB(part, seed)
            if not onBox then
                return nil
            end
            -- One refinement: project box point onto ray, clamp, reclamp onto box.
            local t2 = math.max(0, (onBox - rayOrigin):Dot(dir))
            local onRay = rayOrigin + dir * t2
            return closestPointOnPartOBB(part, onRay) or onBox
        end

        -- Screen-aligned jitter around basePoint, clamped back into the part OBB.
        -- Slider 0�100: 100% = full half-extent reach on camera right/up.
        local function jitterPointInsideOBB(part, basePoint, jitterPct)
            if not part or typeof(basePoint) ~= 'Vector3' then
                return basePoint
            end
            local slider = math.clamp(tonumber(jitterPct) or 0, 0, 100)
            local base = closestPointOnPartOBB(part, basePoint) or basePoint
            if slider <= 0 then
                return base
            end
            local amp = slider / 100
            local half = part.Size * 0.5
            local reach = amp * math.max(half.X, half.Y, half.Z)
            camera = Workspace.CurrentCamera or camera
            local right = Vector3.new(1, 0, 0)
            local up = Vector3.new(0, 1, 0)
            local look = Vector3.new(0, 0, -1)
            if camera then
                right = camera.CFrame.RightVector
                up = camera.CFrame.UpVector
                look = camera.CFrame.LookVector
            end
            local ox = (math.random() * 2 - 1) * reach
            local oy = (math.random() * 2 - 1) * reach
            local oz = (math.random() * 2 - 1) * reach * 0.35
            local candidate = base + right * ox + up * oy + look * oz
            return closestPointOnPartOBB(part, candidate) or base
        end

        local function isAimPointVisible(origin, aimPos, plr)
            if typeof(origin) ~= 'Vector3' or typeof(aimPos) ~= 'Vector3' or not plr then
                return false
            end
            local toTarget = aimPos - origin
            if toTarget.Magnitude < 1e-4 then
                return true
            end

            camera = Workspace.CurrentCamera or camera
            local camPos = camera and camera.CFrame.Position
            local localChar = LocalPlayer.Character
            local headPos = localChar and localChar:FindFirstChild('Head') and localChar.Head.Position

            local ignore = {}
            if localChar then
                ignore[#ignore + 1] = localChar
            end
            local ghostFolder = Workspace:FindFirstChild('BacktrackGhosts')
            if ghostFolder then
                ignore[#ignore + 1] = ghostFolder
            end

            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            params.FilterDescendantsInstances = ignore

            local function checkRay(startPos, endPos)
                local dir = endPos - startPos
                if dir.Magnitude < 1e-4 then
                    return true
                end
                local result = Workspace:Raycast(startPos, dir, params)
                if not result or not result.Instance then
                    return true
                end
                local hit = result.Instance
                local char = plr.Character
                local playersFolder = Workspace:FindFirstChild('Players')
                local wsChar = playersFolder and playersFolder:FindFirstChild(plr.Name)
                if char and hit:IsDescendantOf(char) then
                    return true
                end
                if wsChar and hit:IsDescendantOf(wsChar) then
                    return true
                end
                return false
            end

            -- 1. Check weapon origin
            if not checkRay(origin, aimPos) then
                return false
            end
            -- 2. Check camera origin
            if camPos and (camPos - origin).Magnitude > 0.5 then
                if not checkRay(camPos, aimPos) then
                    return false
                end
            end
            -- 3. Check character head origin
            if headPos and (headPos - origin).Magnitude > 0.5 then
                if not checkRay(headPos, aimPos) then
                    return false
                end
            end

            return true
        end

        local function isSilentTargetAlive(plr)
            if not plr or plr == LocalPlayer then
                return false
            end
            if isSharedFriendRole(plr) then
                return false
            end
            if AimLock.TargetOnly and AimLock.TargetOnly.Value == true and not isSharedTargetRole(plr) then
                return false
            end
            if IsPlayerKO(plr) then
                return false
            end
            local char = plr.Character
            if not char then
                return false
            end
            local hum = char:FindFirstChildOfClass('Humanoid')
            if hum and (hum.Health or 0) <= 0 then
                return false
            end
            return true
        end

        local function clearSilentCache()
            lastSilentTarget = nil
            lastSilentHrp = nil
            lastSilentPlayer = nil
            lockedPlayer = nil
            lockClock = 0
            nextAcquireAt = 0
        end

        safeConnect(Players.PlayerRemoving, function(plr)
            clearLagHistory(plr)
        end)

        local function degreesToScreenRadius(fovDeg)
            camera = Workspace.CurrentCamera or camera
            if not camera then
                return 0
            end
            local fov = math.clamp(tonumber(fovDeg) or 5, 0.1, 179)
            local vpY = camera.ViewportSize and camera.ViewportSize.Y
            if not vpY or vpY <= 0 then vpY = 600 end
            local halfScreen = vpY * 0.5
            local camFov = math.rad(math.max(camera.FieldOfView or 70, 1))
            local r = math.tan(math.rad(fov) * 0.5) / math.tan(camFov * 0.5) * halfScreen
            if r ~= r or r <= 0 then
                return (tonumber(fovDeg) or 30) * 4
            end
            return r
        end

        -- Screen-space FOV gate matching the drawn FOV circle around the crosshair.
        local function screenFovDist(aimPos, crosshair, fovPx)
            camera = Workspace.CurrentCamera or camera
            if not camera or typeof(aimPos) ~= 'Vector3' then
                return nil, false
            end
            local screenPos, onScreen = camera:WorldToViewportPoint(aimPos)
            if (not onScreen) or screenPos.Z <= 0 then
                return nil, false
            end
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - crosshair).Magnitude
            if dist > fovPx then
                return dist, false
            end
            return dist, true
        end

        -- relaxed=true: alive + range only (no FOV/wall reject) � sticky lock must not blank shots.
        local function buildAimForPlayer(plr, origin, fov, relaxed)
            camera = Workspace.CurrentCamera or camera
            if not camera or typeof(origin) ~= 'Vector3' or not plr then
                return nil, nil
            end
            if not isSilentTargetAlive(plr) then
                return nil, nil
            end
            local char = plr.Character
            if not char then
                return nil, nil
            end
            local weaponName = getEquippedWeaponName()
            local maxDist = (weaponName and originalRanges[weaponName]) or 200
            local crosshair = UserInputService:GetMouseLocation()
            local aimMode = tostring(AimLock.AimMode and AimLock.AimMode.Value or 'Body Part')
            local bodyPartName = tostring(AimLock.BodyPart and AimLock.BodyPart.Value or 'Head')
            local jitterPct = tonumber(AimLock.HitboxJitter and AimLock.HitboxJitter.Value) or 25
            local fovPx = degreesToScreenRadius(fov)
            local rayOrigin, rayDir = mouseWorldRay()

            local scorePos = nil
            local aimHrp = nil
            local aimPart = nil
            if aimMode == 'Closest Hitbox' then
                local hrp = char:FindFirstChild('HumanoidRootPart')
                if not hrp or not hrp:IsA('BasePart') then
                    return nil, nil
                end
                aimHrp = hrp
                aimPart = hrp
                -- Score FOV against closest OBB point to crosshair ray (not HRP center).
                scorePos = hrp.Position
                if rayOrigin and rayDir then
                    scorePos = closestPointOnPartToRay(hrp, rayOrigin, rayDir) or scorePos
                end
            else
                local part = resolveBodyPart(char, bodyPartName)
                if not part then
                    return nil, nil
                end
                aimPart = part
                scorePos = part.Position
            end

            if (scorePos - origin).Magnitude > maxDist then
                return nil, nil
            end

            if not isAimPointVisible(origin, scorePos, plr) then
                return nil, nil
            end
            if not relaxed then
                local _, inFov = screenFovDist(scorePos, crosshair, fovPx)
                if not inFov then
                    return nil, nil
                end
            end

            local aimPos = scorePos
            if aimMode == 'Closest Hitbox' and aimHrp then
                local closest = scorePos
                if rayOrigin and rayDir then
                    closest = closestPointOnPartToRay(aimHrp, rayOrigin, rayDir) or closest
                end
                closest = closest or closestPointOnPartOBB(aimHrp, aimHrp.Position) or aimHrp.Position
                local jittered = jitterPointInsideOBB(aimHrp, closest, jitterPct)
                local _, jitterInFov = screenFovDist(jittered, crosshair, fovPx)
                if jitterInFov and isAimPointVisible(origin, jittered, plr) then
                    aimPos = jittered
                elseif isAimPointVisible(origin, closest, plr) then
                    local _, closestInFov = screenFovDist(closest, crosshair, fovPx)
                    aimPos = closestInFov and closest or scorePos
                else
                    aimPos = scorePos
                end
            elseif aimPart then
                aimPos = aimPart.Position
            end

            if not isAimPointVisible(origin, aimPos, plr) then
                if isAimPointVisible(origin, scorePos, plr) then
                    aimPos = scorePos
                else
                    return nil, nil
                end
            end

            local lagAim = applySpeedLagAim(aimPos, plr, weaponName)
            if lagAim and isAimPointVisible(origin, lagAim, plr) then
                aimPos = lagAim
            end

            if not isAimPointVisible(origin, aimPos, plr) then
                return nil, nil
            end
            return aimPos, aimHrp
        end

        local CANDIDATE_PARTS = {
            'Head',
            'UpperTorso',
            'Torso',
            'HumanoidRootPart',
            'LowerTorso',
            'RightUpperArm',
            'LeftUpperArm',
            'Right Arm',
            'Left Arm',
            'RightUpperLeg',
            'LeftUpperLeg',
            'Right Leg',
            'Left Leg',
        }

        local function findTarget(origin, fov)
            -- Pick the player whose visible hitbox/point is physically closest to the crosshair in 2D screen space
            local bestScreenDist, bestPlr = math.huge, nil
            camera = Workspace.CurrentCamera or camera
            if not camera or typeof(origin) ~= 'Vector3' then
                return nil, nil, nil
            end
            local weaponName = getEquippedWeaponName()
            local maxDist = (weaponName and originalRanges[weaponName]) or 200
            local crosshair = UserInputService:GetMouseLocation()
            local aimMode = tostring(AimLock.AimMode and AimLock.AimMode.Value or 'Body Part')
            local bodyPartName = tostring(AimLock.BodyPart and AimLock.BodyPart.Value or 'Head')
            local fovPx = degreesToScreenRadius(fov)
            local rayOrigin, rayDir = mouseWorldRay()

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr == LocalPlayer then
                    continue
                end
                if not isSilentTargetAlive(plr) then
                    continue
                end
                local char = plr.Character
                if not char then
                    continue
                end

                local plrBestDist = math.huge

                if aimMode == 'Closest Hitbox' then
                    for _, pName in ipairs(CANDIDATE_PARTS) do
                        local part = char:FindFirstChild(pName)
                        if part and part:IsA('BasePart') then
                            local pt = part.Position
                            if rayOrigin and rayDir then
                                pt = closestPointOnPartToRay(part, rayOrigin, rayDir) or pt
                            end
                            if (pt - origin).Magnitude <= maxDist then
                                local screenDist, inFov = screenFovDist(pt, crosshair, fovPx)
                                if inFov and screenDist and screenDist < plrBestDist then
                                    if isAimPointVisible(origin, pt, plr) then
                                        plrBestDist = screenDist
                                    end
                                end
                            end
                        end
                    end
                else
                    local part = resolveBodyPart(char, bodyPartName)
                    if part and part:IsA('BasePart') then
                        local pt = part.Position
                        if (pt - origin).Magnitude <= maxDist then
                            local screenDist, inFov = screenFovDist(pt, crosshair, fovPx)
                            if inFov and screenDist and isAimPointVisible(origin, pt, plr) then
                                plrBestDist = screenDist
                            end
                        end
                    end
                end

                if plrBestDist < bestScreenDist then
                    bestScreenDist = plrBestDist
                    bestPlr = plr
                end
            end

            if not bestPlr then
                return nil, nil, nil
            end
            local aimPos, aimHrp = buildAimForPlayer(bestPlr, origin, fov, false)
            if not aimPos then
                return nil, nil, nil
            end
            return aimPos, aimHrp, bestPlr
        end

        local function resolveSilentTarget(origin)
            if not isAimFovActive() then
                clearSilentCache()
                if BacktrackApi and type(BacktrackApi.clearPending) == 'function' then
                    BacktrackApi.clearPending()
                end
                return nil
            end
            -- Dedup getAim + packFire in the same shot (one jitter sample). Never cache a miss or occluded target.
            local now = os.clock()
            if lastSilentTarget and (now - lastResolveClock) < 0.04 then
                if isAimPointVisible(origin, lastSilentTarget, lastSilentPlayer) then
                    return lastSilentTarget
                else
                    clearSilentCache()
                end
            end
            local fov = tonumber(AimLock.FOV.Value) or 5
            local fovPx = degreesToScreenRadius(fov)
            local crosshair = UserInputService:GetMouseLocation()

            -- 1. Find live player closest to crosshair inside FOV circle
            local closestAim, closestHrp, closestPlr = findTarget(origin, fov)
            local closestDist = math.huge
            if closestAim then
                local d = screenFovDist(closestAim, crosshair, fovPx)
                if d then
                    closestDist = d
                end
            end

            -- 2. Check Backtrack ghost (only if visible and closer than live target)
            local ghostAim, ghostHrp, ghostPlr = nil, nil, nil
            pcall(function()
                if not (BacktrackApi and BacktrackApi.isActive and BacktrackApi.isActive()) then
                    return
                end
                if not (BacktrackApi.peekUseGhost and BacktrackApi.peekUseGhost()) then
                    return
                end
                if type(BacktrackApi.pickGhostInFov) ~= 'function' then
                    return
                end
                local function inFov(pos)
                    return screenFovDist(pos, crosshair, fovPx)
                end
                local gAim, gHrp, gPlr = BacktrackApi.pickGhostInFov(origin, inFov)
                if gAim and gPlr and isAimPointVisible(origin, gAim, gPlr) then
                    local gDist = screenFovDist(gAim, crosshair, fovPx)
                    if gDist and (not closestAim or gDist < closestDist) then
                        ghostAim, ghostHrp, ghostPlr = gAim, gHrp, gPlr
                    end
                end
            end)

            if ghostAim and ghostPlr then
                lockedPlayer = ghostPlr
                lockClock = now
                nextAcquireAt = 0
                lastSilentTarget = ghostAim
                lastSilentHrp = ghostHrp
                lastSilentPlayer = ghostPlr
                lastResolveClock = now
                return ghostAim
            end

            if closestAim and closestPlr then
                lockedPlayer = closestPlr
                lockClock = now
                nextAcquireAt = 0
                lastSilentTarget = closestAim
                lastSilentHrp = closestHrp
                lastSilentPlayer = closestPlr
                lastResolveClock = now
                return closestAim
            end

            clearSilentCache()
            return nil
        end

        -- Boom Hood shotgun LocalScript (RandomBulletOffsets path, default):
        --   ends[i] = muzzle + aimDir * 5 - pattern[i]
        -- Offsets live near the muzzle (~5 studs), not at the far target. Translating
        -- ends to the silent hit point collapses angular spread � rebuild/retarget instead.
        local SHOTGUN_NEAR_AIM_DIST = 5
        local silentGunConfig = nil
        local shotgunPatternCache = {} -- [weaponName] = RandomBulletOffsets table

        local function ensureSilentGunConfig()
            if silentGunConfig then
                return silentGunConfig
            end
            local ok, cfg = pcall(function()
                local Modules = ReplicatedStorage:FindFirstChild('Modules')
                local GunModuleInst = Modules and Modules:FindFirstChild('GunModule')
                local ConfigInst = GunModuleInst and GunModuleInst:FindFirstChild('Config')
                return ConfigInst and require(ConfigInst)
            end)
            if ok and type(cfg) == 'table' then
                silentGunConfig = cfg
            end
            return silentGunConfig
        end

        local function getEquippedGunName()
            local char = LocalPlayer and LocalPlayer.Character
            local tool = char and char:FindFirstChildOfClass('Tool')
            return tool and tool.Name or nil
        end

        local function pickShotgunPattern(weaponName, pelletCount)
            local cfg = ensureSilentGunConfig()
            local weapon = cfg and weaponName and cfg[weaponName]
            local patterns = weapon and weapon.RandomBulletOffsets
            if type(patterns) ~= 'table' or #patterns < 1 then
                patterns = shotgunPatternCache[weaponName]
            else
                shotgunPatternCache[weaponName] = patterns
            end
            if type(patterns) ~= 'table' or #patterns < 1 then
                return nil
            end
            local pattern = patterns[math.random(1, #patterns)]
            if type(pattern) ~= 'table' or #pattern < pelletCount then
                return nil
            end
            return pattern
        end

        local COLLAPSE_EPS = 0.05

        local function vectorsAreCollapsed(vectors, count)
            if type(vectors) ~= 'table' or count < 2 then
                return false
            end
            local first = vectors[1]
            if typeof(first) ~= 'Vector3' then
                return true
            end
            for i = 2, count do
                local pe = vectors[i]
                if typeof(pe) ~= 'Vector3' then
                    return true
                end
                if (pe - first).Magnitude < COLLAPSE_EPS then
                    return true
                end
            end
            return false
        end

        local function endsAreCollapsed(ends, count)
            return vectorsAreCollapsed(ends, count)
        end

        local function pelletDirFromEnd(origin, endPos)
            if typeof(origin) ~= 'Vector3' or typeof(endPos) ~= 'Vector3' then
                return nil
            end
            local delta = endPos - origin
            if delta.Magnitude < 1e-4 then
                return nil
            end
            return delta.Unit
        end

        -- Project each near-muzzle end into a unique far hit along its pellet ray.
        local function hitAlongPellet(origin, endPos, refPoint)
            if typeof(refPoint) ~= 'Vector3' then
                return refPoint
            end
            local dir = pelletDirFromEnd(origin, endPos)
            if not dir then
                return refPoint
            end
            local dist = (refPoint - origin).Magnitude
            if dist < 1e-4 then
                return refPoint
            end
            return origin + dir * dist
        end

        local function buildSpreadVisualHits(origin, ends, hits, count, refPoint)
            if typeof(origin) ~= 'Vector3' or type(ends) ~= 'table' then
                return hits
            end
            local ref = refPoint
            if typeof(ref) ~= 'Vector3' and type(hits) == 'table' and typeof(hits[1]) == 'Vector3' then
                ref = hits[1]
            end
            if typeof(ref) ~= 'Vector3' then
                return hits
            end
            local out = {}
            for i = 1, count do
                if typeof(ends[i]) == 'Vector3' then
                    out[i] = hitAlongPellet(origin, ends[i], ref)
                elseif type(hits) == 'table' and typeof(hits[i]) == 'Vector3' then
                    out[i] = hits[i]
                end
            end
            return out
        end

        local function basisFromDir(dir)
            local up = math.abs(dir.Y) < 0.95 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
            local right = dir:Cross(up)
            if right.Magnitude < 1e-4 then
                right = dir:Cross(Vector3.new(0, 0, 1))
            end
            right = right.Unit
            local trueUp = right:Cross(dir).Unit
            return right, trueUp
        end

        -- Game formula: ends[i] = muzzle + aimDir * 5 - pattern[i]
        local function applyPatternEnds(origin, newDir, ends, count, pattern)
            if type(pattern) ~= 'table' then
                return false
            end
            local newCenter = origin + newDir * SHOTGUN_NEAR_AIM_DIST
            local wrote = 0
            for i = 1, count do
                local off = pattern[i]
                if typeof(off) == 'Vector3' then
                    ends[i] = newCenter - off
                    wrote = wrote + 1
                end
            end
            return wrote >= count and not endsAreCollapsed(ends, count)
        end

        -- Unique planar offsets so pellets never share one ray when config pattern is missing.
        local function applySyntheticEnds(origin, newDir, ends, count)
            local newCenter = origin + newDir * SHOTGUN_NEAR_AIM_DIST
            local right, up = basisFromDir(newDir)
            local radius = 0.55
            for i = 1, count do
                local angle = (i - 1) * (math.pi * 2 / count) + (i * 0.37)
                local r = radius * (0.65 + 0.35 * ((i - 1) % 3) / 2)
                local ox = math.cos(angle) * r
                local oy = math.sin(angle) * r
                ends[i] = newCenter - (right * ox + up * oy)
            end
            -- Guaranteed uniqueness: nudge any residual collision.
            if endsAreCollapsed(ends, count) then
                for i = 1, count do
                    ends[i] = newCenter - (right * (i * 0.22) + up * ((i % 2) * 0.18))
                end
            end
        end

        local function rebuildUniqueEnds(origin, newDir, ends, count)
            local pattern = pickShotgunPattern(getEquippedGunName(), count)
            if applyPatternEnds(origin, newDir, ends, count, pattern) then
                return
            end
            applySyntheticEnds(origin, newDir, ends, count)
        end

        local function redirectPackEnds(origin, bulletcount, ends, target)
            if typeof(origin) ~= 'Vector3' or typeof(target) ~= 'Vector3' then
                return
            end
            if type(ends) ~= 'table' then
                return
            end
            local count = math.max(1, math.floor(tonumber(bulletcount) or 1))
            local newDir = (target - origin)
            if newDir.Magnitude < 1e-4 then
                return
            end
            newDir = newDir.Unit

            if count <= 1 then
                ends[1] = target
                return
            end

            local anchor = ends[1]
            local anchorDist = typeof(anchor) == 'Vector3' and (anchor - origin).Magnitude or 0
            local inputCollapsed = endsAreCollapsed(ends, count)

            -- Preserve near-muzzle pattern only when input already has unique pellet ends.
            if (not inputCollapsed)
                and typeof(anchor) == 'Vector3'
                and anchorDist > 1.5
                and anchorDist < 12
            then
                local oldDir = (anchor - origin)
                if oldDir.Magnitude >= 1e-4 then
                    oldDir = oldDir.Unit
                    local oldCenter = origin + oldDir * SHOTGUN_NEAR_AIM_DIST
                    local newCenter = origin + newDir * SHOTGUN_NEAR_AIM_DIST
                    local ok = true
                    for i = 1, count do
                        local pe = ends[i]
                        if typeof(pe) ~= 'Vector3' then
                            ok = false
                            break
                        end
                        ends[i] = newCenter - (oldCenter - pe)
                    end
                    if ok and not endsAreCollapsed(ends, count) then
                        return
                    end
                end
            end

            -- Far non-collapsed pattern: rigid translate onto silent target.
            if (not inputCollapsed)
                and typeof(anchor) == 'Vector3'
                and anchorDist >= 12
            then
                local offset = target - anchor
                local ok = true
                for i = 1, count do
                    local pe = ends[i]
                    if typeof(pe) ~= 'Vector3' then
                        ok = false
                        break
                    end
                    ends[i] = pe + offset
                end
                if ok and not endsAreCollapsed(ends, count) then
                    return
                end
            end

            -- Always rebuild unique near-muzzle ends (pattern or synthetic). Never collapse.
            rebuildUniqueEnds(origin, newDir, ends, count)
        end

        local EFFECT_END_KEYS = { 'ends', 'Ends', 'EndPositions', 'endPositions', 'BulletEnds' }
        local EFFECT_HIT_KEYS = { 'hits', 'Hits', 'HitPositions', 'hitPositions', 'BulletHits' }
        local EFFECT_ORIGIN_KEYS = { 'origin', 'Origin', 'Muzzle', 'muzzle', 'Start', 'start' }
        local EFFECT_DIR_KEYS = { 'direction', 'Direction', 'aimDir', 'AimDir', 'dir', 'Dir' }
        local EFFECT_DIRS_KEYS = { 'directions', 'Directions', 'aimDirs', 'AimDirs', 'dirs', 'Dirs' }

        local function copyVector3Array(src, dst, count)
            if type(src) ~= 'table' or type(dst) ~= 'table' then
                return
            end
            local n = math.max(count or 0, #src)
            for i = 1, n do
                local v = src[i]
                if typeof(v) == 'Vector3' then
                    dst[i] = v
                end
            end
        end

        local function setEffectTableKey(effect, keys, value)
            if type(effect) ~= 'table' then
                return false
            end
            for _, key in ipairs(keys) do
                local slot = effect[key]
                if slot ~= nil then
                    if type(slot) == 'table' and type(value) == 'table' then
                        copyVector3Array(value, slot, #value)
                    else
                        effect[key] = value
                    end
                    return true
                end
            end
            return false
        end

        local function syncPelletDirections(effect, origin, ends, count)
            if type(effect) ~= 'table' or typeof(origin) ~= 'Vector3' or type(ends) ~= 'table' then
                return
            end
            local dirs = {}
            local wrote = 0
            for i = 1, count do
                local dir = pelletDirFromEnd(origin, ends[i])
                if dir then
                    dirs[i] = dir
                    wrote = wrote + 1
                    if type(effect[i]) == 'table' then
                        effect[i].Direction = dir
                        effect[i].direction = dir
                        effect[i].dir = dir
                        effect[i].AimDir = dir
                        effect[i].aimDir = dir
                    end
                end
            end
            if wrote > 0 then
                setEffectTableKey(effect, EFFECT_DIRS_KEYS, dirs)
            end
        end

        -- Mirror final packed shot data into FireServer effect for remote Bullet_Rays.
        local function syncFireEffect(unpacked, effect)
            if type(unpacked) ~= 'table' or effect == nil then
                return effect
            end
            if type(effect) ~= 'table' then
                return effect
            end

            local origin = unpacked.origin
            local ends = unpacked.ends
            local hits = unpacked.hits
            local count = math.max(1, math.floor(tonumber(unpacked.bulletcount) or 1))
            if type(ends) ~= 'table' and type(hits) ~= 'table' then
                return effect
            end

            local isShotgun = count > 1
            local visualHits = hits
            if isShotgun and type(ends) == 'table' then
                local refPoint = nil
                if type(hits) == 'table' and typeof(hits[1]) == 'Vector3' then
                    refPoint = hits[1]
                end
                visualHits = buildSpreadVisualHits(origin, ends, hits, count, refPoint)
            end

            if type(effect[1]) == 'table' then
                for i = 1, count do
                    local pellet = effect[i]
                    if type(pellet) == 'table' then
                        if typeof(ends and ends[i]) == 'Vector3' then
                            pellet.End = ends[i]
                            pellet['end'] = ends[i]
                            pellet.Position = ends[i]
                        end
                        local hitPos = type(visualHits) == 'table' and visualHits[i] or nil
                        if typeof(hitPos) == 'Vector3' then
                            pellet.Hit = hitPos
                            pellet.hit = hitPos
                        end
                        if typeof(origin) == 'Vector3' then
                            pellet.Origin = origin
                            pellet.origin = origin
                        end
                        local dir = pelletDirFromEnd(origin, ends and ends[i])
                        if dir then
                            pellet.Direction = dir
                            pellet.direction = dir
                            pellet.dir = dir
                            pellet.AimDir = dir
                            pellet.aimDir = dir
                        end
                    end
                end
            end

            if type(effect.data) == 'table' then
                syncFireEffect(unpacked, effect.data)
            end

            if type(ends) == 'table' then
                setEffectTableKey(effect, EFFECT_END_KEYS, ends)
            end
            if type(visualHits) == 'table' then
                setEffectTableKey(effect, EFFECT_HIT_KEYS, visualHits)
            elseif type(hits) == 'table' then
                setEffectTableKey(effect, EFFECT_HIT_KEYS, hits)
            end
            if typeof(origin) == 'Vector3' then
                setEffectTableKey(effect, EFFECT_ORIGIN_KEYS, origin)
            end

            if isShotgun then
                syncPelletDirections(effect, origin, ends, count)
            else
                local aimPoint = nil
                if type(visualHits) == 'table' and typeof(visualHits[1]) == 'Vector3' then
                    aimPoint = visualHits[1]
                elseif type(hits) == 'table' and typeof(hits[1]) == 'Vector3' then
                    aimPoint = hits[1]
                elseif type(ends) == 'table' and typeof(ends[1]) == 'Vector3' then
                    aimPoint = ends[1]
                end
                if typeof(origin) == 'Vector3' and typeof(aimPoint) == 'Vector3' then
                    local delta = aimPoint - origin
                    if delta.Magnitude >= 1e-4 then
                        setEffectTableKey(effect, EFFECT_DIR_KEYS, delta.Unit)
                    end
                end
            end

            return effect
        end

        PSilentApi.redirectPackEnds = redirectPackEnds
        PSilentApi.resolveSilentTarget = resolveSilentTarget
        PSilentApi.syncFireEffect = syncFireEffect
        PSilentApi.hitAlongPellet = hitAlongPellet
        PSilentApi.isAimFovActive = isAimFovActive
        PSilentApi.isSilentAutoShotActive = isSilentAutoShotActive

        local fovGui = nil
        local fovFrame = nil
        local fovStroke = nil

        local function ensureFOVCircleGui()
            if not fovGui or not fovGui.Parent then
                local parent = (gethui and gethui()) or game:GetService('CoreGui')
                fovGui = Instance.new('ScreenGui')
                fovGui.Name = 'SilentAimFOVCircle'
                fovGui.IgnoreGuiInset = true
                fovGui.ResetOnSpawn = false
                fovGui.DisplayOrder = 9999
                fovGui.Parent = parent

                fovFrame = Instance.new('Frame')
                fovFrame.Name = 'Circle'
                fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                fovFrame.BackgroundTransparency = 1
                fovFrame.BorderSizePixel = 0
                fovFrame.Visible = false
                fovFrame.Parent = fovGui

                local corner = Instance.new('UICorner')
                corner.CornerRadius = UDim.new(1, 0)
                corner.Parent = fovFrame

                fovStroke = Instance.new('UIStroke')
                fovStroke.Thickness = 1.5
                fovStroke.Color = Color3.fromRGB(255, 255, 255)
                fovStroke.Parent = fovFrame

                AimLock.FOVCircleGui = fovGui
                AimLock.FOVCircleFrame = fovFrame
                AimLock.FOVCircleStroke = fovStroke
            end
        end

        local function UpdateFOVCircle()
            ensureFOVCircleGui()
            local showCircle = (AimLock.ShowFOV and AimLock.ShowFOV.Value == true) and not (State and State.PanicMode)
            if showCircle then
                local center = UserInputService:GetMouseLocation()
                local radius = degreesToScreenRadius(AimLock.FOV and AimLock.FOV.Value or 30)
                local col = (AimLock.FOVColor and typeof(AimLock.FOVColor.Value) == 'Color3') and AimLock.FOVColor.Value or Color3.fromRGB(255, 255, 255)
                local d = math.max(2, math.floor(radius * 2 + 0.5))

                fovFrame.Position = UDim2.fromOffset(center.X, center.Y)
                fovFrame.Size = UDim2.fromOffset(d, d)
                fovStroke.Color = col
                fovFrame.Visible = true
            else
                if fovFrame then
                    fovFrame.Visible = false
                end
            end
        end

        local function setupGetAimHook()
            if hooked then
                return true
            end
            local ok = pcall(function()
                local Modules = ReplicatedStorage:FindFirstChild('Modules')
                if not Modules then
                    return
                end
                local GunModuleInst = Modules:FindFirstChild('GunModule')
                local GunNetInst = Modules:FindFirstChild('GunNet')
                if not GunModuleInst then
                    return
                end
                local GunModule = require(GunModuleInst)
                local ConfigInst = GunModuleInst:FindFirstChild('Config')
                local GunConfig = ConfigInst and require(ConfigInst)

                if type(GunConfig) == 'table' then
                    silentGunConfig = GunConfig
                    for weaponName, weapon in pairs(GunConfig) do
                        if type(weapon) == 'table' and weapon.Range ~= nil then
                            originalRanges[weaponName] = weapon.Range
                        end
                        if type(weapon) == 'table' and type(weapon.RandomBulletOffsets) == 'table' then
                            shotgunPatternCache[weaponName] = weapon.RandomBulletOffsets
                        end
                    end
                end

                if type(GunModule) ~= 'table' or type(GunModule.getAim) ~= 'function' then
                    return
                end

                oldGetAim = GunModule.getAim
                GunModule.getAim = function(origin, range)
                    local aimDir, aimDist = oldGetAim(origin, range)
                    if isAimFovActive() then
                        if not peekSkipSilentThisShot() then
                            local target = resolveSilentTarget(origin)
                            if target then
                                local newDir = (target - origin).Unit
                                aimDir = newDir
                                aimDist = (target - origin).Magnitude
                            end
                        end
                    else
                        clearSilentCache()
                        bypassShotsLeft = 0
                        pendingSkip = nil
                    end
                    return aimDir, aimDist
                end

                -- Chain onto existing GunNet.packFire if already wrapped.
                if not packFireHooked and GunNetInst then
                    local GunNet = require(GunNetInst)
                    if type(GunNet) == 'table' and type(GunNet.packFire) == 'function' then
                        local prevPackFire = GunNet.packFire
                        PSilentApi.rawPackFire = prevPackFire
                        GunNet.packFire = function(origin, range, bulletcount, hits, ends)
                            if isAimFovActive() and typeof(origin) == 'Vector3' then
                                if not consumeSkipSilentThisShot() then
                                    local target = resolveSilentTarget(origin)
                                    if target then
                                        redirectPackEnds(origin, bulletcount, ends, target)
                                    end
                                end
                            end
                            if BacktrackApi and type(BacktrackApi.consumeUseGhost) == 'function' then
                                pcall(BacktrackApi.consumeUseGhost)
                            end
                            local btActive = BacktrackApi and BacktrackApi.isActive and BacktrackApi.isActive()
                            local hasGhost = BacktrackApi and BacktrackApi.hasPendingRedirects and BacktrackApi.hasPendingRedirects()
                            if btActive and hasGhost and type(BacktrackApi.snapPackedShot) == 'function' then
                                pcall(BacktrackApi.snapPackedShot, origin, range, bulletcount, hits, ends)
                            end
                            return prevPackFire(origin, range, bulletcount, hits, ends)
                        end
                        packFireHooked = true
                    end
                end

                hooked = true
            end)
            return hooked == true and ok ~= false
        end

        setupGetAimHook()

        local lastAutoShotAt = 0

        local function getMuzzleOrigin()
            local char = LocalPlayer and LocalPlayer.Character
            if not char then
                return camera and camera.CFrame.Position or nil
            end
            local tool = char:FindFirstChildOfClass('Tool')
            if tool then
                local handle = tool:FindFirstChild('Handle')
                if tool:FindFirstChild('Default') then
                    local mesh = tool.Default:FindFirstChild('Mesh')
                    local def = mesh and mesh:FindFirstChild('Default')
                    local muzzle = def and def:FindFirstChild('Muzzle')
                    if muzzle then
                        return muzzle.WorldPosition
                    end
                end
                if handle then
                    local muzzle = handle:FindFirstChild('Muzzle')
                    if muzzle then
                        return muzzle.WorldPosition
                    end
                    return (handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
                end
            end
            local head = char:FindFirstChild('Head')
            if head and head:IsA('BasePart') then
                return head.Position
            end
            local hrp = char:FindFirstChild('HumanoidRootPart')
            if hrp and hrp:IsA('BasePart') then
                return hrp.Position
            end
            return camera and camera.CFrame.Position or nil
        end

        local function triggerWeaponShot(tool)
            pcall(function()
                if tool and type(tool.Activate) == 'function' then
                    tool:Activate()
                end
            end)
            pcall(function()
                if type(mouse1click) == 'function' then
                    mouse1click()
                elseif type(mouse1press) == 'function' and type(mouse1release) == 'function' then
                    mouse1press()
                    task.delay(0.01, function()
                        pcall(mouse1release)
                    end)
                elseif VirtualInputManager and type(VirtualInputManager.SendMouseButtonEvent) == 'function' then
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.delay(0.01, function()
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                        end)
                    end)
                end
            end)
        end

        local function stepSilentAutoShot()
            if not isSilentAutoShotActive() then
                return
            end

            local char = LocalPlayer and LocalPlayer.Character
            if not char then
                return
            end
            local hum = char:FindFirstChildOfClass('Humanoid')
            if not hum or hum.Health <= 0 then
                return
            end

            local tool = char:FindFirstChildOfClass('Tool')
            if not tool then
                return
            end

            local ammo = tool:FindFirstChild('Ammo')
            local shooting = tool:FindFirstChild('Shooting')
            local isGun = (ammo ~= nil) or (shooting ~= nil) or (originalRanges[tool.Name] ~= nil)
            if not isGun then
                return
            end

            if ammo and ammo.Value <= 0 then
                return
            end
            if shooting and shooting.Value == true then
                return
            end

            local now = os.clock()
            local delayMs = tonumber(AimLock.AutoShotDelay and AimLock.AutoShotDelay.Value) or 0
            local delaySec = math.max(0, delayMs) / 1000
            local minInterval = math.max(delaySec, 0.03)
            if (now - lastAutoShotAt) < minInterval then
                return
            end

            local origin = getMuzzleOrigin()
            if not origin then
                return
            end

            local target = resolveSilentTarget(origin)
            if not target then
                return
            end
            if not isAimPointVisible(origin, target, lastSilentPlayer) then
                clearSilentCache()
                return
            end

            lastAutoShotAt = now
            triggerWeaponShot(tool)
        end

        if AimLock.Connection then
            AimLock.Connection:Disconnect()
        end
        local lastGetAimRetry = 0
        AimLock.Connection = safeConnect(RunService.RenderStepped, function()
            if not hooked then
                setupGetAimHook()
            end
            if not isAimFovActive() then
                clearSilentCache()
                bypassShotsLeft = 0
                pendingSkip = nil
                if BacktrackApi and type(BacktrackApi.clearPending) == 'function' then
                    BacktrackApi.clearPending()
                end
            end
            if AimLock.ShowFOV and AimLock.ShowFOV.Value == true then
                UpdateFOVCircle()
            elseif fovFrame and fovFrame.Visible then
                fovFrame.Visible = false
            end
            stepSilentAutoShot()
        end)

        Library:OnUnload(function()
            clearSilentCache()
            clearLagHistory(nil)
            bypassShotsLeft = 0
            pendingSkip = nil
            if AimLock.Connection then
                pcall(function() AimLock.Connection:Disconnect() end)
                AimLock.Connection = nil
            end
            if fovGui then
                pcall(function() fovGui:Destroy() end)
                fovGui = nil
            end
            if AimLock.FOVCircleGui then
                pcall(function() AimLock.FOVCircleGui:Destroy() end)
                AimLock.FOVCircleGui = nil
            end
            if hooked and oldGetAim then
                pcall(function()
                    local Modules = ReplicatedStorage:FindFirstChild('Modules')
                    local GunModuleInst = Modules and Modules:FindFirstChild('GunModule')
                    if GunModuleInst then
                        local GunModule = require(GunModuleInst)
                        if type(GunModule) == 'table' then
                            GunModule.getAim = oldGetAim
                        end
                    end
                end)
            end
        end)
    end)(State.AimLock, safeConnect, Library, isSharedTargetRole, isSharedFriendRole, Toggles, Options)

    do
    (function()
    local tabButtons = {}
    local function applyTabVisual(entry)
        if not entry then
            return
        end
        local active = entry.active == true
        local hovered = entry.hovered == true
        local bg = active and palette.surfaceElevated or (hovered and palette.surfaceSoft or palette.surface)
        local bgTrans = active and 0.15 or (hovered and 0.35 or 0.55)
        local textColor = active and palette.text or (hovered and palette.textDim or palette.textDim)
        local strokeColor = active and palette.stroke or palette.strokeSoft
        local strokeTransparency = active and 0.35 or 0.65
        tween(entry.button, 0.16, { BackgroundColor3 = bg, BackgroundTransparency = bgTrans, TextColor3 = textColor })
        tween(entry.stroke, 0.16, { Color = strokeColor, Transparency = strokeTransparency })
        if entry.indicator then
            entry.indicator.BackgroundColor3 = palette.accentBar
            entry.indicator.Visible = active
        end
    end

    local function setTab(tabName)
        for name, page in pairs(pages) do
            page.root.Visible = (name == tabName)
        end
        for name, entry in pairs(tabButtons) do
            local active = (name == tabName)
            entry.active = active
            applyTabVisual(entry)
        end
    end

    local menuState = {
        open = false,
        animating = false,
    }

    local function setMenuVisible(show)
        if isInitialLoaderActive then
            if show then
                isInitialLoaderActive = false
                if screen then screen.Enabled = true end
                if keybindScreen then keybindScreen.Enabled = true end
            else
                return
            end
        end
        if menuState.animating then
            return
        end
        if show == menuState.open then
            return
        end
        menuState.animating = true

        local targetSize = mainTargetSize
        local targetPos = mainTargetPos
        local closeWidth = math.max(1, math.floor(targetSize.X.Offset * 0.96))
        local closeHeight = math.max(1, math.floor(targetSize.Y.Offset * 0.96))
        local closedSize = UDim2.fromOffset(closeWidth, closeHeight)
        local closedPos = UDim2.new(0.5, -closeWidth / 2, 0.5, -closeHeight / 2)

        local easeStyleName = tostring(State.MenuEaseStyle and State.MenuEaseStyle.Value or 'Quint')
        local easeDirName = tostring(State.MenuEaseDir and State.MenuEaseDir.Value or 'Out')
        local easeStyle = Enum.EasingStyle[easeStyleName] or Enum.EasingStyle.Quint
        local easeDir = Enum.EasingDirection[easeDirName] or Enum.EasingDirection.Out
        local animSpeed = math.clamp(tonumber(State.TweeningSpeed and State.TweeningSpeed.Value) or 0.28, 0.05, 5)

        screen.Enabled = true
        if show then
            main.Visible = true
            main.Size = closedSize
            main.Position = closedPos
            main.BackgroundTransparency = 1
            if settingsWindow then
                settingsWindow.Visible = true
                if syncSettingsPosition then
                    syncSettingsPosition()
                end
            end

            local syncConn
            syncConn = safeConnect(RunService.RenderStepped, function()
                if syncSettingsPosition then
                    syncSettingsPosition()
                end
            end)

            tween(main, animSpeed, { Size = targetSize, Position = targetPos, BackgroundTransparency = 0 }, easeStyle, easeDir)
            runLater(animSpeed + 0.02, function()
                if syncConn then
                    pcall(function() syncConn:Disconnect() end)
                end
                menuState.open = true
                menuState.animating = false
                if syncSettingsPosition then
                    syncSettingsPosition()
                end
            end)
        else
            setRangePanelVisible(false)
            if missShotsUi.setVisible then
                missShotsUi.setVisible(false)
            end
            if silentMissShotsUi.setVisible then
                silentMissShotsUi.setVisible(false)
            end
            if settingsWindow then
                settingsWindow.Visible = false
            end
            local closeSpeed = math.max(0.05, animSpeed * 0.75)
            tween(main, closeSpeed, { Size = closedSize, Position = closedPos, BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            runLater(closeSpeed + 0.02, function()
                screen.Enabled = false
                menuState.open = false
                menuState.animating = false
                main.BackgroundTransparency = 0
            end)
        end
    end

    local function createTabButton(name)
        local btn = Instance.new('TextButton')
        btn.AutoButtonColor = false
        btn.Size = UDim2.new(1 / 6, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel = 0
        btn.Text = ''
        btn.Parent = tabBar

        local bg = Instance.new('Frame')
        bg.Name = 'Bg'
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        bg.BorderSizePixel = 0
        bg.Parent = btn

        local bgGrad = Instance.new('UIGradient')
        bgGrad.Rotation = 90
        bgGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHex('1F1F1F')),
            ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
        })
        bgGrad.Parent = bg

        local function MakePiece(Anchor, Pos, Sz, Col, ZIdx)
            local p = Instance.new('Frame')
            p.AnchorPoint = Anchor
            p.Position = Pos
            p.Size = Sz
            p.BackgroundColor3 = typeof(Col) == 'string' and Color3.fromHex(Col) or Col
            p.BorderSizePixel = 0
            p.ZIndex = ZIdx
            p.Parent = bg
            return p
        end

        local topBlack    = MakePiece(Vector2.new(0, 0), UDim2.new(0, 0, 0, 0),  UDim2.new(1, 0, 0, 1),  '000000', 4)
        local topGray     = MakePiece(Vector2.new(0, 0), UDim2.new(0, 0, 0, 1),  UDim2.new(1, 0, 0, 1),  '393939', 4)
        local bottomBlack = MakePiece(Vector2.new(0, 1), UDim2.new(0, 0, 1, 0),  UDim2.new(1, 0, 0, 1),  '000000', 4)
        local bottomGray  = MakePiece(Vector2.new(0, 1), UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1),  '393939', 4)
        local sep         = MakePiece(Vector2.new(1, 0), UDim2.new(1, 0, 0, 2),  UDim2.new(0, 1, 1, -4), '393939', 3)

        local topGradient = Instance.new('Frame')
        topGradient.Name = 'TopGradient'
        topGradient.AnchorPoint = Vector2.new(0, 0)
        topGradient.Position = UDim2.new(0, 0, 0, 0)
        topGradient.Size = UDim2.new(1, 0, 0, 1)
        topGradient.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        topGradient.BorderSizePixel = 0
        topGradient.Visible = false
        topGradient.ZIndex = 5
        topGradient.Parent = bg
        local tabTopGrad = Instance.new('UIGradient')
        tabTopGrad.Parent = topGradient
        registerAccentGradient(tabTopGrad)

        local lbl = Instance.new('TextLabel')
        lbl.Name = 'Label'
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.BorderSizePixel = 0
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextColor3 = Color3.fromHex('8C8F99')
        lbl.Text = string.lower(name)
        lbl.Parent = bg
        lbl.ZIndex = 6

        local entry = {
            button = btn,
            bg = bg,
            bgGrad = bgGrad,
            topGradient = topGradient,
            topBlack = topBlack,
            topGray = topGray,
            bottomBlack = bottomBlack,
            bottomGray = bottomGray,
            sep = sep,
            label = lbl,
            active = false,
        }

        local function applyTabVisual()
            if entry.active then
                bg.Position = UDim2.new(0, 0, 0, 1)
                bg.Size = UDim2.new(1, 0, 1, -1)
                bgGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('161616')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('151515')),
                })
                lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                topGradient.Visible = true
                topBlack.Visible = false
                topGray.Visible = false
                bottomBlack.Visible = false
                bottomGray.Visible = false
                sep.Visible = false
            else
                bg.Position = UDim2.new(0, 0, 0, 0)
                bg.Size = UDim2.new(1, 0, 1, 0)
                bgGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHex('1F1F1F')),
                    ColorSequenceKeypoint.new(1, Color3.fromHex('181818')),
                })
                lbl.TextColor3 = Color3.fromHex('8C8F99')
                topGradient.Visible = false
                topBlack.Visible = true
                topGray.Visible = true
                bottomBlack.Visible = true
                bottomGray.Visible = true
                sep.Visible = true
            end
        end

        safeConnect(btn.MouseButton1Click, function()
            setTab(name)
            for _, e in pairs(tabButtons) do
                if e.button then
                    e.active = (e == entry)
                    if type(e.applyTabVisual) == 'function' then
                        e.applyTabVisual()
                    end
                end
            end
        end)

        entry.applyTabVisual = applyTabVisual
        applyTabVisual()
        tabButtons[name] = entry
    end

    createTabButton('Combat')
    createTabButton('pSilent')
    createTabButton('Backtrack')
    createTabButton('Visuals')
    createTabButton('Roles')
    createTabButton('Inventory')

    setTab('Combat')
    if tabButtons['Combat'] then
        tabButtons['Combat'].active = true
        tabButtons['Combat'].applyTabVisual()
    end

    local function isCtrlDown()
        return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
    end

    applyLayoutSizes = function(recenter)
        if main then
            local w = tonumber(State.MenuWidth and State.MenuWidth.Value) or 600
            local h = tonumber(State.MenuHeight and State.MenuHeight.Value) or 550
            w = math.clamp(w, 500, 800)
            h = math.clamp(h, 450, 700)
            main.Size = UDim2.fromOffset(w, h)
            mainTargetSize = main.Size
            if recenter then
                main.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
                mainTargetPos = main.Position
            end
            if syncSettingsPosition then
                syncSettingsPosition()
            end
        end
        if rangePanel then
            local rw = math.clamp(tonumber(State.RangePanelWidth and State.RangePanelWidth.Value) or 248, 220, 420)
            local rh = math.clamp(tonumber(State.RangePanelHeight and State.RangePanelHeight.Value) or 290, 260, 560)
            rangePanel.Size = UDim2.fromOffset(rw, rh)
            if rangePanelOpen then
                syncRangePanelPosition()
            end
        end
        if missShotsUi.panel then
            local mw = math.clamp(tonumber(State.MissShotsPanelWidth and State.MissShotsPanelWidth.Value) or 248, 220, 420)
            local mh = math.clamp(tonumber(State.MissShotsPanelHeight and State.MissShotsPanelHeight.Value) or 180, 140, 360)
            missShotsUi.panel.Size = UDim2.fromOffset(mw, mh)
            if missShotsUi.open and missShotsUi.syncPosition then
                missShotsUi.syncPosition()
            end
        end
        if silentMissShotsUi.panel then
            local smw = math.clamp(tonumber(State.SilentMissShotsPanelWidth and State.SilentMissShotsPanelWidth.Value) or 248, 220, 420)
            local smh = math.clamp(tonumber(State.SilentMissShotsPanelHeight and State.SilentMissShotsPanelHeight.Value) or 180, 140, 360)
            silentMissShotsUi.panel.Size = UDim2.fromOffset(smw, smh)
            if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                silentMissShotsUi.syncPosition()
            end
        end
        if type(applyOverlayPanelPositions) == 'function' then
            applyOverlayPanelPositions()
        end
    end

    applyOverlayPanelPositions = function()
        if keybindWindow then
            local x = tonumber(State.KeybindsPanelX and State.KeybindsPanelX.Value) or 16
            local y = tonumber(State.KeybindsPanelY and State.KeybindsPanelY.Value) or 16
            keybindWindow.Position = UDim2.fromOffset(x, y)
        end
        if spectatorListPanel then
            local x = tonumber(State.SpectatorListX and State.SpectatorListX.Value) or 16
            local y = tonumber(State.SpectatorListY and State.SpectatorListY.Value) or 96
            spectatorListPanel.Position = UDim2.fromOffset(x, y)
        end
    end

    local function setupCtrlResize(target, opts)
        opts = opts or {}
        local minW = opts.minW or 200
        local minH = opts.minH or 200
        local maxW = opts.maxW or 1600
        local maxH = opts.maxH or 1000
        local widthOption = opts.widthOption
        local heightOption = opts.heightOption
        local onChanged = opts.onChanged

        local grip = Instance.new('TextButton')
        grip.Name = 'CtrlResizeGrip'
        grip.AnchorPoint = Vector2.new(1, 1)
        grip.Position = UDim2.new(1, -2, 1, -2)
        grip.Size = UDim2.fromOffset(18, 18)
        grip.BackgroundColor3 = palette.textDim
        grip.BackgroundTransparency = 1
        grip.Text = ''
        grip.AutoButtonColor = false
        grip.ZIndex = 100
        grip.Parent = target
        applyCorner(grip, 4)

        local line1 = Instance.new('Frame')
        line1.AnchorPoint = Vector2.new(1, 1)
        line1.Position = UDim2.new(1, -3, 1, -3)
        line1.Size = UDim2.fromOffset(10, 2)
        line1.BackgroundColor3 = palette.textDim
        line1.BackgroundTransparency = 0.65
        line1.BorderSizePixel = 0
        line1.Parent = grip

        local line2 = Instance.new('Frame')
        line2.AnchorPoint = Vector2.new(1, 1)
        line2.Position = UDim2.new(1, -3, 1, -7)
        line2.Size = UDim2.fromOffset(6, 2)
        line2.BackgroundColor3 = palette.textDim
        line2.BackgroundTransparency = 0.65
        line2.BorderSizePixel = 0
        line2.Parent = grip

        local function setGripVisible(active)
            local transparency = active and 0.2 or 0.65
            line1.BackgroundTransparency = transparency
            line2.BackgroundTransparency = transparency
            grip.BackgroundTransparency = active and 0.82 or 1
        end

        trackConnection(safeConnect(UIS.InputBegan, function(input)
            if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
                setGripVisible(true)
            end
        end))
        trackConnection(safeConnect(UIS.InputEnded, function(input)
            if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
                if not isCtrlDown() then
                    setGripVisible(false)
                end
            end
        end))

        local resizing = false
        local resizeInput = nil
        local resizeStartMouse = nil
        local resizeStartW = 0
        local resizeStartH = 0

        local function applyDimensions(w, h)
            w = math.clamp(math.floor(w + 0.5), minW, maxW)
            h = math.clamp(math.floor(h + 0.5), minH, maxH)
            target.Size = UDim2.fromOffset(w, h)
            if widthOption then
                widthOption:SetValue(w)
            end
            if heightOption then
                heightOption:SetValue(h)
            end
            if onChanged then
                onChanged(w, h)
            end
        end

        safeConnect(grip.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if not isCtrlDown() then
                return
            end
            resizing = true
            resizeInput = input
            resizeStartMouse = input.Position
            resizeStartW = target.Size.X.Offset
            resizeStartH = target.Size.Y.Offset
        end)

        safeConnect(grip.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                resizeInput = input
            end
        end)

        trackConnection(safeConnect(UIS.InputChanged, function(input)
            if not resizing or input ~= resizeInput then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            local delta = input.Position - resizeStartMouse
            applyDimensions(resizeStartW + delta.X, resizeStartH + delta.Y)
        end))

        trackConnection(safeConnect(UIS.InputEnded, function(input)
            if not resizing then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            resizing = false
            resizeInput = nil
            if type(requestSaveConfig) == 'function' then
                requestSaveConfig()
            end
        end))
    end

    setupCtrlResize(main, {
        minW = 500,
        minH = 400,
        maxW = 1000,
        maxH = 800,
        widthOption = State.MenuWidth,
        heightOption = State.MenuHeight,
        onChanged = function(w, h)
            mainTargetSize = UDim2.fromOffset(w, h)
            if rangePanelOpen then
                syncRangePanelPosition()
            end
            if missShotsUi.open and missShotsUi.syncPosition then
                missShotsUi.syncPosition()
            end
            if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                silentMissShotsUi.syncPosition()
            end
            end,
    })

    setupCtrlResize(rangePanel, {
        minW = 220,
        minH = 260,
        maxW = 420,
        maxH = 560,
        widthOption = State.RangePanelWidth,
        heightOption = State.RangePanelHeight,
        onChanged = function()
            if rangePanelOpen then
                syncRangePanelPosition()
            end
            if missShotsUi.open and missShotsUi.syncPosition then
                missShotsUi.syncPosition()
            end
            if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                silentMissShotsUi.syncPosition()
            end
        end,
    })

    if missShotsUi.panel then
        setupCtrlResize(missShotsUi.panel, {
            minW = 220,
            minH = 140,
            maxW = 420,
            maxH = 360,
            widthOption = State.MissShotsPanelWidth,
            heightOption = State.MissShotsPanelHeight,
            onChanged = function()
                if missShotsUi.open and missShotsUi.syncPosition then
                    missShotsUi.syncPosition()
                end
                if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                    silentMissShotsUi.syncPosition()
                end
            end,
        })
    end

    if silentMissShotsUi.panel then
        setupCtrlResize(silentMissShotsUi.panel, {
            minW = 220,
            minH = 140,
            maxW = 420,
            maxH = 360,
            widthOption = State.SilentMissShotsPanelWidth,
            heightOption = State.SilentMissShotsPanelHeight,
            onChanged = function()
                if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                    silentMissShotsUi.syncPosition()
                end
            end,
        })
    end

    menuState.open = false

    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

safeConnect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if isCtrlDown() then
                return
            end
            dragging = true
            dragStart = input.Position
            startPos = main.Position
safeConnect(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

safeConnect(header.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

trackConnection(safeConnect(UIS.InputChanged, function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            mainTargetPos = main.Position
            if syncSettingsPosition then
                syncSettingsPosition()
            end
            if rangePanelOpen then
                syncRangePanelPosition()
            end
            if missShotsUi.open and missShotsUi.syncPosition then
                missShotsUi.syncPosition()
            end
            if silentMissShotsUi.open and silentMissShotsUi.syncPosition then
                silentMissShotsUi.syncPosition()
            end
            end
    end))

safeConnect(closeBtn.MouseButton1Click, function()
        setMenuVisible(false)
    end)

    local function updateKeyStates(input, began)
        for opt, _ in pairs(KeybindOptions) do
            local keyVal = opt.__storeMode and { opt.__key, opt.__mode } or opt.__key
            if keyMatch(input, keyVal) then
                if began then
                    opt.__down = true
                    if opt.__mode == 'Toggle' then
                        opt.__toggled = not opt.__toggled
                    end
                else
                    opt.__down = false
                end
            end
        end
    end

    local function extractBindableInput(input)
        if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
            return input.KeyCode
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            return nil
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
            return input.UserInputType
        end

        return nil
    end

trackConnection(safeConnect(UIS.InputBegan, function(input, gameProcessed)
        if keybindCapture then
            local capture = keybindCapture
            if (os.clock() - (capture.startedAt or 0)) < 0.08 then
                return
            end
            if input.KeyCode == Enum.KeyCode.Escape then
                keybindCapture = nil
                if capture.button then
                    capture.button.Text = keyName(capture.option.Value)
                    capture.button.TextColor3 = palette.accent
                end
                return
            end

            local bind = extractBindableInput(input)
            if bind then
                keybindCapture = nil
                capture.option:SetValue(bind)
                if capture.button then
                    capture.button.Text = keyName(capture.option.Value)
                    capture.button.TextColor3 = palette.accent
                end
            end
            return
        end

        updateKeyStates(input, true)
        if gameProcessed then
            return
        end
        if keyMatch(input, State.MenuKey.Value) then
            if not isInitialLoaderActive then
                setMenuVisible(not menuState.open)
            end
        end
    end))

trackConnection(safeConnect(UIS.InputEnded, function(input)
        updateKeyStates(input, false)
    end))

    pcall(loadConfig)
    if type(loadRoles) == 'function' then
        pcall(loadRoles)
    end
    if Options.ThemeAccent and Options.ThemeAccent.Value == Color3.fromRGB(168, 48, 52) then
        Options.ThemeAccent:SetValue(Color3.fromHex('99bcff'))
    end
    applyThemePreset(State.ThemePreset and State.ThemePreset.Value or 'Default', true)
    applyLayoutSizes(true)
    pcall(applyTheme)

    local syncWmVisibility
    pcall(function()
        local watermarkGui = Instance.new('ScreenGui')
        watermarkGui.Name = 'BomzhoodWatermark'
        watermarkGui.ResetOnSpawn = false
        watermarkGui.IgnoreGuiInset = true
        watermarkGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        watermarkGui.DisplayOrder = 9999
        watermarkGui.Parent = (gethui and gethui()) or CoreGui or parent

        local wmFrame = Instance.new('Frame')
        wmFrame.Name = 'Watermark'
        wmFrame.AnchorPoint = Vector2.new(0.5, 0)
        wmFrame.Position = UDim2.new(0.5, 0, 0, 8)
        wmFrame.Size = UDim2.fromOffset(420, 22)
        wmFrame.BackgroundColor3 = Color3.fromHex('161616')
        wmFrame.BorderSizePixel = 0
        wmFrame.ZIndex = 10
        wmFrame.Parent = watermarkGui
        applyCoincideBorder(wmFrame)

        local wmTop = Instance.new('Frame')
        wmTop.Size = UDim2.new(1, 0, 0, 1)
        wmTop.BorderSizePixel = 0
        wmTop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        wmTop.ZIndex = 14
        wmTop.Parent = wmFrame
        local wmGrad = Instance.new('UIGradient')
        wmGrad.Parent = wmTop
        registerAccentGradient(wmGrad)

        local wmLbl = Instance.new('TextLabel')
        wmLbl.BackgroundTransparency = 1
        wmLbl.Size = UDim2.new(1, -12, 1, 0)
        wmLbl.Position = UDim2.fromOffset(6, 0)
        wmLbl.Font = Enum.Font.Gotham
        wmLbl.TextSize = 11
        wmLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        wmLbl.TextXAlignment = Enum.TextXAlignment.Center
        wmLbl.ZIndex = 12
        wmLbl.Text = 'Bomzhood Hub'
        wmLbl.Parent = wmFrame

        local LP = Players.LocalPlayer
        local fps, fpsAcc, fpsCnt = 60, 0, 0
        local gameName = 'Roblox'
        task.spawn(function()
            local ok, info = pcall(game.GetService(game, 'MarketplaceService').GetProductInfo, game:GetService('MarketplaceService'), game.PlaceId)
            if ok and info and info.Name then gameName = info.Name end
        end)

        trackConnection(safeConnect(RunService.RenderStepped, function(dt)
            fpsCnt = fpsCnt + 1
            fpsAcc = fpsAcc + dt
            if fpsAcc >= 0.5 then
                fps = math.round(fpsCnt / fpsAcc)
                fpsCnt, fpsAcc = 0, 0
            end
        end))

        local function updateWatermarkText()
            if not watermarkGui or not watermarkGui.Parent then return end
            local isWmEnabled = (State.Watermark and State.Watermark.Value == true)
            watermarkGui.Enabled = isWmEnabled
            wmFrame.Visible = isWmEnabled
            if not isWmEnabled then return end

            local pingMs = 0
            pcall(function()
                local stats = game:GetService('Stats')
                if stats and stats.PerformanceStats and stats.PerformanceStats.Ping then
                    pingMs = math.round(stats.PerformanceStats.Ping:GetValue())
                elseif stats and stats.Network and stats.Network.ServerStatsItem and stats.Network.ServerStatsItem['Data Ping'] then
                    pingMs = math.round(stats.Network.ServerStatsItem['Data Ping']:GetValue())
                elseif LP and type(LP.GetNetworkPing) == 'function' then
                    pingMs = math.round(LP:GetNetworkPing() * 1000)
                end
            end)

            local optMode = tostring(State.WatermarkOpts and State.WatermarkOpts.Value or 'Title | Fps | Ping | Game')
            local parts = { 'Bomzhood Hub' }
            if optMode == 'Title | Fps' then
                table.insert(parts, tostring(fps) .. ' fps')
            elseif optMode == 'Title | Fps | Ping' then
                table.insert(parts, tostring(fps) .. ' fps')
                table.insert(parts, tostring(pingMs) .. ' ms')
            elseif optMode == 'Full Info' then
                table.insert(parts, tostring(fps) .. ' fps')
                table.insert(parts, tostring(pingMs) .. ' ms')
                table.insert(parts, gameName)
                if LP then
                    table.insert(parts, LP.Name)
                end
                table.insert(parts, os.date('%H:%M:%S'))
            else
                table.insert(parts, tostring(fps) .. ' fps')
                table.insert(parts, tostring(pingMs) .. ' ms')
                table.insert(parts, gameName)
            end

            local fullText = table.concat(parts, ' | ')
            wmLbl.Text = fullText
            local textWidth = math.max(260, #fullText * 7 + 28)
            wmFrame.Size = UDim2.fromOffset(textWidth, 22)
        end

        local wmAcc = 0
        trackConnection(safeConnect(RunService.Heartbeat, function(dt)
            if not watermarkGui or not watermarkGui.Parent then return end
            if not State.Watermark or State.Watermark.Value ~= true then
                watermarkGui.Enabled = false
                wmFrame.Visible = false
                return
            end

            local rate = tonumber(State.WatermarkRate and State.WatermarkRate.Value) or 0.1
            wmAcc = wmAcc + dt
            if wmAcc < rate then return end
            wmAcc = 0

            updateWatermarkText()
        end))

        syncWmVisibility = function()
            if isInitialLoaderActive then
                watermarkGui.Enabled = false
                wmFrame.Visible = false
                return
            end
            local enabled = (State.Watermark and State.Watermark.Value == true)
            watermarkGui.Enabled = enabled
            wmFrame.Visible = enabled
            if enabled then
                updateWatermarkText()
            end
        end

        attachChangeListener(State.Watermark, syncWmVisibility)
        attachChangeListener(State.WatermarkOpts, updateWatermarkText)
        syncWmVisibility()

        Library:OnUnload(function()
            pcall(function()
                if watermarkGui and watermarkGui.Parent then
                    watermarkGui:Destroy()
                end
            end)
        end)
    end)

    createCoincideLoader("Bomzhood Hub", function()
        isInitialLoaderActive = false
        if screen then
            screen.Enabled = true
        end
        if keybindScreen then
            keybindScreen.Enabled = true
        end
        if setKeybindWindowVisible then
            setKeybindWindowVisible()
        end
        pcall(function()
            if syncWmVisibility then
                syncWmVisibility()
            end
        end)
        setMenuVisible(true)
        task.spawn(function()
            pcall(function()
                local loaded = false
                if isfile and isfile(autoLoadFile) and readfile then
                    local nm = tostring(readfile(autoLoadFile) or ''):gsub('%s+$', '')
                    if nm ~= '' and loadConfig then
                        local ok = loadConfig(nm)
                        if ok then
                            loaded = true
                            if type(showNotification) == 'function' then
                                showNotification('Settings', 'Auto-loaded config: ' .. nm, 3)
                            end
                        end
                    end
                end
                if not loaded and loadConfig then
                    if isfile and isfile(getConfigFilePath('default')) then
                        loadConfig('default')
                    elseif isfile and isfile(filePath) then
                        loadConfig('config')
                    end
                end
                if setKeybindWindowVisible then
                    setKeybindWindowVisible()
                end
                if refreshKeybindWindow then
                    refreshKeybindWindow()
                end
                if applyOverlayPanelPositions then
                    applyOverlayPanelPositions()
                end
            end)
        end)
    end)

    Library:OnUnload(function()
        saveConfig()
        for _, conn in ipairs(runtimeConnections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        for _, conn in ipairs(keybindConnections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        pcall(function()
            if settingsWindow and settingsWindow.Parent then
                settingsWindow:Destroy()
            end
        end)
        pcall(function()
            if screen then
                screen:Destroy()
            end
        end)
        pcall(function()
            if rangePanel then
                rangePanel:Destroy()
            end
        end)
        pcall(function()
            if missShotsUi.panel then
                missShotsUi.panel:Destroy()
            end
        end)
        pcall(function()
            if silentMissShotsUi.panel then
                silentMissShotsUi.panel:Destroy()
            end
        end)
        pcall(function()
            if keybindScreen then
                keybindScreen:Destroy()
            end
        end)
        end)
    end)()
    end

    do
    (function(BT, safeConnect, Library, isSharedTargetRole, isSharedFriendRole, runLaterFn)
        local Players = game:GetService('Players')
        local ReplicatedStorage = game:GetService('ReplicatedStorage')
        local RunService = game:GetService('RunService')
        local Workspace = game:GetService('Workspace')
        local LocalPlayer = Players.LocalPlayer
        local FOLDER_NAME = 'BacktrackGhosts'
        local RANGE_PAD = 2
        local ghostMap = {}
        local playerGhosts = {}
        local history = {}
        local pendingRedirects = {}
        local pendingUseGhost = nil
        local sendingFire = false
        local hookedShoot = false
        local hookedFire = false
        local queryCacheAt = {}
        local QUERY_REFRESH = 0.1

        local function isKeyActive(optionObj)
            if not optionObj then
                return false
            end
            if type(optionObj.GetState) == 'function' then
                local ok, state = pcall(function()
                    return optionObj:GetState()
                end)
                if ok then
                    return state == true
                end
            end
            return false
        end

        local function isActive()
            return BT and BT.Enabled and BT.Enabled.Value == true and isKeyActive(BT.Key)
        end

        local function getFolder()
            local folder = Workspace:FindFirstChild(FOLDER_NAME)
            if folder then
                return folder
            end
            folder = Instance.new('Folder')
            folder.Name = FOLDER_NAME
            folder.Parent = Workspace
            return folder
        end

        local function resolveLivePart(realHrp)
            if not realHrp or not realHrp.Parent then
                return nil
            end
            local char = realHrp.Parent
            for _, name in ipairs({ 'UpperTorso', 'HumanoidRootPart', 'Head', 'Hitbox' }) do
                local p = char:FindFirstChild(name)
                if p and p:IsA('BasePart') then
                    return p
                end
            end
            return realHrp
        end

        local function muzzleOrigin()
            local char = LocalPlayer and LocalPlayer.Character
            if not char then
                return nil
            end
            local tool = char:FindFirstChildOfClass('Tool')
            if tool then
                local handle = tool:FindFirstChild('Handle')
                if tool:FindFirstChild('Default') then
                    local mesh = tool.Default:FindFirstChild('Mesh')
                    local def = mesh and mesh:FindFirstChild('Default')
                    local muzzle = def and def:FindFirstChild('Muzzle')
                    if muzzle then
                        return muzzle.WorldPosition
                    end
                end
                if handle then
                    local muzzle = handle:FindFirstChild('Muzzle')
                    if muzzle then
                        return muzzle.WorldPosition
                    end
                    return (handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
                end
            end
            local hrp = char:FindFirstChild('HumanoidRootPart')
            return hrp and hrp.Position or nil
        end

        local function equippedWeaponRange(packedRange)
            local char = LocalPlayer and LocalPlayer.Character
            local tool = char and char:FindFirstChildOfClass('Tool')
            if tool then
                local r = tool:FindFirstChild('Range')
                if r and (r:IsA('NumberValue') or r:IsA('IntValue')) then
                    return r.Value
                end
            end
            return tonumber(packedRange) or 0
        end

        local function hasLineOfSight(origin, live)
            if typeof(origin) ~= 'Vector3' or not live or not live.Parent then
                return false
            end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            local exclude = {}
            if LocalPlayer.Character then
                exclude[#exclude + 1] = LocalPlayer.Character
            end
            local folder = Workspace:FindFirstChild(FOLDER_NAME)
            if folder then
                exclude[#exclude + 1] = folder
            end
            params.FilterDescendantsInstances = exclude
            local delta = live.Position - origin
            if delta.Magnitude < 0.05 then
                return true
            end
            local result = Workspace:Raycast(origin, delta, params)
            if not result then
                return true
            end
            return result.Instance:IsDescendantOf(live.Parent)
        end

        local function isPlayerValid(plr)
            if not plr or plr == LocalPlayer then
                return false
            end
            if isSharedFriendRole(plr) then
                return false
            end
            if BT.TargetOnly and BT.TargetOnly.Value == true and not isSharedTargetRole(plr) then
                return false
            end
            if IsPlayerKO(plr) then
                return false
            end
            local char = plr.Character
            if not char then
                return false
            end
            local hum = char:FindFirstChildOfClass('Humanoid')
            if hum and (hum.Health or 0) <= 0 then
                return false
            end
            local hrp = char:FindFirstChild('HumanoidRootPart')
            return hrp and hrp:IsA('BasePart')
        end

        local function wouldRegister(origin, live, plr)
            if plr and not isPlayerValid(plr) then
                return false
            end
            if not live or not live.Parent then
                return false
            end
            if typeof(origin) ~= 'Vector3' then
                origin = muzzleOrigin()
            end
            if typeof(origin) ~= 'Vector3' then
                return false
            end
            local maxRange = equippedWeaponRange(nil)
            if maxRange <= 0 then
                maxRange = 200
            end
            if (live.Position - origin).Magnitude > maxRange + RANGE_PAD then
                return false
            end
            return hasLineOfSight(origin, live)
        end

        local function destroyGhost(plr)
            local part = plr and playerGhosts[plr]
            if part then
                ghostMap[part] = nil
                playerGhosts[plr] = nil
                pcall(function()
                    part:Destroy()
                end)
            end
            if plr then
                queryCacheAt[plr] = nil
            end
        end

        local function clearAll()
            for plr in pairs(playerGhosts) do
                destroyGhost(plr)
            end
            for part in pairs(ghostMap) do
                ghostMap[part] = nil
                pcall(function()
                    part:Destroy()
                end)
            end
            history = {}
            pendingRedirects = {}
            pendingUseGhost = nil
            queryCacheAt = {}
            local folder = Workspace:FindFirstChild(FOLDER_NAME)
            if folder then
                folder:ClearAllChildren()
            end
        end

        local function sampleAt(hist, targetT)
            if not hist or #hist == 0 then
                return nil
            end
            local prev = hist[1]
            for i = 1, #hist do
                local s = hist[i]
                if s.t <= targetT then
                    prev = s
                else
                    local span = s.t - prev.t
                    local alpha = span > 1e-4 and math.clamp((targetT - prev.t) / span, 0, 1) or 0
                    return {
                        cf = prev.cf:Lerp(s.cf, alpha),
                        size = prev.size:Lerp(s.size, alpha),
                    }
                end
            end
            return { cf = prev.cf, size = prev.size }
        end

        local function sourcePart(char)
            local hitbox = char:FindFirstChild('Hitbox')
            if hitbox and hitbox:IsA('BasePart') then
                return hitbox
            end
            return char:FindFirstChild('HumanoidRootPart')
        end

        local function ensureGhost(plr, sample)
            local part = playerGhosts[plr]
            local created = false
            if not (part and part.Parent) then
                created = true
                part = Instance.new('Part')
                part.Name = 'BT_' .. plr.Name
                part.Anchored = true
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.Massless = true
                part.Transparency = 1
                part.Material = Enum.Material.SmoothPlastic
                part.Parent = getFolder()

                local box = Instance.new('BoxHandleAdornment')
                box.Name = 'Outline'
                box.Adornee = part
                box.AlwaysOnTop = true
                box.ZIndex = 5
                box.Parent = part

                local sel = Instance.new('SelectionBox')
                sel.Name = 'Edge'
                sel.Adornee = part
                sel.LineThickness = 0.03
                sel.Parent = part

                playerGhosts[plr] = part
            end
            local hrp = plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
            ghostMap[part] = hrp
            part.Size = sample.size
            part.CFrame = sample.cf
            local color = (BT.Color and BT.Color.Value) or Color3.fromRGB(0, 220, 255)
            local show = BT.ShowGhosts and BT.ShowGhosts.Value == true
            local box = part:FindFirstChild('Outline')
            if box then
                box.Size = part.Size
                box.Color3 = color
                box.Transparency = show and 0.55 or 1
                box.Adornee = part
            end
            local sel = part:FindFirstChild('Edge')
            if sel then
                sel.Color3 = color
                sel.Transparency = show and 0.15 or 1
                sel.Adornee = part
            end
            local live = resolveLivePart(hrp)
            local nowQ = os.clock()
            local lastQ = queryCacheAt[plr] or 0
            if created or (nowQ - lastQ) >= QUERY_REFRESH then
                queryCacheAt[plr] = nowQ
                part.CanQuery = wouldRegister(muzzleOrigin(), live, plr)
            end
            return part
        end

        local function pushHistory(plr, source)
            local now = os.clock()
            local hist = history[plr]
            if not hist then
                hist = {}
                history[plr] = hist
            end
            hist[#hist + 1] = { t = now, cf = source.CFrame, size = source.Size }
            local delay = math.clamp(tonumber(BT.Delay and BT.Delay.Value) or 200, 50, 400) / 1000
            local cutoff = now - delay - 0.25
            while #hist > 0 and hist[1].t < cutoff do
                table.remove(hist, 1)
            end
            while #hist > 48 do
                table.remove(hist, 1)
            end
        end

        local function tickGhosts()
            if not isActive() then
                if next(playerGhosts) then
                    clearAll()
                end
                return
            end
            local delay = math.clamp(tonumber(BT.Delay and BT.Delay.Value) or 200, 50, 400) / 1000
            local now = os.clock()
            local seen = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if isPlayerValid(plr) then
                    seen[plr] = true
                    local source = sourcePart(plr.Character)
                    if source and source:IsA('BasePart') then
                        pushHistory(plr, source)
                        local sample = sampleAt(history[plr], now - delay)
                        if sample then
                            ensureGhost(plr, sample)
                        end
                    end
                end
            end
            for plr in pairs(playerGhosts) do
                if not seen[plr] then
                    destroyGhost(plr)
                    history[plr] = nil
                end
            end
        end

        -- Описание: Проверяет, попала ли позиция/деталь в ghost-модель бэктрека и возвращает живую часть игрока
        local function resolveFromPart(hit)
            if typeof(hit) ~= 'Instance' then
                return nil, nil, nil
            end
            local hrp = ghostMap[hit]
            if not hrp and type(hit.Name) == 'string' and string.sub(hit.Name, 1, 3) == 'BT_' then
                local plr = Players:FindFirstChild(string.sub(hit.Name, 4))
                hrp = plr and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
            end
            if not hrp or not hrp.Parent then
                return nil, nil, nil
            end
            local plr = Players:GetPlayerFromCharacter(hrp.Parent)
            return plr, resolveLivePart(hrp), hit
        end

        local function getBacktrackChance()
            local chanceObj = (BT and BT.Chance) or (BT and BT.SilentChance) or (BT and BT.TriggerChance)
            return math.clamp(tonumber(chanceObj and chanceObj.Value) or 0, 0, 100)
        end

        -- Описание: Рассчитывает процентную вероятность использования фантома для Silent Aim
        local function peekUseGhost()
            if pendingUseGhost ~= nil then
                return pendingUseGhost
            end
            if not isActive() then
                pendingUseGhost = false
                return false
            end
            local chance = getBacktrackChance()
            if chance <= 0 then
                pendingUseGhost = false
                return false
            end
            if chance >= 100 then
                pendingUseGhost = true
                return true
            end
            pendingUseGhost = math.random(1, 100) <= chance
            return pendingUseGhost
        end

        -- Описание: Расчёт процента вероятности использования фантома для Triggerbot
        local function peekTriggerUseGhost()
            if not isActive() then
                return false
            end
            local chance = getBacktrackChance()
            if chance <= 0 then
                return false
            end
            if chance >= 100 then
                return true
            end
            return math.random(1, 100) <= chance
        end

        -- Описание: Возвращает результат проверки Silent Chance и обнуляет временный кэш выстрела
        local function consumeUseGhost()
            local v = peekUseGhost()
            pendingUseGhost = nil
            return v
        end

        -- Описание: Сбрасывает текущий кэш шанса бэктрека
        local function clearPending()
            pendingUseGhost = nil
        end

        -- Описание: Находит ближайшего ghost-фантома игрока в пределах FOV, в которого гарантированно зарегистрируется урон
        local function pickGhostInFov(origin, inFovFn)
            if not isActive() then
                return nil, nil, nil
            end
            if typeof(origin) ~= 'Vector3' then
                return nil, nil, nil
            end
            local bestDist, bestAim, bestHrp, bestPlr = math.huge, nil, nil, nil
            for plr, part in pairs(playerGhosts) do
                if part and part.Parent and isPlayerValid(plr) then
                    local live = resolveLivePart(ghostMap[part] or (plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')))
                    if live and wouldRegister(origin, live, plr) then
                        local dist, inFov = inFovFn(part.Position)
                        if inFov and dist and dist < bestDist then
                            bestDist = dist
                            bestAim = part.Position
                            bestHrp = ghostMap[part]
                            bestPlr = plr
                        end
                    end
                end
            end
            return bestAim, bestHrp, bestPlr
        end

        local function snapPackedShot(origin, range, count, hits, ends)
            if not pendingRedirects or #pendingRedirects < 1 then
                return
            end
            local n = math.max(tonumber(count) or 0, #pendingRedirects)
            if hits then
                n = math.max(n, #hits)
            end
            local pelletCount = math.max(1, math.floor(tonumber(count) or n))
            for i = 1, n do
                local entry = pendingRedirects[i]
                local live = type(entry) == 'table' and entry.live or nil
                local forceMiss = type(entry) == 'table' and entry.miss == true
                if forceMiss or not wouldRegister(origin, live, nil) then
                    continue
                end
                -- Shotgun ends stay near-muzzle unique; never collapse all pellets to live.Position.
                if hits then
                    if pelletCount > 1 and ends and typeof(ends[i]) == 'Vector3' and typeof(origin) == 'Vector3' then
                        local spreadHit = PSilentApi and PSilentApi.hitAlongPellet
                        if type(spreadHit) == 'function' then
                            hits[i] = spreadHit(origin, ends[i], live.Position)
                        else
                            hits[i] = live.Position
                        end
                    else
                        hits[i] = live.Position
                    end
                end
                if pelletCount <= 1 and ends then
                    ends[i] = live.Position
                end
            end
        end

        local function applyRedirects(origin, range, count, hits, ends, hitInstances)
            local changed = false
            count = tonumber(count) or (hits and #hits) or 0
            local n = math.max(count, #pendingRedirects)
            if hitInstances then
                n = math.max(n, #hitInstances)
            end
            local pelletCount = math.max(1, math.floor(count > 0 and count or n))
            for i = 1, n do
                local entry = pendingRedirects[i]
                local live = type(entry) == 'table' and entry.live or nil
                local forceMiss = type(entry) == 'table' and entry.miss == true
                local isGhost = hitInstances and typeof(hitInstances[i]) == 'Instance' and ghostMap[hitInstances[i]] ~= nil
                if not live and isGhost then
                    local _, resolved = resolveFromPart(hitInstances[i])
                    live = resolved
                end
                if not entry and not isGhost then
                    continue
                end
                if forceMiss or not wouldRegister(origin, live, nil) then
                    if hitInstances then
                        hitInstances[i] = nil
                    end
                    changed = true
                    continue
                end
                if hitInstances then
                    hitInstances[i] = live
                end
                if hits then
                    if pelletCount > 1 and ends and typeof(ends[i]) == 'Vector3' and typeof(origin) == 'Vector3' then
                        local spreadHit = PSilentApi and PSilentApi.hitAlongPellet
                        if type(spreadHit) == 'function' then
                            hits[i] = spreadHit(origin, ends[i], live.Position)
                        else
                            hits[i] = live.Position
                        end
                    else
                        hits[i] = live.Position
                    end
                end
                -- Single pellet can snap end; shotgun keeps unique near-muzzle ends.
                if pelletCount <= 1 and ends then
                    ends[i] = live.Position
                end
                changed = true
            end
            return changed
        end

        local function setupHooks()
            local Modules = ReplicatedStorage:FindFirstChild('Modules')
            if not Modules then
                return
            end
            local GunModuleInst = Modules:FindFirstChild('GunModule')
            local GunNetInst = Modules:FindFirstChild('GunNet')
            if GunModuleInst and not hookedShoot then
                pcall(function()
                    local GunModule = require(GunModuleInst)
                    if type(GunModule) ~= 'table' or type(GunModule.shoot) ~= 'function' then
                        return
                    end
                    local oldShoot = GunModule.shoot
                    local wrap = function(args)
                        local results = table.pack(oldShoot(args))
                        local hitInst = results[2]
                        local plr, live = resolveFromPart(hitInst)
                        if not live then
                            return table.unpack(results, 1, results.n)
                        end
                        local origin = nil
                        if type(args) == 'table' then
                            origin = args.ForcedOrigin
                            if typeof(origin) ~= 'Vector3' then
                                origin = muzzleOrigin()
                            end
                        end
                        if wouldRegister(origin, live, plr) then
                            results[2] = live
                            results[1] = live.Position
                            table.insert(pendingRedirects, { live = live })
                        else
                            table.insert(pendingRedirects, { miss = true })
                        end
                        return table.unpack(results, 1, results.n)
                    end
                    if type(hookfunction) == 'function' then
                        oldShoot = hookfunction(GunModule.shoot, wrap)
                    else
                        GunModule.shoot = wrap
                    end
                    hookedShoot = true
                end)
            end
            if not GunNetInst then
                return
            end
            pcall(function()
                local GunNet = require(GunNetInst)
                if type(GunNet) ~= 'table' then
                    return
                end
                local gunFire = type(GunNet.getFireRemote) == 'function' and GunNet.getFireRemote() or nil
                if gunFire and not hookedFire then
                    local function patchOutgoingFire(packed, hitInstances)
                        local unpacked = typeof(packed) == 'buffer' and type(GunNet.unpackFire) == 'function' and GunNet.unpackFire(packed) or nil
                        if not unpacked then
                            if type(hitInstances) == 'table' then
                                for i, hit in pairs(hitInstances) do
                                    local entry = pendingRedirects[i]
                                    if ghostMap[hit] or (type(entry) == 'table' and (entry.miss or entry.live)) then
                                        hitInstances[i] = nil
                                    end
                                end
                            end
                            pendingRedirects = {}
                            return packed, hitInstances
                        end
                        local did = applyRedirects(
                            unpacked.origin,
                            unpacked.range,
                            unpacked.bulletcount,
                            unpacked.hits,
                            unpacked.ends,
                            hitInstances
                        )
                        local packFn = (PSilentApi and PSilentApi.rawPackFire) or GunNet.packFire
                        if did and type(packFn) == 'function' then
                            packed = packFn(
                                unpacked.origin,
                                unpacked.range,
                                unpacked.bulletcount,
                                unpacked.hits,
                                unpacked.ends
                            )
                        end
                        pendingRedirects = {}
                        return packed, hitInstances, unpacked
                    end

                    local function fireGun(invoke, self, packed, hitInstances, effect)
                        if sendingFire then
                            return invoke(self, packed, hitInstances, effect)
                        end
                        sendingFire = true
                        local unpacked = nil
                        local okPatch, err = pcall(function()
                            packed, hitInstances, unpacked = patchOutgoingFire(packed, hitInstances)
                        end)
                        if not okPatch then
                            sendingFire = false
                            error(err)
                        end
                        if type(unpacked) == 'table' and PSilentApi and type(PSilentApi.syncFireEffect) == 'function' then
                            effect = PSilentApi.syncFireEffect(unpacked, effect)
                        elseif effect ~= nil
                            and typeof(packed) == 'buffer'
                            and type(GunNet.unpackFire) == 'function'
                            and PSilentApi
                            and type(PSilentApi.syncFireEffect) == 'function'
                        then
                            local fallbackUnpacked = GunNet.unpackFire(packed)
                            if fallbackUnpacked then
                                effect = PSilentApi.syncFireEffect(fallbackUnpacked, effect)
                            end
                        end
                        local results = table.pack(pcall(invoke, self, packed, hitInstances, effect))
                        sendingFire = false
                        if not results[1] then
                            error(results[2])
                        end
                        return table.unpack(results, 2, results.n)
                    end

                    if type(hookfunction) == 'function' then
                        local oldFireServer
                        oldFireServer = hookfunction(gunFire.FireServer, function(self, packed, hitInstances, effect)
                            if self == gunFire then
                                return fireGun(oldFireServer, self, packed, hitInstances, effect)
                            end
                            return oldFireServer(self, packed, hitInstances, effect)
                        end)
                    end
                    hookedFire = true
                end
            end)
        end

        -- Публичный API бэктрека с описанием функций
        BacktrackApi.isActive = isActive -- Описание: Активен ли бэктрек
        BacktrackApi.muzzleOrigin = muzzleOrigin -- Описание: Возвращает позицию дула оружия
        BacktrackApi.wouldRegister = wouldRegister -- Описание: Проверка возможности попадания
        BacktrackApi.resolveFromPart = resolveFromPart -- Описание: Определение игрока по ghost-части
        BacktrackApi.pickGhostInFov = pickGhostInFov -- Описание: Поиск ghost-цели в FOV
        BacktrackApi.peekUseGhost = peekUseGhost -- Описание: Проверка шанса Silent Ghost Chance
        BacktrackApi.peekTriggerUseGhost = peekTriggerUseGhost -- Описание: Проверка шанса Trigger Ghost Chance
        BacktrackApi.consumeUseGhost = consumeUseGhost -- Описание: Применение Silent Ghost Chance
        BacktrackApi.clearPending = clearPending -- Описание: Очистка временного состояния выстрела
        BacktrackApi.hasPendingRedirects = function()
            return type(pendingRedirects) == 'table' and #pendingRedirects > 0
        end
        BacktrackApi.snapPackedShot = snapPackedShot -- Описание: Корректировка концов патронов дробных выстрелов
        BacktrackApi.clearAll = clearAll -- Описание: Очистка всех созданных фантомов
        BacktrackApi.ghostMap = ghostMap

        safeConnect(RunService.Heartbeat, function()
            if not hookedShoot or not hookedFire then
                setupHooks()
            end
            tickGhosts()
        end)
        safeConnect(Players.PlayerRemoving, function(plr)
            destroyGhost(plr)
            history[plr] = nil
        end)
        if Library and type(Library.OnUnload) == 'function' then
            Library:OnUnload(function()
                clearAll()
            end)
        end

        if type(runLaterFn) == 'function' then
            runLaterFn(0, setupHooks)
        else
            setupHooks()
        end
    end)(State.Backtrack, safeConnect, Library, isSharedTargetRole, isSharedFriendRole, runLater)
    end
end
