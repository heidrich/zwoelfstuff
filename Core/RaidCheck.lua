---------------------------------------------------------------------------
-- RaidCheck - is everybody actually ready.
--
-- Owner, 2026-08-12, pointing at the fourth screenshot: "screen4 zeigt alle in
-- der gruppe oder raid, mit klasse, name und welchen food, flask etc sie drin
-- haben, auch alle gruppen und raid buffs, haltbarkeit + item level."
--
-- THE HARD PART IS NOT THE WINDOW, IT IS WHERE THE FACTS COME FROM.
--
-- Four sources, in order of trust, and a row takes each FACT from the first
-- source that has it (RaidCheck.FactsFor):
--
--   1. THEIR OWN CLIENT, over the addon channel. Exact, everywhere - and
--      only players running this addon answer.
--   2. THEIR AURAS, read from here. "Auras are secret" is a WHERE, not an
--      always (Core/Secrets.lua) - when this client may read them, the
--      food, flask, rune and buff cells fill for people who never heard of
--      this addon. MRT reads the room the same way, behind the same check.
--   3. THE INSPECT, for gear. The server answers it about anybody, addon
--      or not - the item level and the enchants come from Core/Gear.lua.
--   4. THE SHARED DURABILITY WIRE (Core/Durability.lua), which everybody
--      running MRT or BigWigs answers without knowing it.
--
-- WHAT IS NOT KNOWN STAYS NOT KNOWN - per FIELD, not per row. A durability
-- that arrived without a flask answer draws its number beside a waiting
-- mark, and silence is never drawn as a cross: a cross is a fact about
-- somebody's flask and silence is not.
--
-- THE SPELL IDS WERE READ, NOT REMEMBERED. Every one below comes out of MRT's
-- RaidCheck.lua on this machine, which is maintained against the live game -
-- the house rule after two evenings lost to numbers quoted from memory. The
-- flask list is the Midnight one; the food test is the WELL FED icon rather
-- than a list of four hundred ids, because that icon has been the same since
-- Wrath and the id list goes stale with every patch.
---------------------------------------------------------------------------
local _, ns = ...

local RaidCheck = {}
ns.RaidCheck = RaidCheck

local UI = ns.UI
local C = UI.C

---------------------------------------------------------------------------
-- What counts as what
---------------------------------------------------------------------------
-- The generic "Well Fed" icon. Every food buff in the game wears it.
RaidCheck.FOOD_ICON = 136000

-- Midnight flasks, from MRT's tableFlask.
RaidCheck.FLASKS = {
    [1236763] = true, [1239355] = true, [1235057] = true, [1239755] = true,
    [1236767] = true, [1235111] = true, [1235110] = true, [1235108] = true,
}

-- Augment runes, MRT's tableRunes. The old ones are kept: somebody using a
-- leftover rune from the last expansion still has the buff, and telling them
-- they have none is worse than saying nothing.
RaidCheck.RUNES = {
    [224001] = true, [270058] = true, [317065] = true, [347901] = true,
    [367405] = true, [393438] = true, [453250] = true, [1234969] = true,
    [1242347] = true, [1264426] = true,
}

-- THE GROUP BUFFS, in bit order. The order is the wire format: bit 1 is
-- Stamina for as long as this addon exists, because a client one version
-- behind is reading the same bits. Anything new goes on the END.
RaidCheck.BUFFS = {
    { key = "stam", bit = 1,  label = "Stamina",
      spells = { [21562] = true, [264764] = true } },
    { key = "int",  bit = 2,  label = "Intellect",
      spells = { [1459] = true, [264760] = true } },
    { key = "ap",   bit = 4,  label = "Attack power",
      spells = { [6673] = true, [264761] = true } },
    { key = "vers", bit = 8,  label = "Versatility",
      spells = { [1126] = true } },
    { key = "mast", bit = 16, label = "Mastery",
      spells = { [462854] = true } },
    -- One buff, thirteen spellings: the movement blessing is a different id
    -- per flavour and every one of them is the same line on this window.
    { key = "move", bit = 32, label = "Movement",
      spells = {
          [381732] = true, [381741] = true, [381746] = true, [381748] = true,
          [381749] = true, [381750] = true, [381751] = true, [381752] = true,
          [381753] = true, [381754] = true, [381756] = true, [381757] = true,
          [381758] = true,
      } },
}

