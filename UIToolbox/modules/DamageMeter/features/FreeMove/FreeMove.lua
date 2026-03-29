-- UIToolbox
-- modules/DamageMeter/features/FreeMove/FreeMove.lua
--
-- Makes DamageMeterSessionWindow1 freely draggable outside Edit Mode.
-- Persists position to UIToolboxDB. Injects a toggle button above the window.
--
-- Technical note: DamageMeter (the Edit Mode system frame) is a protected Blizzard
-- frame and cannot be moved by addon code. We instead move DamageMeterSessionWindow1
-- by detaching it from its parent DamageMeter frame (TOPLEFT+BOTTOMRIGHT anchors,
-- which also control size) and giving it an explicit size + single TOPLEFT anchor.
-- On disable we pin it in place the same way so there is no visible jump.

local FreeMove = {}
UIToolbox.FreeMove = FreeMove

local SESSION_FRAME_NAME = "DamageMeterSessionWindow1"
local BUTTON_SIZE = 27
local BUTTON_GAP  = 2

-- ── Position helpers ─────────────────────────────────────────────────────────

local function ApplyPosition(frame, pos)
    local relativeFrame = _G[pos.relativeTo] or UIParent
    frame:ClearAllPoints()
    if pos.width and pos.height then
        frame:SetSize(pos.width, pos.height)
    end
    frame:SetPoint(pos.point, relativeFrame, pos.relativePoint, pos.offsetX, pos.offsetY)
end

local function CapturePosition(frame)
    local point, relativeTo, relativePoint, offsetX, offsetY = frame:GetPoint(1)
    if not point then return nil end
    return {
        point         = point,
        relativeTo    = relativeTo and relativeTo:GetName() or "UIParent",
        relativePoint = relativePoint,
        offsetX       = offsetX,
        offsetY       = offsetY,
        width         = frame:GetWidth(),
        height        = frame:GetHeight(),
    }
end

local function IsValidSavedPosition(pos)
    if not pos then return false end
    if not pos.point or not pos.relativePoint then return false end
    -- Reject positions relative to the Edit Mode parent — those are stale
    if pos.relativeTo == "DamageMeter" then return false end
    return true
end

-- ── Drag enable / disable ────────────────────────────────────────────────────

-- Detach SessionWindow1 from DamageMeter and pin it at its current screen
-- position and size. Must be called while the frame still has valid anchors.
local function PinToScreen(frame)
    local left   = frame:GetLeft()
    local top    = frame:GetTop()
    local width  = frame:GetWidth()
    local height = frame:GetHeight()
    frame:ClearAllPoints()
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left or 0, top or 0)
end

function FreeMove:Enable(restoreSavedPosition)
    local db    = UIToolbox.db.freeMove
    local frame = _G[SESSION_FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    if restoreSavedPosition and db.hasCustomPosition and IsValidSavedPosition(db.savedPosition) then
        ApplyPosition(frame, db.savedPosition)
    else
        PinToScreen(frame)
    end

    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UIToolbox.db.freeMove.savedPosition = CapturePosition(self)
        UIToolbox.db.freeMove.hasCustomPosition = true
    end)
end

function FreeMove:Disable()
    local frame = _G[SESSION_FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop",  nil)
    frame:SetMovable(false)
    frame:RegisterForDrag()

    -- Leave the frame where it is visually — just pin it to UIParent at its
    -- current screen position so it doesn't snap back to DamageMeter's anchor.
    PinToScreen(frame)
end

-- ── Button injection ─────────────────────────────────────────────────────────

local function UpdateButtonIcon(btn)
    local enabled = UIToolbox.db.freeMove.enabled
    btn.Icon:SetAtlas(enabled and "128-RedButton-VisibilityOn" or "128-RedButton-VisibilityOff", true)
end

local function CreateHeaderButtons(sessionWindow)
    if sessionWindow.UIToolboxFreeMoveButton then return end  -- idempotency guard

    local btn = CreateFrame("Button", "UIToolbox_FreeMoveButton", sessionWindow)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetPoint("BOTTOMLEFT", sessionWindow, "TOPLEFT", 0, 4)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    btn.Icon = icon
    UpdateButtonIcon(btn)

    btn:SetScript("OnEnter", function(self)
        local enabled = UIToolbox.db.freeMove.enabled
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("UIToolbox: Free Move", 1, 1, 1)
        GameTooltip:AddLine(enabled and "Click to disable" or "Click to enable", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        local db = UIToolbox.db.freeMove
        db.enabled = not db.enabled
        if db.enabled then
            FreeMove:Enable()
        else
            FreeMove:Disable()
        end
        UpdateButtonIcon(self)
    end)

    sessionWindow.UIToolboxFreeMoveButton = btn
end

-- ── Initialization ───────────────────────────────────────────────────────────

local initialized = false

function FreeMove:OnZoneChanged()
    if initialized then return end
    initialized = true

    local db = UIToolbox.db.freeMove
    if db.savedPosition and not IsValidSavedPosition(db.savedPosition) then
        db.savedPosition = nil
        db.hasCustomPosition = false
    end

    if db.hasCustomPosition == nil then
        db.hasCustomPosition = db.savedPosition ~= nil
    end

    if db.enabled then
        self:Enable(true)  -- restore saved position on login
    end
end

local function HookDamageMeter()
    if not DamageMeter then return end

    hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, windowData)
        local sessionWindow = windowData and windowData.sessionWindow
        if sessionWindow then
            CreateHeaderButtons(sessionWindow)
        end
    end)

    local sessionWindow = _G[SESSION_FRAME_NAME]
    if sessionWindow then
        CreateHeaderButtons(sessionWindow)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookDamageMeter()
    end
end)

UIToolbox:RegisterModule(FreeMove)
