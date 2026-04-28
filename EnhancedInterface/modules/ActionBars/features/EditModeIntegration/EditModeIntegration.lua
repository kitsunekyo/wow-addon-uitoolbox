local SYSTEM_INDEX_TO_BAR_INDEX = {
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
    [5] = 5,
    [6] = 6,
    [7] = 7,
    [8] = 8,
}

EnhancedInterface.EditModeCompanion.Register({
    filter = function(systemFrame)
        if systemFrame.system ~= Enum.EditModeSystem.ActionBar then return false end
        return SYSTEM_INDEX_TO_BAR_INDEX[systemFrame.systemIndex] ~= nil
    end,

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
