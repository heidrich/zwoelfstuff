---------------------------------------------------------------------------
-- Visibility - when a bar is on screen at all.
--
-- "Show my defensives only in a dungeon, and only while I am in combat" is
-- one of the two things people build a second UI addon for. It is a rule per
-- bar, evaluated on the events that can change the answer and never on a
-- timer: polling the group size sixty times a second to learn something that
-- changes twice an evening is how an addon earns a reputation.
--
-- EVERY RULE IS AN "AND".
--
-- A bar shows when every rule it has agrees. That is the model people can
-- hold in their head, and it is why each rule's default is "any" - a rule you
-- have not set cannot be the reason something is missing.
--
-- WHY ALPHA AND NOT HIDE.
--
-- Half of what a bar shows belongs to Blizzard - see Core/Screen.lua - and
-- hiding a Blizzard frame is one of the named ways to taint it. So "hidden"
-- here means alpha 0, on our own cells and on the adopted ones alike, and
-- the rule that decides it is applied in exactly one place.
---------------------------------------------------------------------------
local _, ns = ...

local Visibility = {}
ns.Visibility = Visibility

---------------------------------------------------------------------------
-- The vocabulary
--
-- Every list here is also what the options page shows, so a rule cannot exist
-- in the evaluator and be missing from the editor.
---------------------------------------------------------------------------
ns.SHOW_MODES = {
    { value = "always", text = "Always" },
    { value = "rules",  text = "Only when..." },
    { value = "never",  text = "Never" },
}

ns.SHOW_COMBAT = {
    { value = "any", text = "In and out of combat" },
    { value = "in",  text = "Only in combat" },
    { value = "out", text = "Only out of combat" },
}

ns.SHOW_TARGET = {
    { value = "any", text = "Target or not" },
    { value = "yes", text = "Only with a target" },
    { value = "no",  text = "Only without a target" },
}

ns.SHOW_GROUP = {
    { value = "any",   text = "Alone or grouped" },
    { value = "solo",  text = "Only alone" },
    { value = "party", text = "Only in a party" },
    { value = "raid",  text = "Only in a raid" },
}

ns.SHOW_RESTING = {
    { value = "any", text = "Anywhere" },
    { value = "no",  text = "Not in a rested area" },
    { value = "yes", text = "Only in a rested area" },
}

-- The instance types the client actually reports, read off a working addon on
-- this machine (EllesmereUI_Conditions.lua maps party/raid/arena/pvp) rather
-- than written from memory.
--
-- Delves report as a scenario, so the two share a line rather than getting a
-- key that the client never returns and that would therefore never match.
ns.SHOW_WHERE = {
    { key = "none",     text = "Out in the world" },
    { key = "party",    text = "Dungeons" },
    { key = "raid",     text = "Raids" },
    { key = "scenario", text = "Scenarios and delves" },
    { key = "pvp",      text = "Battlegrounds" },
    { key = "arena",    text = "Arenas" },
}

ns.SHOW_DEFAULTS = {
    mode    = "always",
    combat  = "any",
    target  = "any",
    group   = "any",
    resting = "any",

    -- Every place, until the user says otherwise. An empty table would read
    -- as "nowhere" and make a new rule hide the bar the moment it is switched
    -- on, which looks like a bug rather than a setting.
    where = {
        none = true, party = true, raid = true,
        scenario = true, pvp = true, arena = true,
    },

    -- Only these specs. Empty means every one of them: same reasoning.
    specs = {},

    -- What "does not apply" looks like. 0 is out of the way entirely; a low
    -- number keeps the bar there as a ghost, which is what people want while
    -- they are still arranging it.
    hiddenAlpha = 0,
}

---------------------------------------------------------------------------
-- The state, sampled once per change
--
-- Read together and cached, so twelve bars asking twelve questions is one
-- pass over the game rather than twelve.
---------------------------------------------------------------------------
local state = {
    combat = false,
    where = "none",
    group = "solo",
    target = false,
    resting = false,
    spec = nil,
}

