---------------------------------------------------------------------------
-- Routes - your Mythic Dungeon Tools pull, marked on the mobs themselves
--
-- NOT GATED ON A KEYSTONE, and that is deliberate rather than an oversight.
-- A normal dungeon holds the same mobs with the same npcIDs as the timed one,
-- so a route marks them just as well - and MDT has data for raids too. The
-- only thing that has to be true is that MDT is holding a route for the place
-- you are standing in.
--
-- WHAT IT DOES.
--
-- Reads the route you planned in MDT and puts a coloured badge over every
-- nameplate belonging to the pull you are on, in the colour that pull already
-- has in MDT. The next pull gets the same badge, dimmed. So "which of these
-- do I take now" is answered by looking at the mobs rather than at a list.
--
-- WHY THE NAMEPLATE AND NOT A MARKER IN THE WORLD.
--
-- MDT stores a position for every mob, and those positions are in MDT'S OWN
-- map space - the coordinates of its dungeon texture, not the game's. MDT
-- never needs to convert them because it never shows where you are standing,
-- so there is no conversion to borrow and one would have to be calibrated per
-- dungeon and per floor.
--
-- And it would be wrong for a large part of the route anyway: MDT carries
-- PATROL PATHS, and a patrolling mob is not where its dot is. A badge on the
-- nameplate is on the mob wherever the mob actually is.
--
-- HOW A LIVE MOB IS MATCHED TO A PLANNED ONE, AND THE LIMIT OF IT.
--
-- A unit's GUID carries its npcID in field six
-- (type-0-serverID-instanceID-zoneUID-**id**-spawnUID, read off
-- MRT/Functions.lua). MDT's enemies carry the same id. That is the join.
--
-- IT IS A TYPE MATCH, NOT AN INDIVIDUAL ONE. MDT plans per CLONE - "these two
-- of the four identical mobs over there" - and a live unit only ever tells us
-- what KIND it is. Nothing in the API returns a hostile NPC's map position, so
-- there is no way to tell one clone from another in the world.
--
-- So this says "this mob type is in pull 3, which wants two of them". It does
-- not say "this exact one". That is stated on the panel rather than left to be
-- discovered, and it is the same granularity MDTHelper works at.
--
-- NOTHING HERE TOUCHES BLIZZARD'S NAMEPLATE.
--
-- The badge is our own frame, anchored to the nameplate and nothing more.
-- EllesmereUINameplates decorates the same frames, and two addons writing to
-- one frame is a fight this addon has already had once with the Cooldown
-- Manager. Anchoring is not writing, so there is nothing to fight over.
---------------------------------------------------------------------------
local _, ns = ...

local Routes = {}
ns.Routes = Routes

-- How often the badges are re-checked. Nameplates come and go on their own
-- events; this catches the rest - a pull advancing, a route being edited in
-- MDT while you stand there.
local SWEEP = 0.25

-- How often the route itself is re-read from MDT. Slower than the sweep: MDT
-- announces nothing when you open it, switch dungeon or edit a pull, so this
-- is the only way any of that reaches the badges.
local RESYNC = 2.0

---------------------------------------------------------------------------
-- Reaching MDT
--
-- Every call is guarded and every one of them can be missing. MDT is a big
-- addon that is not always loaded, its API is not a published one, and a
-- version that renames a field must cost this feature and nothing else.
---------------------------------------------------------------------------
-- Named Planner, not MDT: the global IS called MDT, and a local function of
-- the same name reading it would call itself.
local function Planner()
    if type(MDT) ~= "table" then return nil end
    return MDT
end

function Routes:Available()
    return Planner() ~= nil
end

function Routes:UnavailableReason()
    if not Planner() then
        return "Mythic Dungeon Tools is not loaded"
    end
    if not self.dungeonIdx then
        return "MDT has no route for where you are standing"
    end
    if #self.pulls == 0 then
        return "the route MDT has open here has no pulls in it"
    end
    return nil
end

Routes.pulls = {}
Routes.byNpc = {}          -- npcID -> { pull = index, want = how many }
Routes.killed = {}         -- npcID -> how many have died this run
Routes.nameToNpc = {}      -- what the mob is called -> its npcID
Routes.spellToNpc = {}     -- a spell only one enemy here casts -> its npcID
Routes.plateNpc = {}       -- nameplate unit -> the npcID we worked out for it
Routes.index = 1

---------------------------------------------------------------------------
-- WHICH DUNGEON THE ROUTE IS READ FOR
--
-- Not MDT's db.currentDungeonIdx on its own, and this is the whole reason
-- nothing was being badged.
--
-- That field is the dungeon MDT'S WINDOW is showing, and MDT only follows you
-- into a zone when the window is OPENED: MDT:CheckCurrentZone is called from
-- ShowInterface and from MDT's own init, and from nowhere else - there is no
-- zone event behind it. So: log in, walk into a dungeon, never open MDT, and
-- MDT is still holding whichever dungeon it had last.
--
-- Reading that blindly is the quiet way to be wrong. A route for ANOTHER
-- dungeon parses perfectly, has pulls, has colours - and its npcIDs match
-- nothing standing in front of you. Nothing is badged and there is no error
-- to see, which is exactly what "I see no badges" looked like.
--
-- So the ZONE decides. MDT's own choice is the fallback, for standing outside
-- a dungeon with the planner open on one.
---------------------------------------------------------------------------
function Routes:DungeonIdx()
    local addon = Planner()
    if not addon then return nil, nil end

    local map = C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetBestMapForUnit("player") or nil
    if map and type(addon.zoneIdToDungeonIdx) == "table" then
        -- MDT keys this by uiMapID and registers every sublevel of a dungeon,
        -- which is why the floor you are on resolves as well as the entrance.
        -- Read off MDT:CheckCurrentZone, which uses the same two calls.
        local zoneIdx = addon.zoneIdToDungeonIdx[map]
        if zoneIdx then return zoneIdx, "zone" end
    end

    local ok, db = pcall(function() return addon.GetDB and addon:GetDB() end)
    if ok and type(db) == "table" and db.currentDungeonIdx then
        return db.currentDungeonIdx, "mdt"
    end
    return nil, nil
end

