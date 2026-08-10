---------------------------------------------------------------------------
-- Answers - the other end of a request. Somebody asks; this is the button.
--
-- Owner, 2026-08-10: "wenn man selbst heiler ist" - so this is the mirror of
-- the externals panel. That one asks; this one is asked.
--
-- WHY THE BAR IS ALWAYS THERE AND ONLY LIGHTS UP, which is the whole shape of
-- this file and is dictated by the game rather than chosen:
--
--   A cell casts a real spell on a real person, so it is a
--   SecureActionButton. Its spell and its target live in ATTRIBUTES, and
--   attributes cannot be changed in combat. Neither can Show, Hide, SetPoint,
--   SetParent or a resize on a protected frame. Verified in EllesmereUIQoL's
--   raid tools, which writes the same rule at the top of its own file and
--   defers every options-driven change to PLAYER_REGEN_ENABLED.
--
--   So a cell CANNOT be pointed at whoever happens to have asked. It is
--   pointed at somebody while you are out of combat - which is the owner's
--   own question, "kann das addon beim gruppen bauen die erkannten spieler
--   schon reinschreiben?", and the answer is yes, that is exactly when.
--
--   What CAN change in combat is how it looks. So every cell that could ever
--   be needed stands there dimmed, and a request makes the right one shout.
--
-- WHAT THIS NEVER DOES: cast. The player presses the button and the GAME
-- casts. There is no path in this addon that reaches a protected function,
-- and there is not going to be one.
---------------------------------------------------------------------------
local _, ns = ...

local Answers = {}
ns.Answers = Answers

local Comm = ns.Comm

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
Answers.DEFAULTS = {
    -- OFF UNTIL ASKED FOR, and this is not the module switch - it is the same
    -- pair the co-tank panel has. The module being on is what makes the
    -- feature exist; this is what puts something on your screen. A bar that
    -- appears unbidden after an update is worse than one nobody has found,
    -- and the module defaults ON so that a request can still TELL you the
    -- feature is there. See Announce below.
    enabled   = false,
    size      = 40,
    gap       = 4,
    linger    = 8,       -- how long a request keeps shouting
    scale     = 1.0,
    alpha     = 1.0,
    idleAlpha = 0.35,    -- what a cell looks like with nothing to answer
    borderSize      = 1,
    borderTexture   = "None",
    backdrop        = true,
    backdropAlpha   = 0.90,
    backdropTexture = "Blizzard",
    iconZoom        = 0.08,
    onlyInInstance  = false,
}

function Answers.Config()
    ns.db.answers = ns.db.answers or {}
    local cfg = ns.db.answers
    for key, value in pairs(Answers.DEFAULTS) do
        if cfg[key] == nil then cfg[key] = value end
    end
    cfg.borderColor = cfg.borderColor or { 0, 0, 0 }
    cfg.backdropColor = cfg.backdropColor or { 0, 0, 0 }
    -- Which of your spells you are willing to be asked for. Absent means
    -- "not answered yet", and Offers reads that as yes - a spell you have
    -- never seen a switch for should be on the bar, not silently missing.
    cfg.offers = cfg.offers or {}
    return cfg
end

function Answers.Offering(spellID)
    return Answers.Config().offers[spellID] ~= false
end

-- `x and nil or y` NEVER YIELDS nil, and that is not a subtlety - it is the
-- shape of the bug. `true and nil` is nil, nil is false, so `or y` takes over
-- and the answer is y whichever way x went. Written that way, switching a
-- spell ON stored `false`, so it could be turned off exactly once and never
-- back on. Owner, 2026-08-10: "wenn ich den button auf aus schalte [...] kann
-- ich ihn nicht mehr anschalten."
--
-- An if. Every time. There is no clever form of this that works.
function Answers.SetOffering(spellID, on)
    local offers = Answers.Config().offers
    if on then
        offers[spellID] = nil     -- absent means yes, see Offering
    else
        offers[spellID] = false
    end
    Answers.Rebuild()
end

