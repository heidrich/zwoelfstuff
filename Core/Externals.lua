---------------------------------------------------------------------------
-- Externals - the cooldowns SOMEBODY ELSE presses on you.
--
-- Owner, 2026-08-09: "das sind quasi cooldowns von extern die man auf tanks
-- wirken kann" - and what he wants from them is not a tracker: "wo alle cds
-- der klassen aufgelistet sind, da ziehe ich mir wieder welche in slots, die
-- slots kann ich dann auf dem screen frei platzieren. beim klick auf einen
-- spell wird der heiler / klasse angewispert."
--
-- WHAT THIS PANEL IS NOT, and the difference is the whole design:
--
-- It is NOT a cooldown display. Method Raid Tools shows other people's
-- cooldowns by reading COMBAT_LOG_EVENT_UNFILTERED - checked in its own
-- ExCD2.lua, which is where this list came from. That log is closed to
-- addons on 12.0, and since 12.0.5 another player's INSTANT cast is not
-- announced at all. Every spell below is instant. So "Ironbark, ready in
-- 1:12" is a number this addon cannot know, and a panel that printed one
-- would be guessing in the one moment you would believe it.
--
-- It IS the question, asked in one click: who in this group can save me, and
-- tell them now. That part is completely knowable - class is readable, the
-- group roster is readable, and a whisper on a click is the player's own
-- action, not automation.
--
-- THE LIST. Fourteen spells, cross-checked against MRT's own DEFTAR set
-- ("defensive on a target"), which is the same idea under another name.
-- Cooldowns are carried for the TOOLTIP only - so the panel can say how long
-- what you are asking for lasts - and never as a clock, for the reason above.
---------------------------------------------------------------------------
local _, ns = ...

local Externals = {}
ns.Externals = Externals

-- class:    who can cast it. UnitClass answers this for every group member
--           and never refuses, which is why the panel is built on it.
-- healer:   true when only the healing specialisation has it. Used to pick
--           WHO to ask in a five-man, where there is one healer and asking
--           the retribution paladin for a Blessing of Sacrifice is asking
--           the wrong paladin - even though he does have it.
-- cooldown: for the tooltip. Never counted down. See the header.
Externals.SPELLS = {
    { spellID = 3411,   class = "WARRIOR", cooldown = 30 },   -- Intervene
    { spellID = 1044,   class = "PALADIN", cooldown = 25 },   -- Blessing of Freedom
    { spellID = 1022,   class = "PALADIN", cooldown = 300 },  -- Blessing of Protection
    { spellID = 6940,   class = "PALADIN", cooldown = 120 },  -- Blessing of Sacrifice
    { spellID = 204018, class = "PALADIN", cooldown = 300 },  -- Blessing of Spellwarding
    { spellID = 633,    class = "PALADIN", cooldown = 600 },  -- Lay on Hands
    { spellID = 33206,  class = "PRIEST",  cooldown = 180, healer = true },  -- Pain Suppression
    { spellID = 47788,  class = "PRIEST",  cooldown = 180, healer = true },  -- Guardian Spirit
    { spellID = 2050,   class = "PRIEST",  cooldown = 60,  healer = true },  -- Holy Word: Serenity
    { spellID = 108968, class = "PRIEST",  cooldown = 300 },  -- Void Shift
    { spellID = 116849, class = "MONK",    cooldown = 120, healer = true },  -- Life Cocoon
    { spellID = 102342, class = "DRUID",   cooldown = 90,  healer = true },  -- Ironbark
    { spellID = 363534, class = "EVOKER",  cooldown = 240, healer = true },  -- Rewind
    { spellID = 357170, class = "EVOKER",  cooldown = 60 },   -- Time Dilation
}

local byID = {}
for _, entry in ipairs(Externals.SPELLS) do byID[entry.spellID] = entry end