-- The route MDT has chosen FOR THAT DUNGEON. MDT:GetCurrentPreset() would
-- answer for the open one instead, so the same lookup is done by hand:
-- db.presets[idx][db.currentPreset[idx]].
function Routes:PresetFor(dungeonIdx)
    local addon = Planner()
    if not (addon and dungeonIdx) then return nil end
    local ok, db = pcall(function() return addon.GetDB and addon:GetDB() end)
    if not (ok and type(db) == "table") then return nil end

    local presets = db.presets and db.presets[dungeonIdx]
    local chosen = db.currentPreset and db.currentPreset[dungeonIdx]
    if type(presets) ~= "table" or not chosen then return nil end
    return presets[chosen]
end

function Routes:DungeonName(dungeonIdx)
    local addon = Planner()
    local list = addon and addon.dungeonList
    if type(list) ~= "table" then return nil end
    return list[dungeonIdx or self.dungeonIdx or 0]
end

---------------------------------------------------------------------------
-- Reading the route
--
-- The shape is MDT's, read off MDTHelper's own RebuildPullData, which is the
-- working example of this and is installed:
--
--   MDT:GetCurrentPreset().value.pulls   an ORDERED array of pulls
--   pull.color                           {r,g,b} - MDT already has the colour
--   pull[enemyIdx]                       a table of clone indices
--   MDT.dungeonEnemies[dungeonIdx][enemyIdx].id      the npcID
--                                       .count      forces
--                                       .name
---------------------------------------------------------------------------
function Routes:Sync()
    local addon = Planner()
    wipe(self.pulls)
    wipe(self.byNpc)
    wipe(self.nameToNpc)
    self.dungeonIdx = nil
    self.dungeonFrom = nil
    self.presetName = nil
    if not addon then return false end

    -- The zone first, MDT's open window second. See Routes:DungeonIdx.
    local dungeonIdx, from = self:DungeonIdx()
    if not dungeonIdx then return false end

    local enemies = addon.dungeonEnemies and addon.dungeonEnemies[dungeonIdx]
    if type(enemies) ~= "table" then return false end

    local preset = self:PresetFor(dungeonIdx)
    if type(preset) ~= "table" then return false end
    local pulls = preset.value and preset.value.pulls
    if type(pulls) ~= "table" then return false end

    self.dungeonIdx = dungeonIdx
    self.dungeonFrom = from
    self.presetName = preset.text

    -- What the whole dungeon is worth, so a pull's forces can be turned into
    -- a share of the counter the game keeps.
    local totals = addon.dungeonTotalCount and addon.dungeonTotalCount[dungeonIdx]
    self.dungeonForces = type(totals) == "table" and totals.normal or nil

    -- WHAT EACH MOB IS CALLED, for the days the GUID cannot be read.
    --
    -- Built from every enemy in the dungeon rather than only the ones in the
    -- route, so a mob that is genuinely not in your pulls can be told apart
    -- from one we simply failed to identify. Names go through MDT's own
    -- translation table, the way MDTHelper does it - MDT stores them in
    -- English and MDT.L holds the client's language.
    --
    -- FIRST ID WINS on a shared name. Two npcIDs can be called the same
    -- thing; a name can only point at one of them, and this path is the
    -- fallback rather than the truth.
    local L = addon.L
    for _, enemy in pairs(enemies) do
        if enemy and enemy.id and enemy.name then
            local shown = (L and L[enemy.name]) or enemy.name
            if self.nameToNpc[shown] == nil then
                self.nameToNpc[shown] = enemy.id
            end
        end
    end

    -- WHAT EACH MOB CASTS, which may be the last door left.
    --
    -- MDT records the spells every enemy uses, and across all of its dungeons
    -- 666 of 701 distinct spells - 95% - belong to exactly ONE enemy. A mob
    -- that casts therefore names itself, without the game having to say what
    -- it is.
    --
    -- ONLY THE UNAMBIGUOUS ONES ARE KEPT. A spell two enemies share is thrown
    -- away rather than guessed at: a badge on the wrong pack is worse than no
    -- badge, because it is acted on.
    wipe(self.spellToNpc)
    wipe(self.plateNpc)
    local owner = {}
    for _, enemy in pairs(enemies) do
        if enemy and enemy.id and type(enemy.spells) == "table" then
            for spellID in pairs(enemy.spells) do
                local sid = tonumber(spellID)
                if sid then
                    if owner[sid] == nil then
                        owner[sid] = enemy.id
                    elseif owner[sid] ~= enemy.id then
                        owner[sid] = false
                    end
                end
            end
        end
    end
    for sid, npcID in pairs(owner) do
        if npcID then self.spellToNpc[sid] = npcID end
    end

    for order, pull in ipairs(pulls) do
        local entry = {
            index = order,
            -- MDT'S OWN COLOUR. The whole point: the pull you coloured green
            -- in the planner is green on the mobs. Inventing a palette here
            -- would mean two things called pull 3 that do not look alike.
            color = type(pull.color) == "table"
                and { pull.color[1] or 1, pull.color[2] or 1, pull.color[3] or 1 }
                or { 1, 1, 1 },
            npcs = {},      -- npcID -> how many clones this pull takes
            forces = 0,
            names = {},
        }

        for enemyIdx, clones in pairs(pull) do
            -- "color" is a key on the same table, so the type test is the
            -- guard rather than the key name - MDT may add more of them.
            if enemyIdx ~= "color" and type(clones) == "table" then
                local enemy = enemies[enemyIdx]
                if enemy and enemy.id then
                    local count = 0
                    for _ in pairs(clones) do count = count + 1 end
                    entry.npcs[enemy.id] = (entry.npcs[enemy.id] or 0) + count
                    entry.forces = entry.forces + (enemy.count or 0) * count
                    entry.names[enemy.id] = enemy.name
                end
            end
        end

        -- A pull with nothing in it is a pull MDT is holding open while it is
        -- being built. Kept, so the numbering matches the planner exactly -
        -- an off-by-one against the thing on your second monitor is worse
        -- than an empty row.
        self.pulls[#self.pulls + 1] = entry

        for npcID, want in pairs(entry.npcs) do
            -- FIRST PULL WINS. The same mob type usually appears in several
            -- pulls, and a badge has to say one thing. The earliest pull that
            -- is not finished is the one you are being sent to, so the lookup
            -- is resolved at read time rather than baked in here.
            local seen = self.byNpc[npcID]
            if not seen then self.byNpc[npcID] = {} end
            local list = self.byNpc[npcID]
            list[#list + 1] = { pull = order, want = want }
        end
    end

    if self.index > #self.pulls then self.index = math.max(1, #self.pulls) end
    return true
end

function Routes:Count() return #self.pulls end
function Routes:Get(index) return self.pulls[index] end
function Routes:Current() return self.pulls[self.index] end

function Routes:Step(delta)
    local count = #self.pulls
    if count == 0 then return end
    local next_ = self.index + delta
    if next_ < 1 then next_ = 1 end
    if next_ > count then next_ = count end
    self.index = next_
    self:Sweep()
end

function Routes:SetPull(index)
    self.index = math.max(1, math.min(#self.pulls, index or 1))
    self:Sweep()
end

---------------------------------------------------------------------------
-- Which pull a live mob belongs to
--
-- Pure and exported, because it is the whole rule and the desktop harness can
-- check it without a dungeon: given the pull a mob appears in and how far the
-- run has got, which badge does it wear?
--
--   "current"  it is in the pull you are on
--   "next"     it is in the pull after it
--   nil        it is in neither, so it wears nothing
--
-- Anything further ahead is deliberately unmarked. A screen where half the
-- room is badged is a screen that has stopped telling you anything.
---------------------------------------------------------------------------
function Routes.Standing(pullIndex, currentIndex)
    if not (pullIndex and currentIndex) then return nil end
    if pullIndex == currentIndex then return "current" end
    if pullIndex == currentIndex + 1 then return "next" end
    return nil
end

-- The pull this npcID should be shown as, given where the run is. The
-- EARLIEST pull at or after the current one wins: a mob type used in pulls 2,
-- 5 and 9 is about pull 5 while you are on 5, not about 2 which is done.
function Routes:PullForNpc(npcID)
    local list = self.byNpc[npcID]
    if not list then return nil end

    local best
    for _, entry in ipairs(list) do
        if entry.pull >= self.index and (not best or entry.pull < best.pull) then
            best = entry
        end
    end
    return best and best.pull or nil, best and best.want or nil
end

---------------------------------------------------------------------------
-- The npcID of a live unit
--
-- Field six of the GUID. A plain string split - no arithmetic, nothing
-- secret: a GUID is readable on this patch and it is the one thing about a
-- hostile unit that is.
---------------------------------------------------------------------------
function Routes.NpcFromGUID(guid)
    -- ASKED BEFORE ANYTHING IS DONE WITH IT. A secret value may not be
    -- compared, and the line below compares - so on a patch where anything
    -- read off a unit can come back secret, the type test is not the guard,
    -- this is. MDT's own public API opens with the same question.
    if not ns.CanCompute(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    -- Players have a GUID too and it has no npcID worth reading.
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

---------------------------------------------------------------------------
-- WHICH MOB IS ON A NAMEPLATE, BY WHATEVER MEANS THE CLIENT ALLOWS
--
-- The GUID is the right answer and it is not always available: on this patch
-- UnitGUID can come back as a value an addon may not look at, and in a
-- dungeon it does - all ten nameplates at once, which is what made "no
-- badges" survive two fixes.
--
-- The name is the fallback. MDT stores a name for every enemy and the game
-- will tell us what the thing in front of us is called, so the two can be
-- joined even when the id cannot. It is weaker: two npcIDs can share a name,
-- and only one of them can win. That is why it runs SECOND and never
-- overrides an id that was readable.
--
-- Returns the npcID and how it was found ("id" or "name"), because the
-- diagnostic has to be able to say which - a route working off names is
-- worth knowing about before it surprises somebody.
---------------------------------------------------------------------------
-- The spell a unit is casting or channelling right now, or nil. Guarded like
-- everything else read off a unit: a spell id that may not be looked at may
-- not be a table key either.
function Routes.CastSpell(unit)
    local get = UnitCastingInfo
    if type(get) == "function" then
        local ok, _, _, _, _, _, _, _, _, spellID = pcall(get, unit)
        if ok and ns.CanCompute(spellID) and type(spellID) == "number" then
            return spellID
        end
    end
    get = UnitChannelInfo
    if type(get) == "function" then
        local ok, _, _, _, _, _, _, _, spellID = pcall(get, unit)
        if ok and ns.CanCompute(spellID) and type(spellID) == "number" then
            return spellID
        end
    end
    return nil
end

function Routes:NpcForUnit(unit)
    if not unit then return nil, nil end

    -- Worked out once, kept until the plate is handed to another mob. A mob
    -- only casts now and then, and a badge that appears mid-cast and leaves
    -- again is worse than one that never came.
    local remembered = self.plateNpc[unit]
    if remembered then return remembered, "remembered" end

    local byID = Routes.NpcFromGUID(UnitGUID(unit))
    if byID then return byID, "id" end

    local name = UnitName(unit)
    if ns.CanCompute(name) and type(name) == "string" then
        local byName = self.nameToNpc[name]
        if byName then return byName, "name" end
    end

    -- LAST DOOR: what it is casting. See the spell index in Sync.
    local spellID = Routes.CastSpell(unit)
    if spellID then
        local byCast = self.spellToNpc[spellID]
        if byCast then
            self.plateNpc[unit] = byCast
            return byCast, "cast"
        end
    end
    return nil, nil
end

---------------------------------------------------------------------------
-- The badges
---------------------------------------------------------------------------
local badges = {}          -- nameplate frame -> our badge

local function BuildBadge(plate)
    local badge = CreateFrame("Frame", nil, plate)
    badge:SetFrameStrata("HIGH")
    badge:SetSize(30, 30)

    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bg:SetAllPoints(badge)
    badge.bg:SetColorTexture(1, 1, 1, 1)

    badge.edge = ns.CreateBorder(badge, 2, "BORDER")

    badge.label = badge:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(badge.label, nil, 15, "THICKOUTLINE")
    badge.label:SetPoint("CENTER", badge, "CENTER", 0, 0)

    return badge
end

-- Anchored ABOVE the plate, never onto it. Nothing here writes to a frame
-- Blizzard or another addon owns.
local function PlaceBadge(badge, plate, db)
    badge:ClearAllPoints()
    badge:SetPoint("BOTTOM", plate, "TOP", db.offsetX or 0, db.offsetY or 4)
    badge:SetSize(db.size or 30, db.size or 30)
end

function Routes:HideAll()
    for _, badge in pairs(badges) do badge:Hide() end
end

-- Test mode is deliberately NOT saved. It draws over every nameplate in the
-- world, which is fine for ten seconds in front of a pack and wrong for
-- anything else, and a switch that survives a reload would be found again by
-- accident three days later.
function Routes:SetTesting(on)
    self.testing = on and true or false
    self:Sweep()
end

---------------------------------------------------------------------------
-- EVERY NAMEPLATE ON SCREEN, AND WHICH UNIT IS ON IT
--
-- NOT plate.namePlateUnitToken, which is the obvious way and is wrong here.
-- That field is only reliably set while a NAME_PLATE_UNIT_ADDED event is
-- being handled; polled from a timer - which is exactly what the sweep does -
-- it comes back nil. EllesmereUICooldownManager says so in as many words at
-- line 6972 and walks the tokens instead, and so do BigWigs' nameplate tools.
--
-- That nil was the second half of "no badges": no unit meant no GUID, no
-- GUID meant no npcID, and every badge fell through to the unmatched case.
--
-- So the UNIT is the thing iterated and the plate is asked for by unit.
-- One implementation, because the diagnostic has to walk exactly what the
-- sweep walks or it is describing a different screen.
---------------------------------------------------------------------------
local MAX_PLATES = 40   -- nameplate1..nameplate40 is the range the client hands out

function Routes:ForEachPlate(fn)
    local forUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not forUnit then return 0 end

    local count = 0
    for i = 1, MAX_PLATES do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local plate = forUnit(unit)
            if plate then
                count = count + 1
                fn(unit, plate)
            end
        end
    end
    return count
end

---------------------------------------------------------------------------
-- One pass over every nameplate on screen
---------------------------------------------------------------------------
function Routes:Sweep()
    local db = ns.db and ns.db.routes
    if not db then return end

    self.drawn = 0
    self.plateCount = 0

    -- TEST MODE ignores the route on purpose. "Nothing is marked" is two
    -- questions wearing one face - is the drawing working, and did the route
    -- match anything - and this separates them in one click: every nameplate
    -- gets a badge, route or no route.
    if not (self.testing or (db.enabled and self:Available() and #self.pulls > 0)) then
        self:HideAll()
        return
    end

    local seen = {}
    self.plateCount = self:ForEachPlate(function(unit, plate)
        local npcID = self:NpcForUnit(unit)
        local pullIndex = npcID and self:PullForNpc(npcID)
        local standing = Routes.Standing(pullIndex, self.index)

        -- The NEXT pull is only marked when it was asked for. On a busy pull
        -- it is the difference between a hint and a wall of badges.
        if standing == "next" and not db.showNext then standing = nil end

        if self.testing and not standing then
            standing = "current"
            pullIndex = nil
        end

        if standing then
            local badge = badges[plate]
            if not badge then
                badge = BuildBadge(plate)
                badges[plate] = badge
            end
            seen[badge] = true

            local pull = pullIndex and self:Get(pullIndex)
            local colour = pull and pull.color or { 1, 1, 1 }
            local dim = standing == "next" and (db.nextAlpha or 0.45) or 1

            badge.bg:SetColorTexture(colour[1], colour[2], colour[3],
                (db.alpha or 0.9) * dim)
            badge.edge:SetColor(0, 0, 0, dim)
            badge.label:SetText(db.showNumber ~= false
                and tostring(pullIndex or "?") or "")
            badge.label:SetAlpha(dim)
            PlaceBadge(badge, plate, db)
            badge:Show()
            self.drawn = self.drawn + 1
        end
    end)

    for plate, badge in pairs(badges) do
        if not seen[badge] then badge:Hide() end
        -- A nameplate frame is pooled and reused, never destroyed, so the
        -- badge stays with it rather than being rebuilt on every pull.
        if not plate:IsShown() then badge:Hide() end
    end
end

---------------------------------------------------------------------------
-- Progress
--
-- A pull is finished when everything it wanted has died. The count comes off
-- the combat log, which is the only thing that reports a death we did not
-- have targeted.
--
-- ADVANCING IS A SUGGESTION, NOT A LAW. It moves on by itself when the pull
-- is clear, and the panel has arrows, because a route survives contact with a
-- wipe about as well as any other plan.
---------------------------------------------------------------------------
function Routes:NoteKill(npcID)
    if not npcID then return end
    self.killed[npcID] = (self.killed[npcID] or 0) + 1

    local db = ns.db and ns.db.routes
    if not (db and db.autoAdvance) then return end

    -- IN A KEYSTONE THE FORCES COUNTER IS THE AUTHORITY, and it is already
    -- stepping the route on. Counting deaths as well would advance twice for
    -- one pull and skip the next one. lastForces is only ever set by a
    -- reading that worked, so its presence IS "there is a counter here".
    if self.lastForces ~= nil then return end

    local pull = self:Current()
    if not pull then return end

    for id, want in pairs(pull.npcs) do
        if (self.killed[id] or 0) < want then return end
    end

    -- Everything this pull asked for is down. The kills are NOT wiped: the
    -- same mob type in a later pull is counted from zero for that pull, which
    -- would be wrong, so each pull is measured against the running total it
    -- inherited.
    for id, want in pairs(pull.npcs) do
        self.killed[id] = (self.killed[id] or 0) - want
    end
    if self.index < #self.pulls then
        self.index = self.index + 1
        self:Sweep()
    end
end

---------------------------------------------------------------------------
-- PROGRESS THE WAY THE GAME COUNTS IT
--
-- The enemy forces counter - the 91/591 on your objective tracker - is a far
-- better answer than counting deaths, and for three reasons.
--
-- It needs no GUID, which on this patch is the difference between working and
-- not. It counts a mob a team-mate killed two rooms away, which a nameplate
-- never sees. And it is the number the dungeon itself is scored on, so it
-- cannot drift from what the run actually is.
--
-- This is how MDTHelper does it and it is the only thing MDTHelper does for
-- progress: it has an npcKills table that is wiped and never written to. It
-- does not know which mob is still standing. Neither does anything else -
-- that question is answered here by the nameplate, which is the whole reason
-- this feature exists.
--
-- IT ONLY EXISTS IN A KEYSTONE. A normal dungeon has no weighted criterion,
-- so kill counting stays as the fallback rather than being replaced.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- The counter as a share of the whole, 0..1, out of the string the game
-- writes on the objective tracker.
--
-- Pure and exported because the shape of that string is the one thing here
-- nobody can be sure of from reading: MDTHelper pulls the first run of digits
-- out of it, EllesmereUIMythicTimer strips a percent sign and swaps a comma
-- for a decimal point. Those two cannot both be describing the same string,
-- so both shapes are handled and both are pinned by a test.
---------------------------------------------------------------------------
function Routes.ParseForces(text)
    if type(text) ~= "string" then return nil, nil end

    -- "91/591" - a count against a total.
    local a, b = text:match("(%d+)%s*/%s*(%d+)")
    if a and b and tonumber(b) and tonumber(b) > 0 then
        return tonumber(a) / tonumber(b), "fraction"
    end

    -- "15.40%", or "15,40%" on a client that writes decimals the German way.
    local cleaned = text:gsub("%%", "")
    if cleaned:find(",") and not cleaned:find("%.") then
        cleaned = cleaned:gsub(",", ".")
    end
    local pct = tonumber(cleaned)
    if pct then return pct / 100, "percent" end

    return nil, nil
end

function Routes:ForcesFraction()
    if not (C_Scenario and C_Scenario.GetStepInfo
        and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return nil, "no scenario api"
    end

    local ok, numCriteria = pcall(function()
        return select(3, C_Scenario.GetStepInfo())
    end)
    if not ok or type(numCriteria) ~= "number" then return nil, "no step" end

    for i = 1, numCriteria do
        local got, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if got and type(info) == "table" and info.isWeightedProgress then
            -- The numbers first, because they are exact. They can also be
            -- withheld, which is why the string exists as a second answer.
            local qty, total = info.quantity, info.totalQuantity
            if ns.CanCompute(qty) and ns.CanCompute(total)
                and type(qty) == "number" and type(total) == "number"
                and total > 0 then
                return qty / total, "counted"
            end

            local text = info.quantityString
            if ns.CanCompute(text) and type(text) == "string" then
                local share, shape = Routes.ParseForces(text)
                if share then return share, shape end
                return nil, "unparsed: " .. text
            end
            return nil, "withheld"
        end
    end
    return nil, "no forces here"
end

-- What share of the dungeon this pull is worth, 0..1.
function Routes:PullShare(pull)
    if not (pull and self.dungeonForces and self.dungeonForces > 0) then
        return nil
    end
    return pull.forces / self.dungeonForces
end

-- Called whenever the counter moves. The DELTA is accumulated against the
-- pull you are on, not the absolute total, so stepping back and forth by hand
-- does not make the next pull complete itself.
function Routes:NoteForces(fraction)
    if type(fraction) ~= "number" then return end

    local last = self.lastForces
    self.lastForces = fraction
    if type(last) ~= "number" then return end       -- first reading is a baseline

    local delta = fraction - last
    if delta <= 0 then return end                    -- a reset, or no movement

    local db = ns.db and ns.db.routes
    if not (db and db.autoAdvance) then return end

    self.forcesAccum = (self.forcesAccum or 0) + delta

    local pull = self:Current()
    local share = self:PullShare(pull)
    if not share or share <= 0 then return end

    -- NOT the whole pull. A stray that ran off, a patrol that was already
    -- dead, an add nobody counted - waiting for the last percent of a pull
    -- means never advancing. MDTHelper lands on four fifths as well.
    -- The nudge is not superstition. Underneath these are whole numbers of
    -- forces out of a whole-number total, and the exact case - a pull worth
    -- a tenth, four fifths of it down - lands on 0.07999999999999999 against
    -- 0.08000000000000002. Without it, a pull cleared to precisely the
    -- threshold never advances, which is the one case most likely to happen.
    local threshold = db.forcesThreshold or 0.8
    if self.forcesAccum + 1e-9 < share * threshold then return end

    self.forcesAccum = math.max(0, self.forcesAccum - share)
    if self.index < #self.pulls then
        self.index = self.index + 1
        self:Sweep()
    end
end

function Routes:ResetRun()
    wipe(self.killed)
    self.index = 1
    self.forcesAccum = 0
    self.lastForces = nil
    self:Sweep()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Routes:Start()
    if self.events then return end
    self.events = CreateFrame("Frame")

    for _, event in ipairs({
        "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED",
        "COMBAT_LOG_EVENT_UNFILTERED",
        "PLAYER_ENTERING_WORLD",
        "CHALLENGE_MODE_START",
        -- Walking through the door of the dungeon, and between its floors.
        -- MDT has no zone event of its own, so this is where the route for
        -- the place you are actually standing in gets picked up.
        "ZONE_CHANGED_NEW_AREA",
        -- The enemy forces counter moved. The better half of progress, and
        -- the only half that needs nothing from a unit.
        "SCENARIO_CRITERIA_UPDATE",
        -- A mob naming itself. See Routes.CastSpell and the spell index.
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_CHANNEL_START",
    }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end

    self.events:SetScript("OnEvent", function(_, event, unit, _, spellID)
        -- A plate handed back to the pool must forget what it was, or the
        -- next mob on that token inherits the last one's badge.
        if event == "NAME_PLATE_UNIT_REMOVED" or event == "NAME_PLATE_UNIT_ADDED" then
            if unit then Routes.plateNpc[unit] = nil end
            Routes:Sweep()
            return
        end

        -- A cast is the moment a mob names itself, and it is over in a second
        -- or two - far too short to be caught by a sweep that runs four times
        -- a second and only looks at what is casting right then.
        if event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if type(unit) ~= "string" or not unit:match("^nameplate") then return end
            local id = ns.CanCompute(spellID) and type(spellID) == "number"
                and spellID or Routes.CastSpell(unit)
            local npcID = id and Routes.spellToNpc[id]
            if npcID then
                Routes.plateNpc[unit] = npcID
                Routes:Sweep()
            end
            return
        end

        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- Guarded like every other client call in this addon: the desktop
            -- harness has no combat log, and a missing global must cost this
            -- one feature rather than the file.
            if not CombatLogGetCurrentEventInfo then return end
            -- destName comes along for the same reason the nameplates need
            -- it: the GUID in a combat log line can be withheld too, and a
            -- kill that cannot be counted is a pull that never finishes.
            local _, subEvent, _, _, _, _, _, destGUID, destName =
                CombatLogGetCurrentEventInfo()
            if subEvent ~= "UNIT_DIED" then return end

            local npcID = Routes.NpcFromGUID(destGUID)
            if not npcID and ns.CanCompute(destName)
                and type(destName) == "string" then
                npcID = Routes.nameToNpc[destName]
            end
            Routes:NoteKill(npcID)
            return
        end

        if event == "CHALLENGE_MODE_START" or event == "PLAYER_ENTERING_WORLD" then
            -- A new key is a new run. The route is re-read as well, because
            -- MDT follows you into the dungeon and may only now know which
            -- one you are in.
            Routes:Sync()
            Routes:ResetRun()
            return
        end

        if event == "SCENARIO_CRITERIA_UPDATE" then
            Routes:NoteForces((Routes:ForcesFraction()))
            return
        end

        if event == "ZONE_CHANGED_NEW_AREA" then
            -- Re-read, but the RUN IS NOT RESET: a floor change mid-dungeon
            -- fires this too, and losing which pull you are on halfway down
            -- would be worse than any route it could pick up.
            Routes:Sync()
            Routes:Sweep()
            return
        end

        Routes:Sweep()
    end)

    -- The sweep catches what the events do not: a pull advanced by hand, a
    -- route edited in MDT while you stand in front of the pack.
    self.events:SetScript("OnUpdate", function(_, elapsed)
        -- The route itself is re-read on a slower beat than the badges are
        -- drawn. MDT is a live thing on the other monitor: you open it, pick
        -- the dungeon, edit a pull - and none of that fires an event anyone
        -- outside MDT can hear. Two seconds is below noticing and well above
        -- walking a whole preset four times a second.
        Routes.reread = (Routes.reread or 0) + elapsed
        if Routes.reread >= RESYNC then
            Routes.reread = 0
            local db = ns.db and ns.db.routes
            if db and (db.enabled or Routes.testing) then Routes:Sync() end
        end

        Routes.accum = (Routes.accum or 0) + elapsed
        if Routes.accum < SWEEP then return end
        Routes.accum = 0
        Routes:Sweep()
    end)
end

---------------------------------------------------------------------------
-- WHAT THIS CLIENT WILL TELL US ABOUT A MOB AT ALL
--
-- Written after three trips into a dungeon that each tested one guess. The
-- GUID is withheld; the name is withheld too. Rather than guess a fourth
-- time, this asks EVERY question at once and prints what came back, so one
-- run settles which doors are open.
--
-- MDT stores more than a name for each enemy - id, count (its forces),
-- health, creatureType, level - so any of those that survives is a possible
-- join. Nothing here decides anything; it only reports.
---------------------------------------------------------------------------
local function Describe(ok, value)
    if not ok then return "|cffff4040raised|r" end
    if value == nil then return "|cff888888nil|r" end
    if not ns.CanCompute(value) then return "|cffff8040withheld|r" end
    local kind = type(value)
    if kind == "string" then return string.format("\"%s\"", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    return kind
end

local function Ask(fn, ...)
    if type(fn) ~= "function" then return Describe(true, nil) end
    return Describe(pcall(fn, ...))
end

function Routes:Probe()
    ns.Print("|cffffd100--------- what this client will say about a mob ---------|r")

    ---------------------------------------------------------------------
    -- WHERE THINGS ARE.
    --
    -- Asked first and separately, because it is a different idea from
    -- identity and it may outlive it: if a mob has a POSITION we can read,
    -- then what it is called stops mattering. A coordinate plus a database
    -- we build ourselves is exactly what MDT is - it never asks the game
    -- what a mob is either, it stores where one stands.
    --
    -- So the questions are: can we place the PLAYER, can we place a MOB, and
    -- failing both, is there anything geometric left - a bearing off the
    -- nameplate's position on screen, a coarse distance from an interact
    -- check.
    ---------------------------------------------------------------------
    ns.Print("|cffffd100the player|r")
    if type(UnitPosition) == "function" then
        -- All four, not just the first: x, y and the instance id together are
        -- what a recorded position would consist of, so seeing one of them is
        -- not the same as being able to store a place.
        local ok, x, y, z, inst = pcall(UnitPosition, "player")
        ns.Print("   UnitPosition      " .. Describe(ok, x) .. " / "
            .. Describe(ok, y) .. " / " .. Describe(ok, z)
            .. "  instance " .. Describe(ok, inst))
    else
        ns.Print("   UnitPosition      |cff888888no api|r")
    end
    ns.Print("   facing            " .. Ask(GetPlayerFacing))
    local best = C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetBestMapForUnit("player") or nil
    ns.Print("   map               " .. Describe(true, best))
    if best and C_Map and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, best, "player")
        if ok and type(pos) == "table" and pos.GetXY then
            local got, x, y = pcall(pos.GetXY, pos)
            ns.Print("   map position      " .. Describe(got, x)
                .. " / " .. Describe(got, y))
        else
            ns.Print("   map position      " .. Describe(ok, pos))
        end
    end

    local shown = 0
    self:ForEachPlate(function(unit, plate)
        if shown >= 3 then return end
        shown = shown + 1
        ns.Print("|cffffd100" .. unit .. "|r")

        ns.Print("   UnitName          " .. Ask(UnitName, unit))
        ns.Print("   UnitGUID          " .. Ask(UnitGUID, unit))
        ns.Print("   UnitHealthMax     " .. Ask(UnitHealthMax, unit))
        ns.Print("   UnitLevel         " .. Ask(UnitLevel, unit))
        ns.Print("   UnitCreatureType  " .. Ask(UnitCreatureType, unit))
        ns.Print("   UnitClassification " .. Ask(UnitClassification, unit))

        -- The forces this one mob is worth. MDT stores the same number as
        -- enemy.count, so if it survives it is a join - a coarse one, but a
        -- join. It is also the only unit call MDTHelper trusts in a dungeon.
        local crit = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues
        if crit then
            local ok, value, percent = pcall(crit, unit)
            ns.Print("   criteria value    " .. Describe(ok, value))
            ns.Print("   criteria percent  " .. Describe(ok, percent))
        else
            ns.Print("   criteria value    |cff888888no api|r")
        end

        -- What the nameplate itself is DISPLAYING. The engine draws a name up
        -- there; whether an addon may read it back is a different question
        -- from whether it may ask the unit, and worth knowing.
        -- Every step type-checked. Nameplate frames are decorated by whatever
        -- else is installed, so none of these fields is promised to be what
        -- it looks like - and a diagnostic that raises is worse than useless,
        -- because it fails at the moment its answer is wanted. The desktop
        -- harness threw here on the first run, which is exactly the point.
        local uf = plate and (plate.UnitFrame or plate.unitFrame)
        if type(uf) ~= "table" then uf = nil end
        local fs = uf and uf.name
        if type(fs) == "table" and type(fs.GetText) == "function" then
            ns.Print("   nameplate text    " .. Ask(fs.GetText, fs))
        else
            ns.Print("   nameplate text    |cff888888no such font string|r")
        end

        -- WHAT IS IT CASTING. The last door: MDT records every enemy's
        -- spells and 95% of them belong to exactly one enemy, so a readable
        -- spell id is an identity. Only answers while the mob is casting.
        local spellID = Routes.CastSpell(unit)
        if spellID then
            ns.Print("   casting           " .. tostring(spellID)
                .. (self.spellToNpc[spellID]
                    and (" |cff40ff40-> npc " .. self.spellToNpc[spellID] .. "|r")
                    or " |cff888888(not one of this dungeon's, or shared)|r"))
        elseif type(UnitCastingInfo) == "function" then
            local ok, name = pcall(UnitCastingInfo, unit)
            ns.Print("   casting           " .. (ok and name ~= nil
                and ("|cffff8040casting, but the spell id is " .. Describe(ok, name)
                    .. " and unreadable|r")
                or "|cff888888nothing right now|r"))
        end

        -- CAN WE PLACE THIS MOB. The whole of the coordinate idea rests here.
        ns.Print("   UnitPosition      " .. Ask(UnitPosition, unit))
        if C_Map and C_Map.GetPlayerMapPosition then
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, best or 0, unit)
            ns.Print("   map position      " .. Describe(ok, pos))
        end
        ns.Print("   distance squared  " .. Ask(UnitDistanceSquared, unit))
        -- A coarse ring: true inside about 28 yards. Not a position, but a
        -- real fact about distance if everything else is shut.
        ns.Print("   within ~28y       " .. Ask(CheckInteractDistance, unit, 4))

        -- The nameplate's own geometry. The frame is ours to measure even
        -- when the unit behind it is not: where it sits across the screen is
        -- a BEARING to the mob, and Blizzard scales distant plates, so the
        -- scale is a hint at range. Ugly, but it is geometry the engine has
        -- already computed and has no reason to withhold.
        if plate and type(plate.GetCenter) == "function" then
            local ok, cx, cy = pcall(plate.GetCenter, plate)
            ns.Print("   plate centre      " .. Describe(ok, cx)
                .. " / " .. Describe(ok, cy))
        end
        if plate and type(plate.GetEffectiveScale) == "function" then
            ns.Print("   plate scale       " .. Ask(plate.GetEffectiveScale, plate))
        end
    end)

    if shown == 0 then
        ns.Print("No nameplates. Stand in front of a pack and run it again.")
    end
end

---------------------------------------------------------------------------
-- Diagnosis
--
-- /zs route. What MDT is holding, which pull we think you are on, and what
-- the mobs in front of you resolved to - because "it is not marking anything"
-- has three different causes and they look identical on screen.
---------------------------------------------------------------------------
local function Yes(value) return value and "|cff40ff40yes|r" or "|cffff4040no|r" end

function Routes:Dump()
    ns.Print("|cffffd100----------------------------------------|r")

    -- THE SWITCH FIRST, AND ALWAYS. The old version of this printed a
    -- flawless report - route read, pulls listed, mobs resolved - while the
    -- feature was switched off, and said nothing about the one fact that
    -- explained the empty screen. A diagnostic that can be right and useless
    -- at the same time is not a diagnostic.
    local db = ns.db and ns.db.routes or {}
    ns.Print("Switched on: " .. Yes(db.enabled)
        .. (self.testing and "   |cffffd100TEST MODE|r" or ""))
    if not db.enabled and not self.testing then
        ns.Print("|cffffd100That is the answer|r - |cffffd100/zs|r, M+ and raid stuff, "
            .. "Routes, |cffffd100Show them|r.")
    end

    -- Enemy nameplates. The badge hangs off one; with them off there is
    -- nothing in the world to hang it from, and no amount of route is going
    -- to help.
    local plateCVar = type(GetCVarBool) == "function"
        and GetCVarBool("nameplateShowEnemies") or nil
    if plateCVar ~= nil then
        ns.Print("Enemy nameplates on: " .. Yes(plateCVar))
    end

    if not self:Available() then
        ns.Print("|cffff4040Mythic Dungeon Tools is not loaded.|r")
        return
    end

    ---------------------------------------------------------------------
    -- WHICH DUNGEON, AND WHO DECIDED. The silent wrong answer lives here:
    -- MDT keeps the dungeon its window last showed and only follows you when
    -- it is opened, so a route can be read perfectly and be for somewhere
    -- else entirely.
    ---------------------------------------------------------------------
    local zoneIdx, from = self:DungeonIdx()
    ns.Print(string.format("Dungeon: |cffffd100%s|r |cff888888(%s, %s)|r",
        self:DungeonName(zoneIdx) or ("index " .. tostring(zoneIdx or "-")),
        tostring(zoneIdx or "-"),
        from == "zone" and "from where you are standing"
            or from == "mdt" and "|cffff8040MDT's open window - you are not in a "
                .. "dungeon MDT knows|r"
            or "unknown"))

    local why = self:UnavailableReason()
    if why then
        ns.Print("|cffff4040No route|r - " .. why .. ".")
        ns.Print("Open MDT, pick this dungeon and the route, then "
            .. "|cffffd100/zs route|r again.")
        return
    end

    ns.Print(string.format("|cff40ff40Route read.|r |cffffd100%s|r - %d pulls, "
        .. "on |cffffd100%d|r.", self.presetName or "unnamed",
        #self.pulls, self.index))

    local pull = self:Current()
    if pull then
        for npcID, want in pairs(pull.npcs) do
            ns.Print(string.format("   %s |cff888888%d|r  x%d, %d killed",
                pull.names[npcID] or "?", npcID, want, self.killed[npcID] or 0))
        end
    end

    -- WHICH OF THE TWO WAYS OF MEASURING PROGRESS IS ALIVE. In a keystone the
    -- game's own forces counter drives the route on; outside one there is no
    -- such counter and deaths are counted instead. They are never both on,
    -- and which one it is changes what "it did not advance" means.
    local fraction, readAs = self:ForcesFraction()
    if fraction then
        local share = self:PullShare(pull)
        ns.Print(string.format("Forces: |cffffd100%.1f%%|r of the dungeon "
            .. "|cff888888(read as %s)|r. This pull is worth %s; %s counted "
            .. "since it began.", fraction * 100, readAs,
            share and string.format("%.1f%%", share * 100) or "?",
            string.format("%.1f%%", (self.forcesAccum or 0) * 100)))
    else
        ns.Print(string.format("Forces: |cff888888none - %s.|r Pulls step on "
            .. "by counting kills here.", tostring(readAs)))
    end

    -- The SAME walk the sweep does. A diagnostic that finds its nameplates a
    -- different way is describing a different screen, and this one already
    -- did once: it read plate.namePlateUnitToken, which is nil when polled.
    local lines = {}
    local matched, unreadable, byName = 0, 0, 0
    local secretGuids, oddGuids = 0, 0

    -- WHAT THE NAME PATH ACTUALLY SAW, for the first nameplate it failed on.
    --
    -- "0 found by name" has three causes that look identical from outside:
    -- the index was never built, the client withholds the name as well, or
    -- the name it gives is spelled differently from the one MDT stores. This
    -- says which, in one line, and it goes at the bottom where a chat window
    -- cannot scroll it away.
    local probe
    local indexed = 0
    for _ in pairs(self.nameToNpc) do indexed = indexed + 1 end
    local plateCount = self:ForEachPlate(function(unit)
        local guid = UnitGUID(unit)
        local npcID, how = self:NpcForUnit(unit)
        local pullIndex = npcID and self:PullForNpc(npcID)
        if pullIndex then matched = matched + 1 end
        if how == "name" then byName = byName + 1 end

        -- WHY the id could not be read, not just that it could not. Secret,
        -- absent and malformed are three different faults with three
        -- different answers, and one message for all of them sent this
        -- investigation down the wrong road once already.
        local trouble
        if not ns.CanCompute(guid) then
            if guid ~= nil then
                trouble = "the client will not let us look at its GUID"
                secretGuids = secretGuids + 1
            end
        elseif type(guid) ~= "string" then
            trouble = "its GUID is a " .. type(guid)
            oddGuids = oddGuids + 1
        elseif not Routes.NpcFromGUID(guid) then
            trouble = "its GUID has no npc id in it"
            oddGuids = oddGuids + 1
        end
        if trouble and not npcID then unreadable = unreadable + 1 end

        if not npcID and not probe then
            local name = UnitName(unit)
            if not ns.CanCompute(name) then
                probe = "the client will not give us its name either"
            elseif type(name) ~= "string" then
                probe = "its name came back as a " .. type(name)
            else
                probe = string.format("its name is \"%s\", which is %s this "
                    .. "dungeon's list", name,
                    self.nameToNpc[name] and "IN" or "|cffff4040NOT in|r")
            end
        end

        local verdict
        if pullIndex then
            verdict = "pull " .. pullIndex
                .. (how == "name" and " |cffff8040(by name)|r" or "")
        elseif npcID then
            verdict = "|cff888888not in the route|r"
                .. (how == "name" and " |cffff8040(by name)|r" or "")
        elseif trouble then
            verdict = "|cffff8040" .. trouble .. ", and its name is not in "
                .. "this dungeon's list|r"
        else
            verdict = "|cff888888not in the route|r"
        end
        lines[#lines + 1] = string.format("   %s |cff888888%s|r - %s",
            UnitName(unit) or "?", tostring(npcID or "-"), verdict)
    end)

    -- Collected first, printed after: the count belongs above the list, and
    -- it is not known until the walk is done.
    ns.Print(string.format("Nameplates on screen: |cffffd100%d|r, badges "
        .. "drawn: |cffffd100%d|r%s", plateCount, self.drawn or 0,
        self.testing and "  |cffff8040(test mode badges everything - that "
            .. "number is not a route match)|r" or ""))
    for _, line in ipairs(lines) do ns.Print(line) end

    if plateCount == 0 then
        ns.Print("|cffffd100No nameplates|r - stand in front of a pack, in "
            .. "combat or not, and run this again.")
        return
    end

    -- THE VERDICT, LAST AND IN ONE LINE.
    --
    -- Deliberately at the bottom. The per-nameplate list is the evidence and
    -- it is as long as the pack; a chat window shows the tail, and the answer
    -- has to be in the part that survives. It is also the one sentence worth
    -- pasting to somebody else.
    if secretGuids > 0 then
        ns.Print(string.format("|cff888888%d GUID(s) withheld by the client; "
            .. "%d mob(s) found by name instead.|r", secretGuids, byName))
    end
    if probe then
        ns.Print(string.format("Names: |cffffd100%d|r known in this dungeon. "
            .. "The first one we could not place - %s.", indexed, probe))
    end
    if oddGuids > 0 then
        ns.Print(string.format("|cffff8040%d GUID(s) were readable but had no "
            .. "npc id.|r", oddGuids))
    end

    if matched > 0 then
        ns.Print(string.format("|cff40ff40%d of %d nameplates are in this "
            .. "route.|r", matched, plateCount))
    elseif unreadable > 0 then
        ns.Print(string.format("|cffff4040None matched. %d could not be "
            .. "identified at all|r - neither GUID nor name. Everything else "
            .. "here is working; that is the client.", unreadable))
    else
        ns.Print("|cffff4040None of these mobs are in the route.|r Right "
            .. "dungeon, wrong pack - or the pull you are on is further along "
            .. "than you are.")
    end

    -- When NOTHING could be identified, the next question is always "what
    -- CAN we read then", so it is answered here rather than waiting to be
    -- asked. /zs probe runs it on its own.
    if matched == 0 and plateCount > 0 and unreadable == plateCount then
        self:Probe()
    end
end
