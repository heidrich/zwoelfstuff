---------------------------------------------------------------------------
-- Share.lua - turning what you built into something you can paste
--
-- One string, one direction each way. Everything in here is PURE except the
-- two library calls: it takes a table and returns a string, or takes a string
-- and returns a table and a reason it could not. Nothing in this file reads
-- ns.db, writes ns.db, or knows a frame exists - which is why the whole of it
-- can be tested on a desktop with no game running, and is.
--
-- THE FORMAT
--
--   !ZS1_<printable>
--
--   printable = EncodeForPrint( CompressDeflate( Serialize( payload ) ) )
--
-- The version sits in the PREFIX and not only inside the payload. A string
-- from a future format can then be recognised and refused before a single
-- byte of it is decoded - the alternative is decompressing something built by
-- rules we do not have and reporting "corrupt" for a string that is perfectly
-- fine and simply newer.
--
-- WHY THESE TWO LIBRARIES. Serialize turns a table into bytes, Deflate makes
-- them small and printable. WeakAuras, Plater, MDT and EllesmereUI all reach
-- for exactly this pair. A hand-written serializer is a worse copy of a
-- solved problem, and the one place it would show is somebody else's string
-- failing to open with no way to tell whose fault it was.
---------------------------------------------------------------------------
local _, ns = ...

local Share = {}
ns.Share = Share

-- Fetched once at file scope. LibStub is loaded before us by the TOC, and a
-- library that is missing here is missing for the whole session - so the
-- callers below say so once, in words, rather than raising on a nil index.
local Serializer = LibStub and LibStub("LibSerialize", true)
local Deflate    = LibStub and LibStub("LibDeflate", true)

---------------------------------------------------------------------------
-- The string
---------------------------------------------------------------------------

-- Bump BOTH when the shape of a payload changes in a way an older build
-- cannot read. The prefix is what a stranger's addon looks at first.
Share.FORMAT = 1
Share.PREFIX = "!ZS1_"

-- A profile string is long. This is the length past which the import window
-- says "that is a big one" rather than looking frozen - it is a display
-- threshold and nothing refuses to work above it.
Share.LONG_STRING = 20000

---------------------------------------------------------------------------
-- WHAT CAN TRAVEL, and what each piece is called in front of a person.
--
-- The order is the order the checkboxes appear in. `key` is both the
-- checkbox key and the field in payload.parts, so the export window and the
-- import window cannot disagree about what a part is called - that is the
-- kind of drift that ends with a part that exports and never arrives.
--
-- `spells` marks the parts that name a spell, which is the only reason the
-- class stamp exists at all. Everything else is arrangement and colour and
-- travels between any two characters in the game.
---------------------------------------------------------------------------
Share.PARTS = {
    {
        key = "bars", label = "Bars", spells = true,
        note = "The grids, their arrangement, sizes, colours, rules and "
            .. "positions on screen. Pick which ones below.",
    },
    {
        key = "reminders", label = "Reminders", spells = true,
        note = "The lines of text and what makes each one appear.",
    },
    {
        key = "coTanks", label = "Co-tank panel",
        note = "The row layout, what each row shows, and where it sits.",
    },
    {
        key = "presets", label = "Saved looks",
        note = "The styles under Save as - sizes, spacing and colours, with "
            .. "no spells and no grid in them.",
    },
    {
        key = "settings", label = "Settings",
        note = "Fonts, the minimap button, the game-menu entry and the rest "
            .. "of what applies everywhere.",
    },
}

-- The same list keyed, for the checks below and for anything that has a part
-- name in hand and needs to know whether it is one.
Share.PART_BY_KEY = {}
for _, part in ipairs(Share.PARTS) do Share.PART_BY_KEY[part.key] = part end

---------------------------------------------------------------------------
-- Copying
--
-- Local and private on purpose. Bars.lua has one of these too; this one is
-- not a second copy of a RULE, it is a second copy of "walk a table", which
-- has nothing in it to drift.
---------------------------------------------------------------------------
local function DeepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, inner in pairs(value) do copy[key] = DeepCopy(inner) end
    return copy
end
Share.DeepCopy = DeepCopy

