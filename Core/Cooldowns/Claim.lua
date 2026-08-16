---------------------------------------------------------------------------
-- THE ONE FILE THAT WRITES TO A FRAME BLIZZARD OWNS.
--
-- Named as such in the desk guard before a line of it existed, so the
-- exemption is a decision rather than a patch applied the day the guard first
-- went red. Everything above it - Render, the editor, the options page - asks
-- for a frame to be placed or given back and never touches one itself. That
-- is enforced from outside: a `local item = CDM:ItemForSpell(...)` in any
-- other file is a door the guard watches, and `item:SetPoint(...)` there
-- fails the build.
--
-- The five rules are in Contract.lua. This file is what obeying them costs.
--
-- WHAT WE ARE ACTUALLY DOING, in one sentence: Blizzard's Cooldown Manager
-- draws the icons, and we move them. Nothing here parses an aura, computes a
-- duration or paints a swipe - that all happens inside the client, where
-- secret values are readable and ours to borrow rather than to reproduce.
--
---------------------------------------------------------------------------
-- SIX THINGS MEASURED IN HIS CLIENT, not reasoned about here. All six come
-- out of the implementation that ran for months and out of `/zs skin`, and
-- five of them are counter-intuitive enough that a fresh attempt would get
-- them wrong in exactly the same order.
--
-- 1. A POSITION SET ONCE DOES NOT SURVIVE. Blizzard re-anchors its item
--    frames on every layout pass of its own, and there is no event for it.
--    The only answer that needs no polling is to hook the frame's own
--    SetPoint and re-assert from inside it. That is not a symptom of forcing
--    something - it is what adopting somebody else's frame costs, and the
--    plan was wrong to file it as one.
--
-- 2. NEVER SetScale ON THEIR FRAME - COMPENSATE THE SIZE INSTEAD. A frame's
--    width is measured in its own coordinate space, and Blizzard's Edit Mode
--    has a size slider that scales the item frames. At scale 1.2 a frame
--    reports 36 and draws 43. That is why every icon "measured correct" while
--    three of them were visibly the wrong size. Anchoring needs no such
--    correction: a point resolves in screen space.
--
-- 3. NEVER Hide() - ALPHA ONLY, AND ALPHA NEEDS A HOOK TOO. Hiding a
--    Blizzard frame taints it. And a single SetAlpha does not hold either:
--    the out-of-range veil is driven by range, so Blizzard writes the alpha
--    back the moment you walk anywhere.
--
-- 4. THE RELEASE LESSON, and it is the one that matters most. The version
--    before the rebuild recorded NOTHING before stripping a decoration, so
--    letting go left every one of them pinned at zero for the rest of the
--    session - Blizzard's own Cooldown Manager left permanently stripped by
--    an addon that had just said it let go. Every write in this file is
--    paired with a record of what was there before, and the self test proves
--    the round trip rather than trusting it.
--
-- 5. THE MASK BELONGS TO THE TEXTURE, NOT TO THE FRAME. Measured with
--    `/zs skin`: replacing a mask's own texture with a white square does NOT
--    square the corners - the region still reported Blizzard's 130871 after
--    every attempt. The mask has to come OFF the texture it masks. The white
--    square is kept only as a second attempt, because a mask that cannot be
--    removed can sometimes still be flattened.
--
-- 6. DECORATIONS COME BACK FROM THE POOL. Blizzard rebuilds these frames from
--    a pool and re-decorates them, so stripping once is stripping until the
--    next time that frame is handed out. The strip runs on every pass; it is
--    a handful of regions and it is the only thing that stays true.
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Claim = {}
Cooldowns.Claim = Claim

---------------------------------------------------------------------------
-- Holding a frame where we put it
---------------------------------------------------------------------------

