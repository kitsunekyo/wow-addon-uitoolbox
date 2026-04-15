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
                    -- Do NOT call ObjectiveTrackerManager:UpdateAll() directly here.
                    -- This set callback fires from a plain addon SetScript("OnClick")
                    -- handler — a fully tainted execution context.  Calling UpdateAll()
                    -- from there runs the entire tracker layout chain (sort by uiOrder,
                    -- LayoutContents, SetHeightModifier, UIParent_ManageFramePositions)
                    -- with taint, causing "secret number value" errors downstream.
                    -- Instead, signal the OnUpdate poller in DamageMeterEmbed to call
                    -- UpdateAll() from the clean C++ game loop context.
                    EnhancedInterfaceObjectivesTrackerDamageMeterModule.RequestUpdateAll()
                end
            end,
        },
    },
})
