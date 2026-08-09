---------------------------------------------------------------------------
-- Death.lua - what killed you, and what could have prevented it
--
-- The owner's ask, in his words: when you die, a window with a quick
-- analysis - what came in, with numbers; which defensives were AVAILABLE;
-- whether a healthstone or a potion was sitting in the bags; and a way to
-- share the short version in chat.
--
-- WHERE THE DATA COMES FROM, because on this patch that is the whole design:
-- the combat log is gone and auras are secret, but Blizzard now runs its own
-- damage meter and death recap and lets an addon READ them -
-- C_DamageMeter.GetCombatSessionFromType lists the deaths of the current
-- fight, each carrying a deathRecapID, and C_DeathRecap.GetRecapEvents turns
-- that into the last events before the death: timestamp, amount, the health
-- you had left after each, overkill on the killing blow. The AMOUNTS ARE
-- REAL NUMBERS - EllesmereUIDamageMeters divides and compares them in
-- shipping code, which is how this was established. The spell NAME may be a
-- secret: displayable, but not comparable and never allowed into a chat
-- string. Every name in here goes through SafeName first.
--
-- "Was it available" is ns.History's estimate - own casts plus base
-- cooldown - because the client will not answer the question directly. The
-- window says "by our own clock" and means it.
---------------------------------------------------------------------------
local _, ns = ...

local Death = {}
ns.Death = Death

local UI -- ns.UI, taken late: Widgets loads after this file

-- The last capture, kept for the session only. Deaths are not saved
-- variables: an analysis is read in the minute after dying, not archived.
Death.snapshot = nil

-- How far back the quick analysis looks, in seconds. The recap itself
-- decides how many events it hands over; this only bounds OUR arithmetic.
local WINDOW = 10

---------------------------------------------------------------------------
-- Names, made safe
---------------------------------------------------------------------------

-- A name that is safe to compute with, concatenate, and send to chat - or a
-- fallback word derived from the event type, which is always ours. This is
-- the only door a recap string passes through.
function Death.SafeName(name, eventType)
    if type(name) == "string" and name ~= "" and ns.CanCompute(name) then
        return name
    end
    if eventType == "SWING_DAMAGE" then return "Melee" end
    if eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        return "a heal"
    end
    return "a spell"
end