---------------------------------------------------------------------------
-- WHAT YOU CAN BE ASKED FOR
--
-- Pure, and it takes the class rather than reading it, because "what does a
-- paladin see" is a question this has to answer without being on a paladin.
--
-- Your class's externals, plus your taunt if you have one - a taunt request
-- is answered by pressing your OWN taunt, which is why it carries no target
-- spell of its own.
---------------------------------------------------------------------------
function Answers.Offers(class, chosen)
    local out = {}
    if not class then return out end

    for _, entry in ipairs(ns.Externals.SPELLS) do
        if entry.class == class
            and (not chosen or chosen[entry.spellID] ~= false) then
            out[#out + 1] = { spellID = entry.spellID, kind = Comm.EXTERNAL }
        end
    end

    for _, entry in ipairs(ns.Taunts.SPELLS) do
        if entry.class == class and not entry.spec
            and (not chosen or chosen[entry.spellID] ~= false) then
            out[#out + 1] = { spellID = entry.spellID, kind = Comm.TAUNT }
        end
    end

    return out
end

-- Blood's Death Grip is the one taunt with a spec on it, and Offers leaves
-- every spec-bound entry out rather than showing a frost death knight a
-- button that taunts nothing. His own taunt is Dark Command either way.

---------------------------------------------------------------------------
-- WHO MIGHT ASK
--
-- The tanks, and only the tanks. The request side of this addon is the
-- externals panel and the taunt button, and both belong to a tank - so a
-- cell per group member would be thirty-eight buttons for a question nobody
-- is going to ask from them.
---------------------------------------------------------------------------
Answers.MAX_ASKERS = 3

function Answers.Askers(roster)
    local out = {}
    for _, member in ipairs(roster or {}) do
        if not member.isPlayer and member.role == "TANK" then
            out[#out + 1] = member
            if #out >= Answers.MAX_ASKERS then break end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- WHAT IS PENDING
--
-- A list rather than one slot: two tanks asking at once is the moment this
-- feature is for, not an edge case.
---------------------------------------------------------------------------
Answers.pending = {}

-- Pure. Returns the list so a test can hold one of its own, and REPLACES the
-- entry from the same person for the same thing - pressing a request button
-- twice is one request, not two rows.
function Answers.Remember(list, packet, now)
    for _, entry in ipairs(list) do
        if entry.from == packet.fromShort and entry.kind == packet.kind
            and entry.spellID == packet.spellID then
            entry.at = now
            return list
        end
    end
    list[#list + 1] = {
        from = packet.fromShort, kind = packet.kind,
        spellID = packet.spellID, at = now,
    }
    return list
end

function Answers.Prune(list, now, linger)
    for index = #list, 1, -1 do
        if (now - list[index].at) > (linger or 8) then
            table.remove(list, index)
        end
    end
    return list
end

-- Does this cell answer that request? Pure, and it is the one rule the whole
-- feature turns on: the right cell lights up and the others do not.
function Answers.Matches(cell, entry)
    if not (cell and entry) then return false end
    if cell.who ~= entry.from then return false end
    if cell.kind ~= entry.kind then return false end
    -- A taunt request names no spell: any taunt of yours answers it.
    if entry.kind == Comm.TAUNT then return true end
    return cell.spellID == entry.spellID
end

function Answers.Waiting(list, cell, now, linger)
    for _, entry in ipairs(list) do
        if Answers.Matches(cell, entry)
            and (now - entry.at) <= (linger or 8) then
            return entry
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local panel, cells = nil, {}
local pendingRebuild = false

function Answers.Frame() return panel end

function Answers.Style()
    local cfg = Answers.Config()
    return {
        borderSize       = math.max(0, cfg.borderSize or 1),
        borderColor      = cfg.borderColor or { 0, 0, 0 },
        borderTexture    = cfg.borderTexture or "None",
        borderGradient   = cfg.borderGradient,
        backdrop         = cfg.backdrop ~= false,
        backdropColor    = cfg.backdropColor or { 0, 0, 0 },
        backdropAlpha    = cfg.backdropAlpha or 0.9,
        backdropTexture  = cfg.backdropTexture or "Blizzard",
        backdropGradient = cfg.backdropGradient,
        iconZoom         = cfg.iconZoom or 0.08,
    }
end

function Answers:ShouldShow()
    if not ns.Modules:IsOn("answers") then return false end
    if Answers.placing then return true end
    local cfg = Answers.Config()
    if not cfg.enabled then return false end
    if cfg.onlyInInstance and IsInInstance and not IsInInstance() then
        return false
    end
    return true
end

-- SOMEBODY ASKED AND YOU HAVE NO BAR TO ANSWER WITH.
--
-- The bar is off until it is switched on, which is right - but a request that
-- then does nothing at all is a feature that silently does nothing, which is
-- the same as one that does not work. So the first time in a session that
-- somebody asks you for something you could actually give, you are told once
-- what happened and where the switch is.
local told = false

function Answers.Announce(who, spellID)
    if told then return false end
    told = true
    ns.Print(string.format("|cffffd100%s asked you for %s.|r", who or "Somebody",
        spellID and (ns.SpellName(spellID) or "a cooldown") or "a taunt"))
    ns.Print("  Switch on |cffffd100Answering|r (/zs, under Tank stuff) and "
        .. "a button lights up for it instead of this line.")
    return true
end

local function BuildCell(index)
    if cells[index] then return cells[index] end

    -- SecureActionButtonTemplate, and the type is "macro" rather than
    -- "spell": a macro line takes [@Name], which survives the roster
    -- shuffling that moves party2 to party1 mid-key. The `unit` attribute
    -- takes a TOKEN, and a token is exactly the thing that changes under you.
    local cell = CreateFrame("Button", "ZwoelfStuffAnswer" .. index, panel,
        "SecureActionButtonTemplate")
    cell:RegisterForClicks("AnyUp")

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(cell)

    cell.chrome = ns.CreateChrome(cell)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)

    -- The shout: an accent ring and the asker's name. Both are pure looks,
    -- which is the only kind of change allowed on a protected frame while
    -- somebody is in combat - and combat is when this happens.
    cell.call = ns.CreateBorder(cell, 3, "OVERLAY")
    cell.call:SetColor(ns.UI.C.accent[1], ns.UI.C.accent[2], ns.UI.C.accent[3], 1)
    cell.call:Hide()

    cell.name = ns.UI.Label(cell, "", 10, ns.UI.C.text)
    cell.name:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
    cell.name:SetWordWrap(false)

    cell:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.spellName or "")
        GameTooltip:AddLine(self.who and ("On |cffffd100" .. self.who .. "|r")
            or "|cff888888Nobody to cast it on|r", 1, 1, 1)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    cells[index] = cell
    return cell
end

-- WHICH CELL IS WHICH, written while nobody is in combat.
--
-- Everything in here is a protected change - SetAttribute, SetPoint, a size.
-- In combat it is remembered and done again the moment the fight ends, which
-- is the pattern EllesmereUIQoL uses and names: applyPending.
function Answers.Rebuild()
    if not panel then return end

    if InCombatLockdown and InCombatLockdown() then
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local cfg = Answers.Config()
    local _, class = UnitClass("player")
    local offers = Answers.Offers(class, cfg.offers)
    local askers = Answers.Askers(ns.Roster())
    local size, gap = cfg.size or 40, cfg.gap or 4
    local style = Answers.Style()

    -- WHILE PLACING, THERE IS SOMETHING TO PLACE. Owner, 2026-08-10: "awnser
    -- button sehe ich im edit mode nicht" - and he was right: standing alone,
    -- there are no tanks to build cells FOR, so the bar had nothing in it and
    -- correctly drew nothing. Which is useless when the whole point of edit
    -- mode is to decide where it goes.
    --
    -- A stand-in row, and it carries NO macro: a cell aimed at nobody must do
    -- nothing when it is clicked rather than cast at whoever you happen to
    -- have targeted. The same rule the externals panel follows when it draws
    -- every picked slot while being placed.
    local preview = false
    if #askers == 0 and (Answers.placing or cfg.preview) then
        askers = { { name = "Tank", preview = true } }
        preview = true
    end
    if #offers == 0 and preview then
        offers = { { spellID = 355, kind = Comm.TAUNT, preview = true } }
    end

    local index = 0
    for row, asker in ipairs(askers) do
        for column, offer in ipairs(offers) do
            index = index + 1
            local cell = BuildCell(index)

            cell.who = asker.name
            cell.kind = offer.kind
            cell.spellID = offer.spellID
            cell.preview = asker.preview and true or false
            cell.spellName = ns.SpellName(offer.spellID)
                or ("Spell " .. offer.spellID)

            -- The macro the GAME runs when you click. Written here, out of
            -- combat, exactly once per roster change.
            --
            -- A stand-in cell gets NO macro at all: there is nobody called
            -- "Tank" to cast on, and a cell that fires at your current target
            -- instead would be the addon doing something you did not ask for.
            -- THE SAME `and nil or` TRAP, and here it was worse than a
            -- setting that would not switch: written that way, a stand-in
            -- cell got type="macro" AND a macro aimed at a player called
            -- "Tank" - the exact thing the paragraph above says must never
            -- happen. Two lines, both of them plain ifs.
            if asker.preview then
                cell:SetAttribute("type", nil)
                cell:SetAttribute("macrotext", nil)
            else
                cell:SetAttribute("type", "macro")
                cell:SetAttribute("macrotext",
                    string.format("/cast [@%s] %s", asker.name, cell.spellName))
            end

            cell:SetSize(size, size)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", panel, "TOPLEFT",
                (column - 1) * (size + gap), -(row - 1) * (size + gap))

            cell.icon:SetTexture(ns.SpellTexture(offer.spellID))
            ns.PaintSurface(cell.bg, style)
            ns.PaintBorder(cell.chrome, style, false)
            local zoom = style.iconZoom
            cell.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            cell.name:SetText(asker.name)

            cell:Show()
        end
    end

    for spare = index + 1, #cells do
        cells[spare].who = nil
        cells[spare]:Hide()
    end

    local wide = math.max(1, #offers)
    local tall = math.max(1, #askers)
    panel:SetSize(wide * size + (wide - 1) * gap,
        tall * size + (tall - 1) * gap)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -260)
    panel:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))

    panel:SetShown(index > 0 and Answers:ShouldShow())
    Answers.Repaint()