-- Pure. Which bit of the mask a buff is, and whether it is set - so the
-- window's ticks can be checked without a raid.
function RaidCheck.HasBuff(mask, buff)
    if type(mask) ~= "number" or not buff then return false end
    return math.floor(mask / buff.bit) % 2 == 1
end

---------------------------------------------------------------------------
-- WHAT THIS CHARACTER IS CARRYING
--
-- Reads the player and nobody else, which is the only unit any of this is
-- allowed to be asked about.
--
-- Answers nil when the client will not say. That is a real state on 12.x -
-- C_Secrets.ShouldAurasBeSecret is the client announcing it - and nil travels
-- all the way to the window as "no answer", because a zero would read as
-- "this person has no flask".
---------------------------------------------------------------------------
-- BOTH OF THESE MOVED TO Core/Secrets.lua and are called through, not
-- copied. The proc recorder in Core/Auras.lua asks the same question for a
-- different reason - which buff came and went with a glow - and two loops
-- over the same sixty slots would be two places to get the secrecy guard
-- wrong. Kept under these names because this file's callers read well with
-- them.
function RaidCheck.AurasReadable() return ns.AurasReadable() end

local function OwnAuraIDs() return ns.OwnAuras("player", "HELPFUL") end

-- The lowest durability of anything worn, as a percent. The LOWEST and not
-- the average: a raid leader asking about durability is asking whether
-- somebody's weapon is about to fall apart, and an average hides exactly that.
function RaidCheck.Durability()
    if not GetInventoryItemDurability then return nil end
    local worst
    for slot = 1, 18 do
        local ok, current, maximum = pcall(GetInventoryItemDurability, slot)
        if ok and current and maximum and maximum > 0 then
            local percent = current / maximum * 100
            if not worst or percent < worst then worst = percent end
        end
    end
    if not worst then return nil end
    return math.floor(worst + 0.5)
end

function RaidCheck.ItemLevel()
    if not GetAverageItemLevel then return nil end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if not ok or not equipped then return nil end
    return math.floor(equipped + 0.5)
end

-- ONE CLASSIFIER FOR BOTH DIRECTIONS. The same rule reads the player for
-- the wire and a group-mate for their row - two copies would drift, and a
-- drifted copy is a window whose columns disagree about one flask.
function RaidCheck.Classify(ids, icons)
    if not (ids and icons) then return nil end
    local facts = {}

    facts.fo = (icons[RaidCheck.FOOD_ICON] and 1) or 0

    facts.fl = 0
    for id in pairs(RaidCheck.FLASKS) do
        if ids[id] then
            facts.fl = 1
            break
        end
    end

    facts.ru = 0
    for id in pairs(RaidCheck.RUNES) do
        if ids[id] then
            facts.ru = 1
            break
        end
    end

    local mask = 0
    for _, buff in ipairs(RaidCheck.BUFFS) do
        for id in pairs(buff.spells) do
            if ids[id] then
                mask = mask + buff.bit
                break
            end
        end
    end
    facts.bf = mask

    return facts
end

-- ANOTHER PLAYER, READ FROM HERE - the same sixty slots, the same rule,
-- through the same secrecy gate. nil when the client is withholding, and
-- nil is drawn as waiting, never as a cross.
--
-- VISIBILITY FIRST. The aura list answers identically for "no buffs" and
-- "cannot see them" - nothing at the first slot either way - so somebody
-- offline or phased away would classify as a row of zeros: invented
-- crosses about a person nobody read. Both answers can arrive as secret
-- booleans, and Truth's fallback lands on "not readable", which draws as
-- waiting - the honest direction for a reader.
function RaidCheck.ReadUnit(unit)
    if not unit then return nil end
    if UnitIsConnected and not ns.Truth(UnitIsConnected(unit), false) then
        return nil
    end
    if UnitIsVisible and not ns.Truth(UnitIsVisible(unit), false) then
        return nil
    end
    return RaidCheck.Classify(ns.OwnAuras(unit, "HELPFUL"))
end

-- The whole answer, in the shape that goes on the wire.
function RaidCheck.Read()
    local facts = {}

    local level = RaidCheck.ItemLevel()
    if level then facts.il = level end

    local durability = RaidCheck.Durability()
    if durability then facts.du = durability end

    local carried = RaidCheck.Classify(OwnAuraIDs())
    if carried then
        facts.fo, facts.fl = carried.fo, carried.fl
        facts.ru, facts.bf = carried.ru, carried.bf
    end

    return facts
