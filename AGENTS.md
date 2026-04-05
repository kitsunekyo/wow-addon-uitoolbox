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

### Version Bumps and Releases

To release a new version to CurseForge:

1. **Clean up old tags** (if necessary):
   ```bash
   # Delete incorrect tags locally
   git tag -d v0.1.1-release v0.1.2-release
   
   # Delete from remote (if already pushed)
   git push origin :refs/tags/v0.1.1-release :refs/tags/v0.1.2-release
   ```

2. **Run the version bump script**:
   ```bash
   ./version-bump.sh 0.1.2
   ```
   
   This script will:
   - Validate the version format (X.Y.Z)
   - Update `## Version:` in `EnhancedInterface.toc`
   - Generate changelog entries from git commits since the last tag
   - Categorize commits as: **Added** (feat:), **Fixed** (fix:), **Changed** (refactor:), **Documentation** (docs:)
   - Prepend the new section to `CHANGELOG.md` with the release date
   - Commit both files with message `chore: bump version to X.Y.Z`
   - Create a git tag `vX.Y.Z`

3. **Push to remote**:
   ```bash
   git push origin main --tags
   ```
   
   This triggers the CurseForge packager webhook, which packages only the `EnhancedInterface/` folder (as configured in `.curseforge`).

**Important:**
- Commit message format matters: use `feat:`, `fix:`, `refactor:`, and `docs:` prefixes to categorize changelog entries correctly.
- Always run `./version-bump.sh` before pushing to ensure consistency between version numbers and tags.
- The webhook requires the tag format `vX.Y.Z` (with `v` prefix) and will only package files within `EnhancedInterface/`.

## Knowledge Base

Reference documents accumulated during development. Consult these before researching topics they cover.

- [Attaching Buttons to Blizzard Frames](knowledge/attaching-buttons-to-blizzard-frames.md) — how to inject custom buttons into Blizzard frames, atlas texture usage, accessing frame children, idempotency, and hooking late-created windows
- [Edit Mode and Injected Buttons](knowledge/edit-mode-and-injected-buttons.md) — how Edit Mode dragging affects injected buttons, primary vs secondary damage meter windows, `ApplyLayoutToFrame` hook pattern
- [Taint and Secure Execution](knowledge/taint-and-secure-execution.md) — how taint spreads, protected functions, `hooksecurefunc` vs `HookScript`, combat lockdown guards, `AllowedWhenUntainted` APIs, debugging taint errors, and EnhancedInterface-specific risk areas
- [Tabs and Panels](knowledge/tabs-and-panels.md) — `PanelTabButtonTemplate`, `PanelTemplates_*` helpers, tab naming convention, scrollable panels, and `UIPanelScrollFrameTemplate`
- [Buttons and Interactions](knowledge/buttons-and-interactions.md) — button templates, click scripts, enable/disable, atlas textures, tooltip-on-hover pattern, context menus via `MenuUtil`, and combat lockdown notes
- [Custom Frames and Borders](knowledge/custom-frames-and-borders.md) — `BackdropTemplate`, `SetBackdrop`, pre-defined backdrop tables, standard frame templates, movable/resizable frames, frame strata, and saving position
- [Text and Form Elements](knowledge/text-and-form-elements.md) — `FontString` font objects and methods, `EditBox` (InputBoxTemplate), `CheckButton` (checkbox), `Slider` (UISliderTemplateWithLabels), and the modern `Menu`/`DropdownButton` system

## Tools

### Finding In-Game Textures

To browse available in-game textures and atlas entries for use in the addon, instruct the user to type `/tav` in the WoW chat to open the **TextureAtlasViewer** addon. This lets you search and preview atlas textures by name so you can pick appropriate assets before coding them in.

### Inspecting Frames and Events (DevTool)

When debugging UI layout, frame hierarchy, or event flow, instruct the user to use the **DevTool** addon (`/dev` to toggle its window). Key use cases:

- **Frame stack** — type `/fstack` in WoW chat to highlight the frame under the cursor and show its name/hierarchy. Use this to identify the exact frame name to hook into or parent against.
- **Event tracing** — type `/etrace` in WoW chat (or use DevTool's Events tab) to monitor fired events in real time. Use this to discover which events fire during a specific action so you know what to register for.
- **Inspecting tables/globals** — in the DevTool History tab, enter any fully-qualified global name (e.g. `PlayerFrame` or `UIParent`) to explore its fields and child frames interactively.
- **Logging function calls** — in the DevTool Fn Call Log tab, enter `<function> <parent>` to log calls, arguments, and return values at runtime.
- **Chat commands**: `/dev help` lists all available commands; `/dev <name>` adds a global to the inspector directly from chat.

Use DevTool whenever you need to identify frame names for injection, verify event names and payloads, or inspect the live state of any global table or frame.

## Resources

**official battle.net developer docs**

- [Guides](https://community.developer.battle.net/documentation/world-of-warcraft/guides)
- [Game Data APIs](https://community.developer.battle.net/documentation/world-of-warcraft/game-data-apis)
- [Profile APIs](https://community.developer.battle.net/documentation/world-of-warcraft/profile-apis)

**warcraft.wiki.gg**

- [World of Warcraft API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated)