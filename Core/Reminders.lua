---------------------------------------------------------------------------
-- Reminders - a line of text on the screen when something is wrong
--
-- WHAT IT IS FOR.
--
-- A bar tells you the state of a cooldown while you are looking at it. A
-- reminder is for the state you are NOT looking at: Bone Shield has fallen
-- off, and you are watching the boss. So it is deliberately not subtle -
-- large type near the middle of the screen, optionally flashing, and gone the
-- instant the condition it names stops being true.
--
-- WHERE THE ANSWER COMES FROM, AND WHY IT IS NOT AN AURA SCAN.
--
-- On patch 12.0 an aura's fields are secret values: a buff cannot be found by
-- ID, name or icon, so "do I have Bone Shield" has no direct answer in Lua at
-- all. What DOES answer is Blizzard's own Cooldown Manager - it already
-- tracks the spell, and its item frame knows whether the thing is active.
-- ns.CDM:ItemIsActive reads that one clean boolean off the frame.
--
-- Two consequences worth saying out loud rather than discovering:
--
--   1. A REMINDER CAN ONLY WATCH A SPELL THE COOLDOWN MANAGER TRACKS. That
--      is most of what anyone would want to be reminded about, and it is the
--      same set the bars can show. When it is not tracked, the reminder says
--      so on its own page instead of silently never firing.
--
--   2. "ACTIVE" MEANS WHAT BLIZZARD MEANS BY IT, and that differs by where
--      the spell sits: a tracked buff is active while the buff is on you, a
--      cooldown is active while the cooldown is running. Rather than guess
--      which one a given spell is and be wrong, the options page shows the
--      live state next to the spell you picked, so the setting is read off
--      the screen rather than out of a manual.
--
-- WHEN IT IS ALLOWED TO SHOW AT ALL is ns.Visibility, the same evaluator the
-- bars use - one vocabulary for "only in combat", "only in raids", "only on
-- these specs". A second set of words for the same idea is how a settings
-- page starts having to be learned.
---------------------------------------------------------------------------
local _, ns = ...

local Reminders = {}
ns.Reminders = Reminders

-- More than this is a screen nobody can read anyway, and the number is here
-- rather than inline so the options page and the evaluator cannot disagree.
local MAX = 12
Reminders.MAX = MAX

-- How often the condition is re-asked. The flash runs every frame; this does
-- not need to. A tenth of a second is faster than anyone reacts and costs one
-- boolean read per reminder.
local CHECK_INTERVAL = 0.1

---------------------------------------------------------------------------
-- The vocabulary
--
-- Every list here is also what the options page shows, so a trigger cannot
-- exist in the evaluator and be missing from the editor.
---------------------------------------------------------------------------

-- What makes the message appear.
--
-- Both entries are the SAME read with the sense flipped, which is the whole
-- reason there are two of them rather than a "not" switch: "when Bone Shield
-- is missing" is the thing you want to write down, and "invert the condition"
-- is a thing you have to work out.
ns.REMINDER_TRIGGERS = {
    { value = "missing", text = "When it is not active",
      hint = "A buff that has fallen off, or a cooldown that is ready." },
    { value = "active",  text = "While it is active",
      hint = "A buff that is up, or a cooldown that is still running." },
}

