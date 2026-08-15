---------------------------------------------------------------------------
-- CDM - the Cooldown Manager layer.
--
-- THE CHANGE OF APPROACH, and why.
--
-- Everything before this tried to track auras itself. On patch 12.0 that is
-- impossible: aura fields are secret values, so an addon cannot identify a
-- buff by ID, name or icon. The sanctioned replacement, Blizzard_AuraContainer,
-- does not arrive until 12.1 - measured on this client, CreateFrame for it
-- fails outright. So the entire aura-tracking stack could not work here, and
-- did not.
--
-- Blizzard's Cooldown Manager already solved all of it. It knows every
-- tracked cooldown and buff, it owns frames that display them with correct
-- icons, swipes, charges, stacks and timing, and it does that inside the
-- game where secret values are not a problem.
--
-- WE READ IT. WE NO LONGER TAKE IT OVER, and that is the change in 4.83.0.
--
-- Until then this file did both: it answered questions about the Cooldown
-- Manager, and it also adopted Blizzard's item frames - re-anchoring them,
-- resizing them, stripping their decorations and handing them back on
-- release. That half was the engine under our own cooldown bars, and the
-- bars are gone. Owner's words: "there are a lot of other very good CDM
-- addons that do the job better." So a thousand lines of takeover went with
-- them, and what is left is the half every OTHER module actually uses:
--
--   what does the Cooldown Manager know     Catalogue, ForEachCatalogued
--   which frame is showing this spell       ItemForSpell, RebuildItemIndex
--   is that frame active right now          ItemIsActive
--   what spell is this frame really         ItemSpellID, VariantFamily
--
-- Nothing here writes to a Blizzard frame any more. Every remaining call
-- asks and reports. The reminders, the co-tank panel, the death log and the
-- spell picker are the readers; if this file ever starts setting points
-- again, that is the bars coming back and it needs saying out loud.
--
-- Verified against these implementations on this machine:
--   EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua  (secret discipline)
--   EllesmereUIActionBars/EllesmereUIActionBars.lua        (category enumeration)
---------------------------------------------------------------------------
local _, ns = ...

local CDM = {}
ns.CDM = CDM

---------------------------------------------------------------------------
-- The four viewers
--
-- Global frames, created by Blizzard's own Cooldown Manager. Each holds a
-- frame pool of item frames - one per cooldown or buff it currently shows.
---------------------------------------------------------------------------
CDM.VIEWERS = {
    { key = "essential", global = "EssentialCooldownViewer", label = "Cooldowns", kind = "icon" },
    { key = "utility",   global = "UtilityCooldownViewer",   label = "Utility",   kind = "icon" },
    { key = "buffIcon",  global = "BuffIconCooldownViewer",  label = "Buffs",     kind = "icon" },
    { key = "buffBar",   global = "BuffBarCooldownViewer",   label = "Buff bars", kind = "bar"  },
}

-- The fifth group, which is not a viewer: everything the Cooldown Manager
-- knows and is not showing anywhere. Named here and read by the picker, so
-- the two cannot disagree about what the string is.
--
-- Deliberately NOT in VIEWERS: there is no frame pool behind it, and every
-- loop over VIEWERS would then be asking Blizzard for a global that does not
-- exist. ViewerRank falls through to #VIEWERS for it, which is exactly the
-- band we want - after all four.
CDM.HIDDEN_KEY = "hidden"
local HIDDEN_KEY = CDM.HIDDEN_KEY

function CDM:GetViewer(key)
    for _, viewer in ipairs(self.VIEWERS) do
        if viewer.key == key then return _G[viewer.global], viewer end
    end
    return nil
end

