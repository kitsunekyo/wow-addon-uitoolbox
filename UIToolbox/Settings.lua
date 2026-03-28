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
    -- Damage Meter — Free Move
    -- ----------------------------------------------------------------
    local headerDamageMeter = CreateSettingsListSectionHeaderInitializer("Damage Meter")
    Settings.RegisterInitializer(category, headerDamageMeter)

    local freeMoveEnabledSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_FREE_MOVE_ENABLED",
        Settings.VarType.Boolean,
        "Free Move",
        false,
        function() return UIToolbox.db.freeMove.enabled end,
        function(value)
            UIToolbox.db.freeMove.enabled = value
            if value then
                UIToolbox.FreeMove:Enable()
            else
                UIToolbox.FreeMove:Disable()
            end
        end
    )
    Settings.CreateCheckbox(
        category,
        freeMoveEnabledSetting,
        "Makes the Damage Meter window freely draggable outside of Edit Mode. " ..
        "Position is saved across sessions."
    )

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    UIToolbox.settingsCategory = category
end)
