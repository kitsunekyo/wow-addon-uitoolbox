local PersonalResourceDisplay = {}
EnhancedInterfacePersonalResourceDisplayModule = PersonalResourceDisplay

local POWER_BAR_HEIGHT = 10
local HEALTH_BAR_HEIGHT = 10
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local DEFAULT_POWER_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local DEFAULT_PREDICTION_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_HEALTH_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local hooksInstalled = false
local applyingStyles = false

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

local CLASS_RESOURCE_FRAMES = {
    "RuneFrame",
    "WarlockPowerFrame",
    "PaladinPowerBarFrame",
    "RogueComboPointBarFrame",
    "DruidComboPointBarFrame",
    "MonkHarmonyBarFrame",
    "MageArcaneChargesFrame",
    "EssencePlayerFrame",
}

local hiddenClassResourceFrames = {}

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

    frame.HealthBarsContainer:Show()
    local healthBar = frame.HealthBarsContainer.healthBar
    if not healthBar then
        return
    end

    if restyle then
        healthBar:SetStatusBarTexture(BAR_TEXTURE)
        PixelUtil.SetHeight(frame.HealthBarsContainer, HEALTH_BAR_HEIGHT)
    else
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

    if hideHealth then
        powerBar:ClearAllPoints()
        powerBar:SetPoint("TOP", frame, "TOP")
    else
        powerBar:ClearAllPoints()
        powerBar:SetPoint("TOP", frame.HealthBarsContainer, "BOTTOM")
    end

    if restyle then
        powerBar:SetStatusBarTexture(BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(BAR_TEXTURE)
        end
        PixelUtil.SetHeight(powerBar, POWER_BAR_HEIGHT)
    else
        powerBar:SetStatusBarTexture(DEFAULT_POWER_BAR_TEXTURE)
        if powerBar.ManaCostPredictionBar then
            powerBar.ManaCostPredictionBar:SetTexture(DEFAULT_PREDICTION_TEXTURE)
        end
        if originalPowerBarHeight then
            powerBar:SetHeight(originalPowerBarHeight)
        end
    end

    if hideHealth then
        if powerBar.Border then
            powerBar.Border:SetShown(true)
        end
        EnsurePowerBarTopBorder(powerBar)
        powerBar.EnhancedInterfaceTopBorder:SetShown(true)
    else
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
        return
    end

    if not C_GameRules.IsPersonalResourceDisplayEnabled() then
        return
    end

    if IsHideWhenMountedEnabled() and IsMounted() then
        frame:Hide()
    else
        if not frame:IsShown() then
            frame:Show()
        end
    end
end

function PersonalResourceDisplay:HookSizeCapture()
    local frame = GetFrame()
    if not frame then return end

    if frame.HealthBarsContainer then
        if not originalHealthContainerHeight and not IsRestyleBarsEnabled() then
            local h = frame.HealthBarsContainer:GetHeight()
            if h > 0 then originalHealthContainerHeight = h end
        end
        frame.HealthBarsContainer:HookScript("OnSizeChanged", function(_, _, h)
            if not originalHealthContainerHeight and not IsRestyleBarsEnabled() and h > 0 then
                originalHealthContainerHeight = h
            end
        end)
    end

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

    self:HookSizeCapture()

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

    hooksecurefunc(PersonalResourceDisplayMixin, "UpdateShownState", function()
        pendingApply = true
    end)

    -- TAINT HAZARD: calling frame.HealthBarsContainer:Hide() directly from this
    -- hook runs in Blizzard's call chain, which can be reached from tainted addon
    -- code (e.g. another addon calling SetupHealthBar). Hide() on a PRD sub-frame
    -- in a tainted context propagates taint into the PRD layout system.
    -- Fix: set pendingApply = true (plain boolean write) and let OnUpdate handle it.
    local frame = GetFrame()
    if frame and frame.HealthBarsContainer then
        hooksecurefunc(frame.HealthBarsContainer, "Show", function()
            if IsHideHealthBarEnabled() then
                pendingApply = true
            end
        end)
    end

    hooksInstalled = true
end

function PersonalResourceDisplay:RequestApply()
    pendingApply = true
end

PersonalResourceDisplay:TryInstallHooks()

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- TAINT HAZARD: PLAYER_MOUNT_DISPLAY_CHANGED can fire inside a tainted call
        -- chain (e.g. another addon triggering a mount state change). Calling
        -- ApplyMountVisibility() directly here calls frame:Hide()/Show() on a
        -- protected Edit Mode frame from a potentially tainted context, spreading
        -- taint into UIParent_ManageFramePositions and causing downstream errors.
        -- Fix: defer via pendingApply flag; OnUpdate consumes it in a clean context.
        pendingApply = true
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- TAINT HAZARD: same as PLAYER_MOUNT_DISPLAY_CHANGED above.
        -- Also, PLAYER_REGEN_ENABLED fires just as combat ends — frame operations
        -- are now allowed, but the event itself can still arrive in a tainted chain.
        -- Defer via pendingApply so OnUpdate does the actual Show/Hide in clean context.
        pendingApply = true
        return
    end

    pendingApply = true
end)

initFrame:SetScript("OnUpdate", function()
    if pendingApply then
        pendingApply = false
        PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    end
end)
