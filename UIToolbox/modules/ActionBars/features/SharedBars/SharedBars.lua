-- UIToolbox
-- modules/ActionBars/features/SharedBars/SharedBars.lua
--
-- Shared Action Bars: keeps selected action bars identical across all talent
-- loadouts / specs.
--
-- When a bar is enabled, a snapshot of its current button assignments is saved
-- to UIToolboxDB. On every loadout switch, all enabled bars are restored from
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
-- ── Mount handling ─────────────────────────────────────────────────────────────
--
-- GetActionInfo returns type="summonmount", id=mountActionID (opaque, not a
-- spellID). C_Spell.PickupSpell(mountActionID) does NOT work.
-- Correct path:
--   Snapshot: C_ActionBar.GetSpell(slot) → spellID (stable mount summon spell)
--   Restore:  C_Spell.PickupSpell(spellID) — mount spells are regular spells
--             and can be placed on action bars exactly like other spells.
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
-- companion.  flyout is skipped (no safe pickup API).

local SharedBars = {}
UIToolbox.SharedBars = SharedBars

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

-- ── State ──────────────────────────────────────────────────────────────────────

local pendingRestore  = false  -- true when a restore was deferred due to combat
local restorePending  = false  -- debounce flag for TriggerRestore

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function GetDB()
    return UIToolbox.db.sharedBars
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
        -- id is a stable mount spell ID (0 = random favorite).
        if id == 0 then
            C_MountJournal.Pickup(0)
            return true
        end
        C_Spell.PickupSpell(id)
        return true
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
            -- else: "flyout" and unknown types are intentionally skipped.
            end
        end
    end

    GetDB().bars[barIndex].slots = slots
end

-- Restore all 12 slots of a bar from the DB snapshot.
-- Must NOT be called while InCombatLockdown() is true.
function SharedBars:RestoreBar(barIndex)
    local firstSlot = GetFirstSlot(barIndex)
    if not firstSlot then return end

    local db    = GetDB()
    local entry = db.bars[barIndex]
    if not entry or not entry.slots then return end

    for i = 1, BAR_COUNT do
        local slot   = firstSlot + (i - 1)
        local record = entry.slots[i]

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
end

-- ── Event handling ────────────────────────────────────────────────────────────
--
-- Two triggers:
--
-- 1. PLAYER_TALENT_UPDATE — fires on spec changes. Skip first fire (login).
--    Updates cached config ID so TRAIT_CONFIG_UPDATED doesn't double-fire.
--
-- 2. TRAIT_CONFIG_UPDATED — fires on loadout switches AND talent node spends.
--    Only acts if the saved config ID changed (= loadout switch).
--
-- Both events fire together on spec changes, so TriggerRestore is debounced:
-- multiple calls within the same frame schedule only one 0.5s restore timer.

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

local baselineSet       = false  -- guards the first PLAYER_TALENT_UPDATE on login
local lastSavedConfigID = nil    -- last known saved loadout config ID

-- Returns the currently-selected saved config ID for the active spec, or nil.
local function GetCurrentSavedConfigID()
    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return nil end
    return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

-- Schedule a deferred restore (0.5s lets WoW finish applying the loadout).
-- Debounced: multiple calls before the timer fires only schedule one restore.
local function TriggerRestore()
    if restorePending then return end
    restorePending = true
    C_Timer.After(0.5, function()
        restorePending = false
        SharedBars:RestoreAllEnabled()
    end)
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
            SharedBars:RestoreAllEnabled()
        end
    end
end)
