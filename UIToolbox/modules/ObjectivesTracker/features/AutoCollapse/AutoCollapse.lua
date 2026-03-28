-- UIToolbox
-- modules/ObjectivesTracker/features/AutoCollapse/AutoCollapse.lua
--
-- Automatically collapses configured Objective Tracker sections when entering
-- any game instance. Restores each section to its pre-instance state on exit.

local AutoCollapse = {}

local SECTIONS = {
    { key = "campaign",    frameName = "CampaignQuestObjectiveTracker" },
    { key = "quests",      frameName = "QuestObjectiveTracker"         },
    { key = "worldQuests", frameName = "WorldQuestObjectiveTracker"    },
}

local INSTANCE_TYPES = {
    party = true, raid = true, pvp = true, arena = true, scenario = true,
}

local preInstanceState = {}
local wasInInstance    = false

function AutoCollapse:OnZoneChanged(inInstance, instanceType)
    local db = UIToolbox.db.autoCollapse
    if not db.enabled then return end

    local enteringInstance = inInstance and INSTANCE_TYPES[instanceType]

    if enteringInstance and not wasInInstance then
        -- Snapshot current collapse states, then collapse enabled sections
        for _, section in ipairs(SECTIONS) do
            local frame = _G[section.frameName]
            if frame then
                preInstanceState[section.key] = frame:IsCollapsed()
                if db.sections[section.key] then
                    frame:SetCollapsed(true)
                end
            end
        end
        wasInInstance = true

    elseif not enteringInstance and wasInInstance then
        -- Restore each section to its pre-instance state
        for _, section in ipairs(SECTIONS) do
            local frame = _G[section.frameName]
            if frame then
                local wasCollapsed = preInstanceState[section.key]
                if wasCollapsed ~= nil then
                    frame:SetCollapsed(wasCollapsed)
                end
            end
        end
        preInstanceState = {}
        wasInInstance    = false
    end
end

UIToolbox:RegisterModule(AutoCollapse)
