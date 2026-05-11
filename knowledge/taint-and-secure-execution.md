# Taint and Secure Execution

Source: [warcraft.wiki.gg — Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)

## Hard Rules

- Treat all addon Lua as tainted, including addon `OnUpdate`, addon `OnEvent`, hook callbacks, timer callbacks, menu callbacks, and mouse/key scripts.
- Do not treat deferral as a way to become secure. Deferral may avoid one call chain, but the deferred addon callback is still addon code.
- Never call frame-mutating APIs from `hooksecurefunc`, `HookScript`, `SetScript("OnEvent", ...)`, `OnClick`, `OnMouseDown`, `OnEnter`, `OnLeave`, menu callbacks, or timer callbacks when the target is Blizzard-managed or shared UI state.
- Avoid mutating Blizzard-managed frames, shared Blizzard font objects, global Blizzard tooltip state, or Blizzard layout tables from addon callbacks.
- If a change needs Blizzard-managed frame mutation, prefer a Blizzard-owned/settings-owned API path. If no clearly safe path exists, do not implement it without live taint testing.

Frame-mutating APIs include, but are not limited to: `SetHeight`, `SetWidth`, `SetSize`, `SetPoint`, `ClearAllPoints`, `SetScale`, `SetAlpha`, `Show`, `Hide`, `SetShown`, `SetFont`, `SetFontObject`, `SetText`, `SetTextColor`, `SetStatusBarTexture`, `SetTexture`, `SetAtlas`, `PixelUtil.*`, and `C_NamePlate.SetNamePlateSize`.

## Core Concepts

WoW runs Lua in two broad contexts:

- **Secure:** Blizzard signed FrameXML.
- **Tainted:** third-party addon code.

Taint can spread through values, table fields, globals, function closures, and frame/widget properties. If Blizzard secure code later reads tainted state and then performs protected work or arithmetic on secret values, errors can appear far away from the original addon write.

Common symptoms include:

- `attempt to perform arithmetic on local ... (a secret number value, while execution tainted by 'EnhancedInterface')`
- `attempt to perform string conversion on a secret string value`
- `ADDON_ACTION_BLOCKED` for protected frame or map/objective tracker operations

## High-Risk Areas In This Addon

- Personal Resource Display and nameplate code, because these are Blizzard-managed UI systems.
- Objective tracker code, because full tracker refreshes can cascade into protected WorldMap pin paths.
- Edit Mode integration, because layout application touches Blizzard-managed frame geometry.
- Tooltip and text code, because shared Blizzard tooltips and font objects are reused by unrelated Blizzard UI widgets.

## Hooks And Scripts

Use `hooksecurefunc` to observe Blizzard calls without replacing Blizzard functions, but do not mutate Blizzard-managed frames or shared UI state inside the hook callback.

Use `HookScript` instead of `SetScript` when adding behavior to existing Blizzard frames. Do not mutate Blizzard-managed frames or shared UI state inside the script callback.

Addon-created button scripts may update SavedVariables and addon-owned state. Do not use them to directly mutate Blizzard-managed frames or shared UI state.

## Timers And Deferral

Do not use `C_Timer.After` as a taint fix. A timer callback is still addon code, and closures created in tainted paths can carry taint forward.

Do not document or implement `C_Timer.After(0, function() ... protected or Blizzard-managed mutation ... end)` as a safe pattern.

## Tooltip Guidance

Avoid using the global `GameTooltip` from addon callbacks. Blizzard reuses `GameTooltip` for many secure UI paths, including map POI widget sets.

For addon-only hover help, use an addon-owned tooltip frame and keep it isolated from Blizzard tooltip state.

## Font And Text Guidance

Avoid dynamic `SetText`, `SetFont`, or `SetFontObject` on FontStrings that use shared Blizzard font objects from addon callbacks. Shared font metrics can be reused by unrelated Blizzard UI widgets.

If addon-owned dynamic text is required, use an addon-private font object and avoid wiring it into Blizzard-managed layout paths. Treat this as a risk area requiring live testing.

## Combat Lockdown

Combat lockdown is separate from taint. Guard protected frame operations with `InCombatLockdown()`, but remember that passing a combat guard does not make addon code secure.

Avoid calling full repaint/layout APIs such as `ObjectiveTrackerManager:UpdateAll()` during combat or from tainted addon callbacks unless a specific code path has been verified in game.

## Globals

Never overwrite or shadow Blizzard globals. Keep helper functions and state local or under the `EnhancedInterface` namespace.

## Debugging

- `issecure()` returns false from addon code and is only useful for confirming secure snippets.
- `issecurevariable("SomeGlobal")` can help identify tainted globals.
- Taint errors may surface in unrelated Blizzard files because Blizzard encountered tainted state later.

## References

- [Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)
- [hooksecurefunc](https://warcraft.wiki.gg/wiki/API_hooksecurefunc)
- [InCombatLockdown](https://warcraft.wiki.gg/wiki/API_InCombatLockdown)
- [issecure](https://warcraft.wiki.gg/wiki/API_issecure)
- [SecureTemplates](https://warcraft.wiki.gg/wiki/SecureTemplates)
