-- EnhancedInterface
-- shared/EditModeCompanionDialog/EditModeCompanionDialog.lua
--
-- Provides a persistent companion dialog that appears below the Blizzard
-- EditModeSystemSettingsDialog whenever any registered EnhancedInterface
-- module has settings to show for the currently selected Edit Mode system
-- frame.
--
-- ── Design ────────────────────────────────────────────────────────────────────
--
--   • One persistent Frame (DIALOG strata) created EAGERLY at PLAYER_LOGIN /
--     Blizzard_EditMode-loaded time (a clean, Blizzard-driven dispatch
--     context).  Never destroyed.  Styled with a child Border frame that
--     inherits DialogBorderTranslucentTemplate — the exact same template used
--     by EditModeSystemSettingsDialog.
--   • A pool of MAX_ROWS persistent checkbox row frames is created EAGERLY
--     alongside the dialog.  Each row owns a FontString label and a
--     CheckButton.  Rows are created up-front so no CreateFrame /
--     CreateFontString call ever happens from our OnUpdate-driven update
--     path (which is tainted — see TAINT MODEL below).
--   • Modules register "providers" via EnhancedInterface.EditModeCompanion.Register().
--     A provider is:
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
--   • On every EditModeSystemSettingsDialog:UpdateSettings(systemFrame) call
--     UpdateCompanionDialog collects all rows from matching providers, does
--     property-only updates (SetText/SetChecked/SetPoint/Show/Hide) on the
--     pre-built frames, and re-anchors below the Blizzard dialog.
--   • Hides when Edit Mode is closed.
--
-- ── TAINT MODEL ───────────────────────────────────────────────────────────────
--
-- Two distinct taint hazards in this file:
--
-- (1) hooksecurefunc callbacks inherit the taint of whatever called the
--     original function.  When another addon (e.g. AccWideUILayoutSelection)
--     calls C_EditMode.SetActiveLayout(), our UpdateSizeAndAnchors hook fires
--     inside that tainted chain.  Any frame mutation performed directly inside
--     the hook would propagate taint.  FIX: only set a boolean flag inside the
--     hook; the OnUpdate poller below consumes it.
--
-- (2) Addon-registered OnUpdate handlers carry THIS addon's taint stamp on
--     the call stack.  They are NOT a clean execution context.  This means
--     anything we do inside our own OnUpdate handler is tainted.
--
--     Critically:
--       • CreateFrame / CreateFontString called from a tainted context taints
--         the new object permanently.
--       • SetText / SetFont / SetFontObject on a tainted FontString (or any
--         FontString in a tainted call) writes into the GLOBAL FONT METRICS
--         CACHE — shared with every Blizzard FontString, including the
--         widgets inside Area POI tooltips.  Once the cache is tainted, any
--         later GetStringHeight() / GetStringWidth() / GetLeft() / GetBottom()
--         on any FontString returns a "secret number" and Blizzard's widget
--         arithmetic crashes with errors like:
--           - UIWidgetTemplateTextWithState:Setup -> textHeight (secret)
--           - UIWidgetTemplateBase:Setup        -> arithmetic on secret
--           - FrameUtil.GetUnscaledFrameRect    -> frameLeft (secret)
--           - SharedTooltipTemplates            -> arithmetic on secret
--           - ADDON_ACTION_BLOCKED PerformEmote (WorldMap show path)
--
--     FIX: Build all frames and FontStrings EAGERLY in EventUtil.ContinueOnAddOnLoaded
--     ("Blizzard_EditMode", BuildDialog) — a Blizzard-driven dispatch from a
--     clean context.  The OnUpdate-driven UpdateCompanionDialog must NEVER
--     create frames or FontStrings; it only updates properties on the pre-built
--     pool.  Property updates (SetText/SetChecked/SetPoint/Show/Hide) on
--     already-clean FontStrings do NOT taint the metrics cache because no
--     metrics measurement happens — Blizzard reuses the cached entry from the
--     clean creation context.

