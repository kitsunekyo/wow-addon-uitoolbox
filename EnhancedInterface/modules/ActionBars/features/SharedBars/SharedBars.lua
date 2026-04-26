-- EnhancedInterface
-- modules/ActionBars/features/SharedBars/SharedBars.lua
--
-- Shared Action Bars: keeps selected action bars identical across all talent
-- loadouts / specs.
--
-- When a bar is enabled, a snapshot of its current button assignments is saved
-- to EnhancedInterfaceDB. On every loadout switch, all enabled bars are restored from
-- their snapshots after a short defer to let WoW finish applying the loadout.
--
-- ── Trigger detection ──────────────────────────────────────────────────────────
--
-- SELECTED_LOADOUT_CHANGED never fires (broken since 10.0.7).
-- hooksecurefunc(C_ClassTalents, "LoadConfig") does NOT work — C namespace
-- table functions are C-implemented and cannot be hooked via hooksecurefunc.
--
-- Working approach:
--   • PLAYER_TALENT_UPDATE fires on spec changes (NOT on within-spec loadout
--     switches). Skip the first fire (login baseline).
--   • TRAIT_CONFIG_UPDATED fires on loadout switches AND on talent node spends.
--     To distinguish a loadout switch from a node spend, we compare
--     C_ClassTalents.GetLastSelectedSavedConfigID() before and after:
--     if the saved config ID changed, it was a loadout switch; restore.
--   Both events can fire together on a spec change, so TriggerRestore is
--   debounced — multiple calls within the same frame only schedule one restore.
--
-- ── Live editing ───────────────────────────────────────────────────────────────
--
-- ACTIONBAR_SLOT_CHANGED fires whenever the player adds, removes, or moves an
-- action on any bar (arg1 = 1-based slot number).  When the changed slot belongs
-- to an enabled shared bar we re-snapshot that bar so the edit is persisted and
-- survives the next loadout/spec switch.
--
-- Snapshots are suppressed while RestoreBar is running (the pickup/place calls
-- inside RestoreBar also fire ACTION_BAR_SLOT_CHANGED; we must not let those
-- clobber the snapshot with the spec-specific layout we are replacing).
--
-- ── Mount handling ─────────────────────────────────────────────────────────────
--
-- GetActionInfo returns type="summonmount", id=mountActionID (opaque, not a
-- spellID). C_Spell.PickupSpell(mountActionID) does NOT work.
-- Correct path:
--   Snapshot: C_ActionBar.GetSpell(slot) → spellID (stable mount summon spell)
--   Restore:  PickupMountBySpellID(spellID) — iterates C_MountJournal.GetMountIDs()
--             to find the mount by spellID, then calls C_MountJournal.Pickup(idx).
--             C_Spell.PickupSpell does not work for mounts in current retail.
--   Special:  mountActionID == 268435455 → "Summon Random Favorite Mount"
--             → store spellID=0, restore with C_MountJournal.Pickup(0)
--
-- ── Macro handling ─────────────────────────────────────────────────────────────
--
-- GetActionInfo returns type="macro", id=macroIndex. Macro indices can shift
-- across spec switches (character-specific macro slots). We snapshot the macro
-- name instead and restore via PickupMacro(name), which is stable.
--
-- ── Combat guard ───────────────────────────────────────────────────────────────
--
-- PickupAction / PlaceAction are #nocombat restricted. Deferred to
-- PLAYER_REGEN_ENABLED if InCombatLockdown() is true when restore fires.
--
-- Supported action types: spell, summonmount, item, macro, equipmentset,
-- companion, flyout.  flyout is restored by scanning the spellbook for a
-- matching FLYOUT entry and calling PickupSpellBookItem.

local SharedBars = {}
EnhancedInterface.SharedBars = SharedBars

