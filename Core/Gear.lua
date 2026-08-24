---------------------------------------------------------------------------
-- WHAT EVERYBODY IS WEARING
--
-- Owner, 2026-08-23, about MRT: it "kann beim gruppen check die item level,
-- vz, gear, food alles abfragen ohne das die addons alle haben muessen" -
-- and for gear he is right. An inspect never needed an addon on the other
-- side: the server answers it for ANY group member, and the answer carries
-- the item links, the item level and the talents. Read from MRT/Inspect.lua
-- on this machine, which is maintained against the live game.
--
-- WHAT THIS FILE IS NOT. It does not talk to the server itself. Core/Specs.lua
-- owns the inspect channel - one question in flight, a throttle the server
-- respects, and the guard that yields the wire to the player's own inspect
-- window (b9ty's blank equipment slots). This file rides that queue: it says
-- WHO it wants, and it harvests whenever an answer lands - answers that were
-- asked for a spec included, because the same answer carries both and asking
-- twice for one person would be waste.
--
-- IT FAILS OPEN. nil means "not read yet" and never "naked": somebody out of
-- range stays an empty card until they walk over, and no cell invents a
-- number in the moment somebody would believe it.
---------------------------------------------------------------------------
local _, ns = ...

local Gear = {}
ns.Gear = Gear

---------------------------------------------------------------------------
-- The slots, in the order a character sheet reads. The labels are the
-- game's own globals - localized by the client, not by us. 4 is the shirt
-- and 19 the tabard; neither says anything about being ready.
---------------------------------------------------------------------------
Gear.SLOTS = {
    { id = 1,  global = "HEADSLOT" },
    { id = 2,  global = "NECKSLOT" },
    { id = 3,  global = "SHOULDERSLOT" },
    { id = 15, global = "BACKSLOT" },
    { id = 5,  global = "CHESTSLOT" },
    { id = 9,  global = "WRISTSLOT" },
    { id = 10, global = "HANDSSLOT" },
    { id = 6,  global = "WAISTSLOT" },
    { id = 7,  global = "LEGSSLOT" },
    { id = 8,  global = "FEETSLOT" },
    { id = 11, global = "FINGER0SLOT" },
    { id = 12, global = "FINGER1SLOT" },
    { id = 13, global = "TRINKET0SLOT" },
    { id = 14, global = "TRINKET1SLOT" },
    { id = 16, global = "MAINHANDSLOT" },
    { id = 17, global = "SECONDARYHANDSLOT" },
}

function Gear.SlotLabel(entry)
    local name = entry and entry.global and _G[entry.global]
    if type(name) == "string" and name ~= "" then return name end
    return entry and entry.global or "?"
end

-- Which slots take an enchant THIS season. Read from MRT's InspectViewer
-- (isSlotForEnchant, the Midnight block) rather than remembered: head,
-- shoulder, chest, legs, feet, both rings and the main hand. NOT the back,
-- wrist, hands or neck - those enchants belong to older expansions.
Gear.ENCHANTABLE = {
    [1] = true, [3] = true, [5] = true, [7] = true, [8] = true,
    [11] = true, [12] = true, [16] = true,
}

-- The off hand counts only when it is a WEAPON. MRT answers this with a
-- hand-kept list of specs; the item in the slot answers it without one - a
-- shield or a held frill takes no weapon enchant, a second blade does.
function Gear.OffhandWantsEnchant(link)
    if type(link) ~= "string" then return false end
    local read = (C_Item and C_Item.GetItemInfoInstant)
        or GetItemInfoInstant
    if type(read) ~= "function" then return false end
    local ok, _, _, _, _, _, classID = pcall(read, link)
    return (ok and classID == 2) and true or false
end

---------------------------------------------------------------------------
-- READING ONE LINK. Pure, and the shape every judgement stands on:
-- item:itemID:enchantID:gem1:gem2:gem3:gem4 - an empty field between the
-- colons is "none", which is a fact, not a failure.
---------------------------------------------------------------------------
function Gear.LinkFacts(link)
    if type(link) ~= "string" then return nil end
    local itemID, enchant, g1, g2, g3, g4 =
        link:match("item:(%d*):(%d*):(%d*):(%d*):(%d*):(%d*)")
    if not itemID or itemID == "" then return nil end

    local gems = 0
    if g1 ~= "" and g1 ~= "0" then gems = gems + 1 end
    if g2 ~= "" and g2 ~= "0" then gems = gems + 1 end
    if g3 ~= "" and g3 ~= "0" then gems = gems + 1 end
    if g4 ~= "" and g4 ~= "0" then gems = gems + 1 end

    return {
        item = tonumber(itemID),
        enchanted = (enchant ~= "" and enchant ~= "0") and true or false,
        gems = gems,
    }
end

-- How many enchants are missing across a read set of slots. Pure. The off
-- hand is judged by what is IN it, so the rule needs the links, not just
-- the slot ids.
function Gear.MissingEnchants(slots)
    if type(slots) ~= "table" then return nil end
    local missing = 0
    for id, facts in pairs(slots) do
        local wants = Gear.ENCHANTABLE[id]
            or (id == 17 and Gear.OffhandWantsEnchant(facts.link))
        if wants and not facts.enchanted then missing = missing + 1 end
    end
    return missing
end

---------------------------------------------------------------------------
-- WHAT HAS BEEN READ, by GUID - party3 is a different person after somebody
-- leaves, a GUID never is.
---------------------------------------------------------------------------
local known = {}

local listeners = {}

function Gear.OnLearned(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

function Gear.Of(guid)
    return guid and known[guid] or nil
end

function Gear.Forget(guid)
    if guid then
        known[guid] = nil
    else
        for key in pairs(known) do known[key] = nil end
    end
end

local function Now()
    return (GetTime and GetTime()) or 0
end

---------------------------------------------------------------------------
-- THE HARVEST. Called with a unit whose inspect answer is present - either
-- our own character, whose gear is always readable, or a unit the Specs
-- queue was just answered about.
---------------------------------------------------------------------------
local function ReadSlots(unit)
    local slots = {}
    local incomplete = false
    for _, entry in ipairs(Gear.SLOTS) do
        local okID, itemID = pcall(GetInventoryItemID, unit, entry.id)
        local okLink, link = pcall(GetInventoryItemLink, unit, entry.id)
        local facts = okLink and Gear.LinkFacts(link) or nil
        if facts then
            facts.link = link
            if C_Item and C_Item.GetDetailedItemLevelInfo then
                local okIlvl, ilvl =
                    pcall(C_Item.GetDetailedItemLevelInfo, link)
                if okIlvl and type(ilvl) == "number" and ilvl > 0 then
                    facts.ilvl = ilvl
                end
            end
            slots[entry.id] = facts
        elseif okID and itemID then
            -- The slot HOLDS something and the link has not arrived from
            -- the item cache yet. That is the difference between "empty"
            -- and "not read", and only one of the two may say 0 enchants.
            incomplete = true
        end
    end
    return slots, incomplete
end

local function ReadAverage(unit, own)
    if own then
        if type(GetAverageItemLevel) ~= "function" then return nil end
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and type(equipped) == "number" and equipped > 0 then
            return math.floor(equipped + 0.5)
        end
        return nil
    end
    local read = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
    if type(read) ~= "function" then return nil end
    local ok, level = pcall(read, unit)
    if ok and type(level) == "number" and level > 0 then
        return math.floor(level + 0.5)
    end
    return nil
end

-- The hero tree's name, off the trait tree the answer carries. A walk over
-- every node, because the game offers no shorter question; once per inspect
-- and guarded throughout - a client without C_Traits answers "not read".
local function ReadHeroName(configID)
    if type(configID) ~= "number" then return nil end
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes
        and C_Traits.GetNodeInfo and C_Traits.GetSubTreeInfo) then
        return nil
    end
    local okConfig, config = pcall(C_Traits.GetConfigInfo, configID)
    local treeID = okConfig and type(config) == "table"
        and type(config.treeIDs) == "table" and config.treeIDs[1] or nil
    if not treeID then return nil end
    local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
    if not (okNodes and type(nodes) == "table") then return nil end
    for _, nodeID in ipairs(nodes) do
        local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if okNode and type(node) == "table"
            and node.subTreeID and node.subTreeActive then
            local okSub, sub =
                pcall(C_Traits.GetSubTreeInfo, configID, node.subTreeID)
            if okSub and type(sub) == "table"
                and type(sub.name) == "string" and sub.name ~= "" then
                return sub.name
            end
        end
    end
    return nil
end

local function ReadTalents(unit, own)
    local loadout, hero

    if own then
        local getConfig = C_ClassTalents and C_ClassTalents.GetActiveConfigID
        if getConfig then
            local ok, configID = pcall(getConfig)
            if ok and type(configID) == "number" then
                if C_Traits and C_Traits.GenerateImportString then
                    local okString, text =
                        pcall(C_Traits.GenerateImportString, configID)
                    if okString and type(text) == "string" and text ~= "" then
                        loadout = text
                    end
                end
                hero = ReadHeroName(configID)
            end
        end
    else
        if C_Traits and C_Traits.GenerateInspectImportString then
            local ok, text =
                pcall(C_Traits.GenerateInspectImportString, unit)
            if ok and type(text) == "string" and text ~= "" then
                loadout = text
            end
        end
        local inspectConfig = Constants and Constants.TraitConsts
            and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
        hero = ReadHeroName(inspectConfig)
    end

    return loadout, hero
end

function Gear.Harvest(unit, guid, secondPass)
    if not unit then return nil end
    guid = guid or (UnitGUID and UnitGUID(unit))
    -- A guid this client withholds must not become a table key - that exact
    -- write is what broke 1.0.0.
    if not ns.CanCompute(guid) then return nil end

    local own = UnitIsUnit and ns.Truth(UnitIsUnit(unit, "player"), false)
        or false

    local slots, incomplete = ReadSlots(unit)

    -- THE SECOND LOOK CAN BE BLIND. By the time it runs, the inspect
    -- snapshot has usually been handed back - Specs clears it the moment
    -- the answer is absorbed - and a blind read answers "nothing worn",
    -- which must never replace the real slots the first pass banked. A
    -- second pass may only ADD: one that saw less is thrown away, and
    -- what it answers nil about keeps its first-pass answer.
    local before = known[guid]
    if secondPass and before and before.slots then
        local had, has = 0, 0
        for _ in pairs(before.slots) do had = had + 1 end
        for _ in pairs(slots) do has = has + 1 end
        if has < had then return before end
    end

    local loadout, hero = ReadTalents(unit, own)
    local carry = secondPass and before or nil

    local data = {
        at = Now(),
        ilvl = ReadAverage(unit, own) or (carry and carry.ilvl) or nil,
        slots = slots,
        -- Published only once the item cache has answered for everything
        -- worn AND anything was readable at all: a count taken while links
        -- are still arriving reads as "0 missing" about slots it never saw,
        -- and one taken over nothing would say it about a person this
        -- client knows nothing about.
        vz = (not incomplete and next(slots) ~= nil)
            and Gear.MissingEnchants(slots) or nil,
        loadout = loadout or (carry and carry.loadout) or nil,
        hero = hero or (carry and carry.hero) or nil,
    }
    known[guid] = data

    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, guid)
        if not ok then geterrorhandler()(err) end
    end

    -- ONE second look, not a loop: the links the cache had not served yet
    -- are usually there a moment later - MRT waits the same beat. The unit
    -- token is re-checked against the GUID because party3 may be somebody
    -- else by then.
    if incomplete and not secondPass and C_Timer and C_Timer.After then
        C_Timer.After(1.3, function()
            local held = UnitGUID and UnitGUID(unit)
            if ns.CanCompute(held) and held == guid then
                Gear.Harvest(unit, guid, true)
            end
        end)
    end

    return data