-- Padding / sizing constants — matched to EditModeSystemSettingsDialog
local DIALOG_PADDING_H     = 20    -- widthPadding=40 split evenly → 20px each side
local DIALOG_PADDING_TOP   = 42    -- title at y=-15 (~14px tall) + 12px gap below it
local DIALOG_PADDING_BOT   = 20    -- heightPadding=40 split evenly → 20px bottom
local ROW_HEIGHT           = 32    -- fixedHeight of EditModeSettingCheckboxTemplate
local ROW_SPACING          = 2     -- spacing on the Settings VerticalLayoutFrame
local TITLE_OFFSET_Y       = -15   -- same as EditModeSystemSettingsDialog Title anchor
local DEFAULT_DIALOG_WIDTH = 350   -- fallback used until OnSizeChanged fires once
local MAX_ROWS             = 16    -- pre-built row pool size (plenty of head-room)

-- ── Module namespace ──────────────────────────────────────────────────────────

EnhancedInterface.EditModeCompanion = EnhancedInterface.EditModeCompanion or {}
local Companion = EnhancedInterface.EditModeCompanion

local providers = {}   -- array of provider tables registered by modules

-- ── Public API ────────────────────────────────────────────────────────────────

--- Register a content provider.
--- @param provider table  { filter(systemFrame)→bool, rows={...} }
function Companion.Register(provider)
    table.insert(providers, provider)
end

-- ── State ─────────────────────────────────────────────────────────────────────

local dialog                 = nil   -- the persistent Frame (built eagerly)
local rowFrames              = {}    -- pool of MAX_ROWS row frames
local pendingSystemFrame     = nil   -- flag set by hook, consumed by OnUpdate
local cachedBlizzDialogWidth = nil   -- captured by OnSizeChanged (untainted)

-- ── Eager construction (clean Blizzard-driven context) ───────────────────────
-- Called exactly once from EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode")
-- which the C++ engine dispatches in a clean context (no addon taint on the
-- stack).  This is the ONLY place CreateFrame / CreateFontString is called
-- in this file.

