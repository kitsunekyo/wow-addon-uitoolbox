# Tabs and Panels

How to create tabbed interfaces in retail WoW addons using Blizzard's built-in tab system.

## Overview

WoW provides a tab system via `PanelTemplates.lua` (FrameXML). Tabs are Button frames using the `"PanelTabButtonTemplate"` template, managed through a set of `PanelTemplates_*` helper functions.

## Core Pattern

```lua
local frame = CreateFrame("Frame", "MyAddonFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(400, 300)
frame:SetPoint("CENTER")

-- Content panels (one per tab)
local panel1 = CreateFrame("Frame", nil, frame)
panel1:SetAllPoints(frame)

local panel2 = CreateFrame("Frame", nil, frame)
panel2:SetAllPoints(frame)
panel2:Hide()

-- Tab buttons
local tab1 = CreateFrame("Button", "MyAddonFrameTab1", frame, "PanelTabButtonTemplate")
tab1:SetText("Overview")
tab1:SetID(1)
tab1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, -30)

local tab2 = CreateFrame("Button", "MyAddonFrameTab2", frame, "PanelTabButtonTemplate")
tab2:SetText("Settings")
tab2:SetID(2)
tab2:SetPoint("LEFT", tab1, "RIGHT", -14, 0)

-- Register tabs with the frame
PanelTemplates_SetNumTabs(frame, 2)
PanelTemplates_SetTab(frame, 1)  -- select tab 1 by default

-- Tab switch handler
local panels = { panel1, panel2 }
local function SelectTab(id)
    PanelTemplates_SetTab(frame, id)
    for i, panel in ipairs(panels) do
        if i == id then panel:Show() else panel:Hide() end
    end
end

tab1:SetScript("OnClick", function() SelectTab(1) end)
tab2:SetScript("OnClick", function() SelectTab(2) end)
```

## Key Functions

| Function | Description |
|---|---|
| `PanelTemplates_SetNumTabs(frame, n)` | Tells the system how many tabs the frame has |
| `PanelTemplates_SetTab(frame, id)` | Sets the visually selected tab (highlights it) |
| `PanelTemplates_UpdateTabs(frame)` | Refreshes tab appearance (call after changing selection) |
| `PanelTemplates_TabResize(tab, padding, minWidth, maxWidth, absoluteSize)` | Resizes a tab to fit its text with optional constraints |

## Tab Sizing

By default tabs size to the text. To auto-size with padding:

```lua
-- Auto-size tab to text + 24px padding, minimum 60px wide
PanelTemplates_TabResize(tab1, 24, 60)
```

Call this after `SetText` if tab text changes dynamically.

## Tab State

The system tracks `frame.numTabs` and `frame.selectedTab` on the parent frame:

```lua
frame.numTabs      -- total number of tabs
frame.selectedTab  -- currently selected tab ID (1-indexed)
```

`PanelTemplates_SetTab` sets `frame.selectedTab` and updates the visual state of all tab buttons named `<frameName>Tab<N>` automatically — which is why tab buttons must be named following the convention `<ParentFrameName>Tab<N>`.

## Naming Convention (Important)

Tab buttons **must** follow this naming scheme for `PanelTemplates_SetTab` to find them:

```
<ParentFrameName>Tab1
<ParentFrameName>Tab2
...
```

If the parent frame is `"MyAddonFrame"`, tabs must be named `"MyAddonFrameTab1"`, `"MyAddonFrameTab2"`, etc.

## Scrollable Tab Rows

For many tabs that overflow horizontally, use `TabSystem` or manually handle overflow. Simple approach: use a scroll frame as the tab container.

## Nested Panels with ScrollFrames

For scrollable content inside a panel:

```lua
local scrollFrame = CreateFrame("ScrollFrame", nil, panel1, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", panel1, "TOPLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", panel1, "BOTTOMRIGHT", -22, 4)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(scrollFrame:GetWidth(), 1)  -- height grows with content
scrollFrame:SetScrollChild(content)
```

## Integration with Settings Panel

When building addon settings, prefer integrating into Blizzard's Settings UI (`Settings.RegisterVerticalLayoutCategory`) instead of a standalone tab frame — see the Settings API. Use tabs for in-world or HUD frames that need multiple views.

## Common Templates

| Template | Description |
|---|---|
| `"PanelTabButtonTemplate"` | Standard WoW tab button (rounded bottom tabs) |
| `"BasicFrameTemplate"` | Simple titled frame with close button |
| `"BasicFrameTemplateWithInset"` | Same with inset background texture |
| `"UIPanelScrollFrameTemplate"` | Scroll frame with standard scrollbar |
