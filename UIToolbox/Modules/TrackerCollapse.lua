-- UIToolbox
-- Modules/TrackerCollapse.lua
--
-- Automatically collapses configured Objective Tracker sections when entering
-- any game instance (dungeon, raid, pvp, arena, scenario). Restores each
-- section to its pre-instance collapse state on exit.

local TrackerCollapse = {}

-- Map of config key to global tracker frame name.
-- Order is intentional: Campaign first, then Quests, then World Quests.
local SECTIONS = {
    { key = "campaign",    frameName = "CampaignQuestObjectiveTracker" },
    { key = "quests",      frameName = "QuestObjectiveTracker"         },
    { key = "worldQuests", frameName = "WorldQuestObjectiveTracker"    },
}

-- Instance types that trigger collapse.
local INSTANCE_TYPES = {
    party    = true,
    raid     = true,
    pvp      = true,
    arena    = true,
    scenario = true,
}

-- Snapshot of collapse states taken just before entering an instance,
-- keyed by section key. Used to restore state on exit.
local preInstanceState = {}
local wasInInstance    = false

local function dbg(msg)
    print("|cff888888[UIToolbox]|r " .. msg)
end

-- Collapse or restore all configured sections based on zone state.
function TrackerCollapse:OnZoneChanged(inInstance, instanceType)
    local db = UIToolbox.db.trackerCollapse

    if not db.enabled then return end

    local enteringInstance = inInstance and INSTANCE_TYPES[instanceType]

    if enteringInstance and not wasInInstance then
        dbg("TrackerCollapse: entering instance (" .. (instanceType or "?") .. "), collapsing sections.")
        -- Snapshot current states, then collapse enabled sections.
        for _, section in ipairs(SECTIONS) do
            local frame = _G[section.frameName]
            if frame then
                preInstanceState[section.key] = frame:IsCollapsed()
                if db.sections[section.key] then
                    frame:SetCollapsed(true)
                    dbg("  Collapsed: " .. section.frameName)
                else
                    dbg("  Skipped (disabled in config): " .. section.frameName)
                end
            else
                dbg("  Frame not found: " .. section.frameName)
            end
        end
        wasInInstance = true

    elseif not enteringInstance and wasInInstance then
        dbg("TrackerCollapse: leaving instance, restoring sections.")
        -- Restore each section to its pre-instance state.
        for _, section in ipairs(SECTIONS) do
            local frame = _G[section.frameName]
            if frame then
                local wasCollapsed = preInstanceState[section.key]
                if wasCollapsed ~= nil then
                    frame:SetCollapsed(wasCollapsed)
                    dbg("  Restored: " .. section.frameName .. " -> collapsed=" .. tostring(wasCollapsed))
                end
            else
                dbg("  Frame not found: " .. section.frameName)
            end
        end
        preInstanceState = {}
        wasInInstance    = false
    end
end

UIToolbox:RegisterModule(TrackerCollapse)
