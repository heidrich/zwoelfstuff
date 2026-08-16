---------------------------------------------------------------------------
-- THE PLACES WE DRAW OURSELVES.
--
-- WHY THIS FILE EXISTS, and it is one answer to a whole session of "das ging
-- vorher".
--
-- Wave 2 adopts Blizzard's frames. For an ICON that is exactly right: their
-- template is a square picture with a swipe over it, which is what an icon is,
-- so borrowing one means their clock, their swipe and their counters keep
-- working with nothing of ours left to go stale.
--
-- For a BAR it is wrong, and it was wrong in five separate reports:
--
--   "die bar hoehe wird komisch dargestellt, da wird nur der bg hoeher"
--   "stack count wird immer noch nicht bei den buffs angezeigt"
--   "empowered rune weapon hat 2 aufladungen ... da muesste eine 2 irgendwo sein"
--   "spell name kannste bei icons rausnehmen, nur bei bars sichtbar"
--   "DAS GING VORHER. auch bei den Bars, da konnte ich NAME, aufladung und
--    restzeit anzeigen"
--
-- All five fall out of ONE fact: Blizzard's TrackedBar template lays ITSELF
-- out. Its StatusBar keeps the height the template chose, its name and timer
-- sit where the template put them, its counter frames exist or do not by its
-- own rules, and contract rule 4 allows a claimed frame alpha 1 and nothing
-- else. So every control on the bar page was either styling a frame that was
-- not there, or moving a plate behind one that would not move.
--
-- 4.82.0 had neither fault and fixed neither: the bar he SAW there was our own
-- StatusBar on a cell we sized (old Screen.lua:104-222, BuildAuraVisual).
-- Deleting the second renderer deleted the only thing that ever obeyed those
-- settings - "a removal makes its neighbour load-bearing", the fourth time in
-- one session.
--
-- SO A BAR-SHAPED PLACE IS OURS AGAIN AND AN ICON-SHAPED ONE STAYS BORROWED.
-- That is exactly 4.82.0's split, arrived at from the other side, and it is
-- what the owner approved in those words: "von mir aus".
--
---------------------------------------------------------------------------
-- WHAT WE DO NOT TAKE BACK: THE CLOCK.
--
-- A tracked buff's remaining time is a SECRET VALUE on this patch. We may not
-- read it, compare it or divide by it - which is the whole reason the old
-- second renderer could not simply run its own timer either. It mirrored
-- instead, and so does this: Blizzard's StatusBar for the same spell is still
-- on screen (veiled at alpha 0, which stops nothing updating), and its
-- min/max/value go straight into ours. SetValue is a supported sink for a
-- secret; nothing on this path inspects one.
--
-- The same for the number beside it: Blizzard's own timer FontString is copied
-- across as a STRING. The engine formatted it inside the game where the value
-- was readable, and a string handed on untouched is not a computation.
--
-- WHAT IS DELIBERATELY STILL NOT HERE: `fillGrow`, "Fill up". Making a
-- mirrored value grow means subtracting it from its maximum, which is
-- arithmetic on a secret. The engine can do it - SetTimerDuration with
-- Enum.StatusBarTimerDirection.ElapsedTime - but there is no known way to take
-- that back off a StatusBar once given, so a bar whose owner switched the
-- setting off again would be stuck. Named and deferred rather than half-wired
-- a third time; see Fill.Direction's note, which says the same thing about the
-- same setting.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Own = {}
Cooldowns.Own = Own

-- Captured at file scope, which puts this file's TOC position into the
-- program: Look, Text and Fill must all load above it. The desk reads the TOC
-- and fails the build if that is ever disturbed - the alternative is `attempt
-- to index a nil value` on somebody's next login and not one word out here.
local Look = Cooldowns.Look
local Text = Cooldowns.Text
local Fill = Cooldowns.Fill

---------------------------------------------------------------------------
-- Whose place this is
---------------------------------------------------------------------------

-- DO WE DRAW THIS ONE OURSELVES?
--
-- Asked of the ITEM's shape and never of the slot's. Which template Blizzard
-- issued is a fact about the spell's category - a buff-bar spell is bar-shaped
-- wherever it is put - and the slot only decides whether the thing we draw has
-- room for a fill and a name beside its icon.
--
-- That distinction is not academic: a buff-bar spell dropped on an icon-shaped
-- bar used to be Blizzard's whole bar frame squashed into a square. Now it is
-- a square icon, which is what a square place is for.
function Own.Wanted(item)
    if type(item) ~= "table" then return false end
    local cdm = ns.CDM
    if type(cdm) ~= "table" or type(cdm.ItemShape) ~= "function" then
        return false
    end
    return cdm:ItemShape(item) == "bar"
