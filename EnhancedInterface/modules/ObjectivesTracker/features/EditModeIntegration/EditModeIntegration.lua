-- EnhancedInterface
-- modules/ObjectivesTracker/features/EditModeIntegration/EditModeIntegration.lua
--
-- Registers Damage Meter settings with the shared EditModeCompanionDialog so they
-- appear in the "EnhancedInterface" companion panel when the player selects the
-- DamageMeter frame in Edit Mode.

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        -- DamageMeter is a singleton global (Enum.EditModeSystem.DamageMeter).
        -- Guard against the optional dependency not being loaded.
        return DamageMeter ~= nil and systemFrame == DamageMeter
    end,

    rows = {
        {
            type    = "checkbox",
            label   = "Show in Objective Tracker",
            tooltip = "Embeds the damage meter inside the Objective Tracker as a collapsible section.",
            get = function()
                return EnhancedInterface.db.objectivesTrackerDamageMeter.enabled
            end,
            set = function(value)
                EnhancedInterface.db.objectivesTrackerDamageMeter.enabled = value
                if EnhancedInterfaceObjectivesTrackerDamageMeterModule then
                    ObjectiveTrackerManager:UpdateAll()
                end
            end,
        },
    },
})
