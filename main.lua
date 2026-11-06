local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/werthjgwdfhuisdf/b2345v345b345b/refs/heads/main/library.lua"))()

-- Load the AutoPlay backend module
local AutoPlay = loadfile("autoplay.lua")()

local window = library:window({
    name = "Anime Adventures",
    suffix = "AutoPlay",
    gameInfo = "AA Automation Engine | Milenium UI"
})

window:seperator({name = "Automation"})

local place_tab, upgrade_tab, ability_tab = window:tab({
    name = "Auto Play",
    tabs = {"Auto Place", "Auto Upgrade", "Auto Abilities"}
})

-- ==============================================================================
-- SUB-TAB 1: AUTO PLACE & PLACEMENT GRID
-- ==============================================================================
do
    local col_left = place_tab:column({})
    local place_sec = col_left:section({name = "Placement Engine", default = true})

    place_sec:toggle({
        name = "Enable Auto Place",
        default = AutoPlay.Config.AutoPlaceEnabled,
        seperator = true,
        callback = function(enabled)
            AutoPlay.Config.AutoPlaceEnabled = enabled
            if enabled then
                AutoPlay.ComputeGrid()
                AutoPlay.RenderGrid()
            end
        end,
        info = "Automatically places equipped units into calculated grid positions."
    })

    place_sec:slider({
        name = "Path Position (%)",
        min = 0,
        max = 100,
        interval = 1,
        default = AutoPlay.Config.PathPercentage,
        suffix = "%",
        callback = function(val)
            AutoPlay.Config.PathPercentage = val
            AutoPlay.ComputeGrid()
            AutoPlay.RenderGrid()
        end,
        info = "Position along the enemy path (0% = Spawn, 100% = Base)."
    })

    place_sec:toggle({
        name = "Show Grid Visuals",
        default = AutoPlay.Config.ShowGridVisuals,
        seperator = true,
        callback = function(val)
            AutoPlay.Config.ShowGridVisuals = val
            AutoPlay.RenderGrid()
        end,
        info = "Renders 3D colored visual markers on the ground showing free & occupied spots."
    })

    local col_right = place_tab:column({})
    local grid_sec = col_right:section({name = "Grid Geometry", default = true})

    grid_sec:slider({
        name = "Grid Rows",
        min = 1,
        max = 6,
        interval = 1,
        default = AutoPlay.Config.GridRows,
        callback = function(val)
            AutoPlay.Config.GridRows = val
            AutoPlay.ComputeGrid()
            AutoPlay.RenderGrid()
        end
    })

    grid_sec:slider({
        name = "Grid Columns",
        min = 1,
        max = 6,
        interval = 1,
        default = AutoPlay.Config.GridCols,
        callback = function(val)
            AutoPlay.Config.GridCols = val
            AutoPlay.ComputeGrid()
            AutoPlay.RenderGrid()
        end
    })

    grid_sec:slider({
        name = "Grid Spacing (studs)",
        min = 3,
        max = 12,
        interval = 0.5,
        default = AutoPlay.Config.GridSpacing,
        suffix = " studs",
        callback = function(val)
            AutoPlay.Config.GridSpacing = val
            AutoPlay.ComputeGrid()
            AutoPlay.RenderGrid()
        end
    })

    grid_sec:slider({
        name = "Grid Rotation",
        min = 0,
        max = 360,
        interval = 5,
        default = AutoPlay.Config.GridRotation,
        suffix = "°",
        callback = function(val)
            AutoPlay.Config.GridRotation = val
            AutoPlay.ComputeGrid()
            AutoPlay.RenderGrid()
        end
    })
end

-- ==============================================================================
-- SUB-TAB 2: AUTO UPGRADE UNITS
-- ==============================================================================
do
    local col_left = upgrade_tab:column({})
    local upgrade_sec = col_left:section({name = "Upgrade Engine", default = true})

    upgrade_sec:toggle({
        name = "Enable Auto Upgrade",
        default = AutoPlay.Config.AutoUpgradeEnabled,
        seperator = true,
        callback = function(enabled)
            AutoPlay.Config.AutoUpgradeEnabled = enabled
        end,
        info = "Automatically upgrades your placed units when sufficient gold/yen is available."
    })

    upgrade_sec:slider({
        name = "Global Max Upgrades",
        min = 1,
        max = 15,
        interval = 1,
        default = AutoPlay.Config.GlobalMaxUpgrades,
        callback = function(val)
            AutoPlay.Config.GlobalMaxUpgrades = val
        end,
        info = "Maximum number of times each unit can be upgraded."
    })

    local col_right = upgrade_tab:column({})
    local slot_sec = col_right:section({name = "Per-Slot Limits", default = true})

    for slot = 1, 6 do
        slot_sec:slider({
            name = "Slot " .. slot .. " Max Upgrades",
            min = 0,
            max = 15,
            interval = 1,
            default = AutoPlay.Config.SlotMaxUpgrades[slot] or 10,
            callback = function(val)
                AutoPlay.Config.SlotMaxUpgrades[slot] = val
            end
        })
    end
end

-- ==============================================================================
-- SUB-TAB 3: AUTO USE ABILITIES
-- ==============================================================================
do
    local col_left = ability_tab:column({})
    local ability_sec = col_left:section({name = "Ability Engine", default = true})

    ability_sec:toggle({
        name = "Enable Auto Abilities",
        default = AutoPlay.Config.AutoAbilitiesEnabled,
        seperator = true,
        callback = function(enabled)
            AutoPlay.Config.AutoAbilitiesEnabled = enabled
        end,
        info = "Triggers unit active abilities automatically based on configured trigger conditions."
    })

    ability_sec:dropdown({
        name = "Trigger Condition",
        items = {"Whenever Ready", "When Boss Is Near"},
        default = AutoPlay.Config.AbilityMode,
        multi = false,
        seperator = true,
        callback = function(mode)
            AutoPlay.Config.AbilityMode = mode
        end,
        info = "Choose whether to fire abilities on cooldown or preserve them until a Boss approaches."
    })

    local col_right = ability_tab:column({})
    local detection_sec = col_right:section({name = "Boss Detection", default = true})

    detection_sec:slider({
        name = "Boss Proximity Range",
        min = 15,
        max = 150,
        interval = 5,
        default = AutoPlay.Config.BossDetectionRange,
        suffix = " studs",
        callback = function(val)
            AutoPlay.Config.BossDetectionRange = val
        end,
        info = "Activation radius around the unit when checking for tagged bosses."
    })
end

-- ==============================================================================
-- CONFIGURATION & PRESETS
-- ==============================================================================
library:init_config(window)
