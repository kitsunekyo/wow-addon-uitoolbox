# Taint and Secure Execution

Source: [warcraft.wiki.gg — Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)

## Why This Matters

Taint is one of the most important concepts in WoW addon development. Getting it wrong
causes **protected functions to silently fail or error**, typically in combat — right when
the player needs the UI most. The damage is permanent until a UI reload.

For EnhancedInterface specifically: because we inject buttons into and hook Blizzard frames, we
are in frequent proximity to the protected-function boundary. Understanding taint prevents
us from accidentally breaking Blizzard's UI for the player.

---

## What Is Taint?

WoW runs Lua in two execution contexts:

- **Secure (clean):** Blizzard's signed FrameXML. Can call any API.
- **Tainted (dirty):** All third-party addon code, always. Cannot call protected APIs.

**Taint spreads like honey.** Any value written by tainted code becomes tainted. If that
tainted value is later read by Blizzard's secure code, Blizzard's execution path becomes
tainted too — and if it then tries to call a protected function, it errors.

### What Can Be Tainted

All Lua values can be tainted: locals, globals, table keys, table values, function closures.

- Creating a value inherits the current taint of the execution path.
- Reading a secure value from tainted code → result is tainted; original stays clean.
- Reading a tainted value → result is tainted, execution path becomes tainted.
- Writing to a global → the global gets the taint of the current execution path.

### The Critical Rule

> **Never write to a global variable that Blizzard's secure code will later read.**

If you shadow or overwrite a Blizzard global from addon code, you taint it. Any Blizzard
function that reads that global then becomes tainted and will fail when it calls a
protected function.

---

## Taint vs. Combat Lockdown — Two Distinct Concepts

These are often confused but are separate restrictions:

| Concept | What Triggers It | What It Blocks |
|---|---|---|
| **Taint** | Addon code touching secure values | Protected function calls (any time) |
| **Combat Lockdown** | Entering combat | Modifying protected frames (Show/Hide/SetAttribute/SetPoint) |

Taint errors can happen **outside combat**. Combat lockdown errors only happen **in combat**.
Both must be handled correctly.

---

## Protected Functions and the `AllowedWhenUntainted` Flag

Many API functions are annotated `AllowedWhenUntainted` in the API documentation. This
means they **return nil or silently fail when called from tainted (addon) code**.

Known examples relevant to EnhancedInterface:

- `C_NamePlate.GetNamePlates()` — returns `nil` from addon code
- `C_NamePlate.GetNamePlateForUnit()` — returns `nil` from addon code

These APIs require a secure execution path; they cannot be called directly from addon code.
The workaround is to use hook patterns that receive frame references as arguments (e.g.
via `hooksecurefunc`), bypassing the need to call these APIs directly.

---

## Safe Patterns

### 1. `hooksecurefunc` — the primary tool

```lua
hooksecurefunc("FunctionName", function(arg1, arg2)
    -- runs AFTER the original, same args, return values ignored
    -- does NOT taint the original function
end)

-- Also works on table methods:
hooksecurefunc(SomeFrame, "MethodName", function(self, ...)
    -- self is the frame, clean reference from Blizzard's execution
end)
```

- The original function runs first, fully secure.
- Your hook receives the same arguments but **cannot** affect the original's return values.
- Your hook code is tainted, but it does not retroactively taint the original call.
- **Cannot be undone** without a full UI reload.
- Since Patch 11.0.0 (TWW), certain core Lua functions cannot be hooked at all
  (e.g. `pcall`, `pairs`, `rawset`, `setmetatable`).

### 2. `frame:HookScript` — for script handlers

```lua
frame:HookScript("OnClick", function(self, button, down)
    -- runs AFTER any existing OnClick handlers
end)
```

Use instead of `frame:SetScript` when you want to add behavior without replacing existing
handlers (which would break any previously registered secure handler).

### 3. `InCombatLockdown()` guard — for protected frame modifications

```lua
if InCombatLockdown() then return end
frame:SetMovable(true)
frame:SetAttribute("type", "spell")
```

Always check `InCombatLockdown()` before:
- Calling `Show()`, `Hide()` on protected frames
- Calling `SetAttribute()` on any frame
- Calling `SetMovable()`, `EnableMouse()`, `SetPoint()` on protected frames or their parents/anchors

Queue the action to `PLAYER_REGEN_ENABLED` if it needs to run eventually.

### 4. Avoid global pollution

```lua
-- BAD: pollutes the global namespace, risks taint spreading
MyAddonHelper = function() ... end

-- GOOD: keep state local to the module / in an addon-owned table
local MyAddon = MyAddon or {}
local function helper() ... end
```

### 5. Don't call `C_Timer.After` inside a tainted hook

`C_Timer.After(delay, callback)` schedules a deferred Lua function. When the callback
fires, it does NOT start a fresh taint context — **the closure inherits the taint of
the execution context in which it was created**.

