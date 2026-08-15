---------------------------------------------------------------------------
-- Effects - the things a cell does that are not just sitting there.
--
-- A flash when a cooldown comes back. A glow while it is ready. A pulse when
-- you have been standing on a ready defensive for six seconds in combat. This
-- is the half of a cooldown display that people actually read out of the
-- corner of their eye, and it is why "just show the icons" is never enough.
--
-- PORTED FROM 4.82.0's Core/Effects.lua, WHICH IS EVIDENCE RATHER THAN A
-- DRAFT. It ran in his client for months and it paid for every comment in it;
-- the ones that record a measurement are carried over word for word, because
-- a sentence like "isActive is nil on this client, and that is absence rather
-- than secrecy" cannot be re-derived at a desk.
--
-- WHAT CHANGED, AND IT IS ONE THING.
--
-- The old file drove OUR cell frames: it knew a "drawn" cell it had painted
-- itself and an "adopted" one it had borrowed, and it asked a different
-- question of each. There are no drawn cells left. Every cell is one of
-- Blizzard's item frames pinned to a slot of ours, so the split by WHO DREW
-- IT is gone and the split that replaces it is by WHAT THE ITEM IS ABOUT -
-- ns.CDM:ItemTracks, "cooldown" or "buff". That is not a tidy-up: with no
-- drawn cells left, a buff item would otherwise fall into the cooldown branch
-- and every proc would light while it was DOWN, which is the exact fault the
-- old file's own comment records from the other direction.
--
-- WHAT WE WRITE, AND IT IS ALSO ONE THING. `Claim.Set(item.Icon,
-- "SetVertexColor", ...)` for the greying, and nothing else on anything
-- Blizzard owns. The flash, both edge rings, the running squares and the
-- pandemic marker are OUR textures on OUR cell frame, so they are created,
-- coloured and hidden freely. Taking a cell off screen needs no alpha of its
-- own either: rule 4's two answers are exactly "on screen" and "off", so the
-- state rule is expressed as Claim.Veil over Claim.Reveal and Render makes
-- that choice from the map Effects.Pass hands back.
--
-- SECRET VALUES. Since 12.0 the fields this reads can arrive as secret, and a
-- boolean test on one raises. Everything below goes through ns.CanCompute
-- first, and an unreadable state means "behave as if the feature were
-- switched off" rather than "guess" - a display that flashes at random is
-- worse than one that does not flash at all.
--
-- REMAINING TIME. Deliberately not read. There is no field on the info table
-- for it and the Cooldown widget's own timing is a duration object on this
-- patch, so with every cell adopted there is no source at all: `lowWarn` and
-- `lowColor` stay in EFFECT_DEFAULTS because the profile promise says nothing
-- is rewritten, and they are declared UNANSWERED in Effects.ANSWERED so the
-- options page cannot offer a row that could never fire. Sounds.lua paid for
-- the opposite once - "a moment nobody raises is a row in the options that
-- can never make a sound".
---------------------------------------------------------------------------
local _, ns = ...

local Cooldowns = ns.Cooldowns
local Effects = {}
Cooldowns.Effects = Effects

-- Captured at file scope, so this file sits BELOW Claim.lua and Store.lua in
-- the TOC and ABOVE Render.lua. Render is deliberately not captured at all -
-- a file may not reach up the TOC, which is why the repaint is a callback
-- Render registers rather than a call made from here.
local Claim = Cooldowns.Claim
local Store = Cooldowns.Store

local GetTime, sin = GetTime, math.sin

---------------------------------------------------------------------------
-- Every key 4.82.0 stored, unchanged and complete
--
-- COMPLETE MATTERS MORE THAN IT LOOKS. Two of his four bars carry only 18 of
-- these 23 keys - glowStyle, glowDots, readyGlowUsableOnly, hideWhen and
-- reflow are simply absent from them - so for half his profile this table IS
-- the answer, not a description of one. That is also why nothing is ever
-- written back into a bar from here: Store's promise is that nothing is
-- rewritten, and a seeded default is a value somebody can no longer clear.
---------------------------------------------------------------------------
ns.EFFECT_DEFAULTS = {
    -- The flash when a cooldown finishes. The single most asked-for thing in
    -- any cooldown addon, and the reason people keep a second one installed.
    readyFlash   = false,
    readyPulses  = 2,
    readyColor   = { 1.00, 0.85, 0.40 },

    -- A steady edge while the spell is up. Combat-only by default: a screen
    -- of glowing icons while you stand in the city is noise.
    readyGlow    = false,
    readyGlowCombatOnly = true,

    -- WHAT THE GLOW LOOKS LIKE.
    --
    --   "edge"   two rings at different alphas - a soft rectangle
    --   "pixel"  a handful of squares running round the outline
    --
    -- The edge is the quiet one and stays the default. The running squares
    -- are the shape people know from every other addon that has ever marked
    -- "press this", and motion is caught by the corner of your eye in a way a
    -- steady colour is not - which is the entire job of a proc marker.
    glowStyle    = "edge",
    glowDots     = 8,

    -- READY AND AFFORDABLE ARE TWO DIFFERENT THINGS, and only one of them is
    -- what "can I press this" means. A cooldown that has finished while you
    -- are short of the rage, the runic power or the runes is an icon telling
    -- you to press something that will not go off. Off by default, because
    -- the plain reading - "the cooldown is back" - is the one people expect
    -- from a cooldown display and the surprising one should be asked for.
    readyGlowUsableOnly = false,
    glowColor    = { 1.00, 0.72, 0.25 },
    glowSize     = 2,

    -- The nag. A spell that has been ready for this long IN COMBAT starts
    -- pulsing. 0 switches it off.
    reminderAfter = 0,
    reminderColor = { 1.00, 0.35, 0.30 },

    -- While the buff this cell tracks is up.
    activeGlow   = false,
    activeColor  = { 0.45, 0.90, 1.00 },

    -- The refresh window: the tail of an aura where recasting wastes nothing.
    -- NOT calculated here - Blizzard works it out and this addon hooks the
    -- answer, see CDM:InPandemic. It therefore only lights for auras the user
    -- has pandemic alerts switched on for in Blizzard's own settings.
    pandemicGlow  = false,
    pandemicColor = { 1.00, 0.45, 0.15 },

    -- Below this many seconds left, the cell pulses. NO SOURCE while every
    -- cell is an adopted frame - see the header, and Effects.ANSWERED, which
    -- is where that is said in a form a guard can read.
    lowWarn      = 0,
    lowColor     = { 1.00, 0.35, 0.30 },

    -- Classic and quiet: the art greys out while the cooldown runs.
    dimOnCooldown = false,
    dimAmount     = 0.55,

    -- TAKE IT OFF THE SCREEN ENTIRELY, by state.
    --
    --   "never"    always there                          (the default)
    --   "cooling"  gone while it is ONLY recharging - it earns its square by
    --              being usable, or by working (its own buff still running)
    --
    -- There were three values for a while. The inverse - hide what is ready
    -- or working - reads like the useful opposite and is not: it is almost
    -- everything almost always, so picking it emptied the bar. Taken out
    -- rather than left in and explained, and a profile still carrying it
    -- lands on hiding nothing - see Effects.HiddenByState.
    hideWhen = "never",

    -- AND WHETHER THE OTHERS CLOSE UP BEHIND IT.
    --
    --   "off"   the place stays empty. Nothing moves, ever, and "the third
    --           one is my stun" keeps being true.
    --   "all"   everything repacks from the front. What is left IS the list.
    --   "line"  each row closes up within itself and the rows stay put -
    --           right for a grid, where repacking would pull a defensive out
    --           of the second row up into the first.
    --
    -- Off by default, because a display whose icons move has to be re-read
    -- every time and muscle memory is worth more than the empty square costs.
    -- The arithmetic is ns.Layout.Compact, reached through Model.Places, and
    -- it is kept apart from the drawing: an off-by-one there does not raise,
    -- it puts the wrong icon in the wrong square and looks like a working
    -- display.
    reflow = "off",

    -- How fast anything that pulses, pulses. One control for all of them, so
    -- a display does not end up with three different heartbeats.
    pulseSpeed   = 1.0,
}

