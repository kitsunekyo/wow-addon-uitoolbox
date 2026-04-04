-- EnhancedInterface
-- modules/ActionBars/features/EditModeIntegration/EditModeIntegration.lua
--
-- Registers the "Shared Bar" setting with the shared EditModeCompanionDialog
-- so it appears in the "EnhancedInterface" companion panel when the player selects a
-- supported action bar in Edit Mode.
--
-- ── Bar index mapping ──────────────────────────────────────────────────────────
--
-- Enum.EditModeActionBarSystemIndices (values 1–8 map 1:1 to SharedBars barIndex):
--   MainBar   = 1  →  SharedBars barIndex 1  (Action Bar 1)
--   Bar2      = 2  →  barIndex 2
--   Bar3      = 3  →  barIndex 3
--   RightBar1 = 4  →  barIndex 4
--   RightBar2 = 5  →  barIndex 5
--   ExtraBar1 = 6  →  barIndex 6
--   ExtraBar2 = 7  →  barIndex 7
--   ExtraBar3 = 8  →  barIndex 8
--
-- StanceBar (11), PetActionBar (12), PossessActionBar (13) are NOT supported.

-- Maps Enum.EditModeActionBarSystemIndices → SharedBars barIndex.
local SYSTEM_INDEX_TO_BAR_INDEX = {
    [1] = 1,  -- MainBar
    [2] = 2,  -- Bar2
    [3] = 3,  -- Bar3
    [4] = 4,  -- RightBar1 (MultiBarRight)
    [5] = 5,  -- RightBar2 (MultiBarLeft)
    [6] = 6,  -- ExtraBar1 (MultiBar5)
    [7] = 7,  -- ExtraBar2 (MultiBar6)
    [8] = 8,  -- ExtraBar3 (MultiBar7)
}

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        if systemFrame.system ~= Enum.EditModeSystem.ActionBar then return false end
        return SYSTEM_INDEX_TO_BAR_INDEX[systemFrame.systemIndex] ~= nil
    end,

    -- Dynamic rows: content depends on which action bar is selected.
    getRows = function(systemFrame)
        local barIndex = SYSTEM_INDEX_TO_BAR_INDEX[systemFrame.systemIndex]
        if not barIndex then return nil end

        return {
            {
                type    = "checkbox",
                label   = "Shared Bar",
                tooltip = "Keeps this bar's buttons the same across all talent loadouts. " ..
                          "Enabling takes a snapshot of the current layout.",
                get = function()
                    local db = EnhancedInterface.db.sharedBars.bars[barIndex]
                    return db ~= nil and db.enabled == true
                end,
                set = function(value)
                    if value then
                        EnhancedInterface.SharedBars:EnableBar(barIndex)
                    else
                        EnhancedInterface.SharedBars:DisableBar(barIndex)
                    end
                end,
            },
        }
    end,
})
