-- UIToolbox
-- modules/ObjectivesTracker/features/DamageMeterEmbed/DamageMeterEmbed.lua
--
-- Adds a Damage Meter feature module to the "All Objectives" tracker.
-- When enabled, this feature embeds DamageMeterSessionWindow1 directly inside
-- the tracker module using SetHeightModifier to reserve space.
--
-- No paired XML file: the frame is created entirely in Lua to avoid the
-- mixin= attribute evaluation-at-parse-time ordering constraint.

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Height reserved for the embedded damage meter window.
-- DamageMeterSessionWindow1 has a fixed height driven by the Edit Mode system;
-- we match what it ships with by default (similar to the tracker panel height).
local METER_HEIGHT = 200

-- Expand the embedded meter a bit past the tracker content bounds so the
-- meter rows visually span the full section width.
local METER_SIDE_BLEED = 20

-- Slightly reduce the "Damage Done" header text size in the embedded view.
local DAMAGE_TYPE_HEADER_FONT_DELTA = 1

-- ---------------------------------------------------------------------------
-- Mixin
-- ---------------------------------------------------------------------------

local UIToolboxObjectivesTrackerDamageMeterModuleMixin = CreateFromMixins(ObjectiveTrackerModuleMixin)

function UIToolboxObjectivesTrackerDamageMeterModuleMixin:InitModule()
    -- Register damage-meter events so we can refresh when combat data changes.
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    self:RegisterEvent("DAMAGE_METER_RESET")
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
end

function UIToolboxObjectivesTrackerDamageMeterModuleMixin:OnEvent(event, ...)
    self:MarkDirty()
end

-- Returns true when the embed feature is enabled and the damage meter addon loaded.
local function ShouldEmbed()
    return UIToolbox.db.objectivesTrackerDamageMeter
       and UIToolbox.db.objectivesTrackerDamageMeter.enabled
       and (DamageMeter ~= nil)
end

-- Returns true when the session window exists and is available to embed.
local function GetSessionWindow()
    return _G["DamageMeterSessionWindow1"]
end

local function ApplyEmbeddedHeaderFont(sessionWindow)
    if not sessionWindow.GetDamageMeterTypeName then return end

    local typeName = sessionWindow:GetDamageMeterTypeName()
    if not typeName or not typeName.GetFont then return end

    if not sessionWindow._uitoolbox_origTypeNameFont then
        local fontPath, fontSize, fontFlags = typeName:GetFont()
        if not (fontPath and fontSize) then return end

        sessionWindow._uitoolbox_origTypeNameFont = {
            path = fontPath,
            size = fontSize,
            flags = fontFlags,
        }
    end

    local orig = sessionWindow._uitoolbox_origTypeNameFont
    local targetSize = math.max(8, orig.size - DAMAGE_TYPE_HEADER_FONT_DELTA)
    typeName:SetFont(orig.path, targetSize, orig.flags)
end

local function RestoreHeaderFont(sessionWindow)
    local orig = sessionWindow._uitoolbox_origTypeNameFont
    if not orig or not sessionWindow.GetDamageMeterTypeName then return end

    local typeName = sessionWindow:GetDamageMeterTypeName()
    if typeName and typeName.SetFont then
        typeName:SetFont(orig.path, orig.size, orig.flags)
    end
end

-- Called by the container every time the tracker repaints.
function UIToolboxObjectivesTrackerDamageMeterModuleMixin:LayoutContents()
    if not ShouldEmbed() then
        -- Feature off: clear any reserved height and hide the session window embed.
        self:ClearHeightModifier("damageMeter")
        self:DetachSessionWindow()
        return
    end

    local sessionWindow = GetSessionWindow()
    if not sessionWindow then
        -- Damage meter not yet created; nothing to show.
        self:ClearHeightModifier("damageMeter")
        return
    end

    -- We must call LayoutBlock at least once so hasContents becomes true and
    -- the module is considered to have content (visibility rule).
    -- Use a zero-height invisible block — the damage meter window itself provides all visuals.
    local block = self:GetBlock("uitoolbox_damagemeter")
    block.height = 0
    if not self:LayoutBlock(block) then
        return
    end
    -- Hide the block's own visual elements so nothing renders behind the meter.
    block:Hide()

    -- Reserve extra vertical space inside this module for the meter window.
    self:SetHeightModifier("damageMeter", METER_HEIGHT)

    -- Anchor the session window inside ContentsFrame on the next tick, after
    -- UpdateHeight() has already run and expanded the module frame.
    C_Timer.After(0, function()
        self:EmbedSessionWindow()
    end)
end