-- ── Bar definitions ────────────────────────────────────────────────────────────
-- Keys are WoW Action Bar numbers (1–8). Bar 1 has two pages; the second page
-- is stored under the synthetic key 10 (i.e. "Bar 1, Page 2").
-- Slot ranges per warcraft.wiki.gg/wiki/Action_slot:
--   Bar 1 page 1 : 1–12    (ActionButton)
--   Bar 1 page 2 : 13–24   (ActionButton, page 2)
--   Bar 2        : 61–72   (MultiBarBottomLeft)
--   Bar 3        : 49–60   (MultiBarBottomRight)
--   Bar 4        : 25–36   (MultiBarRight)
--   Bar 5        : 37–48   (MultiBarLeft)
--   Bar 6        : 145–156 (MultiBar5)
--   Bar 7        : 157–168 (MultiBar6)
--   Bar 8        : 169–180 (MultiBar7)

local BAR_SLOTS = {
    [1]  = 1,    -- Action Bar 1 (Page 1)
    [10] = 13,   -- Action Bar 1 (Page 2)  synthetic key, never shown as "Bar 10"
    [2]  = 61,   -- Action Bar 2
    [3]  = 49,   -- Action Bar 3
    [4]  = 25,   -- Action Bar 4
    [5]  = 37,   -- Action Bar 5
    [6]  = 145,  -- Action Bar 6
    [7]  = 157,  -- Action Bar 7
    [8]  = 169,  -- Action Bar 8
}

local BAR_COUNT = 12  -- buttons per bar

-- Opaque mountActionID returned by GetActionInfo for "Summon Random Favorite Mount".
local RANDOM_FAVORITE_MOUNT_ACTION_ID = 268435455

-- ── Slot → bar reverse lookup ──────────────────────────────────────────────────
-- Built once from BAR_SLOTS so we can map any slot number back to a barIndex
-- in O(1) instead of scanning all bars on every ACTION_BAR_SLOT_CHANGED.

local SLOT_TO_BAR = {}  -- [slotNumber] = barIndex
for barIndex, firstSlot in pairs(BAR_SLOTS) do
    for i = 0, BAR_COUNT - 1 do
        SLOT_TO_BAR[firstSlot + i] = barIndex
    end
end

-- ── State ──────────────────────────────────────────────────────────────────────

local pendingRestore    = false  -- true when a restore was deferred due to combat
local restorePending    = false  -- debounce flag for TriggerRestore
local restoringBars     = false  -- true while RestoreBar is running; suppresses snapshot-on-change
local pendingSnapshots  = {}     -- barIndex → true; set by debounce, cleared by timer

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GetDB()
    return EnhancedInterface.db.sharedBars
end

-- Ensure the bar entry exists in db.
local function EnsureBarEntry(barIndex)
    local db = GetDB()
    if not db.bars[barIndex] then
        db.bars[barIndex] = { enabled = false, slots = {} }
    end
end

-- Returns the first slot number for a bar, or nil for an invalid index.
local function GetFirstSlot(barIndex)
    return BAR_SLOTS[barIndex]
end

