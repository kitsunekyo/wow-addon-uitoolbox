# Adding Custom Sections to the Objective Tracker

How to inject a fully native-looking custom module into the "All Objectives" tracker panel (`ObjectiveTrackerFrame`), sitting alongside built-in sections like Quests and World Quests.

---

## Architecture Overview

The tracker is a three-tier system, all inside `Blizzard_ObjectiveTracker`:

| Tier | Global | Role |
|---|---|---|
| Container | `ObjectiveTrackerFrame` | The visible panel ("All Objectives") |
| Manager | `ObjectiveTrackerManager` | Singleton registry; owns all containers and modules |
| Module | e.g. `QuestObjectiveTracker` | One collapsible section (a frame mixin) |

Each section is a **module** — a frame that inherits `ObjectiveTrackerModuleTemplate` and overrides `LayoutContents()`.

---

## The Correct Implementation Pattern

### Do not use XML for the module frame

The XML `mixin=` attribute is evaluated immediately at parse time. If the paired Lua file hasn't loaded yet, WoW throws:

```
Has bad mixin: YourMixinName
```

The safest approach for third-party addons is to skip the XML entirely and create the frame purely in Lua.

### Full working skeleton

```lua
-- 1. Define the mixin BEFORE CreateFrame
local MyTrackerModuleMixin = CreateFromMixins(ObjectiveTrackerModuleMixin);

function MyTrackerModuleMixin:InitModule()
    -- Called once when the module is first wired into a container.
    -- Register events here if your content is data-driven.
end

function MyTrackerModuleMixin:LayoutContents()
    -- Called every repaint. Must call LayoutBlock() for each item.
    -- Return immediately if LayoutBlock() returns false (no space left).
    local block = self:GetBlock("my_unique_key");
    block:SetHeader("My Block Title");
    block:AddObjective("obj1", "Objective text here", nil, nil,
        OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE);
    if not self:LayoutBlock(block) then return end
end

-- 2. Create the frame in Lua using the Blizzard template
local frame = CreateFrame(
    "Frame",
    "MyTrackerModule",           -- becomes a global; used by SetModuleContainer
    ObjectiveTrackerFrame,       -- parent (re-anchored later by SetContainer)
    "ObjectiveTrackerModuleTemplate"
);

-- 3. Apply the mixin AFTER CreateFrame
Mixin(frame, MyTrackerModuleMixin);

-- 4. Set headerText AND call SetHeader() explicitly.
--    OnLoad() fires during CreateFrame and reads self.headerText at that moment,
--    before we've set it. SetHeader() pushes the label into the header sub-frame
--    retroactively.
frame.headerText = "My Section";
frame:SetHeader("My Section");

-- 5. Set uiOrder to a number before registration.
--    Built-in modules use 1–11. nil crashes the container sort.
--    > 11 appends below all built-in sections.
frame.uiOrder = 100;

-- 6. Register after Init() has run
--    hooksecurefunc guarantees we run after ObjectiveTrackerManager:Init(),
--    which is when self.containers is populated. Without this, SetModuleContainer
--    hits a silent guard and does nothing.
--    PLAYER_ENTERING_WORLD is a fallback for the case where Init already ran
--    before our hook was installed (can happen depending on load order).
local registered = false;
local function TryRegister()
    if registered then return end;
    if not (ObjectiveTrackerManager.containers
            and ObjectiveTrackerManager.containers[ObjectiveTrackerFrame]) then
        return;
    end
    registered = true;
    ObjectiveTrackerManager:SetModuleContainer(MyTrackerModule, ObjectiveTrackerFrame);
    -- UpdateAll on the next tick: SetModuleContainer calls MarkDirty, but if
    -- Init's layout pass has already consumed the dirty ticker a manual nudge
    -- ensures the module appears immediately.
    C_Timer.After(0, function()
        ObjectiveTrackerManager:UpdateAll();
    end);
end

hooksecurefunc(ObjectiveTrackerManager, "Init", TryRegister);

local _f = CreateFrame("Frame");
_f:RegisterEvent("PLAYER_ENTERING_WORLD");
_f:SetScript("OnEvent", function() TryRegister() end);
```