end

-- WHAT CHANGES WHILE SOMEBODY IS FIGHTING. Alpha, a ring, a word - and
-- nothing else, because nothing else is allowed and nothing else is needed.
function Answers.Repaint()
    if not panel then return end

    local cfg = Answers.Config()
    local now = GetTime and GetTime() or 0
    Answers.Prune(Answers.pending, now, cfg.linger)

    local idle = math.max(0, math.min(1, cfg.idleAlpha or 0.35))
    local lit = math.max(0, math.min(1, cfg.alpha or 1))

    for _, cell in ipairs(cells) do
        if cell.who then
            -- A stand-in cell is drawn at full strength with its name on it:
            -- while you are placing the bar, "which of these is it" is the
            -- only question, and a dimmed square answers it badly.
            if cell.preview then
                cell:SetAlpha(lit)
                cell.call:Hide()
                cell.name:Show()
            else
                local waiting = Answers.Waiting(Answers.pending, cell, now,
                    cfg.linger)
                cell:SetAlpha(waiting and lit or idle)
                cell.call:SetShown(waiting ~= nil)
                cell.name:SetShown(waiting ~= nil)
            end
        end
    end
end

function Answers:SavePosition()
    -- NOTHING, on purpose. Working the position out again from GetCenter
    -- minus UIParent:GetCenter() mixes two coordinate spaces the moment this
    -- carries a scale of its own, and the frame jumps every time edit mode
    -- closes. The mover writes cfg.x and cfg.y exactly; nothing else moves
    -- this. See the long note in Externals.lua.
