-- UIToolbox
-- Settings.lua: Registers the addon settings panel in the WoW Settings UI.

local ADDON_NAME = "UIToolbox"

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
    local category = Settings.RegisterVerticalLayoutCategory("UIToolbox")

    -- ----------------------------------------------------------------
    -- Objective Tracker — Auto-Collapse
    -- ----------------------------------------------------------------
    Settings.RegisterInitializer(category, createSection("Objective Tracker"))

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
    -- Damage Meter
    -- ----------------------------------------------------------------
    Settings.RegisterInitializer(category, createSection("Damage Meter"))

    local damageMeterEmbedSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_OBJECTIVE_TRACKER_DAMAGE_METER_EMBED",
        Settings.VarType.Boolean,
        "Show in Objective Tracker",
        false,
        function() return UIToolbox.db.objectivesTrackerDamageMeter.enabled end,
        function(value)
            UIToolbox.db.objectivesTrackerDamageMeter.enabled = value
            if UIToolboxObjectivesTrackerDamageMeterModule then
                ObjectiveTrackerManager:UpdateAll()
            end
        end
    )
    Settings.CreateCheckbox(
        category,
        damageMeterEmbedSetting,
        "Embeds the damage meter inside the Objective Tracker as a collapsible section."
    )

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

    -- ----------------------------------------------------------------
    -- Personal Resource Display
    -- ----------------------------------------------------------------
    Settings.RegisterInitializer(category, createSection("Personal Resource Display"))

    local prdEnabledSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_PERSONAL_RESOURCE_DISPLAY_ENABLED",
        Settings.VarType.Boolean,
        "Enable custom bars",
        true,
        function() return UIToolbox.db.personalResourceDisplay.enabled end,
        function(value)
            UIToolbox.db.personalResourceDisplay.enabled = value
            if UIToolboxPersonalResourceDisplayModule then
                UIToolboxPersonalResourceDisplayModule:ApplyToCurrentPlayerNameplate()
            end
        end
    )

    local prdEnabledInitializer = Settings.CreateCheckbox(
        category,
        prdEnabledSetting,
        "Master toggle for Personal Resource Display customisations. " ..
        "Individual options below have no effect when this is disabled."
    )

    local prdHideHealthSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_PRD_HIDE_HEALTH_BAR",
        Settings.VarType.Boolean,
        "Hide health bar",
        false,
        function() return UIToolbox.db.personalResourceDisplay.hideHealthBar end,
        function(value)
            UIToolbox.db.personalResourceDisplay.hideHealthBar = value
            if UIToolboxPersonalResourceDisplayModule then
                UIToolboxPersonalResourceDisplayModule:ApplyToCurrentPlayerNameplate()
            end
        end
    )
    local prdHideHealthInitializer = Settings.CreateCheckbox(
        category,
        prdHideHealthSetting,
        "Hides the health bar from the Personal Resource Display."
    )
    prdHideHealthInitializer:SetParentInitializer(prdEnabledInitializer, function()
        return UIToolbox.db.personalResourceDisplay.enabled
    end)

    local prdHideClassResourcesSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_PRD_HIDE_CLASS_RESOURCES",
        Settings.VarType.Boolean,
        "Hide duplicate class resources",
        false,
        function() return UIToolbox.db.personalResourceDisplay.hideClassResources end,
        function(value)
            UIToolbox.db.personalResourceDisplay.hideClassResources = value
            if UIToolboxPersonalResourceDisplayModule then
                UIToolboxPersonalResourceDisplayModule:ApplyToCurrentPlayerNameplate()
            end
        end
    )
    local prdHideClassResourcesInitializer = Settings.CreateCheckbox(
        category,
        prdHideClassResourcesSetting,
        "Hides class resource frames below the player unit frame " ..
        "(runes, holy power, combo points, soul shards, chi, arcane charges, essence orbs)."
    )
    prdHideClassResourcesInitializer:SetParentInitializer(prdEnabledInitializer, function()
        return UIToolbox.db.personalResourceDisplay.enabled
    end)

    local prdRestylePowerBarSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_PRD_RESTYLE_POWER_BAR",
        Settings.VarType.Boolean,
        "Restyle bars",
        false,
        function() return UIToolbox.db.personalResourceDisplay.restylePowerBar end,
        function(value)
            UIToolbox.db.personalResourceDisplay.restylePowerBar = value
            if UIToolboxPersonalResourceDisplayModule then
                UIToolboxPersonalResourceDisplayModule:ApplyToCurrentPlayerNameplate()
            end
        end
    )
    local prdRestylePowerBarInitializer = Settings.CreateCheckbox(
        category,
        prdRestylePowerBarSetting,
        "Applies a clean look to both the health bar and power bar: uses the RaidFrame health fill texture " ..
        "(Interface\\RaidFrame\\Raid-Bar-Hp-Fill), reduces height to 10px, and replaces " ..
        "the rounded Blizzard border with a thin 1px pixel border."
    )
    prdRestylePowerBarInitializer:SetParentInitializer(prdEnabledInitializer, function()
        return UIToolbox.db.personalResourceDisplay.enabled
    end)

    -- ----------------------------------------------------------------
    -- Action Bars — Shared Bars
    -- ----------------------------------------------------------------
    Settings.RegisterInitializer(category, createSection("Action Bars"))

    -- Display order and labels for the 8 shareable bars.
    -- index matches the BAR_SLOTS key in SharedBars.lua.
    -- Bar 1 has two pages; page 2 uses the synthetic key 10.
    local sharedBarDefs = {
        { index = 1,  label = "Action Bar 1 (Page 1)" },
        { index = 10, label = "Action Bar 1 (Page 2)" },
        { index = 2,  label = "Action Bar 2"          },
        { index = 3,  label = "Action Bar 3"          },
        { index = 4,  label = "Action Bar 4"          },
        { index = 5,  label = "Action Bar 5"          },
        { index = 6,  label = "Action Bar 6"          },
        { index = 7,  label = "Action Bar 7"          },
        { index = 8,  label = "Action Bar 8"          },
    }

    for _, def in ipairs(sharedBarDefs) do
        local barIndex = def.index
        local setting = Settings.RegisterProxySetting(
            category,
            "UITOOLBOX_SHARED_BAR_" .. barIndex,
            Settings.VarType.Boolean,
            "Share " .. def.label,
            false,
            function()
                local entry = UIToolbox.db.sharedBars.bars[barIndex]
                return entry ~= nil and entry.enabled == true
            end,
            function(value)
                if value then
                    UIToolbox.SharedBars:EnableBar(barIndex)
                else
                    UIToolbox.SharedBars:DisableBar(barIndex)
                end
            end
        )
        Settings.CreateCheckbox(
            category,
            setting,
            "Keeps this bar's button layout the same across all talent loadouts. " ..
            "Enabling saves the current layout as the shared snapshot."
        )
    end

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    UIToolbox.settingsCategory = category
end)
