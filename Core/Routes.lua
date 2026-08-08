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
        return "MDT has no dungeon open"
    end
    if #self.pulls == 0 then
        return "the open MDT route has no pulls in it"
    end
    return nil
end

Routes.pulls = {}
Routes.byNpc = {}          -- npcID -> { pull = index, want = how many }
Routes.killed = {}         -- npcID -> how many have died this run
Routes.index = 1

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
    self.dungeonIdx = nil
    if not addon then return false end

    -- Which dungeon MDT is showing. Asked rather than assumed: MDT keeps
    -- whatever was open last, and a route for another dungeon marked on these
    -- mobs would be confidently wrong.
    local ok, db = pcall(function() return addon.GetDB and addon:GetDB() end)
    if not (ok and type(db) == "table" and db.currentDungeonIdx) then return false end
    local dungeonIdx = db.currentDungeonIdx

    local enemies = addon.dungeonEnemies and addon.dungeonEnemies[dungeonIdx]
    if type(enemies) ~= "table" then return false end

    local gotPreset, preset = pcall(function()
        return addon.GetCurrentPreset and addon:GetCurrentPreset()
    end)
    if not (gotPreset and type(preset) == "table") then return false end
    local pulls = preset.value and preset.value.pulls
    if type(pulls) ~= "table" then return false end

    self.dungeonIdx = dungeonIdx

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
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    -- Players have a GUID too and it has no npcID worth reading.
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
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

---------------------------------------------------------------------------
-- One pass over every nameplate on screen
---------------------------------------------------------------------------
function Routes:Sweep()
    local db = ns.db and ns.db.routes
    if not db then return end

    if not (db.enabled and self:Available() and #self.pulls > 0) then
        self:HideAll()
        return
    end

    local plates = C_NamePlate and C_NamePlate.GetNamePlates
        and C_NamePlate.GetNamePlates() or nil
    if not plates then return end

    local seen = {}
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken
        local npcID = unit and Routes.NpcFromGUID(UnitGUID(unit))
        local pullIndex = npcID and self:PullForNpc(npcID)
        local standing = Routes.Standing(pullIndex, self.index)

        -- The NEXT pull is only marked when it was asked for. On a busy pull
        -- it is the difference between a hint and a wall of badges.
        if standing == "next" and not db.showNext then standing = nil end

        if standing then
            local badge = badges[plate]
            if not badge then
                badge = BuildBadge(plate)
                badges[plate] = badge
            end
            seen[badge] = true

            local pull = self:Get(pullIndex)
            local colour = pull and pull.color or { 1, 1, 1 }
            local dim = standing == "next" and (db.nextAlpha or 0.45) or 1

            badge.bg:SetColorTexture(colour[1], colour[2], colour[3],
                (db.alpha or 0.9) * dim)
            badge.edge:SetColor(0, 0, 0, dim)
            badge.label:SetText(db.showNumber ~= false and tostring(pullIndex) or "")
            badge.label:SetAlpha(dim)
            PlaceBadge(badge, plate, db)
            badge:Show()
        end
    end

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

function Routes:ResetRun()
    wipe(self.killed)
    self.index = 1
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
    }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end

    self.events:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- Guarded like every other client call in this addon: the desktop
            -- harness has no combat log, and a missing global must cost this
            -- one feature rather than the file.
            if not CombatLogGetCurrentEventInfo then return end
            local _, subEvent, _, _, _, _, _, destGUID =
                CombatLogGetCurrentEventInfo()
            if subEvent == "UNIT_DIED" then
                Routes:NoteKill(Routes.NpcFromGUID(destGUID))
            end
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

        Routes:Sweep()
    end)

    -- The sweep catches what the events do not: a pull advanced by hand, a
    -- route edited in MDT while you stand in front of the pack.
    self.events:SetScript("OnUpdate", function(_, elapsed)
        Routes.accum = (Routes.accum or 0) + elapsed
        if Routes.accum < SWEEP then return end
        Routes.accum = 0
        Routes:Sweep()
    end)
end

---------------------------------------------------------------------------
-- Diagnosis
--
-- /zs route. What MDT is holding, which pull we think you are on, and what
-- the mobs in front of you resolved to - because "it is not marking anything"
-- has three different causes and they look identical on screen.
---------------------------------------------------------------------------
function Routes:Dump()
    ns.Print("|cffffd100----------------------------------------|r")

    local why = self:UnavailableReason()
    if why then
        ns.Print("|cffff4040No route|r - " .. why .. ".")
        if self:Available() then
            ns.Print("Open the dungeon and the route in MDT, then |cffffd100/zs route|r again.")
        end
        return
    end

    ns.Print(string.format("|cff40ff40Route read.|r %d pulls, on |cffffd100%d|r.",
        #self.pulls, self.index))

    local pull = self:Current()
    if pull then
        for npcID, want in pairs(pull.npcs) do
            ns.Print(string.format("   %s |cff888888%d|r  x%d, %d killed",
                pull.names[npcID] or "?", npcID, want, self.killed[npcID] or 0))
        end
    end

    local plates = C_NamePlate and C_NamePlate.GetNamePlates
        and C_NamePlate.GetNamePlates() or {}
    ns.Print(string.format("Nameplates on screen: |cffffd100%d|r", #plates))
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken
        local npcID = unit and Routes.NpcFromGUID(UnitGUID(unit))
        local pullIndex = npcID and self:PullForNpc(npcID)
        ns.Print(string.format("   %s |cff888888%s|r - %s",
            unit and UnitName(unit) or "?", tostring(npcID or "-"),
            pullIndex and ("pull " .. pullIndex) or "|cff888888not in the route|r"))
    end
end
