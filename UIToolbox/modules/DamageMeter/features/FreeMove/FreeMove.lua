-- UIToolbox
-- modules/DamageMeter/features/FreeMove/FreeMove.lua
--
-- Makes DamageMeterSessionWindow1 freely draggable outside Edit Mode.
-- Persists position to UIToolboxDB. Injects a toggle button above the window.

local FreeMove = {}
UIToolbox.FreeMove = FreeMove

local FRAME_NAME  = "DamageMeterSessionWindow1"
local BUTTON_SIZE = 27
local BUTTON_GAP  = 2

-- ── Position helpers ─────────────────────────────────────────────────────────

local function ApplyPosition(frame, pos)
    local relativeFrame = _G[pos.relativeTo] or UIParent
    frame:ClearAllPoints()
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
    }
end

-- ── Drag enable / disable ────────────────────────────────────────────────────

local firstEnable = true

function FreeMove:Enable()
    local db    = UIToolbox.db.freeMove
    local frame = _G[FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    if firstEnable then
        firstEnable = false
        if not db.savedPosition then
            db.savedPosition = CapturePosition(frame)
        end
    else
        if db.savedPosition then
            ApplyPosition(frame, db.savedPosition)
        end
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop",  function(f)
        f:StopMovingOrSizing()
        UIToolbox.db.freeMove.savedPosition = CapturePosition(f)
    end)
end

function FreeMove:Disable()
    local db    = UIToolbox.db.freeMove
    local frame = _G[FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop",  nil)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:RegisterForDrag()

    if db.savedPosition then
        ApplyPosition(frame, db.savedPosition)
    end
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
    if db.enabled then
        self:Enable()
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

    local sessionWindow = _G[FRAME_NAME]
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
