-- UIToolbox
-- Modules/DamageMeterDrag.lua
--
-- Makes DamageMeterSessionWindow1 freely draggable at any time, not just in
-- Edit Mode. On drag stop the new position is written directly into Edit
-- Mode's active layout via OnSystemPositionChange, so Edit Mode is always
-- the single source of truth for the frame's position and size.
-- Disabling simply asks Edit Mode to re-apply its layout, restoring whatever
-- position and size the user has configured there.

local DamageMeterDrag = {}
UIToolbox.DamageMeterDrag = DamageMeterDrag

local FRAME_NAME = "DamageMeterSessionWindow1"

-- ---------------------------------------------------------------------------
-- Enable / Disable
-- ---------------------------------------------------------------------------

function DamageMeterDrag:Enable()
    local frame = _G[FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        -- Write the new position directly into Edit Mode's active layout.
        -- This makes Edit Mode the single source of truth: position persists
        -- via Edit Mode's own save system, and restores cleanly on disable.
        EditModeManagerFrame:OnSystemPositionChange(f)
    end)
end

function DamageMeterDrag:Disable()
    local frame = _G[FRAME_NAME]
    if not frame then return end
    if InCombatLockdown() then return end

    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)

    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:RegisterForDrag()

    -- Ask Edit Mode to re-apply its own stored layout (position + size).
    -- Since OnSystemPositionChange kept it in sync, this restores cleanly.
    if EditModeManagerFrame and EditModeManagerFrame.ApplyLayoutToFrame then
        EditModeManagerFrame:ApplyLayoutToFrame(frame)
    end
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------

local initialized = false

function DamageMeterDrag:OnZoneChanged()
    if initialized then return end
    initialized = true

    local db = UIToolbox.db.damageMeterDrag
    local frame = _G[FRAME_NAME]
    if not frame then return end

    if db.enabled then
        self:Enable()
    end
end

UIToolbox:RegisterModule(DamageMeterDrag)