-- Reparent and anchor DamageMeterSessionWindow1 inside our ContentsFrame.
function UIToolboxObjectivesTrackerDamageMeterModuleMixin:EmbedSessionWindow()
    if InCombatLockdown() then return end

    local sessionWindow = GetSessionWindow()
    if not sessionWindow then return end

    -- Guard: only act when embed is still wanted (setting may have changed).
    if not ShouldEmbed() then
        self:DetachSessionWindow()
        return
    end

    -- Mark as embedded so we know to restore it later.
    if not sessionWindow._uitoolbox_embedded then
        -- Save original parent and anchors for restoration.
        sessionWindow._uitoolbox_origParent = sessionWindow:GetParent()
        sessionWindow._uitoolbox_origClampedToScreen = sessionWindow:IsClampedToScreen()
        sessionWindow._uitoolbox_embedded = true
    end

    -- Re-parent into our module's contents area.
    sessionWindow:SetParent(self.ContentsFrame)

    -- Fill the reserved space inside ContentsFrame.
    -- ContentsFrame grows to (METER_HEIGHT) because of SetHeightModifier.
    -- Anchor below the header block with a small top offset.
    sessionWindow:ClearAllPoints()
    sessionWindow:SetPoint("TOPLEFT",  self.ContentsFrame, "TOPLEFT",  -METER_SIDE_BLEED, 0)
    sessionWindow:SetPoint("TOPRIGHT", self.ContentsFrame, "TOPRIGHT", METER_SIDE_BLEED, 0)
    sessionWindow:SetHeight(METER_HEIGHT)
    sessionWindow:SetClampedToScreen(false)
    ApplyEmbeddedHeaderFont(sessionWindow)
    sessionWindow:Show()
end

-- Restore DamageMeterSessionWindow1 to its original parent and position.
function UIToolboxObjectivesTrackerDamageMeterModuleMixin:DetachSessionWindow()
    if InCombatLockdown() then return end

    local sessionWindow = GetSessionWindow()
    if not sessionWindow then return end
    if not sessionWindow._uitoolbox_embedded then return end

    sessionWindow._uitoolbox_embedded = false

    -- Re-parent back to the Edit Mode system frame.
    local origParent = sessionWindow._uitoolbox_origParent or DamageMeter
    sessionWindow:SetParent(origParent)

    -- Restore Blizzard's default layout: fill DamageMeter completely.
    sessionWindow:ClearAllPoints()
    sessionWindow:SetPoint("TOPLEFT",     origParent, "TOPLEFT",     0,  0)
    sessionWindow:SetPoint("BOTTOMRIGHT", origParent, "BOTTOMRIGHT", 0,  0)
    if sessionWindow._uitoolbox_origClampedToScreen ~= nil then
        sessionWindow:SetClampedToScreen(sessionWindow._uitoolbox_origClampedToScreen)
    end
    RestoreHeaderFont(sessionWindow)
end

-- ---------------------------------------------------------------------------
-- Frame creation
-- ---------------------------------------------------------------------------

local frame = CreateFrame(
    "Frame",
    "UIToolboxObjectivesTrackerDamageMeterModule",
    ObjectiveTrackerFrame,
    "ObjectiveTrackerModuleTemplate"
)

Mixin(frame, UIToolboxObjectivesTrackerDamageMeterModuleMixin)

-- headerText must be set before SetHeader() is called, but OnLoad() already
-- ran during CreateFrame with headerText=nil. Call SetHeader() explicitly now
-- to push the label into the header sub-frame's Text font string.
frame.headerText = "Damage Meter"
frame:SetHeader("Damage Meter")

-- Sit below all built-in modules (their uiOrder values are 1–11).
frame.uiOrder = 100

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Use hooksecurefunc on Init so we are guaranteed to run after
-- ObjectiveTrackerManager:Init() has populated self.containers.
-- PLAYER_ENTERING_WORLD is the fallback for the case where Init already ran.
local registered = false
local function TryRegister()
    if registered then return end
    if not (ObjectiveTrackerManager.containers
            and ObjectiveTrackerManager.containers[ObjectiveTrackerFrame]) then
        return
    end
    registered = true
    ObjectiveTrackerManager:SetModuleContainer(UIToolboxObjectivesTrackerDamageMeterModule, ObjectiveTrackerFrame)
    C_Timer.After(0, function()
        ObjectiveTrackerManager:UpdateAll()
    end)
end

hooksecurefunc(ObjectiveTrackerManager, "Init", TryRegister)

local diag = CreateFrame("Frame")
diag:RegisterEvent("PLAYER_ENTERING_WORLD")
diag:SetScript("OnEvent", function()
    TryRegister()
end)

-- Re-embed after Edit Mode writes its layout back to DamageMeter (which would
-- overwrite our anchors on the session window's parent). Defer one tick.
local function HookEditMode()
    if not EditModeManagerFrame then return end
    hooksecurefunc(EditModeManagerFrame, "ApplyLayoutToFrame", function(_, systemFrame)
        if systemFrame == DamageMeter then
            C_Timer.After(0, function()
                if ShouldEmbed() then
                    UIToolboxObjectivesTrackerDamageMeterModule:EmbedSessionWindow()
                end
            end)
        end
    end)
end

-- Hook edit mode once DamageMeter is available.
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookEditMode()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
