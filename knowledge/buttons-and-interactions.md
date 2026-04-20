# Buttons and Interactions

How to create and style buttons in retail WoW addons, handle clicks, and build hover interactions.

## Standard Button Templates

| Template | Description |
|---|---|
| `"UIPanelButtonTemplate"` | Standard gold/grey panel button (most common) |
| `"UIPanelButtonTemplate2"` | Variant with different sizing behaviour |
| `"UIPanelCloseButton"` | X close button (16×16), used in frames |
| `"GameMenuButtonTemplate"` | Larger menu-style button |
| `"OptionsButtonTemplate"` | Used in interface options |
| `"PanelTabButtonTemplate"` | Tab-style button (see tabs-and-panels.md) |

## Creating a Basic Button

```lua
local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
btn:SetSize(120, 22)
btn:SetPoint("CENTER", parent, "CENTER")
btn:SetText("Click Me")
btn:SetScript("OnClick", function(self, mouseButton, down)
    -- TAINT NOTE: OnClick is always a tainted execution context. Safe for
    -- writing to SavedVariables, addon-owned state, or purely addon-owned frames.
    -- If the handler must mutate Blizzard-managed frames (SetPoint, SetHeight,
    -- Show, Hide, SetScale, SetFont, etc.), do NOT call those APIs here —
    -- set a boolean flag and consume it from an OnUpdate poller instead.
    -- See knowledge/taint-and-secure-execution.md for the canonical pattern.
end)
```

## Button Scripts

| Script | Signature | Notes |
|---|---|---|
| `OnClick` | `(self, button, down)` | `button`: `"LeftButton"`, `"RightButton"`, etc. |
| `OnDoubleClick` | `(self, button)` | Double-click event |
| `OnMouseDown` | `(self, button)` | Fires on press |
| `OnMouseUp` | `(self, button)` | Fires on release |
| `OnEnter` | `(self, motion)` | Mouse enters the button |
| `OnLeave` | `(self, motion)` | Mouse leaves the button |
| `OnEnable` | `(self)` | Fired when button is enabled |
| `OnDisable` | `(self)` | Fired when button is disabled |

## Click Registration

By default buttons only receive `LeftButton` clicks. To receive all buttons:

```lua
btn:RegisterForClicks("AnyUp")       -- any mouse button, on release
btn:RegisterForClicks("AnyDown")     -- any mouse button, on press
btn:RegisterForClicks("AnyUp", "AnyDown")  -- both
```

## Enable / Disable

```lua
btn:Enable()    -- makes button clickable and shows normal state
btn:Disable()   -- greys out button and prevents clicks
btn:IsEnabled() -- returns true/false
```

Disabled buttons automatically use the `DisabledTexture` if set.

## Textures via Atlas

Use atlas textures instead of file paths wherever possible (they scale with UI and respect theme):

```lua
btn:SetNormalAtlas("common-button-blue-gradient")
btn:SetHighlightAtlas("common-button-blue-gradient", "ADD")
btn:SetPushedAtlas("common-button-blue-gradient")
btn:SetDisabledAtlas("common-button-blue-gradient")
```

Or use the lower-level texture API:

```lua
local tex = btn:CreateTexture(nil, "BACKGROUND")
tex:SetAtlas("common-icon-backdrop-square-rounded")
tex:SetAllPoints(btn)
```

Browse available atlas entries with `"/dump C_Texture.GetAtlasInfo(\"name\")"` in-game or search [wow-ui-source](https://github.com/Gethe/wow-ui-source).

## Tooltip on Hover

```lua
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Button Title", 1, 1, 1)          -- white title
    GameTooltip:AddLine("Description text.", 0.8, 0.8, 0.8, true)  -- grey body, wrap
    GameTooltip:Show()
end)

btn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)
```

Anchor options: `"ANCHOR_RIGHT"`, `"ANCHOR_LEFT"`, `"ANCHOR_TOP"`, `"ANCHOR_BOTTOM"`, `"ANCHOR_CURSOR"`, `"ANCHOR_TOPRIGHT"`, `"ANCHOR_TOPLEFT"`, `"ANCHOR_BOTTOMRIGHT"`, `"ANCHOR_BOTTOMLEFT"`, `"ANCHOR_NONE"`.

## Icon Button (No Border)

For icon-only buttons (e.g. toolbar icons):

```lua
local btn = CreateFrame("Button", nil, parent)
btn:SetSize(24, 24)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints(btn)
icon:SetAtlas("QuestNormal")  -- or SetTexture("Interface\\...")

local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
highlight:SetAllPoints(btn)
highlight:SetColorTexture(1, 1, 1, 0.2)  -- subtle white glow on hover
btn:SetHighlightTexture(highlight)

btn:SetScript("OnClick", function() ... end)
```

## Checked / Toggle Button

Use `CheckButton` for togglable buttons (see text-and-form-elements.md for checkboxes). For a custom toggle button, track state manually:

```lua
local active = false
btn:SetScript("OnClick", function(self)
    active = not active
    -- SetText on an addon-owned button is fine from OnClick.
    -- For mutations to Blizzard-managed frames use a flag + OnUpdate poller instead.
    if active then
        self:SetText("Active")
    else
        self:SetText("Inactive")
    end
end)
```

## Right-Click Context Menu

Use the `Menu` system (retail 10.0+):

```lua
local menuDescriptor = {
    {
        text = "Option 1",
        func = function() print("Option 1") end,
    },
    {
        text = "Option 2",
        func = function() print("Option 2") end,
    },
}

btn:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            rootDescription:CreateTitle("My Menu")
            rootDescription:CreateButton("Option 1", function() print("Option 1") end)
            rootDescription:CreateButton("Option 2", function() print("Option 2") end)
            rootDescription:CreateDivider()
            rootDescription:CreateButton("Close", function() end)
        end)
    end
end)
btn:RegisterForClicks("AnyUp")
```

## Button Width from Text

To size a button to fit its text — call this at setup time (file-load or ADDON_LOADED),
not from inside an event handler or hook:

```lua
btn:SetText("Label")
local textWidth = btn:GetTextWidth()
btn:SetWidth(math.max(80, textWidth + 20))  -- minimum 80px, 20px padding
```

## Combat Lockdown

Buttons attached to secure frames (e.g. action bars) may not be manipulated during combat. For non-action addon buttons this is rarely an issue, but if using `SecureActionButtonTemplate`:

```lua
-- Safe: check before modifying
if not InCombatLockdown() then
    btn:SetAttribute(...)
end
```

See `knowledge/taint-and-secure-execution.md` for full details.
