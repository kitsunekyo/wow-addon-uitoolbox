-- UIToolbox
-- Modules/DamageMeterButton.lua
--
-- Injects a custom button into the Blizzard damage meter header, positioned
-- to the left of the existing settings (gear) button. Clicking it toggles the
-- free-drag feature from DamageMeterDrag.

local DamageMeterButton = {}
UIToolbox.DamageMeterButton = DamageMeterButton

local FRAME_NAME  = "DamageMeterSessionWindow1"
local BUTTON_NAME = "UIToolbox_DamageMeterButton"
local BUTTON_SIZE = 27

-- ---------------------------------------------------------------------------
-- Visual state
-- ---------------------------------------------------------------------------

-- Gold tint when drag is active, white (neutral) when inactive — matches the
-- convention WoW uses for toggled toolbar/header buttons.
local COLOR_ACTIVE   = { r = 1.0, g = 0.82, b = 0.0 }
local COLOR_INACTIVE = { r = 1.0, g = 1.0,  b = 1.0 }

local activeButton  -- reference kept so Settings.lua can trigger a refresh

local function RefreshButtonVisual()
	if not activeButton then return end
	local enabled = UIToolbox.db.damageMeterDrag.enabled
	local c = enabled and COLOR_ACTIVE or COLOR_INACTIVE
	activeButton.Icon:SetVertexColor(c.r, c.g, c.b)
end

-- ---------------------------------------------------------------------------
-- Button creation
-- ---------------------------------------------------------------------------

local function CreateHeaderButton(sessionWindow)
	if sessionWindow.UIToolboxButton then return end

	local sessionDropdown = sessionWindow.SessionDropdown
	if not sessionDropdown then return end

	-- Use the same template as the gear button for identical visual behaviour.
	local btn = CreateFrame("DropdownButton", BUTTON_NAME, sessionWindow, "DamageMeterSettingsDropdownButtonTemplate")
	btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	btn:SetPoint("RIGHT", sessionDropdown, "LEFT", -4, -3)

	-- Single menu item that toggles free drag on/off.
	btn:SetupMenu(function(_, rootDescription)
		rootDescription:SetTag("MENU_UITOOLBOX_HEADER_BUTTON")

		local db = UIToolbox.db.damageMeterDrag
		local label = db.enabled and "Disable Free Drag" or "Enable Free Drag"

		rootDescription:CreateButton(label, function()
			db.enabled = not db.enabled
			if db.enabled then
				UIToolbox.DamageMeterDrag:Enable()
			else
				UIToolbox.DamageMeterDrag:Disable()
			end
			RefreshButtonVisual()
		end)
	end)

	btn:SetScript("OnEnter", function(self)
		local enabled = UIToolbox.db.damageMeterDrag.enabled
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText("UIToolbox: Free Drag", 1, 1, 1)
		GameTooltip:AddLine(enabled and "Click to disable" or "Click to enable", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	activeButton = btn
	RefreshButtonVisual()

	sessionWindow.UIToolboxButton = btn
end

-- ---------------------------------------------------------------------------
-- Initialization — Blizzard built-in addons are NOT detected via ADDON_LOADED
-- or IsAddOnLoaded(). Hook directly on PLAYER_LOGIN when DamageMeter is ready.
-- ---------------------------------------------------------------------------

local hooked = false

local function HookDamageMeter()
	if hooked then return end
	if not DamageMeter then return end

	hooked = true

	hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, windowData, _windowIndex)
		local sessionWindow = windowData and windowData.sessionWindow
		if sessionWindow then
			CreateHeaderButton(sessionWindow)
		end
	end)

	local sessionWindow = _G[FRAME_NAME]
	if sessionWindow then
		CreateHeaderButton(sessionWindow)
	end
end

local moduleFrame = CreateFrame("Frame")
moduleFrame:RegisterEvent("PLAYER_LOGIN")
moduleFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		HookDamageMeter()
	end
end)

UIToolbox:RegisterModule(DamageMeterButton)
