-- UIToolbox
-- modules/PersonalResourceDisplay/features/BarStyling/PersonalResourceDisplay.lua

local PersonalResourceDisplay = {}
UIToolboxPersonalResourceDisplayModule = PersonalResourceDisplay

local POWER_BAR_HEIGHT = 10
local HEALTH_BAR_HEIGHT = 10
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local DEFAULT_POWER_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local DEFAULT_PREDICTION_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_HEALTH_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local hooksInstalled = false
-- Captured once before the first restyle is applied; used to restore original heights.
local originalHealthContainerHeight = nil
local originalPowerBarHeight = nil

local function IsHideHealthBarEnabled()
    return UIToolbox.db
        and UIToolbox.db.personalResourceDisplay
        and UIToolbox.db.personalResourceDisplay.hideHealthBar
end

local function IsHideClassResourcesEnabled()
    return UIToolbox.db
        and UIToolbox.db.personalResourceDisplay
        and UIToolbox.db.personalResourceDisplay.hideClassResources
end

local function IsRestyleBarsEnabled()
    return UIToolbox.db
        and UIToolbox.db.personalResourceDisplay
        and UIToolbox.db.personalResourceDisplay.restylePowerBar
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

local hiddenClassResourceFrames = {}

local function ApplyClassResourceFrameStyle()
    if IsHideClassResourcesEnabled() then
        for _, frameName in ipairs(CLASS_RESOURCE_FRAMES) do
            local frame = _G[frameName]
            if frame and frame:IsShown() then
                frame:Hide()
                hiddenClassResourceFrames[frameName] = true
            end
        end
    else
        for frameName, _ in pairs(hiddenClassResourceFrames) do
            local frame = _G[frameName]
            if frame then
                frame:Show()
            end
        end
        wipe(hiddenClassResourceFrames)
    end
end

local function EnsurePowerBarBorder(powerBar)
    if powerBar.UIToolboxUniformBorder then
        return
    end

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

local function UpdatePowerBarBorder(powerBar)
    local border = powerBar.UIToolboxUniformBorder
    if not border then
        return
    end

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
end

local function ApplyHealthStyle(frame)
    if not frame or not frame.HealthBarsContainer then
        return
    end

    local hideHealth = IsHideHealthBarEnabled()
    local restyle = IsRestyleBarsEnabled()

    if hideHealth then
        frame.HealthBarsContainer:Hide()
        return
    end

    -- Health bar is visible: always write the correct state unconditionally.
    -- This ensures toggling hideHealth or restyle in any order lands correctly.
    frame.HealthBarsContainer:Show()
    local healthBar = frame.HealthBarsContainer.healthBar
    if not healthBar then
        return
    end

    if restyle then
        if not originalHealthContainerHeight then
            originalHealthContainerHeight = frame.HealthBarsContainer:GetHeight()
        end
        healthBar:SetStatusBarTexture(BAR_TEXTURE)
        PixelUtil.SetHeight(frame.HealthBarsContainer, HEALTH_BAR_HEIGHT)
    else
        -- Restore Blizzard defaults unconditionally — no prior-state guard needed.
        healthBar:SetStatusBarTexture(DEFAULT_HEALTH_BAR_TEXTURE)
        if originalHealthContainerHeight then
            frame.HealthBarsContainer:SetHeight(originalHealthContainerHeight)
        end
    end
end

local function ApplyPowerStyle(frame)
    local powerBar = frame and frame.PowerBar
    if not powerBar then
        return
    end

    local restyle = IsRestyleBarsEnabled()
    local hideHealth = IsHideHealthBarEnabled()

    -- Reposition: power bar anchors to top of frame when health is hidden, otherwise below health.
    if hideHealth then
        powerBar:ClearAllPoints()
        powerBar:SetPoint("TOP", frame, "TOP")
    else
        powerBar:ClearAllPoints()
        powerBar:SetPoint("TOP", frame.HealthBarsContainer, "BOTTOM")
    end

    -- Texture and height: always write correct state unconditionally.
    if restyle then
        if not originalPowerBarHeight then
            originalPowerBarHeight = powerBar:GetHeight()
        end
        powerBar:SetStatusBarTexture(BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(BAR_TEXTURE)
        end
        PixelUtil.SetHeight(powerBar, POWER_BAR_HEIGHT)
    else
        -- Restore Blizzard defaults unconditionally.
        powerBar:SetStatusBarTexture(DEFAULT_POWER_BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(DEFAULT_PREDICTION_TEXTURE)
        end
        if originalPowerBarHeight then
            powerBar:SetHeight(originalPowerBarHeight)
        end
    end

    -- Border: only managed when hideHealth is enabled.
    -- restyle alone never touches borders.
    if hideHealth then
        EnsurePowerBarBorder(powerBar)
        UpdatePowerBarBorder(powerBar)
        powerBar.UIToolboxUniformBorder:SetShown(true)
        if powerBar.Border then
            powerBar.Border:SetShown(false)
        end
    else
        -- Restore Blizzard border unconditionally (safe even if we never touched it).
        if powerBar.UIToolboxUniformBorder then
            powerBar.UIToolboxUniformBorder:Hide()
        end
        if powerBar.Border then
            powerBar.Border:Show()
        end
    end
end

function PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    local frame = GetFrame()
    if not frame then
        return
    end

    ApplyHealthStyle(frame)
    ApplyPowerStyle(frame)
    ApplyClassResourceFrameStyle()
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
            if IsHideHealthBarEnabled() then
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
