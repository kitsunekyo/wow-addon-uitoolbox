# Edit Mode and Injected Buttons — Drag Behavior

## The Two Classes of Damage Meter Windows

The damage meter uses two fundamentally different positioning strategies. Understanding this
distinction is critical for knowing how custom buttons behave during Edit Mode.

---

## Window 1 (Primary) — Controlled by Edit Mode

`DamageMeterSessionWindow1` is **anchored to its parent `DamageMeter` frame** with full-coverage
points:

```lua
-- from DamageMeter.lua (Blizzard source)
sessionWindow:SetPoint("TOPLEFT")
sessionWindow:SetPoint("BOTTOMRIGHT")
```

The `DamageMeter` parent frame is itself a registered **Edit Mode system frame** — it implements
`EditModeDamageMeterSystemMixin`. When the player drags the damage meter in Edit Mode, they are
dragging the `DamageMeter` parent, not `DamageMeterSessionWindow1` directly. The session window
follows because it is anchored to the parent via `TOPLEFT`/`BOTTOMRIGHT`.

**Result:** Any button you inject into `DamageMeterSessionWindow1` (parented to it, anchored
relative to its children) **moves with the frame** during Edit Mode dragging — automatically,
because the entire parent subtree moves together.

No extra code is required to achieve this. Parenting is sufficient.

---

## Windows 2 & 3 (Secondary) — Free-floating, No Edit Mode

Secondary windows are **not** registered with Edit Mode:

```lua
-- from DamageMeter.lua (Blizzard source)
function DamageMeterMixin:CanMoveOrResizeSessionWindow(sessionWindow)
    -- The size and location of the primary session window is controlled through edit mode.
    return self:GetPrimarySessionWindow() ~= sessionWindow
end
```

Secondary windows are given their own drag/resize capability independent of Edit Mode:
- `SetMovable(true)`
- `SetResizable(true)`
- Drag is initiated by `OnDragStart` → `StartMoving()` on the session window itself

Injected buttons in secondary windows also move with them during free-drag, because they are
children of the session window frame.

---

## Edit Mode: ApplyLayoutToFrame Hook

When Edit Mode applies a saved layout, it calls `EditModeManagerFrame:ApplyLayoutToFrame(systemFrame)`.
For the damage meter, this resets the position of the `DamageMeter` parent frame. If your addon
has saved a custom position for `DamageMeterSessionWindow1`, Edit Mode will overwrite it.

The correct pattern to survive this (used in `DamageMeterDrag.lua`):

```lua
hooksecurefunc(EditModeManagerFrame, "ApplyLayoutToFrame", function(_, systemFrame)
    if systemFrame == DamageMeter then
        -- Re-apply your saved position one tick later
        C_Timer.After(0, function()
            ReapplyPosition(frame, db)
        end)
    end
end)
```

This is only relevant if you are **overriding the Edit Mode position** of the primary window. If
you just want buttons that move with the frame, no hook is needed.

---

## Summary Table

| Window | Moves with Edit Mode drag? | Button moves with window? | Notes |
|---|---|---|---|
| `DamageMeterSessionWindow1` | Yes (via parent `DamageMeter`) | Yes (child frame) | Dragged in Edit Mode only |
| `DamageMeterSessionWindow2/3` | N/A (not in Edit Mode) | Yes (child frame) | Free-drag outside Edit Mode |

---

## Key Takeaway

**Parenting a button to a frame is all that is needed for the button to move with the frame.**

Whether the frame is moved by Edit Mode, free-drag, or `SetPoint` — all children move with it
automatically. There is no API to register a button as "attached" to a frame; the WoW widget
hierarchy handles this natively.

---

## Caveats

- **Combat lockdown:** You cannot call `SetMovable`, `EnableMouse`, or similar protected methods
  during combat. Guard these calls with `if not InCombatLockdown() then`.
- **`SetUserPlaced(false)`:** Blizzard calls this on secondary windows when they are first created
  to prevent premature position-cache writes. If your addon reuses the window name and a stale
  position exists in the layout cache, this avoids restoring the wrong position.
- **Edit Mode visibility:** During Edit Mode, `DamageMeter:SetIsEditing(true)` is called. The
  primary session window shows mock data. Your injected button will be visible and clickable during
  Edit Mode unless you hide it conditionally.

---

## See Also

- `EnhancedInterface/Modules/DamageMeterDrag.lua` — position override with `ApplyLayoutToFrame` hook
- `EnhancedInterface/Modules/DamageMeterButton.lua` — button injection reference implementation
- [Edit Mode — warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/Edit_Mode)
- [Blizzard_DamageMeter/DamageMeter.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_DamageMeter/DamageMeter.lua)