---------------------------------------------------------------------------
-- WHICH OF THOSE KEYS THIS WAVE ACTUALLY READS
--
-- Store.READERS' idea one level down. Up there a whole wave claims a key;
-- here the key itself says whether anything answers it, and the two that do
-- not are named rather than left to be discovered by somebody switching a
-- setting on and watching nothing happen.
--
-- The options page builds its rows from this, and a desk guard reads it, so
-- "lowWarn has no source" is a fact the build can check rather than a comment
-- somebody has to find. When wave 5 draws bars of its own with a clock we
-- own, it flips two entries here and the rows appear.
---------------------------------------------------------------------------
Effects.ANSWERED = {
    readyFlash          = true,
    readyPulses         = true,
    readyColor          = true,
    readyGlow           = true,
    readyGlowCombatOnly = true,
    readyGlowUsableOnly = true,
    glowStyle           = true,
    glowDots            = true,
    glowColor           = true,
    glowSize            = true,
    reminderAfter       = true,
    reminderColor       = true,
    activeGlow          = true,
    activeColor         = true,
    pandemicGlow        = true,
    pandemicColor       = true,
    dimOnCooldown       = true,
    dimAmount           = true,
    hideWhen            = true,
    reflow              = true,
    pulseSpeed          = true,
    -- lowWarn and lowColor are absent, and their absence is the statement.
}

-- ONE VALUE, WITH ONE FALLBACK PATH. PURE.
--
-- 4.82.0 wrote `fxOpts.readyPulses or 2`, `glowDots or 8` and `dimAmount or
-- 0.55` at the call sites, beside a table that already said 2, 8 and 0.55.
-- Two copies of a default is one copy that drifts, and on half his bars the
-- call-site copy was the one actually answering.
--
-- NOT `fxOpts[key] or default`, and that is the whole reason this is four
-- lines rather than one: `x and y or z` cannot carry false. readyGlowCombatOnly
-- defaults to TRUE, so a stored `false` - somebody who wants the glow outside
-- combat - would collapse and come back as true, and no amount of clicking
-- would change it.
function Effects.Option(fxOpts, key)
    if type(fxOpts) == "table" then
        local value = fxOpts[key]
        if value ~= nil then return value end
    end
    return ns.EFFECT_DEFAULTS[key]
end

-- A colour as three numbers, never as a table somebody could mutate. A stored
-- colour that is not a table at all - an older shape, a hand-edited profile -
-- falls back to the default rather than raising three lines later inside the
-- paint.
local function Colour(fxOpts, key)
    local stored = Effects.Option(fxOpts, key)
    if type(stored) ~= "table" then stored = ns.EFFECT_DEFAULTS[key] end
    -- White for a key that names no colour at all. The alternative is three
    -- nils reaching SetColorTexture, which paints nothing and reads on screen
    -- as "the glow is broken" rather than as "that key is not a colour".
    if type(stored) ~= "table" then return 1, 1, 1 end
    return stored[1] or 1, stored[2] or 1, stored[3] or 1
end

---------------------------------------------------------------------------
-- What this item is about, and whether it is inside its refresh window
--
-- BOTH OF THESE BELONG IN CDM.lua AND BOTH ARE ASKED FOR HERE FIRST.
-- CDM:ItemTracks, CDM:HookPandemic, CDM:InPandemic and CDM:PandemicSupported
-- went out with the takeover half in 4.83.0 and are being put back verbatim
-- from cdm-full-4.82.0:Core/CDM.lua:357-397 and :1259-1273 in this same
-- commit. Until they are, this file must still load and must still be honest,
-- so each is asked for by name and answered without it if it is not there.
--
-- The tracks fallback is two lines of somebody else's file and it is a second
-- copy of one fact, which is a thing this codebase otherwise refuses. It is
-- here because the alternative is worse in a way that is invisible: with no
-- answer at all every buff item falls into the cooldown branch, the ready
-- glow lights every proc that is DOWN, and the flash fires when one runs out
-- rather than when it lands. That is a fault you photograph, not one you
-- notice. The real answer wins the moment it exists.
---------------------------------------------------------------------------
local function Tracks(item)
    local ask = ns.CDM.ItemTracks
    if type(ask) == "function" then return ask(ns.CDM, item) end

    local viewer = ns.CDM:ItemViewer(item)
    local key = viewer and viewer.key
    if key == "buffIcon" or key == "buffBar" then return "buff" end
    return "cooldown"
end

-- The pandemic window is ASKED, never calculated. Dividing the time left by
-- the full duration is exactly the arithmetic this patch forbids - both
-- numbers can be secret - and Blizzard already works it out inside the game
-- where they are readable. Nothing here computes anything.
--
-- No answer means no marker, which is the shape of every unreadable value in
-- this addon: the feature stands down rather than guessing.
local function InPandemic(item)
    local ask = ns.CDM.InPandemic
    if type(ask) ~= "function" then return false end
    return ask(ns.CDM, item) == true
end

---------------------------------------------------------------------------
-- Reading the state
---------------------------------------------------------------------------