---

## Key API Reference

### Module mixin

| Method | When to override | Notes |
|---|---|---|
| `InitModule()` | Optional | Called once on first `SetContainer`. Register events here. |
| `LayoutContents()` | **Required** | Called every repaint. Must call `LayoutBlock()` at least once or module stays hidden. |
| `OnEvent(event, ...)` | Optional | Call `self:MarkDirty()` to trigger a repaint. |

### Building blocks inside `LayoutContents()`

```lua
-- Acquire (or reuse) a block frame for a given unique string key
local block = self:GetBlock("unique_key");

-- Set the bold header line (also seeds block.height)
block:SetHeader("Title text");

-- Add an objective line below the header
-- dashStyle options: OBJECTIVE_DASH_STYLE_SHOW | HIDE | HIDE_AND_COLLAPSE
block:AddObjective("obj_key", "Line text", nil, nil, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE);

-- Finalise the block. Returns false if the tracker panel is full — bail immediately.
if not self:LayoutBlock(block) then return end
```

### Triggering a repaint from an event

```lua
function MyTrackerModuleMixin:OnEvent(event, ...)
    self:MarkDirty();   -- schedules LayoutContents() on the next frame
end
```

`MarkDirty()` is a no-op if `self.parentContainer` is nil (i.e. before `SetContainer` has run), so it is safe to call at any time.

---

## Positioning

`uiOrder` controls the display order. Built-in modules occupy values 1–11 (in the order they are listed in `ObjectiveTrackerManager:Init()`):

| uiOrder | Module |
|---|---|
| 1 | ScenarioObjectiveTracker |
| 2 | UIWidgetObjectiveTracker |
| 3 | CampaignQuestObjectiveTracker |
| 4 | QuestObjectiveTracker |
| 5 | AdventureObjectiveTracker |
| 6 | AchievementObjectiveTracker |
| 7 | MonthlyActivitiesObjectiveTracker |
| 8 | InitiativeTasksObjectiveTracker |
| 9 | ProfessionsRecipeTracker |
| 10 | BonusObjectiveTracker |
| 11 | WorldQuestObjectiveTracker |

Use a fractional value (e.g. `3.5`) to slot between existing modules. Use `> 11` to append at the bottom.

---

## Visibility Rules

The module is shown only when **all** of the following are true:

1. `LayoutContents()` calls `LayoutBlock()` at least once and it returns `true`
   — this is what sets `hasContents = true` internally via `InternalAddBlock()`
2. `availableHeight > 0` (the panel has room)
3. The module is not collapsed

`hasContents` is reset to `false` at the start of every layout pass in `BeginLayout()`. It cannot be pre-seeded manually.

---

## Common Pitfalls

| Mistake | Symptom | Fix |
|---|---|---|
| XML `mixin=` before paired Lua loads | "Has bad mixin" error | Create frame in Lua; skip XML |
| `frame.headerText = "..."` without `frame:SetHeader(...)` | Section appears with no header label | Always call `SetHeader()` explicitly after `CreateFrame` |
| `uiOrder = nil` | Container sort crashes silently | Always assign a number before registration |
| Using `ContinueAfterAllEvents` instead of hooking `Init` | `SetModuleContainer` silently does nothing | Use `hooksecurefunc(ObjectiveTrackerManager, "Init", ...)` |
| Not calling `UpdateAll()` after late registration | Module registered but not rendered until next organic update | Call `C_Timer.After(0, function() ObjectiveTrackerManager:UpdateAll() end)` after `SetModuleContainer` |
| `LayoutContents()` never calls `LayoutBlock()` | Module always hidden (state = NoObjectives) | Must call `GetBlock` → populate → `LayoutBlock` |

---

## Taint Notes

- `ObjectiveTrackerManager`, `ObjectiveTrackerFrame`, and all module frames are plain Lua tables / non-secure frames. No taint risk for the registration or layout path.
- Use `hooksecurefunc` (not `SetScript`) if you need to hook any container or manager methods.
- `MarkDirty()` and `UpdateAll()` are safe to call from addon code at any time.
