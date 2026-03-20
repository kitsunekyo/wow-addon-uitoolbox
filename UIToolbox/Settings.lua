-- UIToolbox
-- Settings.lua: Registers the addon settings panel in the WoW Settings UI.

local ADDON_NAME = "UIToolbox"

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    -- Top-level category in the AddOns section of the Settings panel.
    local category = Settings.RegisterVerticalLayoutCategory("UIToolbox")

    -- ----------------------------------------------------------------
    -- Tracker Collapse — enable/disable checkbox
    -- UIToolbox.db is referenced directly (not captured as an upvalue)
    -- so it is always resolved at call time, after ADDON_LOADED has run.
    -- ----------------------------------------------------------------
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
        "Auto-collapse tracker on instance entry",
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

    -- Always the last call -- registers the category into the Settings panel.
    Settings.RegisterAddOnCategory(category)

    UIToolbox.settingsCategory = category
end)