-- HOW MUCH BIGGER THIS FRAME DRAWS THAN THE CELL IT SITS ON. Point 2 above.
--
-- Returns 1 for anything unanswerable, which is the size we asked for - a
-- wrong ratio is worse than none, because it is wrong by a factor rather than
-- by nothing.
local function ScaleRatio(frame, anchorFrame)
    if not (anchorFrame and anchorFrame.GetEffectiveScale) then return 1 end

    local mine = frame:GetEffectiveScale()
    local theirs = anchorFrame:GetEffectiveScale()
    if not (mine and theirs) or mine <= 0 then return 1 end

    return theirs / mine
end

-- Puts back everything we asked for, from inside Blizzard's own setters.
--
-- `applying` is not defensive tidiness: our SetPoint re-enters the SetPoint
-- hook, our SetSize re-enters the SetSize hook, and without the flag the
-- first placement recurses until the stack gives out.
local function Reassert(state, frame)
    if state.applying then return end
    state.applying = true

    if state.anchor then
        local a = state.anchor
        frame:ClearAllPoints()
        frame:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
    if state.width then
        local ratio = ScaleRatio(frame, state.anchor and state.anchor[2])
        frame:SetSize(state.width * ratio, state.height * ratio)
    end
    if state.alpha then
        frame:SetAlpha(state.alpha)
    end

    state.applying = false
end

-- The record for this frame, with the self-healing hooks installed once.
--
-- FOUR HOOKS, and the fourth is the one that is easy to leave out. Blizzard's
-- Cooldown Manager has its own size slider in Edit Mode; one drag on it
-- rescales every item frame with no event to say so, and the size we asked
-- for is compensated FOR the scale. We never CALL SetScale on their frame -
-- rule 1 - we only react to theirs.
local function Hold(item)
    local state = Cooldowns.Record(item)
    if not state or state.hooked then return state end
    state.hooked = true

    -- Each hook only re-asserts what it is responsible for. A frame we hold a
    -- record about but have not placed must not be dragged anywhere by its
    -- own layout pass firing our hook.
    hooksecurefunc(item, "SetPoint", function(frame)
        local pin = Cooldowns.Known(frame)
        if pin and pin.anchor then Reassert(pin, frame) end
    end)
    hooksecurefunc(item, "SetSize", function(frame)
        local pin = Cooldowns.Known(frame)
        if pin and pin.width then Reassert(pin, frame) end
    end)
    hooksecurefunc(item, "SetAlpha", function(frame)
        local pin = Cooldowns.Known(frame)
        if pin and pin.alpha then Reassert(pin, frame) end
    end)
    hooksecurefunc(item, "SetScale", function(frame)
        local pin = Cooldowns.Known(frame)
        if pin and pin.width then Reassert(pin, frame) end
    end)

    return state
end

-- PINS AN ITEM FRAME TO A POINT AND A SIZE OF OURS, AND KEEPS IT THERE.
--   anchor = { point, relativeTo, relativePoint, x, y }
function Claim.Place(item, anchor, width, height)
    local state = Hold(item)
    if not state then return end
    state.anchor = anchor
    state.width, state.height = width, height
    Reassert(state, item)
end

---------------------------------------------------------------------------
-- Rule 4, and why it is two functions rather than one number
--
-- "Unclaimed frames get SetAlpha(0), claimed ones SetAlpha(1). Nothing in
-- between and nothing else." The implementation this replaces took an
-- arbitrary alpha, and an arbitrary alpha is how "nothing in between" stops
-- being a rule and becomes a comment. Two functions cannot be handed 0.6.
--
-- WHAT THAT COSTS, stated rather than discovered later: a per-bar opacity
-- setting cannot be delivered this way. The item frames are Blizzard's
-- children - rule 1 forbids reparenting them - so they do not inherit our
-- container's alpha, and there is no third place to put the number. Wave 4
-- owns `alpha` in Store.READERS and this is the constraint it inherits.
-- Relaxing rule 4 is a decision somebody can make there, in the open; what
-- must not happen is a 0.6 arriving here through a parameter nobody reads.
---------------------------------------------------------------------------