-- The spell's own cooldown, as the client reports it for the PLAYER.
--
--   nil    no answer, or a value we may not compute with
--   false  ready, or only the global cooldown is spinning
--   true   its own cooldown is running
local function SpellOnCooldown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldown) then return nil end

    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not (ok and type(info) == "table") then return nil end

    local start, duration = info.startTime, info.duration
    if not (ns.CanCompute(start) and ns.CanCompute(duration)) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end

    if start <= 0 or duration <= 0 then return false end

    -- THE GLOBAL COOLDOWN IS NOT A COOLDOWN. Every spell in the game reports
    -- one for a second and a half after every cast, and counting it would
    -- make the whole bar blink on each button press - the exact reason the
    -- old route subtracted isOnGCD.
    --
    -- A threshold rather than the GCD spell's own id: that id would be a
    -- number written from memory, which is how this project has already lost
    -- a day twice. Haste only ever makes the GCD shorter, so the ceiling
    -- holds. The cost is that a real cooldown of under 1.5s would read as
    -- ready, and no cooldown worth putting on a bar is that short.
    if duration <= 1.5 then return false end
    return true
end

-- Is this spell on a REAL cooldown right now? true, false, or nil for
-- "cannot tell".
local function OnCooldown(spellID, cooldownID)
    local info = cooldownID and ns.CDM:GetInfo(cooldownID)
    local active = info and info.isActive

    if ns.CanCompute(active) then
        if active ~= true then return false end

        -- Active AND on the GCD is the global cooldown spinning, not the
        -- spell's own. Unreadable GCD flag: treat the cooldown as real, which
        -- at worst delays a flash by a GCD and never invents one.
        local gcd = info.isOnGCD
        if ns.CanCompute(gcd) and gcd == true then return false end
        return true
    end

    -- THE INFO TABLE DOES NOT CARRY THESE FLAGS ON THIS CLIENT, and that is
    -- not secrecy - it is absence. Measured in game with /zs hide, on four
    -- cooldowns that were visibly running: isActive nil, isOnGCD nil.
    --
    -- Everything driven by "is it on cooldown" had therefore been standing
    -- down on every adopted Cooldown Manager icon: the ready flash, the ready
    -- edge, the reminder and the greying, not only the hiding this was found
    -- by. It looked exactly like a feature switched off, which is the shape
    -- this whole addon uses for a value it may not read - so nothing ever
    -- complained. In this wave EVERY cell is adopted, so the fallback below
    -- is not a safety net, it is the road.
    --
    -- NOT item:IsActive. The same dump showed it true on all four cooldowns
    -- and false on three auras that were down, which reads like the answer
    -- and is not: it stayed true once they were ready again, so it means
    -- "this item is being tracked", not "it is running". One correlation, two
    -- meanings, and picking the wrong one hid the whole bar for ever.
    --
    -- The spell's own cooldown is the source, and it is the one a shipping
    -- 12.1 addon leans on hardest - C_Spell.GetSpellCooldown appears 59 times
    -- in EllesmereUI's Cooldown Manager alone.
    return SpellOnCooldown(spellID)
end

-- Is one of the player's own auras carrying this exact spell id running?
--
--   nil    the client will not say - inside a dungeon it often will not
--   false  no such aura
--   true   it is up
local function OwnBuffUp(spellID)
    if not (spellID and ns.AurasReadable()) then return nil end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return nil end

    local ok, aura = pcall(get, spellID)
    if not ok then return nil end
    -- Comparing the TABLE against nil, never a field of it: whether an aura
    -- exists is answerable, what is inside it may not be.
    return aura ~= nil
end

-- IS THIS WORTH A SQUARE ON THE SCREEN RIGHT NOW.
--
--   an ability   it is READY, or it is WORKING - the buff it just put on you
--                is still running. Not while it is merely recharging.
--   a buff       it is up.
--
-- THE OWNER SAID THIS THREE TIMES AND I GOT IT WRONG TWICE, so it is written
-- out in his own shape: "icon ist sichtbar wenn nicht auf cd; wenn druecken,
-- muss das icon solange sichtbar sein, bis der buff wie blood shield auch
-- noch rennt; erst dann ausblenden."
--
--   ready ................ visible   you can press it
--   pressed, buff running  visible   it is doing the thing you pressed it for
--   recharging, buff gone  HIDDEN    a picture of something you cannot use
--
-- My first version hid it the moment it was pressed, because it read "on
-- cooldown" as "not usable". My second kept it up for the whole cooldown. The
-- rule is neither: the icon earns its square by being USABLE or by WORKING.
--
-- A bar holds both kinds, so this is the only place the two can be reconciled
-- - leaving it to whoever reads the menu means a setting that is right for
-- half a bar.
--
-- nil means the client would not say, and nil never hides anything.
--
-- `item` FIRST, and every function in this file that touches one is written
-- that way: that parameter name is the desk guard's door, so every line below
-- it is inside the frame contract whether anybody remembers it or not.
function Effects.Relevant(item, spellID, cooldownID)
    if Tracks(item) == "buff" then
        -- The frame's own answer, and for an aura it means exactly what it
        -- says. Proven in game: false on three auras that were down, true on
        -- the ones that were up. An aura often has no cooldown at all, so
        -- asking the spell's cooldown about one answers "ready" for ever.
        local up = ns.CDM:ItemIsActive(item)
        if up == nil then return nil end
        return up and true or false
    end

    local onCd = OnCooldown(spellID, cooldownID)
    if onCd == nil then return nil end

    -- Ready: nothing else to ask.
    if not onCd then return true end

    -- On cooldown, so the only thing that still earns it a square is its own
    -- buff. Most defensives grant one carrying the ABILITY'S own spell id,
    -- which is why a single lookup covers them; Blood Shield is the one he
    -- named. When the client will not answer - inside restricted content it
    -- often will not - this falls through to hiding, because "goes a few
    -- seconds early in a dungeon" is a smaller fault than "never goes".
    if OwnBuffUp(spellID) == true then return true end
    return false
end

