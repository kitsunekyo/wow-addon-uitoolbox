-- UIToolbox
-- modules/PersonalResourceDisplay/features/BarStyling/PersonalResourceDisplay.lua

local PersonalResourceDisplay = {}
UIToolboxPersonalResourceDisplayModule = PersonalResourceDisplay

local POWER_BAR_HEIGHT = 10
local DEFAULT_POWER_BAR_HEIGHT = 15
local POWER_BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local DEFAULT_POWER_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local DEFAULT_PREDICTION_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local hooksInstalled = false

local function IsEnabled()
    return UIToolbox.db
        and UIToolbox.db.personalResourceDisplay
        and UIToolbox.db.personalResourceDisplay.enabled
end

local function GetFrame()
    return _G.PersonalResourceDisplayFrame
end

-- All class-specific resource frames that sit below PlayerFrame as separate widgets.
-- These are hidden when custom bars are enabled so they don't overlap the PRD.
-- Frames embedded inside PlayerFrame (e.g. MonkStaggerBar, InsanityBarFrame) are
-- intentionally excluded — they overlay the mana bar area, not a separate widget.
local CLASS_RESOURCE_FRAMES = {
    "RuneFrame",              -- Death Knight  (runes)
    "WarlockPowerFrame",      -- Warlock       (soul shards)
    "PaladinPowerBarFrame",   -- Paladin       (holy power)
    "RogueComboPointBarFrame",-- Rogue         (combo points)
    "DruidComboPointBarFrame",-- Druid         (combo points in cat form)
    "MonkHarmonyBarFrame",    -- Monk WW       (chi orbs)
    "MageArcaneChargesFrame", -- Mage Arcane   (arcane charges)
    "EssencePlayerFrame",     -- Evoker        (essence orbs)
}

local function ApplyClassResourceFrameStyle(enabled)
    for _, frameName in ipairs(CLASS_RESOURCE_FRAMES) do
        local frame = _G[frameName]
        if frame then
            if enabled then
                frame:Hide()
            else
                frame:Show()
            end
        end
    end
end

local function ApplyHealthStyle(frame, enabled)
    if not frame or not frame.HealthBarsContainer then
        return
    end

    if enabled then
        frame.HealthBarsContainer:Hide()
    else
        frame.HealthBarsContainer:Show()
    end
end

local function ApplyPowerStyle(frame, enabled)
    local powerBar = frame and frame.PowerBar
    if not powerBar then
        return
    end

    if not powerBar.UIToolboxUniformBorder then
        local border = CreateFrame("Frame", nil, powerBar)
        border:SetAllPoints(powerBar)

        local top = border:CreateTexture(nil, "BACKGROUND")
        top:SetColorTexture(0, 0, 0, 0.5)

        local bottom = border:CreateTexture(nil, "BACKGROUND")
        bottom:SetColorTexture(0, 0, 0, 0.5)

        local left = border:CreateTexture(nil, "BACKGROUND")
        left:SetColorTexture(0, 0, 0, 0.5)

        local right = border:CreateTexture(nil, "BACKGROUND")
        right:SetColorTexture(0, 0, 0, 0.5)

        border.top = top
        border.bottom = bottom
        border.left = left
        border.right = right
        powerBar.UIToolboxUniformBorder = border
    end

    powerBar:ClearAllPoints()

    if enabled then
        powerBar:SetPoint("TOP", frame, "TOP")
        powerBar:SetStatusBarTexture(POWER_BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(POWER_BAR_TEXTURE)
        end
        PixelUtil.SetHeight(powerBar, POWER_BAR_HEIGHT)
    else
        powerBar:SetPoint("TOP", frame.HealthBarsContainer, "BOTTOM")
        powerBar:SetStatusBarTexture(DEFAULT_POWER_BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(DEFAULT_PREDICTION_TEXTURE)
        end
        PixelUtil.SetHeight(powerBar, DEFAULT_POWER_BAR_HEIGHT)
    end

    if powerBar.UIToolboxUniformBorder then
        local border = powerBar.UIToolboxUniformBorder

        border.top:ClearAllPoints()
        border.top:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT")
        border.top:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT")
        PixelUtil.SetHeight(border.top, 1)

        border.bottom:ClearAllPoints()
        border.bottom:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT")
        border.bottom:SetPoint("TOPRIGHT", powerBar, "BOTTOMRIGHT")
        PixelUtil.SetHeight(border.bottom, 1)

        border.left:ClearAllPoints()
        border.left:SetPoint("TOPRIGHT", powerBar, "TOPLEFT")
        border.left:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMLEFT")
        PixelUtil.SetWidth(border.left, 1)

        border.right:ClearAllPoints()
        border.right:SetPoint("TOPLEFT", powerBar, "TOPRIGHT")
        border.right:SetPoint("BOTTOMLEFT", powerBar, "BOTTOMRIGHT")
        PixelUtil.SetWidth(border.right, 1)

        border:SetShown(enabled)
    end

    if powerBar.Border then
        powerBar.Border:SetShown(not enabled)
    end
end

function PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    local frame = GetFrame()
    if not frame then
        return
    end

    local enabled = IsEnabled()
    ApplyHealthStyle(frame, enabled)
    ApplyPowerStyle(frame, enabled)
    ApplyClassResourceFrameStyle(enabled)
end

function PersonalResourceDisplay:TryInstallHooks()
    if hooksInstalled then
        return
    end

    if not PersonalResourceDisplayMixin then
        return
    end

    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow", function(self)
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupHealthBar", function(self)
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", function(self)
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    -- Hook HealthBarsContainer:Show directly so any Show() call from Blizzard code
    -- (e.g. inside SetupHealthBar at the end, or future callers) is intercepted.
    -- This runs after our per-method hooks and re-hides the container whenever
    -- the feature is enabled, closing the race window entirely.
    local frame = GetFrame()
    if frame and frame.HealthBarsContainer then
        hooksecurefunc(frame.HealthBarsContainer, "Show", function()
            if IsEnabled() then
                frame.HealthBarsContainer:Hide()
            end
        end)
    end

    hooksInstalled = true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Blizzard_PersonalResourceDisplay" then
            PersonalResourceDisplay:TryInstallHooks()
            PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
        end
        return
    end

    PersonalResourceDisplay:TryInstallHooks()
    PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
end)