-- The Cooldown Manager shipped well before the aura restrictions, so unlike
-- the aura engine this is expected to be present. It can still be missing on
-- an older client, so callers check.
function CDM:IsAvailable()
    -- ONLY A POSITIVE ANSWER IS CACHED.
    --
    -- A negative one is a statement about this moment, and the usual reason
    -- for it is the one the message below names: Blizzard's Cooldown Manager
    -- has not been switched on yet, so its frames do not exist. Caching that
    -- meant doing exactly what the addon asked for changed nothing until a
    -- reload - the addon told the user to fix it and then refused to notice.
    if self.available then return true end

    self.unavailableReason = nil

    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        self.unavailableReason = "this client has no C_CooldownViewer API"
        return false
    end

    for _, viewer in ipairs(self.VIEWERS) do
        if _G[viewer.global] then
            self.available = true
            return true
        end
    end

    self.unavailableReason = "the Cooldown Manager frames do not exist yet - "
        .. "open Edit Mode once and enable the Cooldown Manager"
    return false
end

function CDM:UnavailableReason()
    self:IsAvailable()
    return self.unavailableReason
end

---------------------------------------------------------------------------
-- Live item frames
--
-- The frame pool is the ground truth for what is on screen. The static
-- category API returns where a cooldown *belongs*, but Blizzard can display
-- it in a different viewer - the user drags things between viewers in Edit
-- Mode, and per-spec layouts move them too. So anything about what is
-- actually shown must come from the pool.
---------------------------------------------------------------------------

-- Calls fn(itemFrame, viewerSpec) for every active item of one viewer.
function CDM:ForEachItem(key, fn)
    local frame, spec = self:GetViewer(key)
    local pool = frame and frame.itemFramePool
    if not (pool and pool.EnumerateActive) then return 0 end

    local count = 0
    for item in pool:EnumerateActive() do
        count = count + 1
        fn(item, spec)
    end
    return count
end

function CDM:ForEachItemEverywhere(fn)
    local total = 0
    for _, viewer in ipairs(self.VIEWERS) do
        total = total + self:ForEachItem(viewer.key, fn)
    end
    return total
end

-- An item frame carries its cooldownID directly, or on the info table it was
-- populated from; both spellings exist across builds.
function CDM:ItemCooldownID(item)
    if not item then return nil end
    return item.cooldownID or (item.cooldownInfo and item.cooldownInfo.cooldownID)
end

function CDM:GetInfo(cooldownID)
    if not cooldownID then return nil end
    local fn = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not fn then return nil end
    local ok, info = pcall(fn, cooldownID)
    if ok then return info end
    return nil
end

---------------------------------------------------------------------------
-- Which spell an item frame stands for
--
-- This used to be one line - `info.overrideSpellID or info.spellID` - and
-- that line is behind a whole class of "it tracks the wrong thing" reports.
-- Three separate faults, each one visible in the reference's own workarounds
-- (EllesmereUICdmSpellPicker.lua:40-231):
--
--   1. THE OVERRIDE GOES STALE. Blizzard keeps reporting an overrideSpellID
--      after the talent that provided it is gone, so the cell shows a spell
--      the player no longer has - wrong name, wrong icon. The reference
--      takes the override only when IsPlayerSpell agrees the player has it.
--
--   2. THE FRAME KNOWS BETTER THAN THE INFO TABLE. Under a transform
--      (Glacial Spike out of Frostbolt) frame:GetSpellID() returns the form
--      that exists in the world; the static cooldownInfo does not.
--
--   3. AN ACTIVE AURA HANDS BACK A SECRET. While the buff is up,
--      GetSpellID/GetAuraSpellID return secret values, so resolution falls
--      through to the generic spec-aura entry - which is why an icon can
--      change into something unrecognisable for exactly as long as the buff
--      lasts. The answer is to remember the last CLEAN read per cooldownID
--      and reuse it. It self-heals: any later clean read overwrites it, so a
--      re-talented cooldown re-resolves on the next pass.
--
-- Secret discipline throughout: issecretvalue is asked BEFORE any comparison,
-- because `id > 0` on a secret is itself the taint.
---------------------------------------------------------------------------

-- A spell ID we are allowed to do Lua on. ns.CanCompute covers the secret
-- test; the rest rejects the shapes that are not an ID.
local function Usable(id)
    if type(id) ~= "number" or not ns.CanCompute(id) then return false end
    return id > 0 and id == math.floor(id)
end
CDM.UsableSpellID = Usable

