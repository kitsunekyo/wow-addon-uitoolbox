-- UIToolbox
-- Settings.lua: Registers the addon settings panel in the WoW Settings UI.

local ADDON_NAME = "UIToolbox"

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    -- Top-level category in the AddOns section of the Settings panel.
    local category = Settings.RegisterVerticalLayoutCategory("UIToolbox")

    -- ----------------------------------------------------------------
    -- Objective Tracker — Auto-Collapse
    -- ----------------------------------------------------------------
    local headerTracker = CreateSettingsListSectionHeaderInitializer("Objective Tracker")
    Settings.RegisterInitializer(category, headerTracker)

    local collapseEnabledSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_AUTO_COLLAPSE_ENABLED",
        Settings.VarType.Boolean,
        "Auto-collapse in instances",
        false,
        function() return UIToolbox.db.autoCollapse.enabled end,
        function(value) UIToolbox.db.autoCollapse.enabled = value end
    )
    Settings.CreateCheckbox(
        category,
        collapseEnabledSetting,
        "Automatically collapses objective tracker sections when entering an instance. " ..
        "Restores them when you leave."
    )

    -- Collapse sections (campaign / quests / worldQuests) ------------
    local headerSections = CreateSettingsListSectionHeaderInitializer("Collapse sections")
    Settings.RegisterInitializer(category, headerSections)

    local sectionSettings = {
        { key = "campaign",    label = "Campaign Quests" },
        { key = "quests",      label = "Regular Quests"  },
        { key = "worldQuests", label = "World Quests"    },
    }

    for _, entry in ipairs(sectionSettings) do
        local key = entry.key
        local setting = Settings.RegisterProxySetting(
            category,
            "UITOOLBOX_AUTO_COLLAPSE_SECTION_" .. strupper(key),
            Settings.VarType.Boolean,
            entry.label,
            true,
            function() return UIToolbox.db.autoCollapse.sections[key] end,
            function(value) UIToolbox.db.autoCollapse.sections[key] = value end
        )
        Settings.CreateCheckbox(category, setting, nil)
    end

    -- ----------------------------------------------------------------
    -- Nameplates — Scale Fine-Tune
    -- ----------------------------------------------------------------
    local headerNameplates = CreateSettingsListSectionHeaderInitializer("Nameplates")
    Settings.RegisterInitializer(category, headerNameplates)

    local nameplateScaleSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_NAMEPLATE_SCALE",
        Settings.VarType.Number,
        "Scale Fine-Tune",
        1.0,
        function() return UIToolbox.db.nameplateScale.factor end,
        function(value)
            UIToolbox.NameplateScale:SetFactor(value)
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

    UIToolbox.settingsCategory = category
end)
