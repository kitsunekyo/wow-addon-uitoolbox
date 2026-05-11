-- TAINT MODEL — read this before changing anything in this file
-- ─────────────────────────────────────────────────────────────
-- Common misconception: "OnUpdate handlers run from the C++ game loop, so
-- they are a clean execution context."  That is FALSE for OnUpdate handlers
-- registered by addons.  When an addon creates a frame and calls
-- SetScript("OnUpdate", fn), the engine invokes fn with the registering
-- addon's taint stamp on the execution stack.  Any C-implemented mutator
-- called inside that handler runs tainted.
--
-- Likewise, addon-registered OnEvent handlers (`SetScript("OnEvent", ...)`
-- on a frame whose events were registered via `frame:RegisterEvent` from
-- addon code) run tainted.  Calling SetText from such a context applies
-- a "Text aspect" (Patch 12.0.0 Secret Values system) to the FontString
-- and can poison the global font-metrics cache slot for that font, causing
-- crashes like:
--   • UIWidgetTemplateTextWithState:Setup -> textHeight (secret number)
--   • SharedTooltipTemplates              -> arithmetic on secret number
--   • ADDON_ACTION_BLOCKED PerformEmote() (WorldMap show path)
--
-- Strategy used here:
--   1. The label uses an addon-private font object instead of shared Blizzard
--      font objects such as NumberFontNormal.
--   2. Hooks and events only mark pending state; the actual label updates are
--      coalesced by the poller below.

local PowerValueDisplay = {}

local powerLabel  = nil
local powerFont   = nil
local hookedBars  = {}
local pendingRefresh = false
local pendingText = nil
local pendingTextDirty = false

local function IsEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.powerValueDisplay
        and EnhancedInterface.db.powerValueDisplay.enabled
end

local function GetPowerBar()
    local frame = _G.PersonalResourceDisplayFrame
    return frame and frame.PowerBar
end

local function EnsureFont()
    if powerFont then return powerFont end

    powerFont = CreateFont("EnhancedInterfacePowerValueFont")
    powerFont:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    powerFont:SetTextColor(1, 1, 1, 1)
    powerFont:SetShadowColor(0, 0, 0, 1)
    powerFont:SetShadowOffset(1, -1)

    return powerFont
end

local function EnsureLabel()
    if powerLabel then
        local powerBar = GetPowerBar()
        if powerBar and powerLabel:GetParent() ~= powerBar then
            powerLabel:SetParent(powerBar)
            powerLabel:ClearAllPoints()
            powerLabel:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
        end
        return
    end

    local powerBar = GetPowerBar()
    if not powerBar then
        return
    end

    powerLabel = powerBar:CreateFontString(nil, "OVERLAY")
    powerLabel:SetFontObject(EnsureFont())
    powerLabel:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
end

local function QueuePowerTextRefresh()
    if not IsEnabled() then
        pendingText = nil
        pendingTextDirty = true
        return
    end

    local powerType = UnitPowerType("player")
    local current   = UnitPower("player", powerType)
    pendingText = tostring(current)
    pendingTextDirty = true
end

local function HookBar(bar)
    if not bar or hookedBars[bar] then return end
    hookedBars[bar] = true

    if type(bar.UpdatePower) == "function" then
        hooksecurefunc(bar, "UpdatePower", QueuePowerTextRefresh)
    end
    if type(bar.UpdateMaxPower) == "function" then
        hooksecurefunc(bar, "UpdateMaxPower", QueuePowerTextRefresh)
    end
end

local function HookAllBars()
    if not _G.NamePlateDriverFrame then return end
    if NamePlateDriverFrame.GetClassNameplateManaBar then
        HookBar(NamePlateDriverFrame:GetClassNameplateManaBar())
    end
    if NamePlateDriverFrame.GetClassNameplateBar then
        HookBar(NamePlateDriverFrame:GetClassNameplateBar())
    end
end

function PowerValueDisplay:SetEnabled(enabled)
    EnhancedInterface.db.powerValueDisplay.enabled = enabled
    pendingRefresh = true
    pendingTextDirty = true
end

local function OnPRDSetup()
    pendingRefresh = true
end

if PersonalResourceDisplayMixin then
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", OnPRDSetup)
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow",        OnPRDSetup)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
watcher:SetScript("OnEvent", function()
    pendingRefresh = true
    pendingTextDirty = true
    HookAllBars()
end)

pendingRefresh = true
pendingTextDirty = true
HookAllBars()

local poller = CreateFrame("Frame")
poller:SetScript("OnUpdate", function()
    if pendingRefresh then
        pendingRefresh = false
        EnsureLabel()
    end

    if pendingTextDirty then
        pendingTextDirty = false

        if not IsEnabled() then
            if powerLabel then
                powerLabel:Hide()
            end
            return
        end

        EnsureLabel()
        if not powerLabel then return end

        powerLabel:Show()
        powerLabel:SetText(pendingText or "")
    end
end)

_G.EnhancedInterfacePowerValueDisplayModule = PowerValueDisplay
