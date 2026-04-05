# Enhanced Interface - World of Warcraft Addon

You are a Lua addon author for World of Warcraft (retail only — latest version). Write clean, performant code that integrates naturally into the WoW UI using existing Blizzard assets and templates.

## Project Structure

The addon lives under `EnhancedInterface/`:

```
EnhancedInterface/
  EnhancedInterface.toc   # load order and metadata
  Core.lua                # addon init, SavedVariables (EnhancedInterfaceDB), event dispatch, module registry
  Settings.lua            # WoW Settings UI panel registration
  modules/                # self-contained feature modules, grouped by UI area
    ActionBars/
      features/
        SharedBars/               # shared action bar slots across characters
        EditModeIntegration/
    Nameplates/
      features/
        NameplateScale/           # fine-tune nameplate scale factor
    ObjectivesTracker/
      features/
        AutoCollapse/             # auto-collapse tracker sections by zone
        DamageMeterEmbed/         # embed damage meter into the objectives tracker
        EditModeIntegration/
    PersonalResourceDisplay/
      features/
        BarStyling/               # restyle/hide PRD bars
        EditModeIntegration/
  shared/                 # utilities reused across multiple modules
    EditModeCompanionDialog/      # dialog that accompanies Edit Mode for injected buttons
```

**Conventions:**
- `Core.lua` exposes the global `EnhancedInterface` frame. All settings live on `EnhancedInterface.db` (backed by `EnhancedInterfaceDB` SavedVariablesPerCharacter).
- Each feature is a single `.lua` file (sometimes paired with an `EditModeIntegration.lua`). New features follow the same pattern: one file per feature under `modules/<Area>/features/<FeatureName>/`.
- After adding a new file, register it in `EnhancedInterface.toc`.

## Development Environment

### MANDATORY: Where to edit files

> **All development MUST be done inside the WSL2 Arch Linux workspace.**
> **NEVER directly edit or write files anywhere under `/mnt/c/...` on the Windows host.**

The canonical source of truth is the WSL2 workspace:
```
/home/aspieslechner/agent-workspaces/wow-addon/
```

### MANDATORY: Deploying changes

> **After every completed change, run `sync.sh` to deploy the addon to WoW.**

```bash
bash /home/aspieslechner/agent-workspaces/wow-addon/sync.sh
```

After syncing, the user must type `/reload` in WoW to pick up the changes.

## Knowledge Base

Reference documents accumulated during development. Consult these before researching topics they cover.

- [Attaching Buttons to Blizzard Frames](knowledge/attaching-buttons-to-blizzard-frames.md) — how to inject custom buttons into Blizzard frames, atlas texture usage, accessing frame children, idempotency, and hooking late-created windows
- [Edit Mode and Injected Buttons](knowledge/edit-mode-and-injected-buttons.md) — how Edit Mode dragging affects injected buttons, primary vs secondary damage meter windows, `ApplyLayoutToFrame` hook pattern
- [Taint and Secure Execution](knowledge/taint-and-secure-execution.md) — how taint spreads, protected functions, `hooksecurefunc` vs `HookScript`, combat lockdown guards, `AllowedWhenUntainted` APIs, debugging taint errors, and EnhancedInterface-specific risk areas
- [Tabs and Panels](knowledge/tabs-and-panels.md) — `PanelTabButtonTemplate`, `PanelTemplates_*` helpers, tab naming convention, scrollable panels, and `UIPanelScrollFrameTemplate`
- [Buttons and Interactions](knowledge/buttons-and-interactions.md) — button templates, click scripts, enable/disable, atlas textures, tooltip-on-hover pattern, context menus via `MenuUtil`, and combat lockdown notes
- [Custom Frames and Borders](knowledge/custom-frames-and-borders.md) — `BackdropTemplate`, `SetBackdrop`, pre-defined backdrop tables, standard frame templates, movable/resizable frames, frame strata, and saving position
- [Text and Form Elements](knowledge/text-and-form-elements.md) — `FontString` font objects and methods, `EditBox` (InputBoxTemplate), `CheckButton` (checkbox), `Slider` (UISliderTemplateWithLabels), and the modern `Menu`/`DropdownButton` system
