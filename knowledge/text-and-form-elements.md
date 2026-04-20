# Text and Form Elements

How to create text labels, input fields, checkboxes, sliders, and dropdowns in retail WoW addons.

## FontString (Text Labels)

FontStrings are not frames — they are created as children of a frame via `CreateFontString`.

```lua
local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
label:SetText("Hello World")
```

The third argument is a `FontObject` (an inherited font definition).

### Common Font Objects

| FontObject | Use |
|---|---|
| `"GameFontNormal"` | Standard body text (yellow-ish) |
| `"GameFontHighlight"` | White body text |
| `"GameFontDisable"` | Grey/disabled body text |
| `"GameFontNormalLarge"` | Larger body text |
| `"GameFontNormalSmall"` | Smaller body text |
| `"GameFontNormalHuge"` | Large heading |
| `"GameFontNormalLargeLeft"` | Large, left-aligned |
| `"GameFontHighlightLarge"` | White large text |
| `"GameFontHighlightSmall"` | White small text |
| `"GameTooltipText"` | Standard tooltip body text |
| `"GameTooltipHeaderText"` | Tooltip title |
| `"NumberFontNormalSmall"` | Numeric display (monospaced-ish) |

### FontString Methods

```lua
label:SetText("New text")
label:GetText()                          -- returns current text
label:SetTextColor(1, 0.82, 0)          -- RGB (gold)
label:SetTextColor(1, 1, 1, 0.5)        -- RGBA (semi-transparent white)
label:SetJustifyH("LEFT")               -- "LEFT", "CENTER", "RIGHT"
label:SetJustifyV("TOP")                -- "TOP", "MIDDLE", "BOTTOM"
label:SetWordWrap(true)                  -- enable word wrapping
label:SetMaxLines(3)                     -- limit visible lines
label:GetStringWidth()                   -- width of rendered text
label:GetStringHeight()                  -- height of rendered text
```

### Color Codes in Text

WoW supports inline color codes:

```lua
label:SetText("|cffff8000Orange text|r normal text")
-- Format: |cAARRGGBB ... |r
```

Common codes: `|cffffd100` (gold), `|cffff2020` (red), `|cff00ff00` (green), `|cffffffff` (white).

---

## EditBox (Text Input)

```lua
local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
editBox:SetSize(200, 20)
editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -30)
editBox:SetAutoFocus(false)  -- IMPORTANT: prevent stealing keyboard focus on Show()
editBox:SetMaxLetters(255)
editBox:SetText("default value")
```

### EditBox Methods

```lua
editBox:SetText("value")
editBox:GetText()                   -- returns current content
editBox:SetMaxLetters(n)            -- max character limit (0 = unlimited)
editBox:SetNumeric(true)            -- only allow numbers
editBox:SetPassword(true)           -- mask input as dots
editBox:SetAutoFocus(false)         -- don't grab focus when shown
editBox:SetFocus()                  -- programmatically focus the box
editBox:ClearFocus()                -- remove focus
editBox:HighlightText()             -- select all text
editBox:HighlightText(0, 5)         -- select chars 0-5
editBox:SetEnabled(false)           -- disable input
```

### EditBox Scripts

```lua
editBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        -- text was changed by the user (not SetText)
        local value = self:GetText()
    end
end)

editBox:SetScript("OnEnterPressed", function(self)
    local value = self:GetText()
    self:ClearFocus()
    -- process value
end)

editBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")  -- or restore previous value
    self:ClearFocus()
end)

editBox:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()  -- select all when focused
end)

editBox:SetScript("OnEditFocusLost", function(self)
    -- validate or save
end)
```

### Multi-line EditBox

```lua
local editBox = CreateFrame("EditBox", nil, parent)
editBox:SetMultiLine(true)
editBox:SetFontObject("GameFontNormal")
editBox:SetSize(300, 100)
editBox:SetAutoFocus(false)
```

For a scrollable multi-line input, parent it inside a `ScrollFrame`.

---

## CheckButton (Checkbox)

### With Built-in Label (Recommended)

```lua
local check = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
check:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
check.Text:SetText("Enable feature")
check.tooltip = "Tooltip shown on hover"  -- built into template's OnEnter
check:SetChecked(true)

check:SetScript("OnClick", function(self)
    local enabled = self:GetChecked()
    -- Save the setting, then apply it.
    -- TAINT NOTE: OnClick is always a tainted context. If applying the setting
    -- requires mutating Blizzard-managed frames (SetPoint, SetHeight, Show, Hide,
    -- SetScale, etc.), do NOT call those APIs here. Set a boolean flag and let an
    -- OnUpdate poller perform the frame writes. See taint-and-secure-execution.md.
    -- Direct calls are only safe when mutating purely addon-owned frames that
    -- Blizzard's secure layout system will never read.
end)
```

