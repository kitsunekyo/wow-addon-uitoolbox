# Custom Frames and Borders

How to create styled frames with Blizzard-look backdrops, borders, and drag behaviour in retail WoW addons.

## BackdropTemplate (Required since 9.0.1)

Since Shadowlands (9.0.1), `SetBackdrop` requires the frame to inherit `"BackdropTemplate"`:

```lua
local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
frame:SetSize(300, 200)
frame:SetPoint("CENTER")
```

Without `"BackdropTemplate"`, calling `SetBackdrop` will silently fail.

## SetBackdrop Table

```lua
frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileEdge = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)         -- black, 80% opaque
frame:SetBackdropBorderColor(0.6, 0.6, 0.6)  -- grey border
```

| Field | Description |
|---|---|
| `bgFile` | Background texture path (tiled) |
| `edgeFile` | Border/edge texture path |
| `tile` | Whether the bg texture tiles |
| `tileEdge` | Whether the edge texture tiles |
| `tileSize` | Size of bg tile in pixels |
| `edgeSize` | Width/height of border in pixels |
| `insets` | Inner padding so content avoids the border |

## Pre-defined Backdrop Tables

Blizzard defines ready-made backdrop tables in `Blizzard_SharedXML/Backdrop.lua`:

```lua
frame:SetBackdrop(BACKDROP_TOOLTIP_8_8_1111)        -- tooltip look (thin border)
frame:SetBackdrop(BACKDROP_DIALOG_32_32)             -- dialog box look (thick border)
frame:SetBackdrop(BACKDROP_DARK_DIALOG_32_32)        -- dark dialog variant
frame:SetBackdrop(BACKDROP_TOOLTIP_16_16_5555)       -- wider insets
```

Or use `ApplyBackdrop` pattern:

```lua
frame.backdropInfo = BACKDROP_TOOLTIP_8_8_1111
frame:ApplyBackdrop()
```

## Common Texture Paths

| Use | Path |
|---|---|
| Tooltip background | `"Interface\\Tooltips\\UI-Tooltip-Background"` |
| Tooltip border | `"Interface\\Tooltips\\UI-Tooltip-Border"` |
| Dialog background | `"Interface\\DialogFrame\\UI-DialogBox-Background"` |
| Dialog border | `"Interface\\DialogFrame\\UI-DialogBox-Border"` |
| Dark background | `"Interface\\DialogFrame\\UI-DialogBox-Background-Dark"` |
| Gold border | `"Interface\\DialogFrame\\UI-DialogBox-Gold-Border"` |
| Flat dark bg | `"Interface\\BUTTONS\\WHITE8X8"` (tint with color) |

## Standard Frame Templates

Use these for complete styled frames with title bar and close button:

| Template | Description |
|---|---|
| `"BasicFrameTemplate"` | Titled frame with dragon-art header and close button |
| `"BasicFrameTemplateWithInset"` | Same + inset texture for content area |
| `"ButtonFrameTemplate"` | Larger dialog-style frame |
| `"PortraitFrameTemplate"` | Frame with portrait slot (like character frame) |
| `"InsetFrameTemplate"` | Inset panel only (no title bar) |
| `"ThinBorderTemplate"` | Minimal thin-line border |

```lua
local frame = CreateFrame("Frame", "MyAddonFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(400, 300)
frame:SetPoint("CENTER")
frame.TitleText:SetText("My Addon")
-- frame.CloseButton is already wired up to hide frame
```

## Making a Frame Movable

```lua
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
```

`SetClampedToScreen(true)` prevents dragging the frame off-screen.

## Making a Frame Resizable

```lua
frame:SetResizable(true)
frame:SetResizeBounds(200, 150, 600, 400)  -- min w/h, max w/h

local resizeHandle = CreateFrame("Button", nil, frame)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
resizeHandle:SetNormalAtlas("UI-Frame-SouthEast-Resize")
resizeHandle:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
end)
resizeHandle:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
end)
```

## Frame Strata

Controls render order (back to front):

| Strata | Use |
|---|---|
| `"BACKGROUND"` | World-level decorations |
| `"LOW"` | Low-priority UI |
| `"MEDIUM"` | Default for most addon frames |
| `"HIGH"` | Important UI elements |
| `"DIALOG"` | Dialogs that should appear above most UI |
| `"FULLSCREEN"` | Full-screen overlays |
| `"FULLSCREEN_DIALOG"` | Dialogs over fullscreen content |
| `"TOOLTIP"` | Always on top (except cursor) |

```lua
frame:SetFrameStrata("DIALOG")
frame:SetFrameLevel(5)  -- fine-grained control within the same strata
```

## Adding a Title Bar

When using `BasicFrameTemplate`, the title is via `frame.TitleText`. For a custom frame:

```lua
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOP", frame, "TOP", 0, -8)
title:SetText("Frame Title")
```

## Adding a Close Button

```lua
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function() frame:Hide() end)
```

## Saving/Restoring Position

```lua
-- Save on drag stop
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    MyAddonDB.framePos = { point = point, relPoint = relPoint, x = x, y = y }
end)

-- Restore on load
local pos = MyAddonDB.framePos
if pos then
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end
```

## Show/Hide with Animation

Simple fade in/out using `UIFrameFadeIn` / `UIFrameFadeOut` (FrameXML helpers):

```lua
UIFrameFadeIn(frame, 0.3, 0, 1)   -- fade in over 0.3s
UIFrameFadeOut(frame, 0.3, 1, 0)  -- fade out over 0.3s
```

Or toggle instantly:

```lua
frame:Show()
frame:Hide()
frame:SetShown(not frame:IsShown())
```
