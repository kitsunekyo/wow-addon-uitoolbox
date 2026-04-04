-- EnhancedInterface
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

-- Fallback height reserved for the embedded damage meter window when the
-- session window has not yet been sized by the Edit Mode system.
-- DamageMeterSessionWindow1's actual height is driven by Edit Mode; we read
-- it dynamically at embed time to avoid calling SetHeight() on the window.
-- Calling SetHeight() from addon code taints the frame's C++ height property,
-- which Blizzard's Edit Mode and UIParent layout code then reads in secure
-- contexts, propagating taint into tooltip widget containers and causing
-- "SetWidth: Secret values are only allowed during untainted execution" errors.
local METER_HEIGHT_FALLBACK = 200

-- Expand the embedded meter a bit past the tracker content bounds so the
-- meter rows visually span the full section width.
local METER_SIDE_BLEED = 20

-- Slightly reduce the "Damage Done" header text size in the embedded view.
local DAMAGE_TYPE_HEADER_FONT_DELTA = 1

-- ---------------------------------------------------------------------------
-- Mixin
-- ---------------------------------------------------------------------------

local EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin = CreateFromMixins(ObjectiveTrackerModuleMixin)

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:InitModule()
    -- Register damage-meter events so we can refresh when combat data changes.
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    self:RegisterEvent("DAMAGE_METER_RESET")
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
end

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:OnEvent(event, ...)
    self:MarkDirty()
end

-- Returns true when the embed feature is enabled and the damage meter addon loaded.
local function ShouldEmbed()
    return EnhancedInterface.db.objectivesTrackerDamageMeter
       and EnhancedInterface.db.objectivesTrackerDamageMeter.enabled
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

local function RefreshEmbeddedStyleState(sessionWindow)
    if not sessionWindow then return end

    if DamageMeter and DamageMeter.ShouldUseClassColor and sessionWindow.SetUseClassColor then
        local useClassColor = DamageMeter:ShouldUseClassColor()
        if useClassColor ~= nil then
            sessionWindow:SetUseClassColor(useClassColor and true or false)
        end
    end
end

-- Called by the container every time the tracker repaints.
function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:LayoutContents()
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
    -- Use the session window's current (Blizzard-managed) height so we never
    -- need to call SetHeight() on the session window ourselves.
    local meterHeight = sessionWindow:GetHeight()
    if not meterHeight or meterHeight <= 0 then
        meterHeight = METER_HEIGHT_FALLBACK
    end
    self:SetHeightModifier("damageMeter", meterHeight)

    -- Anchor the session window inside ContentsFrame on the next tick, after
    -- UpdateHeight() has already run and expanded the module frame.
    C_Timer.After(0, function()
        self:EmbedSessionWindow()
    end)
end

-- Reparent and anchor DamageMeterSessionWindow1 inside our ContentsFrame.
function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:EmbedSessionWindow()
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

    -- Anchor the session window inside ContentsFrame.
    -- ContentsFrame height is reserved via SetHeightModifier using the session
    -- window's own (Blizzard-managed) height, so no SetHeight() call is needed.
    -- Calling SetHeight() from addon code would taint the frame's C++ height
    -- property, which Blizzard's Edit Mode and UIParent layout code reads in
    -- secure contexts — that taint propagates into tooltip widget containers.
    sessionWindow:ClearAllPoints()
    sessionWindow:SetPoint("TOPLEFT",  self.ContentsFrame, "TOPLEFT",  -METER_SIDE_BLEED, 0)
    sessionWindow:SetPoint("TOPRIGHT", self.ContentsFrame, "TOPRIGHT", METER_SIDE_BLEED, 0)
    sessionWindow:SetClampedToScreen(false)
    ApplyEmbeddedHeaderFont(sessionWindow)
    sessionWindow:Show()
    RefreshEmbeddedStyleState(sessionWindow)
end

-- Restore DamageMeterSessionWindow1 to its original parent and position.
function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:DetachSessionWindow()
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
    "EnhancedInterfaceObjectivesTrackerDamageMeterModule",
    ObjectiveTrackerFrame,
    "ObjectiveTrackerModuleTemplate"
)

Mixin(frame, EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin)

-- headerText must be set before SetHeader() is called, but OnLoad() already
-- ran during CreateFrame with headerText=nil. Call SetHeader() explicitly now
-- to push the label into the header sub-frame's Text font string.
frame.headerText = "Damage Meter"
frame:SetHeader("Damage Meter")