-- On screen, because we placed it.
function Claim.Reveal(item)
    local state = Hold(item)
    if not state then return end
    state.alpha = 1
    Reassert(state, item)
end

-- Off screen without hiding it: a cooldown the user did not put on a bar.
--
-- The record is what makes this stick - the hook reads `pin.alpha` and writes
-- it back whenever Blizzard's own range veil moves it.
function Claim.Veil(item)
    local state = Hold(item)
    if not state then return end
    state.alpha = 0
    Reassert(state, item)
end

---------------------------------------------------------------------------
-- The decorations
--
-- Blizzard's item frames are not one design. Each viewer decorates its own -
-- different masks, so different corners; a shared overlay that lightens some
-- and not others; a border here, a shadow there. Adopted unchanged they are
-- five different icons in a row.
--
-- EVERY NAME BELOW WAS READ OFF WORKING CODE ON THIS MACHINE
-- (EllesmereUICooldownManager/EllesmereUICdmHooks.lua, HideBlizzardDecorations)
-- and none of it is guessed. Studied for what it does, never copied: that
-- addon is All Rights Reserved and so is this one.
--
-- ONE LIST, READ BY THE STRIPPER AND BY THE RESTORER. Two copies would drift,
-- and the copy that drifts is the one that quietly stops putting something
-- back - which is failure mode 4 all over again, arrived at by bookkeeping.
---------------------------------------------------------------------------

Claim.DECORATIONS = {
    "Border", "Shadow", "IconShadow", "DebuffBorder", "CooldownFlash",
    "SpellActivationAlert",
}

-- Reachable by file id as well as by atlas, so both are checked.
local OVERLAY_FILE = 6707800
local SQUARE_MASK  = "Interface\\Buttons\\WHITE8X8"

-- WHAT EACH REGION LOOKED LIKE BEFORE WE TOUCHED IT.
--
-- Weak keys, and the record lives here rather than on the region: writing one
-- of our keys onto a Blizzard object is rule 3, and these are Blizzard's
-- objects. A strong table would also hold every region the session ever saw,
-- which is how a pooled frame never gets collected.
local hushed = setmetatable({}, { __mode = "k" })

-- One flag for the whole file rather than one per region. The hook below
-- calls SetAlpha, which re-enters the hook; the flag is what stops that, and
-- it is only ever set around a call we make ourselves.
local hushing = false

-- IS THIS FIELD ACTUALLY AN OBJECT?
--
-- A decoration is absent on plenty of Blizzard's templates - `CooldownFlash`
-- is not on every one of them - and absent is nil, which every line below
-- already survives. What none of them survives is a field that holds
-- something ELSE, and there is one way for that to happen in the client: a
-- decoration name that collides with a widget METHOD. `item.Border` is a
-- texture; `item.Show` would be a function, and reaching for its alpha would
-- take the whole render pass down.
--
-- Every widget is a table in this client - that is what makes this askable at
-- all rather than a guess about userdata.
local function Object(value)
    return type(value) == "table" and value or nil
end

local function Dim(region, alsoHide)
    region = Object(region)
    if not region then return end

    local record = hushed[region]
    if not record then
        record = {
            alpha = (region.GetAlpha and region:GetAlpha()) or 1,
            shown = (region.IsShown and region:IsShown()) or false,
        }
        hushed[region] = record

        -- Point 3: Blizzard writes the alpha back. pcall, because not every
        -- region on every build is hookable and a decoration that will not
        -- stay quiet costs one visible border, not the addon.
        pcall(hooksecurefunc, region, "SetAlpha", function(self)
            local held = hushed[self]
            if hushing or not (held and held.silent) then return end
            hushing = true
            self:SetAlpha(0)
            hushing = false
        end)
    end

    record.silent = true
    hushing = true
    pcall(region.SetAlpha, region, 0)
    if alsoHide then pcall(region.Hide, region) end
    hushing = false
end

