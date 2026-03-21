-- UIToolbox
-- Modules/TrackerCollapse.lua
--
-- Automatically collapses configured Objective Tracker sections when entering
-- any game instance (dungeon, raid, pvp, arena, scenario). Restores each
-- section to its pre-instance collapse state on exit.

local TrackerCollapse = {}

-- Map of config key → global tracker frame name.
-- Order is intentional: Campaign first, then Quests, then World Quests.
local SECTIONS = {
    { key = "campaign",    frameName = "CampaignQuestObjectiveTracker" },
    { key = "quests",      frameName = "QuestObjectiveTracker"         },
    { key = "worldQuests", frameName = "WorldQuestObjectiveTracker"    },
}

-- Snapshot of collapse states taken just before entering an instance,
-- keyed by section key. Used to restore state on exit.
local preInstanceState = {}
local wasInInstance    = false

-- Collapse or restore all configured sections based on zone state.
function TrackerCollapse:OnZoneChanged(inInstance, instanceType)
    local db = UIToolbox.db.trackerCollapse

    if not db.enabled then return end

    local instanceTypes = db.instanceTypes
    local enteringInstance = inInstance and instanceTypes and instanceTypes[instanceType]

    if enteringInstance and not wasInInstance then
        -- Snapshot current states, then collapse enabled sections.
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
        -- Restore each section to its pre-instance state.
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

UIToolbox:RegisterModule(TrackerCollapse)

