EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
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
                    -- Set callbacks run tainted; defer UpdateAll via module poller.
                    EnhancedInterfaceObjectivesTrackerDamageMeterModule.RequestUpdateAll()
                end
            end,
        },
    },
})