local function Sample()
    state.combat = UnitAffectingCombat("player") and true or false
    state.target = UnitExists("target") and true or false
    state.resting = IsResting() and true or false

    local inside, instanceType = IsInInstance()
    state.where = (inside and instanceType) or "none"

    if IsInRaid() then
        state.group = "raid"
    elseif IsInGroup() then
        state.group = "party"
    else
        state.group = "solo"
    end

    -- The spec ID, not its index: an index means a different spec on a
    -- different class, and a rule saved on one character would quietly apply
    -- to the wrong spec on another.
    local info = C_SpecializationInfo
    if info and info.GetSpecialization and info.GetSpecializationInfo then
        local ok, index = pcall(info.GetSpecialization)
        if ok and index then
            local okID, id = pcall(info.GetSpecializationInfo, index)
            state.spec = okID and id or nil
        else
            state.spec = nil
        end
    else
        -- No API, no answer. Leaving the last one in place would keep a spec
        -- rule running off a value nothing can refresh.
        state.spec = nil
    end
end

function Visibility:State()
    return state
end

---------------------------------------------------------------------------
-- The rule
---------------------------------------------------------------------------

-- Whether a table of allowed keys lets `key` through. An empty or missing
-- table means "no filter set", never "nothing allowed" - see SHOW_DEFAULTS.
local function Allows(set, key)
    if not set then return true end

    local empty = true
    for _ in pairs(set) do empty = false break end
    if empty then return true end

    return set[key] and true or false
end

-- Whether the place we are in passes the rule.
--
-- An instance type the client reports and this list has never heard of lets
-- the bar through on purpose: a new one in a patch must not make everybody's
-- UI vanish in the new content. Shared with the explanation below rather than
-- written twice - the editor was naming "not in this kind of place" as the
-- reason in exactly the case where the evaluator lets the bar through, which
-- is worse than no explanation at all.
local function WhereAllows(rule)
    for _, entry in ipairs(ns.SHOW_WHERE) do
        if entry.key == state.where then
            return Allows(rule.where, state.where)
        end
    end
    return true
end

-- true when the bar should be visible, plus the alpha to use when it is not.
function Visibility:Evaluate(cfg)
    if cfg.enabled == false then return false end

    local rule = cfg.show
    if not rule or rule.mode == "always" or rule.mode == nil then return true end
    if rule.mode == "never" then return false end

    if rule.combat == "in" and not state.combat then return false end
    if rule.combat == "out" and state.combat then return false end

    if rule.target == "yes" and not state.target then return false end
    if rule.target == "no" and state.target then return false end

    if rule.resting == "yes" and not state.resting then return false end
    if rule.resting == "no" and state.resting then return false end

    if rule.group ~= nil and rule.group ~= "any" and rule.group ~= state.group then
        return false
    end

    if not WhereAllows(rule) then return false end

    if state.spec and not Allows(rule.specs, state.spec) then return false end

    return true
end

-- The alpha multiplier a bar is drawn at right now: 1 when its rule agrees,
-- and whatever the rule says otherwise.
function Visibility:Factor(cfg)
    if self:Evaluate(cfg) then return 1 end
    local rule = cfg.show
    return (rule and rule.hiddenAlpha) or 0
end

-- A one-line answer for the editor: why is this bar not on screen?
function Visibility:Explain(cfg)
    if cfg.enabled == false then return "Switched off." end

    local rule = cfg.show
    if not rule or rule.mode == "always" or rule.mode == nil then return nil end
    if rule.mode == "never" then return "Set to never show." end

    if rule.combat == "in" and not state.combat then return "Waiting for combat." end
    if rule.combat == "out" and state.combat then return "Hidden in combat." end
    if rule.target == "yes" and not state.target then return "Waiting for a target." end
    if rule.target == "no" and state.target then return "Hidden while you have a target." end
    if rule.resting == "yes" and not state.resting then return "Only in a rested area." end
    if rule.resting == "no" and state.resting then return "Hidden in a rested area." end
    if rule.group ~= nil and rule.group ~= "any" and rule.group ~= state.group then
        return "Only " .. rule.group .. ", and you are " .. state.group .. "."
    end
    if not WhereAllows(rule) then return "Not in this kind of place." end
    if state.spec and not Allows(rule.specs, state.spec) then return "Not for this spec." end

    return nil
end

---------------------------------------------------------------------------
-- Staying current
--
-- Every event that can change an answer above, and nothing else. The work is
-- one Sample plus one alpha pass, so it is cheap enough to run on all of them
-- and correct enough that no bar is ever a frame behind.
---------------------------------------------------------------------------
local listeners = {}

function Visibility:OnChanged(fn)
    listeners[#listeners + 1] = fn
end

local function Announce()
    Sample()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "PLAYER_UPDATE_RESTING", "PLAYER_SPECIALIZATION_CHANGED",
}) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", Announce)

function Visibility:Start()
    Sample()
end
