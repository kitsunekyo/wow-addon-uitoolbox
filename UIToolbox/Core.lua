-- UIToolbox
-- Core.lua: Addon initialization, SavedVariables, and event dispatch.

local ADDON_NAME = "UIToolbox"

-- Default settings. Merged with SavedVariables on load so new keys are always present.
local DEFAULTS = {
    trackerCollapse = {
        enabled = true,
        instanceTypes = {
            party    = true,  -- Dungeons
            raid     = true,  -- Raids
            pvp      = true,  -- Battlegrounds
            arena    = true,  -- Arenas
            scenario = true,  -- Scenarios
        },
        sections = {
            campaign    = true,
            quests      = true,
            worldQuests = true,
        },
    },
    damageMeterDrag = {
        enabled = false,  -- opt-in, off by default
    },
}

-- Recursively apply defaults: fill in any keys that are missing from target.
local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = CopyTable(v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            ApplyDefaults(target[k], v)
        end
    end
end

-- ============================================================
-- Addon frame and event dispatch
-- ============================================================

local UIToolbox = CreateFrame("Frame", ADDON_NAME)
_G[ADDON_NAME] = UIToolbox

UIToolbox.modules = {}

-- Register a module to receive OnZoneChanged calls.
function UIToolbox:RegisterModule(module)
    table.insert(self.modules, module)
end

-- Internal event handler — dispatches to named methods on self.
UIToolbox:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

UIToolbox:RegisterEvent("ADDON_LOADED")

function UIToolbox:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables and apply defaults for any missing keys.
    UIToolboxDB = UIToolboxDB or {}

    -- Migration: DBs created before instanceTypes was added have a stale
    -- enabled=false. Wipe just the trackerCollapse block so defaults re-apply.
    local tc = UIToolboxDB.trackerCollapse
    if tc and tc.instanceTypes == nil then
        UIToolboxDB.trackerCollapse = nil
    end

    ApplyDefaults(UIToolboxDB, DEFAULTS)
    self.db = UIToolboxDB

    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
end

local function DispatchZoneChanged()
    local inInstance, instanceType = IsInInstance()
    for _, module in ipairs(UIToolbox.modules) do
        if module.OnZoneChanged then
            module:OnZoneChanged(inInstance, instanceType)
        end
    end
end

-- Fires on loading-screen transitions (dungeons, raids, teleports).
function UIToolbox:PLAYER_ENTERING_WORLD()
    DispatchZoneChanged()
end

-- Fires on seamless zone transitions (delve entrances, subzones).
function UIToolbox:ZONE_CHANGED_NEW_AREA()
    DispatchZoneChanged()
end
