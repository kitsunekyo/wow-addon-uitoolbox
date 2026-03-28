-- UIToolbox
-- modules/DamageMeter/features/QuickClear/QuickClear.lua
--
-- Injects a Quick Clear button into every DamageMeter session window header.
-- Clicking it calls C_DamageMeter.ResetAllCombatSessions() to wipe all data.

local QuickClear = {}
UIToolbox.QuickClear = QuickClear

local BUTTON_SIZE = 27
local BUTTON_GAP  = 2

-- ── Button injection ─────────────────────────────────────────────────────────

local function CreateHeaderButtons(sessionWindow)
    if sessionWindow.UIToolboxQuickClearButton then return end  -- idempotency guard

    local btn = CreateFrame("Button", nil, sessionWindow)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    -- Anchor to the right of the FreeMove button if present, otherwise fall back
    -- to a fixed offset from the window's top-left corner.
    local freeMoveBtn = sessionWindow.UIToolboxFreeMoveButton
    if freeMoveBtn then
        btn:SetPoint("BOTTOMLEFT", freeMoveBtn, "BOTTOMRIGHT", BUTTON_GAP, 0)
    else
        btn:SetPoint("BOTTOMLEFT", sessionWindow, "TOPLEFT", BUTTON_SIZE + BUTTON_GAP, 4)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetAtlas("128-RedButton-Delete", true)
    btn.Icon = icon

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("UIToolbox: Quick Clear", 1, 1, 1)
        GameTooltip:AddLine("Reset all damage meter data.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        C_DamageMeter.ResetAllCombatSessions()
    end)

    sessionWindow.UIToolboxQuickClearButton = btn
end

-- ── Initialization ───────────────────────────────────────────────────────────

local function HookDamageMeter()
    if not DamageMeter then return end

    hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, windowData)
        local sessionWindow = windowData and windowData.sessionWindow
        if sessionWindow then
            -- Defer one tick so FreeMove (loaded before us) can inject its button first.
            C_Timer.After(0, function() CreateHeaderButtons(sessionWindow) end)
        end
    end)

    -- Inject into any windows already set up at login time.
    local windowDataList = DamageMeter:GetWindowDataList()
    if windowDataList then
        for _, windowData in ipairs(windowDataList) do
            local sessionWindow = windowData and windowData.sessionWindow
            if sessionWindow then
                C_Timer.After(0, function() CreateHeaderButtons(sessionWindow) end)
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

UIToolbox:RegisterModule(QuickClear)