function Externals.Get(spellID) return byID[spellID] end

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
-- SLOTS, NOT A LIST. Owner: "slot anzahl geht nicht. das sollte wie bei den
-- cooldowns funktionieren."
--
-- So this is shaped like a bar: a COUNT of slots, and a sparse table of what
-- is in each one. The difference from the old ordered list is the whole point
-- - a list has no empty third slot to click on, so there was nothing to
-- select and nothing for a count to change.
-- ROWS AND COLUMNS, the way a bar has them. Owner: "anzahl rows fehlt! wie
-- die cdm einstellungen, reihe und spalten anzahl."
--
-- So the panel is a LATTICE and not a run of slots with a wrap setting: rows
-- times columns is how many places there are, which is the same sentence the
-- cooldown bars answer. The old pair - a count plus "how many in a line" -
-- said the same thing in two numbers that could disagree, and the disagreement
-- was silent (a count of 7 in lines of 6 is a lonely second line nobody asked
-- for).
Externals.MAX_ROWS = 6
Externals.MAX_COLUMNS = 12
Externals.MAX_SLOTS = Externals.MAX_ROWS * Externals.MAX_COLUMNS

local function Clamp(value, low, high)
    value = math.floor(tonumber(value) or low)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Externals.Config()
    ns.db.externals = ns.db.externals or {}
    local cfg = ns.db.externals
    cfg.cells = cfg.cells or {}
    cfg.assigned = cfg.assigned or {}   -- [spellID] = "Name-Realm"
    cfg.channels = cfg.channels or {}

    -- THE OLDEST SHAPE FIRST, and the order is the whole point.
    --
    -- A profile written before the slots existed carries an ordered LIST.
    -- Poured into the cells in the order it had, once, and then dropped - a
    -- migration that runs twice would refill slots somebody has emptied.
    --
    -- This used to sit at the BOTTOM of this function, below the migration
    -- that deletes cfg.count - so `math.max(cfg.count, ...)` was reading a
    -- number that had just been removed and threw on login for anybody whose
    -- profile still had a `picked` list. Two migrations in one function are
    -- read oldest-first or they read each other's leftovers.
    if cfg.picked then
        for index, spellID in ipairs(cfg.picked) do
            if cfg.cells[index] == nil then cfg.cells[index] = spellID end
        end
        cfg.count = math.max(cfg.count or 6, #cfg.picked)
        cfg.picked = nil
    end

    -- A profile written before the lattice carries a count and a line width.
    -- Read once into rows and columns and then dropped - and it is dropped
    -- rather than kept in step, because two numbers for one shape is exactly
    -- what this replaced.
    if cfg.count or cfg.perLine then
        local perLine = Clamp(cfg.perLine or 6, 1, Externals.MAX_COLUMNS)
        local count = Clamp(cfg.count or 6, 1, Externals.MAX_SLOTS)
        cfg.columns = cfg.columns or perLine
        cfg.rows = cfg.rows or math.ceil(count / perLine)
        cfg.count, cfg.perLine = nil, nil
    end

    cfg.rows = Clamp(cfg.rows or 1, 1, Externals.MAX_ROWS)
    cfg.columns = Clamp(cfg.columns or 6, 1, Externals.MAX_COLUMNS)

    -- One channel, chosen before it could be several. Carried over, then
    -- dropped - a migration that runs twice would switch a channel somebody
    -- has just turned off back on.
    if cfg.channel then
        cfg.channels[cfg.channel] = true
        cfg.channel = nil
    end
    -- A profile that has never been asked sends a whisper, which is what the
    -- feature was built around.
    if next(cfg.channels) == nil then cfg.channels.WHISPER = true end

    return cfg
end

function Externals.Rows() return Externals.Config().rows end
function Externals.Columns() return Externals.Config().columns end

function Externals.Count()
    local cfg = Externals.Config()
    return cfg.rows * cfg.columns
end

-- WHAT FALLS OFF THE END STAYS PUT. Taking a lattice down and back up must
-- give you what you had - the same rule a bar's cells follow, and the reason
-- a shrunk bar does not forget its spells.
function Externals.SetRows(value)
    Externals.Config().rows = Clamp(value, 1, Externals.MAX_ROWS)
    Externals.Refresh()
end

function Externals.SetColumns(value)
    Externals.Config().columns = Clamp(value, 1, Externals.MAX_COLUMNS)
    Externals.Refresh()
end

-- WHERE SLOT `index` SITS, as a zero-based column and row. Pure, and the ONE
-- answer: the panel on screen and the preview on the settings page both ask
-- it, so a preview that disagrees with the screen is not a thing that can
-- happen. `down` is the growth setting - fill a column before wrapping
-- instead of a row.
function Externals.Cell(index, rows, columns, down)
    local slot = index - 1
    if down then
        return math.floor(slot / rows), slot % rows
    end
    return slot % columns, math.floor(slot / columns)
end

-- HOW BIG THE DRAWN THING IS, in columns and rows. A panel showing three of
-- its twelve places is three icons wide and one tall, not twelve by one: what
-- is not drawn takes up no room, which is the whole meaning of "verschwindet
-- ganz". Pure, and the panel's own size comes from it.
function Externals.Extent(shown, rows, columns, down)
    if shown <= 0 then return 0, 0 end
    if down then
        return math.ceil(shown / rows), math.min(shown, rows)
    end
    return math.min(shown, columns), math.ceil(shown / columns)
end

function Externals.SpellAt(index)
    return Externals.Config().cells[index]
end

function Externals.SetSlot(index, spellID)
    if index < 1 or index > Externals.MAX_SLOTS then return end
    if spellID and not byID[spellID] then return end
    local cfg = Externals.Config()

    -- One spell in one slot. Putting it somewhere else MOVES it rather than
    -- leaving a second copy, which would whisper twice for one click.
    if spellID then
        for other, id in pairs(cfg.cells) do
            if id == spellID and other ~= index then cfg.cells[other] = nil end
        end
    end

    cfg.cells[index] = spellID
    Externals.Refresh()
end

function Externals.ClearSlot(index)
    local cfg = Externals.Config()
    local spellID = cfg.cells[index]
    cfg.cells[index] = nil
    if spellID then cfg.assigned[spellID] = nil end
    Externals.Refresh()
end

-- Every spell on the panel, in slot order, holes skipped. What the SCREEN
-- draws and what the "Who to ask" rows walk.
function Externals.Picked()
    local out = {}
    local cfg = Externals.Config()
    for index = 1, Externals.Count() do
        if cfg.cells[index] then out[#out + 1] = cfg.cells[index] end
    end
    return out
end

function Externals.SlotOf(spellID)
    local cfg = Externals.Config()
    for index = 1, Externals.Count() do
        if cfg.cells[index] == spellID then return index end
    end
    return nil
end

function Externals.IsPicked(spellID)
    return Externals.SlotOf(spellID) ~= nil
end

-- Into the slot somebody has selected, or the first empty one. Answers the
-- index it used, or nil when every slot is full - which the page reports,
-- because a click that quietly does nothing reads as a broken list.
function Externals.Pick(spellID, preferred)
    if not byID[spellID] then return nil end
    if Externals.IsPicked(spellID) then return Externals.SlotOf(spellID) end

    local cfg = Externals.Config()
    if preferred and preferred >= 1 and preferred <= Externals.Count() then
        Externals.SetSlot(preferred, spellID)
        return preferred
    end

    for index = 1, Externals.Count() do
        if not cfg.cells[index] then
            Externals.SetSlot(index, spellID)
            return index
        end
    end
    return nil
end

function Externals.Drop(spellID)
    local index = Externals.SlotOf(spellID)
    if index then Externals.ClearSlot(index) end
end

---------------------------------------------------------------------------
-- WHO CAN CAST IT
--
-- Pure, and it takes the roster as a plain list, so the rule that decides
-- who gets whispered can be tested without a group - which is the only way
-- it ever will be tested, because a five-man with two paladins in it is not
-- something a self test can arrange.
--
-- Each member is { name = , class = , role = , isPlayer = }.
--
-- THE PLAYER HIMSELF IS NEVER A CANDIDATE. He is the tank asking for help;
-- a paladin tank whispering himself for a Blessing of Sacrifice is the panel
-- answering its own question.
---------------------------------------------------------------------------
function Externals.Candidates(spell, roster)
    local out = {}
    if not spell then return out end
    for _, member in ipairs(roster or {}) do
        if member.class == spell.class and not member.isPlayer then
            out[#out + 1] = member
        end
    end
    return out
end

-- WHO A CLICK ASKS. Owner's rule, in his words: "in 5 mann dungeons werden
-- heiler der klasse angewispert. im raid sollte man das zuweisen koennen."
--
-- So: an assignment wins whenever one has been made, and the group size
-- decides nothing about that - a name you typed in is a decision, and a
-- decision does not stop being one when the raid breaks up into a five-man.
--
-- With no assignment, the healer of that class is asked. Pain Suppression
-- belongs to a discipline priest and Life Cocoon to a mistweaver, and in a
-- five-man there is exactly one healer - so this is right nearly always and
-- wrong in a way that costs one whisper when it is not.
function Externals.Whom(spell, roster, assignedName)
    local candidates = Externals.Candidates(spell, roster)
    if #candidates == 0 then return nil end

    if assignedName then
        for _, member in ipairs(candidates) do
            if member.name == assignedName then return member, "assigned" end
        end
        -- The assigned player is not here any more. Falling through to the
        -- rule below is right, and saying so matters: a slot that silently
        -- whispers somebody else is worse than one that says it did.
    end

    for _, member in ipairs(candidates) do
        if member.role == "HEALER" then return member, "healer" end
    end

    return candidates[1], "only one"
end

-- WHO IS IN THE GROUP lives in Init.lua now: the taunt announce needs the
-- same list to find the other tank, and two walks over the same party would
-- be two chances to disagree about who is in it.
Externals.Roster = ns.Roster

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------
-- The message, with the spell's name written into it. One sentence for every
-- slot, editable, because "Ironbark bitte!" in German and a raid leader's own
-- wording are the same setting.
Externals.DEFAULT_MESSAGE = "%s bitte!"

-- WHERE IT GOES. Owner: "wir brauchen noch mehr funktionen, neben wisper,
-- /p /ra /y etc".
--
-- "GROUP" is one entry rather than three, and that is the whole reason it
-- exists: /p is NOT the party channel in a random dungeon. A group formed by
-- the finder talks on INSTANCE_CHAT, and a message sent to PARTY there
-- arrives nowhere at all - silently. IsInGroup(2) is the test, taken from
-- BigWigs, which picks its channel exactly this way in shipping code.
-- SEVERAL AT ONCE, not one of five. Owner: "wir brauchen hier eine
-- mehrfachauswahl, sorry, das hab ich falsch kommuniziert." A whisper to the
-- one person who can cast it AND a line in party chat is a reasonable thing
-- to want - the first is aimed, the second is insurance.
Externals.CHANNELS = ns.Chat.CHANNELS

function Externals.ChannelOn(value)
    local cfg = Externals.Config()
    return cfg.channels[value] and true or false
end

function Externals.ToggleChannel(value)
    local cfg = Externals.Config()
    cfg.channels[value] = (not cfg.channels[value]) or nil

    -- NEVER ALL OFF. A button that sends nowhere is not a setting, it is a
    -- button that does nothing - and the click that emptied the last one is
    -- exactly the click somebody would not notice doing it.
    for _ in pairs(cfg.channels) do return end
    cfg.channels.WHISPER = true
end

-- Kept under this name because the page, the tooltip and a hundred lines of
-- self test call it here. The rules themselves live in Core/Chat.lua now,
-- with the taunt announce as their second caller.
Externals.ResolveChannel = ns.Chat.ResolveChannel
Externals.SendingTo = ns.Chat.SendingTo

-- %s is the spell, %n is the person being asked. Two placeholders because a
-- whisper does not need a name in it and a message to the whole group does -
-- "Ironbark bitte!" in party chat asks nobody in particular.
function Externals.Message(spellName, targetName)
    local cfg = Externals.Config()
    local text = cfg.message
    if type(text) ~= "string" or text == "" then
        text = Externals.DEFAULT_MESSAGE
    end

    -- A message somebody edited down to no placeholder still has to name the
    -- spell, or every slot sends the same sentence and nobody knows which of
    -- their four buttons is being asked for.
    if not text:find("%%s") then
        text = text .. " (" .. (spellName or "?") .. ")"
    end

    return ns.Chat.Fill(text, { s = spellName or "?", n = targetName })
end

function Externals.Ask(spellID)
    local spell = byID[spellID]
    if not spell then return false, "not an external" end

    local cfg = Externals.Config()

    -- WHO is resolved whatever the channels are: the message names them, and
    -- "who would this ask" is the question the tooltip answers either way.
    local target, why = Externals.Whom(spell, Externals.Roster(),
        cfg.assigned[spellID])

    if cfg.channels.WHISPER and not target then
        -- A whisper with nobody to whisper is the one case worth refusing
        -- outright ONLY when it is the sole channel. With party chat also on,
        -- the message still has somewhere to go.
        local others = false
        for value in pairs(cfg.channels) do
            if value ~= "WHISPER" then others = true end
        end
        if not others then
            return false, "nobody in the group can cast it"
        end
    end

    local going = ns.Chat.Where(cfg.channels)

    -- A whisper with no recipient is dropped here rather than refused above:
    -- the other channels still carry the message.
    for index = #going, 1, -1 do
        if going[index].channel == "WHISPER" and not target then
            table.remove(going, index)
        end
    end

    if #going == 0 then
        return false, "there is nowhere to send it - you are not in a group"
    end

    local name = ns.SpellName(spellID) or ("Spell " .. spellID)
    local text = Externals.Message(name, target and target.name)
    local ok, note = ns.Chat.Post(text, going, target and target.name)
    if not ok then return false, note end

    -- AND THE SAME THING ON THE ADDON CHANNEL. Invisible, structured, and it
    -- does not depend on the wording of a sentence the player is allowed to
    -- edit - anybody in the group running this addon gets a button that
    -- answers instead of a line to read. The chat line above still goes out
    -- for everybody who does not.
    ns.Comm.Send(ns.Comm.REQUEST, ns.Comm.EXTERNAL, spellID)

    return true, target and target.name or going[1].channel, note or why
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel

function Externals.Frame() return panel end

local function SlotSize()
    return Externals.Config().size or 40
end

function Externals:Create()
    if panel then return panel end

    panel = CreateFrame("Frame", "ZwoelfStuffExternals", UIParent)
    panel:SetSize(200, 40)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel.slots = {}

    Externals.panel = panel
    self:ApplyLayout()
    return panel
end

-- Where it sits and how the icons are arranged. Its own function because
-- Edit Mode moves it and the options page re-arranges it, and both need the
-- same walk rather than two that agree today.
function Externals:ApplyLayout()
    if not panel then return end
    local cfg = Externals.Config()
    local size = SlotSize()
    local gap = cfg.gap or 4
    local rows, columns = cfg.rows, cfg.columns
    local vertical = cfg.growth == "down"

    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", cfg.x or -260, cfg.y or -160)

    local shown = 0
    for _, spellID in ipairs(Externals.Picked()) do
        -- A SLOT NOBODY CAN FILL IS NOT DRAWN. The owner's choice: "verschwindet
        -- ganz". So the panel is as wide as the help actually available, and
        -- an empty group leaves nothing on screen at all.
        -- WHILE PLACING OR TESTING, EVERY PICKED SLOT IS DRAWN. Otherwise a
        -- slot is only there when somebody present can actually fill it -
        -- the owner's choice, "verschwindet ganz" - which is right on a
        -- screen mid-pull and useless while you are arranging the thing.
        if Externals.placing or Externals.testing
            or #Externals.Candidates(byID[spellID], Externals.Roster()) > 0 then
            shown = shown + 1
            local slot = panel.slots[shown] or Externals.BuildSlot()
            panel.slots[shown] = slot
            slot.spellID = spellID

            -- The SAME lattice the settings page draws, from the same
            -- function. What is placed here is the SHOWN sequence rather than
            -- the slot number, so a spell nobody present can cast leaves no
            -- hole on screen - it closes up.
            local column, line = Externals.Cell(shown, rows, columns, vertical)

            slot:SetSize(size, size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", panel, "TOPLEFT",
                column * (size + gap), -(line * (size + gap)))
            slot.icon:SetTexture(ns.SpellTexture(spellID))

            -- THE PERSON THIS SLOT WOULD ASK, and what they still have. Only
            -- if they have said - somebody without the addon leaves the swipe
            -- off entirely rather than being drawn as ready.
            local target = Externals.Whom(byID[spellID], Externals.Roster(),
                cfg.assigned[spellID])
            local now = GetTime and GetTime() or 0
            local left = target and Externals.RemoteLeft(spellID, target.name, now)
            if left and left > 0 and slot.cooldown then
                slot.cooldown:SetCooldown(now - 0.001, left)
                slot.cooldown:Show()
            elseif slot.cooldown then
                slot.cooldown:Hide()
            end

            -- Painted every pass rather than only when a setting changes:
            -- the pass is a walk over at most two dozen icons, and "the
            -- border did not update" is a class of bug this buys off outright.
            local style = Externals.Style()
            ns.PaintSurface(slot.bg, style)
            ns.PaintBorder(slot.chrome, style, false)
            local zoom = style.iconZoom
            slot.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

            slot:Show()
        end
    end

    for index = shown + 1, #panel.slots do panel.slots[index]:Hide() end

    local wide, tall = Externals.Extent(shown, rows, columns, vertical)
    panel:SetSize(math.max(1, wide * size + (wide - 1) * gap),
        math.max(1, tall * size + (tall - 1) * gap))

    -- The panel's own scale and opacity, the two a bar carries as well.
    panel:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))
    panel:SetAlpha(math.max(0, math.min(1, cfg.alpha or 1)))

    panel:SetShown(shown > 0 and self:ShouldShow())
end

function Externals:ShouldShow()
    if not ns.Modules:IsOn("externals") then return false end
    -- Both of these outrank every rule below, and they are the two explicit
    -- requests to SEE the thing. `unlocked` used to be read off ns.EditMode
    -- here, where it is a FILE-LOCAL and therefore always nil - so the panel
    -- was never on screen in edit mode and its mover had nothing to sit on.
    -- Edit Mode calls SetPlacing now, the same door the co-tank panel and the
    -- reminders are opened through.
    if Externals.testing or Externals.placing then return true end
    local cfg = Externals.Config()
    if cfg.onlyInGroup ~= false and not IsInGroup() then return false end
    if cfg.onlyInCombat and not UnitAffectingCombat("player") then return false end
    return true
end

-- The style table the shared painters read. Built from the config under the
-- SAME key names a bar's is, so ns.PaintSurface and ns.PaintBorder need to
-- know nothing about this panel - and a change to how a border is drawn
-- reaches both without anybody remembering there are two places.
function Externals.Style()
    local cfg = Externals.Config()
    return {
        borderSize      = math.max(0, cfg.borderSize or 1),
        borderColor     = cfg.borderColor or { 0, 0, 0 },
        borderTexture   = cfg.borderTexture or "None",
        borderGradient  = cfg.borderGradient,
        backdrop        = cfg.backdrop ~= false,
        backdropColor   = cfg.backdropColor or { 0, 0, 0 },
        backdropAlpha   = cfg.backdropAlpha or 0.9,
        backdropTexture = cfg.backdropTexture or "Blizzard",
        backdropGradient = cfg.backdropGradient,
        iconZoom        = cfg.iconZoom or 0.08,
    }
end

function Externals.BuildSlot()
    local slot = CreateFrame("Button", nil, panel)
    slot:SetFrameStrata("MEDIUM")

    -- A PLATE, THE ART, THEN THE FRAME - the same three layers a cooldown
    -- cell has, in the same order, painted by the same two functions.
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints(slot)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)

    slot.chrome = ns.CreateChrome(slot)

    slot:SetScript("OnEnter", function(self)
        -- The hover is the panel's own, not a style: it says "this is the one
        -- you are about to press", and it has to be visible whatever border
        -- the user chose - including none at all.
        self.hover:Show()
        if not (GameTooltip and self.spellID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.SpellName(self.spellID) or "")
        end
        local spell = byID[self.spellID]
        local target, why = Externals.Whom(spell, Externals.Roster(),
            Externals.Config().assigned[self.spellID])
        if target then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to ask |cffffd100" .. target.name .. "|r"
                .. " (" .. (why or "") .. ")", 0.61, 0.64, 0.69)
        end
        GameTooltip:Show()
    end)

    slot:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    slot:SetScript("OnClick", function(self)
        local ok, whoOrWhy = Externals.Ask(self.spellID)
        if not ok then ns.Print("|cffff8040" .. tostring(whoOrWhy) .. ".|r") end
    end)

    -- ABOVE the chrome, or a thick border drawn on top of it would swallow
    -- the one signal that says the cursor is here.
    slot.hover = ns.CreateBorder(slot, 2, "OVERLAY")
    slot.hover:SetColor(ns.UI.C.accent[1], ns.UI.C.accent[2],
        ns.UI.C.accent[3], 1)
    slot.hover:Hide()

    -- SOMEBODY IS DOING IT. Its own ring rather than recolouring the hover
    -- one: they are two different facts and you can be hovering a slot while
    -- the answer arrives.
    slot.answer = ns.CreateBorder(slot, 3, "OVERLAY")
    slot.answer:SetColor(0.25, 1, 0.35, 1)
    slot.answer:Hide()

    -- THE OTHER PERSON'S COOLDOWN, drawn by the game's own swipe so it looks
    -- like every other cooldown on the screen. Only ever fed a number
    -- somebody REPORTED - see NoteCooldown.
    slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cooldown:SetAllPoints(slot)
    slot.cooldown:SetDrawEdge(false)
    slot.cooldown:SetHideCountdownNumbers(false)
    slot.cooldown:Hide()

    return slot
