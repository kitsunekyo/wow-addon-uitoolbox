## [0.1.4]

### Fixed
- avoid tainted GetHeight() in DamageMeterEmbed SetHeightModifier call
- eliminate taint source in DamageMeterEmbed causing QuestMapFrame errors

## [0.1.0]

### Added
- Simplify power bar border handling and add top border texture
- Add 'Hide when mounted' option to Personal Resource Display settings
- Add event handling for combat session updates and player regen

## [0.0.1]

### Added
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

### Fixed
- Objectives don't collapse when entering delve
- Error when flying over worldquest area
- Jumping damage meter frame
- Lua error