end

---------------------------------------------------------------------------
-- WHERE THE PARTS GO, and this half is PURE.
--
-- Split out and given no frame on purpose. The anchoring of a fill beside an
-- icon has now been got wrong twice - once each way round - and both times the
-- fault was invisible in the options preview, because the preview draws both
-- halves out of ONE rectangle while the screen has two. A rule that can be
-- proved at a desk stops being a rule that gets re-derived from a screenshot.
--
--   slot       { w, h } - Model's answer for this place
--   placement  "left", "right" or "hidden"
--
-- Returns:
--   wide   the slot is bar-shaped, so there is room for a fill and a name
--   icon   nil, or { side = "LEFT"/"RIGHT", size = n }
--   fill   nil, or { left = n, right = n } - insets from the cell's own edges
--   band   what Text.Caption calls iconWidth: nil stands the name down
--
-- NO GAP BETWEEN THE ICON AND THE FILL. 4.82.0 had none and the bar read as
-- one object; the two pixels in the adopted version were there to match a
-- sliver Blizzard's own template leaves, and on a cell we draw there is no
-- template to match.
---------------------------------------------------------------------------
function Own.Parts(slot, placement)
    local w = tonumber(slot and slot.w) or 0
    local h = tonumber(slot and slot.h) or 0
    placement = placement or "left"

    -- SQUARE: the icon IS the place. No fill, no name - there is no band
    -- beside a square to put a word in, which is Text.Caption's own rule and
    -- the reason it takes nil for an answer.
    if w <= h + 0.5 then
        return { wide = false, icon = { side = "LEFT", size = h } }
    end

    -- A HIDDEN ICON IS A BAR ALL THE WAY ACROSS, and it still gets its name:
    -- Layout.LabelBand answers 5 and 5 for an icon width of nought, so the
    -- word sits inside the bar rather than against its edge. `band = 0` rather
    -- than nil is what says "there is a band, it just has no icon in it".
    if placement == "hidden" then
        return { wide = true, fill = { left = 0, right = 0 }, band = 0 }
    end

    local right = placement == "right"
    return {
        wide = true,
        icon = { side = right and "RIGHT" or "LEFT", size = h },
        fill = { left = right and 0 or h, right = right and h or 0 },
        band = h,
    }
end

---------------------------------------------------------------------------
-- The widget
--
-- Built once per cell and kept. A frame cannot be destroyed in this API -
-- Render says the same about its containers - so building one per pass would
-- leak one per pass, and this runs on every pass.
--
-- `cell.own` is a key on OUR OWN frame. Contract rule 3 is about frames
-- BLIZZARD owns; the cell is Render's, and hiding this behind a weak side
-- table would be ceremony that buys nothing.
---------------------------------------------------------------------------

-- Every cell that has ever carried one, so the module switch can take them all
-- down. Weak keys because a cell belongs to a container that outlives nothing
-- in particular - and because a strong list here would be the one table in the
-- folder that pins frames for the session.
local drawn = setmetatable({}, { __mode = "k" })