end

function Externals.Refresh()
    if not panel then return end
    Externals:ApplyLayout()
end

-- THE POSITION IS NOT RE-MEASURED WHEN EDIT MODE CLOSES, and that is a fix
-- rather than a shortcut. Owner, 2026-08-10: "im edit mode wird die position
-- der leiste von external cd immer zurückgesetzt."
--
-- It used to work the position out again from panel:GetCenter() minus
-- UIParent:GetCenter() - and those two are in DIFFERENT UNITS the moment the
-- panel carries a scale of its own, because GetCenter answers in the frame's
-- own coordinate space. So closing edit mode wrote a number that was the
-- dragged one divided by the scale, and the panel jumped. Every time.
--
-- Nothing else moves this frame: the mover writes cfg.x and cfg.y exactly,
-- ApplyLayout puts it there, and there is no StartMoving anywhere on it. The
-- co-tank panel DOES have one, which is why it keeps its own SavePosition -
-- and that one reads GetPoint, which needs no arithmetic at all.
function Externals:SavePosition()
    -- Deliberately nothing. See above.
end

-- Edit Mode is open and this panel is one of the things being placed.
function Externals:SetPlacing(on)
    Externals.placing = on and true or false
    if not Externals.placing then self:SavePosition() end
    Externals.Refresh()
