-- UIToolbox
-- modules/ActionBars/features/EditModeIntegration/EditModeIntegration.lua
--
-- Injects a "Shared Bar" checkbox into the EditModeSystemSettingsDialog for
-- each action bar that supports the SharedBars feature.
--
-- ── How the injection works ────────────────────────────────────────────────────
--
-- When the player clicks an action bar in Edit Mode, Blizzard calls
-- EditModeSystemSettingsDialog:UpdateSettings(systemFrame).  That function:
--   1. Calls ReleaseAllNonSliders() — releases every pool-acquired checkbox/dropdown
--   2. Re-acquires fresh pool frames for each registered setting
--   3. Calls self.Settings:Layout() to reflow the VerticalLayoutFrame
--   4. Returns — then UpdateSizeAndAnchors calls self:Layout() on the outer dialog
--
-- Pool-acquired frames are destroyed on every update, so we cannot use the pool.
-- Instead we create one persistent Frame parented to self.Settings (the dialog's
-- VerticalLayoutFrame).  It survives ReleaseAll because it is not pool-managed.
--
-- We hook UpdateSettings with hooksecurefunc on the frame instance directly
-- (hooking the mixin table does not work — WoW dispatches via the frame).
-- The hook runs after Blizzard's settings are laid out, but crucially BEFORE
-- UpdateSizeAndAnchors calls self:Layout() on the outer dialog:
--   UpdateSettings → [hook] → UpdateButtons → UpdateExtraButtons → UpdateSizeAndAnchors
--
-- In the hook we:
--   • Show/hide/reconfigure the checkbox for the currently selected bar
--   • Call self.Settings:Layout() so the VerticalLayoutFrame includes our frame
--   • The outer dialog's Layout() in UpdateSizeAndAnchors then expands to fit
--
-- ── Bar index mapping ──────────────────────────────────────────────────────────
--
-- Enum.EditModeActionBarSystemIndices (values 1–8 map 1:1 to SharedBars barIndex):
--   MainBar   = 1  →  SharedBars barIndex 1  (Action Bar 1)
--   Bar2      = 2  →  barIndex 2
--   Bar3      = 3  →  barIndex 3
--   RightBar1 = 4  →  barIndex 4
--   RightBar2 = 5  →  barIndex 5
--   ExtraBar1 = 6  →  barIndex 6
--   ExtraBar2 = 7  →  barIndex 7
--   ExtraBar3 = 8  →  barIndex 8
--
-- StanceBar (11), PetActionBar (12), PossessActionBar (13) are NOT supported.
--
-- Note: Enum.EditModeSystem.ActionBar == 0 (not 1).

-- Maps Enum.EditModeActionBarSystemIndices → SharedBars barIndex.
local SYSTEM_INDEX_TO_BAR_INDEX = {
    [1] = 1,  -- MainBar
    [2] = 2,  -- Bar2
    [3] = 3,  -- Bar3
    [4] = 4,  -- RightBar1 (MultiBarRight)
    [5] = 5,  -- RightBar2 (MultiBarLeft)
    [6] = 6,  -- ExtraBar1 (MultiBar5)
    [7] = 7,  -- ExtraBar2 (MultiBar6)
    [8] = 8,  -- ExtraBar3 (MultiBar7)
}

-- layoutIndex for our frame — must exceed the highest Blizzard action bar
-- setting index.  Action bars have 9 settings (indices 1–9), so 100 is safe.
local INJECT_LAYOUT_INDEX = 100

-- The one persistent checkbox frame (created lazily the first time the hook runs).
local injectedCheckbox = nil

-- ── Checkbox frame creation ────────────────────────────────────────────────────

-- Creates a frame that mimics EditModeSettingCheckboxTemplate in appearance and
-- behaviour, but is NOT managed by the pool, so it persists across UpdateSettings
-- calls.
--
-- parent: the dialog's self.Settings VerticalLayoutFrame.
local function CreateInjectedCheckbox(parent)
    -- Outer frame — must have an explicit size so VerticalLayoutMixin can
    -- measure it via child:GetSize().  Width matches the dialog content width
    -- (~260 px; dialog is 300 px wide with 40 px total widthPadding).
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(260, 32)
    f:SetPoint("TOPLEFT")

    -- CheckButton — same textures as EditModeSettingCheckboxTemplate.
    local cb = CreateFrame("CheckButton", nil, f)
    cb:SetSize(32, 32)
    cb:SetPoint("LEFT", f, "LEFT", -5, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    f.Button = cb

    -- Label — same font as EditModeSettingCheckboxTemplate.
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    label:SetSize(220, 32)
    label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    label:SetJustifyH("LEFT")
    label:SetText("Shared Bar")
    f.Label = label

    -- Click handler: directly toggle SharedBars (no C_EditMode involvement).
    cb:SetScript("OnClick", function(btn)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local barIndex = f.barIndex
        if not barIndex then return end
        if btn:GetChecked() then
            UIToolbox.SharedBars:EnableBar(barIndex)
        else
            UIToolbox.SharedBars:DisableBar(barIndex)
        end
    end)

    -- Tooltip on hover.
    cb:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Shared Bar", 1, 1, 1)
        GameTooltip:AddLine(
            "Keeps this bar's buttons the same across all talent loadouts. " ..
            "Enabling takes a snapshot of the current layout.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    f:Hide()
    return f
end

-- ── Hook registration ─────────────────────────────────────────────────────────

-- Blizzard_EditMode is demand-loaded (only when the player opens Edit Mode for
-- the first time).  EventUtil.ContinueOnAddOnLoaded handles both cases:
--   • addon not yet loaded → fires when ADDON_LOADED fires for it
--   • addon already loaded  → fires immediately on the next frame
local function RegisterHook()
    -- Hook the frame instance directly (confirmed working).
    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateSettings", function(self, systemFrame)
        -- Guard: only run when Blizzard would (attached system matches).
        if systemFrame ~= self.attachedToSystem then return end

        -- Guard: only action bars (Enum.EditModeSystem.ActionBar == 0).
        if systemFrame.system ~= Enum.EditModeSystem.ActionBar then
            if injectedCheckbox then injectedCheckbox:Hide() end
            return
        end

        local barIndex = SYSTEM_INDEX_TO_BAR_INDEX[systemFrame.systemIndex]
        if not barIndex then
            -- StanceBar / PetActionBar / PossessActionBar — not supported.
            if injectedCheckbox then injectedCheckbox:Hide() end
            return
        end

        -- Create on first use, parented to the dialog's Settings layout frame.
        if not injectedCheckbox then
            injectedCheckbox = CreateInjectedCheckbox(self.Settings)
        end

        -- Configure for the currently selected bar.
        injectedCheckbox.barIndex    = barIndex
        injectedCheckbox.layoutIndex = INJECT_LAYOUT_INDEX

        local db = UIToolbox.db.sharedBars.bars[barIndex]
        injectedCheckbox.Button:SetChecked(db ~= nil and db.enabled == true)
        injectedCheckbox:Show()

        -- Re-run the VerticalLayoutFrame pass so our frame is included.
        -- UpdateSizeAndAnchors (called after us in UpdateDialog) will then
        -- resize the outer dialog to fit.
        self.Settings:Layout()
    end)
end

local _initFrame = CreateFrame("Frame")
_initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", RegisterHook)
end)