### Simple Checkbox (No Label)

```lua
local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
check:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
check:SetSize(26, 26)
check:SetChecked(false)

check:SetScript("OnClick", function(self)
    local enabled = self:GetChecked()
    -- TAINT NOTE: same as above — defer Blizzard frame mutations via flag + OnUpdate.
end)
```

Add a manual label for `UICheckButtonTemplate`:

```lua
local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("LEFT", check, "RIGHT", 4, 0)
label:SetText("Enable feature")
```

### CheckButton Methods

```lua
check:SetChecked(true)     -- set state
check:GetChecked()         -- returns true/false
check:SetEnabled(false)    -- disable interaction
```

---

## Slider

```lua
local slider = CreateFrame("Slider", nil, parent, "UISliderTemplateWithLabels")
slider:SetSize(200, 20)
slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -30)
slider:SetOrientation("HORIZONTAL")  -- or "VERTICAL"
slider:SetMinMaxValues(0, 100)
slider:SetValue(50)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)

-- Template provides .Text (title above), .Low (left label), .High (right label)
slider.Text:SetText("Volume")
slider.Low:SetText("0")
slider.High:SetText("100")
```

### Slider Scripts

```lua
slider:SetScript("OnValueChanged", function(self, value, userInput)
    if userInput then
        -- user dragged/clicked (not SetValue)
        -- round to step if needed
        value = math.floor(value + 0.5)
        -- Apply setting.
        -- TAINT NOTE: OnValueChanged is a tainted context. If applying the value
        -- requires mutating Blizzard-managed frames, defer via flag + OnUpdate.
        -- See taint-and-secure-execution.md.
    end
end)
```

### Slider Methods

```lua
slider:SetMinMaxValues(min, max)
slider:GetMinMaxValues()           -- returns min, max
slider:SetValue(val)
slider:GetValue()                  -- returns current value
slider:SetValueStep(step)          -- snap increment
slider:SetObeyStepOnDrag(true)     -- enforce step during drag
slider:Enable() / :Disable()
```

### Slider with Value Display

Pattern: show current value in the `.Text` or a separate FontString:

```lua
local valueLabel = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
valueLabel:SetPoint("TOP", slider, "BOTTOM", 0, -2)

slider:SetScript("OnValueChanged", function(self, value, userInput)
    valueLabel:SetText(string.format("%.0f", value))
end)
```

---

## Dropdown (Modern Menu System)

Since 10.0, Blizzard's preferred dropdown is the `Menu` system. Avoid `UIDropDownMenu_*` for new code.

### Simple Dropdown via Menu

```lua
local selected = "Option A"
local options = { "Option A", "Option B", "Option C" }

local dropdownBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
dropdownBtn:SetSize(150, 22)
dropdownBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
dropdownBtn:SetText(selected .. " \226\150\190")  -- ▾ arrow appended

dropdownBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
        for _, option in ipairs(options) do
            local opt = option  -- capture loop var
            rootDescription:CreateRadio(opt, function()
                return selected == opt
            end, function()
                selected = opt
                dropdownBtn:SetText(selected .. " \226\150\190")
                -- Apply setting.
                -- TAINT NOTE: menu callbacks are tainted contexts. If applying
                -- requires mutating Blizzard-managed frames, defer via flag + OnUpdate.
            end)
        end
    end)
end)
```

### DropdownButton Widget (10.2+)

```lua
-- Uses the DropdownButton widget if available
local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
dropdown:SetSize(150, 22)
dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
dropdown:SetupMenu(function(dropdown, rootDescription)
    rootDescription:CreateTitle("Choose option")
    rootDescription:CreateRadio("Option A", function() return selected == "Option A" end, function()
        selected = "Option A"
    end)
    rootDescription:CreateRadio("Option B", function() return selected == "Option B" end, function()
        selected = "Option B"
    end)
end)
```

---

## Form Layout Tips

- Use consistent 8–10px left/right padding inside frames
- Stack elements top-to-bottom with 6–8px vertical gap
- Align labels to the right of checkboxes / left of sliders
- Group related controls with a header FontString using `"GameFontNormalLarge"` or a thin separator line:

```lua
-- Separator line
local sep = frame:CreateTexture(nil, "OVERLAY")
sep:SetColorTexture(0.5, 0.5, 0.5, 0.5)
sep:SetSize(frame:GetWidth() - 20, 1)
sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -50)
```
