-- EnhancedInterface
-- modules/ObjectivesTracker/features/AutoCollapse/EditModeIntegration.lua
--
-- Registers Auto-Collapse settings with the shared EditModeCompanionDialog so they
-- appear in the "EnhancedInterface" companion panel when the player selects the
-- Objective Tracker frame in Edit Mode.

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        return systemFrame.system == Enum.EditModeSystem.ObjectiveTracker
    end,

    rows = {
        {
            type    = "checkbox",
            label   = "Auto-collapse in instances",
            tooltip = "Automatically collapses objective tracker sections when entering " ..
                      "an instance. Restores them when you leave.",
            get = function()
                return EnhancedInterface.db.autoCollapse.enabled
            end,
            set = function(value)
                EnhancedInterface.db.autoCollapse.enabled = value
            end,
        },
        {
            type    = "checkbox",
            label   = "  Collapse: Campaign Quests",
            tooltip = "Collapse the Campaign Quests section when entering an instance.",
            get = function()
                return EnhancedInterface.db.autoCollapse.sections.campaign
            end,
            set = function(value)
                EnhancedInterface.db.autoCollapse.sections.campaign = value
            end,
        },
        {
            type    = "checkbox",
            label   = "  Collapse: Regular Quests",
            tooltip = "Collapse the Regular Quests section when entering an instance.",
            get = function()
                return EnhancedInterface.db.autoCollapse.sections.quests
            end,
            set = function(value)
                EnhancedInterface.db.autoCollapse.sections.quests = value
            end,
        },
        {
            type    = "checkbox",
            label   = "  Collapse: World Quests",
            tooltip = "Collapse the World Quests section when entering an instance.",
            get = function()
                return EnhancedInterface.db.autoCollapse.sections.worldQuests
            end,
            set = function(value)
                EnhancedInterface.db.autoCollapse.sections.worldQuests = value
            end,
        },
    },
})