-- NOTE: Do NOT set frame.uiOrder here at load time.
-- Setting it from addon code produces a tainted numeric value. When
-- ObjectiveTrackerContainerMixin:Update() sorts the modules table it reads
-- every module's uiOrder via a comparator; reading a tainted value contaminates
-- the entire sort execution context. That tainted context then propagates into
-- UIParent_ManageFramePositions(), which repositions UI frames — tainting their
-- positions. Blizzard code that later reads those positions (e.g.
-- QuestMapLogTitleButton_OnEnter in QuestMapFrame.lua) then hits
-- "attempt to perform numeric conversion on a secret number value" errors.
--
-- Instead, uiOrder is assigned inside TryRegister() immediately after the
-- module is registered. The value is still technically tainted (all addon-
-- written numbers are), but by setting it right before MarkDirty triggers
-- and clearing needsSorting, we ensure the sort never fires as a direct
-- result of our module being added, eliminating the taint propagation path.

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Permanently suppress the module-sort on ObjectiveTrackerFrame.
--
-- ObjectiveTrackerContainerMixin:AddModule() and RemoveModule() both set
-- needsSorting = true, which causes the next Update() to run table.sort().
-- The sort comparator reads every module's uiOrder; since our module's
-- uiOrder is written by addon code it is a tainted value. Reading it in the
-- comparator taints the entire sort execution context, which propagates into
-- UIParent_ManageFramePositions() and downstream Blizzard code —
-- triggering "attempt to perform numeric conversion on a secret number value"
-- (QuestMapFrame.lua:2123) and "SetPassThroughButtons: protected function"
-- (MapCanvas pin passthrough) errors.
--
-- The sort is safe to suppress on ObjectiveTrackerFrame because:
--   • Built-in modules are ordered stably at startup via AssignModulesOrder().
--   • Our module always sits at the end (uiOrder 100 > all built-in 1–11).
--   • Suppressing sort on ObjectiveTrackerFrame does not affect other
--     containers (BonusObjectiveTracker, etc.) — we guard by container.
--
-- We hook AddModule/RemoveModule on the *mixin* so the hook is registered once
-- and covers all future calls regardless of call site.
local sortSuppressInstalled = false
local function InstallSortSuppressHooks()
    if sortSuppressInstalled then return end
    sortSuppressInstalled = true

    -- hooksecurefunc runs our callback AFTER the original function body.
    -- At that point needsSorting has already been set to true; we flip it back
    -- to false so the sort never executes for ObjectiveTrackerFrame.
    hooksecurefunc(ObjectiveTrackerContainerMixin, "AddModule", function(self)
        if self == ObjectiveTrackerFrame then
            self.needsSorting = false
        end
    end)

    hooksecurefunc(ObjectiveTrackerContainerMixin, "RemoveModule", function(self)
        if self == ObjectiveTrackerFrame then
            self.needsSorting = false
        end
    end)
end

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

    -- Install sort-suppress hooks before registration so the AddModule call
    -- inside SetModuleContainer is already covered.
    InstallSortSuppressHooks()

    -- Assign uiOrder here (just before registration) so the value is present
    -- when needed, but note it is still addon-tainted.
    -- Sit below all built-in modules (their uiOrder values are 1–11).
    EnhancedInterfaceObjectivesTrackerDamageMeterModule.uiOrder = 100

    ObjectiveTrackerManager:SetModuleContainer(EnhancedInterfaceObjectivesTrackerDamageMeterModule, ObjectiveTrackerFrame)

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
local function TryHookMethod(object, methodName, hookFunc)
    if object and type(object[methodName]) == "function" then
        hooksecurefunc(object, methodName, hookFunc)
        return true
    end

    return false
end

local function HookEditMode()
    if not EditModeManagerFrame then return end

    local function ReembedIfDamageMeter(_, systemFrame)
        if systemFrame == DamageMeter then
            C_Timer.After(0, function()
                if ShouldEmbed() then
                    EnhancedInterfaceObjectivesTrackerDamageMeterModule:EmbedSessionWindow()
                end
            end)
        end
    end

    -- Older clients used ApplyLayoutToFrame; current retail updates each
    -- system through UpdateSystem.
    if TryHookMethod(EditModeManagerFrame, "ApplyLayoutToFrame", ReembedIfDamageMeter) then
        return
    end

    TryHookMethod(EditModeManagerFrame, "UpdateSystem", ReembedIfDamageMeter)
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
