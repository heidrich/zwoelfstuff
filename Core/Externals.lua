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
function Externals.Config()
    ns.db.externals = ns.db.externals or {}
    local cfg = ns.db.externals
    cfg.picked = cfg.picked or {}       -- ordered list of spell ids
    cfg.assigned = cfg.assigned or {}   -- [spellID] = "Name-Realm", raid only
    return cfg
end

function Externals.Picked()
    return Externals.Config().picked
end

function Externals.IsPicked(spellID)
    for _, id in ipairs(Externals.Picked()) do
        if id == spellID then return true end
    end
    return false
end

function Externals.Pick(spellID)
    if not byID[spellID] or Externals.IsPicked(spellID) then return end
    local picked = Externals.Picked()
    picked[#picked + 1] = spellID
    Externals.Refresh()
end

function Externals.Drop(spellID)
    local picked = Externals.Picked()
    for index, id in ipairs(picked) do
        if id == spellID then
            table.remove(picked, index)
            break
        end
    end
    Externals.Config().assigned[spellID] = nil
    Externals.Refresh()
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

---------------------------------------------------------------------------
-- The live roster
---------------------------------------------------------------------------
local function GroupUnits(out)
    wipe(out)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do out[#out + 1] = "raid" .. index end
    elseif IsInGroup() then
        out[#out + 1] = "player"
        for index = 1, GetNumGroupMembers() - 1 do
            out[#out + 1] = "party" .. index
        end
    else
        out[#out + 1] = "player"
    end
    return out
end

local unitScratch, rosterScratch = {}, {}

function Externals.Roster()
    wipe(rosterScratch)
    for _, unit in ipairs(GroupUnits(unitScratch)) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            -- Readable on this patch, both of them, and checked anyway: a
            -- name that came back secret must not become a table key.
            if ns.CanCompute(name) and ns.CanCompute(class)
                and type(name) == "string" and type(class) == "string" then
                rosterScratch[#rosterScratch + 1] = {
                    name = name,
                    class = class,
                    role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
                    isPlayer = UnitIsUnit(unit, "player") and true or false,
                }
            end
        end
    end
    return rosterScratch
end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------
-- The message, with the spell's name written into it. One sentence for every
-- slot, editable, because "Ironbark bitte!" in German and a raid leader's own
-- wording are the same setting.
Externals.DEFAULT_MESSAGE = "%s bitte!"

function Externals.Message(spellName)
    local cfg = Externals.Config()
    local text = cfg.message
    if type(text) ~= "string" or text == "" then
        text = Externals.DEFAULT_MESSAGE
    end
    -- A message somebody edited down to no placeholder still has to name the
    -- spell, or every slot sends the same sentence and nobody knows which of
    -- their four buttons is being asked for.
    if not text:find("%%s") then
        return text .. " (" .. (spellName or "?") .. ")"
    end
    return (text:gsub("%%s", spellName or "?"))
end

function Externals.Ask(spellID)
    local spell = byID[spellID]
    if not spell then return false, "not an external" end

    local target, why = Externals.Whom(spell, Externals.Roster(),
        Externals.Config().assigned[spellID])
    if not target then
        return false, "nobody in the group can cast it"
    end

    local name = ns.SpellName(spellID) or ("Spell " .. spellID)
    -- C_ChatInfo first, the global as the fallback. The bare one is
    -- deprecated on this patch - BigWigs' loader takes the namespaced version
    -- outright, ChatThrottleLib takes it with exactly this fallback - and the
    -- death window's share already goes through the same pair.
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(Externals.Message(name), "WHISPER", nil, target.name)
    return true, target.name, why
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
    local perLine = math.max(1, cfg.perLine or 6)
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

            local line = math.floor((shown - 1) / perLine)
            local column = (shown - 1) % perLine
            local across = column * (size + gap)
            local down = line * (size + gap)

            slot:SetSize(size, size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", panel, "TOPLEFT",
                vertical and down or across,
                -(vertical and across or down))
            slot.icon:SetTexture(ns.SpellTexture(spellID))
            slot:Show()
        end
    end

    for index = shown + 1, #panel.slots do panel.slots[index]:Hide() end

    local lines = math.max(1, math.ceil(shown / perLine))
    local perLineShown = math.min(shown, perLine)
    if vertical then
        panel:SetSize(math.max(1, lines * size + (lines - 1) * gap),
            math.max(1, perLineShown * size + math.max(0, perLineShown - 1) * gap))
    else
        panel:SetSize(math.max(1, perLineShown * size + math.max(0, perLineShown - 1) * gap),
            math.max(1, lines * size + (lines - 1) * gap))
    end

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

function Externals.BuildSlot()
    local C = ns.UI.C

    local slot = CreateFrame("Button", nil, panel)
    slot:SetFrameStrata("MEDIUM")

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local edge = ns.CreateBorder(slot, 1, "OVERLAY")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    slot:SetScript("OnEnter", function(self)
        edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
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

    slot:SetScript("OnLeave", function()
        edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    slot:SetScript("OnClick", function(self)
        local ok, whoOrWhy = Externals.Ask(self.spellID)
        if not ok then ns.Print("|cffff8040" .. tostring(whoOrWhy) .. ".|r") end
    end)

    return slot
end

function Externals.Refresh()
    if not panel then return end
    Externals:ApplyLayout()
end

function Externals:SavePosition()
    if not panel then return end
    local cfg = Externals.Config()
    local x, y = panel:GetCenter()
    local px, py = UIParent:GetCenter()
    if x and y and px and py then
        cfg.x = math.floor(x - px + 0.5)
        cfg.y = math.floor(y - py + 0.5)
    end
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
function Externals:Dump()
    ns.Print("|cffffd100externals|r - who each slot would ask.")

    if not ns.Modules:IsOn("externals") then
        ns.Print("  |cffff4040The Externals module is switched off.|r")
    end

    local roster = Externals.Roster()
    ns.Print(string.format("  %d in the group, %d picked.",
        #roster, #Externals.Picked()))

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