end

function Answers:SetPlacing(on)
    Answers.placing = on and true or false
    if not Answers.placing then self:SavePosition() end
    Answers.Rebuild()
end

function Answers.Refresh() Answers.Rebuild() end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function Answers:Create()
    if panel then return panel end

    panel = CreateFrame("Frame", "ZwoelfStuffAnswers", UIParent)
    panel:SetSize(40, 40)
    panel:SetClampedToScreen(true)
    panel:Hide()

    Answers.panel = panel
    self:Rebuild()
    return panel
end

function Answers:Start()
    if self.started then return end
    self.started = true

    Comm.Listen(function(packet)
        if packet.what ~= Comm.REQUEST then return end
        if not ns.Modules:IsOn("answers") then return end

        -- Only what you could actually answer. A druid being told that
        -- somebody wants Pain Suppression is noise: there is no button of
        -- his that answers it.
        local _, class = UnitClass("player")
        local mine = false
        for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers)) do
            if offer.kind == packet.kind
                and (packet.kind == Comm.TAUNT
                    or offer.spellID == packet.spellID) then
                mine = true
            end
        end
        if not mine then return end

        if not Answers.Config().enabled then
            Answers.Announce(packet.fromShort, packet.spellID)
            return
        end

        Answers.Remember(Answers.pending, packet,
            GetTime and GetTime() or 0)
        Answers.Repaint()

        if Answers.Config().sound ~= false and PlaySound then
            pcall(PlaySound, 8959)   -- the raid-warning chime
        end
    end)

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
        if not ns.db then return end

        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            Answers.OnCast(spellID)
            return
        end

        -- PLAYER_REGEN_ENABLED is the moment a rebuild that was refused in
        -- combat is allowed. The roster events are why it would have been
        -- asked for at all.
        if event ~= "PLAYER_REGEN_ENABLED" or pendingRebuild then
            Answers.Rebuild()
        end

        -- AND SAY WHAT YOU HAVE. A tank who joins mid-key missed every
        -- message sent before he arrived, so the group re-introduces itself
        -- whenever it changes. Two seconds late on purpose: a roster event
        -- comes in a burst of three or four while people load in.
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            if C_Timer and C_Timer.After then
                C_Timer.After(2, Answers.ReportAll)
            end
        end
    end)

    -- Ten a second is what everything else in this addon repaints at, and
    -- this one only changes an alpha and a ring.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.2, function()
            if panel and panel:IsShown() then Answers.Repaint() end
        end)
    end