-- Pick up a mount onto the cursor by its spellID, ready to be placed on an
-- action bar slot.  Uses C_MountJournal.Pickup which is the only API that
-- correctly places a mount on an action button.
--
-- C_MountJournal.Pickup takes a displayIndex — the 1-based index into the
-- currently displayed (filtered) mount list, NOT into GetMountIDs().
-- To guarantee the mount is visible we temporarily reset journal filters,
-- find the mount by mountID in the displayed list, pick it up, then restore
-- the previous search text and filters.
--
-- Returns true if the mount was found and picked up.
local function PickupMountBySpellID(spellID)
    -- First find the mountID for this spellID.
    local targetMountID
    for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
        local _, mSpellID, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if isCollected and mSpellID == spellID then
            targetMountID = mountID
            break
        end
    end
    if not targetMountID then return false end

    -- Save current search text and reset filters so every collected mount shows.
    local savedSearch = C_MountJournal.GetSearch and C_MountJournal.GetSearch() or ""
    C_MountJournal.SetDefaultFilters()
    C_MountJournal.SetSearch("")

    -- Find the display index for our mount.
    local displayIndex
    local numDisplayed = C_MountJournal.GetNumDisplayedMounts()
    for i = 1, numDisplayed do
        local _, _, _, _, _, _, _, _, _, _, _, mID = C_MountJournal.GetDisplayedMountInfo(i)
        if mID == targetMountID then
            displayIndex = i
            break
        end
    end

    -- Restore previous search (filters were reset to default; that's acceptable).
    C_MountJournal.SetSearch(savedSearch)

    if not displayIndex then return false end
    C_MountJournal.Pickup(displayIndex)
    return true
end

-- Pick up a flyout onto the cursor by its flyoutID, ready to be placed on an
-- action bar slot.  Scans the player spellbook and pet spellbook using the
-- modern C_SpellBook API (added 11.0.0; replaces the removed GetNumSpellTabs /
-- GetSpellTabInfo / GetSpellBookItemInfo / PickupSpellBookItem globals).
--
-- For each skill line, iterates every spellbook slot looking for an entry of
-- type Enum.SpellBookItemType.Flyout whose actionID matches the target flyoutID.
-- When found, calls C_SpellBook.PickupSpellBookItem to put it on the cursor.
--
-- Returns true if the flyout was found and picked up.
local function PickupFlyoutByID(flyoutID)
    local bankTypes = { Enum.SpellBookSpellBank.Player, Enum.SpellBookSpellBank.Pet }
    for _, bankType in ipairs(bankTypes) do
        local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
        for i = 1, numSkillLines do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if info then
                for j = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local itemType, actionID = C_SpellBook.GetSpellBookItemType(j, bankType)
                    if itemType == Enum.SpellBookItemType.Flyout and actionID == flyoutID then
                        C_SpellBook.PickupSpellBookItem(j, bankType)
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Returns true if the live contents of `slot` already match the saved `record`.
-- Used by RestoreBar to skip pickup/place churn on slots that don't need to
-- change.  Avoiding spurious writes to Action Bar 1 in particular prevents
-- side effects on Blizzard's MainMenuBarArtFrame (gryphon art) which can
-- otherwise re-show despite the "Hide Bar Art" Edit Mode setting.
--
-- Both arguments may be nil-ish:
--   record == nil  → caller treats slot as "should be empty"
--   live  == nil   → slot is currently empty
local function SlotMatchesRecord(slot, record)
    local liveType, liveID, liveSubType = GetActionInfo(slot)

    -- Both empty → match.
    if not record then
        return liveType == nil
    end

    -- Record present but slot empty → mismatch.
    if not liveType then
        return false
    end

    -- Type must match for everything below.
    if liveType ~= record.type then
        return false
    end

    if record.type == "spell"
    or record.type == "item"
    or record.type == "equipmentset"
    or record.type == "flyout" then
        return liveID == record.id

    elseif record.type == "companion" then
        return liveID == record.id and liveSubType == record.subType

    elseif record.type == "macro" then
        -- record.id stores the macro name; live id is the macro index.
        local liveName = GetMacroInfo(liveID)
        return liveName == record.id

    elseif record.type == "summonmount" then
        -- record.id == 0 means "Summon Random Favorite Mount" (opaque action id).
        if record.id == 0 then
            return liveID == RANDOM_FAVORITE_MOUNT_ACTION_ID
        end
        -- Otherwise compare the stable mount summon spellID.
        local liveSpellID = C_ActionBar.GetSpell(slot)
        return liveSpellID == record.id
    end

    return false
end

-- Pickup the correct cursor item for a saved slot record.
-- Returns true if a pickup was attempted (cursor state determines success).
local function PickupSavedAction(record)
    if not record then return false end

    local actionType = record.type
    local id         = record.id
    local subType    = record.subType

    if actionType == "spell" then
        C_Spell.PickupSpell(id)
        return true
    elseif actionType == "summonmount" then
        -- id == 0: random favorite mount.
        -- id > 0: spellID of the specific mount summon spell (from C_ActionBar.GetSpell).
        --         C_Spell.PickupSpell does not work for mounts in current retail;
        --         use PickupMountBySpellID which goes through C_MountJournal.Pickup.
        if id == 0 then
            C_MountJournal.Pickup(0)
            return true
        end
        return PickupMountBySpellID(id)
    elseif actionType == "item" then
        PickupItem(id)
        return true
    elseif actionType == "macro" then
        -- id is the macro name (snapshotted as name for stability across specs).
        PickupMacro(id)
        return true
    elseif actionType == "equipmentset" then
        PickupEquipmentSet(id)
        return true
    elseif actionType == "companion" then
        -- subType is "MOUNT" or "CRITTER"; id is the companion index.
        PickupCompanion(subType, id)
        return true
    elseif actionType == "flyout" then
        -- id is the flyoutID from GetActionInfo. Locate the matching spellbook
        -- entry and pick it up from there (no direct PickupFlyout API exists).
        return PickupFlyoutByID(id)
    end

    return false
end

-- ── Public API ─────────────────────────────────────────────────────────────────

-- Snapshot the current live state of a bar into the DB.
-- Safe to call at any time (GetActionInfo is never restricted).
function SharedBars:SnapshotBar(barIndex)
    local firstSlot = GetFirstSlot(barIndex)
    if not firstSlot then return end

    EnsureBarEntry(barIndex)

    local slots = {}
    for i = 0, BAR_COUNT - 1 do
        local slot = firstSlot + i
        local actionType, id, subType = GetActionInfo(slot)
        if actionType and id then
            if actionType == "spell"
            or actionType == "item"
            or actionType == "equipmentset"
            or actionType == "companion" then
                slots[i + 1] = { type = actionType, id = id, subType = subType }

            elseif actionType == "macro" then
                -- Store name instead of index — names are stable across spec switches.
                local name = GetMacroInfo(id)
                if name then
                    slots[i + 1] = { type = "macro", id = name }
                end

            elseif actionType == "summonmount" then
                -- Store the stable mount summon spellID via C_ActionBar.GetSpell.
                -- mountActionID from GetActionInfo is opaque and not usable directly.
                if id == RANDOM_FAVORITE_MOUNT_ACTION_ID then
                    slots[i + 1] = { type = "summonmount", id = 0 }
                else
                    local spellID = C_ActionBar.GetSpell(slot)
                    if spellID then
                        slots[i + 1] = { type = "summonmount", id = spellID }
                    end
                end

            elseif actionType == "flyout" then
                -- id is the flyoutID — a stable server-defined identifier for the
                -- flyout definition (e.g. Skyriding, Warbands, Hero's Path).
                -- Restored via PickupFlyoutByID which scans the spellbook.
                slots[i + 1] = { type = "flyout", id = id }
            -- else: unknown types are intentionally skipped.
            end
        end
    end

    GetDB().bars[barIndex].slots = slots
end

-- Restore all 12 slots of a bar from the DB snapshot.
-- Must NOT be called while InCombatLockdown() is true.
--
-- Diff-before-restore: each slot is compared against the snapshot via
-- SlotMatchesRecord and skipped entirely when already in sync.  This avoids
-- spurious PickupAction/PlaceAction churn — most loadout switches leave the
-- shared bar untouched, so restore becomes a near-no-op.  Reducing writes to
-- Action Bar 1 in particular prevents collateral damage to Blizzard's
-- MainMenuBarArtFrame state (the "Hide Bar Art" Edit Mode setting can
-- otherwise be silently undone by rapid bar mutations during loadout swaps).
function SharedBars:RestoreBar(barIndex)
    local firstSlot = GetFirstSlot(barIndex)
    if not firstSlot then return end

    local db    = GetDB()
    local entry = db.bars[barIndex]
    if not entry or not entry.slots then return end

    for i = 1, BAR_COUNT do
        local slot   = firstSlot + (i - 1)
        local record = entry.slots[i]

        -- Skip slots that already match the snapshot — no pickup, no place,
        -- no clear.  This is the common case on loadout switches.
        if not SlotMatchesRecord(slot, record) then
            -- Clear the slot first regardless (removes actions not in snapshot).
            ClearCursor()
            PickupAction(slot)   -- picks up whatever is there (or is a no-op if empty)
            ClearCursor()        -- drop it to effectively clear the slot

            if record then
                ClearCursor()
                if PickupSavedAction(record) then
                    local cursorType = GetCursorInfo()
                    if cursorType then
                        PlaceAction(slot)
                        ClearCursor()
                    end
                end
            end
        end
    end
end

-- Enable shared mode for a bar and immediately snapshot its current state.
function SharedBars:EnableBar(barIndex)
    if not GetFirstSlot(barIndex) then return end
    EnsureBarEntry(barIndex)
    GetDB().bars[barIndex].enabled = true
    self:SnapshotBar(barIndex)
end

-- Disable shared mode for a bar.  The snapshot is kept but no longer applied.
function SharedBars:DisableBar(barIndex)
    if not GetFirstSlot(barIndex) then return end
    EnsureBarEntry(barIndex)
    GetDB().bars[barIndex].enabled = false
end

-- Restore all enabled bars.  Defers if in combat.
-- restoringBars is expected to be true when called from TriggerRestore.
-- It is cleared here after all bars are restored so live-edit snapshots
-- are re-enabled once we are done writing to the slots.
function SharedBars:RestoreAllEnabled()
    if InCombatLockdown() then
        pendingRestore = true
        return
    end

    local db = GetDB()
    for barIndex in pairs(BAR_SLOTS) do
        local entry = db.bars[barIndex]
        if entry and entry.enabled then
            self:RestoreBar(barIndex)
        end
    end

    restoringBars = false
end

-- ── Event handling ────────────────────────────────────────────────────────────
--
-- Three triggers:
--
-- 1. PLAYER_TALENT_UPDATE — fires on spec changes. Skip first fire (login).
--    Updates cached config ID so TRAIT_CONFIG_UPDATED doesn't double-fire.
--
-- 2. TRAIT_CONFIG_UPDATED — fires on loadout switches AND talent node spends.
--    Only acts if the saved config ID changed (= loadout switch).
--
-- 3. ACTIONBAR_SLOT_CHANGED — fires whenever the player edits any slot (add,
--    remove, move). If the changed slot belongs to an enabled shared bar we
--    re-snapshot that bar so the edit is persisted and survives the next
--    loadout/spec switch. Suppressed while RestoreBar is running.
--
-- Both PLAYER_TALENT_UPDATE and TRAIT_CONFIG_UPDATED can fire together on a
-- spec change, so TriggerRestore is debounced: multiple calls within the same
-- frame schedule only one 0.5s restore timer.

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

local baselineSet       = false  -- guards the first PLAYER_TALENT_UPDATE on login
local lastSavedConfigID = nil    -- last known saved loadout config ID

-- Timestamps (GetTime() targets) for deferred work, set by TriggerRestore and
-- TriggerSnapshotBar and consumed by the OnUpdate handler below.
--
-- TAINT HAZARD: PLAYER_TALENT_UPDATE and TRAIT_CONFIG_UPDATED can fire inside a
-- call chain tainted by another addon (e.g. a talent UI addon during a loadout
-- switch).  C_Timer.After closures created in those contexts bake in the tainted
-- execution context permanently.  When the closure fires, it calls
-- RestoreAllEnabled() or SnapshotBar() from that tainted context, which can
-- propagate taint through PickupAction/PlaceAction into Blizzard's action bar
-- secure handling.
-- Fix: store only a plain number (GetTime() + delay) in an upvalue — no closure
-- is created.  The OnUpdate handler fires from the C++ game loop (clean context)
-- and does the actual work there.
--
-- Note: GetTime() called from a tainted context returns a tainted number, but
-- that number is only compared to another GetTime() call inside OnUpdate (also
-- from the clean C++ game loop context) — never written to a Blizzard frame
-- property.  The arithmetic stays inside addon-owned upvalues, so taint does
-- not escape into Blizzard's secure execution paths.
local pendingRestoreAt   = nil  -- GetTime() target for deferred restore, or nil
local pendingSnapshotsAt = {}   -- barIndex → GetTime() target for deferred snapshot

-- Returns the currently-selected saved config ID for the active spec, or nil.
local function GetCurrentSavedConfigID()
    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return nil end
    return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

-- Schedule a deferred restore (0.5s lets WoW finish applying the loadout).
-- Debounced: multiple calls before the timer fires only schedule one restore.
-- Also sets restoringBars immediately so that ACTION_BAR_SLOT_CHANGED events
-- fired by WoW while it rewrites bars for the new spec/loadout don't corrupt
-- the stored snapshot before we get a chance to restore it.
local function TriggerRestore()
    if restorePending then return end
    restorePending   = true
    restoringBars    = true
    pendingRestoreAt = GetTime() + 0.5
end

-- Debounced re-snapshot for a single bar after a live edit.
-- Uses a 0.1s defer so that rapid multi-slot operations (e.g. drag-swap
-- between two slots on the same bar) only generate one snapshot write.
local function TriggerSnapshotBar(barIndex)
    if pendingSnapshotsAt[barIndex] then return end
    pendingSnapshots[barIndex]   = true
    pendingSnapshotsAt[barIndex] = GetTime() + 0.1
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "TRAIT_CONFIG_UPDATED" then
        -- Fires for loadout switches AND node spends. Only act on a loadout
        -- switch, detected by a change in the saved config ID.
        local currentID = GetCurrentSavedConfigID()
        if currentID ~= lastSavedConfigID then
            lastSavedConfigID = currentID
            TriggerRestore()
        end

    elseif event == "PLAYER_TALENT_UPDATE" then
        -- Fires on spec changes. Skip the first fire (login baseline).
        if not baselineSet then
            baselineSet = true
            lastSavedConfigID = GetCurrentSavedConfigID()
            return
        end
        -- Spec change: resync the cached config ID (so TRAIT_CONFIG_UPDATED
        -- doesn't also trigger) and restore.
        lastSavedConfigID = GetCurrentSavedConfigID()
        TriggerRestore()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRestore then
            pendingRestore = false
            restoringBars  = true
            SharedBars:RestoreAllEnabled()
        end

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        -- Suppress during restore to avoid overwriting the snapshot with the
        -- spec-specific layout we are in the process of replacing.
        if restoringBars then return end

        local slot     = ...
        local barIndex = SLOT_TO_BAR[slot]
        if not barIndex then return end

        local db    = GetDB()
        local entry = db.bars[barIndex]
        if not (entry and entry.enabled) then return end

        TriggerSnapshotBar(barIndex)
    end
end)

-- OnUpdate: consume pendingRestoreAt and pendingSnapshotsAt timestamps set by
-- TriggerRestore / TriggerSnapshotBar.  Fires from the C++ game loop (clean
-- execution context), so RestoreAllEnabled() and SnapshotBar() run untainted
-- regardless of what execution context originally called TriggerRestore/
-- TriggerSnapshotBar.
frame:SetScript("OnUpdate", function()
    local now = GetTime()

    if pendingRestoreAt and now >= pendingRestoreAt then
        pendingRestoreAt = nil
        restorePending   = false
        SharedBars:RestoreAllEnabled()
    end

    for barIndex, fireAt in pairs(pendingSnapshotsAt) do
        if now >= fireAt then
            pendingSnapshotsAt[barIndex] = nil
            pendingSnapshots[barIndex]   = nil
            -- Re-check: bar may have been disabled between the edit and now.
            local db    = GetDB()
            local entry = db.bars[barIndex]
            if entry and entry.enabled then
                SharedBars:SnapshotBar(barIndex)
            end
        end
    end
end)
