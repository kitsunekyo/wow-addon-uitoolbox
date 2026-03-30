-- UIToolbox
-- Settings.lua: Registers the addon settings panel in the WoW Settings UI.

local ADDON_NAME = "UIToolbox"

local SECTION_HEADER_HEIGHT = 32

local function isSearchActive()
    return SettingsPanel and SettingsPanel.SearchBox and SettingsPanel.SearchBox:HasText()
end

-- Creates a collapsible section initializer.
-- CalculateHeight and OnExpandedChanged are abstract on SettingsExpandableSectionMixin
-- and must be injected onto each concrete frame instance after Init. We do this via a
-- one-time hook on the mixin's Init method.
local function createSection(name)
    local init = CreateSettingsExpandableSectionInitializer(name)

    -- GetExtent is called by the scroll box to allocate layout space. When collapsed it
    -- only needs to fit the header button; when expanded child elements handle their own
    -- space, so the section frame itself stays header-height only.
    function init:GetExtent()
        return SECTION_HEADER_HEIGHT
    end

    return init
end

-- Hook SettingsExpandableSectionMixin.Init once to inject the two abstract methods onto
-- every expandable section frame as it is acquired from the frame pool.
local hooked = false
local function ensureFrameHook()
    if hooked then return end
    hooked = true

    hooksecurefunc(SettingsExpandableSectionMixin, "Init", function(frame, initializer)
        -- CalculateHeight: called by OnClick immediately after toggling data.expanded.
        -- The section frame itself is always header-height; child rows are separate frames.
        frame.CalculateHeight = function(self)
            return SECTION_HEADER_HEIGHT
        end

        -- OnExpandedChanged: called after SetHeight with the new expanded state.
        -- Triggers the settings list to re-evaluate all shown predicates.
        frame.OnExpandedChanged = function(self, expanded)
            if SettingsInbound and SettingsInbound.RepairDisplay then
                SettingsInbound.RepairDisplay()
            elseif SettingsPanel and SettingsPanel.RepairDisplay then
                SettingsPanel:RepairDisplay()
            end
        end
    end)
end

-- Bind a settings initializer to a collapsible section so it only appears when expanded.
local function addToSection(initializer, sectionInit)
    initializer:AddShownPredicate(function()
        if isSearchActive() then return true end
        return sectionInit.data.expanded == true
    end)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    -- Top-level category in the AddOns section of the Settings panel.
    local category = Settings.RegisterVerticalLayoutCategory("UIToolbox")

    -- Inject CalculateHeight / OnExpandedChanged onto expandable section frames.
    ensureFrameHook()

    -- ----------------------------------------------------------------
    -- Objective Tracker — Auto-Collapse
    -- ----------------------------------------------------------------
    local trackerSection = createSection("Objective Tracker")
    Settings.RegisterInitializer(category, trackerSection)

    local collapseEnabledSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_AUTO_COLLAPSE_ENABLED",
        Settings.VarType.Boolean,
        "Auto-collapse in instances",
        false,
        function() return UIToolbox.db.autoCollapse.enabled end,
        function(value) UIToolbox.db.autoCollapse.enabled = value end
    )
    local collapseEnabledInit = Settings.CreateCheckbox(
        category,
        collapseEnabledSetting,
        "Automatically collapses objective tracker sections when entering an instance. " ..
        "Restores them when you leave."
    )
    addToSection(collapseEnabledInit, trackerSection)

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
        local init = Settings.CreateCheckbox(category, setting, nil)
        addToSection(init, trackerSection)
    end

    -- ----------------------------------------------------------------
    -- Damage Meter
    -- ----------------------------------------------------------------
    local damageMeterSection = createSection("Damage Meter")
    Settings.RegisterInitializer(category, damageMeterSection)

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
    local damageMeterEmbedInit = Settings.CreateCheckbox(
        category,
        damageMeterEmbedSetting,
        "Embeds the damage meter inside the Objective Tracker as a collapsible section."
    )
    addToSection(damageMeterEmbedInit, damageMeterSection)

    -- ----------------------------------------------------------------
    -- Nameplates — Scale Fine-Tune
    -- ----------------------------------------------------------------
    local nameplatesSection = createSection("Nameplates")
    Settings.RegisterInitializer(category, nameplatesSection)

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

    local nameplateScaleInit = Settings.CreateSlider(
        category,
        nameplateScaleSetting,
        sliderOptions,
        "Multiplies the current Blizzard nameplate size by this factor. " ..
        "Use this to fine-tune between Blizzard's preset steps (Small / Medium / Large …)."
    )
    addToSection(nameplateScaleInit, nameplatesSection)

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    UIToolbox.settingsCategory = category
end)
