# UIToolbox

A personal World of Warcraft addon that improves the default UI with a collection of focused quality-of-life tools.

Built for WoW retail (Midnight, Interface version 120001).

## Features

### Tracker Collapse

Automatically collapses Objective Tracker sections when entering any instance (dungeon, raid, PvP, arena, scenario), and restores them to their previous state when you leave.

**Sections managed:**
- Campaign
- Quests
- World Quests

**Behavior:**
- On instance entry: snapshots the current collapse state of each section, then collapses the enabled ones.
- On instance exit: restores each section exactly as it was before you entered.
- Configurable per-section via `UIToolboxDB.trackerCollapse.sections`.

## Development

### File structure

```
UIToolbox/
├── UIToolbox.toc               TOC file (Interface version, dependencies, file list)
├── Core.lua                    Addon init, SavedVariables, module registry, event dispatch
└── Modules/
    └── TrackerCollapse.lua     Auto-collapse tracker sections on instance entry
sync.sh                         Copies UIToolbox/ to the WoW AddOns folder
```

### Iteration loop

1. Make changes to files in `UIToolbox/`
2. Run `./sync.sh` from WSL to copy files to the WoW AddOns directory
3. Type `/reload` in WoW to reload the UI

### Debugging in-game

| Command | Purpose |
|---|---|
| `/etrace` | Event trace — confirm events are firing |
| `/framestack` | Hover over frames to inspect their names |
| `/dump UIToolboxDB` | Inspect current SavedVariables state |
| `/reload` | Reload the UI after syncing new files |

### SavedVariables structure

```lua
UIToolboxDB = {
    trackerCollapse = {
        enabled = true,
        sections = {
            campaign    = true,
            quests      = true,
            worldQuests = true,
        },
    },
}
```

To temporarily disable the feature in-game:

```lua
/run UIToolbox.db.trackerCollapse.enabled = false
```

## Dependencies

- `Blizzard_ObjectiveTracker` (built-in Blizzard addon, always present in retail)