-- Can it actually be cast right now - not "is the cooldown back", but "will
-- pressing it do something". nil when the client will not say.
--
-- IsSpellUsable answers two things at once and the second is the one that
-- matters here: usable, and whether the reason it is not is resources. A
-- spell out of range or without a target reports unusable too, and that is
-- NOT what this is for - a defensive is unusable by that reading whenever
-- nothing is targeted, and greying it out would be wrong every pull.
function Effects.Affordable(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return nil end
    local ok, usable, noResource = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return nil end
    if not ns.CanCompute(usable) or not ns.CanCompute(noResource) then
        return nil
    end
    -- Unusable for any OTHER reason is left alone: only the resource answer
    -- belongs to this feature.
    if noResource == true then return false end
    return true
end

---------------------------------------------------------------------------
-- The rules, all pure
--
-- Everything below this line is arithmetic and words. The desk has no screen
-- and deliberately does not dispatch OnUpdate, so this is the half of the
-- feature that can be PROVED out there rather than looked at in his client.
---------------------------------------------------------------------------

-- PURE. Whether this cell is currently taken off screen by its state rule.
--
-- `relevant` is three-valued and nil is the important one: a cooldown the
-- client will not talk about must never disappear. An icon that vanishes
-- because the addon could not read something is indistinguishable from a bug,
-- and it takes the spell with it.
function Effects.HiddenByState(fxOpts, relevant)
    if relevant == nil then return false end
    -- ONE RULE, and the inverse was deliberately taken out rather than left
    -- unlisted. "Hide what is ready or working" is almost everything almost
    -- always, so it emptied the bar; the owner hit it twice and read it as a
    -- fault, which it was. A profile that still carries the old value falls
    -- through to hiding nothing, which gives the bar back instead of leaving
    -- somebody with an empty one.
    if Effects.Option(fxOpts, "hideWhen") == "cooling" then
        return relevant == false
    end
    return false
end

-- PURE. Whether the ready glow may light this instant.
--
--   ready       the cooldown is back
--   affordable  true / false / nil for "the client will not say"
--
-- Unknown lights it. Every unreadable value in this addon falls back to the
-- behaviour of the feature switched off, because an effect that disappears
-- when something could not be read is indistinguishable from a broken one.
function Effects.GlowAllowed(fxOpts, ready, affordable)
    if not ready then return false end
    if not Effects.Option(fxOpts, "readyGlow") then return false end
    if Effects.Option(fxOpts, "readyGlowUsableOnly") and affordable == false then
        return false
    end
    return true
end

-- PURE. Whether this bar wants the ticker at all. A bar with everything off
-- is never registered, so the ticker walks nothing and then disarms itself.
--
-- `sound` is the caller's answer to ns.Sounds.HasAny("ready") and it is new.
-- 4.82.0 asked only about the visuals, so somebody who chose a sound and left
-- every visual off was watched by nothing and heard nothing - the setting was
-- there, the noise never came, and there was no way to tell that from a
-- broken sound file.
function Effects.Wanted(fxOpts, sound)
    if sound then return true end
    if Effects.Option(fxOpts, "readyFlash") then return true end
    if Effects.Option(fxOpts, "readyGlow") then return true end
    if Effects.Option(fxOpts, "activeGlow") then return true end
    if Effects.Option(fxOpts, "pandemicGlow") then return true end
    if Effects.Option(fxOpts, "dimOnCooldown") then return true end
    if (tonumber(Effects.Option(fxOpts, "reminderAfter")) or 0) > 0 then
        return true
    end
    -- A bar that only hides things still needs the ticker: it is the only
    -- thing watching for the state to flip back.
    return Effects.Option(fxOpts, "hideWhen") ~= "never"
end

---------------------------------------------------------------------------
-- WALKING THE OUTLINE OF A RECTANGLE
--
-- PURE, and the reason the running glow can be checked at all out here: the
-- harness has no screen, but "where is dot 3 of 8 at this instant" is
-- arithmetic.
--
-- progress 0..1 walks CLOCKWISE from the top-left corner and wraps, so a
-- caller can hand in 0.9 + 0.3 without thinking about it. Returns x, y
-- measured from the BOTTOM-LEFT, which is the corner WoW's SetPoint
-- arithmetic is happiest with.
---------------------------------------------------------------------------
function Effects.PerimeterPoint(progress, width, height)
    width, height = math.max(0, width or 0), math.max(0, height or 0)
    local perimeter = 2 * (width + height)
    if perimeter <= 0 then return 0, 0 end

    -- Wrap first: a dot at 1.25 is a dot at 0.25, and a negative one runs
    -- backwards rather than off the end.
    progress = (progress or 0) % 1
    if progress < 0 then progress = progress + 1 end

    local along = progress * perimeter

    if along <= width then                       -- the top, left to right
        return along, height
    end
    along = along - width
    if along <= height then                      -- the right, downwards
        return width, height - along
    end
    along = along - height
    if along <= width then                       -- the bottom, right to left
        return width - along, 0
    end
    along = along - width
    return 0, along                              -- the left, upwards
end

-- PURE, 0..1, smooth, WITH ITS CLOCK HANDED IN - Sounds.MayPlay's shape, and
-- for the same reason: the alternative is a test that waits.
--
-- `phase` keeps two different pulses on one cell from lining up into a single
-- brighter one.
function Effects.Pulse(now, speed, phase)
    return 0.5 + 0.5 * sin((now or 0) * 3.2 * (speed or 1) + (phase or 0))
end

-- ONE PULSE OF THE FLASH, AND HOW BRIGHT IT GETS. Two numbers rather than two
-- literals scattered through the tick: "two pulses" has to mean twice this,
-- both where the countdown is started and where it is drawn.
local FLASH_STEP = 0.35
local FLASH_PEAK = 0.55

-- PURE. The repeating sawtooth that makes "two pulses" two visible flashes
-- instead of one long fade that happens to last twice as long.
function Effects.FlashAlpha(left)
    if not left or left <= 0 then return 0 end
    return ((left % FLASH_STEP) / FLASH_STEP) * FLASH_PEAK
end

---------------------------------------------------------------------------
-- The overlay
--
-- One frame per cell, above whatever the cell shows. All of it ours: the cell
-- is our frame, so its rectangle already matches the icon's - Claim anchored
-- the item at an offset of zero and compensated its size by ScaleRatio.
--
-- HALF OF WHAT IT HAS TO COVER IS NOT OURS. An adopted Cooldown Manager frame
-- is Blizzard's child, so its draw order has nothing to do with our frame
-- level. Strata and level are READ off the frame we have to beat and written
-- to ours, every pass, because pooled frames come back with whatever level
-- they had last: reading a Blizzard frame is harmless, writing to one is not.
--
-- Blizzard's own CooldownFlash and SpellActivationAlert are already dark -
-- Claim.DECORATIONS strips both - so ours is the only flash on screen.
---------------------------------------------------------------------------
function Effects.Attach(cell)
    if cell.fx then return cell.fx end

    local fx = CreateFrame("Frame", nil, cell)
    fx:SetAllPoints(cell)
    fx:Hide()

    -- The edge. Drawn on a frame of its own rather than as a texture on the
    -- cell, for the same reason the border is: a texture is painted under the
    -- cell's own child frames whatever layer it claims.
    fx.glow = ns.CreateBorder(fx, 2, "OVERLAY")
    fx.glow:Hide()

    -- A second, wider edge just outside the first. Two rings at different
    -- alphas read as a soft glow; one hard rectangle reads as a selection box.
    fx.halo = CreateFrame("Frame", nil, fx)
    fx.halo:SetPoint("TOPLEFT", fx, "TOPLEFT", -2, 2)
    fx.halo:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 2, -2)
    fx.haloEdge = ns.CreateBorder(fx.halo, 2, "OVERLAY")
    fx.haloEdge:Hide()

    -- The running squares live on a frame of their own, OUTSIDE the cell's
    -- rect: a dot is centred on the outline, so half of it hangs over the
    -- edge and would be clipped by a parent that stops there.
    fx.dotHost = CreateFrame("Frame", nil, fx)
    fx.dotHost:SetPoint("TOPLEFT", fx, "TOPLEFT", -4, 4)
    fx.dotHost:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 4, -4)
    fx.dotHost:Hide()
    fx.dots = {}

    fx.flash = fx:CreateTexture(nil, "OVERLAY", nil, 3)
    fx.flash:SetAllPoints(fx)
    fx.flash:SetTexture(ns.WHITE)
    fx.flash:SetBlendMode("ADD")
    fx.flash:SetAlpha(0)

    cell.fx = fx
    return fx
end

-- Everything our overlay is showing, off, and the cell's remembered state
-- cleared. For a cell that lost its frame, changed its spell or fell off the
-- bar - without this the last frame of a glow stays on screen for ever.
--
-- THE GREYING IS NOT UNDONE HERE, and it does not need to be. It went on
-- through Claim.Set, so Claim.Give puts the icon's own vertex colour back
-- when the frame is handed over; a frame the pool re-issues to another cell
-- arrives with our state gone and is repainted on its first tick; and a frame
-- nobody wants is at alpha 0. Every path closes within one tick, which is why
-- this does not need to hold on to an item frame to be correct.
function Effects.Silence(cell)
    local fx = cell and cell.fx
    if not fx then
        if cell then cell.fxState = nil end
        return false
    end

    fx:Hide()
    fx.glow:Hide()
    fx.haloEdge:Hide()
    if fx.dotHost then fx.dotHost:Hide() end
    fx.flash:SetAlpha(0)
    cell.fxState = nil
    return true
end

---------------------------------------------------------------------------
-- The one ticker
--
-- ONE FRAME FOR EVERY CELL, not one per cell, and its OnUpdate is INSTALLED
-- when something is watched and REMOVED when nothing is. That is what makes
-- "nothing polls" true rather than "an empty loop runs sixty times a second".
--
-- Throttled: nothing here has to be right to the frame, and a pulse computed
-- sixteen times a second looks exactly like one computed sixty times a
-- second.
---------------------------------------------------------------------------
local TICK = 0.06
local elapsed = 0
local armed = false

local ticker = CreateFrame("Frame")