end

---------------------------------------------------------------------------
-- TELLING THE GROUP WHAT YOU HAVE
--
-- The owner's idea, and it is the one that gets past the wall this addon has
-- been standing at since 4.58.0: a foreign cooldown cannot be READ, but the
-- person who owns it can SAY it. Every client knows its own perfectly.
--
-- Sent as an addon message, not a chat line - same information, invisible,
-- and it does not fill the party window with "lay on hands rdy" every ten
-- minutes.
---------------------------------------------------------------------------
-- What the client says about one of your own spells. Answers the seconds
-- left, 0 when it is ready, and nil when the client will not say - which is
-- a different answer and must not be reported as "ready".
function Answers.Remaining(spellID)
    local info = C_Spell and C_Spell.GetSpellCooldown
        and C_Spell.GetSpellCooldown(spellID)
    if type(info) ~= "table" then return nil end

    local start, duration = info.startTime, info.duration
    if not (ns.CanCompute(start) and ns.CanCompute(duration)) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end

    -- A duration under two seconds is the global cooldown, not this spell's.
    -- Reporting THAT as "used" would blink every icon in the group every
    -- time the healer pressed anything at all.
    if start == 0 or duration <= 1.5 then return 0 end

    local left = (start + duration) - (GetTime and GetTime() or 0)
    return left > 0 and left or 0
end

