-- UIToolbox
-- shared/EditModeCompanionDialog/EditModeCompanionDialog.lua
--
-- Provides a persistent companion dialog that appears below the Blizzard
-- EditModeSystemSettingsDialog whenever any registered UIToolbox module has
-- settings to show for the currently selected Edit Mode system frame.
--
-- ── Design ────────────────────────────────────────────────────────────────────
--
--   • One persistent Frame (DIALOG strata) created lazily on first use.
--     Never destroyed.  Styled with a child Border frame that inherits
--     DialogBorderTranslucentTemplate — the exact same template used by
--     EditModeSystemSettingsDialog (DiamondMetal nine-slice border +
--     solid black translucent Bg, no BackdropTemplate needed).
--   • Modules register "providers" via UIToolbox.EditModeCompanion.Register().
--     A provider is a table:
--       {
--           filter(systemFrame) → bool   -- return true if this provider has
--                                        -- content for the selected frame
--           rows                         -- array of row descriptors (see below)
--       }
--   • Row descriptors (currently only type = "checkbox"):
--       {
--           type    = "checkbox",
--           label   = "...",
--           tooltip = "...",
--           get     = function() → bool,
--           set     = function(value),
--       }
--   • On every EditModeSystemSettingsDialog:UpdateSettings(systemFrame) call the
--     companion dialog collects all rows from matching providers, builds/reuses
--     persistent row frames, shows only the needed ones, resizes itself, and
--     re-anchors to the bottom of the Blizzard dialog.
--   • Hides when Edit Mode is closed (PLAYER_INTERACTION_MANAGER_FRAME_HIDE).
--
-- ── Taint notes ───────────────────────────────────────────────────────────────
--
--   We never touch secure frames or write to protected fields.  The companion
--   dialog is a plain non-secure frame.  hooksecurefunc on a frame instance
--   (not a global function) is safe — it runs in the addon's own execution
--   context, not tainted.

-- Padding / sizing constants — matched to EditModeSystemSettingsDialog
-- Width is NOT hardcoded: we read EditModeSystemSettingsDialog:GetWidth() at
-- runtime so our dialog always matches its actual (auto-resized) width.
local DIALOG_PADDING_H    = 20    -- widthPadding=40 split evenly → 20px each side
local DIALOG_PADDING_TOP  = 42    -- title at y=-15 (~14px tall) + 12px gap below it
local DIALOG_PADDING_BOT  = 20    -- heightPadding=40 split evenly → 20px bottom
local ROW_HEIGHT          = 32    -- fixedHeight of EditModeSettingCheckboxTemplate
local ROW_SPACING         = 2     -- spacing on the Settings VerticalLayoutFrame
local TITLE_OFFSET_Y      = -15   -- same as EditModeSystemSettingsDialog Title anchor

-- ── Module namespace ──────────────────────────────────────────────────────────

UIToolbox.EditModeCompanion = UIToolbox.EditModeCompanion or {}
local Companion = UIToolbox.EditModeCompanion

local providers = {}   -- array of provider tables registered by modules

-- ── Public API ────────────────────────────────────────────────────────────────

--- Register a content provider.
--- @param provider table  { filter(systemFrame)→bool, rows={...} }
function Companion.Register(provider)
    table.insert(providers, provider)
end

-- ── Row frame pool ────────────────────────────────────────────────────────────
-- We maintain a flat array of persistent checkbox row frames.  They are created
-- once and reused across updates — never pool-managed so they survive
-- ReleaseAllNonSliders on the Blizzard dialog (they are parented to our own
-- dialog, not to the Blizzard one).

local rowFrames = {}   -- persistent array of row frame objects