local function OnUpdate(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end

    -- THE REAL SPAN SINCE THE LAST TICK, not the throttle interval. They are
    -- not the same number - a tick fires on the first frame at or after TICK,
    -- so counting in TICKs makes "two pulses" run long on a loaded machine
    -- and drift further the worse the frame rate is.
    local span = elapsed
    elapsed = 0

    Effects.Step(GetTime(), UnitAffectingCombat("player") and true or false,
        span)
end

local function Arm()
    if armed then return end
    armed = true
    elapsed = 0
    ticker:SetScript("OnUpdate", OnUpdate)
end

local function Disarm()
    if not armed then return end
    armed = false
    ticker:SetScript("OnUpdate", nil)
end

---------------------------------------------------------------------------
-- The registry
--
-- Rebuilt every render pass rather than kept in step by hand. A cell that
-- stops being tracked has to stop being ticked, and "remember to unregister"
-- is the kind of rule that survives exactly until the next feature.
--
-- The entries hold a live item frame. That is safe BECAUSE the list is thrown
-- away every pass: nothing here outlives the pass that made it, so a pooled
-- frame is held for one render and no longer, and no weak table is needed to
-- say so.
---------------------------------------------------------------------------
local watched = {}
local watching = 0

-- Set by any cell whose state rule changed what it should look like, cleared
-- after ONE repaint. A flag rather than a call per cell: twelve cooldowns
-- coming back together is one render, not twelve.
local repaintWanted = false
local repaint

-- What Effects.Pass worked out this pass, so Track can seed a cell's memory
-- with it. Weak keys, because these are Blizzard's pooled frames and a strong
-- table would hold every one the session ever saw.
local seedHidden = setmetatable({}, { __mode = "k" })

-- Asked once per pass rather than once per cell: HasAny walks the sound book,
-- and the answer cannot change while a single render pass runs.
local soundWanted

function Effects.BeginPass()
    for index = 1, watching do watched[index] = nil end
    watching = 0
    soundWanted = nil
    for item in pairs(seedHidden) do seedHidden[item] = nil end
end

-- Puts an entry on the list and arms the ticker. Exported so the self test
-- can drive a tick with a cell it made itself.
function Effects.Watch(cell, entry)
    if not (cell and entry) then return false end
    entry.cell = cell
    watching = watching + 1
    watched[watching] = entry
    Arm()
    return true
end

-- Silences every watched cell, empties the list and DISARMS. What Render.Stop
-- calls, and the difference between "nothing polls" and "an empty loop runs".
function Effects.StopAll()
    local stopped = watching
    for index = 1, watching do
        local entry = watched[index]
        if entry and entry.cell then Effects.Silence(entry.cell) end
        watched[index] = nil
    end
    watching = 0
    soundWanted = nil
    repaintWanted = false
    Disarm()
    return stopped
end

-- How many cells the ticker is walking, and whether it is armed at all. For
-- /zs cdm, and for the self test's "a bar with everything off costs nothing".
function Effects.Watched()
    return watching, armed
end

-- WHO TO ASK FOR A REPAINT when a state rule flips. Registered once by
-- Render.Start. A callback rather than a call, because this file loads ABOVE
-- Render.lua and a file may not reach up the TOC.
function Effects.OnRepaint(fn)
    if type(fn) == "function" then repaint = fn end
end

---------------------------------------------------------------------------
-- One walk of a bar, before anything is placed
--
-- Render asks this first and feeds the answer straight into Model.Places, and
-- then reads it again per cell to choose Claim.Veil over Claim.Reveal.
--
-- THE MAP IS THE STATE RULE'S AND NOTHING ELSE'S. Render used to build a map
-- of "this cell has no live frame" and hand THAT to the compactor; it was
-- dead code because nothing set a reflow mode, and the day one did, his
-- five-icon row would have re-packed itself every time Blizzard stopped
-- pooling a situational spell. 4.82.0 fed Compact the state map only
-- (Screen.lua:1240-1248) and so does this.
--
-- HOW WIDE A LINE IS belongs to Model.Places, which passes `columns`. That is
-- right for all four of his bars and wrong for a flow="columns" bar, where a
-- line is a column of `rows` cells. Named here rather than patched into
-- Model.lua, which is wave 1's and pure.
---------------------------------------------------------------------------
function Effects.Pass(bar, items, count)
    local fxOpts = type(bar) == "table" and bar.effects or nil
    local hidden = {}
    local compact = Effects.Option(fxOpts, "reflow")

    -- CAN THIS RULE HIDE ANYTHING AT ALL - asked of the rule itself rather
    -- than by comparing hideWhen to a word here. If neither answer hides,
    -- nothing can, and the whole per-cell read below is skipped: Relevant
    -- costs a GetSpellCooldown and sometimes an aura scan, per cell, per
    -- pass, and "never" is the default on every bar he owns.
    local asks = Effects.HiddenByState(fxOpts, true)
        or Effects.HiddenByState(fxOpts, false)

    local cells = Store.Cells(bar)
    for index = 1, (count or 0) do
        local item = items and items[index]
        if item then
            local off = false
            if asks then
                off = Effects.HiddenByState(fxOpts, Effects.Relevant(item,
                    cells[index], ns.CDM:ItemCooldownID(item)))
            end
            if off then hidden[index] = true end

            -- What the tick must start from, so the first tick after a pass
            -- cannot report a flip that the pass itself caused - which would
            -- ask for a render from inside the render it was made by.
            seedHidden[item] = off
        end
    end

    return hidden, compact
end

---------------------------------------------------------------------------
-- Registering one cell
--
-- `item` FIRST, deliberately: that is the desk guard's door, so every line of
-- this function is checked against the frame contract. Reading its strata and
-- its level is allowed and writing anything is not.
---------------------------------------------------------------------------
function Effects.Track(item, cell, bar, spellID)
    if not (item and cell) then return false end

    local fxOpts = type(bar) == "table" and bar.effects or nil
    if soundWanted == nil then
        soundWanted = (ns.Sounds and ns.Sounds.HasAny("ready")) and true or false
    end

    if not Effects.Wanted(fxOpts, soundWanted) then
        Effects.Silence(cell)
        return false
    end

    local fx = Effects.Attach(cell)
    if item.GetFrameStrata then
        fx:SetFrameStrata(item:GetFrameStrata() or "MEDIUM")
    end
    if item.GetFrameLevel then
        fx:SetFrameLevel((item:GetFrameLevel() or 0) + 6)
    end

    -- The refresh window, hooked on the frame rather than computed. Idempotent
    -- and safe to call every pass; the closures it installs live at file scope
    -- in CDM.lua, because a hooksecurefunc callback is billed to the addon
    -- whose execution context created it and one built inside a render pass
    -- bills whoever we are standing in.
    if type(ns.CDM.HookPandemic) == "function" then ns.CDM:HookPandemic(item) end

    local state = cell.fxState
    if not state then
        state = {}
        cell.fxState = state
    end
    local seeded = seedHidden[item]
    if seeded ~= nil then state.hidden = seeded end

    Effects.Watch(cell, {
        item       = item,
        spellID    = spellID,
        cooldownID = ns.CDM:ItemCooldownID(item),
        -- Asked once, here, rather than on every tick: which viewer a frame
        -- came out of only changes when the pools churn, and a churn rebuilds
        -- this list anyway.
        tracks     = Tracks(item),
        effects    = fxOpts,
    })
    return true
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- THE SQUARES, PLACED. Everything decided here is arithmetic from
-- Effects.PerimeterPoint; this function only turns it into anchors.
--
-- The dots are made on demand and kept: a frame cannot be freed in this game,
-- so a pool that only ever grows to the largest count a bar has used is the
-- honest shape rather than a leak.
local function RunDots(fx, fxOpts, now, r, g, b, alpha, thickness)
    local host = fx.dotHost
    if not host then return end

    local wanted = math.max(2, math.min(24,
        math.floor(tonumber(Effects.Option(fxOpts, "glowDots")) or 8)))
    local size = math.max(2, thickness + 1)

    -- The inset the host was given, so a dot centred on the OUTLINE of the
    -- cell sits at the middle of its own square rather than at its corner.
    local width = math.max(0, (host:GetWidth() or 0) - 8)
    local height = math.max(0, (host:GetHeight() or 0) - 8)

    -- One lap every four seconds at speed 1. Slow enough to read as a
    -- travelling light rather than as a flicker.
    local speed = tonumber(Effects.Option(fxOpts, "pulseSpeed")) or 1
    local lap = (now * 0.25 * speed) % 1

    for index = 1, wanted do
        local dot = fx.dots[index]
        if not dot then
            dot = host:CreateTexture(nil, "OVERLAY")
            dot:SetTexture(ns.WHITE)
            dot:SetBlendMode("ADD")
            fx.dots[index] = dot
        end

        local x, y = Effects.PerimeterPoint(lap + (index - 1) / wanted,
            width, height)
        dot:SetSize(size, size)
        dot:ClearAllPoints()
        -- +4 puts it back into the host's own coordinates, and the half-size
        -- centres the square on the line instead of hanging it off one side.
        dot:SetPoint("CENTER", host, "BOTTOMLEFT", x + 4, y + 4)
        dot:SetColorTexture(r, g, b, alpha)
        dot:Show()
    end

    -- Anything left over from a larger count is parked, never destroyed.
    for index = wanted + 1, #fx.dots do fx.dots[index]:Hide() end

    host:Show()
end

-- THE ONE WRITE THIS FILE MAKES TO SOMETHING BLIZZARD OWNS, and it goes
-- through the door every other file writes through: Claim.Set records the
-- icon's vertex colour before we touch it, so Claim.Give hands it back
-- exactly as it was.
--
-- NOT Claim.Unset to undo it. Unset clears everything recorded for an object,
-- and the look wave writes SetDesaturated and SetTexCoord on this same icon -
-- undoing our greying that way would rip out its crop with it. Full brightness
-- is written instead, and the real value is still the one Claim gives back.
local function Dim(item, value)
    local icon = item and item.Icon
    if type(icon) ~= "table" then return false end
    return Claim.Set(icon, "SetVertexColor", value, value, value)
end

local function TickCell(entry, now, inCombat, span)
    local cell = entry.cell
    local fx = cell.fx
    if not fx then return end

    local fxOpts = entry.effects
    local state = cell.fxState
    if not state then
        state = {}
        cell.fxState = state
    end

    -----------------------------------------------------------------------
    -- What is true right now
    --
    -- TWO DIFFERENT QUESTIONS, and they are not each other's opposite.
    --
    --   ready  a COOLDOWN is available again, or its own buff is still
    --          working. nil when it cannot be read.
    --   lit    the buff this cell tracks is up. nil when this is not that
    --          kind of cell at all.
    --
    -- ONE read answers whichever of the two this cell has, and the split is
    -- by ns.CDM:ItemTracks - by what the item is ABOUT. The first version
    -- answered both with one field - `ready = not active` on an aura cell -
    -- and it was backwards in the way that shows: the ready glow lit every
    -- proc that was DOWN and the flash fired when one ran out rather than
    -- when it landed.
    --
    -- It is deliberately the SAME read the hide rule uses. Two readings of
    -- one state is how a ticker and a render pass end up disagreeing for a
    -- frame, and on a defensive whose buff is still running "up" is what both
    -- of them mean.
    -----------------------------------------------------------------------
    local relevant = Effects.Relevant(entry.item, entry.spellID,
        entry.cooldownID)

    local ready, lit
    if entry.tracks == "buff" then lit = relevant else ready = relevant end

    -----------------------------------------------------------------------
    -- The flash, on the edge into the state worth noticing: a cooldown
    -- coming back, or the buff landing.
    --
    -- Compared against `false` rather than "not nil": the very first tick
    -- after a cell appears knows nothing about the tick before it, and a
    -- flash there would fire on every reload and every re-flow.
    -----------------------------------------------------------------------
    local arrived
    if lit ~= nil then
        arrived = lit and state.wasLit == false
        state.wasLit = lit
    elseif ready ~= nil then
        arrived = ready and state.wasReady == false
        state.wasReady = ready
    end

    if arrived and Effects.Option(fxOpts, "readyFlash") then
        local pulses = tonumber(Effects.Option(fxOpts, "readyPulses")) or 2
        state.flashLeft = pulses * FLASH_STEP
    end

    -- AND THE SAME EDGE MAKES THE NOISE. On `arrived` rather than on `ready`,
    -- for the reason written above it: `ready` is true for as long as the
    -- spell is up, and a sound on a state rather than on a change would play
    -- sixty times a second. It is deliberately NOT behind readyFlash - a
    -- sound instead of a flash is a reasonable thing to want, and one switch
    -- for two senses is how a setting becomes unexplainable.
    --
    -- Keyed by the spell, so a cooldown that sits on three bars makes one
    -- sound rather than three, and moving it does not lose it. The throttle
    -- in Sounds.Play is what keeps a whole bar coming back at once to one.
    if arrived and ns.Sounds then
        ns.Sounds.Play("ready", entry.spellID)
    end

    -- How long it has been sitting there ready, for the nag. Cooldowns only:
    -- a buff that is up is not something you are forgetting to press.
    if ready == false then
        state.readySince = nil
    elseif ready and not state.readySince then
        state.readySince = now
    end

    -----------------------------------------------------------------------
    -- Draw it
    -----------------------------------------------------------------------
    local speed = tonumber(Effects.Option(fxOpts, "pulseSpeed")) or 1
    local glowKey, glowAlpha

    -- The nag wins over the plain ready glow: it is the one that means
    -- something is going wrong, and two edges at once is just mud.
    local nagAfter = tonumber(Effects.Option(fxOpts, "reminderAfter")) or 0
    if nagAfter > 0 and inCombat and ready and state.readySince
        and (now - state.readySince) >= nagAfter then
        glowKey = "reminderColor"
        glowAlpha = 0.35 + 0.65 * Effects.Pulse(now, speed)
    else
        -- ASKED ONLY WHEN THE SETTING IS ON, and kept out of the condition
        -- itself. 4.82.0 wrote `usableOnly and Affordable(id) or nil` here,
        -- and `x and y or z` cannot carry false: the one answer this setting
        -- exists to act on - you cannot afford it - collapsed into nil, which
        -- GlowAllowed reads as "unknown" and lights. The setting has
        -- therefore never once done anything.
        local affordable
        if Effects.Option(fxOpts, "readyGlowUsableOnly") then
            affordable = Effects.Affordable(entry.spellID)
        end

        if Effects.GlowAllowed(fxOpts, ready, affordable)
            and (inCombat or not Effects.Option(fxOpts, "readyGlowCombatOnly"))
        then
            glowKey = "glowColor"
            glowAlpha = 0.85
        elseif Effects.Option(fxOpts, "activeGlow") and lit then
            glowKey = "activeColor"
            glowAlpha = 0.85
        end
    end

    -- THE REFRESH WINDOW WINS OVER THE PLAIN GLOWS, for the same reason the
    -- nag does: it is the one that means "press this now".
    if Effects.Option(fxOpts, "pandemicGlow") and InPandemic(entry.item) then
        glowKey = "pandemicColor"
        glowAlpha = 0.45 + 0.55 * Effects.Pulse(now, speed)
    end

    if glowKey then
        local r, g, b = Colour(fxOpts, glowKey)
        local thickness = tonumber(Effects.Option(fxOpts, "glowSize")) or 2

        if Effects.Option(fxOpts, "glowStyle") == "pixel" then
            -- The two rings step aside entirely. A running outline INSIDE a
            -- solid one is a box with something crawling in it; the motion is
            -- the whole signal and it needs the edge to itself.
            fx.glow:Hide()
            fx.haloEdge:Hide()
            RunDots(fx, fxOpts, now, r, g, b, glowAlpha, thickness)
        else
            if fx.dotHost then fx.dotHost:Hide() end
            fx.glow:SetThickness(thickness)
            fx.glow:SetColor(r, g, b, glowAlpha)
            fx.glow:Show()
            fx.haloEdge:SetThickness(math.max(1, thickness - 1))
            fx.haloEdge:SetColor(r, g, b, glowAlpha * 0.35)
            fx.haloEdge:Show()
        end
        fx:Show()
    else
        fx.glow:Hide()
        fx.haloEdge:Hide()
        if fx.dotHost then fx.dotHost:Hide() end
    end

    if state.flashLeft and state.flashLeft > 0 then
        state.flashLeft = state.flashLeft - span
        local r, g, b = Colour(fxOpts, "readyColor")
        fx.flash:SetVertexColor(r, g, b)
        fx.flash:SetAlpha(Effects.FlashAlpha(state.flashLeft))
        fx:Show()
        if state.flashLeft <= 0 then
            state.flashLeft = nil
            fx.flash:SetAlpha(0)
        end
    elseif fx.flash:GetAlpha() > 0 then
        fx.flash:SetAlpha(0)
    end

    if not glowKey and not state.flashLeft then fx:Hide() end

    -----------------------------------------------------------------------
    -- Taking it off the screen, by state
    --
    -- NOT WRITTEN HERE, and that is the whole design. The render pass owns
    -- whether a cell is on screen - it is Claim.Reveal or Claim.Veil and
    -- nothing in between - and a ticker writing a second answer sixteen times
    -- a second would win until the next render and lose on it, which is a
    -- flicker rather than a feature.
    --
    -- So this notices the FLIP and asks for one repaint. A cooldown starting
    -- or ending is a handful of events a fight, not a per-frame job.
    -----------------------------------------------------------------------
    -- `relevant`, NOT `ready`, and it is the one line where that matters.
    -- Effects.Pass asks with Relevant's answer for BOTH kinds of cell, so a
    -- tick that asked with `ready` would be nil on every buff cell and would
    -- never notice a proc dropping - the pass would take it off screen and
    -- nothing would ever put it back. Two readings of one state, one frame
    -- apart, is the fault this whole file is arranged to make impossible.
    local wantsHidden = Effects.HiddenByState(fxOpts, relevant)
    if state.hidden == nil then
        state.hidden = wantsHidden
    elseif state.hidden ~= wantsHidden then
        state.hidden = wantsHidden
        repaintWanted = true
    end

    -----------------------------------------------------------------------
    -- Greying out while the cooldown runs
    -----------------------------------------------------------------------
    if Effects.Option(fxOpts, "dimOnCooldown") and ready ~= nil then
        local target = ready and 1
            or (tonumber(Effects.Option(fxOpts, "dimAmount")) or 0.55)
        -- Only on a CHANGE. Writing a vertex colour sixteen times a second
        -- for the whole length of a two-minute cooldown is work for nothing.
        if state.dim ~= target then
            state.dim = target
            Dim(entry.item, target)
        end
    elseif state.dim and state.dim ~= 1 then
        state.dim = 1
        Dim(entry.item, 1)
    end
end

---------------------------------------------------------------------------
-- One tick over every watched cell
--
-- EXPORTED, because the harness deliberately does not dispatch OnUpdate -
-- firing those from out there would be inventing a client - and this is the
-- only way the desk can prove that a flash decays, that an edge fires once,
-- or that twelve cells flipping together ask for ONE repaint.
--
-- `now`, `inCombat` and `span` are all handed in for the same reason.
---------------------------------------------------------------------------
function Effects.Step(now, inCombat, span)
    local walked = 0

    for index = 1, watching do
        local entry = watched[index]
        if entry and entry.cell then
            walked = walked + 1
            local ok, err = pcall(TickCell, entry, now, inCombat, span or 0)
            if not ok then
                -- One bad cell must not stop the other eleven, and it must
                -- not spam the error frame sixteen times a second either.
                watched[index] = nil
                geterrorhandler()(err)
            end
        end
    end

    -- AFTER the walk, so a render triggered by the first cell does not run
    -- while the other eleven are still being ticked - Render rebuilds the
    -- very list being walked.
    local repainted = false
    if repaintWanted then
        repaintWanted = false
        if repaint then repainted = pcall(repaint) and true or false end
    end

    -- Nothing left to watch: stop being a per-frame job at all. A pass that
    -- registered nobody costs one more tick and then costs nothing.
    if watching == 0 then Disarm() end

    return walked, repainted
end

---------------------------------------------------------------------------
-- WHY IS NOTHING HIDING
--
-- Owner set "take off screen: while on cooldown", photographed a bar with
-- four running cooldowns still on it, and said "scheint noch nicht zu
-- funktionieren."
--
-- Every reading in this chain is a value the client is allowed to withhold,
-- and the whole addon answers a withheld value with "do what the feature
-- switched off does" - so a rule that never fires and a rule that is never
-- ASKED look identical from the outside. Reading further would have been the
-- third guess in a row; this asks the client instead.
--
-- Run it while the cooldowns are actually running, which is the state that
-- cannot be reproduced at a desk.
---------------------------------------------------------------------------
local function Say(label, value)
    if value == nil then
        return string.format("%s |cff888888nil|r", label)
    end
    if not ns.CanCompute(value) then
        return string.format("%s |cffff7a3dSECRET|r", label)
    end
    return string.format("%s |cffffd100%s|r", label, tostring(value))
end

function Effects.Dump()
    ns.Print("|cffffd100--- what the client will say about each cooldown ---|r")
    ns.Print("|cff888888SECRET means the value exists and may not be read. "
        .. "That is not a bug in itself - it is why a rule stands down.|r")

    if type(ns.CDM.PandemicSupported) == "function"
        and not ns.CDM:PandemicSupported() then
        ns.Print("|cff888888No item frame on this client has "
            .. "ShowPandemicStateFrame, so the refresh marker cannot light "
            .. "for anything.|r")
    end

    for _, bar in pairs(Store.Bars()) do
        if type(bar) == "table" then
            local rule = Effects.Option(bar.effects, "hideWhen")
            ns.Print(string.format("|cffffd100%s|r  take off screen: %s  "
                .. "reflow: %s", tostring(bar.name or bar.id or "?"), rule,
                tostring(Effects.Option(bar.effects, "reflow"))))

            local cells = Store.Cells(bar)
            for cellIndex = 1, Store.Capacity(bar) do
                local spellID = cells[cellIndex]
                local item = spellID and ns.CDM:ItemForSpell(spellID) or nil
                if item then
                    local cooldownID = ns.CDM:ItemCooldownID(item)
                    local info = cooldownID and ns.CDM:GetInfo(cooldownID)
                    local relevant = Effects.Relevant(item, spellID, cooldownID)

                    local okCd, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
                    cdInfo = okCd and cdInfo or nil

                    local parts = {
                        Say("isActive", info and info.isActive),
                        Say("isOnGCD", info and info.isOnGCD),
                        Say("item:IsActive", ns.CDM:ItemIsActive(item)),
                        Say("start", cdInfo and cdInfo.startTime),
                        Say("duration", cdInfo and cdInfo.duration),
                        Say("tracks", Tracks(item)),
                        Say("own buff up", OwnBuffUp(spellID)),
                        Say("pandemic", InPandemic(item)),
                        Say("relevant", relevant),
                        Say("hidden", Effects.HiddenByState(bar.effects,
                            relevant)),
                    }
                    ns.Print(string.format("   %d. %s  cd=%s  %s", cellIndex,
                        ns.SpellName(spellID) or tostring(spellID),
                        tostring(cooldownID), table.concat(parts, "  ")))
                end
            end
        end
    end

    local walking, running = Effects.Watched()
    ns.Print(string.format("Ticker: |cffffd100%d|r cells watched, %s.",
        walking, running and "armed" or "|cff888888disarmed|r"))
end