local function CallOn(item, method)
    local fn = item and item[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, item)
    if ok and Usable(value) then return value end
    return nil
end

-- Does the player have this spell right now? true, false, or nil for "the
-- client will not say". IsPlayerSpell is what the reference asks, but it is
-- deprecated on this build; C_SpellBook.IsSpellKnown is the current spelling
-- and is what the installed addons use. Nil rather than a guess, so the one
-- caller can decide what an unanswerable question means.
local function PlayerHas(spellID)
    if not Usable(spellID) then return nil end
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then return nil end
    local ok, has = pcall(known, spellID)
    if not ok then return nil end
    return has and true or false
end

-- The last clean GetSpellID seen for a cooldownID, so an active (secret)
-- read still resolves to the live talent form. Keyed by cooldownID, which is
-- a plain number and stays readable while the aura's own fields do not.
local cleanSpellByCooldown = {}

function CDM:BaseSpell(spellID)
    if not (Usable(spellID) and C_Spell and C_Spell.GetBaseSpell) then return nil end
    local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
    if ok and Usable(base) and base ~= spellID then return base end
    return nil
end

function CDM:OverrideSpell(spellID)
    if not (Usable(spellID) and C_Spell and C_Spell.GetOverrideSpell) then return nil end
    local ok, override = pcall(C_Spell.GetOverrideSpell, spellID)
    if ok and Usable(override) and override ~= spellID then return override end
    return nil
end

