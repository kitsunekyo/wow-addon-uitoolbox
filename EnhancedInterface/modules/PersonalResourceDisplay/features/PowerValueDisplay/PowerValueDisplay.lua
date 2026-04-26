-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/PowerValueDisplay/PowerValueDisplay.lua
--
-- Displays the player's current primary power value (mana, rage, energy, runic
-- power, focus, fury, etc.) as a number centered on the Personal Resource
-- Display power bar. Works for all classes — the power type is determined
-- dynamically via UnitPowerType each update.
--
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

local powerLabel  = nil  -- the FontString we create once and reuse
local hookedBars  = {}   -- set of class-nameplate power-bar instances we've hooked

local function IsEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.powerValueDisplay
        and EnhancedInterface.db.powerValueDisplay.enabled
end

local function GetPowerBar()
    local frame = _G.PersonalResourceDisplayFrame
    return frame and frame.PowerBar
end

-- Create the label.  Idempotent — safe to call multiple times.
--
-- IMPORTANT: this function MUST NOT call SetFont or SetFontObject with a
-- custom Blizzard-side font object that hasn't already been measured.  We
-- inherit everything from NumberFontNormal (a Blizzard font object loaded
-- from FrameXML) via the template argument to CreateFontString.
local function EnsureLabel()
    if powerLabel then
        -- Re-parent to the current PowerBar in case Blizzard re-created it.
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

    -- Inherit font, size, outline, shadow from NumberFontNormal.  No SetFont
    -- call, no metrics cache write.
    powerLabel = powerBar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    powerLabel:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
    powerLabel:SetText("")
end

-- Read the current power value and write it into the label.  Called only
-- from the `hooksecurefunc` callbacks on Blizzard's UpdatePower / UpdateMaxPower
-- methods, which run in a clean Blizzard-dispatched context.
local function WritePowerText()
    if not IsEnabled() then
        if powerLabel then powerLabel:Hide() end
        return
    end
    EnsureLabel()
    if not powerLabel then return end
    powerLabel:Show()
    local powerType = UnitPowerType("player")
    local current   = UnitPower("player", powerType)
    powerLabel:SetText(tostring(current))
end

-- ── Hook the class-nameplate power bar(s) ─────────────────────────────────
-- The class-nameplate bars (mana bar + class resource bar) are owned by
-- NamePlateDriverFrame.  Their `UpdatePower` / `UpdateMaxPower` methods are
-- invoked from Blizzard's own OnEvent, so hooksecurefunc callbacks fire
-- in a clean execution context — SetText is safe.

local function HookBar(bar)
    if not bar or hookedBars[bar] then return end
    hookedBars[bar] = true

    if type(bar.UpdatePower) == "function" then
        hooksecurefunc(bar, "UpdatePower", WritePowerText)
    end
    if type(bar.UpdateMaxPower) == "function" then
        hooksecurefunc(bar, "UpdateMaxPower", WritePowerText)
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

-- Public: called by SettingsUI / EditModeIntegration to apply enable/disable
-- changes immediately.  Property-only mutation on our own FontString — no
-- metrics-cache write — so even from a tainted UI callback context this is
-- safe.
function PowerValueDisplay:SetEnabled(enabled)
    EnhancedInterface.db.powerValueDisplay.enabled = enabled
    if enabled then
        EnsureLabel()
        HookAllBars()
        WritePowerText()
    elseif powerLabel then
        powerLabel:Hide()
    end
end

-- ── Setup hooks (capture bar swaps from spec / power-type changes) ────────
-- PRD setup hooks fire when Blizzard re-creates / re-parents the power bar
-- under the PRD frame.  We re-ensure our label is parented to the current
-- bar.  These hooks fire from Blizzard's own setup paths (clean context).

local function OnPRDSetup()
    EnsureLabel()
end

if PersonalResourceDisplayMixin then
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", OnPRDSetup)
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow",        OnPRDSetup)
end

-- ── Watcher: re-hook when Blizzard swaps the class-nameplate bar instance ─
-- UNIT_DISPLAYPOWER and PLAYER_TALENT_UPDATE indicate spec/power-type
-- changes that may swap the class-nameplate bar instance.  This watcher's
-- OnEvent runs tainted (we registered the events from addon code), but it
-- only calls hooksecurefunc and EnsureLabel — both are setup-time mutations
-- that do not touch the font-metrics cache.

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
watcher:SetScript("OnEvent", function()
    EnsureLabel()
    HookAllBars()
end)

-- Try at file load (NamePlateDriverFrame is a hard-loaded global).
EnsureLabel()
HookAllBars()

-- Export module for use in EditModeIntegration
_G.EnhancedInterfacePowerValueDisplayModule = PowerValueDisplay
