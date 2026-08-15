---------------------------------------------------------------------------
-- Who else is managing cooldowns on this account.
--
-- Two addons that both take over Blizzard's Cooldown Manager frames produce a
-- broken screen and neither of them can tell whose fault it is - the frames
-- are Blizzard's, both addons claim them, and the loser is whoever ran second
-- that login. It is not diagnosable from the inside, so it has to be ASKED
-- before either of us starts.
--
-- WHY THERE IS NO LIST OF ADDON NAMES.
--
-- A hardcoded list is wrong twice: it names addons that have not been written
-- yet, and it goes stale the first time somebody renames a folder. Every
-- cooldown-manager addon has to SAY SO in its TOC, because that is the line a
-- person reads before installing it - so the metadata is a better list than
-- any we could keep, and it is already on the user's disk.
--
-- CALIBRATED AGAINST 97 INSTALLED ADDONS, not reasoned. Matching on the word
-- "cooldown" alone gives a false positive on the first machine it was tried
-- on: ProfessionShoppingList's notes read "Track recipes, reagents,
-- cooldowns, patron orders". So the phrases below are the ones that only a
-- Cooldown Manager addon uses, and on that machine they match exactly one
-- addon - EllesmereUI's, whose notes say "A CDM replacement focused on
-- performance, customizations and alerts".
--
-- CHECKED AGAINST SOMEBODY ELSE'S LIST, which is the strongest test available
-- for a rule about addons that are not installed here. EllesmereUI ships a
-- table of what it believes collides with its own cooldown module. Of the
-- addons in it that are specifically about cooldowns, this rule finds all but
-- one from metadata alone. The exception is a whole interface suite whose
-- name and description never mention cooldowns - and it is deliberately NOT
-- hardcoded here, because the claim that it collides is somebody else's,
-- unverified, and a warning that fires on a suite is a warning aimed at a
-- great many people who do not have this problem.
--
-- So the honest statement of what this can do is the one the options page
-- makes: it finds addons that SAY what they are.
--
-- WHAT THIS DELIBERATELY DOES NOT REPORT. MoveAny is installed on that same
-- machine and can move all four viewers - but only for a frame the user has
-- ticked, and the default is off (its settings.lua registers the widget
-- behind `IsEnabled("EssentialCooldownViewer", false)`). An addon that COULD
-- collide is not one that DOES, and a warning that fires on a quiet neighbour
-- is a warning people learn to click away.
--
-- ENABLED, NOT INSTALLED. An addon switched off for this character is not
-- managing anything. GetAddOnEnableState answers that without the other addon
-- having loaded, which is what makes this safe to ask early - a check that
-- depended on load order would report "no conflict" for whoever loads after
-- us and be wrong every second login.
---------------------------------------------------------------------------
local ADDON, ns = ...

local Cooldowns = ns.Cooldowns
local Rivals = {}
Cooldowns.Rivals = Rivals

-- The phrases, lower-cased. Each one is a claim only a Cooldown Manager addon
-- makes about itself. "cooldown" on its own is NOT here, and the comment above
-- says what it cost.
local CLAIMS = {
    "cooldown manager",
    "cooldownmanager",
    "cooldown viewer",
    "cooldownviewer",
}

-- CDM as a WORD, not as three letters. Without the boundaries this matches
-- "cdmanager" and, more to the point, any addon whose author initials happen
-- to fall that way in a sentence.
local function SaysCDM(text)
    return text:find("%f[%w]cdm%f[%W]") ~= nil
end

local function Claims(text)
    if not text or text == "" then return false end
    text = text:lower()
    for _, phrase in ipairs(CLAIMS) do
        if text:find(phrase, 1, true) then return true end
    end
    return SaysCDM(text)
end

-- 2 means enabled for this character. BigWigs' loader says so in as many
-- words at Loader.lua:955, and passes the player's GUID as the second
-- argument, which is the spelling that works on this patch.
local ENABLED = 2

local scanned, found

---------------------------------------------------------------------------
-- Every enabled addon that says it manages cooldowns, us excluded
--
-- Cached for the session: an addon cannot be enabled or disabled without a
-- reload, so the answer cannot change under us, and the loop is over every
-- addon the client knows.
---------------------------------------------------------------------------
function Rivals.Others()
    if scanned then return found end
    scanned, found = true, {}

    local C = C_AddOns
    if not (C and C.GetNumAddOns and C.GetAddOnInfo) then return found end

    -- nil rather than an error on a client that does not answer: without a
    -- character the enable state cannot be asked, and reporting nobody is the
    -- honest answer, not reporting everybody.
    local me = UnitGUID and UnitGUID("player")

    for index = 1, C.GetNumAddOns() do
        local ok, name, title, notes = pcall(C.GetAddOnInfo, index)
        if ok and name and name ~= ADDON then
            local on = true
            if me and C.GetAddOnEnableState then
                local okState, state = pcall(C.GetAddOnEnableState, name, me)
                on = (not okState) or state == ENABLED
            end
            -- THE FOLDER NAME COUNTS TOO, and it is the cheapest of the three.
            -- Four of the five cooldown-manager addons known to collide with
            -- this one are called BetterCooldownManager, CooldownManagerCentered,
            -- SkironCooldownManager and Ayije_CDM: every one of them says what
            -- it is in the folder alone, and an addon whose author was terse in
            -- the Notes field is not one we want to miss.
            if on and (Claims(name) or Claims(title) or Claims(notes)) then
                found[#found + 1] = {
                    folder = name,
                    -- The title is what the user sees in their addon list, so
                    -- it is what we name them by. Colour codes stripped: they
                    -- are the other addon's branding and would repaint our
                    -- sentence in the middle.
                    label = (title and title ~= "" and title:gsub("|c%x%x%x%x%x%x%x%x", "")
                        :gsub("|r", "") or name),
                }
            end
        end
    end
    return found
