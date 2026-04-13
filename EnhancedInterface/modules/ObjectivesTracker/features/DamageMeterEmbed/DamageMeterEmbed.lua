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

-- Height reserved for the embedded damage meter window.
-- DamageMeterSessionWindow1's actual height is driven by Edit Mode.
--
-- IMPORTANT: We must NOT call sessionWindow:GetHeight() from addon (tainted)
-- code.  Any value returned by GetHeight() inherits the taint of the calling
-- execution context.  Passing that tainted number to SetHeightModifier feeds
-- it into ObjectiveTrackerModuleMixin's height management, which in turn
-- propagates through UIParent_ManageFramePositions() and taints the positions
-- of downstream UI frames — causing "attempt to perform arithmetic on a secret
-- number value" errors when Blizzard's tooltip / MoneyFrame code reads those
-- positions (e.g. via TaskPOI_OnEnter → MoneyFrame_Update).
--
-- Instead we cache the session window's height from within a secure execution
-- context (the OnSizeChanged script, called by Blizzard's own layout code) so
-- the stored value is untainted.  Until a secure measurement is available we
-- use METER_HEIGHT_FALLBACK as the initial reservation.
local METER_HEIGHT_FALLBACK = 200

-- Last known height of DamageMeterSessionWindow1, captured from Blizzard's
-- secure execution context via OnSizeChanged.  Starts at nil; falls back to
-- METER_HEIGHT_FALLBACK until Blizzard sizes the window at least once.
local cachedMeterHeight = nil

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

    -- When the embed is enabled during combat, EmbedSessionWindow() is blocked
    -- by InCombatLockdown().  MarkDirty() on PLAYER_REGEN_ENABLED re-runs
    -- LayoutContents(), which re-queues EmbedSessionWindow() once lockdown lifts.
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    -- GetBlock calls Reset() which zeros block.height already; do NOT write it
    -- from addon code because any number we write is tainted, and LayoutBlock
    -- passes it to block:SetHeight(), feeding a tainted value into C++ frame
    -- layout — which propagates through UIParent_ManageFramePositions() and
    -- causes "secret number value" errors in downstream Blizzard code.
    local block = self:GetBlock("uitoolbox_damagemeter")
    if not self:LayoutBlock(block) then
        return
    end
    -- Hide the block's own visual elements so nothing renders behind the meter.
    block:Hide()

    -- Reserve extra vertical space inside this module for the meter window.
    -- Use the height captured from Blizzard's secure OnSizeChanged context.
    -- We must NOT call sessionWindow:GetHeight() here: any value returned by
    -- GetHeight() from tainted (addon) code is itself tainted and would poison
    -- SetHeightModifier, propagating taint into frame layout and causing
    -- "secret number value" errors in MoneyFrame/tooltip arithmetic downstream.
    local meterHeight = cachedMeterHeight or METER_HEIGHT_FALLBACK
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

-- NOTE: uiOrder must NOT be set from addon code.
-- Any number written by addon code is tainted. When
-- ObjectiveTrackerContainerMixin:Update() sorts the modules table it reads
-- every module's uiOrder via a comparator; reading a tainted value contaminates
-- the entire sort execution context. That tainted context propagates into
-- UIParent_ManageFramePositions(), which repositions UI frames — tainting their
-- positions. Blizzard code that later reads those positions (e.g.
-- QuestMapLogTitleButton_OnEnter in QuestMapFrame.lua) then hits
-- "attempt to perform numeric conversion on a secret number value" errors.
--
-- Instead, uiOrder is written inside a hooksecurefunc on AssignModulesOrder.
-- That hook runs within Blizzard's own Init() call stack, so the write is
-- untainted. The value is #modules + 1, placing our module last (after all
-- built-in modules, which get uiOrder 1–11).

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Assign our module's uiOrder from within Blizzard's own execution context
-- so the value is untainted. hooksecurefunc fires as part of Blizzard's
-- Init() → AssignModulesOrder() call, so the write carries Blizzard's trust.
-- Built-in modules receive uiOrder 1–11 (ipairs index in orderedModules);
-- we place ourselves immediately after the last one.
hooksecurefunc(ObjectiveTrackerManager, "AssignModulesOrder", function(self, modules)
    EnhancedInterfaceObjectivesTrackerDamageMeterModule.uiOrder = #modules + 1
end)

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
-- overwrite our anchors on the session window's parent).
--
-- TAINT HAZARD: hooksecurefunc callbacks on EditModeManagerFrame methods run
-- inside the call chain that originates from C_EditMode.SetActiveLayout() calls
-- by any addon (e.g. AccWideUILayoutSelection).  That call chain carries taint
-- from those addons.  Any C_Timer.After closure created inside such a hook
-- inherits the tainted execution context and will propagate taint to whatever
-- it touches — including chat-frame internal state (ChatHistory_GetToken,
-- HistoryKeeper.lua), causing "attempt to perform string conversion on a secret
-- string value" errors.
--
-- FIX: Never call C_Timer.After (or any other deferred work) inside the
-- hooksecurefunc callback.  Instead, only flip a plain boolean flag.  A
-- separate OnUpdate handler, driven by the game loop's own C++ call origin
-- (not the tainted hook call chain), polls the flag and performs the actual
-- re-embed outside of the tainted context.