local function Build(cell)
    local own = cell.own
    if own then return own end

    own = {}

    -- THE PLATE. A texture on the cell rather than a frame: nothing of ours
    -- needs to draw underneath it, and a texture cannot be given a frame level
    -- that fights with the fill's.
    own.bg = cell:CreateTexture(nil, "BACKGROUND")
    own.bg:SetAllPoints(cell)

    -- THE FILL. A real StatusBar rather than a texture we resize by hand: it
    -- takes LibSharedMedia's textures unchanged, it CLIPS its art instead of
    -- squashing it, and the value is one number - which is what lets a secret
    -- pass through it untouched.
    own.fill = CreateFrame("StatusBar", nil, cell)
    own.fill:SetFrameLevel(cell:GetFrameLevel() + 1)
    own.fill:SetMinMaxValues(0, 1)
    own.fill:SetValue(0)

    -- THE ICON, on the cell and above the plate. It is a texture rather than a
    -- child frame for the same reason the plate is, and it never overlaps the
    -- fill - Own.Parts hands them two rectangles that share an edge.
    own.icon = cell:CreateTexture(nil, "ARTWORK")

    -- ITS OWN FRAME, five levels up, exactly as an adopted cell's. A border
    -- texture on the cell would be painted UNDER the cell's own child frames
    -- whatever draw layer it claimed, and the fill is one of them - so the
    -- border would disappear behind the bar as it filled.
    own.chrome = ns.CreateChrome(cell)

    -- THE REMAINING TIME, copied from Blizzard's own string. Ten levels up,
    -- the same layer Text.Caption and Text.Count use, so the four things this
    -- addon writes on a cell cannot end up in three different orders.
    local layer = CreateFrame("Frame", nil, cell)
    layer:SetAllPoints(cell)
    layer:SetFrameLevel(cell:GetFrameLevel() + 10)
    own.timer = layer:CreateFontString(nil, "OVERLAY")
    own.timer:SetWordWrap(false)

    cell.own = own
    drawn[cell] = true
    return own
end

---------------------------------------------------------------------------
-- The clock
---------------------------------------------------------------------------

-- BLIZZARD'S TIMER STRING ON A TRACKED BAR.
--
-- Counted, not named: the FontStrings on one of these StatusBars have no
-- names, and the first is the spell's name while the SECOND is the timer.
-- 4.82.0 found it the same way and cited the same measurement
-- (EllesmereUICdmBuffBars.lua:3407) - this is a fact about Blizzard's
-- template rather than something either addon invented.
local function TimerString(mirror)
    if type(mirror) ~= "table" or type(mirror.GetRegions) ~= "function" then
        return nil
    end

    local seen = 0
    for _, region in ipairs({ mirror:GetRegions() }) do
        if type(region) == "table" and type(region.GetObjectType) == "function"
            and region:GetObjectType() == "FontString" then
            seen = seen + 1
            if seen == 2 then return region end
        end
    end
    return nil
end

-- ONE MIRROR STEP. Everything it touches is passed straight through; nothing
-- here reads a number.
--
-- NOT ONE ALLOCATION PER FRAME, AND THAT IS THE WHOLE REASON THIS IS SHAPED
-- LIKE THIS.
--
-- The first version wrapped both reads and both writes in `pcall(function()
-- ... end)`, which is tidy and builds A CLOSURE EVERY TIME IT RUNS. This runs
-- once per frame per bar-shaped place: four bars at sixty frames is two
-- hundred and forty closures a second, every second the addon is on screen,
-- for the collector to sweep up. Owner, on the game's own memory list: "wenn
-- das addon offen ist sollte das weniger ein problem sein, schlimm waere es
-- nur, wenn im zu zustand so viele ressourcen verbraucht werden" - and he is
-- exactly right about which half matters. A window you opened once is held
-- and then stops growing; garbage made per frame never stops.
--
-- pcall on a METHOD REFERENCE allocates nothing: `pcall(mirror.GetValue,
-- mirror)` passes a function that already exists and arguments on the stack.
--
-- READ BOTH, THEN WRITE BOTH, which keeps the promise the closure version was
-- written for: the two reads and the two writes are one picture, and half of
-- them landing is a bar showing the right length against the wrong scale.
-- Split into four calls it is actually stronger - a failed READ now stops the
-- write instead of leaving one of the two applied.
local function Sync(fill, mirror, timer, text)
    local okRange, low, high = pcall(mirror.GetMinMaxValues, mirror)
    if not okRange then return false end

    local okValue, value = pcall(mirror.GetValue, mirror)
    if not okValue then return false end

    if not pcall(fill.SetMinMaxValues, fill, low, high) then return false end
    if not pcall(fill.SetValue, fill, value) then return false end

    if timer and text then
        -- GetText can hand back a secret string - it was formatted from one
        -- inside the engine. SetText takes it; tostring on it would raise, so
        -- nothing here does anything else with it.
        local got, value = pcall(text.GetText, text)
        if got then pcall(timer.SetText, timer, value or "") end
    end
    return true
end

