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
    local category = Settings.RegisterVerticalLayoutCategory("EnhancedInterface")

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
        function() return EnhancedInterface.db.autoCollapse.enabled end,
        function(value) EnhancedInterface.db.autoCollapse.enabled = value end
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
            function() return EnhancedInterface.db.autoCollapse.sections[key] end,
            function(value) EnhancedInterface.db.autoCollapse.sections[key] = value end
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
        function() return EnhancedInterface.db.objectivesTrackerDamageMeter.enabled end,
        function(value)
            EnhancedInterface.db.objectivesTrackerDamageMeter.enabled = value
            if EnhancedInterfaceObjectivesTrackerDamageMeterModule then
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
                local entry = EnhancedInterface.db.sharedBars.bars[barIndex]
                return entry ~= nil and entry.enabled == true
            end,
            function(value)
                if value then
                    EnhancedInterface.SharedBars:EnableBar(barIndex)
                else
                    EnhancedInterface.SharedBars:DisableBar(barIndex)
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

    EnhancedInterface.settingsCategory = category
end)