-- Flag set by the Edit Mode hook; consumed by the OnUpdate poller below.
local pendingReembed = false

local function TryHookMethod(object, methodName, hookFunc)
    if object and type(object[methodName]) == "function" then
        hooksecurefunc(object, methodName, hookFunc)
        return true
    end

    return false
end

local function HookEditMode()
    if not EditModeManagerFrame then return end

    -- Only set the flag here — do NOT call C_Timer.After or anything that
    -- creates a new closure capturing this tainted execution context.
    local function ReembedIfDamageMeter(_, systemFrame)
        if systemFrame == DamageMeter then
            pendingReembed = true
        end
    end

    -- Older clients used ApplyLayoutToFrame; current retail updates each
    -- system through UpdateSystem.
    if TryHookMethod(EditModeManagerFrame, "ApplyLayoutToFrame", ReembedIfDamageMeter) then
        return
    end

    TryHookMethod(EditModeManagerFrame, "UpdateSystem", ReembedIfDamageMeter)
end

-- Hook the session window's OnSizeChanged to capture its height from within
-- Blizzard's secure execution context.  Edit Mode calls SetHeight() on the
-- session window from secure code; that triggers OnSizeChanged with an
-- untainted width/height pair, which we store in cachedMeterHeight.
--
-- We must NOT use sessionWindow:GetHeight() from addon code because the return
-- value inherits taint from the calling context (see METER_HEIGHT_FALLBACK note
-- above).  OnSizeChanged arguments are passed by the C++ engine and are clean.
local function HookSessionWindowSize()
    local sessionWindow = GetSessionWindow()
    if not sessionWindow then return end

    -- Seed the cache with the current size if the window already has a valid
    -- height (e.g. Edit Mode layout was applied before PLAYER_LOGIN).
    -- We read this once from addon code; it may be tainted.  We only use it as
    -- the initial seed — once OnSizeChanged fires from Blizzard code the value
    -- will be replaced with an untainted one.  Not calling SetHeightModifier
    -- with this seed value avoids injecting taint into the tracker layout.

    sessionWindow:HookScript("OnSizeChanged", function(_, _, h)
        -- h is passed directly by the C++ engine from Blizzard's SetHeight()
        -- call, so it carries no addon taint.
        if h and h > 0 then
            cachedMeterHeight = h
        end
    end)
end

-- Hook edit mode once DamageMeter is available.
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookEditMode()
        HookSessionWindowSize()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- OnUpdate poller: consume the pendingReembed flag set by the Edit Mode hook.
-- This handler is invoked by the C++ game loop, which provides a fresh
-- execution context not derived from the tainted Edit Mode call chain.
-- Reading and clearing the flag here, then calling EmbedSessionWindow, keeps
-- all the actual frame-manipulation work outside of any tainted context.
hookFrame:SetScript("OnUpdate", function()
    if not pendingReembed then return end
    pendingReembed = false
    if ShouldEmbed() then
        EnhancedInterfaceObjectivesTrackerDamageMeterModule:EmbedSessionWindow()
    end
end)