If `C_Timer.After` is called inside a `hooksecurefunc` callback that ran during
another addon's tainted call (e.g., `AccWideUILayoutSelection` calling
`C_EditMode.SetActiveLayout()`), the deferred function carries that addon's taint.
When it later does frame manipulation, those operations taint shared Blizzard state
(frame positions, string tables), causing unrelated errors like
`"attempt to perform string conversion on a secret string value"` in
`ChatHistory_GetToken` / `HistoryKeeper.lua`.

**Pattern to avoid:**
```lua
-- BAD: C_Timer.After inside a hooksecurefunc — closure captures tainted context
hooksecurefunc(EditModeManagerFrame, "UpdateSystem", function(_, systemFrame)
    if systemFrame == DamageMeter then
        C_Timer.After(0, function()   -- taint from this call chain baked in
            DoSomeWork()
        end)
    end
end)
```

**Safe pattern — flag + OnUpdate poller:**
```lua
-- Only flip a flag inside the hook (boolean assignment doesn't spread taint)
local pendingWork = false
hooksecurefunc(EditModeManagerFrame, "UpdateSystem", function(_, systemFrame)
    if systemFrame == DamageMeter then
        pendingWork = true   -- safe: no C_Timer, no closures created here
    end
end)

-- Separate OnUpdate handler — C++ game loop provides a fresh call origin,
-- breaking the taint chain from the hook above.
local poller = CreateFrame("Frame")
poller:SetScript("OnUpdate", function()
    if not pendingWork then return end
    pendingWork = false
    DoSomeWork()   -- now executes outside the tainted hook call chain
end)
```

The `OnUpdate` script fires from the C++ game loop's own call origin, not from
the tainted hook's call chain. Even though addon `OnUpdate` handlers are always
tainted code, the *execution context* is a fresh one — values it reads from
upvalues don't inherit the identity taint from the hook invocation that set the flag.

Never overwrite or shadow Blizzard globals. Use addon-namespaced tables.

---

## Debugging Taint

### `issecure()`

```lua
print(issecure())  -- false from any addon code (always)
```

Always returns `false` from addon code. Useful for verifying execution context in secure
snippets only.

### `issecurevariable("varName")`

```lua
local secure, tainted_by = issecurevariable("SomeGlobal")
-- secure: boolean
-- tainted_by: string name of the addon that tainted it (if any)
```

Use this to diagnose which addon tainted a global that's causing problems.

### Taint error messages

When a protected function is blocked by taint, WoW prints an error like:

```
Action blocked because of taint from <AddonName> - <function>
```

The error identifies the addon responsible. In our error messages, it will say `EnhancedInterface`.

---

## Relevance to EnhancedInterface

### Current code — what we're doing right

| Module | Pattern | Why It's Safe |
|---|---|---|
| `NameplateScale` | `hooksecurefunc(NamePlateUnitFrameMixin, "ApplyFrameOptions", ...)` | Receives `self` cleanly from Blizzard's call; never queries the gated APIs directly |
| `FreeMove` | `if InCombatLockdown() then return end` guard | Prevents attempting protected frame moves in combat |
| All modules | Never touching Blizzard globals | No global pollution risk |

### Risk areas to watch

- **Hooking Blizzard event handlers** with `SetScript` instead of `HookScript` — replaces
  and destroys the original secure handler; use `HookScript` instead.
- **Parenting addon frames to protected frames** — the parent inherits lockdown restrictions;
  only parent to protected frames when intentionally creating a protected frame.
- **Anchoring to protected frames** — temporarily inherits combat lockdown restrictions on
  the anchored frame too.
- **Writing to shared globals** in response to events — if Blizzard code later reads that
  global, taint spreads.
- **Calling `C_Timer.After` inside a `hooksecurefunc` that may run in a tainted chain** —
  when another addon (e.g. `AccWideUILayoutSelection`) calls `C_EditMode.SetActiveLayout()`,
  our hooks on `EditModeManagerFrame:UpdateSystem` / `ApplyLayoutToFrame` fire in that
  tainted context. Any `C_Timer.After` closure created there bakes in the taint and
  spreads it on deferred execution. Use the **flag + OnUpdate poller** pattern instead
  (see Safe Pattern #5 above).

---

## Quick Reference

| Task | Safe Approach |
|---|---|
| Observe a Blizzard function call | `hooksecurefunc` |
| Observe a frame's script event | `frame:HookScript(...)` |
| Modify a protected frame | Only outside combat; check `InCombatLockdown()` |
| Access a frame gated by `AllowedWhenUntainted` | Use a hook that receives the frame as an argument |
| Debug which addon caused taint | `issecurevariable("globalName")` |
| Check if execution is secure | `issecure()` (only meaningful in Blizzard code) |

---

## References

- [Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)
- [hooksecurefunc](https://warcraft.wiki.gg/wiki/API_hooksecurefunc)
- [InCombatLockdown](https://warcraft.wiki.gg/wiki/API_InCombatLockdown)
- [issecure](https://warcraft.wiki.gg/wiki/API_issecure)
- [SecureTemplates](https://warcraft.wiki.gg/wiki/SecureTemplates)
- [Protected Functions category](https://warcraft.wiki.gg/wiki/Category:World_of_Warcraft_API/Protected_Functions)
