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
--   1. The FontString is created at file-load time (a clean, Blizzard-driven
--      ADDON_LOADED dispatch context).  CreateFontString uses the third
--      argument NumberFontNormal so no SetFont metrics-cache write happens.
--   2. SetText is driven exclusively from `hooksecurefunc` callbacks on
--      Blizzard-owned methods on the class-nameplate power bar
--      (`UpdatePower`, `UpdateMaxPower`).  Those methods are invoked by
--      Blizzard's own OnEvent (Blizzard-registered for UNIT_POWER_FREQUENT /
--      UNIT_MAXPOWER on the bar instance), so our hook runs in a clean
--      execution context.  SetText from there does NOT taint the cache.
--   3. The class-nameplate power bar instance is swapped by Blizzard when
--      the player changes spec or display power (UNIT_DISPLAYPOWER).  We
--      re-hook the new bar from a watcher OnEvent.  Re-hooking only calls
--      `hooksecurefunc` (a setup-time mutation, doesn't touch frame state)
--      and a property-only Show()/Hide() and SetParent on our own
--      FontString, so even though the watcher is addon-registered, no
--      metrics-cache poisoning occurs.

local PowerValueDisplay = {}

local powerLabel  = nil
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

-- IMPORTANT: this function MUST NOT call SetFont or SetFontObject with a
-- custom Blizzard-side font object that hasn't already been measured.  We
-- inherit everything from NumberFontNormal (a Blizzard font object loaded
-- from FrameXML) via the template argument to CreateFontString.
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

    powerLabel = powerBar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
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
