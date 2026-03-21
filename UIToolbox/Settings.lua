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

    local function GetTrackerCollapseEnabled()
        return UIToolbox.db.trackerCollapse.enabled
    end

    local function SetTrackerCollapseEnabled(value)
        UIToolbox.db.trackerCollapse.enabled = value
    end

    local collapseEnabledSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_TRACKER_COLLAPSE_ENABLED",
        Settings.VarType.Boolean,
        "Auto-collapse in instances",
        false,
        GetTrackerCollapseEnabled,
        SetTrackerCollapseEnabled
    )

    Settings.CreateCheckbox(
        category,
        collapseEnabledSetting,
        "Automatically collapses objective tracker sections when entering an instance. " ..
        "Restores them when you leave."
    )

    -- Collapse in (instance types) ---------------
    local headerInstanceTypes = CreateSettingsListSectionHeaderInitializer("Collapse in")
    Settings.RegisterInitializer(category, headerInstanceTypes)

    local instanceTypeSettings = {
        { key = "party",    label = "Dungeons"       },
        { key = "raid",     label = "Raids"          },
        { key = "pvp",      label = "Battlegrounds"  },
        { key = "arena",    label = "Arenas"         },
        { key = "scenario", label = "Scenarios"      },
    }

    for _, entry in ipairs(instanceTypeSettings) do
        local key = entry.key
        local function MakeGetter(k)
            return function() return UIToolbox.db.trackerCollapse.instanceTypes[k] end
        end
        local function MakeSetter(k)
            return function(value) UIToolbox.db.trackerCollapse.instanceTypes[k] = value end
        end
        local setting = Settings.RegisterProxySetting(
            category,
            "UITOOLBOX_TRACKER_COLLAPSE_INSTANCE_" .. strupper(key),
            Settings.VarType.Boolean,
            entry.label,
            true,
            MakeGetter(key),
            MakeSetter(key)
        )
        Settings.CreateCheckbox(category, setting, nil)
    end

    -- Collapse sections --------------------------
    local headerSections = CreateSettingsListSectionHeaderInitializer("Collapse sections")
    Settings.RegisterInitializer(category, headerSections)

    local sectionSettings = {
        { key = "campaign",    label = "Campaign Quests" },
        { key = "quests",     label = "Regular Quests"  },
        { key = "worldQuests", label = "World Quests"   },
    }

    for _, entry in ipairs(sectionSettings) do
        local key = entry.key
        local function MakeGetter(k)
            return function() return UIToolbox.db.trackerCollapse.sections[k] end
        end
        local function MakeSetter(k)
            return function(value) UIToolbox.db.trackerCollapse.sections[k] = value end
        end
        local setting = Settings.RegisterProxySetting(
            category,
            "UITOOLBOX_TRACKER_COLLAPSE_SECTION_" .. strupper(key),
            Settings.VarType.Boolean,
            entry.label,
            true,
            MakeGetter(key),
            MakeSetter(key)
        )
        Settings.CreateCheckbox(category, setting, nil)
    end

    -- ----------------------------------------------------------------
    -- Damage Meter — Free Drag
    -- ----------------------------------------------------------------
    local headerDamageMeter = CreateSettingsListSectionHeaderInitializer("Damage Meter")
    Settings.RegisterInitializer(category, headerDamageMeter)

    local function GetDamageMeterDragEnabled()
        return UIToolbox.db.damageMeterDrag.enabled
    end

    local function SetDamageMeterDragEnabled(value)
        UIToolbox.db.damageMeterDrag.enabled = value
        if value then
            UIToolbox.DamageMeterDrag:Enable()
        else
            UIToolbox.DamageMeterDrag:Disable()
        end
    end

    local damageMeterDragSetting = Settings.RegisterProxySetting(
        category,
        "UITOOLBOX_DAMAGE_METER_DRAG_ENABLED",
        Settings.VarType.Boolean,
        "Free drag",
        false,
        GetDamageMeterDragEnabled,
        SetDamageMeterDragEnabled
    )

    Settings.CreateCheckbox(
        category,
        damageMeterDragSetting,
        "Allows dragging the Damage Meter window freely at any time, instead of only " ..
        "through Edit Mode. Position is saved between sessions."
    )

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    UIToolbox.settingsCategory = category
end)