-- Gives a decoration back at the alpha it had before we touched it.
--
-- The hook stays, because a hook cannot be removed - but with `silent` off it
-- does nothing at all, so Blizzard drives the region again exactly as before.
local function Undim(region)
    region = Object(region)
    if not region then return end
    local record = hushed[region]
    if not (record and record.silent) then return end

    record.silent = false
    pcall(region.SetAlpha, region, record.alpha)
    if record.shown then pcall(region.Show, region) end
end

-- Which masks were taken off which texture, so they can be put back. Point 5.
local unmasked = setmetatable({}, { __mode = "k" })

local function Unmask(frame, masked)
    frame = Object(frame)
    masked = Object(masked)
    if not frame then return end

    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("MaskTexture") then
            if masked and masked.RemoveMaskTexture then
                local taken = unmasked[masked]
                if not taken then
                    taken = {}
                    unmasked[masked] = taken
                end
                taken[region] = true
                pcall(masked.RemoveMaskTexture, masked, region)
            end
            pcall(region.SetTexture, region, SQUARE_MASK)
        end
    end
end

local function Remask(masked)
    local taken = masked and unmasked[masked]
    if not taken then return end

    for region in pairs(taken) do
        if masked.AddMaskTexture then
            pcall(masked.AddMaskTexture, masked, region)
        end
    end
    unmasked[masked] = nil
end

-- TAKES THE CHROME OFF AN ADOPTED FRAME. Runs on every pass - point 6.
function Claim.Strip(item)
    if not item then return end
    if not Hold(item) then return end

    for _, key in ipairs(Claim.DECORATIONS) do
        Dim(item[key], key == "SpellActivationAlert")
    end

    -- The masks on the item belong to its icon. The ones on the Cooldown
    -- belong to its swipe, which is not reachable from here, so that one gets
    -- the flattening attempt only.
    Unmask(item, item.Icon)
    Unmask(item.Cooldown, nil)

    -- EVERYTHING THE COOLDOWN MANAGER PAINTS ON TOP OF ITS OWN ICONS, matched
    -- by atlas PREFIX rather than by a list of names.
    --
    -- The name list came from a working addon on a DIFFERENT build, and this
    -- client had one it did not mention: UI-CooldownManager-OORshadow, a
    -- half-transparent "out of range" veil sitting at 0.5 on a self-cast
    -- spell that cannot be out of range. That is why some icons looked dimmer
    -- than others for no visible reason.
    for _, region in ipairs({ item:GetRegions() }) do
        if region ~= item.Icon and region.IsObjectType
            and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            local texture = region.GetTexture and region:GetTexture()

            local isChrome = texture == OVERLAY_FILE
                or (atlas ~= nil and (atlas:find("^UI%-HUD%-CoolDownManager")
                    or atlas:find("^UI%-CooldownManager")))

            if isChrome then Dim(region, true) end
        end
    end
end

---------------------------------------------------------------------------
-- BEING TOLD WHEN A FRAME GOES BACK
--
-- Look and Fill hang textures of their own on an adopted frame - a plate
-- under it, a border around it - and those are OURS, so Claim.Unset knows
-- nothing about them. They still have to come off a frame we have just said
-- we let go, or it is failure mode 4 reached from our own side.
--
-- A registered hook rather than a direct call, because this file loads ABOVE
-- every file that needs it and cannot name one at file scope. Three different
-- callers hand frames back - the takeover pass, the module switch and
-- Render.Stop - and none of them should have to remember a list.
---------------------------------------------------------------------------
local givers = {}

