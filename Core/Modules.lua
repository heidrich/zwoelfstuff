---------------------------------------------------------------------------
-- Modules - which parts of this addon are actually running.
--
-- Owner, 2026-08-09: "danach gehen wir die struktur an, das wir module bauen
-- und den welcome screen". Four features had grown inside one addon, and all
-- four booted on every login whether anybody used them or not.
--
-- WHAT IS A MODULE AND WHAT IS NOT. A module is a FEATURE you can want or not
-- want: the bars, the co-tank panel, the reminders, the death log. What is
-- NOT a module is the machinery they all stand on - the Cooldown Manager
-- reader, the profile store, the design system, the minimap button and the
-- entry in the pause menu. Switching the bars off must not take the spell
-- catalogue with it, because a reminder asks that catalogue whether its buff
-- is up and the death log builds its defensives out of it. That is the whole
-- reason CDM:HookPools stayed in Init and is not in the list below.
--
-- WHAT "OFF" MEANS, exactly, and it is deliberately not "unregister
-- everything". Blizzard's callback registries here have no way back out, so a
-- module that had truly unhooked itself could never be switched on again
-- without a reload. Instead:
--
--   Boot   runs ONCE, and only for a module that is on. A module you never
--          switch on never builds a frame and never registers an event.
--   Apply  runs on every change of the switch, and puts the world in the
--          state the switch says - hand the icons back, hide the panel.
--   the GATE lives in the feature itself, in the ONE place that already
--          answers "should this be on screen": Screen:Render, ShouldShow,
--          RefreshIcon. One rule, one place; the switch is just one more
--          reason to say no.
--
-- THE ORDER OF THIS LIST IS THE BOOT ORDER. Reminders ask the Cooldown
-- Manager whether a buff is up, and the bars claim its icon frames first, so
-- the bars go above the reminders. This is the same order Init booted them in
-- when it was a straight line of calls.
--
-- WHERE THE SWITCHES LIVE: in the profile, so per character and realm. The
-- owner's rule for everything you can change about the interface, and it is
-- the right shape here too - a tank wants the death log, a healer alt does
-- not, and they are not the same character.
---------------------------------------------------------------------------
local _, ns = ...

local Modules = {}
ns.Modules = Modules

-- WHICH ROUND OF MODULES A PROFILE HAS ALREADY BEEN ASKED ABOUT.
--
-- The welcome window is shown once per character - and once more when an
-- update brings a module that character has never been offered. Each entry
-- below carries the generation it appeared in; bump this number and the
-- entry's `since` together, and only the new one is called out.
-- 2: the externals panel. The first module added AFTER the welcome window
--    existed, which is what it was built for: everybody who already answered
--    gets asked once more, about this one entry and nothing else.
-- 3: answering. The other end of the externals panel - somebody asks, and
--    this is the button that answers. It talks to other people's clients, so
--    being ASKED about it rather than having it appear is the whole point.
-- 4: the raid bar and the invite tool, together, because they arrived
--    together. Both are OFF by default and the argument is at their entries:
--    one puts buttons on your screen and the other acts in your name at
--    people who are not in the room, and neither should start doing that
--    because somebody updated an addon.
-- 5: the Cooldown Manager, coming back. Everybody who has already answered is
--    asked once more, about this one entry - and for a reason stronger than
--    usual: it is the only module in the list that can COLLIDE with another
--    addon, and the answer has to be given before either of us draws
--    anything. See Cooldowns/Rivals.lua.
Modules.GENERATION = 5