end

---------------------------------------------------------------------------
-- What everybody said
--
-- Keyed by NAME-REALM via Comm.FullName: the channel hands some senders
-- over short and some full, the roster does the same, and two spellings of
-- one person would fill the wrong row - two same-named players on different
-- realms genuinely collide short. Wiped when a check is asked for, so an
-- answer from the last pull cannot be read as an answer to this one - a
-- stale tick is the one thing this window must never draw.
---------------------------------------------------------------------------
RaidCheck.answers = {}
RaidCheck.askedAt = nil

function RaidCheck.Forget()
    for key in pairs(RaidCheck.answers) do RaidCheck.answers[key] = nil end
end

-- ASK, and answer yourself in the same breath. Your own facts never travel -
-- the channel echoes your message back and Comm drops it, which is correct
-- for every other message on it - so they are read locally instead.
function RaidCheck:Ask()
    -- THE WIPE FOLLOWS THE ASK IT BELONGS TO. Both re-asks are throttled,
    -- and a second press inside the quiet window used to empty every
    -- collected row while sending nothing to refill them - a button that
    -- deletes on a double-click. What still stands is from seconds ago
    -- and stays until an ask actually leaves the machine.
    local ok, why = ns.Comm.AskCheck()
    if ok then
        RaidCheck.Forget()
        RaidCheck.askedAt = GetTime and GetTime() or 0
    end
    if ns.Durability and ns.Durability.Request() then
        ns.Durability.Forget()
    end

    local me = ns.Comm.FullName(UnitName and UnitName("player") or "player")
    if me then RaidCheck.answers[me] = RaidCheck.Read() end

    -- Gear rides the inspect queue and needs nothing on the channel; the
    -- player's own is read on the spot inside Want.
    if ns.Gear then
        for _, member in ipairs(ns.Roster()) do
            ns.Gear.Want(member.unit)
        end
    end

    if not ok and why == "you are not in a group" then
        -- Alone, the window is still worth having: it shows YOUR own line,
        -- which is the one a raid leader checks before summoning anybody.
        ns.Print("|cff888888" .. ns.L["You are not in a group."] .. "|r")
    end
    self:Refresh()
    return ok
end

ns.Comm.Listen(function(packet)
    if packet.what ~= ns.Comm.CHECK then return end

    if packet.ask then
        -- SOMEBODY ELSE IS CHECKING. Answering is not a decision the player
        -- has to make: it is their own client saying what they are carrying,
        -- to a group they are already in, and refusing would make the feature
        -- work only when everybody has found a setting.
        --
        -- It IS gated on the module, because a switched-off feature that
        -- still talks on the channel is a feature that is not switched off.
        if ns.Modules:IsOn("raidbar") then
            ns.Comm.SendCheck(RaidCheck.Read())
        end
        return
    end

    if packet.fields then
        local key = ns.Comm.FullName(packet.from)
        if key then
            RaidCheck.answers[key] = packet.fields
            RaidCheck:Refresh()
        end
    end
end)

---------------------------------------------------------------------------
-- WHERE A ROW'S FACTS COME FROM
--
-- Per FIELD, first source that has it: what their client SAID, then what
-- this client can read - their buffs when auras are readable, their gear
-- off the inspect, their durability off the shared wire. A fresh table
-- every time, because writing read fields into a stored answer would let a
-- stale read masquerade as something somebody said.
---------------------------------------------------------------------------
function RaidCheck.FactsFor(member)
    if not member then return nil, false end

    local key = ns.Comm.FullName(member.fullName or member.name)
    local said = key and RaidCheck.answers[key] or nil

    local merged = {}
    if said then
        for field, value in pairs(said) do merged[field] = value end
    end

    if merged.fo == nil or merged.fl == nil or merged.ru == nil
        or merged.bf == nil then
        local read = RaidCheck.ReadUnit(member.unit)
        if read then
            for field, value in pairs(read) do
                if merged[field] == nil then merged[field] = value end
            end
        end
    end

    if merged.du == nil and ns.Durability then
        local heard = ns.Durability.Of(key)
        if heard then merged.du = heard.percent end
    end

    local guid = member.unit and UnitGUID and UnitGUID(member.unit)
    local gear = ns.CanCompute(guid) and ns.Gear and ns.Gear.Of(guid) or nil
    if gear then
        if merged.il == nil and gear.ilvl then merged.il = gear.ilvl end
        if gear.vz ~= nil then merged.vz = gear.vz end
    end

    if next(merged) == nil then return nil, false end
    return merged, said ~= nil
