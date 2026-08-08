---------------------------------------------------------------------------
-- Auras - the ones Blizzard's Cooldown Manager does not carry.
--
-- WHY THIS IS A SEPARATE LIST, AND NOT SIMPLY "MORE COOLDOWNS".
--
-- Most auras already ARE in the Cooldown Manager: its TrackedBuff and
-- TrackedBar categories are auras, which is why Bone Shield, Blood Shield,
-- Death and Decay and Hemostasis appear under Buffs and Buff bars without
-- this file existing. Those are solved.
--
-- What is left over is the Boiling Point case: an aura that is not in the
-- C_CooldownViewer data set at all. No Cooldown Manager addon can add one,
-- because every picker enumerates the same data set. And on patch 12.0 an
-- addon cannot read the aura itself either - aura fields are secret values.
--
-- THE ONE SIGNAL THAT IS LEFT, AND THE SHAPE OF THE ANSWER.
--
-- When an aura empowers an ability, the game lights that ability's action
-- button. SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / _HIDE carry a plain spell ID
-- and never touch aura data.
--
-- So: what is SHOWN is the aura's own icon, and what DRIVES it is the glow on
-- a different spell. The user sees Boiling Point; underneath, Blood Boil is
-- what is actually being watched.
--
-- That also means the aura's real spell ID is not needed for this route. We
-- never query the aura - we draw an icon and run our own clock - so the
-- displayed spell is a CHOICE, not a lookup. It defaults to the talent whose
-- description names the glowing ability, which has the right icon and the
-- right name, and it can be set to anything.
--
-- THE SECOND ROUTE: 12.1, ARRIVING 11 AUG 2026.
--
-- Blizzard_AuraContainer binds a real aura by ID and drives icon, duration,
-- stacks and show/hide itself. That is strictly better than the glow proxy: a
-- proxy cannot tell two procs on one button apart, and its duration is our
-- guess rather than the game's fact.
--
-- It needs something the glow route does not: the aura's REAL spell ID. So an
-- entry carries three separate things, and they are not interchangeable:
--
--   parent   the ability whose button lights up   - drives the 12.0 route
--   display  the icon and name to show            - a choice, either route
--   auraID   the aura itself                      - drives the 12.1 route
--
-- Route selection is automatic: engine when the frame type exists and an
-- auraID is known, glow otherwise. Recording the auraID now, on 12.0, is why
-- the switch costs nothing next week.
--
-- WHY THERE IS NO HARDCODED TABLE OF LINKS.
--
-- There is no API that says "aura X lights up ability Z". Writing such a table
-- from memory is exactly the mistake that already cost this project two wrong
-- spell IDs. So the addon watches instead:
--
--   * every glow this character raises is recorded, per class and spec
--   * the time between SHOW and HIDE is the duration, measured rather than
--     assumed (an early cast cuts it short, so the longest seen is kept)
--   * /zs auras export prints the result as a pasteable block
--
-- A glow set belongs to a class and a spec, not to a player. So one person
-- playing one spec once is enough for everybody who plays it: the export goes
-- into ns.KNOWN_PROCS (Core/KnownProcs.lua) and ships with the addon. That
-- table only ever grows from observation.
---------------------------------------------------------------------------
local _, ns = ...

local Auras = {}
ns.Auras = Auras

---------------------------------------------------------------------------
-- What has actually been observed, and shipped
--
-- The table itself lives in Core/KnownProcs.lua - it is data that grows with
-- every export, and mixing it into this file made "paste your export here"
-- mean "edit the middle of six hundred lines of logic".
---------------------------------------------------------------------------
local function Bundled(key)
    local all = ns.KNOWN_PROCS or {}
    return all[key] or {}
end

---------------------------------------------------------------------------
-- Which route can carry an aura on this client
--
-- Probed by building one, because that is the only honest test. The previous
-- version of this addon gated on LoadAddOn("Blizzard_AuraContainer") - there
-- is no such addon, the frame type is built into the client, and that gate
-- could never open. Every engine feature was silently dead for a full version.
---------------------------------------------------------------------------
function Auras:EngineAvailable()
    if self.engineChecked then return self.engineOK end
    self.engineChecked = true

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent,
        "CustomAuraContainerTemplate")
    self.engineOK = (ok and container ~= nil) and true or false

    if self.engineOK then
        container:Hide()
        container:SetParent(nil)
    end
    return self.engineOK
