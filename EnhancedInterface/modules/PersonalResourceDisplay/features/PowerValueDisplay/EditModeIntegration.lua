-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/PowerValueDisplay/EditModeIntegration.lua
--
-- Registers PowerValueDisplay settings with the shared EditModeCompanionDialog
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
            tooltip = "Displays the current power value (mana, rage, energy, runic power, focus, etc.) as a number on the power bar.",
            get = function()
                return EnhancedInterface.db.powerValueDisplay.enabled
            end,
            set = function(value)
                if EnhancedInterfacePowerValueDisplayModule then
                    EnhancedInterfacePowerValueDisplayModule:SetEnabled(value)
                end
            end,
        },
    },
})