local function BuildRowFrame(index, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT")   -- positioned per-update in UpdateCompanionDialog

    local cb = CreateFrame("CheckButton", nil, f)
    cb:SetSize(32, 32)
    cb:SetPoint("LEFT", f, "LEFT", -5, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    f.Button = cb

    local lbl = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    lbl:SetHeight(ROW_HEIGHT)
    lbl:SetPoint("LEFT", cb, "RIGHT", 5, 0)
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
    return f
end

local function BuildDialog()
    if dialog then return end

    -- Plain frame — styling comes from the Border child, not BackdropTemplate.
    local d = CreateFrame("Frame", "EnhancedInterfaceEditModeCompanionDialog", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(200)   -- same level as EditModeSystemSettingsDialog
    d:SetWidth(DEFAULT_DIALOG_WIDTH)
    d:SetHeight(DIALOG_PADDING_TOP + DIALOG_PADDING_BOT)
    d:Hide()

    -- Border: same template as EditModeSystemSettingsDialog so the panel
    -- matches the game's look exactly (DiamondMetal nine-slice + solid
    -- black translucent Bg).
    local border = CreateFrame("Frame", nil, d, "DialogBorderTranslucentTemplate")
    border:SetAllPoints(d)
    d.Border = border

    -- Title — GameFontHighlightLarge matches EditModeSystemSettingsDialog
    local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", d, "TOP", 0, TITLE_OFFSET_Y)
    title:SetText("EnhancedInterface")
    d.Title = title

    -- Thin divider line under the title (same texture Blizzard uses)
    local divider = d:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
    divider:SetHeight(16)
    divider:SetPoint("TOPLEFT",  d, "TOPLEFT",  DIALOG_PADDING_H,  -30)
    divider:SetPoint("TOPRIGHT", d, "TOPRIGHT", -DIALOG_PADDING_H, -30)
    d.Divider = divider

    dialog = d

    -- Pre-build the entire row pool eagerly so nothing is created lazily
    -- from the tainted OnUpdate path.
    for i = 1, MAX_ROWS do
        rowFrames[i] = BuildRowFrame(i, d)
    end
end

-- ── Update logic (runs from tainted OnUpdate context) ────────────────────────
-- This function MUST NOT call CreateFrame, CreateFontString, SetFont, or
-- SetFontObject.  Property updates only.

local function UpdateCompanionDialog(systemFrame)
    if not dialog then return end   -- BuildDialog hasn't run yet

    -- Collect rows from all matching providers.
    local activeRows = {}
    for _, provider in ipairs(providers) do
        if provider.filter(systemFrame) then
            local rows = provider.getRows and provider.getRows(systemFrame) or provider.rows
            if rows then
                for _, rowDef in ipairs(rows) do
                    table.insert(activeRows, rowDef)
                end
            end
        end
    end

    if #activeRows == 0 then
        dialog:Hide()
        return
    end

    -- Width: use captured value from OnSizeChanged hook (untainted engine
    -- argument) or the default fallback.
    local blizzWidth = cachedBlizzDialogWidth or DEFAULT_DIALOG_WIDTH
    dialog:SetWidth(blizzWidth)
    local rowWidth = blizzWidth - DIALOG_PADDING_H * 2

    -- Position rows.  Cap at MAX_ROWS so we never index beyond the pool.
    local activeCount = math.min(#activeRows, MAX_ROWS)
    local contentTop  = -(DIALOG_PADDING_TOP)
    for i = 1, activeCount do
        local rowDef = activeRows[i]
        local rf = rowFrames[i]
        rf:SetWidth(rowWidth)
        rf.rowDef = rowDef
        rf.Label:SetText(rowDef.label)
        rf.Button:SetChecked(rowDef.get())
        rf:ClearAllPoints()
        rf:SetPoint("TOPLEFT", dialog, "TOPLEFT",
            DIALOG_PADDING_H,
            contentTop - (i - 1) * (ROW_HEIGHT + ROW_SPACING))
        rf:Show()
    end

    -- Hide unused rows in the pool.
    for i = activeCount + 1, MAX_ROWS do
        rowFrames[i]:Hide()
    end

    -- Resize dialog to fit the visible rows.
    local contentHeight = activeCount * (ROW_HEIGHT + ROW_SPACING) - ROW_SPACING
    dialog:SetHeight(DIALOG_PADDING_TOP + contentHeight + DIALOG_PADDING_BOT)

    -- Re-anchor below the Blizzard dialog.
    dialog:ClearAllPoints()
    dialog:SetPoint("TOP", EditModeSystemSettingsDialog, "BOTTOM", 0, -4)

    dialog:Show()
end

-- ── Hook registration ─────────────────────────────────────────────────────────

local function RegisterHook()
    -- Build the entire dialog (and its row pool) right now.  This callback
    -- is dispatched by the C++ engine through EventUtil.ContinueOnAddOnLoaded
    -- in a clean context, so all CreateFrame / CreateFontString calls inside
    -- BuildDialog are untainted.  This is the ONLY place we ever create the
    -- frames in this file.
    BuildDialog()

    -- Capture the Blizzard dialog's width via its OnSizeChanged script.  The
    -- C++ engine passes the new width and height as arguments — these are
    -- untainted regardless of what caller's chain triggered the resize.
    -- Replaces a former GetWidth() call from the OnUpdate poller, which would
    -- have returned a tainted "secret number".
    EditModeSystemSettingsDialog:HookScript("OnSizeChanged", function(_, w, _h)
        if w and w > 0 then
            cachedBlizzDialogWidth = w
        end
    end)

    -- Hook UpdateSizeAndAnchors (the final step of UpdateDialog).  By the
    -- time it fires, Layout() has already run on the outer dialog, so the
    -- OnSizeChanged hook above will have updated cachedBlizzDialogWidth to
    -- the final width before our OnUpdate poller consumes pendingSystemFrame.
    --
    -- TAINT HAZARD: This hook fires inside the call chain of any addon that
    -- calls C_EditMode.SetActiveLayout() (e.g. AccWideUILayoutSelection).
    -- That chain is tainted, so we must NOT call any frame-mutating API here.
    -- Only set a flag; the OnUpdate poller below consumes it.
    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateSizeAndAnchors", function(self, systemFrame)
        if systemFrame ~= self.attachedToSystem then return end
        pendingSystemFrame = systemFrame
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

-- OnUpdate poller: consume pendingSystemFrame set by the hooksecurefunc hook.
-- This handler runs in a tainted context (addon-registered OnUpdate carries
-- our addon's taint stamp on the call stack), but UpdateCompanionDialog only
-- does property updates on already-built frames — no CreateFrame, no
-- CreateFontString, no SetFont — so no taint can propagate into the global
-- font-metrics cache.
_initFrame:SetScript("OnUpdate", function()
    if pendingSystemFrame then
        local sf = pendingSystemFrame
        pendingSystemFrame = nil
        UpdateCompanionDialog(sf)
    end
end)
