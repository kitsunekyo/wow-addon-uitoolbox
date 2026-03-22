-- UIToolbox
-- Modules/DamageMeterButton.lua
--
-- Injects a custom button into the Blizzard damage meter header, positioned
-- to the left of the existing settings (gear) button. Clicking it directly
-- toggles the free-drag feature from DamageMeterDrag.

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

	-- Plain Button — we cannot use DamageMeterSettingsDropdownButtonTemplate because
	-- that template is a DropdownButton whose mixin calls :IsMenuOpen(), which does
	-- not exist on a regular Button. Instead we replicate the visuals manually using
	-- the same atlas names the template defines.
	local btn = CreateFrame("Button", BUTTON_NAME, sessionWindow)
	btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	btn:SetPoint("RIGHT", sessionDropdown, "LEFT", -4, -3)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	icon:SetAtlas("common-dropdown-a-button-settings-shadowless", true)
	btn.Icon = icon

	btn:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			icon:SetAtlas("common-dropdown-a-button-settings-pressed-shadowless", true)
		end
	end)
	btn:SetScript("OnMouseUp", function()
		icon:SetAtlas("common-dropdown-a-button-settings-shadowless", true)
	end)
	btn:SetScript("OnEnter", function(self)
		icon:SetAtlas("common-dropdown-a-button-settings-hover-shadowless", true)
		local enabled = UIToolbox.db.damageMeterDrag.enabled
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText("UIToolbox: Free Drag", 1, 1, 1)
		GameTooltip:AddLine(enabled and "Click to disable" or "Click to enable", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		icon:SetAtlas("common-dropdown-a-button-settings-shadowless", true)
		GameTooltip:Hide()
	end)

	-- Toggle free drag on/off when clicked.
	btn:SetScript("OnClick", function()
		local db = UIToolbox.db.damageMeterDrag
		db.enabled = not db.enabled
		if db.enabled then
			UIToolbox.DamageMeterDrag:Enable()
		else
			UIToolbox.DamageMeterDrag:Disable()
		end
		RefreshButtonVisual()
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