function Claim.OnGive(fn)
    if type(fn) == "function" then givers[#givers + 1] = fn end
end

-- EVERY PART OF AN ITEM FRAME THAT ANYTHING MIGHT RESTYLE, in one list.
--
-- Read by the restore walk so that giving a frame back does not depend on
-- which of the later waves happened to touch it. A part named here and never
-- styled costs one nil check; a part styled and NOT named here is a mark left
-- on a frame we said we had let go, which is the whole failure this file is
-- built around.
local function Parts(item)
    local parts = {
        item, item.Icon, item.Cooldown, item.Bar,
        item.ChargeCount, item.Applications, item.Name, item.Duration,
    }
    if type(item.Icon) == "table" then
        parts[#parts + 1] = item.Icon.Applications
        parts[#parts + 1] = item.Icon.ChargeCount
    end

    -- AND THE STRINGS NOBODY CAN NAME.
    --
    -- Blizzard's countdown number is a FontString the Cooldown owns and
    -- publishes under no key at all - Text.lua finds it by walking
    -- GetRegions, and changes its font, its colour and its ANCHOR. None of
    -- that was coming back: the list above names the Cooldown, and putting a
    -- frame back says nothing about the strings inside it. So the rule-4
    -- promise held for everything that has a name and quietly did not for the
    -- one region on the frame that has none.
    --
    -- Unset on something we never touched is a no-op, which is what makes
    -- walking all of them the safe way rather than a wider one.
    for _, owner in ipairs({ item, item.Cooldown }) do
        if type(owner) == "table" and type(owner.GetRegions) == "function" then
            local ok, regions = pcall(function()
                return { owner:GetRegions() }
            end)
            if ok then
                for _, region in ipairs(regions) do
                    if type(region) == "table" and region.IsObjectType
                        and region:IsObjectType("FontString") then
                        parts[#parts + 1] = region
                    end
                end
            end
        end
    end

    return parts
end

---------------------------------------------------------------------------
-- Letting go
--
-- The whole of point 4, in one function. Everything this addon changed about
-- a frame Blizzard owns is put back HERE, and the self test proves it region
-- by region rather than taking the list on trust.
---------------------------------------------------------------------------

function Claim.Give(item)
    local state = item and Cooldowns.Known(item)
    if not state then return false end

    -- The pin first, so nothing below fires a hook that re-asserts it.
    state.anchor = nil
    state.width, state.height = nil, nil
    if state.alpha then
        state.alpha = nil
        pcall(item.SetAlpha, item, 1)
    end

    -- WHATEVER THE LATER WAVES HUNG ON IT THAT IS OURS. Run BEFORE the record
    -- is forgotten, because a hook that wants to know which cell this was has
    -- one line left in which to ask.
    for _, fn in ipairs(givers) do pcall(fn, item) end

    -- EVERYTHING THE LATER WAVES RESTYLED, put back before the decorations.
    -- Order matters only in that it must happen at all: a part styled by a
    -- wave that did not exist when Give was written would otherwise stay
    -- wearing our look on a frame we have just said we let go.
    for _, part in ipairs(Parts(item)) do Claim.Unset(part) end

    for _, key in ipairs(Claim.DECORATIONS) do Undim(item[key]) end

    -- The chrome regions were matched by atlas rather than by name, so they
    -- cannot be named on the way back either. Undim on a region we never
    -- touched is a no-op, which is what makes walking all of them safe.
    for _, region in ipairs({ item:GetRegions() }) do Undim(region) end
    -- A TYPE TEST, NOT A TRUTHINESS ONE, and the reason is written out in
    -- CDM:Counter, which cites THIS FILE for the guard: "a Blizzard FIELD
    -- spelled like a widget METHOD would come back as a function, and every
    -- caller here is about to index it". Claim carried it in Parts() and not
    -- here, so the one place that reaches through `item.Cooldown` was the one
    -- place that could take a function and index it.
    if type(item.Cooldown) == "table" then
        for _, region in ipairs({ item.Cooldown:GetRegions() }) do Undim(region) end
    end

    -- And its rounded corners. The mask came OFF the icon rather than being
    -- redefined, so putting it back is one call and the icon is Blizzard's
    -- own shape again.
    Remask(item.Icon)

    -- The hooks stay - a hook cannot be removed - but with the record gone
    -- they all read `pin` as nil on their first line and do nothing.
    Cooldowns.Forget(item)
    return true
end

---------------------------------------------------------------------------
-- REMEMBER, THEN SET. The door every other file writes through.
--
-- Waves 4 and 5 restyle these frames: the icon gets a crop and a desaturate,
-- a tracking bar gets our fill texture and colour, the counters get our font.
-- All of that writes to something Blizzard owns, and the rule this file
-- exists for says only this file may.
--
-- FOUR MORE WRITERS WOULD HAVE DISSOLVED THE RULE, and the alternative -
-- putting two thousand lines of styling in here - would have rebuilt the
-- 2 710-line page one folder down. So the rule is kept and the mechanism is
-- generalised instead: one function that records what a thing looked like
-- BEFORE the first time it is asked to change it, and one that puts every
-- recorded field back.
--
-- THIS IS THE WAVE 2 LESSON MADE STRUCTURAL. The version before the rebuild
-- had a hand-written restore per decoration, so "everything is given back"
-- was a discipline somebody had to remember at every call site - and the one
-- they forgot cost Blizzard's Cooldown Manager its borders for a session.
-- Here, forgetting is not available: recording IS the setter.
---------------------------------------------------------------------------

-- WHICH GETTER ANSWERS FOR WHICH SETTER. A setter with no entry cannot be
-- recorded, so it cannot be undone, so it is REFUSED rather than applied - a
-- write we could not take back is exactly what this file is here to prevent.
--
-- IsDesaturated for SetDesaturated: the pair is not spelled alike, which is
-- the sort of thing a "strip the Set, prepend a Get" rule gets wrong silently.
local UNDO = {
    SetAlpha              = "GetAlpha",
    SetTexture            = "GetTexture",
    SetAtlas              = "GetAtlas",
    SetVertexColor        = "GetVertexColor",
    SetTexCoord           = "GetTexCoord",
    SetDesaturated        = "IsDesaturated",
    SetStatusBarTexture   = "GetStatusBarTexture",
    SetStatusBarColor     = "GetStatusBarColor",
    SetTextColor          = "GetTextColor",
    -- THE TWO HALVES OF "WHICH WAY THE FILL RUNS", and they are two because
    -- SetReverseFill only ever flips a HORIZONTAL bar - up and down are
    -- unreachable without the orientation. Both have real getters.
    --
    -- SetReverseFill is NOT "fill up". Wiring it to that is a defect this
    -- addon has already shipped once: reverse moves the fill to the other
    -- END, growing as time passes is the clock, and they are not the same
    -- question.
    SetOrientation        = "GetOrientation",
    SetReverseFill        = "GetReverseFill",

    -- THE THREE THAT WERE MISSING, and every one of them was a feature that
    -- did nothing at all. Claim.Set refuses a setter it cannot undo - which
    -- is right - so a setter left off this list is not a warning, it is a
    -- control that quietly never writes:
    --
    --   SetFont                    the size, face and outline of every
    --                              counter on a bar. Four text elements,
    --                              three controls each, all dead.
    --   SetHideCountdownNumbers    "show Blizzard's own countdown".
    --   SetGradient                every gradient on a fill.
    --
    -- Found by a self test that styled a counter and read the size back: 14
    -- before, 14 after. There is now a guard on the desk that reads every
    -- setter handed to Claim.Set and checks it is spelled here or below, so
    -- a fourth cannot happen quietly.
    SetFont                  = "GetFont",
    SetHideCountdownNumbers  = "GetHideCountdownNumbers",
}

-- SETTERS WITH NO READER AT ALL, and they are not an oversight. A Cooldown's
-- swipe colour and draw-edge can be written and cannot be asked for; there is
-- no GetSwipeColor on any build. So the value before us is unknowable, and
-- the honest undo is Blizzard's own default rather than a remembered one.
--
-- A setter may stand in BOTH tables, and one of them does. Claim.Set reads
-- the getter first and falls back to the default when there is no such
-- function on this build - so `SetHideCountdownNumbers` remembers the real
-- value where GetHideCountdownNumbers exists and returns to Blizzard's own
-- "numbers shown" where it does not. That is better than guessing which
-- build has it.
local WHITE = { r = 1, g = 1, b = 1, a = 1 }

local DEFAULTS = {
    SetSwipeColor = { 0, 0, 0, 0.8 },
    SetDrawEdge   = { false },
    SetDrawSwipe  = { true },

    -- A GRADIENT IS CLEARED BY BEING SET FLAT. There is no GetGradient on any
    -- build and no "off" switch either, so the undo is the one thing that
    -- reliably means no tint: white to white, which multiplies by one.
    --
    -- Plain tables rather than CreateColor, for the reason Fill.lua gives at
    -- its own pair: a colour object IS four fields, those four are all
    -- SetGradient reads, and CreateColor does not exist on the desk.
    SetGradient   = { "HORIZONTAL", WHITE, WHITE },

    SetHideCountdownNumbers = { false },
}

-- What we changed on which object, and what it was. Weak keys: Blizzard's
-- objects, pooled, and a strong table here would hold every one the session
-- ever saw. Separate from the frame records because a region is not a frame
-- and outlives none of the same things.
local touched = setmetatable({}, { __mode = "k" })

-- CHANGES SOMETHING BLIZZARD OWNS, AND RECORDS WHAT IT WAS.
--
--   Claim.Set(region, "SetVertexColor", 1, 0.4, 0.4)
--
-- The first call for a given setter on a given object reads the old value and
-- keeps it. Later calls just apply - the record is what it looked like before
-- WE touched it, not before the last time we did.
--
-- Returns true when the write happened. False means the object cannot do it,
-- or that we have no way to undo it, and in both cases nothing was written.
function Claim.Set(object, setter, ...)
    if type(object) ~= "table" or type(setter) ~= "string" then return false end
    if type(object[setter]) ~= "function" then return false end

    local getter = UNDO[setter]
    local fallback = DEFAULTS[setter]
    if not (getter or fallback) then return false end

    local held = touched[object]
    if not held then
        held = {}
        touched[object] = held
    end

    if held[setter] == nil then
        if getter and type(object[getter]) == "function" then
            local read = { pcall(object[getter], object) }
            -- read[1] is the pcall's own answer; everything after it is the
            -- value. Kept as a list because three of these return four
            -- numbers and one returns two.
            if read[1] then
                table.remove(read, 1)
                held[setter] = read
            end
        end
        -- Still nothing readable? Then the DEFAULT is the undo, if there is
        -- one for this setter.
        if held[setter] == nil then held[setter] = fallback end

        -- AND IF THERE IS NO UNDO AT ALL, NOTHING IS WRITTEN.
        --
        -- The comment above UNDO has always said "refused rather than
        -- applied"; the code recorded `false` and applied anyway, which is
        -- the same sentence pointed at nothing. Found by reading, before a
        -- line of wave 4 existed - and it matters most exactly where it is
        -- hardest to notice: the harness stub answers a getter it has not
        -- implemented with nil, so every restyled region on this desk would
        -- have looked recorded, applied and handed back while none of it
        -- happened. Six swallowed setters cost a day once already.
        --
        -- An entry left behind would say "we touched this", so it goes.
        if held[setter] == nil then
            if next(held) == nil then touched[object] = nil end
            return false
        end
    end

    pcall(object[setter], object, ...)
    return true
end

---------------------------------------------------------------------------
-- ANCHORS, WHICH ARE NOT ONE VALUE
--
-- Claim.Set is one getter per setter, and an anchor cannot be spelled that
-- way: reading one is GetNumPoints() followed by GetPoint(i) i times, and
-- putting it back is ClearAllPoints() followed by SetPoint per point. So it
-- gets its own door rather than a fake getter.
--
-- Wave 4 needs it twice on an icon-shaped frame - the icon texture and the
-- cooldown both have to be told to fill their frame, because each viewer's
-- template anchors its own icon its own way and six adopted icons came out
-- at six sizes. Wave 4's counters need it again. The old implementation wrote
-- that pair by hand as MoveCounter/RestoreCounter and it was the only thing
-- of its kind; there are four now, which is what makes it a door.
---------------------------------------------------------------------------

-- The reserved key an anchor list is filed under. A string nothing can be a
-- setter for, so it can share `touched` with everything else and can never
-- collide with one.
local POINTS = "\0points"

local function RememberPoints(object)
    local held = touched[object]
    if not held then
        held = {}
        touched[object] = held
    end
    if held[POINTS] ~= nil then return end

    local list = {}
    local ok, count = pcall(object.GetNumPoints, object)
    if ok and type(count) == "number" then
        for index = 1, count do
            local read = { pcall(object.GetPoint, object, index) }
            if read[1] then
                table.remove(read, 1)
                list[#list + 1] = read
            end
        end
    end
    -- An empty list is a real answer - a region with no points of its own -
    -- and it is recorded as such. Absent would mean "never touched".
    held[POINTS] = list
end

-- Anchors a region of theirs somewhere of ours, remembering where it was.
function Claim.Anchor(object, point, relativeTo, relativePoint, x, y)
    if type(object) ~= "table" or type(object.SetPoint) ~= "function" then
        return false
    end
    RememberPoints(object)
    pcall(object.ClearAllPoints, object)
    pcall(object.SetPoint, object, point, relativeTo, relativePoint, x, y)
    return true
end

-- The whole of a region told to fill its parent, which is the case wave 4
-- actually has: two points rather than one, and SetAllPoints does not take
-- an inset.
function Claim.Fill(object, frame, inset)
    if type(object) ~= "table" or type(object.SetPoint) ~= "function" then
        return false
    end
    inset = tonumber(inset) or 0
    RememberPoints(object)
    pcall(object.ClearAllPoints, object)
    pcall(object.SetPoint, object, "TOPLEFT", frame, "TOPLEFT", inset, -inset)
    pcall(object.SetPoint, object, "BOTTOMRIGHT", frame, "BOTTOMRIGHT",
        -inset, inset)
    return true
end


-- Everything we changed on this object, put back.
--
-- `false` in the record means "there was nothing to read and no default": we
-- changed it, we cannot undo it, and saying so is better than pretending.
-- Nothing in the shipped list is in that state; it exists so that adding a
-- setter without an undo is visible rather than silent.
function Claim.Unset(object)
    local held = object and touched[object]
    if not held then return false end
    touched[object] = nil

    for setter, value in pairs(held) do
        if setter == POINTS then
            -- Where it hung before us. Cleared first, because SetPoint ADDS
            -- a point rather than replacing one, and a region put back
            -- without the clear would wear its old anchors AND ours.
            pcall(object.ClearAllPoints, object)
            for _, at in ipairs(value) do
                pcall(object.SetPoint, object, unpack(at))
            end
        elseif value then
            -- `unpack`, not `table.unpack`: this client runs Lua 5.1, where
            -- the second one does not exist at all. The harness answers to
            -- both, which is exactly how a 5.4-ism gets shipped.
            pcall(object[setter], object, unpack(value))
        end
    end
    return true
end

-- Has anything on this object been changed by us? For the self test, and for
-- the restore walk below.
function Claim.Touched(object)
    return object ~= nil and touched[object] ~= nil
end

-- EVERY FRAME WE HOLD, HANDED BACK. What "switch the module off" means, and
-- what runs before a reload.
function Claim.GiveAll()
    return Cooldowns.Each(Claim.Give)
end

-- How many frames we have actually PLACED, as opposed to hold a record about.
-- The number /zs cdm prints, and the one that must fall to zero after a
-- release rather than merely stop climbing.
function Claim.Placed()
    local count = 0
    Cooldowns.Each(function(frame)
        local state = Cooldowns.Known(frame)
        if state and state.anchor then count = count + 1 end
    end)
    return count
end
