-- UIToolbox
-- modules/ObjectivesTracker/CustomSection/CustomSection.lua
--
-- Injects a custom section into the "All Objectives" tracker, appearing below
-- all built-in sections. Uses ObjectiveTrackerModuleTemplate so the header,
-- collapse button, and layout machinery are identical to native sections.
--
-- No paired XML file: the frame is created entirely in Lua to avoid the
-- mixin= attribute evaluation-at-parse-time ordering constraint.

-- ---------------------------------------------------------------------------
-- Mixin
-- ---------------------------------------------------------------------------

local UIToolboxTrackerModuleMixin = CreateFromMixins(ObjectiveTrackerModuleMixin);

function UIToolboxTrackerModuleMixin:InitModule()
    -- Nothing to initialise for the prototype.
end

-- Called by the container every time the tracker repaints.
function UIToolboxTrackerModuleMixin:LayoutContents()
    local block = self:GetBlock("uitoolbox_placeholder");
    block:SetHeader("Custom Section — Proof of Concept");
    block:AddObjective("line1", "UIToolbox tracker section is working!", nil, nil,
        OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE);
    if not self:LayoutBlock(block) then
        return;
    end
end

-- ---------------------------------------------------------------------------
-- Frame creation
-- ---------------------------------------------------------------------------

local frame = CreateFrame(
    "Frame",
    "UIToolboxTrackerModule",
    ObjectiveTrackerFrame,
    "ObjectiveTrackerModuleTemplate"
);

Mixin(frame, UIToolboxTrackerModuleMixin);

-- headerText must be set before SetHeader() is called, but OnLoad() already
-- ran during CreateFrame with headerText=nil. Call SetHeader() explicitly now
-- to push the label into the header sub-frame's Text font string.
frame.headerText = "UIToolbox";
frame:SetHeader("UIToolbox");

-- Sit below all built-in modules (their uiOrder values are 1–11).
frame.uiOrder = 100;

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

-- Use hooksecurefunc on Init so we are guaranteed to run after
-- ObjectiveTrackerManager:Init() has populated self.containers.
-- PLAYER_ENTERING_WORLD is the fallback for the case where Init already ran.
local registered = false;
local function TryRegister()
    if registered then return end;
    if not (ObjectiveTrackerManager.containers
            and ObjectiveTrackerManager.containers[ObjectiveTrackerFrame]) then
        return;
    end
    registered = true;
    ObjectiveTrackerManager:SetModuleContainer(UIToolboxTrackerModule, ObjectiveTrackerFrame);
    C_Timer.After(0, function()
        ObjectiveTrackerManager:UpdateAll();
    end);
end

hooksecurefunc(ObjectiveTrackerManager, "Init", TryRegister);

local diag = CreateFrame("Frame");
diag:RegisterEvent("PLAYER_ENTERING_WORLD");
diag:SetScript("OnEvent", function()
    TryRegister();
end);