-- Announce one spell's state. Sent on a cast, when it comes back, and once
-- when the group changes - the last one is what a tank joining mid-key needs,
-- because he missed every message that came before he was there.
function Answers.Report(spellID, kind)
    local left = Answers.Remaining(spellID)
    if left == nil then return false end

    if left <= 0 then
        return Comm.Send(Comm.READY, kind or Comm.EXTERNAL, spellID, 0)
    end
    return Comm.Send(Comm.USED, kind or Comm.EXTERNAL, spellID, left)
end

function Answers.ReportAll()
    if not ns.Modules:IsOn("answers") then return end
    local _, class = UnitClass("player")
    for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers)) do
        Answers.Report(offer.spellID, offer.kind)
    end
end

-- YOU PRESSED IT. The honest signal that a request was answered is the spell
-- actually going out - not the click, which happens whether the cast lands or
-- not. Whoever asked gets told, and the request stops shouting here.
function Answers.OnCast(spellID)
    local now = GetTime and GetTime() or 0
    local answered = nil

    for index = #Answers.pending, 1, -1 do
        local entry = Answers.pending[index]
        local isTaunt = entry.kind == Comm.TAUNT
            and ns.Taunts.IsTaunt(spellID)
        if isTaunt or entry.spellID == spellID then
            answered = entry
            table.remove(Answers.pending, index)
        end
    end

    -- THE COOLDOWN GOES OUT WHETHER ANYBODY ASKED OR NOT. A tank wants to
    -- know his healer just spent Lay on Hands even if the press was the
    -- healer's own idea - which it usually is.
    --
    -- One frame later: the cooldown does not exist yet in the moment the cast
    -- succeeds, so asking now would answer "ready" and undo itself.
    local _, class = UnitClass("player")
    for _, offer in ipairs(Answers.Offers(class, Answers.Config().offers)) do
        if offer.spellID == spellID then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    Answers.Report(spellID, offer.kind)
                    -- And once more when it should be back, so "ready" is a
                    -- fact rather than the tank's arithmetic. Verified before
                    -- it is sent: a reset or a second charge would make the
                    -- guess wrong in the direction that matters.
                    local left = Answers.Remaining(spellID)
                    if left and left > 0 then
                        C_Timer.After(left + 0.2, function()
                            Answers.Report(spellID, offer.kind)
                        end)
                    end
                end)
            end
        end
    end

    if not answered then return end
    Comm.Send(Comm.ACK, answered.kind, answered.spellID)
    Answers.Repaint()
    return answered, now
end

---------------------------------------------------------------------------
-- What is waiting, printed
---------------------------------------------------------------------------
function Answers:Dump()
    ns.Print("|cffffd100answers|r - what you could be asked for, and by whom.")

    if not ns.Modules:IsOn("answers") then
        ns.Print("  |cffff4040The Answering module is switched off.|r")
    end

    local _, class = UnitClass("player")
    local offers = Answers.Offers(class, Answers.Config().offers)
    local names = {}
    for _, offer in ipairs(offers) do
        names[#names + 1] = ns.SpellName(offer.spellID)
            or tostring(offer.spellID)
    end
    ns.Print("  you offer: " .. (#names > 0 and table.concat(names, ", ")
        or "|cff888888nothing your class has|r"))

    local askers = Answers.Askers(ns.Roster())
    local who = {}
    for _, member in ipairs(askers) do who[#who + 1] = member.name end
    ns.Print("  tanks who could ask: " .. (#who > 0 and table.concat(who, ", ")
        or "|cff888888nobody else is tanking|r"))

    ns.Print(string.format("  %d cell%s on the bar, %d waiting.",
        #cells, #cells == 1 and "" or "s", #Answers.pending))

    for _, entry in ipairs(Answers.pending) do
        ns.Print(string.format("    |cff40ff40%s|r asked for %s",
            entry.from, entry.spellID
                and (ns.SpellName(entry.spellID) or entry.spellID)
                or "a taunt"))
    end
end
