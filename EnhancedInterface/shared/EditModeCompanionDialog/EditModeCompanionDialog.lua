-- Build frames/fontstrings once in Blizzard-driven init. Do not create them from
-- the addon OnUpdate path to avoid tainting UI font/cache state.

local DIALOG_PADDING_H     = 20
local DIALOG_PADDING_TOP   = 42
local DIALOG_PADDING_BOT   = 20
local ROW_HEIGHT           = 32
local ROW_SPACING          = 2
local TITLE_OFFSET_Y       = -15
local DEFAULT_DIALOG_WIDTH = 350
local MAX_ROWS             = 16

EnhancedInterface.EditModeCompanion = EnhancedInterface.EditModeCompanion or {}
local Companion = EnhancedInterface.EditModeCompanion

local providers = {}

function Companion.Register(provider)
    table.insert(providers, provider)
end
local dialog                 = nil
local rowFrames              = {}
local pendingSystemFrame     = nil
local pendingHideDialog      = false
local cachedBlizzDialogWidth = nil
local companionTooltip       = nil

local function GetTooltip()
    if not companionTooltip then
        companionTooltip = CreateFrame("GameTooltip", "EnhancedInterfaceEditModeCompanionTooltip", UIParent, "GameTooltipTemplate")
    end

    return companionTooltip
end

local function BuildRowFrame(index, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT")

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
        local tooltip = GetTooltip()
        tooltip:SetOwner(btn, "ANCHOR_RIGHT")
        tooltip:SetText(f.rowDef.label, 1, 1, 1)
        if f.rowDef.tooltip then
            tooltip:AddLine(f.rowDef.tooltip, nil, nil, nil, true)
        end
        tooltip:Show()
    end)
    cb:SetScript("OnLeave", function()
        if companionTooltip then
            companionTooltip:Hide()
        end
    end)

    f:Hide()
    return f
end

local function BuildDialog()
    if dialog then return end

    local d = CreateFrame("Frame", "EnhancedInterfaceEditModeCompanionDialog", UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(200)
    d:SetWidth(DEFAULT_DIALOG_WIDTH)
    d:SetHeight(DIALOG_PADDING_TOP + DIALOG_PADDING_BOT)
    d:Hide()

    local border = CreateFrame("Frame", nil, d, "DialogBorderTranslucentTemplate")
    border:SetAllPoints(d)
    d.Border = border

    local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", d, "TOP", 0, TITLE_OFFSET_Y)
    title:SetText("EnhancedInterface")
    d.Title = title

    local divider = d:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
    divider:SetHeight(16)
    divider:SetPoint("TOPLEFT",  d, "TOPLEFT",  DIALOG_PADDING_H,  -30)
    divider:SetPoint("TOPRIGHT", d, "TOPRIGHT", -DIALOG_PADDING_H, -30)
    d.Divider = divider

    dialog = d

    for i = 1, MAX_ROWS do
        rowFrames[i] = BuildRowFrame(i, d)
    end
end

local function UpdateCompanionDialog(systemFrame)
    if not dialog then return end

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

    local blizzWidth = cachedBlizzDialogWidth or DEFAULT_DIALOG_WIDTH
    dialog:SetWidth(blizzWidth)
    local rowWidth = blizzWidth - DIALOG_PADDING_H * 2

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

    for i = activeCount + 1, MAX_ROWS do
        rowFrames[i]:Hide()
    end

    local contentHeight = activeCount * (ROW_HEIGHT + ROW_SPACING) - ROW_SPACING
    dialog:SetHeight(DIALOG_PADDING_TOP + contentHeight + DIALOG_PADDING_BOT)

    dialog:ClearAllPoints()
    dialog:SetPoint("TOP", EditModeSystemSettingsDialog, "BOTTOM", 0, -4)

    dialog:Show()
end

local function RegisterHook()
    BuildDialog()

    EditModeSystemSettingsDialog:HookScript("OnSizeChanged", function(_, w, _h)
        if w and w > 0 then
            cachedBlizzDialogWidth = w
        end
    end)

    -- Hooks can run in tainted call chains; only set a flag here.
    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateSizeAndAnchors", function(self, systemFrame)
        if systemFrame ~= self.attachedToSystem then return end
        pendingSystemFrame = systemFrame
    end)

    -- Hooks can run in tainted call chains; only set a flag here.
    hooksecurefunc(EditModeManagerFrame, "Hide", function()
        if dialog then pendingHideDialog = true end
    end)
end

local _initFrame = CreateFrame("Frame")
_initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", RegisterHook)
end)
_initFrame:SetScript("OnUpdate", function()
    if pendingSystemFrame then
        local sf = pendingSystemFrame
        pendingSystemFrame = nil
        UpdateCompanionDialog(sf)
    end
    if pendingHideDialog then
        pendingHideDialog = false
        if dialog then dialog:Hide() end
    end
end)