end

function Externals:SetTestMode(on)
    Externals.testing = on and true or false
    Externals.Refresh()
end

---------------------------------------------------------------------------
-- SOMEBODY IS DOING IT
--
-- The other half of the addon channel: you asked, and their button says they
-- pressed it. Worth having on screen rather than only in chat - the whole
-- reason you asked is that you are busy, and "did anybody see that" is the
-- question a green ring answers without being read.
--
-- The ACK is sent when the spell ACTUALLY GOES OUT on their side, not when
-- they click - so this is "it is happening", not "somebody noticed".
---------------------------------------------------------------------------
function Externals.MarkAnswered(spellID, who)
    if not panel then return end
    for _, slot in ipairs(panel.slots) do
        if slot.spellID == spellID and slot:IsShown() then
            slot.answer:SetShown(true)
            if C_Timer and C_Timer.After then
                C_Timer.After(3, function() slot.answer:Hide() end)
            end
        end
    end
    if who then
        ns.Print(string.format("|cff40ff40%s|r is casting %s.", who,
            ns.SpellName(spellID) or "it"))
    end
end

---------------------------------------------------------------------------
-- WHAT THE OTHER PEOPLE STILL HAVE
--
-- The owner's idea, 2026-08-10, and it is the way past a wall this file has
-- had a paragraph about since 4.58.0: a foreign cooldown cannot be READ on
-- this patch, but the person who owns it can SAY it, and their own client
-- knows it exactly.
--
-- So this is not a guess and not a table of assumed durations - it is the
-- number from the machine that holds it. What is NOT known stays not known:
-- somebody without the addon reports nothing, and their slot shows nothing
-- rather than a hopeful clock.
---------------------------------------------------------------------------
-- [spellID][name] = when it is back, in GetTime terms. 0 means ready.
Externals.remote = {}

