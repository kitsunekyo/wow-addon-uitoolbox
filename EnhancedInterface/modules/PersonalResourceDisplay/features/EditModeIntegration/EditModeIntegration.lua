-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/EditModeIntegration/EditModeIntegration.lua
--
-- Registers Personal Resource Display settings with the shared
-- EditModeCompanionDialog so they appear in the "EnhancedInterface" companion panel
-- when the player selects the PersonalResourceDisplay frame in Edit Mode.

-- Helper: schedule a deferred style re-apply via the BarStyling module's flag.
-- TAINT HAZARD: these set callbacks fire from an OnClick handler on an addon-created
-- button — always a tainted execution context.  Calling ApplyToCurrentPlayerNameplate()
-- or ApplyMountVisibility() directly here calls SetHeight(), SetPoint(), Hide(), Show()
-- on PRD sub-frames in that tainted context, propagating taint into Blizzard's layout
-- system and causing "secret number value" errors on WorldMap / UIWidget frames.
-- Fix: use RequestApply() which only sets a boolean flag; the OnUpdate poller in
-- BarStyling.lua performs the actual frame writes from the clean C++ game loop context.
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