end

-- PURE, because a dozen cells' worth of three-state logic is exactly the
-- kind of thing that has shipped broken here before. "unknown" is not "no".
function RaidCheck.CellState(facts, column)
    if not column then return "unknown" end

    if column.kind == "bit" then
        local mask = facts and facts.bf
        if mask == nil then return "unknown" end
        return RaidCheck.HasBuff(mask, column.buff) and "yes" or "no"
    end

    local value = facts and facts[column.key]
    if value == nil then return "unknown" end
    if column.key == "vz" then
        -- The count of MISSING enchants: zero is dressed, anything else is
        -- a list the card behind the magnifier can name.
        return value == 0 and "yes" or "no"
    end
    return value == 1 and "yes" or "no"
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame
local rows = {}

-- The columns, left to right. One table, three readers: the heading row, the
-- body rows and the width the window is built at - so a column added here
-- appears in all three or in none.
local COLUMNS = {
    -- The magnifier first: it is the row's door to the player card, and a
    -- door reads as a door at the start of the line.
    { key = "look",  label = "",           width = 24,  kind = "look" },
    { key = "name",  label = "Name",       width = 130, kind = "text" },
    { key = "il",    label = "Item level", width = 60,  kind = "number" },
    { key = "du",    label = "Durability", width = 62,  kind = "percent" },
    { key = "vz",    label = "Enchants",   width = 46,  kind = "tick" },
    { key = "fo",    label = "Food",       width = 46,  kind = "tick" },
    { key = "fl",    label = "Flask",      width = 46,  kind = "tick" },
    { key = "ru",    label = "Rune",       width = 46,  kind = "tick" },
}

for _, buff in ipairs(RaidCheck.BUFFS) do
    COLUMNS[#COLUMNS + 1] = {
        key = "bf", label = buff.label, width = 46, kind = "bit", buff = buff,
    }
end

RaidCheck.COLUMNS = COLUMNS

function RaidCheck.Width()
    local total = UI.PAD * 2
    for _, column in ipairs(COLUMNS) do total = total + column.width end
    return total
end

local TICK_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TICK_NOT = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TICK_WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local ROW_H = 22

local function BuildRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.cells = {}

    local x = 0
    for position, column in ipairs(COLUMNS) do
        if column.kind == "look" then
            -- The magnifier. A plain button on purpose: the click opens a
            -- window of ours, so none of the secure-press rules apply.
            local look = CreateFrame("Button", nil, row)
            look:SetSize(18, 18)
            look:SetPoint("LEFT", row, "LEFT", x + 2, 0)
            local glass = UI.Glyph(look, "ui-search", 11, C.textDim)
            glass:SetPoint("CENTER", look, "CENTER", 0, 0)
            look:SetScript("OnEnter", function()
                glass:SetColor(C.accent[1], C.accent[2], C.accent[3])
            end)
            look:SetScript("OnLeave", function()
                glass:SetColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end)
            look:SetScript("OnClick", function(self)
                if self.member and ns.PlayerCard then
                    ns.PlayerCard.Show(self.member)
                end
            end)
            row.cells[position] = look
        elseif column.kind == "tick" or column.kind == "bit" then
            local tick = row:CreateTexture(nil, "ARTWORK")
            tick:SetSize(14, 14)
            tick:SetPoint("LEFT", row, "LEFT", x + column.width / 2 - 7, 0)
            row.cells[position] = tick
        else
            local text = UI.Label(row, "", UI.FS.meta, C.textBody)
            text:SetPoint("LEFT", row, "LEFT", x, 0)
            text:SetWidth(column.width - 6)
            text:SetJustifyH(column.kind == "text" and "LEFT" or "RIGHT")
            row.cells[position] = text
        end
        x = x + column.width
    end

    -- Every other row on a slightly lighter ground. Twelve ticks across a
    -- 700-wide window is exactly the place an eye loses its line.
    if index % 2 == 0 then
        UI.Fill(row, "BACKGROUND", C.rowAlt or C.control, 0.35)
    end

    return row
