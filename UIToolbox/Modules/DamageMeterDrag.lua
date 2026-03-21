-- UIToolbox
-- Modules/DamageMeterDrag.lua
--
-- Makes DamageMeterSessionWindow1 freely draggable at any time, not just in
-- Edit Mode. Edit Mode is left completely untouched.
--
-- When free drag is first enabled, the current position is persisted to
-- UIToolboxDB. On disable, the frame is returned to that saved position.
-- On re-enable, the frame is restored to the saved position.

local DamageMeterDrag = {}
UIToolbox.DamageMeterDrag = DamageMeterDrag

local FRAME_NAME = "DamageMeterSessionWindow1"

-- Store whether this is the first enable (for position capture logic)
local firstEnable = true

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function ApplyPosition(frame, pos)
	local relativeFrame = _G[pos.relativeTo] or UIParent
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, relativeFrame, pos.relativePoint, pos.offsetX, pos.offsetY)
end

local function CapturePosition(frame)
	local point, relativeTo, relativePoint, offsetX, offsetY = frame:GetPoint(1)
	if not point then return nil end
	return {
		point        = point,
		relativeTo   = relativeTo and relativeTo:GetName() or "UIParent",
		relativePoint = relativePoint,
		offsetX      = offsetX,
		offsetY      = offsetY,
	}
end

-- ---------------------------------------------------------------------------
-- Enable / Disable
-- ---------------------------------------------------------------------------

function DamageMeterDrag:Enable()
	local db = UIToolbox.db.damageMeterDrag
	local frame = _G[FRAME_NAME]
	if not frame then return end
	if InCombatLockdown() then return end

	-- If this is the first time enabling in this session, capture the position
	if firstEnable then
		firstEnable = false
		if not db.savedPosition then
			db.savedPosition = CapturePosition(frame)
		end
	else
		-- On re-enable, restore to the saved position
		if db.savedPosition then
			ApplyPosition(frame, db.savedPosition)
		end
	end

	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")

	frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
	frame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
end

function DamageMeterDrag:Disable()
	local db = UIToolbox.db.damageMeterDrag
	local frame = _G[FRAME_NAME]
	if not frame then return end
	if InCombatLockdown() then return end

	frame:SetScript("OnDragStart", nil)
	frame:SetScript("OnDragStop",  nil)

	frame:SetMovable(false)
	frame:EnableMouse(false)
	frame:RegisterForDrag()

	-- Restore to the saved position, but keep it stored for re-enabling
	if db.savedPosition then
		ApplyPosition(frame, db.savedPosition)
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
	if db.enabled then
		self:Enable()
	end
end

UIToolbox:RegisterModule(DamageMeterDrag)