local function GetOrCreateRowFrame(index, parent)
    if rowFrames[index] then return rowFrames[index] end

    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT")   -- positioned manually in UpdateRows

    local cb = CreateFrame("CheckButton", nil, f)
    cb:SetSize(32, 32)
    cb:SetPoint("LEFT", f, "LEFT", -5, 0)   -- matches EditModeSettingCheckboxTemplate
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    f.Button = cb

    local lbl = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    lbl:SetHeight(ROW_HEIGHT)
    lbl:SetPoint("LEFT", cb, "RIGHT", 5, 0)   -- matches EditModeSettingCheckboxTemplate label offset
    lbl:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    f.Label = lbl

    cb:SetScript("OnClick", function(btn)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if f.rowDef and f.rowDef.set then
            f.rowDef.set(btn:GetChecked())
        end
    end)

    cb:SetScript("OnEnter", function(btn)
        if not f.rowDef then return end
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(f.rowDef.label, 1, 1, 1)
        if f.rowDef.tooltip then
            GameTooltip:AddLine(f.rowDef.tooltip, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    f:Hide()
    rowFrames[index] = f
    return f
end

-- ── Dialog frame ──────────────────────────────────────────────────────────────

local dialog = nil

local function GetOrCreateDialog()
    if dialog then return dialog end

    -- Plain frame — styling comes from the Border child, not BackdropTemplate.
    local d = CreateFrame("Frame", "UIToolboxEditModeCompanionDialog", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(200)   -- same level as EditModeSystemSettingsDialog
    d:Hide()

    -- Border: use the same template as EditModeSystemSettingsDialog so our
    -- panel matches the game's look exactly (DiamondMetal nine-slice + solid
    -- black translucent Bg).
    local border = CreateFrame("Frame", nil, d, "DialogBorderTranslucentTemplate")
    border:SetAllPoints(d)
    d.Border = border

    -- Title — GameFontHighlightLarge matches EditModeSystemSettingsDialog
    local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", d, "TOP", 0, TITLE_OFFSET_Y)
    title:SetText("UIToolbox")
    d.Title = title

    -- Thin divider line under the title (same texture Blizzard uses)
    local divider = d:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
    divider:SetHeight(16)
    divider:SetPoint("TOPLEFT",  d, "TOPLEFT",  DIALOG_PADDING_H,  -30)
    divider:SetPoint("TOPRIGHT", d, "TOPRIGHT", -DIALOG_PADDING_H, -30)
    d.Divider = divider

    dialog = d
    return d
end

-- ── Update logic ──────────────────────────────────────────────────────────────

local function UpdateCompanionDialog(systemFrame)
    -- Collect rows from all matching providers.
    local activeRows = {}
    for _, provider in ipairs(providers) do
        if provider.filter(systemFrame) then
            -- Support both a static `rows` array and a dynamic `getRows(systemFrame)` function.
            local rows = provider.getRows and provider.getRows(systemFrame) or provider.rows
            if rows then
                for _, rowDef in ipairs(rows) do
                    table.insert(activeRows, rowDef)
                end
            end
        end
    end

    if #activeRows == 0 then
        if dialog then dialog:Hide() end
        return
    end

    local d = GetOrCreateDialog()

    -- Match the Blizzard dialog's current width exactly (it auto-resizes per system frame).
    local blizzWidth = EditModeSystemSettingsDialog:GetWidth()
    d:SetWidth(blizzWidth)
    local rowWidth = blizzWidth - DIALOG_PADDING_H * 2

    -- Position rows inside the dialog.
    local contentTop = -(DIALOG_PADDING_TOP)  -- y offset from dialog top
    for i, rowDef in ipairs(activeRows) do
        local rf = GetOrCreateRowFrame(i, d)
        rf:SetWidth(rowWidth)
        rf.rowDef = rowDef
        rf.Label:SetText(rowDef.label)
        rf.Button:SetChecked(rowDef.get())
        rf:ClearAllPoints()
        rf:SetPoint("TOPLEFT", d, "TOPLEFT",
            DIALOG_PADDING_H,
            contentTop - (i - 1) * (ROW_HEIGHT + ROW_SPACING))
        rf:Show()
    end

    -- Hide unused row frames.
    for i = #activeRows + 1, #rowFrames do
        rowFrames[i]:Hide()
    end

    -- Resize dialog to fit rows.
    local contentHeight = #activeRows * (ROW_HEIGHT + ROW_SPACING) - ROW_SPACING
    d:SetHeight(DIALOG_PADDING_TOP + contentHeight + DIALOG_PADDING_BOT)

    -- Re-anchor below the Blizzard dialog.
    d:ClearAllPoints()
    d:SetPoint("TOP", EditModeSystemSettingsDialog, "BOTTOM", 0, -4)

    d:Show()
end

-- ── Hook registration ─────────────────────────────────────────────────────────

local function RegisterHook()
    -- Hook UpdateSizeAndAnchors (the final step of UpdateDialog) rather than
    -- UpdateSettings.  By the time UpdateSizeAndAnchors fires, self:Layout() has
    -- already run on the outer dialog, so self:GetWidth() returns the true final
    -- width we need to match.
    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateSizeAndAnchors", function(self, systemFrame)
        if systemFrame ~= self.attachedToSystem then return end
        UpdateCompanionDialog(systemFrame)
    end)

    -- Hide when Edit Mode is closed.
    hooksecurefunc(EditModeManagerFrame, "Hide", function()
        if dialog then dialog:Hide() end
    end)
end

local _initFrame = CreateFrame("Frame")
_initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", RegisterHook)
end)
