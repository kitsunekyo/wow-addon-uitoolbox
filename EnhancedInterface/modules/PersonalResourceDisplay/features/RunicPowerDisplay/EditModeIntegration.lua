-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/RunicPowerDisplay/EditModeIntegration.lua
--
-- Registers RunicPowerDisplay settings with the shared EditModeCompanionDialog
-- so they appear in the "EnhancedInterface" companion panel when the player
-- selects the PersonalResourceDisplayFrame in Edit Mode.

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        return systemFrame == PersonalResourceDisplayFrame
    end,

    rows = {
        {
            type    = "checkbox",
            label   = "Show power value",
            tooltip = "Displays the current power value (runic power, mana, rage, etc.) as a number on the power bar.",
            get = function()
                return EnhancedInterface.db.runicPowerDisplay.enabled
            end,
            set = function(value)
                if EnhancedInterfaceRunicPowerDisplayModule then
                    EnhancedInterfaceRunicPowerDisplayModule:SetEnabled(value)
                end
            end,
        },
    },
})
