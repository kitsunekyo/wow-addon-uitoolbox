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
-- Original heights of PRD sub-frames, captured from Blizzard's secure execution
-- context (ADDON_LOADED file-load time and/or OnSizeChanged C++ callbacks) so
-- the stored values are untainted.
--
-- TAINT HAZARD: GetHeight() called from addon code returns a tainted value.
-- Passing a tainted number to SetHeight() injects taint into the frame's C++
-- height property, which Blizzard's layout system reads in secure paths —
-- propagating taint into UIParent_ManageFramePositions() and causing downstream
-- "secret number value" errors (e.g. WorldMap pin SetPropagateMouseClicks).
--
-- Fix: capture via HookSizeCapture() (called from TryInstallHooks at file-load
-- time, a clean ADDON_LOADED context) and via OnSizeChanged hook arguments
-- (passed by the C++ engine, untainted).  GetHeight() is NOT called from any
-- tainted execution path.
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

-- Flag set by hooksecurefunc callbacks and events; consumed by the OnUpdate poller.
-- Declared here (before TryInstallHooks is called) so callbacks write to this local,
-- not an implicit global.
local pendingApply = false

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

    -- Never force-show the PRD if the player has disabled it in WoW's default
    -- settings (Interface > Combat > Personal Resource Display).  Blizzard's
    -- UpdateShownState uses C_GameRules.IsPersonalResourceDisplayEnabled() which
    -- reads the "nameplateShowSelf" CVar; we must honour that decision.
    if not C_GameRules.IsPersonalResourceDisplayEnabled() then
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

-- Capture the original heights of PRD sub-frames from an untainted execution
-- context.  Called once from TryInstallHooks() at file-load time (Blizzard's
-- ADDON_LOADED dispatch — a clean context), so the initial GetHeight() reads
-- are untainted.  OnSizeChanged hooks keep the values current via C++ engine
-- arguments (h is passed by the engine, not read from tainted addon code).
--
-- Only capture when restyle is currently OFF so we record the Blizzard-default
-- size, not a size we have already modified.  Once captured, the value is never
-- overwritten (the guard `not originalXxx` ensures idempotency).
function PersonalResourceDisplay:HookSizeCapture()
    local frame = GetFrame()
    if not frame then return end

    -- HealthBarsContainer
    if frame.HealthBarsContainer then
        -- Seed from current height if restyle is off (file-load context is clean).
        if not originalHealthContainerHeight and not IsRestyleBarsEnabled() then
            local h = frame.HealthBarsContainer:GetHeight()
            if h > 0 then originalHealthContainerHeight = h end
        end
        -- Keep updated via OnSizeChanged: h comes from the C++ engine, untainted.
        frame.HealthBarsContainer:HookScript("OnSizeChanged", function(_, _, h)
            if not originalHealthContainerHeight and not IsRestyleBarsEnabled() and h > 0 then
                originalHealthContainerHeight = h
            end
        end)
    end

    -- PowerBar
    if frame.PowerBar then
        if not originalPowerBarHeight and not IsRestyleBarsEnabled() then
            local h = frame.PowerBar:GetHeight()
            if h > 0 then originalPowerBarHeight = h end
        end
        frame.PowerBar:HookScript("OnSizeChanged", function(_, _, h)
            if not originalPowerBarHeight and not IsRestyleBarsEnabled() and h > 0 then
                originalPowerBarHeight = h
            end
        end)
    end
end

function PersonalResourceDisplay:TryInstallHooks()
    if hooksInstalled then
        return
    end

    if not PersonalResourceDisplayMixin then
        return
    end

    -- Capture original sub-frame heights from the clean ADDON_LOADED file-load
    -- context, then keep them updated via OnSizeChanged (C++ engine arguments,
    -- untainted).  This replaces the former lazy GetHeight() reads inside
    -- ApplyHealthStyle/ApplyPowerStyle, which returned tainted values when called
    -- from hooksecurefunc callbacks or the OnUpdate poller.
    self:HookSizeCapture()

    -- Hook all three setup methods so any re-setup by Blizzard (spec change,
    -- power type change, entering world) triggers a re-apply of our styling.
    --
    -- TAINT HAZARD: These hooks fire inside Blizzard's own call chains, but
    -- those chains can be reached from tainted addon code (e.g. another addon
    -- calling PersonalResourceDisplayFrame:Show(), or triggering a power-type
    -- change that Blizzard handles by calling SetupPowerBar).  Calling
    -- ApplyToCurrentPlayerNameplate() directly from these hooks means
    -- PixelUtil.SetHeight() and SetPoint() on PRD sub-frames run in that tainted
    -- context.  SetHeight() on an Edit Mode managed frame injects taint into its
    -- C++ height property, which UIParent_ManageFramePositions() propagates into
    -- the entire frame stack — causing downstream "secret number value" errors
    -- in widget layout (LayoutFrame.lua:491 GetNumPoints comparison) when the
    -- player hovers over an Area POI on the map.
    --
    -- Fix: set pendingApply = true (a plain boolean write, no taint spread) and
    -- let the OnUpdate poller perform the actual geometry writes from the clean
    -- C++ game loop context.
    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow", function()
        pendingApply = true
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupHealthBar", function()
        pendingApply = true
    end)

    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", function()
        pendingApply = true
    end)

    -- Hook UpdateShownState so that whenever Blizzard re-evaluates whether the PRD
    -- should be visible (e.g. entering/leaving combat, zoning), we re-apply our
    -- mount-hide override.  Same taint rationale as above — defer via flag.
    hooksecurefunc(PersonalResourceDisplayMixin, "UpdateShownState", function()
        pendingApply = true
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

-- pendingApply is declared near the top of the file (before TryInstallHooks) so
-- that the hooksecurefunc callbacks inside TryInstallHooks reference the same local.
-- See the TAINT HAZARD comment there for rationale.

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

    -- PLAYER_ENTERING_WORLD: defer one tick via OnUpdate (see pendingApply above).
    pendingApply = true
end)

initFrame:SetScript("OnUpdate", function()
    if pendingApply then
        pendingApply = false
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end
end)
