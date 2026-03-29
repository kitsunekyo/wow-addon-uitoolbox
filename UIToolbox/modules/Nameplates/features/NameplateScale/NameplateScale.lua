-- UIToolbox
-- modules/Nameplates/features/NameplateScale/NameplateScale.lua
--
-- Fine-grained nameplate scale control.
--
-- Blizzard's nameplateSize CVar only offers 5 discrete steps (Small/Medium/Large/
-- ExtraLarge/Huge). The gap between steps is too coarse for many players.
--
-- We apply a uniform visual scale by combining two operations:
--
--   1. UnitFrame:SetScale(factor)
--      Scales all visual content (health bar, fonts, cast bar, auras, icons…)
--      uniformly. Hooked via NamePlateUnitFrameMixin:ApplyFrameOptions so it fires
--      on every nameplate on spawn and on every option update.
--
--   2. C_NamePlate.SetNamePlateSize(width * factor, height)
--      The C++ container width does not participate in SetScale. Without this
--      correction the UnitFrame (scaled by factor) still fills the original
--      container width, so visually the nameplate appears wider when scaled down
--      and narrower when scaled up. Multiplying the container width by factor
--      keeps the visual width proportional to the scale.
--      Height is left unchanged — Blizzard's height already accounts for scaled
--      bar heights; correcting it would double-apply the scale on height.
--
-- NOTE: C_NamePlate.GetNamePlates() / GetNamePlateForUnit() are gated behind
-- AllowedWhenUntainted and return nil from addon code, so we cannot iterate
-- frames directly. ApplyFrameOptions gives us UnitFrame references; the width
-- correction is applied once per UpdateNamePlateOptions cycle via a hook on the
-- driver mixin.
--
-- The factor is stored per-character in UIToolboxDB.nameplateScale.factor.

local NameplateScale = {}
UIToolbox.NameplateScale = NameplateScale

-- ── Constants ─────────────────────────────────────────────────────────────────

local DEFAULT_FACTOR = 1.0
local BASE_WIDTH     = 230  -- matches NamePlateDriverMixin:GetNamePlateWidth baseline

-- ── State ─────────────────────────────────────────────────────────────────────

-- Weak table: every UnitFrame we have seen, so we can re-apply scale immediately
-- when the slider changes without waiting for the next ApplyFrameOptions call.
local seenFrames = setmetatable({}, { __mode = "v" })

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GetFactor()
    return UIToolbox.db.nameplateScale.factor or DEFAULT_FACTOR
end

-- Scale the UnitFrame's visual content.
local function ScaleUnitFrame(unitFrame)
    unitFrame:SetScale(GetFactor())
end

local function ScaleAllSeen()
    for _, unitFrame in pairs(seenFrames) do
        ScaleUnitFrame(unitFrame)
    end
end

-- Correct the C++ container width so the visual width stays constant.
-- Called after Blizzard's UpdateNamePlateOptions sets the canonical size.
local function CorrectContainerWidth()
    local factor = GetFactor()
    if factor == 1.0 then return end
    if not NamePlateDriverFrame then return end

    local namePlateScale = NamePlateDriverFrame:GetNamePlateScale()

    -- Mirror NamePlateDriverMixin:GetNamePlateWidth / GetNamePlateHeight
    local baseWidth  = NamePlateDriverFrame.baseNamePlateWidth
                    or (BASE_WIDTH * namePlateScale.horizontal)

    local namePlateStyle = CVarCallbackRegistry:GetCVarNumberOrDefault(NamePlateConstants.STYLE_CVAR)
    local baseHeight = NamePlateDriverFrame.baseNamePlateHeight
                    or NamePlateDriverFrame:GetNamePlateHeight(namePlateStyle, namePlateScale)

    -- Scale the container width to match the visual width from SetScale(factor).
    C_NamePlate.SetNamePlateSize(baseWidth * factor, baseHeight)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function NameplateScale:SetFactor(factor)
    UIToolbox.db.nameplateScale.factor = factor
    ScaleAllSeen()
    CorrectContainerWidth()
end

function NameplateScale:GetFactor()
    return UIToolbox.db.nameplateScale.factor or DEFAULT_FACTOR
end

-- ── Initialization ────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")

frame:SetScript("OnEvent", function(_, event)
    if event == "VARIABLES_LOADED" then
        -- Hook ApplyFrameOptions — fires on every nameplate UnitFrame on spawn
        -- and whenever Blizzard re-applies options (CVar change, etc.).
        hooksecurefunc(NamePlateUnitFrameMixin, "ApplyFrameOptions", function(self)
            seenFrames[self] = self
            ScaleUnitFrame(self)
        end)

        -- Hook UpdateNamePlateOptions — fires after Blizzard sets the container
        -- size via C_NamePlate.SetNamePlateSize. We correct the width here.
        hooksecurefunc(NamePlateDriverMixin, "UpdateNamePlateOptions", function()
            CorrectContainerWidth()
        end)

        frame:UnregisterEvent("VARIABLES_LOADED")
    end
end)