---------------------------------------------------------------------------
-- WHOSE STRING THIS IS
--
-- Stamped at export and read at import, for one question only: can the
-- spells in it be cast by whoever is opening it. Nothing here identifies a
-- person - the character name is NOT in it, because a string is meant to be
-- pasted into a public channel and a UI layout is not a reason to publish
-- who made it.
---------------------------------------------------------------------------
function Share.Stamp()
    local stamp = { addon = ns.version }

    if UnitClass then
        local _, class = UnitClass("player")
        stamp.class = class
    end

    -- The specialisation, when the client will say. It is used for the
    -- warning text only - the class is what actually decides whether a spell
    -- can be cast, and a Blood layout on a Frost death knight is a choice
    -- somebody is allowed to make.
    if GetSpecialization and GetSpecializationInfo then
        local index = GetSpecialization()
        if index then
            local id, name = GetSpecializationInfo(index)
            stamp.spec, stamp.specName = id, name
        end
    end

    return stamp
end

-- CAN THE SPELLS IN THIS STRING BE USED HERE?
--
-- Three answers, not two. "no" is a mismatch we are sure about, "yes" is a
-- match we are sure about, and nil is the case that used to be silently
-- treated as a match: a string with no stamp at all, or a client that would
-- not name our own class. The import window says "we cannot tell" for that
-- one rather than promising something.
function Share.SpellsFit(stamp, mine)
    mine = mine or Share.Stamp()
    if not (stamp and stamp.class) then return nil end
    if not mine.class then return nil end
    return stamp.class == mine.class
end