end

-- The one question the welcome window asks. Returns the list and its length,
-- so a caller can say "one" or name them without counting twice.
function Rivals.Any()
    local others = Rivals.Others()
    return #others > 0, others
end

-- What to print in a sentence: "EllesmereUI Cooldown Manager", or two names
-- joined, or "three other addons" once a list stops being readable.
function Rivals.Describe()
    local others = Rivals.Others()
    if #others == 0 then return nil end
    if #others == 1 then return others[1].label end
    if #others == 2 then
        return others[1].label .. " and " .. others[2].label
    end
    return ns.L("%d other addons", #others)
end

---------------------------------------------------------------------------
-- WHY THIS FILE WRITES NOTHING
--
-- The first draft set the module's default from what it found: off when a
-- rival was present, on when the list looked quiet. It was deleted, and the
-- reason is worth keeping because it looked like the careful option.
--
-- A default that reads the addon list is a setting that CHANGES BEHIND THE
-- USER. Install something else next month and a feature you were using turns
-- itself off, or one you never asked for turns itself on - and neither event
-- says a word. It also fights the profile machinery rather than using it:
-- ApplyDefaults fills the key on the first login after an update, so the
-- "nobody has answered yet" test it depended on was already false by the time
-- it ran.
--
-- The module ships OFF, like the raid bar and the invite tool, for the same
-- stated reason and a stronger one - see ns.DEFAULTS.modules. Then the only
-- job left here is to SAY WHAT IS THERE, and every answer the user gets is
-- one they gave.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- WHO ELSE WOULD GO DARK IF THAT ADDON DID
--
-- Owner, 2026-08-15: "jetzt noch einen button einbauen, das man andere cdm
-- abstellt, das kann elle ui auch." It can, and this is the part their power
-- button does not do.
--
-- DisableAddOn does not cascade. Switch off an addon that another one lists
-- as a Dependency and the second simply stops loading, with no message from
-- anybody - the user pressed a button about their cooldowns and lost
-- something else entirely. On the machine this was written on nothing
-- depends on EllesmereUI's cooldown module, which is exactly why the check
-- has to exist rather than be reasoned away: the next person's setup is not
-- this one.
--
-- Only ENABLED addons count. One that is already switched off cannot be
-- broken by this.
---------------------------------------------------------------------------
function Rivals.Dependents(folder)
    local out = {}
    local C = C_AddOns
    if not (folder and C and C.GetNumAddOns and C.GetAddOnInfo
        and C.GetAddOnDependencies) then
        return out
    end

    local me = UnitGUID and UnitGUID("player")
    for index = 1, C.GetNumAddOns() do
        local ok, name = pcall(C.GetAddOnInfo, index)
        if ok and name and name ~= folder then
            local on = true
            if me and C.GetAddOnEnableState then
                local okState, state = pcall(C.GetAddOnEnableState, name, me)
                on = (not okState) or state == ENABLED
            end
            if on then
                -- Varargs, so it is collected into a table before anything
                -- indexes it. GetAddOnDependencies returns the names one
                -- after another rather than a list.
                local okDeps, deps = pcall(function()
                    return { C.GetAddOnDependencies(index) }
                end)
                if okDeps and deps then
                    for _, dep in ipairs(deps) do
                        if dep == folder then out[#out + 1] = name end
                    end
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- SWITCH THEIRS OFF AND TAKE OVER
--
-- Three things, and they belong together because two of them without the
-- third leave somebody worse off than before: their addon goes off, ours
-- goes on, and the caller reloads. Disabling theirs alone would reload into
-- no cooldown manager at all, which is not what anybody pressed the button
-- for.
--
-- IT DELETES NOTHING. DisableAddOn is the same switch as the tick in the
-- game's own addon list - their settings, their layouts and their saved
-- variables are all untouched, and switching it back on there puts
-- everything back. That is worth saying out loud on the button, and it is
-- said.
--
-- The reload is the CALLER's, not ours. A function that reloads the interface
-- can never be run by a test, and this one has enough in it to be worth
-- testing.
---------------------------------------------------------------------------
function Rivals.Disable(folder)
    if not folder or folder == "" then return false, "no addon named" end

    local C = C_AddOns
    if not (C and C.DisableAddOn) then
        return false, "this client cannot switch addons off"
    end

    local ok = pcall(C.DisableAddOn, folder)
    if not ok then return false, "the client refused" end

    -- Ours on, in the same breath. Modules:Set writes it to the profile, and
    -- the reload that follows is what saves the profile - so the order
    -- matters: written first, reloaded after.
    if ns.Modules then ns.Modules:Set("cooldowns", true) end

    -- The scan is cached, and it is now wrong.
    Rivals.Forget()
    return true
end

-- FOR THE TESTS AND FOR /reload-less checking. The scan is cached because the
-- answer cannot change; this is the door that says otherwise.
function Rivals.Forget()
    scanned, found = nil, nil
end

-- The rule on its own, so the calibration above can be tested without a
-- client. Exported for that reason and no other.
Rivals.Claims = Claims
