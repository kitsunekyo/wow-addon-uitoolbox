-- EnhancedInterface
-- modules/PersonalResourceDisplay/features/BarStyling/PersonalResourceDisplay.lua

local PersonalResourceDisplay = {}
EnhancedInterfacePersonalResourceDisplayModule = PersonalResourceDisplay

local POWER_BAR_HEIGHT = 10
local HEALTH_BAR_HEIGHT = 10
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local DEFAULT_POWER_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local DEFAULT_PREDICTION_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_HEALTH_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local hooksInstalled = false
local applyingStyles = false  -- re-entrancy guard for ApplyToCurrentPlayerNameplate
-- Captured once before the first restyle is applied; used to restore original heights.
local originalHealthContainerHeight = nil
local originalPowerBarHeight = nil

local function IsHideHealthBarEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.personalResourceDisplay
        and EnhancedInterface.db.personalResourceDisplay.hideHealthBar
end

local function IsHideClassResourcesEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.personalResourceDisplay
        and EnhancedInterface.db.personalResourceDisplay.hideClassResources
end

local function IsRestyleBarsEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.personalResourceDisplay
        and EnhancedInterface.db.personalResourceDisplay.restylePowerBar
end

local function IsHideWhenMountedEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.personalResourceDisplay
        and EnhancedInterface.db.personalResourceDisplay.hideWhenMounted
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

-- Creates a single top-edge border texture on the power bar that matches Blizzard's
-- NamePlateSecondaryBarBorderTemplate color (black, 50% alpha) used for Bottom/Left/Right.
-- PowerBar.Border intentionally has no Top child (the health bar's bottom border fills that
-- gap normally). We add one here only when the health bar is hidden.
local function EnsurePowerBarTopBorder(powerBar)
    if powerBar.EnhancedInterfaceTopBorder then
        return
    end

    local tex = powerBar:CreateTexture(nil, "BACKGROUND", nil, -8)
    tex:SetColorTexture(0, 0, 0, 0.5)
    tex:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT")
    tex:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT")
    PixelUtil.SetHeight(tex, 1, 2)

    powerBar.EnhancedInterfaceTopBorder = tex
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
        -- PowerBar.Border provides Bottom/Left/Right — keep it visible.
        -- Add a matching Top texture since NamePlateSecondaryBarBorderTemplate has no Top child
        -- (normally the health bar's bottom border closes that gap).
        if powerBar.Border then
            powerBar.Border:SetShown(true)
        end
        EnsurePowerBarTopBorder(powerBar)
        powerBar.EnhancedInterfaceTopBorder:SetShown(true)
    else
        -- Restore Blizzard border unconditionally (safe even if we never touched it).
        if powerBar.EnhancedInterfaceTopBorder then
            powerBar.EnhancedInterfaceTopBorder:Hide()
        end
        if powerBar.Border then
            powerBar.Border:Show()
        end
    end
end

function PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    if applyingStyles then
        return
    end

    local frame = GetFrame()
    if not frame then
        return
    end

    applyingStyles = true
    ApplyHealthStyle(frame)
    ApplyPowerStyle(frame)
    ApplyClassResourceFrameStyle()
    self:ApplyMountVisibility()
    applyingStyles = false
end

function PersonalResourceDisplay:ApplyMountVisibility()
    local frame = GetFrame()
    if not frame then
        return
    end

    if InCombatLockdown() then
        -- Cannot call Hide/Show on protected frames mid-combat.
        -- PLAYER_REGEN_ENABLED will re-invoke this method once combat ends.
        return
    end

    if IsHideWhenMountedEnabled() and IsMounted() then
        frame:Hide()
    else
        -- Only call Show() when the frame is actually hidden to avoid interfering
        -- with Blizzard's own visibility management (e.g. during loading screens).
        if not frame:IsShown() then
            frame:Show()
        end
    end
end

function PersonalResourceDisplay:TryInstallHooks()
    if hooksInstalled then
        return
    end

    if not PersonalResourceDisplayMixin then
        return
    end

    -- Hook all three setup methods so any re-setup by Blizzard (spec change,
    -- power type change, entering world) immediately re-applies our styling.
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow", function()
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupHealthBar", function()
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", function()
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)

    -- Hook UpdateShownState so that whenever Blizzard re-evaluates whether the PRD
    -- should be visible (e.g. entering/leaving combat, zoning), we re-apply our
    -- mount-hide override immediately after its Show()/Hide() decision.
    hooksecurefunc(PersonalResourceDisplayMixin, "UpdateShownState", function()
        PersonalResourceDisplay:ApplyMountVisibility()
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

-- Install hooks immediately at module-load time.
-- Blizzard_PersonalResourceDisplay is declared as an OptionalDependency so it is
-- guaranteed to be loaded before EnhancedInterface; the mixin and frame exist now.
PersonalResourceDisplay:TryInstallHooks()

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        PersonalResourceDisplay:ApplyMountVisibility()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat just ended; flush any deferred mount-hide/show state.
        PersonalResourceDisplay:ApplyMountVisibility()
        return
    end

    -- PLAYER_ENTERING_WORLD: Blizzard fires its own PRD event handlers before ours
    -- (SetupPowerBar etc.), so our hooksecurefunc callbacks will have already run.
    -- We defer one frame via C_Timer.After to guarantee our apply runs after ALL
    -- Blizzard PLAYER_ENTERING_WORLD handlers for this session are complete,
    -- preventing any late Blizzard setup from overwriting our textures/heights.
    C_Timer.After(0, function()
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end)
end)