-- Every ID that means the same spell as this one: itself, what it was before
-- a talent replaced it, what it becomes, and the replacement of its base.
-- A stored spell must find its live frame across all four, or picking
-- "Frostbolt" stops tracking the moment it turns into Glacial Spike.
function CDM:VariantFamily(spellID)
    local family = {}
    if not Usable(spellID) then return family end

    local function Add(id)
        if not Usable(id) then return end
        for _, existing in ipairs(family) do
            if existing == id then return end
        end
        family[#family + 1] = id
    end

    Add(spellID)
    Add(self:OverrideSpell(spellID))
    local base = self:BaseSpell(spellID)
    if base then
        Add(base)
        Add(self:OverrideSpell(base))
    end
    return family
end

-- True when two IDs name the same spell in any of its forms.
function CDM:SameSpell(a, b)
    if not (Usable(a) and Usable(b)) then return false end
    if a == b then return true end
    for _, id in ipairs(self:VariantFamily(a)) do
        if id == b then return true end
    end
    for _, id in ipairs(self:VariantFamily(b)) do
        if id == a then return true end
    end
    return false
end

function CDM:ItemSpellID(item)
    if not item then return nil end
    local cooldownID = self:ItemCooldownID(item)

    -- 1. The frame's own answer, and it is the authoritative one.
    local live = CallOn(item, "GetSpellID") or CallOn(item, "GetAuraSpellID")
    if live then
        if type(cooldownID) == "number" then cleanSpellByCooldown[cooldownID] = live end
        return live
    end

    -- 2. The aura is up and the frame answered with a secret. Reuse the last
    --    clean read rather than degrading to the generic entry below.
    if type(cooldownID) == "number" and cleanSpellByCooldown[cooldownID] then
        return cleanSpellByCooldown[cooldownID]
    end

    -- 3. The static info, override first but only if the player has it.
    local info = self:GetInfo(cooldownID)
    if not info then return nil end
    return self:InfoSpellID(info)
end

-- The same choice made against a plain info table, for the paths that have
-- no frame (the static catalogue). Kept in one place so the picker and the
-- screen can never disagree about what a cooldown is called.
function CDM:InfoSpellID(info)
    if type(info) ~= "table" then return nil end

    local override = info.overrideSpellID
    if Usable(override) then
        -- The stale-override guard. When the client cannot answer, keep the
        -- override: it is still the better guess, and this is exactly the
        -- behaviour we had before the guard existed.
        if PlayerHas(override) ~= false then return override end
    end

    if Usable(info.spellID) then return info.spellID end

    if type(info.linkedSpellIDs) == "table" then
        for _, linked in ipairs(info.linkedSpellIDs) do
            if Usable(linked) then return linked end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- The full catalogue of what the Cooldown Manager knows
--
-- Two sources, on purpose:
--   the live pools  - what is displayed right now, including anything the
--                     user moved between viewers
--   the category API - the static set, which also contains entries Blizzard
--                     only pools situationally (a spell hidden until it is
--                     relevant would otherwise never be listed)
---------------------------------------------------------------------------

-- Which of our four viewers a static category belongs to. The member names
-- are read off working code on this machine (EllesmereUICdmSpellPicker.lua
-- uses Essential, Utility, TrackedBuff and TrackedBar by name), never guessed,
-- and every lookup is nil-safe so a renamed member costs one group heading
-- rather than the whole list.
function CDM:CategoryViewer(category)
    local categories = Enum and Enum.CooldownViewerCategory
    if not categories then return nil end

    if category == categories.Essential then return "essential" end
    if category == categories.Utility then return "utility" end
    if category == categories.TrackedBuff then return "buffIcon" end
    if category == categories.TrackedBar then return "buffBar" end
    return nil
end

-- A viewer's position in the list, which is the order the Cooldown Manager
-- itself puts them in. Each rank owns a band of ten thousand in the sort key,
-- so Cooldowns can never interleave with Utility.
function CDM:ViewerRank(key)
    for index, viewer in ipairs(self.VIEWERS) do
        if viewer.key == key then return index - 1 end
    end
    return #self.VIEWERS
end

---------------------------------------------------------------------------
-- Everything the Cooldown Manager knows, on screen or not
--
-- Two sources, and NEITHER of them is the better one. They answer different
-- questions, and the reference says so in as many words: "Either source alone
-- misses spells. The union catches everything."
--
-- GetCooldownViewerCategorySet returns where a cooldown BELONGS. It is the
-- complete list and it is the only one that knows about a spell Blizzard pools
-- only when it becomes relevant. What it does not know is what the user did in
-- Blizzard's own Cooldown Manager settings: a spell dragged to "Not Displayed"
-- is still in the set, so on its own it offered spells the user had
-- deliberately removed, in an order they had deliberately changed.
--
-- CooldownViewerSettings' data provider answers the arrangement question -
-- GetOrderedCooldownIDs is the user's own order, and anything hidden reports
-- a category we do not map, so it drops out by itself. The reference reaches
-- for it for exactly this reason (EllesmereUICdmSpellPicker.lua:437-501),
-- every step pcall-guarded, because the provider only exists once Blizzard's
-- settings frame has been built.
--
-- So: the arranged source decides ORDER and what the user hid, the static set
-- decides COMPLETENESS. Taking only the first cost us the situational spells
-- on every class; taking only the second cost us the arrangement.
---------------------------------------------------------------------------
local function SettingsProvider()
    local settings = CooldownViewerSettings
    if not (settings and type(settings.GetDataProvider) == "function") then return nil end

    local ok, provider = pcall(settings.GetDataProvider, settings)
    if not (ok and type(provider) == "table") then return nil end
    if type(provider.GetOrderedCooldownIDs) ~= "function"
        or type(provider.GetCooldownInfoForID) ~= "function" then
        return nil
    end
    return provider
end

-- Calls fn(cooldownID, viewerKey, order) for every catalogued cooldown, and
-- returns how many each source contributed - the numbers /zs cdm prints.
--
-- BOTH SOURCES RUN. The arranged one used to return here and the static sets
-- were never reached, which made the second half of this file's own header a
-- description of something that did not happen. What it costs is every spell
-- Blizzard only pools when it becomes relevant: Beacon of Light is Essential
-- for a Holy Paladin permanently and still has no frame most of the time, so
-- it was absent from our picker with nothing to explain why. Every class has
-- spells of that shape, which is why the list looked short on all of them.
--
-- The arrangement is still honoured, and that is the whole reason this is a
-- skip list rather than a plain union. A cooldown the user dragged to "Not
-- Displayed" IS mentioned by the arranged source, under a category we do not
-- map - so it is recorded as spoken for and the static pass leaves it alone.
-- Only cooldowns the arranged source never mentioned at all get added. Both
-- earlier complaints stay fixed: nothing the user removed comes back, and
-- nothing the Cooldown Manager knows goes missing.
function CDM:ForEachCatalogued(fn)
    local counters = {}
    local function Order(viewerKey)
        local rank = self:ViewerRank(viewerKey)
        counters[rank] = (counters[rank] or 0) + 1
        return rank * 10000 + counters[rank]
    end

    -- Keyed by cooldownID, which is a plain number on every path - the
    -- secret values live in the aura fields, never in this handle.
    local spokenFor = {}
    local arranged, hidden, extra = 0, 0, 0

    local provider = SettingsProvider()
    if provider then
        local ok, ordered = pcall(provider.GetOrderedCooldownIDs, provider)
        if ok and type(ordered) == "table" then
            for _, cooldownID in ipairs(ordered) do
                local okInfo, entry = pcall(provider.GetCooldownInfoForID, provider, cooldownID)
                local category = okInfo and type(entry) == "table" and entry.category or nil
                local viewerKey = category ~= nil and self:CategoryViewer(category) or nil
                spokenFor[cooldownID] = true
                if viewerKey then
                    arranged = arranged + 1
                    fn(cooldownID, viewerKey, Order(viewerKey))
                else
                    -- NOT DISPLAYED, AND STILL OFFERED. These used to be
                    -- dropped, on the reading that a category we do not map
                    -- means the user chose not to see it. On a real character
                    -- that is 65 spells out of 74: Blizzard's own default
                    -- leaves nearly everything in Hidden, and the handful you
                    -- arranged are the exception. Dropping them left a picker
                    -- with nine entries next to a Cooldown Manager settings
                    -- panel showing every one.
                    --
                    -- They go in a group of their OWN, ranked after all four
                    -- viewers, so the arranged spells keep the order you gave
                    -- them at the top and these sit underneath, labelled. The
                    -- old complaint was that they were mixed in; being mixed
                    -- in was the fault, not being present.
                    hidden = hidden + 1
                    fn(cooldownID, HIDDEN_KEY, Order(HIDDEN_KEY))
                end
            end
        end
    end

    -- The static sets, for everything the arranged pass never spoke for.
    -- Iterated through VIEWERS rather than pairs(Enum), because pairs has no
    -- order at all and the groups came out shuffled differently on every
    -- rebuild. These land after the arranged entries inside their own viewer
    -- band, because Order shares its counters across both passes: Blizzard's
    -- own arrangement first, then the ones it had no position for.
    local categories = Enum and Enum.CooldownViewerCategory
    local getSet = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    if not (categories and getSet) then
        return arranged, extra, hidden
    end

    for _, viewer in ipairs(self.VIEWERS) do
        for _, category in pairs(categories) do
            if self:CategoryViewer(category) == viewer.key then
                -- true: include what is not talented.
                local ok, set = pcall(getSet, category, true)
                if ok and type(set) == "table" then
                    for _, cooldownID in ipairs(set) do
                        -- A cooldown can sit in two category sets, so the
                        -- mark is written here too, not only above.
                        if not spokenFor[cooldownID] then
                            spokenFor[cooldownID] = true
                            extra = extra + 1
                            fn(cooldownID, viewer.key, Order(viewer.key))
                        end
                    end
                end
            end
        end
    end
    return arranged, extra, hidden
end

function CDM:Catalogue()
    -- Keyed by SPELL, not by cooldown. Several cooldownIDs can point at one
    -- spell - the live frame and the static entry both do - and a picker that
    -- lists the same spell three times is noise: the user picks a spell, and
    -- that is what a cell stores.
    local bySpell = {}

    -- `order` is BLIZZARD'S OWN position for this spell on screen, and it is
    -- absolute across all four viewers, not an index inside one category.
    --
    -- It has to be absolute. The old version numbered each category from 1,
    -- so the first Cooldown and the first Utility both scored 1 and the sort
    -- fell through to the name - which interleaved the groups alphabetically
    -- and is exactly the "list makes no sense" that was reported. Each viewer
    -- now owns a band of ten thousand (see ViewerRank), so groups stay whole
    -- and the position inside a group is Blizzard's own.
    local function Add(cooldownID, viewerKey, live, order)
        if not cooldownID then return end
        local info = self:GetInfo(cooldownID)
        if not info then return end

        local spellID = self:InfoSpellID(info)
        if not spellID then return end

        local existing = bySpell[spellID]
        if existing then
            -- The live pool wins: it knows which viewer actually shows it,
            -- which is what the user sees on screen.
            if viewerKey and not existing.viewer then
                existing.viewer = viewerKey
                existing.cooldownID = cooldownID
            end
            -- First writer wins, and the live pass goes first: a frame's own
            -- layoutIndex beats anything the static list claims.
            if order and not existing.order then existing.order = order end
            if live then existing.known = true end
            return
        end

        bySpell[spellID] = {
            cooldownID = cooldownID,
            spellID    = spellID,
            viewer     = viewerKey,
            order      = order,
            name       = ns.SpellName(spellID) or ("Spell " .. spellID),
            icon       = ns.SpellTexture(spellID),
            -- A frame in a live pool is on screen, so it is talented by
            -- definition; anything else has to be asked about.
            known      = live or ns.IsSpellKnown(spellID),
        }
    end

    -- Pass one: what is on screen right now, in the order it is on screen.
    -- layoutIndex is the frame's own position inside its viewer - the number
    -- Blizzard lays the row out by - so this is the arrangement the user is
    -- looking at while they read our picker.
    for _, viewer in ipairs(self.VIEWERS) do
        local base = self:ViewerRank(viewer.key) * 10000
        self:ForEachItem(viewer.key, function(item)
            local index = item.layoutIndex
            if type(index) ~= "number" then index = 0 end
            Add(self:ItemCooldownID(item), viewer.key, true, base + index)
        end)
    end

    -- Pass two: everything else the Cooldown Manager knows but is not showing
    -- right now - untalented spells, and the ones Blizzard only pools when
    -- they become relevant. They are listed and greyed, so a bar can be built
    -- for a build you are about to switch into.
    self:ForEachCatalogued(function(cooldownID, viewerKey, order)
        Add(cooldownID, viewerKey, false, order)
    end)

    local out = {}
    for _, entry in pairs(bySpell) do out[#out + 1] = entry end

    -- BLIZZARD'S ORDER, then name for anything it has no opinion about.
    --
    -- pairs() has no order at all, so something has to decide - and "what the
    -- Cooldown Manager shows, in the order it shows it" is the only answer
    -- that makes the picker match the thing it is picking from. The spell ID
    -- is the last tiebreak, or two same-named spells would swap places every
    -- time the list is rebuilt.
    -- math.huge, NOT a big-looking number: the order is banded by viewer now
    -- (rank * 10000), so a sentinel like 9999 sits INSIDE the first viewer's
    -- band and would file the unordered leftovers in the middle of Cooldowns.
    table.sort(out, function(a, b)
        local aOrder, bOrder = a.order or math.huge, b.order or math.huge
        if aOrder ~= bOrder then return aOrder < bOrder end
        if a.name == b.name then return a.spellID < b.spellID end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Diagnosis
--
-- Run before building anything on top: it answers whether the Cooldown
-- Manager is actually reachable on this client, and what it currently holds.
---------------------------------------------------------------------------
function CDM:Dump()
    ns.Print("|cffffd100----------------------------------------|r")

    if not self:IsAvailable() then
        ns.Print("|cffff4040Cooldown Manager unavailable|r - " ..
            (self:UnavailableReason() or "reason unknown"))
        return
    end

    ns.Print("|cff40ff40Cooldown Manager reachable.|r Live item frames:")

    local grand = 0
    for _, viewer in ipairs(self.VIEWERS) do
        local frame = _G[viewer.global]
        local lines = {}

        local count = self:ForEachItem(viewer.key, function(item)
            local spellID = self:ItemSpellID(item)
            lines[#lines + 1] = string.format("      %s |cff888888%s|r%s",
                spellID and (ns.SpellName(spellID) or "?") or "|cffff4040unresolved|r",
                tostring(spellID or "-"),
                item:IsShown() and "" or " |cff888888(hidden)|r")
        end)
        grand = grand + count

        ns.Print(string.format("   %s |cffffd100%s|r: %s",
            frame and "|cff40ff40o|r" or "|cffff4040x|r",
            viewer.label,
            frame and (count .. " items") or "frame does not exist"))
        for _, line in ipairs(lines) do ns.Print(line) end
    end

    -- WHERE EVERY ENTRY CAME FROM, because "the list is missing things" has no
    -- answer without it. Three numbers, three different meanings, and the one
    -- that matters is the middle one: spells the Cooldown Manager knows about
    -- and had no arranged position for, which is where the situational ones
    -- live. It read zero for a whole release because the static pass was
    -- unreachable.
    local arranged, extra, hidden = self:ForEachCatalogued(function() end)
    ns.Print(string.format("Sources: |cffffd100%d|r arranged, |cffffd100%d|r " ..
        "only in the category set, |cffffd100%d|r not displayed by Blizzard.",
        arranged, extra, hidden))
    if hidden > 0 then
        ns.Print("   |cff888888That last group is listed too, under Cooldowns|r")
        ns.Print("   |cff888888with the rest - no frame yet, so each one can be|r")
        ns.Print("   |cff888888picked but not tracked. The entry says so.|r")
    end
    if arranged == 0 then
        ns.Print("   |cff888888No arrangement read - Blizzard's Cooldown Manager|r")
        ns.Print("   |cff888888settings have not been opened this session.|r")
    end

    local catalogue = self:Catalogue()
    ns.Print(string.format("Catalogue: |cffffd100%d|r entries, %d live frames.",
        #catalogue, grand))
    if grand == 0 then
        ns.Print("|cffff8040No live frames.|r Open Edit Mode and make sure the")
        ns.Print("Cooldown Manager is enabled, then try again.")
    end
end

---------------------------------------------------------------------------
-- Which live item frame stands for which spell
--
-- It lived in the renderer while the bars were the only thing that asked,
-- and moved here when the reminders started asking the same question - "is
-- the frame for Bone Shield active" is this lookup followed by ItemIsActive.
-- A second walk building a second table is two answers to one question that
-- drift apart on the first talent change. One index, one owner, every reader.
--
-- Rebuilt when the pools churn and on the first read, never on a timer - see
-- ItemForSpell for why both of those are needed and neither is enough alone.
---------------------------------------------------------------------------
local itemBySpell = {}

function CDM:RebuildItemIndex()
    wipe(itemBySpell)
    self.indexBuilt = true

    -- INDEXED UNDER EVERY FORM OF THE SPELL, not just the one the frame is
    -- reporting this second. A talent that replaces a spell changes the ID
    -- the frame resolves to, and a cell that stored the old ID would simply
    -- stop finding it - the spell is right there on screen and the bar goes
    -- blank. Frostbolt becoming Glacial Spike is the everyday case.
    --
    -- The exact ID always wins; the other forms only fill gaps. Two spells of
    -- one family can be on screen at once (a base and its override both
    -- tracked), and without that rule whichever came out of the pool first
    -- would answer for both.
    local exact = {}

    for _, viewer in ipairs(self.VIEWERS) do
        self:ForEachItem(viewer.key, function(item)
            local spellID = self:ItemSpellID(item)
            if not spellID then return end

            if not exact[spellID] then
                exact[spellID] = true
                itemBySpell[spellID] = item
            end
            for _, variant in ipairs(self:VariantFamily(spellID)) do
                if not itemBySpell[variant] then itemBySpell[variant] = item end
            end
        end)
    end
end

-- The live frame for a spell, or nil.
--
-- THE INDEX KEEPS ITSELF NOW, and that is not a tidy-up: it used to be
-- rebuilt once per render pass by the bars, and when they went, its only
-- writer went with them. Nothing threw. The table simply stayed empty for the
-- whole session, so every reminder fell into "Blizzard is not showing this
-- spell" - a surviving feature that silently never fires, blaming Blizzard's
-- settings for a hole of ours. An audit found it; no test could have, because
-- an empty index and a spell that really is untracked are the same answer.
--
-- Two ways it stays current, and both are needed:
--   * NotifyChanged rebuilds it before the listeners run, so the pool churn
--     that already fires on a talent change or a viewer edit carries it.
--   * The first read builds it, for the case where nothing has churned yet -
--     a reminder asking before the Cooldown Manager has drawn anything.
-- `fresh` stays as the escape hatch for a caller that must not be one frame
-- behind.
function CDM:ItemForSpell(spellID, fresh)
    if not spellID then return nil end
    if fresh or not self.indexBuilt then self:RebuildItemIndex() end
    return itemBySpell[spellID]
end

-- Is this buff actually up?
--
-- IsActive, not IsShown. Read off EllesmereUICdmBuffBars.lua:4725 with the
-- reasoning kept, because it is not obvious: a buff-bar item stays SHOWN
-- while inactive unless the user switched on Blizzard's own "Hide when
-- inactive", which is off by default - so IsShown would say yes all evening.
--
-- Returns nil when it cannot be answered, which is not the same as false.
function CDM:ItemIsActive(item)
    if not item then return nil end

    -- THE pcall GUARDS THE CALL, NOT THE ANSWER, and that was the hole. Both
    -- of these read a value off a frame Blizzard owns and then boolean-test it
    -- one line later, outside the pcall - and on this patch a boolean test is
    -- exactly what a secret value raises on. It would have thrown a real error
    -- out of a function whose whole promise is that it never does.
    --
    -- ns.CanCompute turns that into the third answer this function already
    -- documents: nil, "cannot be answered", which every caller handles.
    if item.IsActive then
        local ok, active = pcall(item.IsActive, item)
        if ok and ns.CanCompute(active) then return active and true or false end
    end
    if item.IsShown then
        local ok, shown = pcall(item.IsShown, item)
        if ok and ns.CanCompute(shown) then return shown and true or false end
    end
    return nil
end
---------------------------------------------------------------------------
-- Change notification
--
-- The pools churn: talents, spec changes, entering combat, and Blizzard's
-- own situational show/hide all add and remove item frames. Anything built
-- on top has to rebuild when that happens, so it is centralised here rather
-- than every consumer registering its own events.
---------------------------------------------------------------------------
local listeners = {}

function CDM:OnChanged(fn)
    listeners[#listeners + 1] = fn
end

function CDM:NotifyChanged()
    -- BEFORE the listeners, not after: what changed is which item frames
    -- exist, and every listener's first question is which frame belongs to a
    -- spell. Answering that out of last minute's index is the same bug as
    -- having no index at all, one frame later.
    self:RebuildItemIndex()

    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local watcher = CreateFrame("Frame")

-- Registering an event name the client does not know is a hard error, and
-- the cooldown-viewer events are newer than the rest, so each one is tried
-- on its own. A missing event costs one less rebuild trigger, not a broken
-- addon.
for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
}) do
    pcall(watcher.RegisterEvent, watcher, event)
end

watcher:SetScript("OnEvent", function()
    -- Coalesced: several of these fire together on a spec change, and a
    -- rebuild per event would mean four full relayouts for one action.
    if CDM.pending then return end
    CDM.pending = true
    C_Timer.After(0.2, function()
        CDM.pending = false
        CDM:NotifyChanged()
    end)
end)

-- Newly pooled frames appear without any event: Blizzard acquires them from
-- the pool directly. Hooking Acquire is how the reference catches them.
function CDM:HookPools()
    if self.poolsHooked then return end
    self.poolsHooked = true

    for _, viewer in ipairs(self.VIEWERS) do
        local frame = _G[viewer.global]
        local pool = frame and frame.itemFramePool
        if pool and pool.Acquire then
            hooksecurefunc(pool, "Acquire", function()
                if CDM.pending then return end
                CDM.pending = true
                C_Timer.After(0.05, function()
                    CDM.pending = false
                    CDM:NotifyChanged()
                end)
            end)
        end
    end
end