-- THE EMPTY END, in our own plain numbers.
--
-- Used whenever the buff is down. Mirroring a frame Blizzard has stopped
-- updating shows the last length it had, for ever - a bar that says a buff is
-- half up when it fell off two minutes ago, which is worse than an empty one
-- because it is confidently wrong.
--
-- WRITTEN ONCE PER FALL, NOT ONCE PER FRAME. A buff bar is DOWN for most of an
-- evening, so this is the branch the tick actually spends its life in - and
-- four setters a frame to keep saying nought is the same waste as the closure
-- above, one layer down. `emptied` is on our own widget table.
-- HOW THE PICTURE SAYS "UP" OR "DOWN", in one place because it is asked from
-- TWO.
--
-- It used to be written only on a render pass, and a render pass runs when
-- Blizzard notified us that something changed. The fill does not wait for
-- that - it is mirrored on its own script, sixty times a second - so a bar
-- could be visibly full while its icon still wore the look from whenever the
-- last notification happened to arrive. Owner: "wie du siehst ist Rime
-- aktive, aber das icon leuchtet nicht."
--
-- `active` is the tri-state: true, false, or nil for "cannot be answered".
-- Both lines below fire on exactly `false`, which is deliberate and is the
-- other half of the same report - unknown is never rounded into the dimmer
-- answer. See CDM:ItemIsActive.
local function Wear(own, look, active)
    if not (own and type(look) == "table") then return false end

    own.icon:SetAlpha(Look.Opacity(look, active ~= false))
    own.icon:SetDesaturated(look.inactiveDesaturate and active == false)
    return true
end

local function Empty(own, item)
    if own.emptied then return end
    own.emptied = true

    own.fill:SetMinMaxValues(0, 1)
    own.fill:SetValue(0)
    if own.timer then own.timer:SetText("") end

    -- AND THE SPARK HAS NOTHING LEFT TO LEAD. It rides the fill's texture,
    -- which does not disappear when the bar empties - it collapses onto the
    -- end the bar grows FROM, and sat there as a bright line for as long as
    -- the buff was down. Owner: "wenn die bar leer ist, ist der spark immer
    -- noch zu sehen."
    --
    -- HERE RATHER THAN IN THE TICK, so it costs nothing per frame: this
    -- function already runs once per fall and not once per frame, and the
    -- latch above is what makes that true.
    Fill.Lead(item)
end

---------------------------------------------------------------------------
-- Drawing one place
---------------------------------------------------------------------------

