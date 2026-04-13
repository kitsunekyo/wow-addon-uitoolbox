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

listenerFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Defer one frame so Blizzard's own PRD setup finishes first.
        C_Timer.After(0, function()
            EnsureLabel()
            UpdateLabel()
        end)
        return
    end

    UpdateLabel()
end)

-- ── Hook PRD setup so the label survives spec/power-type changes ──────────────

-- Blizzard re-parents and re-creates parts of the power bar on SetupPowerBar
-- and OnShow. Invalidate and re-create our label after each such call so it
-- stays on the correct bar instance.
local function OnPRDSetup()
    powerLabel = nil
    EnsureLabel()
    UpdateLabel()
end

if PersonalResourceDisplayMixin then
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", OnPRDSetup)
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow",        OnPRDSetup)
end

-- Export module for use in EditModeIntegration
_G.EnhancedInterfacePowerValueDisplayModule = PowerValueDisplay
