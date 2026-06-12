local PersonalResourceDisplay = {}
EnhancedInterfacePersonalResourceDisplayModule = PersonalResourceDisplay

local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local BAR_HEIGHT = 10

local hooksInstalled = false
local applyingStyles = false

local healthOverlay = nil
local powerOverlay = nil
local powerOverlayBorder = nil

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

local function GetHealthBarColor()
    local _, englishClass = UnitClass("player")
    local color = C_ClassColor and C_ClassColor.GetClassColor(englishClass)
    if color then return color:GetRGB() end
    local classColor = RAID_CLASS_COLORS[englishClass]
    if classColor then return classColor.r, classColor.g, classColor.b end
    return 0, 1, 0
end

local function GetPowerBarColor()
    local powerType = UnitPowerType("player")
    local color = PowerBarColor[powerType]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function EnsureOverlayBars()
    if healthOverlay then return end

    local frame = GetFrame()
    if not frame then return end

    healthOverlay = CreateFrame("StatusBar", nil, frame)
    healthOverlay:SetStatusBarTexture(BAR_TEXTURE)
    healthOverlay:SetHeight(BAR_HEIGHT)
    healthOverlay:SetStatusBarColor(GetHealthBarColor())
    healthOverlay:SetMinMaxValues(0, 1)
    healthOverlay:SetValue(1)
    healthOverlay:Hide()

    powerOverlay = CreateFrame("StatusBar", nil, frame)
    powerOverlay:SetStatusBarTexture(BAR_TEXTURE)
    powerOverlay:SetHeight(BAR_HEIGHT)
    powerOverlay:SetStatusBarColor(GetPowerBarColor())
    powerOverlay:SetMinMaxValues(0, 1)
    powerOverlay:SetValue(1)
    powerOverlay:Hide()

    powerOverlayBorder = powerOverlay:CreateTexture(nil, "BACKGROUND", nil, -8)
    powerOverlayBorder:SetColorTexture(0, 0, 0, 0.5)
    powerOverlayBorder:SetPoint("BOTTOMLEFT", powerOverlay, "TOPLEFT")
    powerOverlayBorder:SetPoint("BOTTOMRIGHT", powerOverlay, "TOPRIGHT")
    powerOverlayBorder:SetHeight(1)
    powerOverlayBorder:Hide()
end

local function UpdateHealthValues()
    if not healthOverlay or not healthOverlay:IsShown() then return end
    local maxHealth = UnitHealthMax("player")
    if maxHealth > 0 then
        healthOverlay:SetMinMaxValues(0, maxHealth)
        healthOverlay:SetValue(UnitHealth("player"))
    end
end

local function UpdatePowerValues()
    if not powerOverlay or not powerOverlay:IsShown() then return end
    local powerType = UnitPowerType("player")
    local maxPower = UnitPowerMax("player", powerType)
    if maxPower > 0 then
        powerOverlay:SetMinMaxValues(0, maxPower)
        powerOverlay:SetValue(UnitPower("player", powerType))
    end
end

local function UpdatePowerBarColor()
    if not powerOverlay then return end
    powerOverlay:SetStatusBarColor(GetPowerBarColor())
end

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

local function ApplyHealthStyle(frame)
    if not frame or not frame.HealthBarsContainer then return end

    local hideHealth = IsHideHealthBarEnabled()
    local restyle = IsRestyleBarsEnabled()

    EnsureOverlayBars()

    if hideHealth then
        frame.HealthBarsContainer:Hide()
        if healthOverlay then healthOverlay:Hide() end
    elseif restyle then
        frame.HealthBarsContainer:Hide()
        if healthOverlay then
            healthOverlay:ClearAllPoints()
            healthOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT")
            healthOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
            healthOverlay:Show()
            UpdateHealthValues()
        end
    else
        frame.HealthBarsContainer:Show()
        if healthOverlay then healthOverlay:Hide() end
    end
end

local function ApplyPowerStyle(frame)
    local powerBar = frame and frame.PowerBar
    if not powerBar then return end

    local restyle = IsRestyleBarsEnabled()
    local hideHealth = IsHideHealthBarEnabled()

    EnsureOverlayBars()

    if restyle then
        powerBar:Hide()
        if powerOverlay then
            powerOverlay:ClearAllPoints()
            if hideHealth then
                powerOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT")
                powerOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
            else
                powerOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -BAR_HEIGHT)
                powerOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -BAR_HEIGHT)
            end

            if hideHealth then
                powerOverlayBorder:Show()
            else
                powerOverlayBorder:Hide()
            end

            powerOverlay:Show()
            UpdatePowerValues()
        end
    else
        powerBar:Show()
        if powerOverlay then
            powerOverlay:Hide()
            powerOverlayBorder:Hide()
        end
    end
end

function PersonalResourceDisplay:ApplyMountVisibility()
    local frame = GetFrame()
    if not frame then return end

    if InCombatLockdown() then return end

    if not C_GameRules.IsPersonalResourceDisplayEnabled() then return end

    if IsHideWhenMountedEnabled() and IsMounted() then
        frame:Hide()
    else
        if not frame:IsShown() then
            frame:Show()
        end
    end
end

function PersonalResourceDisplay:ApplyToCurrentPlayerNameplate()
    if applyingStyles then return end

    local frame = GetFrame()
    if not frame then return end

    applyingStyles = true
    ApplyHealthStyle(frame)
    ApplyPowerStyle(frame)
    ApplyClassResourceFrameStyle()
    self:ApplyMountVisibility()
    applyingStyles = false
end

function PersonalResourceDisplay:TryInstallHooks()
    if hooksInstalled then return end

    if not PersonalResourceDisplayMixin then return end

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
        pendingApply = true
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
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

local valueWatcher = CreateFrame("Frame")
valueWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
valueWatcher:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
valueWatcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
valueWatcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
valueWatcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
valueWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        UpdateHealthValues()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        UpdatePowerValues()
    elseif event == "UNIT_DISPLAYPOWER" then
        UpdatePowerBarColor()
        UpdatePowerValues()
    end
end)
