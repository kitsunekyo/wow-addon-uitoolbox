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

local cachedMeterHeight = nil

local METER_SIDE_BLEED = 20

-- TAINT MODEL — why we cannot call SetFont here:
-- ApplyEmbeddedHeaderFont runs from EmbedSessionWindow, which is invoked from
-- our own OnUpdate poller.  Although the comment block on the OnUpdate handler
-- claims the C++ game loop provides "a fresh execution context not derived
-- from any tainted call chain", that is only true for OnUpdate handlers
-- registered by Blizzard itself.  When an addon registers an OnUpdate via
-- SetScript, the engine still stamps the addon's taint on the call stack.
--
-- SetFont(path, size, flags) writes into the global font-metrics cache shared
-- by every FontString in the UI — including Blizzard's UIWidget text frames.
-- Once the cache is tainted by us, any later GetStringHeight/GetStringWidth/
-- GetLeft/GetBottom returns a "secret number", which Blizzard's tooltip and
-- widget layout code feeds into arithmetic and crashes:
--   • UIWidgetTemplateBase:Setup -> arithmetic on secret number
--   • UIWidgetTemplateTextWithState:Setup -> textHeight (secret)
--   • FrameUtil.GetUnscaledFrameRect -> frameLeft (secret)
--   • SharedTooltipTemplates.GameTooltip_InsertFrame -> arithmetic
--   • ADDON_ACTION_BLOCKED PerformEmote() (WorldMap show path)
--
-- SetFontObject with a Blizzard-defined font object does NOT write to the
-- metrics cache; it just swaps the FontString's font-object pointer to one
-- whose metrics are already in the (clean) cache from FrameXML load time.
local DAMAGE_TYPE_HEADER_FONT_OBJECT_NAME = "GameFontNormal"

local pendingUpdateAll = false

local pendingReembed = false

local pendingEmbed = false

local EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin = CreateFromMixins(ObjectiveTrackerModuleMixin)

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:InitModule()
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:OnEvent(event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        pendingUpdateAll = true
    end
end

local function ShouldEmbed()
    return EnhancedInterface.db.objectivesTrackerDamageMeter
       and EnhancedInterface.db.objectivesTrackerDamageMeter.enabled
       and (DamageMeter ~= nil)
end

local function GetSessionWindow()
    return _G["DamageMeterSessionWindow1"]
end

local function ApplyEmbeddedHeaderFont(sessionWindow)
    if not sessionWindow.GetDamageMeterTypeName then return end

    local typeName = sessionWindow:GetDamageMeterTypeName()
    if not typeName or not typeName.SetFontObject then return end

    if not sessionWindow._uitoolbox_origTypeNameFontObject then
        local origObject = typeName:GetFontObject()
        if origObject then
            sessionWindow._uitoolbox_origTypeNameFontObject = origObject
        end
    end

    local target = _G[DAMAGE_TYPE_HEADER_FONT_OBJECT_NAME]
    if target then
        typeName:SetFontObject(target)
    end
end

local function RestoreHeaderFont(sessionWindow)
    if not sessionWindow.GetDamageMeterTypeName then return end
    local origObject = sessionWindow._uitoolbox_origTypeNameFontObject
    if not origObject then return end

    local typeName = sessionWindow:GetDamageMeterTypeName()
    if typeName and typeName.SetFontObject then
        typeName:SetFontObject(origObject)
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

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:LayoutContents()
    if not ShouldEmbed() then
        self:ClearHeightModifier("damageMeter")
        self:DetachSessionWindow()
        return
    end

    local sessionWindow = GetSessionWindow()
    if not sessionWindow then
        self:ClearHeightModifier("damageMeter")
        return
    end

    -- Do not set block height from addon code; tainted numerics can leak into tracker layout.
    local block = self:GetBlock("uitoolbox_damagemeter")
    if not self:LayoutBlock(block) then
        return
    end
    block:Hide()

    -- Use cached OnSizeChanged height; avoid GetHeight() reads from addon code.
    local meterHeight = cachedMeterHeight or METER_HEIGHT_FALLBACK
    self:SetHeightModifier("damageMeter", meterHeight)

    -- TAINT HAZARD: LayoutContents() is called by Blizzard's ObjectiveTracker
    -- layout system, which can be triggered during a call chain tainted by
    -- another addon (e.g. CraftSim tainting a scroll/menu close path).  A
    -- C_Timer.After closure created here would capture that tainted context and
    -- propagate it — causing "secret number value" errors in MathUtil.lua (Clamp)
    -- via ScrollBox when the game menu closes.
    -- Instead we only set a boolean flag.  The OnUpdate poller fires from the
    -- C++ game loop's own call origin, breaking the taint chain.
    pendingEmbed = true
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

    sessionWindow:SetParent(self.ContentsFrame)

    -- Do not call SetHeight() here; height is reserved via SetHeightModifier.
    sessionWindow:ClearAllPoints()
    sessionWindow:SetPoint("TOPLEFT",  self.ContentsFrame, "TOPLEFT",  -METER_SIDE_BLEED, 0)
    sessionWindow:SetPoint("TOPRIGHT", self.ContentsFrame, "TOPRIGHT", METER_SIDE_BLEED, 0)
    sessionWindow:SetClampedToScreen(false)
    ApplyEmbeddedHeaderFont(sessionWindow)
    sessionWindow:Show()
    RefreshEmbeddedStyleState(sessionWindow)
end

function EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin:DetachSessionWindow()
    if InCombatLockdown() then return end

    local sessionWindow = GetSessionWindow()
    if not sessionWindow then return end
    if not sessionWindow._uitoolbox_embedded then return end

    sessionWindow._uitoolbox_embedded = false

    local origParent = sessionWindow._uitoolbox_origParent or DamageMeter
    sessionWindow:SetParent(origParent)

    sessionWindow:ClearAllPoints()
    sessionWindow:SetPoint("TOPLEFT",     origParent, "TOPLEFT",     0,  0)
    sessionWindow:SetPoint("BOTTOMRIGHT", origParent, "BOTTOMRIGHT", 0,  0)
    if sessionWindow._uitoolbox_origClampedToScreen ~= nil then
        sessionWindow:SetClampedToScreen(sessionWindow._uitoolbox_origClampedToScreen)
    end
    RestoreHeaderFont(sessionWindow)
end

local frame = CreateFrame(
    "Frame",
    "EnhancedInterfaceObjectivesTrackerDamageMeterModule",
    ObjectiveTrackerFrame,
    "ObjectiveTrackerModuleTemplate"
)

Mixin(frame, EnhancedInterfaceObjectivesTrackerDamageMeterModuleMixin)

frame.headerText = "Damage Meter"
frame:SetHeader("Damage Meter")

-- uiOrder is assigned from Blizzard's call stack to keep the numeric value untainted.
hooksecurefunc(ObjectiveTrackerManager, "AssignModulesOrder", function(self, modules)
    EnhancedInterfaceObjectivesTrackerDamageMeterModule.uiOrder = #modules + 1
end)

local registered = false
local function TryRegister()
    if registered then return end
    if not (ObjectiveTrackerManager.containers
            and ObjectiveTrackerManager.containers[ObjectiveTrackerFrame]) then
        return
    end
    registered = true

    ObjectiveTrackerManager:SetModuleContainer(EnhancedInterfaceObjectivesTrackerDamageMeterModule, ObjectiveTrackerFrame)

    pendingUpdateAll = true
end

hooksecurefunc(ObjectiveTrackerManager, "Init", TryRegister)

local diag = CreateFrame("Frame")
diag:RegisterEvent("PLAYER_ENTERING_WORLD")
diag:SetScript("OnEvent", function()
    TryRegister()
end)

-- TAINT HAZARD: hooksecurefunc callbacks on EditModeManagerFrame methods run
-- inside the call chain that originates from C_EditMode.SetActiveLayout() calls
-- by any addon (e.g. AccWideUILayoutSelection).  That call chain carries taint
-- from those addons.  Any C_Timer.After closure created inside such a hook
-- inherits the tainted execution context and will propagate taint to whatever
-- it touches — including chat-frame internal state (ChatHistory_GetToken,
-- HistoryKeeper.lua), causing "attempt to perform string conversion on a secret
-- string value" errors.
--
-- Public accessor for other modules to request a deferred tracker refresh.
function EnhancedInterfaceObjectivesTrackerDamageMeterModule.RequestUpdateAll()
    pendingUpdateAll = true
end

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
            pendingReembed = true
        end
    end

    if TryHookMethod(EditModeManagerFrame, "ApplyLayoutToFrame", ReembedIfDamageMeter) then
        return
    end

    TryHookMethod(EditModeManagerFrame, "UpdateSystem", ReembedIfDamageMeter)
end

local function HookSessionWindowSize()
    local sessionWindow = GetSessionWindow()
    if not sessionWindow then return end

    sessionWindow:HookScript("OnSizeChanged", function(_, _, h)
        if h and h > 0 then
            cachedMeterHeight = h
        end
    end)
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookEditMode()
        HookSessionWindowSize()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

hookFrame:SetScript("OnUpdate", function()
    if pendingUpdateAll then
        if not InCombatLockdown() then
            pendingUpdateAll = false
            ObjectiveTrackerManager:UpdateAll()
        end
    end
    if pendingEmbed then
        pendingEmbed = false
        if ShouldEmbed() then
            EnhancedInterfaceObjectivesTrackerDamageMeterModule:EmbedSessionWindow()
        end
    end
    if pendingReembed then
        pendingReembed = false
        if ShouldEmbed() then
            EnhancedInterfaceObjectivesTrackerDamageMeterModule:EmbedSessionWindow()
        end
    end
end)
