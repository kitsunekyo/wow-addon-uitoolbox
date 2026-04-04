# Attaching Custom Buttons to Blizzard Frames

## Overview

You can inject fully functional custom buttons into any accessible Blizzard frame by parenting the
button to the target frame and anchoring it relative to an existing child widget. No Blizzard API is
required for this — it is plain Lua widget creation.

---

## Core Pattern

```lua
local btn = CreateFrame("Button", nil, targetFrame)
btn:SetSize(22, 22)
btn:SetPoint("RIGHT", targetFrame.SettingsDropdown, "LEFT", -4, 0)

-- Use a Blizzard built-in atlas for the icon
btn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
btn:GetNormalTexture():SetAtlas("auctionhouse-filterdropdown-arrow-open", true)
btn:GetNormalTexture():SetAllPoints(btn)

btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
btn:GetHighlightTexture():SetAtlas("auctionhouse-filterdropdown-arrow-open", true)
btn:GetHighlightTexture():SetAllPoints(btn)

btn:SetScript("OnClick", function() ... end)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("My Action", 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

The key is:
1. **Parent to the target frame** — `CreateFrame("Button", nil, targetFrame)`. The button is now a
   child of the Blizzard frame.
2. **Anchor relative to an existing child** — use `SetPoint` relative to a known child widget
   (e.g. `targetFrame.SettingsDropdown`).

---

## Blizzard Button Textures (Atlas-based)

Rather than shipping custom textures, you can reuse Blizzard's atlas system.

```lua
-- Generic helper to apply an atlas to any button texture slot
local function ApplyAtlas(btn, setter, getter, atlasName)
    btn[setter](btn, "Interface\\Buttons\\WHITE8X8")   -- create the texture layer
    local tex = btn[getter](btn)
    if tex then
        tex:SetAtlas(atlasName, true)   -- true = use atlas intrinsic size
        tex:SetAllPoints(btn)
    end
end

ApplyAtlas(btn, "SetNormalTexture",    "GetNormalTexture",    "auctionhouse-filterdropdown-arrow-open")
ApplyAtlas(btn, "SetHighlightTexture", "GetHighlightTexture", "auctionhouse-filterdropdown-arrow-open")
ApplyAtlas(btn, "SetPushedTexture",    "GetPushedTexture",    "auctionhouse-filterdropdown-arrow")
```

### Useful atlas names for small icon buttons

| Atlas name | Description |
|---|---|
| `auctionhouse-filterdropdown-arrow-open` | Chevron pointing down (expanded state) |
| `auctionhouse-filterdropdown-arrow` | Chevron pointing right (collapsed state) |
| `damagemeters-scalehandle` | Resize handle corner icon |
| `damagemeters-scalehandle-hover` | Resize handle hover state |
| `UI-HUD-MicroMenu-Achievements-Up` | Small achievement icon |

You can discover atlas names in-game with addons like `AtlasLoot` or by searching the
[wow-ui-source](https://github.com/Gethe/wow-ui-source) for `SetAtlas` calls.

---

## Accessing Blizzard Frame Children

Blizzard frames expose their child widgets as named keys set via `parentKey` in XML. For
`DamageMeterSessionWindow1/2/3`:

| Key | Type | Description |
|---|---|---|
| `window.SettingsDropdown` | DropdownButton | Settings gear (top-right of header) |
| `window.SessionDropdown` | DropdownButton | Session selector |
| `window.DamageMeterTypeDropdown` | DropdownButton | Stat type selector |
| `window.Header` | Texture | Header bar background (height = 32) |
| `window.ScrollBox` | ScrollBox | Main list |
| `window.ScrollBar` | MinimalScrollBar | Scroll bar |
| `window.ResizeButton` | Button | Bottom-right resize handle |
| `window.Background` | Texture | Semi-transparent background |

Access the windows by global name:

```lua
local window = _G["DamageMeterSessionWindow1"]  -- always exists
local window2 = _G["DamageMeterSessionWindow2"] -- created lazily
local window3 = _G["DamageMeterSessionWindow3"] -- created lazily
```

---

## Idempotency Guard

Windows 2 and 3 are created lazily. Always guard injection with a sentinel on the frame itself:

```lua
if window._myAddonButton then return end  -- already injected
-- ... create button ...
window._myAddonButton = btn
```

---

## Hooking Late-Created Windows

```lua
local dm = _G["DamageMeter"]

-- Fires when player opens an additional meter window from the settings dropdown
if dm and dm.ShowNewSessionWindow then
    hooksecurefunc(dm, "ShowNewSessionWindow", function()
        C_Timer.After(0, TryInjectAll)  -- defer one tick for Blizzard to finish
    end)
end

-- Belt-and-suspenders: also catch the parent OnShow (login/reload)
if dm then
    dm:HookScript("OnShow", function()
        C_Timer.After(0, TryInjectAll)
    end)
end
```

The `C_Timer.After(0, ...)` defers one frame, ensuring Blizzard has finished its own `OnLoad`/`OnShow`
processing before you access the window's children.

---

## Button Templates from Blizzard

Blizzard ships several reusable button templates you can pass as the fourth arg to `CreateFrame`:

| Template | Appearance |
|---|---|
| `UIPanelButtonTemplate` | Standard dialog button with border |
| `SecureActionButtonTemplate` | Action button (combat-safe, for spells/macros) |
| `InsecureActionButtonTemplate` | Like above but outside combat only |
| `GameMenuButtonTemplate` | Game menu style |

For icon-only buttons in tight spaces (like a 22×22 button in a header), use a plain
`CreateFrame("Button", nil, parent)` with manual atlas textures — the templates add unnecessary
padding and text layers.

---

## See Also

- `EnhancedInterface/Modules/DamageMeterButton.lua` — reference implementation used in this addon
- [UIOBJECT Button — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/UIOBJECT_Button)
- [Gethe/wow-ui-source — Blizzard_DamageMeter](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_DamageMeter)
