-- UIToolbox
-- Core.lua: Addon initialization, SavedVariables, and event dispatch.

local ADDON_NAME = "UIToolbox"

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
        enabled         = true,
        hideHealthBar   = false,
        hideClassResources = false,
        restylePowerBar = false,
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

local UIToolbox = CreateFrame("Frame", ADDON_NAME)
_G[ADDON_NAME] = UIToolbox

UIToolbox.modules = {}

-- Register a module to receive OnZoneChanged calls.
-- module must have an OnZoneChanged(inInstance, instanceType) method.
function UIToolbox:RegisterModule(module)
    table.insert(self.modules, module)
end

-- Internal event handler -- dispatches to named methods on self.
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

    -- Migrate legacy key name used before this became an ObjectivesTracker feature.
    if UIToolboxDB.objectivesTrackerDamageMeter == nil and UIToolboxDB.trackerEmbed ~= nil then
        UIToolboxDB.objectivesTrackerDamageMeter = CopyTable(UIToolboxDB.trackerEmbed)
    end

    ApplyDefaults(UIToolboxDB, DEFAULTS)
    self.db = UIToolboxDB

    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function UIToolbox:PLAYER_ENTERING_WORLD()
    local inInstance, instanceType = IsInInstance()
    for _, module in ipairs(self.modules) do
        if module.OnZoneChanged then
            module:OnZoneChanged(inInstance, instanceType)
        end
    end
end
