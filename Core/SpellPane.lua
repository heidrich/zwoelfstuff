---------------------------------------------------------------------------
-- SpellPane - one list of every spell this character can be shown.
--
-- Search at the top, filter chips under it, then the spells themselves in
-- bands: what the Cooldown Manager tracks, then what the aura engine knows.
-- Click one and the HOST decides what that means.
--
-- It lived inside the cooldown workspace until the bars were taken out, and
-- it was the only part of that file anybody else used: the death log builds
-- its defensives chooser from it and the reminders build theirs. Lifting it
-- out was the alternative to keeping a 2700-line options page alive for one
-- function.
--
-- THE HOST CONTRACT, and it is now required rather than defaulted - there is
-- no bar left to be the obvious target:
--
--   Used()            -> { [spellID] = short label } for the "already used" mark
--   Assign(spellID)   what a click and a drop do
--   Hint(spellID)     one tooltip line about what a click would do, or nil
--   Sync()            pull any selection back into range before filling
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local SpellPane = {}
ns.SpellPane = SpellPane

local function Duration(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return "" end
    if seconds < 60 then return string.format("%ds", seconds) end
    local minutes = math.floor(seconds / 60)
    local rest = seconds - minutes * 60
    if rest == 0 then return string.format("%dm", minutes) end
    return string.format("%dm %d", minutes, rest)
end

local SPELL_ROW_H = 32
local HEADING_H   = 26

-- The order the groups appear in, and what they are called. "other" is the
-- catch-all for anything the client hands back under a category this build
-- does not know - it exists so a renamed enum member costs one heading rather
-- than a spell vanishing from the list.
local GROUPS = {
    { key = "essential", label = "Cooldowns" },
    { key = "utility",   label = "Utility" },
    { key = "buffIcon",  label = "Buffs" },
    { key = "buffBar",   label = "Buff bars" },
    -- Not from the Cooldown Manager: procs this character has been seen to
    -- raise. What is shown is the aura; what drives it is the glow underneath.
    { key = "aura",      label = "Auras" },
    { key = "other",     label = "Other" },
}

-- WHICH HEADING AN ENTRY IS LISTED UNDER, which is not the same question as
-- where it CAME FROM.
--
-- Everything Blizzard's Cooldown Manager knows but is not currently displaying
-- used to be a group of its own, called "Not shown by Blizzard". That was a
-- statement about Blizzard's settings panel dressed up as a category, and it
-- read as though those entries were a different KIND of thing. They are not:
-- they are this spec's spells and cooldowns, the same as the ones above them,
-- and on a default setup they are most of the list.
--
-- So they are listed under Cooldowns with everything else. The distinction is
-- kept where it is actually true and actually useful - on the entry itself,
-- as the tooltip line that says there is no frame to adopt yet and names the
-- one drag that fixes it.
--
-- The ORDER still separates them without a heading: the catalogue bands its
-- sort key by viewer rank, and the hidden band ranks after all four viewers.
-- The spells you arranged in Blizzard's own Cooldown Manager stay at the top
-- of Cooldowns, in your order, and the rest follow underneath.
local DISPLAY_GROUP = {
    [ns.CDM.HIDDEN_KEY] = "essential",
}

-- Which heading one entry is listed under. PURE, and exported, for the reason
-- the harness prints two lines below its own result: it cannot check "the
-- picker groups the viewers" at all, because that check needs a live Cooldown
-- Manager and there is none on a desktop. So the DECISION is lifted out of the
-- fill loop, where it was three lines nothing could reach, and the test asserts
-- it directly.
local GROUP_KEYS = {}
for _, group in ipairs(GROUPS) do GROUP_KEYS[group.key] = true end

function SpellPane.GroupKeyFor(viewerKey)
    local key = viewerKey or "other"

    -- Re-homed first: an entry can come from a source that is not a heading of
    -- its own, and the not-currently-displayed spells are exactly that.
    key = DISPLAY_GROUP[key] or key

    -- Then the catch-all, so a viewer key this build does not know costs one
    -- "Other" row rather than a spell that silently vanishes.
    if not GROUP_KEYS[key] then key = "other" end
    return key
end

---------------------------------------------------------------------------
-- WHO THE LIST IS FILLING IN FOR.
--
-- The list itself is the same list wherever it appears - the Cooldown
-- Manager's spells plus this character's recorded procs, grouped, searched
-- and sorted one way. What differs is only what a click MEANS and which
-- entries are already spoken for. So that is what the caller passes, and
-- everything else stays in one place.
--
-- This exists because the reminders page needs the same list, and the
-- alternative was a second one. Every second copy of a display in this addon
-- has drifted from the first, without exception.
--
--   Used()            -> { [spellID] = short label } for the "already used" mark
--   Assign(spellID)   what a click and a drop do
--   Hint(spellID)     one tooltip line about what a click would do, or nil
--   Sync()            pull any selection back into range before filling

function SpellPane:Build(parent, width, host)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints(parent)

    local filter = "all"

    -- The search sits at the TOP. The line that used to be above it said
    -- "Click a spell to fill cell 5 of Cooldowns" in orange - which is what
    -- the column's own subtitle says, one line higher, and orange is meant to
    -- be rare enough to mean something.
    local search = UI.Input(pane, width, function() end, false, "Search")
    search:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    search:SetHeight(28)
    search:SetIcon("ui-search")

    local chips
    chips = UI.ChipRow(pane, width, {
        chips = {
            { key = "all",       text = "All" },
            { key = "essential", text = "Cooldowns" },
            { key = "utility",   text = "Utility" },
            { key = "buffIcon",  text = "Buffs" },
            { key = "buffBar",   text = "Buff bars" },
            { key = "aura",      text = "Auras" },
            -- No chip for the not-currently-displayed spells: they are listed
            -- under Cooldowns now (see DISPLAY_GROUP), and a chip for them
            -- would filter on a key no entry carries any more - it would come
            -- back empty every time.
        },
        current = function() return filter end,
        onSelect = function(key)
            filter = key
            chips.Refresh()
            pane.Fill()
        end,
    })
    chips:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -10)

    local listHost = CreateFrame("Frame", nil, pane)
    listHost:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -10)
    listHost:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 56)

    local scroll, content = UI.ScrollArea(listHost, width - 8)

    -- The footer: a labelled field and the button that acts on it. The label
    -- is beside the field rather than inside it as a placeholder, because a
    -- placeholder disappears the moment you start typing - which is exactly
    -- when "what am I typing here" is still a live question.
    local function AddManual(text)
        local spellID = tonumber(text)
        if spellID and spellID > 0 then
            host.Assign(spellID)
        else
            ns.Print("Enter a numeric spell ID.")
        end
    end

    local manualLabel = UI.Label(pane, "Spell ID", UI.FS.meta, C.textFaint)
    manualLabel:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 14)

    local manualAdd = UI.Button(pane, "Add", 54, function() end)
    manualAdd:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 12)

    local manual = UI.Input(pane, 92, AddManual, true, "")
    manual:SetPoint("LEFT", manualLabel, "RIGHT", 10, 0)
    manual:SetPoint("RIGHT", manualAdd, "LEFT", -8, 0)
    manual:SetHeight(26)

    manualAdd:SetScript("OnClick", function()
        AddManual(manual.input and manual.input:GetText())
    end)

    local footer = UI.Label(pane, "", UI.FS.eyebrow, C.textGhost)
    footer:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    footer:SetWordWrap(false)

    ---------------------------------------------------------------------
    -- ONE FRAME PER LINE YOU CAN SEE, NOT PER SPELL THERE IS
    --
    -- This pane was the most expensive thing the addon built - 2.7 MB and 796
    -- frames, measured with memcheck.lua - and the reason was not the list, it
    -- was the drawing of it: a UI.SpellRow for every entry in the catalogue,
    -- kept for the session, for a column that shows a dozen at a time.
    --
    -- So the list and its drawing are two things now:
    --
    --   plan     one small table per line - a heading or a spell - with the
    --            place it sits at and how tall it is. It is the WHOLE list,
    --            and it costs a table each.
    --   rows     the frames, and there are only as many as fit the column
    --            plus one. They are re-filled as the window moves.
    --
    -- The scroll area calls Paint through scroll.OnScrolled, which is the one
    -- door for all three moments that move the window: the wheel, the contents
    -- changing under it, and the column being resized.
    --
    -- WHAT THIS COSTS: a row under the cursor becomes a different spell while
    -- you scroll, and nothing re-enters a frame the mouse never left. Paint
    -- re-fires OnEnter for the row it is pointing at, or the tooltip would go
    -- on describing the spell that used to be there.
    ---------------------------------------------------------------------
    local plan, rows, headings = {}, {}, {}
    local rowWidth = width - 8
    local planUsed, planCfg = {}, nil
    local Paint

    -- Everything one row says. It was inline in the loop that built the rows;
    -- it has to be its own function now because a row is filled again every
    -- time the window moves over it, not once when it is made.
    local function FillRow(row, entry)
        local used, cfg = planUsed, planCfg

        row.icon:SetTexture(entry.icon or ns.WHITE)
        row.name:SetText(entry.name)

        -- `cell` is a bar's cell NUMBER, and for any other host it is whatever
        -- short word that host uses for "this one is taken". SetUsed only ever
        -- tests it for truth, and the badge prints it, so both shapes work -
        -- but the label below has to be built from it rather than assuming a
        -- number, which is why it goes through tostring.
        local cell = used[entry.spellID]
        local known = entry.known ~= false
        row:SetUsed(cell, known)

        -- ONE SHORT THING ON THE RIGHT, in this order of importance: is it
        -- already placed, does the build have it, how long does it last.
        -- Everything else - the ID, what drives an aura - is in the tooltip,
        -- which is where you look when you are asking about ONE of them
        -- rather than scanning all of them.
        if cell then
            row:SetTrailing(type(cell) == "number"
                and ("Cell " .. cell) or tostring(cell), "cell")
        elseif not known then
            row:SetTrailing("Not in build")
        elseif entry.duration then
            row:SetTrailing(Duration(entry.duration))
        else
            row:SetTrailing("")
        end

        -- What the game's own tooltip cannot know: where this spell already
        -- sits, what actually drives it, and what a click here would do.
        row.dkSpellID = entry.spellID
        wipe(row.dkLines)

        if not known then
            row.dkLines[#row.dkLines + 1] = {
                text = "Not talented right now. It can still go on a "
                    .. "bar - useful when you are about to switch "
                    .. "into the build that has it.",
                r = 0.62, g = 0.64, b = 0.68,
            }
        end

        -- NOW THE ONLY PLACE THE DISTINCTION IS MADE, and the reason it may
        -- not be dropped along with the heading.
        --
        -- A bar cell adopts Blizzard's frame and a reminder reads it; neither
        -- has anything to work with while the spell sits in Blizzard's Hidden
        -- category. Since these entries are listed under Cooldowns with
        -- everything else, this line is what stops one being placed into a
        -- cell that can never light up without saying so first. It is one drag
        -- in Blizzard's own settings to fix, so the line says where.
        if entry.viewer == ns.CDM.HIDDEN_KEY then
            row.dkLines[#row.dkLines + 1] = {
                text = "Blizzard's Cooldown Manager knows this spell "
                    .. "but is not displaying it, so there is no "
                    .. "frame to adopt or read. Drag it into one of "
                    .. "its viewers in Blizzard's own Cooldown "
                    .. "Manager settings first.",
                r = 1.00, g = 0.478, b = 0.239,
            }
        end

        if entry.parent and entry.spellID ~= entry.parent then
            row.dkLines[#row.dkLines + 1] = {
                text = string.format(
                    "Shown while %s lights up%s. The Cooldown Manager "
                    .. "does not carry this one, so the proc is what "
                    .. "drives it.",
                    ns.SpellName(entry.parent) or entry.parent,
                    entry.duration and (", about " .. entry.duration .. "s") or ""),
                r = 1.00, g = 0.478, b = 0.239,
            }
        end

        -- What a click would do, in the host's own words. The bar names the
        -- cell; the reminders page names the reminder.
        local hint = host.Hint and host.Hint(entry.spellID, cell)
        if hint then
            row.dkLines[#row.dkLines + 1] = {
                text = hint,
                r = cell and 0.404 or 0.62,
                g = cell and 0.788 or 0.64,
                b = cell and 0.443 or 0.68,
            }
        elseif cell and type(cell) == "number" then
            row.dkLines[#row.dkLines + 1] = {
                text = string.format("Already on %s, in cell %d.",
                    cfg and cfg.name or "this bar", cell),
                r = 0.404, g = 0.788, b = 0.443,
            }
        end

    end

    -- THE WINDOW, DRAWN. Everything above decided WHAT the list holds; this
    -- decides which handful of it has frames right now.
    --
    -- One row of slack below the fold: a line that is half in is drawn whole,
    -- so the column ends in a cut-off row like any scrolling list and not in a
    -- hole that fills itself in a moment later.
    Paint = function()
        local offset = scroll:GetVerticalScroll() or 0
        local height = scroll:GetHeight() or 0
        local first, last = UI.VisibleRange(plan, offset, height + SPELL_ROW_H)

        local rowCount, headCount = 0, 0

        for index = first, last do
            local item = plan[index]

            if item.entry then
                rowCount = rowCount + 1
                local row = rows[rowCount]
                if not row then
                    row = UI.SpellRow(content, rowWidth, SPELL_ROW_H)
                    rows[rowCount] = row

                    -- WIRED ONCE, when the frame is made, and it reads the
                    -- spell OFF THE ROW. A closure per row per paint would be
                    -- a fresh table on every wheel click, which is the kind of
                    -- churn this whole change exists to stop - and the row
                    -- already carries dkSpellID for the drag.
                    row:SetScript("OnClick", function(pressed)
                        if pressed.dkSpellID then host.Assign(pressed.dkSpellID) end
                    end)
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -item.y)
                FillRow(row, item.entry)
                row:Show()

                -- THE TOOLTIP THE MOUSE IS ALREADY INSIDE. This row has just
                -- become a different spell and the cursor never left it, so
                -- OnEnter will not fire on its own and the tooltip would go on
                -- describing the spell that used to be here.
                if row:IsMouseOver() then
                    local enter = row:GetScript("OnEnter")
                    if enter then enter(row) end
                end
            else
                headCount = headCount + 1
                local heading = headings[headCount]
                if not heading then
                    heading = UI.ListHeading(content, rowWidth, HEADING_H)
                    headings[headCount] = heading
                end

                heading:SetText(item.label, item.count)
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -item.y)
                heading:Show()
            end
        end

        for index = rowCount + 1, #rows do rows[index]:Hide() end
        for index = headCount + 1, #headings do headings[index]:Hide() end
    end

    -- The three moments that move the window over the list, all through one
    -- door. See UI.ScrollArea.
    scroll.OnScrolled = function() Paint() end

    local function Fill()
        local query = (search.input:GetText() or ""):lower()

        -- Two sources, one list. The Cooldown Manager's entries and the procs
        -- this character has raised carry the same fields, so the row below
        -- does not care which it got.
        local catalogue = {}
        for _, entry in ipairs(ns.CDM:Catalogue()) do catalogue[#catalogue + 1] = entry end
        for _, entry in ipairs(ns.Auras:Catalogue()) do catalogue[#catalogue + 1] = entry end

        -- Which spells are already spoken for by whoever this list is filling
        -- in for. For a bar that is that ONE bar: the same spell may sit on
        -- three others, and marking it here would say something the user did
        -- not ask about.
        local used, cfg = host.Used()
        used = used or {}

        local buckets = {}
        for _, group in ipairs(GROUPS) do buckets[group.key] = {} end

        local matched = 0
        for _, entry in ipairs(catalogue) do
            local hit = query == ""
                or entry.name:lower():find(query, 1, true)
                or tostring(entry.spellID):find(query, 1, true)

            local key = SpellPane.GroupKeyFor(entry.viewer)

            if hit and (filter == "all" or filter == key) then
                matched = matched + 1
                local bucket = buckets[key]
                bucket[#bucket + 1] = entry
            end
        end

        -- WITHIN A GROUP: what you can cast, in BLIZZARD'S OWN ORDER.
        --
        -- Alphabetical was tidy and matched nothing. This panel says "From
        -- your Cooldown Manager" at the top, and the Cooldown Manager has an
        -- order of its own - the one you arranged in Blizzard's Edit Mode and
        -- the one the icons appear in on screen. Sorting by anything else
        -- makes the picker and the thing it picks from two different lists.
        --
        -- What you cannot cast still goes last. It is worth listing - a bar
        -- can be built for the build you are about to switch into - but not
        -- worth scrolling past to reach what you can use.
        --
        -- Names only ever break a tie now, which also quietly stops a German
        -- client sorting its umlauts after Z.
        for _, group in ipairs(GROUPS) do
            table.sort(buckets[group.key], function(a, b)
                local aKnown, bKnown = a.known ~= false, b.known ~= false
                if aKnown ~= bKnown then return aKnown end

                -- math.huge: the catalogue's order is banded per viewer, so
                -- any fixed sentinel would land inside one of the bands.
                local aOrder, bOrder = a.order or math.huge, b.order or math.huge
                if aOrder ~= bOrder then return aOrder < bOrder end

                if a.name == b.name then return a.spellID < b.spellID end
                return a.name < b.name
            end)
        end

        -- THE PLAN, and nothing is drawn while it is written. `y` counts
        -- downwards and stays positive here, which is what UI.VisibleRange
        -- reads; the sign is flipped once, where a frame is anchored.
        wipe(plan)
        planUsed, planCfg = used, cfg

        local y = 0
        for _, group in ipairs(GROUPS) do
            local bucket = buckets[group.key]
            if #bucket > 0 then
                -- Headings only when everything is shown. Filtered to one
                -- group, a heading repeats what the chip above already says.
                if filter == "all" then
                    plan[#plan + 1] = {
                        y = y, h = HEADING_H,
                        label = group.label, count = #bucket,
                    }
                    y = y + HEADING_H
                end

                for _, entry in ipairs(bucket) do
                    plan[#plan + 1] = { y = y, h = SPELL_ROW_H, entry = entry }
                    y = y + SPELL_ROW_H
                end
            end
        end

        content:SetHeight(math.max(1, y))

        -- A SHORTER LIST CAN LEAVE THE WINDOW PAST ITS OWN END, and with one
        -- frame per spell that used to be harmless - the rows were all still
        -- there, above the fold. Now it would paint an empty column: nothing
        -- is in the window, so nothing gets drawn. Typing into the search box
        -- is exactly this case.
        local overshoot = y - (scroll:GetHeight() or 0)
        if overshoot < 0 then overshoot = 0 end
        if (scroll:GetVerticalScroll() or 0) > overshoot then
            scroll:SetVerticalScroll(overshoot)
        end

        Paint()
        if scroll.Update then scroll.Update() end

        -- "cooldowns" was wrong for four of the six groups this list holds -
        -- utility, buffs, buff bars and recorded auras are not cooldowns, and
        -- a count that miscounts what it is counting reads as a bug.
        footer:SetText(string.format("%d of %d", matched, #catalogue))
    end

    -- Typing filters as you type; there is nothing to submit.
    search.input:SetScript("OnTextChanged", function()
        search.UpdateGhost()
        Fill()
    end)

    pane.Fill = Fill

    -- WHAT THE LIST HOLDS vs WHAT IT HAS BUILT, and both are published because
    -- the whole point of this pane is that the two numbers are different. The
    -- check that a hundred spells cost a dozen frames cannot be made from
    -- outside without them, and a saving nothing measures comes back.
    pane.LineCount = function() return #plan end
    pane.RowCount = function() return #rows end

    pane.Refresh = function()
        -- Called for its clamping side effect, not its return: it pulls the
        -- selection back into range after a bar has been deleted, and the
        -- list below is filled from that selection.
        if host.Sync then host.Sync() end
        chips.Refresh()
        Fill()
    end

    return pane
end

---------------------------------------------------------------------------
-- The right column, pane two: everything about one bar
--
-- Reached from the Options button on that bar's card, and it comes back to
-- the spells when you are done. Nothing here changes what a bar contains -
-- only how it looks.
---------------------------------------------------------------------------
