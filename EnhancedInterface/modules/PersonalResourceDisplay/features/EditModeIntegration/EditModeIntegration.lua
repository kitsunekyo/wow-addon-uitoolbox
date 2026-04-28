local function DeferApply()
    if EnhancedInterfacePersonalResourceDisplayModule then
        EnhancedInterfacePersonalResourceDisplayModule:RequestApply()
    end
end

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        return systemFrame == PersonalResourceDisplayFrame
    end,

    rows = {
        {
            type    = "checkbox",
            label   = "Hide health bar",
            tooltip = "Hides the health bar from the Personal Resource Display.",
            get = function()
                return EnhancedInterface.db.personalResourceDisplay.hideHealthBar
            end,
            set = function(value)
                EnhancedInterface.db.personalResourceDisplay.hideHealthBar = value
                DeferApply()
            end,
        },
        {
            type    = "checkbox",
            label   = "Hide unit frame class resources",
            tooltip = "Hides class resource frames below the player unit frame " ..
                      "(runes, holy power, combo points, soul shards, chi, arcane charges, essence orbs).",
            get = function()
                return EnhancedInterface.db.personalResourceDisplay.hideClassResources
            end,
            set = function(value)
                EnhancedInterface.db.personalResourceDisplay.hideClassResources = value
                DeferApply()
            end,
        },
        {
            type    = "checkbox",
            label   = "Restyle bars",
            tooltip = "Applies a clean look to both bars: uses the raid-frame health fill texture, " ..
                      "reduces height to 10 px, and replaces the rounded border with a thin 1 px pixel border.",
            get = function()
                return EnhancedInterface.db.personalResourceDisplay.restylePowerBar
            end,
            set = function(value)
                EnhancedInterface.db.personalResourceDisplay.restylePowerBar = value
                DeferApply()
            end,
        },
        {
            type    = "checkbox",
            label   = "Hide when mounted",
            tooltip = "Hides the entire Personal Resource Display while you are mounted.",
            get = function()
                return EnhancedInterface.db.personalResourceDisplay.hideWhenMounted
            end,
            set = function(value)
                EnhancedInterface.db.personalResourceDisplay.hideWhenMounted = value
                DeferApply()
            end,
        },
    },
})
