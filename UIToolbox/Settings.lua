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
        "Automatically collapses the Campaign, Quests, and World Quests tracker sections " ..
        "when entering any instance. Restores them when you leave."
    )

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
