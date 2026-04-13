-- Enhanced Interface
-- Core.lua: Addon initialization, SavedVariables, and event dispatch.

local ADDON_NAME = "EnhancedInterface"

-- Default settings. Merged with SavedVariables on load so new keys are always present.
local DEFAULTS = {
    -- ObjectivesTracker: AutoCollapse
    autoCollapse = {
        enabled = true,
        sections = {
            campaign    = true,
            quests      = true,
            worldQuests = true,
        },
    },
    -- ObjectivesTracker: DamageMeterEmbed
    objectivesTrackerDamageMeter = {
        enabled = false,
    },
    -- Nameplates: NameplateScale
    nameplateScale = {
        factor = 1.0,
    },
    -- PersonalResourceDisplay: bar styling
    personalResourceDisplay = {
        hideHealthBar      = false,
        hideClassResources = false,
        restylePowerBar    = false,
        hideWhenMounted    = false,
    },
    -- PersonalResourceDisplay: power value display (all classes)
    powerValueDisplay = {
        enabled = false,
    },
    -- ActionBars: SharedBars
    -- bars[barIndex] = { enabled = bool, slots = { [n] = { type = "spell"|"item"|"macro"|"equipmentset", id = number } } }
    -- bars is empty by default; entries are created the first time a bar is enabled.
    sharedBars = {
        bars = {},
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

local EnhancedInterface = CreateFrame("Frame", ADDON_NAME)
_G[ADDON_NAME] = EnhancedInterface

EnhancedInterface.modules = {}

-- Register a module to receive OnZoneChanged calls.
-- module must have an OnZoneChanged(inInstance, instanceType) method.
function EnhancedInterface:RegisterModule(module)
    table.insert(self.modules, module)
end

-- Internal event handler -- dispatches to named methods on self.
EnhancedInterface:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

EnhancedInterface:RegisterEvent("ADDON_LOADED")

function EnhancedInterface:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables and apply defaults for any missing keys.
    EnhancedInterfaceDB = EnhancedInterfaceDB or {}

    -- Migrate legacy key name used before this became an ObjectivesTracker feature.
    if EnhancedInterfaceDB.objectivesTrackerDamageMeter == nil and EnhancedInterfaceDB.trackerEmbed ~= nil then
        EnhancedInterfaceDB.objectivesTrackerDamageMeter = CopyTable(EnhancedInterfaceDB.trackerEmbed)
    end

    -- Migrate runicPowerDisplay → powerValueDisplay (renamed to be class-agnostic).
    if EnhancedInterfaceDB.powerValueDisplay == nil and EnhancedInterfaceDB.runicPowerDisplay ~= nil then
        EnhancedInterfaceDB.powerValueDisplay = CopyTable(EnhancedInterfaceDB.runicPowerDisplay)
    end

    ApplyDefaults(EnhancedInterfaceDB, DEFAULTS)
    self.db = EnhancedInterfaceDB

    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function EnhancedInterface:PLAYER_ENTERING_WORLD()
    local inInstance, instanceType = IsInInstance()
    for _, module in ipairs(self.modules) do
        if module.OnZoneChanged then
            module:OnZoneChanged(inInstance, instanceType)
        end
    end
end
