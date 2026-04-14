-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/PowerValueDisplay/PowerValueDisplay.lua
--
-- Displays the player's current primary power value (mana, rage, energy, runic
-- power, focus, fury, etc.) as a number centered on the Personal Resource
-- Display power bar. Works for all classes — the power type is determined
-- dynamically via UnitPowerType each update.

local PowerValueDisplay = {}

local powerLabel = nil  -- the FontString we create once and reuse

local function IsEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.powerValueDisplay
        and EnhancedInterface.db.powerValueDisplay.enabled
end

local function GetPowerBar()
    local frame = _G.PersonalResourceDisplayFrame
    return frame and frame.PowerBar
end

-- Create the label the first time (idempotent — safe to call multiple times).
local function EnsureLabel()
    if powerLabel then
        return
    end

    local powerBar = GetPowerBar()
    if not powerBar then
        return
    end

    powerLabel = powerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    powerLabel:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
    powerLabel:SetTextColor(1, 1, 1, 1)
    powerLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    powerLabel:SetShadowColor(0, 0, 0, 1)
    powerLabel:SetShadowOffset(2, -2)
    powerLabel:SetText("")
end

-- Update the displayed value from the live UnitPower API.
local function UpdateLabel()
    if not IsEnabled() then
        if powerLabel then
            powerLabel:Hide()
        end
        return
    end

    EnsureLabel()
    if not powerLabel then
        return
    end

    powerLabel:Show()
    local powerType = UnitPowerType("player")
    local current   = UnitPower("player", powerType)
    powerLabel:SetText(tostring(current))
end

function PowerValueDisplay:SetEnabled(enabled)
    EnhancedInterface.db.powerValueDisplay.enabled = enabled
    UpdateLabel()
end

-- ── Event listener ────────────────────────────────────────────────────────────

local listenerFrame = CreateFrame("Frame")
listenerFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
listenerFrame:RegisterUnitEvent("UNIT_MAXPOWER",       "player")
listenerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Flag set by PLAYER_ENTERING_WORLD; consumed by the OnUpdate poller below.
--
-- TAINT HAZARD: PLAYER_ENTERING_WORLD can fire inside a call chain tainted by
-- another addon.  Any C_Timer.After closure created there would bake in that
-- taint and propagate it into EnsureLabel/UpdateLabel, which writes to frame
-- properties that Blizzard's secure layout code may later read — potentially
-- causing ADDON_ACTION_BLOCKED (e.g. SetPropagateMouseClicks) when the WorldMap
-- opens via FlightPointDataProvider → MapCanvas pins → UpdateMousePropagation.
-- Using a plain boolean flag (no closure) and consuming it from the OnUpdate
-- poller (C++ game loop origin, clean context) breaks that taint chain.
local pendingInit = false

-- Flag set by UNIT_POWER_FREQUENT / UNIT_MAXPOWER; consumed by the OnUpdate
-- poller below.
--
-- TAINT HAZARD: UNIT_* events fire continuously during combat and can fire
-- inside a call chain tainted by another addon.  Calling UpdateLabel() directly
-- from that context writes to the power label FontString (a child of
-- PersonalResourceDisplayFrame.PowerBar, an Edit Mode system frame), potentially
-- propagating taint into Blizzard's secure layout paths.
-- Deferring through the OnUpdate poller breaks the taint chain.
-- Side benefit: multiple UNIT_POWER_FREQUENT fires per frame are coalesced into
-- a single UpdateLabel() call, reducing per-frame work during combat.
local pendingUpdate = false

-- Flag set by hooksecurefunc callbacks on SetupPowerBar / OnShow; consumed by
-- the OnUpdate poller below.
--
-- TAINT HAZARD: hooksecurefunc callbacks on PersonalResourceDisplayMixin methods
-- run inside Blizzard's own call chain, but that chain can be reached from
-- tainted addon code (e.g. another addon triggering a power-type change or
-- calling PersonalResourceDisplayFrame:Show()).  Calling EnsureLabel() /
-- UpdateLabel() directly from those callbacks executes SetFont / SetText on the
-- power label FontString while the execution context is tainted.  SetFont taints
-- the global font-metrics cache; any subsequent call to GetStringHeight() on
-- *any* FontString — including Blizzard's UIWidget text frames — returns a
-- tainted value.  When Blizzard's UIWidgetTemplateTextWithState:Setup() reads
-- that tainted height via self.Text:GetStringHeight() and feeds it into
-- Clamp() / SetHeight(), it propagates the taint, producing the error:
--   "attempt to perform arithmetic on local 'textHeight'
--    (a secret number value tainted by 'EnhancedInterface')"
-- Fix: only flip a boolean flag inside the hook (no font/text writes).  The
-- OnUpdate poller fires from the C++ game loop's own call origin, breaking the
-- taint chain before EnsureLabel/UpdateLabel run.
local pendingSetup = false

listenerFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Defer one tick via OnUpdate (see pendingInit above).
        pendingInit = true
        return
    end

    -- UNIT_POWER_FREQUENT / UNIT_MAXPOWER: defer via OnUpdate (see pendingUpdate above).
    pendingUpdate = true
end)

listenerFrame:SetScript("OnUpdate", function()
    if pendingInit then
        pendingInit = false
        EnsureLabel()
        UpdateLabel()
    end
    if pendingUpdate then
        pendingUpdate = false
        UpdateLabel()
    end
    if pendingSetup then
        pendingSetup = false
        EnsureLabel()
        UpdateLabel()
    end
end)

-- ── Hook PRD setup so the label survives spec/power-type changes ──────────────
-- Blizzard re-parents and re-creates parts of the power bar on SetupPowerBar
-- and OnShow. We invalidate and re-create our label after each such call so it
-- stays on the correct bar instance.  See pendingSetup above for taint rationale.

local function OnPRDSetup()
    -- Only set a flag — do NOT call EnsureLabel/UpdateLabel here.
    -- See TAINT HAZARD comment above.
    -- Nil out the label reference so EnsureLabel() will recreate it on the
    -- next OnUpdate tick (safe: this is a plain local write, no frame access).
    powerLabel = nil
    pendingSetup = true
end

if PersonalResourceDisplayMixin then
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", OnPRDSetup)
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow",        OnPRDSetup)
end

-- Export module for use in EditModeIntegration
_G.EnhancedInterfacePowerValueDisplayModule = PowerValueDisplay
