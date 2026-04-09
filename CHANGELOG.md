## [0.1.4] - 2026-04-09### Fixed
- avoid tainted GetHeight() in DamageMeterEmbed SetHeightModifier call
- eliminate taint source in DamageMeterEmbed causing QuestMapFrame errors



### Documentation
- Update PRD screenshot

## [0.1.1] - 2024

### Changed
- Add deploy script

## [0.1.0] - 2024

### Added
- Simplify power bar border handling and add top border texture
- Add 'Hide when mounted' option to Personal Resource Display settings
- Add event handling for combat session updates and player regen

### Documentation
- Add development notes
- Add tools and resources
- Update readme
- Add screenshots
- Update agents file

## [0.0.1] - 2024

### Changed
- Move addon settings to Edit Mode companion panels
- Update addon settings category name to 'Enhanced Interface'
- Rename addon from UIToolbox to Enhanced Interface

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

### Changed
- Remove freemove global setting
- Switch from dropdown to button
- Move damage meter drag toggle into button
- New structure

### Fixed
- Objectives don't collapse when entering delve
- Error when flying over worldquest area
- Jumping damage meter frame
- Lua error

### Documentation
- Add knowledge files for tabs, buttons, frames, and form elements
- Add knowledge documentation
- Add custom textures documentation
- Add dev instructions
