## [0.2.0] - 2026-04-15

### Changes
- Add text shadow to power display number
- Add power value number display

### Fixes
- No longer force Personal Resource Display to be shown, if the user has disabled it in the WoW Settings
- Fixed several taint errors.


## [0.1.4]

### Fixes
- avoid tainted GetHeight() in DamageMeterEmbed SetHeightModifier call
- eliminate taint source in DamageMeterEmbed causing QuestMapFrame errors

## [0.1.0]

### Changes
- Simplify power bar border handling and add top border texture
- Add 'Hide when mounted' option to Personal Resource Display settings
- Add event handling for combat session updates and player regen

## [0.0.1]

### Changes
- Companion dialog for Edit Mode UIToolbox settings
- Granular PRD settings with reliable state restoration
- Hide runes, holypower, etc when PRD is shown
- Inject sharedbars into editmode
- Persist SharedBars edits and fix mount restore
- Personal resource display
- Improve damage meter space usage
- Damage meter objective section
- Custom objectives section
- Collapsible sections
- Nameplate size slider
- More toggle customization options

### Fixes
- Objectives don't collapse when entering delve
- Error when flying over worldquest area
- Jumping damage meter frame
- Lua error