end

-- "engine" is the real aura, bound by the game. "glow" is the proxy: an
-- action button lighting up, timed off our own clock. "none" means this proc
-- has nothing to hang on yet.
--
-- glowSpellID is passed in rather than read off the entry: in the proc store
-- the glowing spell is the KEY, not a field, and reading entry.parent here
-- silently reported "no route" for everything.
function Auras:Route(entry, glowSpellID)
    if entry.auraID and self:EngineAvailable() then return "engine" end
    if glowSpellID then return "glow" end
    return "none"
end

---------------------------------------------------------------------------
-- Which class and spec is playing
---------------------------------------------------------------------------
-- Cached: a glow event can fire several times a second in combat, and this
-- only changes when the spec does.
-- Moved to ns.SpecKey in 4.10.0, because the bars need the same answer: what
-- each cell holds is per class and spec now, and two implementations of "who
-- is playing" would eventually disagree about it.
function Auras:SpecKey()
    return (ns.SpecKey())
end

-- The recorder registers on file load, the database only exists from
-- ADDON_LOADED on. Nothing should fire in between, but a recorder that throws
-- would take an event handler down with it, so it checks.
local function Recorded(key, create)
    if not key or not ns.db or not ns.account.procs then return nil end
    local store = ns.account.procs
    if not store[key] and create then store[key] = {} end
    return store[key]
end

---------------------------------------------------------------------------
-- Recording
--
-- Always on. Two events, no polling, and it costs nothing until something
-- actually lights up.
---------------------------------------------------------------------------
local showAt = {}

---------------------------------------------------------------------------
-- Telling you about a proc nobody had seen before
--
-- ONE LINE, LATER, not one line each the moment it happens.
--
-- The recorder is always on, and the first fight on a character it has never
-- watched raises a glow for nearly everything that class does. A print per
-- proc turns that into a wall of chat that reads as the addon complaining -
-- reported as "sooo viele tracking fehler bei allen klassen und spells und
-- buffs", which is exactly what it looks like and is not an error at all.
--
-- So they are collected and reported once, a few seconds after the last one
-- arrives. Discovering things IS the point of this mechanism; announcing each
-- discovery in the middle of a pull is not.
---------------------------------------------------------------------------
local newProcs, announceQueued = {}, false