-- ONE BAR-SHAPED PLACE, DRAWN. Returns the band width for Text.Caption -
-- nil when there is no room for a name.
--
--   cell     ours, already sized and placed by Render
--   item     Blizzard's frame for the same spell. NOT claimed, NOT moved and
--            NOT written to: it is read for its clock and for whether the buff
--            is up, and Render's takeover pass veils it like any other frame
--            nobody placed.
--   slot     Model's rectangle for this place
--   style    Text.Style - the four text elements
--   look     Look.Style - the eighteen appearance keys, already resolved
--   factor   what the show rules came to, 0-1
function Own.Draw(cell, item, bar, index, spellID, slot, style, look, factor)
    if type(cell) ~= "table" or type(look) ~= "table" then return nil end

    local own = Build(cell)
    local parts = Own.Parts(slot, bar and bar.iconPlacement)

    -- WHICH OF BLIZZARD'S FRAMES THIS CELL STANDS FOR. On OUR cell, so rule 3
    -- is not in question, and it is what lets a diagnostic ask Fill about this
    -- place without walking every bar to find out which item it holds.
    cell.dkItem = item

    -- 1. THE PLATE AND THE BORDER. A bar frames itself from just OUTSIDE and
    --    an icon from just inside - one decision, taken in ns.PaintBorder,
    --    because two renderers on one bar disagreeing about it is exactly the
    --    kind of difference nobody can name and everybody sees.
    ns.PaintSurface(own.bg, look)
    ns.PaintBorder(own.chrome, look, parts.wide)

    -- 2. THE ICON. Square wherever it sits: a spell icon stretched to the
    --    width of a bar is the one thing a tracking bar must never look like,
    --    and it is what the adopted version did on its first day.
    local zoom = look.iconZoom
    own.icon:ClearAllPoints()
    if parts.icon then
        local side = parts.icon.side
        own.icon:SetPoint("TOP" .. side, cell, "TOP" .. side, 0, 0)
        own.icon:SetPoint("BOTTOM" .. side, cell, "BOTTOM" .. side, 0, 0)
        own.icon:SetWidth(parts.icon.size)
        own.icon:SetTexture(ns.SpellTexture(spellID))
        own.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        own.icon:Show()
    else
        own.icon:Hide()
    end

    -- 3. THE FILL, HUNG FROM ALL FOUR EDGES OF WHAT THE ICON LEAVES.
    --
    --    Four points and no SetSize, and that is the whole of the bug he
    --    reported twice. A height taken once is a height from the pass the
    --    cell happened to be a different size on; hung from the cell's own top
    --    and bottom, "Bar height" reaches the coloured bar because the
    --    coloured bar IS the cell minus the icon.
    if parts.fill then
        own.fill:ClearAllPoints()
        own.fill:SetPoint("TOPLEFT", cell, "TOPLEFT", parts.fill.left, 0)
        own.fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT",
            -parts.fill.right, 0)
        own.fill:Show()

        -- ITS TEXTURE, ITS COLOUR, ITS DIRECTION, ITS SPARK, ITS CHARGE MARKS
        -- AND ITS STACK BANDS - all of it Fill.lua's, unchanged, because
        -- Fill's one finder now answers with OUR StatusBar for this item.
        --
        -- That is the reason this file does not draw a single one of them
        -- itself. Every one already exists, every one is already tested, and a
        -- second copy of them would be the second copy of a list that is
        -- already stale before it is finished.
        Fill.Own(item, own.fill, cell)
        Fill.Apply(item, bar, index, spellID)
    else
        Fill.Own(item, nil)
        own.fill:Hide()
    end

    -- 4. THE CLOCK, MIRRORED. See the file header: the value is Blizzard's,
    --    worked out inside the game where a secret is readable, and it arrives
    --    here as something to pass on rather than to look at.
    -- ItemLooksActive, not ItemIsActive - see its note in CDM.lua. Both of
    -- the two things this function does with the answer (the dimming below
    -- and the greying at the bottom) fire on exactly `false`, so a client
    -- that goes quiet for a frame used to swap the picture rather than leave
    -- it alone. Owner: "manchmal ist das icon ausgegraut manchmal nicht."
    local active = ns.CDM:ItemLooksActive(item)
    local mirror = parts.fill and Fill.Blizzard(item) or nil
    local text = mirror and TimerString(mirror) or nil

    own.fill:SetScript("OnUpdate", nil)
    if parts.fill then
        local timer = style and style.countdown
        local showTimer = timer and timer.show and text ~= nil
        own.timer:SetShown(showTimer and true or false)
        if showTimer then
            ns.Media.ApplyFont(own.timer, timer.font, timer.size,
                timer.outline, timer.color)
            local x, y = Text.Offset(timer)
            own.timer:ClearAllPoints()
            own.timer:SetPoint(timer.anchor, cell, timer.anchor, x, y)
        end

        if mirror then
            -- ON ITS OWN SCRIPT rather than on the render pass. The value
            -- changes sixty times a second and a render pass runs when
            -- something Blizzard notified us about changed - a bar redrawn
            -- only on those would move in steps of several seconds.
            local function Tick(self)
                local up = ns.CDM:ItemIsActive(item)
                -- nil is "the client will not say", and it is never rounded
                -- into the answer that empties the bar.
                -- THE ICON KEEPS UP WITH THE BAR NOW. `up` is already in hand
                -- every frame; Wear is two setters and no allocation, and
                -- without it the picture only changed when Blizzard happened
                -- to notify us - which is how a full bar ended up beside a
                -- dimmed icon of the same spell.
                if up ~= own.worn then
                    own.worn = up
                    Wear(own, own.look, up)
                end

                if up == false then
                    Empty(own, item)
                    return
                end

                -- AND THE LATCH COMES OFF THE MOMENT IT IS UP AGAIN. Empty
                -- writes once per fall and then goes quiet; without this line
                -- it would go quiet for ever, and a bar that emptied once
                -- would never fill again. The cheap half of a rate limit is
                -- setting it - the half that gets forgotten is clearing it.
                --
                own.emptied = nil

                if not Sync(self, mirror, showTimer and own.timer or nil,
                        text) then
                    self:SetScript("OnUpdate", nil)
                    return
                end

                -- EVERY FRAME, NOT ON THE TRANSITION, and the transition
                -- version of this was wrong twice over.
                --
                -- `waking` only fires when ItemIsActive said the buff FELL
                -- OFF, and on a frame with no IsActive it never says so at
                -- all - so a bar that simply drained to nothing kept its
                -- spark for ever. Which is what he photographed: two empty
                -- bars, a bright line on the right of each.
                --
                -- Fill.Lead is one GetWidth and a comparison, and it only
                -- calls a setter when the answer changes. That is affordable
                -- here; being right only when Blizzard notifies us is not.
                Fill.Lead(item)
            end
            Tick(own.fill)
            own.fill:SetScript("OnUpdate", Tick)
        else
            -- NO FRAME OF THEIRS TO MIRROR. Full rather than empty: the place
            -- is on screen because something put it there, and an empty bar
            -- says "about to run out", which is a statement we cannot support.
            own.fill:SetMinMaxValues(0, 1)
            own.fill:SetValue(1)
        end
    else
        own.timer:Hide()
    end

    -- 5. HOW BRIGHT, AND THE TWO OPACITIES ARE NOT THE SAME QUESTION.
    --
    --    Owner, with the Look tab open: "wenn ich hier while inactive die
    --    opacity ändere, ändert sich der bar bg und das icon ... das sollten
    --    wir hier trennen, denn die option heisst ja icon." He is right, and
    --    it is the only part of a place that had no opacity of its own: the
    --    plate has backdropAlpha, the trough has fillBackAlpha, the fill has
    --    fillAlpha, every text element carries its own in its colour. The
    --    icon had the CELL's, which is every one of those at once.
    --
    --    So the two settings under "The icon" are the ICON's now, and the
    --    whole place keeps only what is genuinely about the whole place: the
    --    show rules' factor, which is not a look setting at all and is the
    --    difference between a place being half-way off screen and a picture
    --    being faint.
    --
    --    ON A BORROWED PLACE NOTHING MOVES. There the cell IS the icon -
    --    Look.Apply spends the same number through Claim on Blizzard's frame -
    --    so "the icon's opacity" and "the cell's" were always one answer, and
    --    this only splits them where there are two things to tell apart.
    --    THE TWO LINES THEMSELVES LIVE IN `Wear`, at the top of this file,
    --    because the tick above needs them too: the fill runs on its own
    --    script and the icon was only ever repainted when Blizzard notified
    --    us about something. `own.look` is what lets the tick reach them
    --    without asking the store again on a frame that has not changed.
    own.look = look
    own.worn = active
    Wear(own, look, active)

    -- THE PLACE ITSELF carries the show rules and nothing else. Written every
    -- pass rather than only when it is not 1: a cell comes back out of Render's
    -- pool still wearing whatever the last place on it faded to.
    cell:SetAlpha((factor and factor < 1) and factor or 1)

    return parts.band