local LIST = {
    {
        -- FIRST IN THE LIST, WHICH IS BOOT ORDER. The reminders ask the
        -- Cooldown Manager whether a buff is up and the death log builds its
        -- defensives out of its catalogue, so it comes up before both - the
        -- same position the bars held before they were removed.
        --
        -- OFF DOES NOT MEAN "STOP REFRESHING" HERE, and this is the one
        -- module where that distinction has teeth. Every frame on screen
        -- belongs to Blizzard; we have moved it, resized it and taken its
        -- border off. A switch that merely stopped the render pass would
        -- leave all of that exactly as it is, with nothing left running that
        -- knows how to undo it - which is the fault the last implementation
        -- shipped, reached from the other direction. So Apply RELEASES: every
        -- frame back at the decoration it had before we touched it.
        --
        -- OFF BY DEFAULT WHEN SOMEBODY ELSE IS DOING IT. Modules:IsOn answers
        -- "on" for anything unanswered, so the default is written into the
        -- profile at first run instead of assumed here - see Init's rival
        -- check. Two addons fighting over Blizzard's frames is the one
        -- failure this module can cause, and the safe side of it is silence.
        -- `grid` is the design's own cooldowns mark - ICON_FILES maps it to
        -- nav-cooldowns, which is the file drawn for this page before the
        -- bars were removed. The drawing outlived the feature; it goes back
        -- on the feature rather than a second one being invented.
        key = "cooldowns", title = "Cooldowns", glyph = "grid", since = 5,
        blurb = "Blizzard's Cooldown Manager, on bars you arrange yourself.",
        detail = "Off, we leave Blizzard's cooldown frames alone entirely.",
        Boot = function() ns.Cooldowns.Render.Start() end,
        -- The switch in both directions, and they are not symmetrical: on is
        -- a render pass, off is a release. Refresh answers Stop for a module
        -- that is off, so this reads as one call and is two.
        Apply = function() ns.Cooldowns.Render.Refresh() end,
    },
    {
        key = "cotanks", title = "Co-Tanks", glyph = "tanks", since = 1,
        blurb = "Every other tank in the group, with their health and their cooldowns.",
        detail = "Off, the panel never appears and no taunt is announced.",
        -- The taunt announce belongs to this module: it is about the OTHER
        -- tank, its settings are on this page, and switching the module off
        -- has to switch off the thing that TALKS as well as the thing that
        -- draws. Its own watcher checks the switch too, because Boot runs
        -- once and a switch can be flipped afterwards.
        Boot = function()
            ns.CoTanks:Create()
            ns.Taunts:Start()
            ns.Taunts:Create()
        end,
        Apply = function()
            ns.CoTanks:Refresh()
            ns.Taunts.Refresh()
        end,
    },
    {
        key = "reminders", title = "Reminders", glyph = "bell", since = 1,
        blurb = "Text on your screen when a buff you rely on has fallen off.",
        detail = "Off, no reminder fires, and the ones you wrote are kept.",
        Boot = function()
            ns.Reminders:Rebuild()
            ns.Reminders:Start()
        end,
        Apply = function() ns.Reminders:Refresh() end,
    },
    {
        key = "externals", title = "External CD request", glyph = "tanks", since = 2,
        blurb = "Somebody else's cooldown - an external, lust, a battle res - and one click to ask.",
        detail = "Off, the panel never appears.",
        Boot = function() ns.Externals:Create() end,
        Apply = function() ns.Externals.Refresh() end,
    },
    {
        key = "answers", title = "External CD answer", glyph = "tanks", since = 3,
        blurb = "When a tank asks for one of YOUR cooldowns, a button lights up. You press it.",
        detail = "Off, nothing lights up and nobody's request reaches you.",
        Boot = function()
            ns.Answers:Create()
            ns.Answers:Start()
        end,
        Apply = function() ns.Answers.Refresh() end,
    },
    {
        -- ONE MODULE, TWO THINGS ON SCREEN: the bar and the raid check window
        -- it opens. They are not two features - the window is what one of the
        -- bar's buttons does, and a switch that leaves half of a button
        -- working is a switch nobody can reason about. It is also why the
        -- raid check ANSWERS other people's asks only while this is on: a
        -- switched-off feature that still talks on the addon channel is not
        -- switched off.
        key = "raidbar", title = "Raid Bar", glyph = "grid", since = 4,
        blurb = "Markers, world markers, pings, a ready check and a pull timer, on a bar you build yourself.",
        detail = "Off, the bar never appears and the raid check answers nobody.",
        Boot = function()
            ns.RaidBar:Create()
        end,
        Apply = function() ns.RaidBar.Refresh() end,
    },
    {
        -- NO Boot AT ALL, and that is the design rather than an omission. It
        -- owns no frame: its watcher is a file-scope frame listening for chat,
        -- and every one of its own switches is off until somebody says
        -- otherwise. Switching the module on therefore puts nothing in
        -- motion, which is exactly right for the one feature here that acts
        -- in your name.
        key = "invites", title = "Invites", glyph = "tanks", since = 4,
        blurb = "Somebody whispers \"inv\" and they are in the group.",
        detail = "Off, nothing is listening and no invitation is sent.",
    },
    {
        key = "deaths", title = "Death-log", glyph = "skull", since = 1,
        blurb = "What killed you, played back, and what you had that could have stopped it.",
        detail = "Off, nothing is recorded and the skull stays away.",
        -- No Boot. Its watcher is a file-scope frame that also LOADS the saved
        -- log, and a log that failed to load is a log you cannot get back by
        -- switching the module on. The recorder and the skull are gated
        -- instead, in Death.lua, where they already ask whether to run.
        Apply = function() ns.Death.RefreshIcon() end,
    },
}
Modules.LIST = LIST

