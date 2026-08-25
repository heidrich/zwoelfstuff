---------------------------------------------------------------------------
-- WHAT EVERYBODY IS WEARING
--
-- Owner, 2026-08-23, about MRT: it "kann beim gruppen check die item level,
-- vz, gear, food alles abfragen ohne das die addons alle haben muessen" -
-- and for gear they are right. An inspect never needed an addon on the other
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

-- Which spell one tree entry stands for. The chain is the one MRT walks:
-- entry, its definition, the definition's spell.
local function EntrySpell(configID, entryID)
    if not entryID then return nil end
    local okEntry, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
    local definitionID = okEntry and type(entry) == "table"
        and entry.definitionID or nil
    if not definitionID then return nil end
    local okDef, def = pcall(C_Traits.GetDefinitionInfo, definitionID)
    if okDef and type(def) == "table"
        and type(def.spellID) == "number" then
        return def.spellID
    end
    return nil
end

-- Which spell a chosen node stands for: its active entry's.
local function NodeSpell(configID, node)
    if not (C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
        return nil
    end
    local entryID = type(node.activeEntry) == "table"
        and node.activeEntry.entryID
        or (type(node.entryIDs) == "table" and node.entryIDs[1])
    return EntrySpell(configID, entryID)
end

---------------------------------------------------------------------------
-- THE BOARD ITSELF - every node of a tree, where it sits and what joins it
--
-- Owner, 2026-08-25: "muessen wir die talentbaeume noch richtig darstellen."
-- The first drawing placed only the CHOSEN nodes and stretched them across
-- the panel, so the picture's shape came from the BUILD rather than from the
-- tree: a dense corner clumped into touching rows, two people's boards could
-- not be compared, and there was no way to see what somebody had walked
-- past. A talent tree is read by its holes as much as by its icons.
--
-- So the geometry is read whole and kept: the nodes, their places, and the
-- lines between them. It belongs to the TREE and not to the player, which is
-- why it is cached - otherwise a hundred-node walk would be paid again for
-- every single group member. MRT caches the same thing for the same reason.
---------------------------------------------------------------------------
local boards = {}

-- For the desk, and for a client that changed trees under us.
function Gear.ForgetBoards() boards = {} end

-- WHERE THE HERO TREE GOES. Its nodes carry their own origin, so they are
-- re-based onto it and then dropped into the empty middle column between the
-- class half and the spec half - which is where the game itself draws them,
-- and where MRT puts them for the same reason. A subtree we cannot re-base
-- keeps its own coordinates rather than being moved by a guess.
local function PlaceHero(board, configID, minX, maxX, minY, maxY)
    local origins = {}
    for _, node in ipairs(board.nodes) do
        if node.sub then
            local origin = origins[node.sub]
            if origin == nil then
                origin = false
                if C_Traits and C_Traits.GetSubTreeInfo then
                    local ok, info = pcall(C_Traits.GetSubTreeInfo,
                        configID, node.sub)
                    if ok and type(info) == "table"
                        and type(info.posX) == "number"
                        and type(info.posY) == "number" then
                        origin = { info.posX, info.posY }
                    end
                end
                origins[node.sub] = origin
            end
            if origin then
                node.x = minX + (maxX - minX) * 0.5 + (node.x - origin[1])
                node.y = minY + (maxY - minY) * 0.35 + (node.y - origin[2])
            end
        end
    end
end

local function FinishBoard(board, configID)
    -- THE EXTENT IS THE CLASS AND SPEC HALVES, hero nodes left out: they are
    -- about to be moved INTO that extent, and letting them set it first
    -- would scale the whole tree around wherever their own tree happens to
    -- live in the coordinate space.
    local minX, maxX, minY, maxY
    for _, node in ipairs(board.nodes) do
        if not node.sub then
            if not minX or node.x < minX then minX = node.x end
            if not maxX or node.x > maxX then maxX = node.x end
            if not minY or node.y < minY then minY = node.y end
            if not maxY or node.y > maxY then maxY = node.y end
        end
    end
    if not minX then minX, maxX, minY, maxY = 0, 1, 0, 1 end

    PlaceHero(board, configID, minX, maxX, minY, maxY)

    -- AND NOW EVERYTHING DRAWN IS INSIDE IT. A hero tree can reach past the
    -- class board, and a node normalized past one is a node off the panel.
    for _, node in ipairs(board.nodes) do
        if node.x < minX then minX = node.x end
        if node.x > maxX then maxX = node.x end
        if node.y < minY then minY = node.y end
        if node.y > maxY then maxY = node.y end
    end

    board.minX, board.maxX, board.minY, board.maxY = minX, maxX, minY, maxY

    -- THE GRID IT SITS ON: the smallest step between two different columns
    -- or rows. Whoever draws this decides how big an icon may be from it,
    -- rather than from a number somebody typed while looking at one class.
    local seen, steps = {}, nil
    for _, node in ipairs(board.nodes) do
        seen[node.x] = true
    end
    local function Smallest(set)
        local list = {}
        for value in pairs(set) do list[#list + 1] = value end
        table.sort(list)
        local best
        for index = 2, #list do
            local step = list[index] - list[index - 1]
            if step > 0 and (not best or step < best) then best = step end
        end
        return best
    end
    steps = Smallest(seen)
    seen = {}
    for _, node in ipairs(board.nodes) do
        seen[node.y] = true
    end
    local down = Smallest(seen)
    if down and (not steps or down < steps) then steps = down end
    board.pitch = steps
end

-- THE BUILD, off the trait tree the answer carries: every CHOSEN node with
-- its rank, the hero tree's name and which one is active, and - the first
-- time this tree is seen - the board every one of them sits on. One walk
-- answers all of it; the game offers no shorter question than all nodes.
-- Guarded throughout: a client without C_Traits answers "not read".
local function ReadBuild(configID)
    if type(configID) ~= "number" then return nil, nil end
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes
        and C_Traits.GetNodeInfo) then
        return nil, nil
    end
    local okConfig, config = pcall(C_Traits.GetConfigInfo, configID)
    local treeID = okConfig and type(config) == "table"
        and type(config.treeIDs) == "table" and config.treeIDs[1] or nil
    if not treeID then return nil, nil end
    local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
    if not (okNodes and type(nodes) == "table") then return nil, nil end

    local board = boards[treeID]
    local building = board == nil
    if building then board = { nodes = {}, byNode = {}, bySpell = {} } end

    -- THE "PICK A HERO TREE" NODE IS A CONTROL, NOT A TALENT. It carries the
    -- two trees as its entries, so a walk that does not know it draws a
    -- talent nobody has and a spell nobody can cast. MRT skips it by type
    -- and so do we; a client without the enum simply keeps it, which is the
    -- old behaviour rather than a new bug.
    local selector = Enum and Enum.TraitNodeType
        and Enum.TraitNodeType.SubTreeSelection or nil

    local picks, hero, heroSub = {}, nil, nil
    local offered, knows = {}, {}
    for _, nodeID in ipairs(nodes) do
        local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if okNode and type(node) == "table" and node.ID ~= 0 then
            local inHero = node.subTreeID ~= nil
            local isSelector = selector ~= nil and node.type == selector

            -- EVERYTHING THE TREE OFFERS, chosen or not, both hero trees
            -- included. "Offered and not taken" is the one certain "cannot
            -- cast it" an inspect can give (owner, 2026-08-24: "wir
            -- muessen das nur richtig erkennen" - the owner's paladin had
            -- wrong talent). A spell a tree never offers stays unjudged.
            if C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo
                and type(node.entryIDs) == "table" then
                for _, entryID in ipairs(node.entryIDs) do
                    local option = EntrySpell(configID, entryID)
                    if option then offered[option] = true end
                end
            end
            if inHero and node.subTreeActive then
                heroSub = heroSub or node.subTreeID
                if not hero and C_Traits.GetSubTreeInfo then
                    local okSub, sub = pcall(C_Traits.GetSubTreeInfo,
                        configID, node.subTreeID)
                    if okSub and type(sub) == "table"
                        and type(sub.name) == "string" and sub.name ~= "" then
                        hero = sub.name
                    end
                end
            end

            -- THE BOARD, once per tree: where this node sits, what it would
            -- be, how many ranks it holds and which nodes it leads to.
            if building and not isSelector
                and type(node.posX) == "number"
                and type(node.posY) == "number"
                and type(node.entryIDs) == "table" then
                local first = EntrySpell(configID, node.entryIDs[1])
                if first then
                    local entry = {
                        id = nodeID,
                        x = node.posX,
                        y = node.posY,
                        spell = first,
                        most = node.maxRanks,
                        sub = node.subTreeID,
                    }
                    if type(node.visibleEdges) == "table" then
                        for _, edge in ipairs(node.visibleEdges) do
                            if type(edge) == "table" and edge.targetNode then
                                entry.edges = entry.edges or {}
                                entry.edges[#entry.edges + 1] = edge.targetNode
                            end
                        end
                    end
                    board.nodes[#board.nodes + 1] = entry
                    board.byNode[nodeID] = #board.nodes
                    -- EVERY SPELLING OF THE SAME PLACE. A choice node holds
                    -- two spells and only one of them is taken, so the board
                    -- has to answer to both or a chosen talent lights up
                    -- nothing.
                    for _, entryID in ipairs(node.entryIDs) do
                        local option = EntrySpell(configID, entryID)
                        if option then
                            board.bySpell[option] = #board.nodes
                        end
                    end
                end
            end
            -- Chosen, and on an ACTIVE board: the other hero tree's nodes
            -- keep their ranks and would draw a build nobody is playing.
            if (not inHero or node.subTreeActive) and not isSelector
                and type(node.currentRank) == "number"
                and node.currentRank > 0
                and type(node.posX) == "number"
                and type(node.posY) == "number" then
                local spell = NodeSpell(configID, node)
                if spell then
                    knows[spell] = true
                    picks[#picks + 1] = {
                        x = node.posX,
                        y = node.posY,
                        hero = inHero or false,
                        spell = spell,
                        rank = node.currentRank,
                        most = node.maxRanks,
                    }
                end
            end
        end
    end
    if building then
        FinishBoard(board, configID)
        boards[treeID] = board
    end

    if #picks == 0 then picks = nil end
    if next(offered) == nil then offered = nil end
    if next(knows) == nil then knows = nil end
    if #board.nodes == 0 then board = nil end
    return picks, hero, offered, knows, board, heroSub
end

local function ReadTalents(unit, own)
    local loadout, hero, picks, offered, knows, board, heroSub

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
                picks, hero, offered, knows, board, heroSub =
                    ReadBuild(configID)
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
        picks, hero, offered, knows, board, heroSub =
            ReadBuild(inspectConfig)
    end

    return loadout, hero, picks, offered, knows, board, heroSub
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

    local loadout, hero, picks, offered, knows, board, heroSub =
        ReadTalents(unit, own)
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
        build = picks or (carry and carry.build) or nil,
        offered = offered or (carry and carry.offered) or nil,
        knows = knows or (carry and carry.knows) or nil,
        board = board or (carry and carry.board) or nil,
        heroSub = heroSub or (carry and carry.heroSub) or nil,
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
-- WANTING. The player is read on the spot - their own links never need the
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
