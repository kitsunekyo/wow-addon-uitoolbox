-- UIToolbox
-- modules/DamageMeter/features/Collapse/Collapse.lua
--
-- Injects a collapse button into every DamageMeter session window header.
-- Clicking it collapses the window body (scroll area) down to just the header,
-- keeping the header and our custom button bar visible. Click again to restore.

local Collapse = {}
UIToolbox.Collapse = Collapse

local BUTTON_SIZE  = 27
local BUTTON_GAP   = 2
local HEADER_HEIGHT = 32  -- DamageMeterSessionWindow header texture height

-- ── Per-window state ─────────────────────────────────────────────────────────

-- Keyed by sessionWindow, stores { collapsed, savedHeight, savedMinResize }
local windowState = {}

-- ── Collapse / expand logic ───────────────────────────────────────────────────

-- Re-anchor the session window at its current top-left position with a new
-- height, so the header never moves when collapsing or expanding.
local function ReplaceHeightKeepTop(sessionWindow, newHeight)
    local left = sessionWindow:GetLeft()
    local top  = sessionWindow:GetTop()
    sessionWindow:ClearAllPoints()
    sessionWindow:SetSize(sessionWindow:GetWidth(), newHeight)
    sessionWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left or 0, top or 0)
end

local function SetCollapsed(sessionWindow, collapsed)
    local state = windowState[sessionWindow]
    if not state then return end

    state.collapsed = collapsed

    -- Body elements to hide/show
    local scrollBox    = sessionWindow.ScrollBox
    local scrollBar    = sessionWindow.ScrollBar
    local background   = sessionWindow.Background
    local resizeButton = sessionWindow.ResizeButton

    if collapsed then
        -- Save the current full height so we can restore it later.
        state.savedHeight = sessionWindow:GetHeight()

        -- Clamp the saved height: ignore any already-collapsed heights.
        if state.savedHeight <= HEADER_HEIGHT + 4 then
            state.savedHeight = state.savedHeight > 0 and 200 or 200
        end

        -- Shrink the window to just the header, keeping the top edge fixed.
        ReplaceHeightKeepTop(sessionWindow, HEADER_HEIGHT)

        -- Disable resizing while collapsed.
        if sessionWindow.SetResizeBounds then
            sessionWindow:SetResizeBounds(0, HEADER_HEIGHT, nil, HEADER_HEIGHT)
        end

        -- Hide body elements.
        if scrollBox    then scrollBox:Hide()    end
        if scrollBar    then scrollBar:Hide()    end
        if background   then background:Hide()   end
        if resizeButton then resizeButton:Hide() end
    else
        -- Restore the window to its previous full height, keeping the top edge fixed.
        local restoreHeight = (state.savedHeight and state.savedHeight > HEADER_HEIGHT)
            and state.savedHeight or 200

        ReplaceHeightKeepTop(sessionWindow, restoreHeight)

        -- Re-enable free resizing.
        if sessionWindow.SetResizeBounds then
            sessionWindow:SetResizeBounds(0, 100, nil, nil)
        end

        -- Show body elements.
        if scrollBox    then scrollBox:Show()    end
        if scrollBar    then scrollBar:Show()    end
        if background   then background:Show()   end
        if resizeButton then resizeButton:Show() end
    end

    -- Update the button icon on this window.
    local btn = sessionWindow.UIToolboxCollapseButton
    if btn then
        btn.Icon:SetAtlas(
            collapsed and "128-RedButton-Plus" or "128-RedButton-Minus",
            true
        )
    end
end

-- ── Button injection ─────────────────────────────────────────────────────────

local function CreateHeaderButtons(sessionWindow)
    if sessionWindow.UIToolboxCollapseButton then return end  -- idempotency guard

    -- Initialize per-window state.
    windowState[sessionWindow] = {
        collapsed   = false,
        savedHeight = nil,
    }

    local btn = CreateFrame("Button", nil, sessionWindow)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    -- Chain to the right of the QuickClear button if present,
    -- then FreeMove, then fall back to a fixed offset.
    local quickClearBtn = sessionWindow.UIToolboxQuickClearButton
    local freeMoveBtn   = sessionWindow.UIToolboxFreeMoveButton
    if quickClearBtn then
        btn:SetPoint("BOTTOMLEFT", quickClearBtn, "BOTTOMRIGHT", BUTTON_GAP, 0)
    elseif freeMoveBtn then
        btn:SetPoint("BOTTOMLEFT", freeMoveBtn, "BOTTOMRIGHT", BUTTON_GAP, 0)
    else
        btn:SetPoint("BOTTOMLEFT", sessionWindow, "TOPLEFT",
            (BUTTON_SIZE + BUTTON_GAP) * 2, 4)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetAtlas("128-RedButton-Minus", true)
    btn.Icon = icon

    btn:SetScript("OnEnter", function(self)
        local state = windowState[sessionWindow]
        local collapsed = state and state.collapsed
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("UIToolbox: Collapse", 1, 1, 1)
        GameTooltip:AddLine(
            collapsed and "Click to expand the damage meter." or "Click to collapse the damage meter.",
            0.7, 0.7, 0.7
        )
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        local state = windowState[sessionWindow]
        if state then
            SetCollapsed(sessionWindow, not state.collapsed)
        end
    end)

    sessionWindow.UIToolboxCollapseButton = btn
end

-- ── Initialization ───────────────────────────────────────────────────────────

local function HookDamageMeter()
    if not DamageMeter then return end

    hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, windowData)
        local sessionWindow = windowData and windowData.sessionWindow
        if sessionWindow then
            -- Defer two ticks so FreeMove and QuickClear can inject their buttons first.
            C_Timer.After(0, function()
                C_Timer.After(0, function() CreateHeaderButtons(sessionWindow) end)
            end)
        end
    end)

    -- Inject into any windows already set up at login time.
    local windowDataList = DamageMeter:GetWindowDataList()
    if windowDataList then
        for _, windowData in ipairs(windowDataList) do
            local sessionWindow = windowData and windowData.sessionWindow
            if sessionWindow then
                C_Timer.After(0, function()
                    C_Timer.After(0, function() CreateHeaderButtons(sessionWindow) end)
                end)
            end
        end
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookDamageMeter()
    end
end)

UIToolbox:RegisterModule(Collapse)
