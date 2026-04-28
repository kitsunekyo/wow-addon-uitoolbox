local ADDON_NAME = "EnhancedInterface"

local DEFAULTS = {
    autoCollapse = {
        enabled = true,
        sections = {
            campaign    = true,
            quests      = true,
            worldQuests = true,
        },
    },
    objectivesTrackerDamageMeter = {
        enabled = false,
    },
    nameplateScale = {
        factor = 1.0,
    },
    personalResourceDisplay = {
        hideHealthBar      = false,
        hideClassResources = false,
        restylePowerBar    = false,
        hideWhenMounted    = false,
    },
    powerValueDisplay = {
        enabled = false,
    },
    sharedBars = {
        bars = {},
    },
}

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

local EnhancedInterface = CreateFrame("Frame", ADDON_NAME)
_G[ADDON_NAME] = EnhancedInterface

EnhancedInterface.modules = {}

function EnhancedInterface:RegisterModule(module)
    table.insert(self.modules, module)
end

EnhancedInterface:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

EnhancedInterface:RegisterEvent("ADDON_LOADED")

function EnhancedInterface:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    EnhancedInterfaceDB = EnhancedInterfaceDB or {}

    if EnhancedInterfaceDB.objectivesTrackerDamageMeter == nil and EnhancedInterfaceDB.trackerEmbed ~= nil then
        EnhancedInterfaceDB.objectivesTrackerDamageMeter = CopyTable(EnhancedInterfaceDB.trackerEmbed)
    end

    if EnhancedInterfaceDB.powerValueDisplay == nil and EnhancedInterfaceDB.runicPowerDisplay ~= nil then
        EnhancedInterfaceDB.powerValueDisplay = CopyTable(EnhancedInterfaceDB.runicPowerDisplay)
    end

    ApplyDefaults(EnhancedInterfaceDB, DEFAULTS)
    self.db = EnhancedInterfaceDB

    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function EnhancedInterface:PLAYER_ENTERING_WORLD()
    -- Defer module frame mutations out of this event to avoid taint propagation.
    local inInstance, instanceType = IsInInstance()
    self._pendingZoneChanged = { inInstance, instanceType }
end

EnhancedInterface:SetScript("OnUpdate", function(self)
    if self._pendingZoneChanged then
        local args = self._pendingZoneChanged
        self._pendingZoneChanged = nil
        for _, module in ipairs(self.modules) do
            if module.OnZoneChanged then
                module:OnZoneChanged(args[1], args[2])
            end
        end
    end
end)