ns.REMINDER_ANCHORS = {
    { value = "CENTER", text = "Middle of the screen" },
    { value = "TOP",    text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
}

-- The icon can sit on either side of the words, or be left off. Above and
-- below are deliberately not offered: a reminder is one line read at a
-- glance, and stacking it makes it a block you have to look AT.
ns.REMINDER_ICON_SIDES = {
    { value = "left",  text = "Left of the text" },
    { value = "right", text = "Right of the text" },
    { value = "none",  text = "No icon" },
}

function Reminders:Defaults()
    return {
        enabled = true,
        text    = "",
        spellID = nil,
        trigger = "missing",

        -- The bars' own rule set, with ONE default changed: a reminder that
        -- shows while you are standing in the city is a reminder you learn to
        -- ignore, and "only in combat" is what anybody setting one up means.
        show = {
            mode    = "rules",
            combat  = "in",
            target  = "any",
            group   = "any",
            resting = "any",
            where   = { none = true, party = true, raid = true,
                        scenario = true, pvp = true, arena = true },
            specs   = {},
        },

        -- The look
        font     = "",
        size     = 34,
        outline  = "THICKOUTLINE",
        color    = { 1.00, 0.36, 0.30 },

        iconSide = "left",
        iconSize = 34,

        flash     = true,
        flashRate = 1.1,      -- full cycles per second
        flashMin  = 0.25,     -- how far down the fade goes, never to nothing

        -- Where
        point    = "CENTER",
        relPoint = "CENTER",
        x        = 0,
        y        = 180,
        scale    = 1.0,
    }
end

-- A NAME THAT IS NEVER EMPTY. The list on the options page needs something to
-- print, and a reminder is usually identified by the spell it watches rather
-- than by anything typed - so the spell comes first, the text second, and the
-- position last. Somebody who has dragged nothing in yet still gets a row
-- they can click.
function Reminders:Label(cfg, index)
    if cfg.spellID then
        local name = ns.SpellName(cfg.spellID)
        if name and name ~= "" then return name end
    end
    local text = cfg.text
    if text and text ~= "" then
        local firstLine = text:match("^[^\r\n]*") or text
        firstLine = firstLine:gsub("^%s+", ""):gsub("%s+$", "")
        if firstLine ~= "" then
            if #firstLine > 24 then firstLine = firstLine:sub(1, 23) .. "..." end
            return firstLine
        end
    end
    return "Reminder " .. tostring(index or "?")
end

---------------------------------------------------------------------------
-- The store
---------------------------------------------------------------------------
-- PER SPEC, at the owner's word: "reminders auch". What you want reminding
-- about is the most spec-shaped setting in the addon - a tank's reminders
-- are about staying alive and the same character's damage spec is being
-- reminded of something else entirely.
--
-- The whole LIST moves, not the individual reminders: a reminder carries its
-- own position, and one that belongs to a spec you are not playing has
-- nothing to show. ns.db.reminders is left where it is for the version
-- before this one.
function Reminders:All()
    local mine = ns.SpecStore("remindersBySpec", "reminders")
    if mine then return mine end

    -- Only while the client has not named the spec. A throwaway rather than
    -- the profile-wide list, because adding a reminder in that second would
    -- otherwise write into a list that every spec then inherits.
    local list = ns.db and ns.db.reminders
    if type(list) ~= "table" then return {} end
    return list
end

function Reminders:Count()
    return #self:All()
end

function Reminders:Get(index)
    return self:All()[index]
end

function Reminders:Add()
    local list = self:All()
    if #list >= MAX then return nil end
    list[#list + 1] = self:Defaults()
    self:Rebuild()
    return #list
end

function Reminders:Remove(index)
    local list = self:All()
    if not list[index] then return end
    table.remove(list, index)
    self:Rebuild()
end

-- Applied to whatever is in the profile, so a reminder saved by an older
-- version gains the keys added since without losing what it had.
function Reminders:Migrate()
    for _, cfg in ipairs(self:All()) do
        ns.ApplyDefaults(cfg, self:Defaults())
    end
end

---------------------------------------------------------------------------
-- The condition
--
-- Split into two questions on purpose, because they fail differently and the
-- options page has to be able to say WHICH one is stopping a reminder:
--
--   State  - what the Cooldown Manager says about the spell right now.
--            "active", "idle", or a reason it cannot answer.
--   Should - whether the message belongs on screen, which needs the state
--            AND the visibility rules AND the master switch.
---------------------------------------------------------------------------

-- Returns "active" | "idle" | nil, and a reason string when it is nil.
--
-- nil is NOT false. A spell the Cooldown Manager does not track cannot be
-- reported as missing, or every reminder anybody mistyped would sit on screen
-- permanently insisting a buff is gone. Unanswerable means silent.
function Reminders:State(cfg)
    if not cfg then return nil, "no reminder" end
    if not cfg.spellID then return nil, "no spell picked yet" end

    if not (ns.CDM and ns.CDM:IsAvailable()) then
        return nil, ns.CDM and ns.CDM:UnavailableReason()
            or "the Cooldown Manager is not up"
    end

    local item = ns.CDM:ItemForSpell(cfg.spellID)
    if not item then
        -- "Not tracking" was the wrong words and sent people looking in the
        -- wrong place. Most spells the Cooldown Manager KNOWS sit in its
        -- Hidden category by default - our picker lists them under Cooldowns
        -- with everything else, marked on the entry - and a spell with no
        -- frame on screen has nothing for us to read. The fix is one drag in
        -- Blizzard's own settings, so that is what the sentence says.
        return nil, "Blizzard is not showing this spell in its Cooldown "
            .. "Manager, so there is no frame to read. Drag it into one of "
            .. "its viewers in Blizzard's own Cooldown Manager settings"
    end

    local active = ns.CDM:ItemIsActive(item)
    if active == nil then return nil, "the frame will not say" end
    return active and "active" or "idle"
end

-- Does the state satisfy the trigger? Pure, and exported for the test: this
-- is the one place the two words in REMINDER_TRIGGERS turn into a decision,
-- and it must not be spelled out a second time in the renderer.
function Reminders.Fires(trigger, state)
    if state ~= "active" and state ~= "idle" then return false end
    if trigger == "active" then return state == "active" end
    return state == "idle"
end

-- THE TWO ESCAPES COME FIRST, and the order is the whole function.
--
-- `enabled` is the master switch, and it sat above them once on the co-tank
-- panel - where it meant that asking to MOVE the thing, or to preview it,
-- both did nothing on a fresh profile. Both are explicit requests to SEE it,
-- so both outrank every rule below, including the switch.
function Reminders:ShouldShow(cfg)
    if not cfg then return false end
    -- The module switch outranks even the two below it, for the reason the
    -- co-tank panel's does: preview and placing are requests to see a feature
    -- that is running, and there is nobody at a greyed-out page to ask.
    if ns.Modules and not ns.Modules:IsOn("reminders") then return false end
    if self.previewing == cfg then return true end
    if self.placing then return true end
    if not cfg.enabled then return false end
    if not ns.Visibility:Evaluate(cfg) then return false end

    local state = self:State(cfg)
    return self.Fires(cfg.trigger, state)
end

-- Edit Mode holds every reminder on screen while the overlay is up, or there
-- is nothing to drag: a message that only appears when a buff has dropped is
-- a message you cannot place while standing in a city.
function Reminders:SetPlacing(on)
    self.placing = on and true or false
    self:Refresh()
end

-- Why nothing is on screen, in one sentence, or nil when it IS on screen.
-- The options page prints this under the spell, so "it does not work" has an
-- answer without anybody reading code.
function Reminders:Explain(cfg)
    if not cfg then return "no reminder" end
    -- THE SWITCH IS REPORTED FIRST. A page that explains at length why one
    -- reminder is not firing, while the whole module is off, is a page that
    -- sends somebody reading their own trigger for a fault that is not there.
    if ns.Modules and not ns.Modules:IsOn("reminders") then
        return "The Reminders module is switched off."
    end
    if not cfg.enabled then return "This reminder is switched off." end

    local state, why = self:State(cfg)
    if not state then
        return "Cannot tell: " .. (why or "no reason given") .. "."
    end

    local ruleReason = ns.Visibility:Explain(cfg)
    if ruleReason then return ruleReason end

    if not self.Fires(cfg.trigger, state) then
        return state == "active"
            and "It is active right now, so there is nothing to remind you of."
            or "It is not active right now, and this reminder waits for it to be."
    end
    return nil
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------
local frames = {}

local function BuildFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:Hide()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    -- Fonted here, because SetText on a FontString with no font raises.
    ns.Media.ApplyFont(frame.text, nil, 32, "THICKOUTLINE")
    frame.text:SetJustifyH("CENTER")

    return frame
end

-- THE SIZE IS MEASURED, NEVER GUESSED.
--
-- A reminder is dragged in Edit Mode, so it needs a real width and height or
-- the mover is a box that does not match the words under it. GetStringWidth
-- is the only thing that knows how wide a font at a size renders, so the
-- frame is sized FROM the text rather than the text fitted INTO the frame.
--
-- Pure and exported for the same reason the layout rules are: the desktop
-- harness answers GetStringWidth with a stub, so the arithmetic is checked
-- here and the drawing is checked by a pair of eyes.
function Reminders.Extent(textWidth, textHeight, iconSide, iconSize, gap)
    local wide, tall = textWidth, textHeight
    if iconSide == "left" or iconSide == "right" then
        wide = wide + iconSize + gap
        if iconSize > tall then tall = iconSize end
    end
    return math.max(1, wide), math.max(1, tall)
end

local ICON_GAP = 8

function Reminders:Style(index)
    local cfg = self:Get(index)
    local frame = frames[index]
    if not (cfg and frame) then return end

    ns.Media.ApplyFont(frame.text, cfg.font ~= "" and cfg.font or nil,
        cfg.size, cfg.outline, cfg.color)
    frame.text:SetText(cfg.text or "")

    local side = cfg.iconSide or "left"
    local hasIcon = (side == "left" or side == "right") and cfg.spellID
    frame.icon:ClearAllPoints()
    frame.text:ClearAllPoints()

    if hasIcon then
        frame.icon:SetTexture(ns.SpellTexture(cfg.spellID))
        frame.icon:SetSize(cfg.iconSize, cfg.iconSize)
        frame.icon:Show()
        if side == "left" then
            frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.text:SetPoint("LEFT", frame.icon, "RIGHT", ICON_GAP, 0)
        else
            frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            frame.text:SetPoint("RIGHT", frame.icon, "LEFT", -ICON_GAP, 0)
        end
    else
        frame.icon:Hide()
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end

    local wide, tall = Reminders.Extent(
        frame.text:GetStringWidth() or 0,
        frame.text:GetStringHeight() or 0,
        hasIcon and side or "none", cfg.iconSize or 0, ICON_GAP)
    frame:SetSize(wide, tall)

    -- NOT WHILE IT IS BORROWED by the options preview, for the same reason
    -- the co-tank panel is not: every slider on the page calls this, and the
    -- preview would jump back to the screen on each one.
    if not self.hosted then
        frame:SetScale(cfg.scale or 1)
        frame:ClearAllPoints()
        frame:SetPoint(cfg.point or "CENTER", UIParent,
            cfg.relPoint or "CENTER", cfg.x or 0, cfg.y or 0)
    end
end

function Reminders:Frame(index)
    return frames[index]
end

function Reminders:SavePosition(index)
    local frame, cfg = frames[index], self:Get(index)
    if not (frame and cfg) or self.hosted then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return end
    cfg.point, cfg.relPoint = point, relPoint
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

-- One frame per configured reminder, and any frame past the end is hidden
-- rather than destroyed: deleting one and adding another is an everyday
-- action on this page, and a frame pool that shrinks is a frame pool that
-- leaves a Lua reference pointing at something the user cannot see.
function Reminders:Rebuild()
    local count = self:Count()
    for index = 1, count do
        if not frames[index] then frames[index] = BuildFrame() end
        self:Style(index)
    end
    for index = count + 1, #frames do
        frames[index]:Hide()
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- The tick
--
-- ONE frame drives every reminder. The condition is re-asked ten times a
-- second; the flash is recomputed every frame, because a fade that steps at
-- 10 Hz is a strobe rather than a pulse.
---------------------------------------------------------------------------
local ticker
local elapsedSinceCheck = 0
local phase = 0

-- The alpha of a flashing reminder at a moment in its cycle. A cosine rather
-- than a sawtooth: a linear ramp snaps back to full at the wrap and reads as
-- a stutter, and a reminder that looks broken is a reminder you distrust.
--
-- Pure and exported, so the shape is checked without a screen.
function Reminders.FlashAlpha(phaseSeconds, rate, floor)
    floor = math.max(0, math.min(1, floor or 0))
    if not rate or rate <= 0 then return 1 end
    local turn = (phaseSeconds or 0) * rate * 2 * math.pi
    -- cos runs 1 -> -1 -> 1, mapped onto floor -> 1 -> floor.
    local wave = (math.cos(turn) + 1) / 2
    return floor + (1 - floor) * wave
end

function Reminders:Refresh()
    for index = 1, self:Count() do
        local cfg, frame = self:Get(index), frames[index]
        if cfg and frame then
            local show = self:ShouldShow(cfg)
            if show and not frame:IsShown() then
                -- Every reminder starts its flash at full brightness rather
                -- than wherever the shared clock happens to be, or a message
                -- that appears mid-fade looks like it was already there and
                -- you missed it.
                frame.flashFrom = phase

                -- AND THE SOUND, ON THE SAME EDGE - the frame's own IsShown
                -- is the "was it up a moment ago" flag, so there is nothing
                -- to remember.
                --
                -- NOT WHILE YOU ARE SETTING IT UP. ShouldShow answers true
                -- for `previewing` and `placing` BEFORE it reaches any of the
                -- real rules, which is right for a picture and wrong for a
                -- noise: dragging a reminder around the screen would chime at
                -- every refresh, and the preview button would chime whether
                -- or not the buff it watches is actually missing.
                if ns.Sounds and not (self.placing or self.previewing) then
                    ns.Sounds.Play("reminder", cfg.spellID)
                end
            end
            frame:SetShown(show)
            if show and not cfg.flash then frame:SetAlpha(1) end
        end
    end
end

function Reminders:Start()
    if ticker then return end
    ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        phase = phase + elapsed

        elapsedSinceCheck = elapsedSinceCheck + elapsed
        if elapsedSinceCheck >= CHECK_INTERVAL then
            elapsedSinceCheck = 0
            Reminders:Refresh()
        end

        for index = 1, Reminders:Count() do
            local cfg, frame = Reminders:Get(index), frames[index]
            if cfg and frame and frame:IsShown() and cfg.flash then
                frame:SetAlpha(Reminders.FlashAlpha(
                    phase - (frame.flashFrom or 0), cfg.flashRate, cfg.flashMin))
            end
        end
    end)

    -- A spec change re-pools every Cooldown Manager frame, so the index a
    -- reminder looks its spell up in is rebuilt under it. Nothing here caches
    -- across that - State asks CDM every time - but the message wants to go
    -- away in the same frame rather than a tenth of a second later.
    if ns.CDM and ns.CDM.OnChanged then
        ns.CDM:OnChanged(function() Reminders:Refresh() end)
    end
end

---------------------------------------------------------------------------
-- The preview
--
-- The options page holds one reminder up on its card. Same rule as the
-- co-tank panel and the bar cards: the REAL frame is borrowed, not a second
-- drawing of it, because two renderers drift and this addon has the scars.
---------------------------------------------------------------------------
function Reminders:Borrow(index, host)
    local frame = frames[index]
    if not frame then return nil end

    self.hosted = index
    self.previewing = self:Get(index)
    frame:SetParent(host)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", host, "CENTER", 0, 0)
    frame:SetScale(1)
    frame:SetAlpha(1)
    frame:Show()
    return frame
end

function Reminders:Release()
    local index = self.hosted
    self.hosted = nil
    self.previewing = nil
    local frame = index and frames[index]
    if not frame then return end
    frame:SetParent(UIParent)
    self:Style(index)
    self:Refresh()
end

---------------------------------------------------------------------------
-- Diagnosis
--
-- /zs reminders. Every reminder, what it watches, and either the state or the
-- reason there isn't one - the same sentence the options page shows, so the
-- two cannot say different things about the same reminder.
---------------------------------------------------------------------------
function Reminders:Dump()
    ns.Print("|cffffd100----------------------------------------|r")
    local count = self:Count()
    if count == 0 then
        ns.Print("No reminders. |cffffd100/zs|r, then Reminders in the list on the left.")
        return
    end

    for index = 1, count do
        local cfg = self:Get(index)
        local state, why = self:State(cfg)
        local mark = self:ShouldShow(cfg) and "|cff40ff40on screen|r"
            or "|cff888888hidden|r"
        ns.Print(string.format("|cffffd100%d.|r %s - %s", index,
            self:Label(cfg, index), mark))
        ns.Print(string.format("      watches %s |cff888888%s|r, %s",
            cfg.spellID and (ns.SpellName(cfg.spellID) or "?") or "|cffff4040nothing|r",
            tostring(cfg.spellID or "-"),
            cfg.trigger == "active" and "while active" or "when not active"))
        ns.Print("      " .. (state and ("state: " .. state)
            or ("|cffff8040cannot tell:|r " .. (why or "?"))))
        local reason = self:Explain(cfg)
        if reason then ns.Print("      |cff888888" .. reason .. "|r") end
    end
end