end

function RaidCheck:Create()
    if frame then return frame end

    local width = RaidCheck.Width()

    frame = CreateFrame("Frame", "ZwoelfStuffRaidCheck", UIParent)
    frame:SetSize(width, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)

    frame.title = UI.Label(frame, "", UI.FS.card, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -18)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -14)
    local cross = UI.Glyph(close, "ui-close", 12, C.textDim)
    cross:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Its text is set at BUILD time and measured from it, because a button
    -- 130 wide is 130 wide in English and too narrow in German. The window is
    -- built the first time it is opened, which is long after the profile - so
    -- the lookup here is the language the player actually chose.
    local ask = UI.Button(frame, ns.L["Ask the group"], nil,
        function() RaidCheck:Ask() end, "primary")
    ask:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, -2)
    frame.ask = ask

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.HEADER_H)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -UI.HEADER_H)

    -- THE HEADING ROW. Written the way the screenshot draws it - the columns
    -- are narrow and the words are not, so they lean rather than being cut in
    -- half. SetRotation takes radians; 45 degrees is the angle every raid
    -- check in the game uses for exactly this reason.
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -(UI.HEADER_H + 6))
    head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -(UI.HEADER_H + 6))
    head:SetHeight(58)
    frame.head = head
    frame.heads = {}

    local x = 0
    for position, column in ipairs(COLUMNS) do
        local label = UI.Label(head, "", 10, C.textFaint)
        if column.kind == "look" or column.kind == "text" then
            label:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", x, 4)
        else
            label:SetPoint("BOTTOM", head, "BOTTOMLEFT",
                x + column.width / 2, 6)
            label:SetRotation(math.pi / 4)
        end
        frame.heads[position] = label
        x = x + column.width
    end

    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    listHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, 34)

    local _, content = UI.ScrollArea(listHost, RaidCheck.Width() - UI.PAD, 6)
    frame.content = content

    frame.foot = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 12)

    table.insert(UISpecialFrames, "ZwoelfStuffRaidCheck")
    return frame
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function ClassColour(class)
    -- The client's own table, which is also what every unit frame in the game
    -- draws a name with - so a name here is the colour it is everywhere else.
    -- Declared in .luarc.json: the language server's definition set does not
    -- carry it although every client has had it for twenty years.
    local colours = RAID_CLASS_COLORS
    local entry = colours and class and colours[class]
    if not entry then return C.text end
    return { entry.r, entry.g, entry.b }
end

-- COALESCED. Twenty answers land inside a second when a raid is asked,
-- and each used to rebuild the whole window - with a fresh read of every
-- unanswered row's auras. One rebuild per frame carries the same facts.
local drawQueued = false

function RaidCheck:Refresh()
    if not (frame and frame:IsShown()) then return end
    if C_Timer and C_Timer.After then
        if drawQueued then return end
        drawQueued = true
        C_Timer.After(0, function()
            drawQueued = false
            RaidCheck:Redraw()
        end)
        return
    end
    RaidCheck:Redraw()
end