end

---------------------------------------------------------------------------
-- WANTING. The player is read on the spot - his own links never need the
-- server. Everybody else goes through the Specs queue, which owns the
-- inspect channel and its manners.
---------------------------------------------------------------------------
function Gear.Want(unit)
    if not unit then return end
    local guid = UnitGUID and UnitGUID(unit)
    if not ns.CanCompute(guid) then return end

    if UnitIsUnit and ns.Truth(UnitIsUnit(unit, "player"), false) then
        if not known[guid] then Gear.Harvest(unit, guid) end
        return
    end

    if known[guid] then return end
    if ns.Specs and ns.Specs.WantGear then ns.Specs.WantGear(unit) end
end

-- A fresh look at one person, on purpose: the card's refresh. Forgetting
-- first means the card honestly says "reading" instead of showing the old
-- gear under a new request.
function Gear.Refresh(unit)
    if not unit then return end
    local guid = UnitGUID and UnitGUID(unit)
    if not ns.CanCompute(guid) then return end
    Gear.Forget(guid)
    if UnitIsUnit and ns.Truth(UnitIsUnit(unit, "player"), false) then
        Gear.Harvest(unit, guid)
        return
    end
    if ns.Specs and ns.Specs.WantGear then ns.Specs.WantGear(unit) end
end

-- Harvest every answer the Specs queue receives - the wire carried the gear
-- whether the question was about a spec or not.
if ns.Specs and ns.Specs.OnAnswered then
    ns.Specs.OnAnswered(function(guid, unit)
        Gear.Harvest(unit, guid)
    end)
end

---------------------------------------------------------------------------
-- STALENESS. Event-driven, not a clock: gear changes announce themselves.
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local guid = UnitGUID and UnitGUID("player")
        if ns.CanCompute(guid) then
            known[guid] = nil
            Gear.Harvest("player", guid)
        end
        return
    end

    -- Both remaining events name a unit. What was read about them is stale;
    -- it is forgotten rather than re-asked, and the next Want asks again.
    -- CanCompute FIRST - a bare boolean test on a withheld guid raises.
    local guid = arg1 and UnitGUID and UnitGUID(arg1)
    if ns.CanCompute(guid) then known[guid] = nil end
end)