function Externals.NoteCooldown(spellID, who, secondsLeft, now)
    if not (spellID and who) then return end
    local store = Externals.remote[spellID]
    if not store then
        store = {}
        Externals.remote[spellID] = store
    end
    store[who] = (secondsLeft or 0) > 0 and (now + secondsLeft) or 0
end

-- Seconds left for that person, 0 when ready, nil when they have never said -
-- and nil is the important one: it is what somebody without the addon looks
-- like, and drawing them as ready would be inventing a fact.
function Externals.RemoteLeft(spellID, who, now)
    local store = Externals.remote[spellID]
    local at = store and who and store[who]
    if at == nil then return nil end
    if at == 0 then return 0 end
    local left = at - now
    return left > 0 and left or 0
end

ns.Comm.Listen(function(packet)
    local C = ns.Comm
    local now = GetTime and GetTime() or 0

    if packet.what == C.ACK and packet.kind == C.EXTERNAL then
        Externals.MarkAnswered(packet.spellID, packet.fromShort)
        return
    end

    if packet.kind ~= C.EXTERNAL then return end

    if packet.what == C.USED then
        Externals.NoteCooldown(packet.spellID, packet.fromShort, packet.value, now)
    elseif packet.what == C.READY or packet.what == C.HELLO then
        Externals.NoteCooldown(packet.spellID, packet.fromShort,
            packet.what == C.HELLO and packet.value or 0, now)
    else
        return
    end

    Externals.Refresh()
end)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
    if ns.db then Externals.Refresh() end