---------------------------------------------------------------------------
-- TAKING SOMEBODY ELSE'S BARS
--
-- THE ONE RULE, used by the importer AND by "take a layout from" between two
-- of your own characters. It was written twice for about an hour and the two
-- copies had already disagreed about what happens to an anchor pointing at a
-- bar that did not come along.
--
--   * Every bar gets a NEW id. Ids are never reused here for the same reason
--     Bars:NextID never reuses one: an anchor points at an id, and a
--     recycled id silently re-attaches a bar to whatever took the old one's
--     place.
--   * Anchors are remapped in a SECOND pass, because a bar can be attached
--     to one that comes after it in the list. An anchor whose target did not
--     travel is dropped, not left dangling.
--   * The spells come along only when they were asked for. Dropping them
--     leaves the grid, the sizes and the colours - which is the whole layout
--     minus the four letters of a spell name.
--
-- nextID is passed in rather than reached for, so this can be run against a
-- counter in a test without a database underneath it.
---------------------------------------------------------------------------
function Share.AdoptBars(sourceBars, nextID, keepSpells)
    if type(sourceBars) ~= "table" then return {}, 0 end

    local copied, oldIDs = {}, {}
    for _, cfg in ipairs(sourceBars) do
        if type(cfg) == "table" then
            local bar = DeepCopy(cfg)
            oldIDs[#copied + 1] = cfg.id

            if not keepSpells then
                -- Both shapes, because a bar saved before the per-spec split
                -- carries the flat one and one saved after carries the other.
                -- Clearing only the shape we expect leaves the other filled,
                -- and the spells arrive anyway on the next spec change.
                bar.cellsBySpec, bar.parkedBySpec = nil, nil
                bar.cells, bar.parked = {}, {}
            end

            bar.id = 0
            copied[#copied + 1] = bar
        end
    end

    if #copied == 0 then return {}, 0 end

    local newID = {}
    for index, bar in ipairs(copied) do
        local fresh = nextID()
        newID[oldIDs[index]] = fresh
        bar.id = fresh
    end

    for _, bar in ipairs(copied) do
        if bar.anchor then
            bar.anchor.to = newID[bar.anchor.to]
            if not bar.anchor.to then bar.anchor = nil end
        end
    end

    return copied, #copied
end

---------------------------------------------------------------------------
-- Out
---------------------------------------------------------------------------

-- payload: { v, stamp, label, parts = { [partKey] = data } }
--
-- Returns the string, or nil and a sentence. The sentence is shown to a
-- person, so it says what to do where that is knowable.
function Share.Encode(payload)
    if type(payload) ~= "table" then return nil, "there is nothing to export" end
    if not Serializer then return nil, "LibSerialize did not load" end
    if not Deflate then return nil, "LibDeflate did not load" end

    payload.v = Share.FORMAT

    -- pcall around both: a table holding something that cannot be serialised
    -- raises inside the library, and the caller is a button in a window.
    local ok, serialized = pcall(Serializer.Serialize, Serializer, payload)
    if not (ok and type(serialized) == "string") then
        return nil, "this could not be packed up"
    end

    local compressed = Deflate:CompressDeflate(serialized)
    if not compressed then return nil, "this could not be compressed" end

    local printable = Deflate:EncodeForPrint(compressed)
    if not printable then return nil, "this could not be turned into text" end

    return Share.PREFIX .. printable
end

---------------------------------------------------------------------------
-- In
--
-- Every failure gets its OWN sentence. "Invalid string" for all six of these
-- is the message that sends somebody to a bug report when the actual problem
-- was that their chat window cut the paste in half.
---------------------------------------------------------------------------
function Share.Decode(text)
    if type(text) ~= "string" then return nil, "there is nothing pasted in" end

    -- Chat windows and forums add a space or a newline at either end far more
    -- often than they corrupt the middle.
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return nil, "there is nothing pasted in" end

    if text:sub(1, #Share.PREFIX) ~= Share.PREFIX then
        -- A ZwoelfStuff string of a DIFFERENT format version is a different
        -- problem from a string that was never ours, and saying so is the
        -- difference between "update your addon" and "check what you copied".
        local ours, version = text:match("^(!ZS(%d+)_)")
        if ours then
            return nil, "this was made with a newer ZwoelfStuff (format "
                .. version .. ", this one reads " .. Share.FORMAT
                .. ") - update the addon and try again"
        end
        return nil, "this is not a ZwoelfStuff string - make sure the whole "
            .. "thing was copied, starting at " .. Share.PREFIX
    end

    if not Serializer then return nil, "LibSerialize did not load" end
    if not Deflate then return nil, "LibDeflate did not load" end

    local decoded = Deflate:DecodeForPrint(text:sub(#Share.PREFIX + 1))
    if not decoded then
        return nil, "this string has characters in it that do not belong - "
            .. "it was probably cut short or joined with something else"
    end

    local decompressed = Deflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "this string is damaged - the end of it is missing or it "
            .. "was pasted twice"
    end

    local ok, payload = Serializer:Deserialize(decompressed)
    if not (ok and type(payload) == "table") then
        return nil, "this string unpacked into something that is not a profile"
    end

    -- The gate, both directions. The prefix caught a newer FORMAT above; this
    -- catches a payload whose version field disagrees with the prefix it
    -- arrived under, which means somebody hand-edited it.
    if type(payload.v) ~= "number" then
        return nil, "this string does not say which version made it"
    end
    if payload.v > Share.FORMAT then
        return nil, "this was made with a newer ZwoelfStuff - update the "
            .. "addon and try again"
    end

    if type(payload.parts) ~= "table" or not next(payload.parts) then
        return nil, "this string is a valid one but has nothing in it"
    end

    -- A part name this build does not know is DROPPED, not refused. A newer
    -- addon adding a sixth part must not make its strings unopenable here -
    -- the four parts we do understand are still worth having, and the count
    -- below is what the import window reports.
    local unknown = {}
    for key in pairs(payload.parts) do
        if not Share.PART_BY_KEY[key] then unknown[#unknown + 1] = key end
    end
    for _, key in ipairs(unknown) do payload.parts[key] = nil end

    if not next(payload.parts) then
        return nil, "everything in this string was made by a newer version of "
            .. "the addon and none of it can be read here"
    end

    payload.dropped = #unknown > 0 and unknown or nil
    return payload
end

---------------------------------------------------------------------------
-- WHAT IS IN THIS STRING, in the words the import window shows before
-- anything is written. Pure, and separate from Decode, because a preview
-- that is computed by the same pass that applies it is a preview that can
-- only be trusted after the fact.
---------------------------------------------------------------------------
function Share.Describe(payload)
    local lines = {}
    if type(payload) ~= "table" or type(payload.parts) ~= "table" then
        return lines
    end

    for _, part in ipairs(Share.PARTS) do
        local data = payload.parts[part.key]
        if data ~= nil then
            local detail
            if part.key == "bars" and type(data) == "table" then
                local count = #data
                detail = count .. (count == 1 and " bar" or " bars")
            elseif part.key == "reminders" and type(data) == "table" then
                local count = #data
                detail = count .. (count == 1 and " reminder" or " reminders")
            elseif part.key == "presets" and type(data) == "table" then
                local count = 0
                for _ in pairs(data) do count = count + 1 end
                detail = count .. (count == 1 and " look" or " looks")
            end

            lines[#lines + 1] = { label = part.label, detail = detail }
        end
    end

    return lines
end