---------------------------------------------------------------------------
-- The analysis - pure, exported, tested
--
-- events: oldest first, each { t, amount, hp, heal, name, overkill }
--         with t in seconds before death (0 = the killing blow), every
--         field already readable - Capture below guarantees that.
-- avail:  { { spellID, name, remaining, why } } - remaining 0 = ready by
--         our clock, nil = cannot tell (why says why).
-- items:  { { name, count } } - only what was actually in the bags.
---------------------------------------------------------------------------
function Death.Analyse(events, maxHP, avail, items)
    local out = {
        totalIn = 0, totalHealed = 0, hits = 0,
        biggest = nil,          -- { amount, name, pct }
        lastHealAgo = nil,      -- seconds before death the last heal landed
        readyDefensives = {},   -- names, ready and unpressed
        unknownDefensives = {}, -- names we cannot judge
        itemsInBags = {},       -- names with count > 0
        lines = {},             -- the verdict, one sentence per line
    }

    for _, ev in ipairs(events or {}) do
        if ev.t <= WINDOW then
            if ev.heal then
                out.totalHealed = out.totalHealed + (ev.amount or 0)
                if not out.lastHealAgo or ev.t < out.lastHealAgo then
                    out.lastHealAgo = ev.t
                end
            else
                out.totalIn = out.totalIn + (ev.amount or 0)
                out.hits = out.hits + 1
                if not out.biggest or (ev.amount or 0) > out.biggest.amount then
                    out.biggest = { amount = ev.amount or 0, name = ev.name }
                end
            end
        end
    end

    if out.biggest and maxHP and maxHP > 0 then
        out.biggest.pct = out.biggest.amount / maxHP
    end

    for _, entry in ipairs(avail or {}) do
        if entry.remaining == 0 then
            out.readyDefensives[#out.readyDefensives + 1] = entry.name
        elseif entry.remaining == nil then
            out.unknownDefensives[#out.unknownDefensives + 1] = entry.name
        end
    end

    for _, item in ipairs(items or {}) do
        if (item.count or 0) > 0 then
            out.itemsInBags[#out.itemsInBags + 1] = item.name
        end
    end

    -- The verdict. Written as observations, not accusations - the person
    -- reading this just died and the addon was not there.
    local lines = out.lines

    if out.hits > 0 then
        if out.biggest and out.biggest.pct and out.biggest.pct >= 0.4 then
            lines[#lines + 1] = string.format(
                "One hit did most of it: %s for %s - %d%% of your health.",
                out.biggest.name or "a spell", ns.ShortNumber(out.biggest.amount),
                math.floor(out.biggest.pct * 100 + 0.5))
        else
            lines[#lines + 1] = string.format(
                "No single killer: %d hits for %s over %ds.",
                out.hits, ns.ShortNumber(out.totalIn), WINDOW)
        end
    end

    if out.lastHealAgo and out.lastHealAgo > 3 then
        lines[#lines + 1] = string.format(
            "The last heal landed %.1fs before the end.", out.lastHealAgo)
    end

    if #out.readyDefensives > 0 then
        lines[#lines + 1] = "Ready and unpressed (by our own clock): "
            .. table.concat(out.readyDefensives, ", ") .. "."
    end

    if #out.itemsInBags > 0 then
        lines[#lines + 1] = "In the bags: "
            .. table.concat(out.itemsInBags, ", ") .. "."
    end

    if #lines == 0 then
        lines[#lines + 1] = "Not enough was readable to say anything useful."
    end

    return out
end

---------------------------------------------------------------------------
-- Finding our own recap
---------------------------------------------------------------------------

-- The realm half of a name, gone. The damage meter names people with realm,
-- UnitName("player") answers without one.
local function StripRealm(name)
    if type(name) ~= "string" then return name end
    local short = name:match("^(.-)%-")
    return short or name
end

-- The deathRecapID of OUR latest death in the current fight, or nil and why.
-- Read the way EllesmereUIDamageMeters reads it: the Deaths list of the
-- damage meter's current session, matched by name. Every step may be absent
-- or secret on this patch, so every step is guarded and names its failure.
function Death.OwnRecapID()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then
        return nil, "this client has no damage meter API"
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    if not ok or type(session) ~= "table" then
        return nil, "the damage meter has no current session"
    end

    local sources = session.sources or session
    if type(sources) ~= "table" or #sources == 0 then
        return nil, "the damage meter recorded no deaths this fight"
    end

    local me = UnitName("player")
    if not ns.CanCompute(me) then
        return nil, "the client withheld your own name"
    end

    -- Newest wins: iterate to the end, keep the last match. Dying twice in
    -- one fight lists two rows, and the one being asked about is always the
    -- one that just happened.
    local found
    for _, src in ipairs(sources) do
        local name = src.name
        if ns.CanCompute(name) and StripRealm(name) == me then
            local rid = src.deathRecapID
            if ns.CanCompute(rid) and type(rid) == "number" and rid > 0 then
                found = rid
            end
        end
    end
    if not found then
        return nil, "your death carries no readable recap id"
    end
    return found
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------

-- Health potions and healthstone. Item ids are stable facts; counts are
-- bag questions, not combat questions, and stay readable. The list is
-- deliberately short - the two things a healer will ask about first.
local RESCUE_ITEMS = {
    { itemID = 5512,   name = "Healthstone" },
    { itemID = 244839, name = "Invigorating Healing Potion" },
    { itemID = 211880, name = "Algari Healing Potion" },
}

local function ItemsInBags()
    local out = {}
    if not (C_Item and C_Item.GetItemCount) then return out end
    for _, item in ipairs(RESCUE_ITEMS) do
        local ok, count = pcall(C_Item.GetItemCount, item.itemID)
        if ok and type(count) == "number" and count > 0 then
            out[#out + 1] = { name = item.name, count = count }
        end
    end
    return out
end

-- What was still ready, off the defensives picked on the Timeline page.
local function Availability(now)
    local out = {}
    for spellID in pairs((ns.db and ns.db.defensives) or {}) do
        local name = ns.SpellName(spellID) or ("Spell " .. spellID)
        local remaining, why = ns.History:Estimate(spellID, now)
        out[#out + 1] = {
            spellID = spellID, name = name,
            remaining = remaining, why = why,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Reads the recap into OUR shape, with every field made safe at the door.
-- After this function nothing downstream needs a guard, which is the only
-- way the pure analysis can stay pure.
function Death.ReadRecap(recapID)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        return nil, nil, "this client has no death recap API"
    end
    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or type(raw) ~= "table" or #raw == 0 then
        return nil, nil, "the recap is empty"
    end

    local maxHP
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if ok2 and type(hp) == "number" and hp > 0 then maxHP = hp end
    end

    -- Newest first in the API; ours is oldest first with t = seconds before
    -- death, because that is the order a person reads a story in.
    local deathAt
    for i = 1, #raw do
        local ts = raw[i].timestamp
        if ns.CanCompute(ts) and type(ts) == "number" then
            deathAt = ts
            break
        end
    end

    -- WHO. The owner wants the killer on the window, and the recap MAY name
    -- a source - the field is unmeasured on this client, so three likely
    -- names are tried and the first readable one wins. /zs probe death dumps
    -- the real fields; when it has been run once, this list becomes one line.
    local killer
    for i = 1, #raw do
        local ev = raw[i]
        for _, key in ipairs({ "sourceName", "casterName", "caster" }) do
            local who = ev[key]
            if ns.CanCompute(who) and type(who) == "string" and who ~= "" then
                killer = who
                break
            end
        end
        if killer then break end
    end

    local events = {}
    for i = #raw, 1, -1 do
        local ev = raw[i]
        local amount = ev.amount
        local hp = ev.currentHP
        local ts = ev.timestamp
        local overkill = ev.overkill
        local kind = ns.CanCompute(ev.event) and ev.event or ""
        events[#events + 1] = {
            t = (deathAt and ns.CanCompute(ts) and type(ts) == "number")
                and math.max(0, deathAt - ts) or 0,
            amount = (ns.CanCompute(amount) and type(amount) == "number")
                and math.abs(amount) or 0,
            hp = (ns.CanCompute(hp) and type(hp) == "number") and hp or nil,
            heal = kind == "SPELL_HEAL" or kind == "SPELL_PERIODIC_HEAL",
            name = Death.SafeName(ev.spellName, kind),
            spellID = (ns.CanCompute(ev.spellId) and type(ev.spellId) == "number"
                and ev.spellId > 0) and ev.spellId or nil,
            overkill = (ns.CanCompute(overkill) and type(overkill) == "number"
                and overkill > 0) and overkill or nil,
        }
    end
    return events, maxHP, nil, killer
end

function Death:Capture()
    local now = GetTime()
    local recapID, why = Death.OwnRecapID()

    local events, maxHP, readWhy, killer
    if recapID then
        events, maxHP, readWhy, killer = Death.ReadRecap(recapID)
    end

    local avail = Availability(now)
    local items = ItemsInBags()

    self.snapshot = {
        at = now,
        when = date("%H:%M:%S"),
        events = events,
        maxHP = maxHP,
        killer = killer,
        avail = avail,
        items = items,
        reason = events == nil and (readWhy or why) or nil,
        analysis = Death.Analyse(events, maxHP, avail, items),
    }
    return self.snapshot
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

-- Where a share goes: the group that is actually around you. Solo it stays
-- in your own chat frame, because SAY from a corpse is noise with an
-- audience of zero.
local function ShareChannel()
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

-- The short version, built ONLY from lines the analysis already made safe.
function Death.ShareLines(snapshot)
    if not snapshot then return nil end
    local a = snapshot.analysis
    local lines = {}
    if a.hits > 0 then
        lines[#lines + 1] = string.format("Death %s: %s in %ds (%d hits).",
            snapshot.when or "", ns.ShortNumber(a.totalIn), WINDOW, a.hits)
    else
        lines[#lines + 1] = string.format("Death %s.", snapshot.when or "")
    end
    for _, line in ipairs(a.lines) do
        lines[#lines + 1] = line
    end
    return lines
end

function Death:Share()
    if not self.snapshot then
        ns.Print("No death recorded yet this session.")
        return
    end
    local lines = Death.ShareLines(self.snapshot) or {}
    local channel = ShareChannel()
    -- C_ChatInfo is the living call on this client (BigWigs' Loader uses
    -- it); the bare global is deprecated and only kept as the fallback.
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do
        if channel then
            send("ZwoelfStuff: " .. line, channel)
        else
            ns.Print(line)
        end
    end
    if not channel then
        ns.Print("|cff888888Not in a group - printed here instead.|r")
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame

-- One row of the event list: time, name, a health bar behind the amount.
-- The bar IS the graph - each row's fill is the health you still had after
-- that event, so reading down the list is watching the health drain.
local ROW_H = 22
local ROWS_MAX = 12

local function BuildWindow()
    UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffDeathFrame", UIParent)
    frame:SetSize(460, 480)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    frame.title = UI.Label(frame, "You died", 16, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)

    frame.sub = UI.Label(frame, "", 11, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local closeMark = UI.Glyph(close, "ui-close", 12, C.textDim)
    closeMark:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- The verdict block, above the event rows: the analysis is the point of
    -- the window, so it does not sit under a scroll.
    frame.verdict = UI.Label(frame, "", 12, C.text)
    frame.verdict:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
    frame.verdict:SetWidth(428)
    frame.verdict:SetJustifyH("LEFT")
    frame.verdict:SetJustifyV("TOP")
    frame.verdict:SetSpacing(3)

    -- Event rows, built once, filled per death.
    frame.rows = {}
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(428, ROW_H)

        row.fill = row:CreateTexture(nil, "BACKGROUND")
        row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

        row.when = UI.Label(row, "", 11, C.textDim)
        row.when:SetPoint("LEFT", row, "LEFT", 6, 0)

        -- The spell's icon, when the recap names a readable id. EllesmereUI
        -- resolves recap icons exactly this way in shipping code.
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 52, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.what = UI.Label(row, "", 12, C.text)
        row.what:SetPoint("LEFT", row, "LEFT", 74, 0)
        row.what:SetWidth(222)
        row.what:SetJustifyH("LEFT")
        row.what:SetWordWrap(false)

        row.amount = UI.Label(row, "", 12, C.text)
        row.amount:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        row:Hide()
        frame.rows[i] = row
    end

    -- Availability column footer: what was ready, what was in the bags.
    frame.avail = UI.Label(frame, "", 11, C.textDim)
    frame.avail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 46)
    frame.avail:SetWidth(428)
    frame.avail:SetJustifyH("LEFT")
    frame.avail:SetJustifyV("BOTTOM")
    frame.avail:SetSpacing(2)

    local share = UI.Button(frame, "Share in chat", 130, function()
        Death:Share()
    end, "primary")
    share:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)

    local dismiss = UI.Button(frame, "Close", 90, function()
        frame:Hide()
    end)
    dismiss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
end

function Death:Show()
    local snapshot = self.snapshot
    if not snapshot then
        ns.Print("No death recorded yet this session.")
        return
    end
    if not frame then BuildWindow() end

    -- The killer, when the recap named one readably. The name is already
    -- through SafeName's door or it would not be in the snapshot.
    if snapshot.killer then
        frame.sub:SetText(string.format("%s  -  killed by %s  -  the last %d seconds",
            snapshot.when or "", snapshot.killer, WINDOW))
    else
        frame.sub:SetText(string.format("%s  -  the last %d seconds",
            snapshot.when or "", WINDOW))
    end

    frame.verdict:SetText(table.concat(snapshot.analysis.lines, "\n"))

    -- Rows: the LAST events win the visible slots; oldest of those on top.
    local events = snapshot.events or {}
    local first = math.max(1, #events - ROWS_MAX + 1)
    local shown = 0
    local maxHP = snapshot.maxHP

    -- Anchored under the verdict, which wraps: measured, not guessed.
    local top = 58 + (frame.verdict:GetStringHeight() or 0) + 14

    for i = first, #events do
        shown = shown + 1
        local row = frame.rows[shown]
        local ev = events[i]

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16,
            -(top + (shown - 1) * (ROW_H + 2)))

        row.when:SetText(string.format("-%.1fs", ev.t))
        local icon = ev.spellID and ns.SpellTexture(ev.spellID)
        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.what:SetText(ev.name or "")
        local sign = ev.heal and "+" or "-"
        local extra = ev.overkill
            and string.format("  (%s overkill)", ns.ShortNumber(ev.overkill))
            or ""
        row.amount:SetText(sign .. ns.ShortNumber(ev.amount) .. extra)

        -- The fill is the health AFTER this event, so the story reads as a
        -- draining bar. A heal row paints the same bar in the green.
        local pct = (maxHP and ev.hp) and math.min(1, ev.hp / maxHP) or 0
        row.fill:SetWidth(math.max(1, 428 * pct))
        if ev.heal then
            row.fill:SetColorTexture(0.10, 0.35, 0.12, 0.55)
        else
            row.fill:SetColorTexture(0.42, 0.08, 0.08, 0.55)
        end
        row:Show()
    end
    for i = shown + 1, ROWS_MAX do frame.rows[i]:Hide() end

    if snapshot.reason then
        frame.avail:SetText("|cffff8040" .. snapshot.reason .. "|r")
    else
        local bits = {}
        for _, entry in ipairs(snapshot.avail or {}) do
            local state
            if entry.remaining == 0 then
                state = "|cff67c971ready|r"
            elseif entry.remaining then
                state = string.format("|cff9ba3af%ds to go|r",
                    math.floor(entry.remaining + 0.5))
            else
                state = "|cff626a76" .. (entry.why or "unknown") .. "|r"
            end
            bits[#bits + 1] = entry.name .. ": " .. state
        end
        frame.avail:SetText(#bits > 0
            and ("Defensives by our own clock -  " .. table.concat(bits, "   "))
            or "No defensives picked on the Timeline page yet.")
    end

    frame:Show()
end

---------------------------------------------------------------------------
-- The probe - every question at once, the way the Routes questions were
-- settled in one trip instead of five. Run it dead, on a corpse, after a
-- wipe: /zs death probe. What it prints decides which window fields stop
-- saying "unknown".
---------------------------------------------------------------------------
local function Verdict(value)
    if value == nil then return "|cff888888absent|r" end
    if not ns.CanCompute(value) then return "|cffff8040SECRET|r" end
    return "|cff40ff40" .. tostring(value) .. "|r"
end

local function DumpTable(label, tbl)
    ns.Print("  " .. label .. ":")
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        ns.Print("    " .. key .. " = " .. Verdict(tbl[key]))
    end
end

function Death:Probe()
    ns.Print("|cffffd100death probe|r - the damage meter first:")
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and Enum and Enum.DamageMeterType) then
        ns.Print("  C_DamageMeter is |cffff4040not on this client|r.")
        return
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    if not ok or type(session) ~= "table" then
        ns.Print("  no current Deaths session (not died this fight, or no fight).")
    else
        local sources = session.sources or session
        ns.Print(string.format("  Deaths session: %d entr%s.",
            #sources, #sources == 1 and "y" or "ies"))
        if sources[1] then DumpTable("first entry, every field", sources[1]) end
    end

    local recapID, why = Death.OwnRecapID()
    if not recapID then
        ns.Print("  own recap: |cffff8040" .. (why or "?") .. "|r")
        return
    end
    ns.Print("  own recap id: " .. Verdict(recapID))

    local okEv, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not okEv or type(raw) ~= "table" then
        ns.Print("  GetRecapEvents |cffff4040threw or answered nothing|r.")
        return
    end
    ns.Print(string.format("  %d recap events. The newest, every field:", #raw))
    if raw[1] then DumpTable("event 1", raw[1]) end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_DEAD")
watcher:SetScript("OnEvent", function()
    if ns.db and ns.db.death and ns.db.death.record == false then return end

    -- The recap needs a moment to exist: capture shortly after the fall,
    -- and once more a little later in case the meter was still writing.
    C_Timer.After(0.8, function()
        local snapshot = Death:Capture()
        local open = not (ns.db and ns.db.death) or ns.db.death.openOnDeath ~= false
        if snapshot.events == nil then
            C_Timer.After(2.0, function()
                snapshot = Death:Capture()
                if open then Death:Show() end
            end)
        elseif open then
            Death:Show()
        end
    end)
end)
