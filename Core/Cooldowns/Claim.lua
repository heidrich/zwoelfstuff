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

    for _, key in ipairs(Claim.DECORATIONS) do Undim(item[key]) end

    -- The chrome regions were matched by atlas rather than by name, so they
    -- cannot be named on the way back either. Undim on a region we never
    -- touched is a no-op, which is what makes walking all of them safe.
    for _, region in ipairs({ item:GetRegions() }) do Undim(region) end
    if item.Cooldown then
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
