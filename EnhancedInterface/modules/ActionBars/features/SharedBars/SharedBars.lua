local SharedBars = {}
EnhancedInterface.SharedBars = SharedBars

local BAR_SLOTS = {
    [1]  = 1,
    [10] = 13,
    [2]  = 61,
    [3]  = 49,
    [4]  = 25,
    [5]  = 37,
    [6]  = 145,
    [7]  = 157,
    [8]  = 169,
}

local BAR_COUNT = 12
local RANDOM_FAVORITE_MOUNT_ACTION_ID = 268435455

local SLOT_TO_BAR = {}
for barIndex, firstSlot in pairs(BAR_SLOTS) do
    for i = 0, BAR_COUNT - 1 do
        SLOT_TO_BAR[firstSlot + i] = barIndex
    end
end

local pendingRestore    = false
local restorePending    = false
local restoringBars     = false
local pendingSnapshots  = {}

local function GetDB()
    return EnhancedInterface.db.sharedBars
end

local function EnsureBarEntry(barIndex)
    local db = GetDB()
    if not db.bars[barIndex] then
        db.bars[barIndex] = { enabled = false, slots = {} }
    end
end

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
local function PickupMountBySpellID(spellID)
    local targetMountID
    for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
        local _, mSpellID, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if isCollected and mSpellID == spellID then
            targetMountID = mountID
            break
        end
    end
    if not targetMountID then return false end

    local savedSearch = C_MountJournal.GetSearch and C_MountJournal.GetSearch() or ""
    C_MountJournal.SetDefaultFilters()
    C_MountJournal.SetSearch("")

    local displayIndex
    local numDisplayed = C_MountJournal.GetNumDisplayedMounts()
    for i = 1, numDisplayed do
        local _, _, _, _, _, _, _, _, _, _, _, mID = C_MountJournal.GetDisplayedMountInfo(i)
        if mID == targetMountID then
            displayIndex = i
            break
        end
    end

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

local function SlotMatchesRecord(slot, record)
    local liveType, liveID, liveSubType = GetActionInfo(slot)

    if not record then
        return liveType == nil
    end

    if not liveType then
        return false
    end

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
        local liveName = GetMacroInfo(liveID)
        return liveName == record.id

    elseif record.type == "summonmount" then
        if record.id == 0 then
            return liveID == RANDOM_FAVORITE_MOUNT_ACTION_ID
        end
        local liveSpellID = C_ActionBar.GetSpell(slot)
        return liveSpellID == record.id
    end

    return false
end

local function PickupSavedAction(record)
    if not record then return false end

    local actionType = record.type
    local id         = record.id
    local subType    = record.subType

    if actionType == "spell" then
        C_Spell.PickupSpell(id)
        return true
    elseif actionType == "summonmount" then
        if id == 0 then
            C_MountJournal.Pickup(0)
            return true
        end
        return PickupMountBySpellID(id)
    elseif actionType == "item" then
        PickupItem(id)
        return true
    elseif actionType == "macro" then
        PickupMacro(id)
        return true
    elseif actionType == "equipmentset" then
        PickupEquipmentSet(id)
        return true
    elseif actionType == "companion" then
        PickupCompanion(subType, id)
        return true
    elseif actionType == "flyout" then
        return PickupFlyoutByID(id)
    end

    return false
end

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
                local name = GetMacroInfo(id)
                if name then
                    slots[i + 1] = { type = "macro", id = name }
                end

            elseif actionType == "summonmount" then
                -- GetActionInfo's mount id is opaque; store stable summon spellID instead.
                if id == RANDOM_FAVORITE_MOUNT_ACTION_ID then
                    slots[i + 1] = { type = "summonmount", id = 0 }
                else
                    local spellID = C_ActionBar.GetSpell(slot)
                    if spellID then
                        slots[i + 1] = { type = "summonmount", id = spellID }
                    end
                end

            elseif actionType == "flyout" then
                slots[i + 1] = { type = "flyout", id = id }
            end
        end
    end

    GetDB().bars[barIndex].slots = slots
end

function SharedBars:RestoreBar(barIndex)
    local firstSlot = GetFirstSlot(barIndex)
    if not firstSlot then return end

    local db    = GetDB()
    local entry = db.bars[barIndex]
    if not entry or not entry.slots then return end

    for i = 1, BAR_COUNT do
        local slot   = firstSlot + (i - 1)
        local record = entry.slots[i]

        if not SlotMatchesRecord(slot, record) then
            ClearCursor()
            PickupAction(slot)
            ClearCursor()

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

function SharedBars:EnableBar(barIndex)
    if not GetFirstSlot(barIndex) then return end
    EnsureBarEntry(barIndex)
    GetDB().bars[barIndex].enabled = true
    self:SnapshotBar(barIndex)
end

function SharedBars:DisableBar(barIndex)
    if not GetFirstSlot(barIndex) then return end
    EnsureBarEntry(barIndex)
    GetDB().bars[barIndex].enabled = false
end

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

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

local baselineSet       = false
local lastSavedConfigID = nil

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
local pendingRestoreAt   = nil
local pendingSnapshotsAt = {}

local function GetCurrentSavedConfigID()
    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return nil end
    return C_ClassTalents.GetLastSelectedSavedConfigID(specID)
end

local function TriggerRestore()
    if restorePending then return end
    restorePending   = true
    restoringBars    = true
    pendingRestoreAt = GetTime() + 0.5
end

local function TriggerSnapshotBar(barIndex)
    if pendingSnapshotsAt[barIndex] then return end
    pendingSnapshots[barIndex]   = true
    pendingSnapshotsAt[barIndex] = GetTime() + 0.1
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "TRAIT_CONFIG_UPDATED" then
        local currentID = GetCurrentSavedConfigID()
        if currentID ~= lastSavedConfigID then
            lastSavedConfigID = currentID
            TriggerRestore()
        end

    elseif event == "PLAYER_TALENT_UPDATE" then
        if not baselineSet then
            baselineSet = true
            lastSavedConfigID = GetCurrentSavedConfigID()
            return
        end
        lastSavedConfigID = GetCurrentSavedConfigID()
        TriggerRestore()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRestore then
            pendingRestore = false
            TriggerRestore()   -- defer via OnUpdate poller; do not call directly from event handler
        end

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
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
            local db    = GetDB()
            local entry = db.bars[barIndex]
            if entry and entry.enabled then
                SharedBars:SnapshotBar(barIndex)
            end
        end
    end
end)