end)

-- What the panel would do right now, printed. The one question anybody has
-- about this feature is "who does this button whisper", and it has an answer
-- that can be read out of the group without pressing anything.
-- WHAT IT IS ACTUALLY PAINTED WITH. "the colour does nothing" has two very
-- different causes - a setting that never reached the painter, and a black
-- line on a black plate - and this tells them apart in one line.
local function StyleLine(style)
    local colour = style.borderColor or { 0, 0, 0 }
    return string.format(
        "border %d px, |cff%02x%02x%02x#%02x%02x%02x|r, texture %s; backdrop %s",
        style.borderSize or 0,
        (colour[1] or 0) * 255, (colour[2] or 0) * 255, (colour[3] or 0) * 255,
        (colour[1] or 0) * 255, (colour[2] or 0) * 255, (colour[3] or 0) * 255,
        tostring(style.borderTexture),
        style.backdrop == false and "off" or "on")
end

function Externals:Dump()
    ns.Print("|cffffd100externals|r - who each slot would ask.")

    if not ns.Modules:IsOn("externals") then
        ns.Print("  |cffff4040The Externals module is switched off.|r")
    end

    local roster = Externals.Roster()
    local cfg = Externals.Config()

    -- THE RAW SHAPE FIRST, and it is not decoration: "my panel is empty" has
    -- two completely different causes - nothing saved, or nothing drawn - and
    -- this line is what tells them apart without another evening of guessing.
    local slots = {}
    for index = 1, Externals.Count() do
        slots[#slots + 1] = tostring(cfg.cells[index] or "-")
    end
    ns.Print(string.format("  %d x %d, running %s: %s",
        cfg.rows, cfg.columns, cfg.growth == "down" and "down" or "across",
        table.concat(slots, " ")))
    ns.Print(string.format("  %d in the group, %d picked.",
        #roster, #Externals.Picked()))
    ns.Print("  " .. StyleLine(Externals.Style()))

    for _, spellID in ipairs(Externals.Picked()) do
        local spell = byID[spellID]
        local name = ns.SpellName(spellID) or ("Spell " .. spellID)
        local target, why = Externals.Whom(spell, roster,
            Externals.Config().assigned[spellID])
        if target then
            ns.Print(string.format("    %s -> |cff40ff40%s|r (%s)",
                name, target.name, why or ""))
        else
            ns.Print(string.format("    %s -> |cff888888nobody here can cast it|r",
                name))
        end
    end
end
