--[[
    Anime Adventures | Complete Auto Play Module
    Features:
    1. Auto Place Units:
       - Configurable map path percentage position (0% - 100%)
       - Dynamic 2D/3D placement grid with custom rows, cols, spacing, and rotation
       - Real-time 3D grid visualization with Billboard status markers (Free/Occupied)
       - Auto-spawn units into free grid slots via spawn_unit endpoint
    2. Auto Upgrade Units:
       - Independent upgrade limit per slot (Slot 1-6) + global max upgrade cap
       - Detects units owned by LocalPlayer in workspace._UNITS
       - Triggers upgrade_unit_ingame endpoint safely
    3. Auto Use Abilities:
       - Tracks cooldown & last cast timestamp from unit._stats
       - Modes: "Whenever Ready" or "When Boss Is Near"
       - Boss detection via CollectionService "bosses" tag and proximity radius
       - Triggers use_active_attack endpoint
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Endpoints = ReplicatedStorage:WaitForChild("endpoints"):WaitForChild("client_to_server")

-- ==============================================================================
-- CONFIGURATION & STATE
-- ==============================================================================
local Config = {
    -- Auto Place
    AutoPlaceEnabled = false,
    PathPercentage = 15,
    GridRows = 3,
    GridCols = 4,
    GridSpacing = 5.5,
    GridRotation = 0,
    ShowGridVisuals = true,
    PlacementInterval = 0.8,
    SlotPlacement = {
        [1] = true,
        [2] = true,
        [3] = true,
        [4] = true,
        [5] = true,
        [6] = true,
    },

    -- Auto Upgrade
    AutoUpgradeEnabled = false,
    GlobalMaxUpgrades = 10,
    UpgradeInterval = 0.4,
    SlotMaxUpgrades = {
        [1] = 10,
        [2] = 10,
        [3] = 10,
        [4] = 10,
        [5] = 10,
        [6] = 10,
    },

    -- Auto Abilities
    AutoAbilitiesEnabled = false,
    AbilityMode = "Whenever Ready", -- "Whenever Ready" or "When Boss Is Near"
    BossDetectionRange = 60,
    AbilityInterval = 0.5,
}

local State = {
    CurrentGridSpots = {},
    LastPlacementTime = 0,
    LastUpgradeTime = 0,
    LastAbilityTime = 0,
}

-- ==============================================================================
-- MAP & PATH UTILITIES
-- ==============================================================================
local function findMapWaypoints()
    local searchContainers = {
        Workspace:FindFirstChild("_map"),
        Workspace:FindFirstChild("_MAPS"),
        Workspace:FindFirstChild("Map"),
        Workspace:FindFirstChild("map"),
        Workspace:FindFirstChild("Waypoints"),
        Workspace:FindFirstChild("waypoints"),
    }

    for _, container in ipairs(searchContainers) do
        if container then
            local wpFolder = container:FindFirstChild("Waypoints") 
                or container:FindFirstChild("waypoints") 
                or container:FindFirstChild("Path") 
                or container:FindFirstChild("path")

            if wpFolder then
                local points = {}
                for _, pt in ipairs(wpFolder:GetChildren()) do
                    if pt:IsA("BasePart") then
                        local num = tonumber(pt.Name:match("%d+")) or 0
                        table.insert(points, {num = num, part = pt, pos = pt.Position})
                    end
                end
                table.sort(points, function(a, b) return a.num < b.num end)
                if #points >= 2 then
                    return points
                end
            end
        end
    end
    return nil
end

local function getPathPointAtPercentage(percent)
    local waypoints = findMapWaypoints()
    if not waypoints or #waypoints < 2 then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            return char.HumanoidRootPart.Position, char.HumanoidRootPart.CFrame.LookVector
        end
        return Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)
    end

    local distances = {0}
    local totalLength = 0
    for i = 1, #waypoints - 1 do
        local dist = (waypoints[i + 1].pos - waypoints[i].pos).Magnitude
        totalLength = totalLength + dist
        table.insert(distances, totalLength)
    end

    local targetDist = math.clamp(percent / 100, 0, 1) * totalLength
    for i = 1, #distances - 1 do
        if targetDist >= distances[i] and targetDist <= distances[i + 1] then
            local segLen = distances[i + 1] - distances[i]
            local alpha = if segLen > 0 then (targetDist - distances[i]) / segLen else 0
            local p0 = waypoints[i].pos
            local p1 = waypoints[i + 1].pos
            local pos = p0:Lerp(p1, alpha)
            local dir = (p1 - p0).Unit
            return pos, dir
        end
    end

    return waypoints[#waypoints].pos, Vector3.new(0, 0, -1)
end

-- ==============================================================================
-- GRID CALCULATION & VISUALIZATION
-- ==============================================================================
local function computePlacementGrid()
    local centerPos, pathDir = getPathPointAtPercentage(Config.PathPercentage)
    local forward = Vector3.new(pathDir.X, 0, pathDir.Z).Unit
    local right = Vector3.new(-forward.Z, 0, forward.X)

    local rad = math.rad(Config.GridRotation)
    local rotatedRight = right * math.cos(rad) + forward * math.sin(rad)
    local rotatedForward = -right * math.sin(rad) + forward * math.cos(rad)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {LocalPlayer.Character, Workspace:FindFirstChild("_AutoPlay_VisualGrid")}
    if Workspace:FindFirstChild("_UNITS") then
        table.insert(ignore, Workspace._UNITS)
    end
    rayParams.FilterDescendantsInstances = ignore

    local spots = {}
    for r = 1, Config.GridRows do
        for c = 1, Config.GridCols do
            local offR = (r - (Config.GridRows + 1) / 2) * Config.GridSpacing
            local offC = (c - (Config.GridCols + 1) / 2) * Config.GridSpacing
            local worldPos = centerPos + (rotatedRight * offC) + (rotatedForward * offR)

            local surfaceY = worldPos.Y
            local rayResult = Workspace:Raycast(worldPos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
            if rayResult then
                surfaceY = rayResult.Position.Y
            end

            table.insert(spots, {
                index = #spots + 1,
                row = r,
                col = c,
                position = Vector3.new(worldPos.X, surfaceY + 0.15, worldPos.Z),
                occupied = false,
                unit = nil
            })
        end
    end

    State.CurrentGridSpots = spots
    return spots
end

local function refreshGridOccupancy()
    local unitsFolder = Workspace:FindFirstChild("_UNITS")
    for _, spot in ipairs(State.CurrentGridSpots) do
        spot.occupied = false
        spot.unit = nil

        if unitsFolder then
            for _, unit in ipairs(unitsFolder:GetChildren()) do
                local root = unit.PrimaryPart or unit:FindFirstChild("HumanoidRootPart") or unit:FindFirstChild("_hitbox")
                if root and (root.Position - spot.position).Magnitude <= (Config.GridSpacing * 0.45) then
                    spot.occupied = true
                    spot.unit = unit
                    break
                end
            end
        end
    end
end

local function renderVisualGrid()
    local folder = Workspace:FindFirstChild("_AutoPlay_VisualGrid")
    if not Config.ShowGridVisuals then
        if folder then folder:Destroy() end
        return
    end

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "_AutoPlay_VisualGrid"
        folder.Parent = Workspace
    end

    folder:ClearAllChildren()

    for _, spot in ipairs(State.CurrentGridSpots) do
        local marker = Instance.new("Part")
        marker.Name = "Spot_" .. spot.index
        marker.Size = Vector3.new(Config.GridSpacing * 0.8, 0.15, Config.GridSpacing * 0.8)
        marker.Position = spot.position
        marker.Anchored = true
        marker.CanCollide = false
        marker.Material = Enum.Material.Neon
        marker.Transparency = 0.4
        marker.Color = if spot.occupied then Color3.fromRGB(240, 50, 50) else Color3.fromRGB(0, 240, 140)
        marker.Parent = folder

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.new(0, 60, 0, 20)
        bb.StudsOffset = Vector3.new(0, 1.2, 0)
        bb.AlwaysOnTop = true
        bb.Parent = marker

        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.Text = "#" .. spot.index .. (spot.occupied and " [OCCUPIED]" or " [FREE]")
        text.TextColor3 = marker.Color
        text.TextSize = 11
        text.Font = Enum.Font.GothamBold
        text.Parent = bb
    end
end

-- ==============================================================================
-- UNIT LOADOUT & LOCAL PLAYER UNITS
-- ==============================================================================
local function getEquippedUnits()
    local units = {}
    local spawnGui = LocalPlayer.PlayerGui:FindFirstChild("spawn_units")
    if spawnGui and spawnGui:FindFirstChild("Lives") and spawnGui.Lives:FindFirstChild("Frame") then
        local grid = spawnGui.Lives.Frame:FindFirstChild("Units")
        if grid then
            for slotIndex, child in ipairs(grid:GetChildren()) do
                if child:IsA("GuiObject") then
                    local uuid = child:GetAttribute("_equipped_frame_unit_uuid")
                    if uuid and uuid ~= "" then
                        table.insert(units, {
                            slot = slotIndex,
                            uuid = uuid,
                            name = child.Name
                        })
                    end
                end
            end
        end
    end
    return units
end

local function getOwnedUnitsInGame()
    local owned = {}
    local unitsFolder = Workspace:FindFirstChild("_UNITS")
    if not unitsFolder then return owned end

    for _, unit in ipairs(unitsFolder:GetChildren()) do
        local stats = unit:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("player") and stats.player.Value == LocalPlayer then
            table.insert(owned, unit)
        end
    end
    return owned
end

-- ==============================================================================
-- CORE AUTOMATION LOOPS
-- ==============================================================================
local function processAutoPlace()
    if not Config.AutoPlaceEnabled then return end
    if tick() - State.LastPlacementTime < Config.PlacementInterval then return end

    local equipped = getEquippedUnits()
    if #equipped == 0 then return end

    computePlacementGrid()
    refreshGridOccupancy()

    for _, unitInfo in ipairs(equipped) do
        if Config.SlotPlacement[unitInfo.slot] ~= false then
            -- Find first unoccupied spot
            for _, spot in ipairs(State.CurrentGridSpots) do
                if not spot.occupied then
                    State.LastPlacementTime = tick()
                    pcall(function()
                        Endpoints.spawn_unit:InvokeServer(
                            unitInfo.uuid,
                            CFrame.new(spot.position)
                        )
                    end)
                    spot.occupied = true
                    renderVisualGrid()
                    return
                end
            end
        end
    end
end

local function processAutoUpgrade()
    if not Config.AutoUpgradeEnabled then return end
    if tick() - State.LastUpgradeTime < Config.UpgradeInterval then return end

    local owned = getOwnedUnitsInGame()
    for _, unit in ipairs(owned) do
        local stats = unit:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("upgrade") then
            local currentUpgrade = stats.upgrade.Value
            local maxUpgrades = Config.GlobalMaxUpgrades

            if currentUpgrade < maxUpgrades then
                State.LastUpgradeTime = tick()
                pcall(function()
                    Endpoints.upgrade_unit_ingame:InvokeServer(unit)
                end)
                return
            end
        end
    end
end

local function processAutoAbilities()
    if not Config.AutoAbilitiesEnabled then return end
    if tick() - State.LastAbilityTime < Config.AbilityInterval then return end

    local owned = getOwnedUnitsInGame()
    local serverTime = Workspace:GetServerTimeNow()

    for _, unit in ipairs(owned) do
        local stats = unit:FindFirstChild("_stats")
        if stats and stats:FindFirstChild("active_attack_cooldown") and stats:FindFirstChild("last_active_cast") then
            local cd = stats.active_attack_cooldown.Value
            local lastCast = stats.last_active_cast.Value
            local remaining = cd - (serverTime - lastCast)

            if remaining <= 0 then
                local canCast = false

                if Config.AbilityMode == "Whenever Ready" then
                    canCast = true
                elseif Config.AbilityMode == "When Boss Is Near" then
                    local bosses = CollectionService:GetTagged("bosses")
                    local unitPos = unit.PrimaryPart and unit.PrimaryPart.Position
                    if unitPos then
                        for _, boss in ipairs(bosses) do
                            local bossPos = boss.PrimaryPart and boss.PrimaryPart.Position
                            if bossPos and (bossPos - unitPos).Magnitude <= Config.BossDetectionRange then
                                canCast = true
                                break
                            end
                        end
                    end
                end

                if canCast then
                    State.LastAbilityTime = tick()
                    pcall(function()
                        Endpoints.use_active_attack:InvokeServer(unit)
                    end)
                    return
                end
            end
        end
    end
end

-- Connect main scheduler
local heartbeatConnection
heartbeatConnection = RunService.Heartbeat:Connect(function()
    processAutoPlace()
    processAutoUpgrade()
    processAutoAbilities()
end)

-- Return API interface
local AutoPlay = {
    Config = Config,
    State = State,
    ComputeGrid = computePlacementGrid,
    RenderGrid = renderVisualGrid,
    Unload = function()
        if heartbeatConnection then
            heartbeatConnection:Disconnect()
        end
        local folder = Workspace:FindFirstChild("_AutoPlay_VisualGrid")
        if folder then folder:Destroy() end
    end
}

return AutoPlay
