local PersonalResourceDisplay = {}
EnhancedInterfacePersonalResourceDisplayModule = PersonalResourceDisplay

local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local DEFAULT_BAR_HEIGHT = 15
local COMPACT_BAR_HEIGHT = 10

local hooksInstalled = false
local subFrameHooksInstalled = false
local applyingStyles = false

local healthOverlay = nil
local healthOverlayBg = nil
local powerOverlay = nil
local powerOverlayBg = nil
local powerOverlayBorder = nil
local healthOverlayBorder = nil

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

local function IsCompactBarsEnabled()
    return EnhancedInterface.db
        and EnhancedInterface.db.personalResourceDisplay
        and EnhancedInterface.db.personalResourceDisplay.compactBars
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
    healthOverlay:SetStatusBarColor(GetHealthBarColor())
    healthOverlay:SetMinMaxValues(0, 1)
    healthOverlay:SetValue(1)
    healthOverlay:Hide()

    healthOverlayBg = healthOverlay:CreateTexture(nil, "BACKGROUND")
    healthOverlayBg:SetAllPoints(healthOverlay)
    healthOverlayBg:SetColorTexture(0, 0, 0, 0.5)

    healthOverlayBorder = CreateFrame("Frame", nil, healthOverlay)
    healthOverlayBorder:SetFrameLevel(healthOverlay:GetFrameLevel() + 2)

    do
        local function makeEdge()
            local tex = healthOverlayBorder:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(0, 0, 0, 0.5)
            return tex
        end

        local top = makeEdge()
        top:SetPoint("BOTTOMLEFT", healthOverlay, "TOPLEFT", -1, 0)
        top:SetPoint("BOTTOMRIGHT", healthOverlay, "TOPRIGHT", 1, 0)
        top:SetHeight(1)

        local bottom = makeEdge()
        bottom:SetPoint("TOPLEFT", healthOverlay, "BOTTOMLEFT", -1, 0)
        bottom:SetPoint("TOPRIGHT", healthOverlay, "BOTTOMRIGHT", 1, 0)
        bottom:SetHeight(1)

        local left = makeEdge()
        left:SetPoint("TOPLEFT", healthOverlay, "TOPLEFT", -1, 1)
        left:SetPoint("BOTTOMLEFT", healthOverlay, "BOTTOMLEFT", -1, -1)
        left:SetWidth(1)

        local right = makeEdge()
        right:SetPoint("TOPRIGHT", healthOverlay, "TOPRIGHT", 1, 1)
        right:SetPoint("BOTTOMRIGHT", healthOverlay, "BOTTOMRIGHT", 1, -1)
        right:SetWidth(1)
    end

    healthOverlayBorder:Show()

    powerOverlay = CreateFrame("StatusBar", nil, frame)
    powerOverlay:SetStatusBarTexture(BAR_TEXTURE)
    powerOverlay:SetStatusBarColor(GetPowerBarColor())
    powerOverlay:SetMinMaxValues(0, 1)
    powerOverlay:SetValue(1)
    powerOverlay:Hide()

    powerOverlayBg = powerOverlay:CreateTexture(nil, "BACKGROUND")
    powerOverlayBg:SetAllPoints(powerOverlay)
    powerOverlayBg:SetColorTexture(0, 0, 0, 0.5)

    powerOverlayBorder = CreateFrame("Frame", nil, powerOverlay)
    powerOverlayBorder:SetFrameLevel(powerOverlay:GetFrameLevel() + 2)

    local function makeEdge()
        local tex = powerOverlayBorder:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0, 0, 0, 0.5)
        return tex
    end

    local top = makeEdge()
    top:SetPoint("BOTTOMLEFT", powerOverlay, "TOPLEFT", -1, 0)
    top:SetPoint("BOTTOMRIGHT", powerOverlay, "TOPRIGHT", 1, 0)
    top:SetHeight(1)

    local bottom = makeEdge()
    bottom:SetPoint("TOPLEFT", powerOverlay, "BOTTOMLEFT", -1, 0)
    bottom:SetPoint("TOPRIGHT", powerOverlay, "BOTTOMRIGHT", 1, 0)
    bottom:SetHeight(1)

    local left = makeEdge()
    left:SetPoint("TOPLEFT", powerOverlay, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMLEFT", powerOverlay, "BOTTOMLEFT", -1, -1)
    left:SetWidth(1)

    local right = makeEdge()
    right:SetPoint("TOPRIGHT", powerOverlay, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMRIGHT", powerOverlay, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(1)

    powerOverlayBorder:Show()
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
    local isCompact = IsCompactBarsEnabled()
    local height = isCompact and COMPACT_BAR_HEIGHT or DEFAULT_BAR_HEIGHT

    EnsureOverlayBars()
    frame.HealthBarsContainer:Hide()

    if hideHealth then
        if healthOverlay then healthOverlay:Hide() end
    else
        if healthOverlay then
            healthOverlay:SetHeight(height)
            healthOverlay:ClearAllPoints()
            healthOverlay:SetPoint("BOTTOMLEFT", powerOverlay, "TOPLEFT")
            healthOverlay:SetPoint("BOTTOMRIGHT", powerOverlay, "TOPRIGHT")

            healthOverlayBorder:Show()
            healthOverlay:Show()
            UpdateHealthValues()
        end
    end
end

local function ApplyPowerStyle(frame)
    local powerBar = frame and frame.PowerBar
    if not powerBar then return end

    local isCompact = IsCompactBarsEnabled()
    local height = isCompact and COMPACT_BAR_HEIGHT or DEFAULT_BAR_HEIGHT

    EnsureOverlayBars()
    powerBar:Hide()

    if powerOverlay then
        powerOverlay:SetHeight(height)
        powerOverlay:ClearAllPoints()
        powerOverlay:SetPoint("TOPLEFT", powerBar, "TOPLEFT")
        powerOverlay:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT")

        powerOverlayBorder:Show()
        powerOverlay:Show()
        UpdatePowerValues()
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

    self:InstallSubFrameHooks()

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

    local function OnBlizzardBarEvent()
        local frame = GetFrame()
        if not frame then return end
        if frame.HealthBarsContainer then frame.HealthBarsContainer:Hide() end
        if frame.PowerBar then frame.PowerBar:Hide() end
        pendingApply = true
    end

    hooksecurefunc(PersonalResourceDisplayMixin, "OnShow", OnBlizzardBarEvent)
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupHealthBar", OnBlizzardBarEvent)
    hooksecurefunc(PersonalResourceDisplayMixin, "SetupPowerBar", OnBlizzardBarEvent)
    hooksecurefunc(PersonalResourceDisplayMixin, "UpdateShownState", OnBlizzardBarEvent)

    PersonalResourceDisplay:InstallSubFrameHooks()

    hooksInstalled = true
end

function PersonalResourceDisplay:InstallSubFrameHooks()
    if subFrameHooksInstalled then return end

    local frame = GetFrame()
    if not frame then return end

    local function OnBlizzardBarEvent()
        local f = GetFrame()
        if not f then return end
        if f.HealthBarsContainer then f.HealthBarsContainer:Hide() end
        if f.PowerBar then f.PowerBar:Hide() end
        pendingApply = true
    end

    if frame.HealthBarsContainer then
        hooksecurefunc(frame.HealthBarsContainer, "Show", OnBlizzardBarEvent)
    end

    if frame.PowerBar then
        hooksecurefunc(frame.PowerBar, "Show", OnBlizzardBarEvent)
        subFrameHooksInstalled = true
    end
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
