-- UIToolbox
-- Core.lua: Addon initialization, SavedVariables, and event dispatch.

local ADDON_NAME = "UIToolbox"

-- Default settings. Merged with SavedVariables on load so new keys are always present.
local DEFAULTS = {
    trackerCollapse = {
        enabled = true,
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
UIToolbox:RegisterEvent("PLAYER_ENTERING_WORLD")

function UIToolbox:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables and apply defaults for any missing keys.
    UIToolboxDB = UIToolboxDB or {}
    ApplyDefaults(UIToolboxDB, DEFAULTS)
    self.db = UIToolboxDB

    self:UnregisterEvent("ADDON_LOADED")
end

function UIToolbox:PLAYER_ENTERING_WORLD()
    local inInstance, instanceType = IsInInstance()
    for _, module in ipairs(self.modules) do
        if module.OnZoneChanged then
            module:OnZoneChanged(inInstance, instanceType)
        end
    end
end