function RaidCheck:Redraw()
    if not (frame and frame:IsShown()) then return end

    local L = ns.L
    frame.title:SetText(L["Raid check"])
    frame.ask:SetText(L["Ask the group"])

    for position, column in ipairs(COLUMNS) do
        frame.heads[position]:SetText(L[column.label])
    end

    local roster = ns.Roster()
    local answered, total = 0, #roster

    for index, member in ipairs(roster) do
        local row = rows[index]
        if not row then
            row = BuildRow(frame.content, index)
            row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0,
                -(index - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0,
                -(index - 1) * ROW_H)
            rows[index] = row
        end
        row:Show()

        local facts, said = RaidCheck.FactsFor(member)
        if said then answered = answered + 1 end

        -- Keep the inspect queue warm: a roster that reshuffled since the
        -- ask would otherwise leave new arrivals permanently unread.
        if ns.Gear then ns.Gear.Want(member.unit) end

        for position, column in ipairs(COLUMNS) do
            local cell = row.cells[position]

            if column.kind == "look" then
                cell.member = member

            elseif column.key == "name" then
                local colour = ClassColour(member.class)
                cell:SetText(member.name)
                cell:SetTextColor(colour[1], colour[2], colour[3])

            elseif column.kind == "number" then
                cell:SetText(facts and facts.il and tostring(facts.il) or "-")
                cell:SetTextColor(C.textBody[1], C.textBody[2], C.textBody[3])

            elseif column.kind == "percent" then
                local value = facts and facts.du
                cell:SetText(value and (value .. "%") or "-")
                -- Under a quarter is the only number on this row worth
                -- shouting about, and it is shouted in the one colour this
                -- design uses for "this will break".
                if value and value < 25 then
                    cell:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
                else
                    cell:SetTextColor(C.textBody[1], C.textBody[2], C.textBody[3])
                end

            elseif column.kind == "tick" or column.kind == "bit" then
                -- THREE STATES PER FIELD, NOT PER ROW. Yes, no, and "not
                -- read" - and the third is the waiting mark rather than a
                -- cross, because a cross is a fact about somebody's flask
                -- and silence is not. Per FIELD, because a row can carry a
                -- durability without a flask answer now - and an answer
                -- that said nothing about food used to be drawn as "no
                -- food", which was this window inventing the exact kind of
                -- fact it promises not to.
                local state = RaidCheck.CellState(facts, column)
                cell:SetTexture(state == "unknown" and TICK_WAITING
                    or (state == "yes" and TICK_READY or TICK_NOT))
                cell:SetAlpha(state == "unknown" and 0.4 or 1)
            end
        end
    end

    for index = total + 1, #rows do rows[index]:Hide() end

    frame.content:SetHeight(math.max(1, total * ROW_H))

    if total == 0 then
        frame.foot:SetText(L["You are not in a group."])
    elseif answered == 0 then
        frame.foot:SetText(L["Nobody has answered yet."] .. " "
            .. L["Grey marks are not read yet, not a no."])
    else
        frame.foot:SetText(L("%d of %d answered", answered, total) .. "  |cff888888"
            .. L["Grey marks are not read yet, not a no."] .. "|r")
    end
end

function RaidCheck:Show()
    self:Create()
    frame:Show()
    -- Opening IS asking. A window that shows twelve waiting marks until you
    -- find a button is a window that looks broken on the one screen where it
    -- has to be believed.
    self:Ask()
end

function RaidCheck:Hide()
    if frame then frame:Hide() end
end

function RaidCheck:Toggle()
    self:Create()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end

function RaidCheck:IsShown()
    return frame and frame:IsShown() and true or false
end

function RaidCheck.Frame() return frame end

---------------------------------------------------------------------------
-- REDRAWING WHEN THE WORLD MOVES. A gear answer and a reshuffled roster
-- both land seconds after the ask - a window that only redrew on channel
-- answers would keep the old rows on screen. Refresh answers nothing while
-- the window is hidden, so both of these are free until it is looked at.
---------------------------------------------------------------------------
local redraw = CreateFrame("Frame")
redraw:RegisterEvent("GROUP_ROSTER_UPDATE")
redraw:SetScript("OnEvent", function() RaidCheck:Refresh() end)

if ns.Gear and ns.Gear.OnLearned then
    ns.Gear.OnLearned(function() RaidCheck:Refresh() end)
end

---------------------------------------------------------------------------
-- /zs check
---------------------------------------------------------------------------
function RaidCheck:Dump()
    ns.Print("|cffffd100raid check|r - what this client can say, and who has said.")

    ns.Print("  auras readable here: "
        .. (RaidCheck.AurasReadable() and "|cff40ff40yes|r"
            or "|cffff8040no - this client keeps them secret|r"))

    local mine = RaidCheck.Read()
    ns.Print(string.format("  you: ilvl %s, durability %s, food %s, flask %s, rune %s, buffs %s",
        tostring(mine.il or "-"), tostring(mine.du or "-"),
        tostring(mine.fo or "-"), tostring(mine.fl or "-"),
        tostring(mine.ru or "-"), tostring(mine.bf or "-")))
    ns.Print("  on the wire: |cff888888" .. ns.Comm.EncodeCheck(mine) .. "|r")

    local count = 0
    for who, facts in pairs(RaidCheck.answers) do
        count = count + 1
        ns.Print(string.format("    %s -> ilvl %s, dur %s, buffs %s", who,
            tostring(facts.il or "-"), tostring(facts.du or "-"),
            tostring(facts.bf or "-")))
    end
    if count == 0 then
        ns.Print("  |cff888888nobody has answered. /zs check ask sends one.|r")
    end
end