local byKey = {}
for _, entry in ipairs(LIST) do byKey[entry.key] = entry end

function Modules:Get(key) return byKey[key] end
function Modules:All() return LIST end

-- HOW MANY THERE ARE, for the two sentences that say so.
--
-- Both of them said "Four features in one addon" - the welcome window and the
-- Modules note on the Settings page - and there have been SIX since External
-- CD answer arrived. Neither was wrong when it was typed; a number in a
-- sentence is simply a copy of a list, and the copy went stale the way every
-- second copy in this addon has. The rows underneath were always built from
-- the registry, so the window has been drawing six switches under a sentence
-- promising four.
function Modules:Count() return #LIST end

-- THE SWITCH, and every gate in the addon reads it through here.
--
-- An unknown key answers YES, not no. A typo in a gate would otherwise
-- silently switch a working feature off for everybody, which is the worse of
-- the two failures by a distance - and SelfTest checks that every key a gate
-- names is in the list above, so the typo is caught where it costs nothing.
function Modules:IsOn(key)
    if not byKey[key] then return true end
    local db = ns.db and ns.db.modules
    -- Before the profile is open there is nothing to read and the honest
    -- answer is the default: on.
    if not db then return true end
    return db[key] ~= false
end

-- Everything a module needs done to match its switch.
--
-- Boot is a pcall for the reason Init's boot loop is: one feature that throws
-- on the way up must not take the others with it, and the error is reported
-- rather than swallowed.
function Modules:Refresh(key)
    local entry = byKey[key]
    if not entry then return false end

    local on = self:IsOn(key)

    if on and entry.Boot and not entry.booted then
        entry.booted = true
        local ok, err = pcall(entry.Boot)
        if not ok then
            ns.Print("|cffff4040" .. entry.title .. " failed to start.|r Everything else still runs.")
            geterrorhandler()(err)
            return false
        end
    end

    if entry.Apply and (entry.booted or not entry.Boot) then
        local ok, err = pcall(entry.Apply, on)
        if not ok then geterrorhandler()(err) end
    end

    return true
end

-- Flip one, and put the world in its new state straight away. No reload.
function Modules:Set(key, on)
    if not byKey[key] then return end
    if not ns.db then return end
    ns.db.modules = ns.db.modules or {}
    ns.db.modules[key] = on and true or false
    self:Refresh(key)
end

function Modules:Toggle(key)
    self:Set(key, not self:IsOn(key))
end

-- Login. In list order, which is dependency order.
function Modules:BootAll()
    for _, entry in ipairs(LIST) do
        self:Refresh(entry.key)
    end
end

-- Every module the switch says is on, in list order. For the one-line status
-- the welcome window and /zs modules both print.
function Modules:CountOn()
    local on = 0
    for _, entry in ipairs(LIST) do
        if self:IsOn(entry.key) then on = on + 1 end
    end
    return on, #LIST
end

---------------------------------------------------------------------------
-- The welcome window's question: has this character been asked yet, and about
-- what.
--
-- A pure rule, so it can be tested without a profile: given what the profile
-- last saw and the generation we ship, say whether to open the window and
-- which entries are new to this character.
--
-- seen == nil is a character that has never been asked at all - every module
-- is new to them, and the window opens showing the whole list rather than
-- four "NEW" badges, because on a first run everything being new is not
-- information.
---------------------------------------------------------------------------
function Modules.WelcomeDue(seen, generation, list)
    generation = generation or Modules.GENERATION
    list = list or LIST

    if seen == nil then
        return true, {}, true   -- due, nothing singled out, first time
    end
    if type(seen) ~= "number" or seen >= generation then
        return false, {}, false
    end

    local fresh = {}
    for _, entry in ipairs(list) do
        if (entry.since or 1) > seen then fresh[#fresh + 1] = entry.key end
    end
    -- A generation bumped without a new module is not a reason to open a
    -- window in somebody's face.
    if #fresh == 0 then return false, {}, false end
    return true, fresh, false
end