local function Announce(spellID)
    newProcs[#newProcs + 1] = ns.SpellName(spellID) or tostring(spellID)
    if announceQueued then return end

    announceQueued = true
    C_Timer.After(6, function()
        announceQueued = false
        local count = #newProcs
        if count == 0 then return end

        -- Named while the list is short enough to read; counted after that.
        local what = (count <= 4) and table.concat(newProcs, ", ")
            or (count .. " new procs")
        wipe(newProcs)

        -- It ends with what to DO with it. Somebody collecting procs for
        -- someone else has no reason to know the command, and "open Auras to
        -- see them" told them where to look at a list rather than how to hand
        -- it over - which is the whole reason they are running this.
        ns.Print(string.format("|cff40ff40%s|r seen for the first time on this "
            .. "spec, and recorded. Nothing is wrong. |cffffd100/zs report|r "
            .. "when you are done, and paste what it shows you.", what))
    end)
end

local function NoteShow(spellID)
    local key = Auras:SpecKey()
    local store = Recorded(key, true)
    if not store then return end

    showAt[spellID] = GetTime()

    local entry = store[spellID]
    if not entry then
        entry = { seen = 0 }
        store[spellID] = entry

        Announce(spellID)

        if ns.Options and ns.Options.OnCatalogChanged then
            ns.Options:OnCatalogChanged()
        end
    end

    entry.seen = (entry.seen or 0) + 1
end

-- When the player last cast each spell. A glow that ends right after its own
-- ability was cast was CUT SHORT; one that ends with no cast behind it RAN
-- OUT, and only that reading is the real duration.
--
-- Without this the number is a floor that creeps upwards for as long as you
-- keep playing, and "wait until it stops growing" is not an answer.
local castAt = {}
local CAST_WINDOW = 0.5

local function NoteCast(spellID)
    castAt[spellID] = GetTime()
end

---------------------------------------------------------------------------
-- Custom active states
--
-- "This is active for N seconds after I press it." For a trinket, a potion or
-- a racial: Blizzard's Cooldown Manager knows when they are on cooldown and
-- nothing at all about the buff they grant, so the one number that matters -
-- am I still inside the window - is on screen nowhere.
--
-- It cannot be measured the way a proc is. A proc announces itself with a
-- glow event; a trinket buff does not, and on this patch its aura may not be
-- read. So the player states the number once and it is believed. That is the
-- whole design, and it is why this is a setting rather than a recorder.
---------------------------------------------------------------------------

-- Every form of every stored spell, so a state set on one variant still
-- fires when the game reports the other. Rebuilt on demand rather than kept
-- in step, because the store changes when a person edits it and the lookup
-- runs on every cast.
local activeByVariant

local function ForgetActiveStates()
    activeByVariant = nil
end
ns.ForgetActiveStates = ForgetActiveStates

function Auras:ActiveStates()
    if not ns.account then return {} end
    ns.account.activeStates = ns.account.activeStates or {}
    return ns.account.activeStates
end

-- Seconds, or nil when this spell has no state. Variant-aware.
function Auras:ActiveStateFor(spellID)
    if not ns.CanCompute(spellID) then return nil end

    if not activeByVariant then
        activeByVariant = {}
        for stored, seconds in pairs(self:ActiveStates()) do
            local value = tonumber(seconds)
            if value and value > 0 then
                -- The exact ID wins; the derived forms only fill gaps, the
                -- same rule the item index follows. Two spells of one family
                -- can each carry their own window.
                activeByVariant[stored] = value
                for _, variant in ipairs(ns.CDM:VariantFamily(stored)) do
                    if activeByVariant[variant] == nil then
                        activeByVariant[variant] = value
                    end
                end
            end
        end
    end

    return activeByVariant[spellID]
end

function Auras:SetActiveState(spellID, seconds)
    if not ns.CanCompute(spellID) then return end
    local store = self:ActiveStates()

    local value = tonumber(seconds)
    -- Nil rather than 0: an absent key is "no window", and writing zeroes
    -- would grow the saved variables by one line per spell ever looked at.
    store[spellID] = (value and value > 0) and value or nil

    ForgetActiveStates()
end

local function NoteHide(spellID)
    local started = showAt[spellID]
    showAt[spellID] = nil
    if not started then return end

    local store = Recorded(Auras:SpecKey(), false)
    local entry = store and store[spellID]
    if not entry then return end

    local now = GetTime()
    local lasted = now - started
    if lasted <= 0.5 or lasted >= 600 then return end

    -- Anything recorded before the two readings were told apart was a floor.
    entry.floor = entry.floor or entry.duration

    local rounded = math.floor(lasted + 0.5)
    local cast = castAt[spellID]
    local cutShort = cast ~= nil and (now - cast) <= CAST_WINDOW

    if cutShort then
        if rounded > (entry.floor or 0) then entry.floor = rounded end
    elseif rounded > (entry.expired or 0) then
        entry.expired = rounded
    end

    -- The longest of both, ALWAYS. A natural expiry used to win outright, and
    -- a single 2s reading then wiped a 15s floor - a glow can end for reasons
    -- other than running out, and casting the empowered ability may report a
    -- different spell ID than the one glowing, so "no cast seen" is not proof
    -- that it ran out.
    entry.duration = math.max(entry.floor or 0, entry.expired or 0)
end

---------------------------------------------------------------------------
-- Reading a name out of the talent trees
--
-- Only for the LABEL. The tracking hangs on the glow, so a wrong guess here
-- costs a caption and nothing else.
--
-- No grammar is parsed: the names of this character's own spells are looked
-- for inside the talent's description text. Both sides are strings the same
-- client produced, so a German client works exactly like an English one.
---------------------------------------------------------------------------
local MIN_NAME = 5

local pending, namers = {}, nil

local function Description(spellID)
    if not (C_Spell and C_Spell.GetSpellDescription) then return nil end

    local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
    if ok and text and text ~= "" then return text end

    -- Spell data loads lazily; an empty description usually means "not here
    -- yet" rather than "there is none". Ask once - the load result event
    -- clears the cache and it is read again.
    if not pending[spellID] and C_Spell.RequestLoadSpellData then
        pending[spellID] = true
        pcall(C_Spell.RequestLoadSpellData, spellID)
    end
    return nil
end

local function PickedTalents()
    local picked = {}

    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
        return picked
    end

    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then return picked end

    local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or not configInfo or not configInfo.treeIDs then return picked end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and nodes then
            for _, nodeID in ipairs(nodes) do
                local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                -- ranksPurchased is the honest test: a node can be visible,
                -- available and still not chosen.
                if okNode and node and node.ranksPurchased and node.ranksPurchased > 0 then
                    -- activeEntry is the selected choice on a choice node;
                    -- plain nodes only carry entryIDs.
                    local entryID = node.activeEntry and node.activeEntry.entryID
                    if not entryID and node.entryIDs then entryID = node.entryIDs[1] end

                    if entryID then
                        local okEntry, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
                        if okEntry and entry and entry.definitionID then
                            local okDef, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
                            if okDef and def and def.spellID then
                                picked[def.spellID] = true
                            end
                        end
                    end
                end
            end
        end
    end

    return picked
end

-- For every talent, ALL the spell names its description mentions - not just
-- the longest one. Keeping only the best match hid Blood Boil behind Heart
-- Strike and made the whole lookup useless in the one case we could check.
local function Namers()
    if namers then return namers end

    namers = {}

    local names = {}
    for _, entry in ipairs(ns.CDM:Catalogue()) do
        local name = entry.name
        if name and #name >= MIN_NAME then
            names[#names + 1] = { key = name:lower(), spellID = entry.spellID }
        end
    end

    for talentID in pairs(PickedTalents()) do
        local text = Description(talentID)
        if text then
            local haystack = text:lower()
            local own = (ns.SpellName(talentID) or ""):lower()
            for _, candidate in ipairs(names) do
                if candidate.key ~= own and haystack:find(candidate.key, 1, true) then
                    local list = namers[candidate.spellID]
                    if not list then
                        list = {}
                        namers[candidate.spellID] = list
                    end
                    list[#list + 1] = talentID
                end
            end
        end
    end

    return namers
end

-- The talent most likely to be the one behind a proc on this ability. Several
-- talents can mention the same ability, so this is a suggestion for a caption
-- and never a fact - which is why nothing depends on it being right.
local function SuggestDisplay(glowSpellID)
    local list = Namers()[glowSpellID]
    if not list or #list == 0 then return nil end

    -- Deterministic: pairs() over the trait tree has no order, and a caption
    -- that changes between logins looks like a bug.
    table.sort(list)
    return list[1]
end

function Auras:Invalidate()
    namers = nil
    ns.ForgetSpecKey()
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- What is known for the spec being played: shipped first, then whatever this
-- character has seen for itself, which wins because it is first-hand.
function Auras:Procs()
    local key = self:SpecKey()
    local merged = {}
    local hidden = ns.account.procsHidden or {}

    for spellID, entry in pairs(Bundled(key)) do
        -- A shipped entry the user threw away stays thrown away. Without
        -- this, "forget" would only clear the recording underneath it and the
        -- proc would come straight back on the next login.
        if not hidden[spellID] then
            merged[spellID] = {
                display = entry.display, auraID = entry.auraID,
                duration = entry.duration,
                -- A shipped duration is a FLOOR, not a confirmed fact: it was
                -- measured the same way, by somebody else. Without this, one
                -- short natural expiry underneath it - Boiling Point ending
                -- after 2s because it was consumed - marked the shipped 15s
                -- as confirmed, which is the opposite of what was seen.
                floor = entry.duration,
                bundled = true,
            }
        end
    end

    for spellID, entry in pairs(Recorded(key, false) or {}) do
        local into = merged[spellID] or {}
        merged[spellID] = into
        into.seen = entry.seen
        if entry.display then into.display = entry.display end
        if entry.auraID then into.auraID = entry.auraID end

        -- Both readings travel, and the longest of everything wins - shipped
        -- value included. Neither kind may lower the number on its own: a
        -- floor is a genuine "at least this", and a natural expiry can be cut
        -- by something other than a cast.
        if entry.expired and entry.expired > (into.expired or 0) then
            into.expired = entry.expired
        end
        if entry.floor and entry.floor > (into.floor or 0) then
            into.floor = entry.floor
        end
        into.duration = math.max(into.duration or 0, into.expired or 0,
            into.floor or 0, entry.duration or 0)
    end

    -- Anything the user pointed at by hand, whatever spec recorded it. Here
    -- the key IS the aura, because the user named the buff they want to see.
    for spellID, entry in pairs(ns.account.auraLinks or {}) do
        local glow = entry.parent or spellID
        local into = merged[glow] or {}
        merged[glow] = into
        into.display = spellID
        into.auraID = into.auraID or spellID
        into.duration = into.duration or entry.duration
        into.manual = true
    end

    return merged
end

function Auras:Catalogue()
    local out = {}

    for glowSpellID, entry in pairs(self:Procs()) do
        local display = entry.display or SuggestDisplay(glowSpellID) or glowSpellID
        local name = ns.SpellName(display)

        if name then
            out[#out + 1] = {
                spellID  = display,          -- what is drawn
                parent   = glowSpellID,      -- what is watched on 12.0
                auraID   = entry.auraID,     -- what is bound on 12.1
                route    = self:Route(entry, glowSpellID),
                viewer   = "aura",
                name     = name,
                icon     = ns.SpellTexture(display),
                known    = true,
                -- Whether the ABILITY that lights up is in the build being
                -- played. A recording survives a respec, so a proc from an
                -- older loadout stays listed and has to say so rather than
                -- looking like something that simply never fires.
                liveHere = ns.IsSpellKnown(glowSpellID),
                duration = entry.duration,
                -- Confirmed only when a natural expiry is at least as long as
                -- the longest run we saw cut short. A shorter one means the
                -- two readings disagree, and a disagreement is not a fact.
                confirmed = entry.expired ~= nil
                    and entry.expired >= (entry.floor or 0),
                seen     = entry.seen,
                bundled  = entry.bundled,
                guessed  = entry.display == nil,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.name == b.name then return a.parent < b.parent end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------

-- Which icon a proc shows. A choice, not a lookup - see the header.
function Auras:SetDisplay(glowSpellID, spellID)
    local store = Recorded(self:SpecKey(), true)
    if not store then return false end

    store[glowSpellID] = store[glowSpellID] or {}
    store[glowSpellID].display = spellID
    ns.Print(string.format("Proc on %s now shows %s.",
        ns.SpellName(glowSpellID) or glowSpellID, ns.SpellName(spellID) or spellID))
    return true
end

-- The aura's real spell ID. Only the 12.1 engine route needs it, and nothing
-- on this client can look it up - so it is typed in once, and from then on it
-- travels with the export.
function Auras:SetAura(glowSpellID, auraID)
    local store = Recorded(self:SpecKey(), true)
    if not store then return false end

    store[glowSpellID] = store[glowSpellID] or {}
    store[glowSpellID].auraID = auraID
    store[glowSpellID].display = store[glowSpellID].display or auraID

    ns.Print(string.format("Proc on %s bound to aura %s (%d).",
        ns.SpellName(glowSpellID) or glowSpellID,
        ns.SpellName(auraID) or "?", auraID))

    if not self:EngineAvailable() then
        ns.Print("|cff888888Stored for patch 12.1 - this client still uses the glow.|r")
    end
    return true
end

-- Drops a proc for good on this account. Two stores, and both have to be
-- dealt with: the recording is deleted, and a SHIPPED entry is marked hidden,
-- because deleting something the addon carries would only last until the file
-- loaded again.
function Auras:Forget(glowSpellID)
    local key = self:SpecKey()
    local store = Recorded(key, false)
    local hadRecording = store and store[glowSpellID] ~= nil
    local isBundled = Bundled(key)[glowSpellID] ~= nil

    if not (hadRecording or isBundled) then return false end

    if hadRecording then store[glowSpellID] = nil end
    if isBundled then
        ns.account.procsHidden = ns.account.procsHidden or {}
        ns.account.procsHidden[glowSpellID] = true
    end

    self:Invalidate()
    ns.Print("Forgot the proc on", ns.SpellName(glowSpellID) or glowSpellID,
        isBundled and "|cff888888(it ships with the addon - hidden for this account)|r" or "")
    return true
end

-- Puts every hidden entry back. The only way out of "I forgot the wrong one"
-- that does not involve editing saved variables by hand.
function Auras:Remember()
    local count = 0
    for _ in pairs(ns.account.procsHidden or {}) do count = count + 1 end

    ns.account.procsHidden = {}
    self:Invalidate()
    ns.Print("Restored", count, "hidden proc" .. (count == 1 and "" or "s") .. ".")
    return count
end

---------------------------------------------------------------------------
-- Diagnosis and export
---------------------------------------------------------------------------
function Auras:Dump()
    ns.Print("|cffffd100----------------------------------------|r")

    local key = self:SpecKey() or "unknown"
    local catalogue = self:Catalogue()

    if #catalogue == 0 then
        ns.Print("|cffffd100" .. key .. "|r: nothing recorded yet.")
        ns.Print("Play normally - every ability that lights up is written down,")
        ns.Print("and shows up in the Auras list by itself.")
        return
    end

    ns.Print(string.format("|cffffd100%s|r - %d proc%s:",
        key, #catalogue, #catalogue == 1 and "" or "s"))

    local ROUTE = {
        engine = "|cff40ff40engine|r",
        glow   = "|cffffd100glow|r",
        none   = "|cffff4040no route|r",
    }

    for _, entry in ipairs(catalogue) do
        -- No "Defile on Defile": when nothing better is known the icon simply
        -- IS the glowing ability, and saying it twice reads as a fault.
        local on = (entry.spellID ~= entry.parent)
            and (" on |cffffd100" .. (ns.SpellName(entry.parent) or "?") .. "|r")
            or " |cff888888(unnamed proc)|r"

        -- A duration that came from the glow running out is a fact. One that
        -- came from casting the ability is only a floor, and saying so is the
        -- difference between a number worth shipping and one that is not.
        local time = entry.confirmed
            and ("|cff40ff40" .. entry.duration .. "s|r")
            or (entry.duration and entry.duration > 0
                and ("|cffff8040>" .. entry.duration .. "s|r")
                or "|cff888888?s|r")

        ns.Print(string.format("   %s |cff888888%d|r%s %s %s%s%s%s",
            entry.name, entry.spellID, on, time,
            ROUTE[entry.route] or "?",
            entry.seen and string.format(" |cff888888seen %dx|r", entry.seen) or "",
            (entry.guessed and entry.spellID ~= entry.parent)
                and " |cffff8040(name guessed)|r" or "",
            entry.liveHere and "" or " |cffff4040not talented|r"))
    end

    ns.Print("Left is what is shown, right is what is watched.")
    ns.Print("|cff40ff4015s|r = the glow ran out on its own, so that IS the duration.")
    ns.Print("|cffff8040>15s|r = you cast it and cut the glow short - at least that long.")
    ns.Print("A proc that never runs out on its own is a |cffffd100cast me|r hint, not an aura.")
    ns.Print(self:EngineAvailable()
        and "|cff40ff40Aura engine available|r - anything with a known aura ID uses it."
        or "|cff888888Aura engine needs patch 12.1 - everything runs on the glow.|r")
    ns.Print("|cffffd100/zs auras export|r to hand this spec's set back.")
end

-- Prints the recorded set as a block that can be pasted straight into
-- KNOWN_PROCS. This is how one player's session becomes everybody's default
-- for that spec.
-- The report, as PLAIN TEXT. No colour codes, because this string is written
-- to be pasted somewhere that is not a chat frame.
--
-- It carries the version and the client build with it: a proc list is only
-- worth anything if you know which build recorded it, and a tester will not
-- think to say. Returns nil when there is nothing to report.
function Auras:ExportText()
    local key = self:SpecKey()

    -- The MERGED view, never the raw recording. Reading the raw store meant
    -- the shipped display was invisible here, so the caption fell back to a
    -- guess and the export would have overwritten a correct entry with it -
    -- Blood Boil came out as Hemostasis instead of Boiling Point.
    local procs = self:Procs()
    if not next(procs) then return nil, key end

    local ids = {}
    for spellID in pairs(procs) do ids[#ids + 1] = spellID end
    table.sort(ids)

    local out = {}
    local function Line(text) out[#out + 1] = text end

    local version, build = ns.version or "?", (GetBuildInfo())
    Line(("-- ZwoelfStuff %s, client %s, %s")
        :format(version, tostring(build), key or "unknown spec"))
    Line(("-- %d proc%s recorded. Paste into ns.KNOWN_PROCS in Core/KnownProcs.lua.")
        :format(#ids, #ids == 1 and "" or "s"))
    Line("")
    Line(('    ["%s"] = {'):format(key))

    for _, spellID in ipairs(ids) do
        local entry = procs[spellID]
        local display = entry.display or SuggestDisplay(spellID) or spellID
        -- The comment carries the warning, because the block gets pasted and
        -- the warning has to survive the paste.
        local confirmed = entry.expired ~= nil
            and entry.expired >= (entry.floor or 0)

        Line(string.format(
            "        [%d] = { display = %d, auraID = %s, duration = %d },  -- %s -> %s%s",
            spellID, display,
            entry.auraID and tostring(entry.auraID) or "nil",
            entry.duration or 15,
            ns.SpellName(spellID) or "?", ns.SpellName(display) or "?",
            confirmed and "" or "  [duration UNCONFIRMED]"))
    end

    Line("    },")
    return table.concat(out, "\n"), key
end

-- Opens the report in a box you can actually copy out of.
--
-- It used to print to the chat frame, which is not a way to hand anything
-- over: chat text cannot be selected, the colour codes would come with it if
-- it could, and thirty lines scroll off the top. That made "export" a command
-- only the person with the source file could use.
function Auras:Export()
    local text, key = self:ExportText()
    if not text then
        ns.Print("Nothing recorded for", key or "this spec", "yet.")
        ns.Print("Play normally - every ability that lights up is written down.")
        return
    end

    ns.UI.CopyBox("Proc report - " .. (key or "this spec"), text,
        "Ctrl+C copies all of it. Esc closes. Check the names first: what is "
        .. "shown is a choice, and the one on the right is only the talent "
        .. "whose text mentions the left one.")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")

for _, event in ipairs({
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "SPELL_DATA_LOAD_RESULT",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
}) do
    pcall(watcher.RegisterEvent, watcher, event)
end

-- Unit-filtered, so every other unit's casts never reach the handler at all.
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- The payloads differ, so they are named rather than assumed: the glow events
-- carry the spell ID first, UNIT_SPELLCAST_SUCCEEDED carries unit, castGUID,
-- spellID.
watcher:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        -- Plain spell IDs, but check rather than assume: computing on a
        -- secret value throws.
        if ns.CanCompute(arg1) then NoteShow(arg1) end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if ns.CanCompute(arg1) then NoteHide(arg1) end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if ns.CanCompute(arg3) then
            NoteCast(arg3)

            -- The only trigger a custom active state has. There is no aura to
            -- watch and no glow to wait for - the press IS the event.
            local seconds = Auras:ActiveStateFor(arg3)
            if seconds and ns.Screen then
                ns.Screen:StartCustomActive(arg3, seconds)
            end
        end

    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Only for a description this addon asked for.
        if arg1 and pending[arg1] then
            pending[arg1] = nil
            namers = nil
        end

    else
        Auras:Invalidate()
        if ns.Options and ns.Options.OnCatalogChanged then
            ns.Options:OnCatalogChanged()
        end
    end
end)
