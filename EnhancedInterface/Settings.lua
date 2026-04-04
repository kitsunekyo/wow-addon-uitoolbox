-- Enhanced Interface
-- Settings.lua: Registers the addon settings panel in the WoW Settings UI.

local ADDON_NAME = "EnhancedInterface"

-- Creates a non-collapsible section header initializer.
--
-- We deliberately avoid SettingsExpandableSectionMixin (collapsible sections) because
-- that pattern requires writing CalculateHeight and OnExpandedChanged onto individual
-- frame instances from addon (tainted) code.  Blizzard's UIParentPanelManager reads
-- those frame fields in a secure execution path when managing panel visibility
-- (e.g. ShowUIPanel for the WorldMap).  Reading a tainted field inside a secure path
-- propagates taint forward and eventually blocks protected-function calls such as
-- Frame:SetPropagateMouseClicks() on world-map pins, producing ADDON_ACTION_BLOCKED.
--
-- CreateSettingsListSectionHeaderInitializer is the standard Blizzard API for
-- non-collapsible section headers.  It uses SettingsListSectionHeaderMixin which only
-- calls Init() -- no abstract methods, no per-instance writes from addon code.
local function createSection(name)
    return CreateSettingsListSectionHeaderInitializer(name)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    -- Top-level category in the AddOns section of the Settings panel.
    local category = Settings.RegisterVerticalLayoutCategory("Enhanced Interface")

    -- ----------------------------------------------------------------
    -- Nameplates
    -- ----------------------------------------------------------------
    Settings.RegisterInitializer(category, createSection("Nameplates"))

    local nameplateScaleSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_NAMEPLATE_SCALE",
        Settings.VarType.Number,
        "Scale Fine-Tune",
        1.0,
        function() return EnhancedInterface.db.nameplateScale.factor end,
        function(value)
            EnhancedInterface.NameplateScale:SetFactor(value)
        end
    )

    local sliderOptions = Settings.CreateSliderOptions(0.75, 1.6, 0.05)
    sliderOptions:SetLabelFormatter(
        MinimalSliderWithSteppersMixin.Label.Right,
        function(value) return string.format("%.0f%%", value * 100) end
    )

    Settings.CreateSlider(
        category,
        nameplateScaleSetting,
        sliderOptions,
        "Multiplies the current Blizzard nameplate size by this factor. " ..
        "Use this to fine-tune between Blizzard's preset steps (Small / Medium / Large …)."
    )

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    EnhancedInterface.settingsCategory = category
end)
