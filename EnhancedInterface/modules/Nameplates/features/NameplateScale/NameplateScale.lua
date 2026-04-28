local NameplateScale = {}
EnhancedInterface.NameplateScale = NameplateScale

local DEFAULT_FACTOR = 1.0
local BASE_WIDTH     = 230

local seenFrames = setmetatable({}, { __mode = "k" })

local function GetFactor()
    local factor = tonumber(EnhancedInterface.db.nameplateScale.factor)
    if not factor or factor <= 0 then
        return DEFAULT_FACTOR
    end

    return factor
end

-- Scale the UnitFrame's visual content.
local function ScaleUnitFrame(unitFrame)
    if not unitFrame then return end

    -- Guard invalid objects to avoid bad self errors from spoofed tables.
    local ok, isFrame = pcall(function() return unitFrame:IsObjectType("Frame") end)
    if not ok or not isFrame then return end

    local forbidOk, forbidden = pcall(function() return unitFrame:IsForbidden() end)
    if forbidOk and forbidden then return end

    unitFrame:SetScale(GetFactor())
end

local function ScaleAllSeen()
    for unitFrame in pairs(seenFrames) do
        ScaleUnitFrame(unitFrame)
    end
end

local function CorrectContainerWidth()
    local factor = GetFactor()
    if factor == 1.0 then return end
    if not NamePlateDriverFrame then return end

    local namePlateScale = NamePlateDriverFrame:GetNamePlateScale()

    local baseWidth  = NamePlateDriverFrame.baseNamePlateWidth
                    or (BASE_WIDTH * namePlateScale.horizontal)

    local namePlateStyle = CVarCallbackRegistry:GetCVarNumberOrDefault(NamePlateConstants.STYLE_CVAR)
    local baseHeight = NamePlateDriverFrame.baseNamePlateHeight
                    or NamePlateDriverFrame:GetNamePlateHeight(namePlateStyle, namePlateScale)

    C_NamePlate.SetNamePlateSize(baseWidth * factor, baseHeight)
end

function NameplateScale:SetFactor(factor)
    local normalized = tonumber(factor)
    if not normalized or normalized <= 0 then
        normalized = DEFAULT_FACTOR
    end

    EnhancedInterface.db.nameplateScale.factor = normalized
    ScaleAllSeen()
    CorrectContainerWidth()
end

function NameplateScale:GetFactor()
    return EnhancedInterface.db.nameplateScale.factor or DEFAULT_FACTOR
end

-- TAINT HAZARD: hooksecurefunc callbacks on NamePlateUnitFrameMixin:ApplyFrameOptions
-- and NamePlateDriverMixin:UpdateNamePlateOptions fire inside Blizzard's nameplate
-- layout pipeline, but that pipeline can be triggered by tainted addon code (e.g.
-- another addon changing a CVar, calling ApplyFrameOptions, or triggering
-- UpdateNamePlateOptions). Calling SetScale() or C_NamePlate.SetNamePlateSize()
-- directly from these hooks runs in a potentially tainted context, tainting the
-- frame's scale property or nameplate dimensions — which Blizzard's secure layout
-- system reads later, producing downstream "secret number value" errors.
-- Fix: set boolean flags only inside the hooks; the OnUpdate poller fires from the
-- C++ game loop's own call origin, providing a clean execution context for the
local pendingScaleFrame = nil
local pendingScaleAll   = false
local pendingWidth      = false

local pollerFrame = CreateFrame("Frame")
pollerFrame:SetScript("OnUpdate", function()
    if pendingScaleFrame then
        local f = pendingScaleFrame
        pendingScaleFrame = nil
        ScaleUnitFrame(f)
    end
    if pendingScaleAll then
        pendingScaleAll = false
        ScaleAllSeen()
    end
    if pendingWidth then
        pendingWidth = false
        CorrectContainerWidth()
    end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")

frame:SetScript("OnEvent", function(_, event)
    if event == "VARIABLES_LOADED" then
        hooksecurefunc(NamePlateUnitFrameMixin, "ApplyFrameOptions", function(self)
            seenFrames[self] = true
            pendingScaleFrame = self
        end)

        hooksecurefunc(NamePlateDriverMixin, "UpdateNamePlateOptions", function()
            pendingWidth = true
        end)

        frame:UnregisterEvent("VARIABLES_LOADED")
    end
end)