end

-- TAKES ONE CELL'S OWN WIDGET OFF SCREEN, and puts the cell's alpha back.
--
-- The alpha is not tidiness: a cell that carried a bar-shaped place and then
-- gets an adopted icon would keep the dimming, and the icon it holds is
-- Blizzard's frame - which does NOT inherit it. So the picture would be a
-- bright icon with a dim name under it and nothing on the page to explain it.
function Own.Hide(cell)
    if type(cell) ~= "table" then return false end
    local own = cell.own
    if not own then return false end

    own.fill:SetScript("OnUpdate", nil)
    own.fill:Hide()
    -- The tick's "what is it wearing" latch goes with it. A cell that comes
    -- back out of the pool for a different spell would otherwise be told it
    -- already wears the right look and skip the first repaint.
    own.worn = nil
    own.icon:SetAlpha(1)
    own.icon:Hide()
    own.bg:Hide()
    own.chrome:Hide()
    own.timer:Hide()
    cell:SetAlpha(1)
    return true
end

-- EVERY CELL WE HAVE DRAWN ON, TAKEN DOWN. What the module switch calls, by
-- way of Render.Stop, and the count it returns is the one that has to fall to
-- nought rather than merely stop climbing.
--
-- Collected into a list first, for the reason Cooldowns.Each documents:
-- walking a table with `next` while something clears entries is undefined.
function Own.ReleaseAll()
    local list = {}
    for cell in pairs(drawn) do list[#list + 1] = cell end

    local count = 0
    for _, cell in ipairs(list) do
        if Own.Hide(cell) then count = count + 1 end
    end
    return count
end

-- How many cells carry one of our widgets. For the self test and for /zs cdm.
function Own.Held()
    local count = 0
    for _ in pairs(drawn) do count = count + 1 end
    return count
end
