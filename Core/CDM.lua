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
-- game where secret values are not a problem. Every addon that "does
-- cooldowns" on this patch works the same way: it does not parse anything,
-- it takes Blizzard's item frames, restyles them and lays them out.
--
-- EllesmereUI states it in one line at the top of its own CDM file:
--   "Mirrors Blizzard CDM bars with custom styling... Does NOT parse secret
--    values, works around restricted APIs."
--
-- This file is that layer: find the viewers, enumerate their live item
-- frames, resolve what each one is, and hold on to them while Blizzard keeps
-- trying to re-anchor them.
--
-- Verified against these implementations on this machine:
--   EllesmereUICooldownManager/EllesmereUICdmHooks.lua
--   EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua
--   EllesmereUIActionBars/EllesmereUIActionBars.lua  (category enumeration)
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

-- An adopted icon stays Blizzard's child, so a viewer that is switched off in
-- Blizzard's Edit Mode takes our icons down with it - the frames exist, they
-- are pooled, they are pinned to the right cell, and nothing is on screen.
-- Worth its own answer, because "my bar is empty" and "the Cooldown Manager
-- is missing" look identical from the outside and are not the same problem.
function CDM:HiddenViewers()
    local hidden

    for _, viewer in ipairs(self.VIEWERS) do
        local frame = _G[viewer.global]
        if frame and not frame:IsShown() then
            hidden = hidden and (hidden .. ", " .. viewer.label) or viewer.label
        end
    end

    return hidden
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
-- The pandemic window - asked, not calculated
--
-- The refresh window is the last ~30% of an aura's duration, where recasting
-- wastes nothing. The obvious way to find it is to divide the remaining time
-- by the full duration, and on this patch that is exactly what an addon may
-- not do: both numbers can be secret, and dividing one secret by another is
-- the taint everything else here is built to avoid.
--
-- BLIZZARD ALREADY KNOWS. Its Cooldown Manager shows a pandemic marker of its
-- own, through two methods on the item frame - ShowPandemicStateFrame and
-- HidePandemicStateFrame. Hooking those turns the question from arithmetic
-- into a fact somebody else worked out, inside the game, where the numbers
-- are readable. The reference does exactly this
-- (EllesmereUICdmBuffBars.lua:81-128) and calculates nothing.
--
-- IT DEPENDS ON A BLIZZARD SETTING. The methods only fire for auras the user
-- has switched pandemic alerts on for, in Blizzard's own Cooldown Manager
-- options. Nothing here can turn that on for them, so the panel says so.
---------------------------------------------------------------------------

-- frame -> true while it is inside its refresh window.
local pandemic = setmetatable({}, { __mode = "k" })
local pandemicHooked = setmetatable({}, { __mode = "k" })

-- AT FILE SCOPE, DELIBERATELY. A hooksecurefunc callback is billed to the
-- addon whose execution context created the closure, so a body made inside
-- another addon's call path bills THEM for every one of our repaints. The
-- reference found this by bisection and says so at its own hook site; a
-- closure built per frame inside a render pass would repeat the mistake.
local function OnPandemicShow(frame)
    pandemic[frame] = true
end

local function OnPandemicHide(frame)
    pandemic[frame] = nil
end

-- Idempotent, and safe to call every render pass: a frame is hooked once.
function CDM:HookPandemic(item)
    if not item or pandemicHooked[item] then return end
    if type(item.ShowPandemicStateFrame) ~= "function" then return end

    pandemicHooked[item] = true
    hooksecurefunc(item, "ShowPandemicStateFrame", OnPandemicShow)
    if type(item.HidePandemicStateFrame) == "function" then
        hooksecurefunc(item, "HidePandemicStateFrame", OnPandemicHide)
    end
end

function CDM:InPandemic(item)
    return item ~= nil and pandemic[item] == true
end

-- Whether this client has the methods at all. Asked once for the panel, so
-- "my pandemic glow does nothing" has an answer that is not a shrug.
function CDM:PandemicSupported()
    local found = false
    self:ForEachItemEverywhere(function(item)
        if type(item.ShowPandemicStateFrame) == "function" then found = true end
    end)
    return found
end

---------------------------------------------------------------------------
-- How many stacks an item frame is showing
--
-- READ BUT NEVER INSPECTED. On 12.0 this number can be a secret value, and
-- on 12.1 it is one inside restricted content. So it is fetched, stored and
-- handed to widget setters - `StatusBar:SetValue` and `FontString:SetText`
-- both take secret arguments natively - and nothing here ever compares it,
-- adds to it or tests it for truth. The comparison against a threshold
-- happens inside the C layer; see the overlays in Core/Screen.lua.
--
-- Two sources, in the reference's order (EllesmereUICdmBuffBars.lua:3259):
-- the frame's own cached aura table first, because it reads without erroring
-- on every client, and the aura-instance query only as a fallback for a frame
-- whose cache is not populated - that call HARD ERRORS on restricted units,
-- so it is guarded twice over.
---------------------------------------------------------------------------
function CDM:ItemStacks(item)
    if not item then return nil end

    local cached = item.auraDataCached
    if cached and cached.applications ~= nil then return cached.applications end

    local instanceID = item.auraInstanceID
    local unit = item.auraDataUnit
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    -- ns.CanCompute rather than a bare issecretvalue: a secret instance ID
    -- may not be passed to the query, and nil must not reach it either.
    if get and unit and ns.CanCompute(instanceID) then
        local ok, data = pcall(get, unit, instanceID)
        if ok and data and data.applications ~= nil then return data.applications end
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
-- Adoption
--
-- Blizzard re-anchors its item frames on every layout pass of its own, so a
-- position set once does not survive. The fix the reference uses is to hook
-- SetPoint on the frame and re-assert our own anchor from inside the hook -
-- self-healing, and it needs no polling.
--
-- Guarded against recursion: our own SetPoint call re-enters the hook.
---------------------------------------------------------------------------
-- Weak keys, and every field lives HERE rather than on the frame: writing a
-- custom key onto a Blizzard frame table is one of the named ways to taint it.
local adopted = setmetatable({}, { __mode = "k" })

-- How much bigger this frame draws than the cell it sits on.
--
-- Blizzard scales its item frames - the Cooldown Manager's own size slider in
-- Edit Mode does exactly that - and a frame's WIDTH is measured in its own
-- coordinate space. A frame at scale 1.2 reports 36 and draws 43. That is
-- why every icon measured correct while three of them were visibly the wrong
-- size and shoved into each other: the report was reading the number that
-- does not decide anything.
--
-- SetScale on a Blizzard frame is off the table, so the size is compensated
-- instead. Anchoring needs no correction - a point resolves in screen space.
local function ScaleRatio(frame, anchorFrame)
    if not (anchorFrame and anchorFrame.GetEffectiveScale) then return 1 end

    local mine = frame:GetEffectiveScale()
    local theirs = anchorFrame:GetEffectiveScale()
    if not (mine and theirs) or mine <= 0 then return 1 end

    return theirs / mine
end

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

-- Installs the self-healing hooks once per frame and returns its record.
--
-- Three hooks, because Blizzard's layout pass rewrites all three. The guard
-- flag matters: our own SetPoint, SetSize and SetAlpha re-enter these.
local function Hold(item)
    local state = adopted[item]
    if state then return state end

    state = {}
    adopted[item] = state

    hooksecurefunc(item, "SetPoint", function(frame)
        local pin = adopted[frame]
        if pin and pin.anchor then Reassert(pin, frame) end
    end)
    hooksecurefunc(item, "SetSize", function(frame)
        local pin = adopted[frame]
        if pin and pin.width then Reassert(pin, frame) end
    end)
    hooksecurefunc(item, "SetAlpha", function(frame)
        local pin = adopted[frame]
        if pin and pin.alpha then Reassert(pin, frame) end
    end)

    -- Scale, because the size we set is compensated FOR the scale. Blizzard's
    -- Cooldown Manager has its own size slider in Edit Mode, and one drag on
    -- it would otherwise put every icon back out of line with no event to
    -- tell us. We never CALL SetScale on their frame - we only react to it.
    hooksecurefunc(item, "SetScale", function(frame)
        local pin = adopted[frame]
        if pin and pin.width then Reassert(pin, frame) end
    end)

    return state
end

-- Pins an item frame to a point and a size of ours, and keeps it there.
--   anchor = { point, relativeTo, relativePoint, x, y }
function CDM:Pin(item, anchor, width, height)
    if not item then return end
    local state = Hold(item)
    state.anchor = anchor
    state.width, state.height = width, height
    Reassert(state, item)
end

-- How visible an item is, and it STAYS that way.
--
-- This is how a cooldown the user did not place disappears: alpha 0, never
-- Hide(). Hiding a Blizzard frame taints it, and Blizzard also turns its own
-- frames back on whenever the viewer relayouts - hence the hook rather than a
-- single call.
function CDM:SetAlpha(item, alpha)
    if not item then return end
    local state = Hold(item)
    state.alpha = alpha
    Reassert(state, item)
end

---------------------------------------------------------------------------
-- Making four viewers' worth of icons look like one set
--
-- Blizzard's item frames are not one design. Each viewer decorates its own:
-- different masks (so different corners), a shared overlay texture that
-- lightens some and not others, a border here, a shadow there. Adopting them
-- unchanged puts five different icons in a row, which is what a Cooldown
-- Manager bar looks like before any addon touches it.
--
-- What has to go, and it is not guesswork - every name below was read off the
-- reference implementation on this machine
-- (EllesmereUICooldownManager/EllesmereUICdmHooks.lua, HideBlizzardDecorations):
--
--   Border, Shadow, IconShadow, DebuffBorder, CooldownFlash   alpha 0
--   SpellActivationAlert                                      alpha 0, hidden
--   every MaskTexture on the frame AND on its Cooldown        square mask
--   the IconOverlay atlas region                              alpha 0, hidden
--
-- Regions, not frames. Hiding a Blizzard FRAME is the thing that taints; its
-- textures are decoration, and the reference hides those too.
---------------------------------------------------------------------------
-- Reachable by file id as well as by atlas, so both are checked.
local OVERLAY_FILE = 6707800
local SQUARE_MASK  = "Interface\\Buttons\\WHITE8X8"

-- The named decorations, in one list.
--
-- Read once by the stripper and once by the restorer, because two copies of
-- this list would drift and the second one would silently stop putting
-- something back.
local DECORATIONS = {
    "Border", "Shadow", "IconShadow", "DebuffBorder", "CooldownFlash",
    "SpellActivationAlert",
}

-- Silenced regions, and it STAYS silenced - until we let go.
--
-- Alpha is not a one-time setting on these: the out-of-range veil is driven
-- by range, so Blizzard writes its alpha back whenever you move. A single
-- SetAlpha(0) is a decoration that returns the moment you walk anywhere. The
-- hook is the same self-healing trick the item frames use for their anchor.
--
-- WHAT EACH REGION LOOKED LIKE BEFORE IS RECORDED. The version before this
-- one kept nothing, and said so - "an alpha of zero is all we know, not what
-- it was before". That was not a limitation, it was an omission, and it had a
-- real cost: releasing a frame back to Blizzard left every decoration pinned
-- at zero for the rest of the session, the range veil included. Switch the
-- takeover off and Blizzard's own Cooldown Manager was left permanently
-- stripped by an addon that claimed to have let go.
--
-- Weak keys, and the record lives here rather than on the region: writing a
-- custom key onto a Blizzard object is one of the named ways to taint it.
local hushed = setmetatable({}, { __mode = "k" })
local hushing = false

local function Dim(region, alsoHide)
    if not region then return end

    local record = hushed[region]
    if not record then
        record = {
            alpha = (region.GetAlpha and region:GetAlpha()) or 1,
            shown = region.IsShown and region:IsShown() or false,
        }
        hushed[region] = record

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

-- Gives a decoration back at the alpha it had before we touched it. The hook
-- stays - a hook cannot be removed - but with `silent` off it does nothing,
-- so Blizzard is free to drive the region again.
local function Undim(region)
    local record = region and hushed[region]
    if not (record and record.silent) then return end

    record.silent = false
    pcall(region.SetAlpha, region, record.alpha)
    if record.shown then pcall(region.Show, region) end
end

-- Blizzard rounds its icons with a mask texture, and the corners cannot be
-- set any other way because they are not a border.
--
-- Measured with /zs skin: replacing the mask's own texture with a white
-- square does NOT work - the region still reported Blizzard's 130871 after
-- every attempt. The mask belongs to the TEXTURE it masks, so the thing to
-- do is take it off the texture rather than try to redefine it. The white
-- square is kept as a second attempt, because a mask that cannot be removed
-- can still sometimes be flattened.
-- Which masks were taken off which texture, so they can be put back. Weak
-- keys, same reason as everything else in this file.
local unmasked = setmetatable({}, { __mode = "k" })

local function Unmask(frame, masked)
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

-- Rounded corners back on a frame we no longer own.
local function Remask(masked)
    local taken = masked and unmasked[masked]
    if not taken then return end

    for region in pairs(taken) do
        if masked.AddMaskTexture then pcall(masked.AddMaskTexture, masked, region) end
    end
    unmasked[masked] = nil
end

-- Runs on EVERY skin pass, not once per frame.
--
-- Measured with /zs skin: after a one-time pass the mask was back to
-- Blizzard's rounded one (130871) and the corners with it. Blizzard rebuilds
-- these frames from a pool and re-decorates them, so a decoration removed
-- once is a decoration removed until the next time it is handed out. The work
-- is a handful of regions and only happens when something actually changed.
local function StripDecorations(item)
    for _, key in ipairs(DECORATIONS) do
        Dim(item[key], key == "SpellActivationAlert")
    end

    -- The masks on the item belong to its icon; the ones on the Cooldown
    -- belong to its swipe, which is not reachable from here - so that one
    -- still gets the flattening attempt only.
    Unmask(item, item.Icon)
    Unmask(item.Cooldown, nil)

    -- Everything the Cooldown Manager paints on top of its own icons, matched
    -- by atlas PREFIX rather than by a list of names.
    --
    -- The list came from a working addon on a different build, and this
    -- client had one it did not mention: UI-CooldownManager-OORshadow, a
    -- half-transparent "out of range" veil that was sitting at 0.5 on a
    -- self-cast spell that cannot be out of range. That was the reason some
    -- icons looked dimmer than others for no visible reason.
    for _, region in ipairs({ item:GetRegions() }) do
        if region ~= item.Icon and region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            local texture = region.GetTexture and region:GetTexture()

            local isChrome = texture == OVERLAY_FILE
                or (atlas ~= nil and (atlas:find("^UI%-HUD%-CoolDownManager")
                    or atlas:find("^UI%-CooldownManager")))

            if isChrome then Dim(region, true) end
        end
    end
end

-- THE FILL OF AN ADOPTED BUFF BAR.
--
-- Blizzard's TrackedBar template carries its own StatusBar, and nothing here
-- ever touched it - so a texture picked in our own panel could not reach the
-- one thing on screen that most obviously IS a bar. Reported by the owner as
-- "die texturen werden nicht übernommen", and entirely correct: what was on
-- screen was Blizzard's own gradient, and no setting in this addon could
-- change it.
--
-- FOUND RATHER THAN ASSUMED. The field name is tried first and the children
-- are walked for a StatusBar if it is not there, so a member Blizzard renames
-- in a patch costs the fill and never an error.
-- The stack or charge counter on an item, which is in one of two places.
--
-- "frame.ChargeCount and frame.Applications are siblings of the icon, and on
-- the frames whose Icon is a container the stack text lives at
-- Icon.Applications" (EllesmereUICdmHooks.lua:2225-2228). Looking in the first
-- place only meant the setting silently did nothing on the other kind of
-- frame - which from the outside is indistinguishable from the setting being
-- broken, and was reported as exactly that.
--
-- Indexing a plain texture with a field name is nil, not an error, so the
-- second lookup is safe on the frames whose Icon is just an icon.
local function Counter(item, key)
    if not item then return nil end
    return item[key] or (item.Icon and item.Icon[key]) or nil
end

-- Where each counter sat before we moved it, so releasing the frame puts it
-- back. Weak keys: these are Blizzard's frames, and a strong reference from
-- an addon is how a pooled frame never gets collected.
--
-- The same rule the stripped decorations already follow. Handing a frame back
-- with its stack count still parked in the corner WE chose is a mark left by
-- an addon that has just said it let go.
local counterAnchor = setmetatable({}, { __mode = "k" })

-- IS BLIZZARD SHOWING ITS OWN COUNTER?
--
-- This is the comparison an addon may not make, made by the game. A stack
-- count is a secret on this patch, so "is it more than one" cannot be asked
-- here at all - but Blizzard asks it inside the engine and answers by HIDING
-- the counter frame rather than by clearing the font string. So the frame's
-- own visibility IS the answer, and reading it touches no secret.
--
-- The reference gates on exactly this before it reads a counter:
-- `if blzChild.Applications and blzChild.Applications:IsShown()`
-- (EllesmereUICdmBuffBars.lua:3322), and the hide behaviour is stated at
-- EllesmereUICooldownManager.lua:5998 ("Blizzard manages show/hide based on
-- whether stacks exist").
--
-- nil means "there is no such counter to ask", which is not the same as false
-- and must not be treated as one - a cell with no Blizzard frame at all has
-- to fall back to its own judgement rather than being silenced.
function CDM:CounterShown(item, key)
    local widget = Counter(item, key)
    if not widget then return nil end
    local ok, shown = pcall(widget.IsShown, widget)
    if not ok then return nil end
    return shown and true or false
end

-- The font string inside one of Blizzard's counter frames, for the diagnostic
-- in Screen:DumpNumbers. Published rather than re-derived there: WHERE these
-- frames live is the thing Counter above exists to know, and a second finder
-- would look in one of the two places and quietly report "none".
function CDM:CounterText(item, key)
    local widget = Counter(item, key)
    if not widget then return nil end
    if widget.GetText then return widget end

    local regions = { widget:GetRegions() }
    for _, region in ipairs(regions) do
        if region.GetText then return region end
    end
    return nil
end

local function MoveCounter(widget, item, text)
    if not counterAnchor[widget] then
        local point, relativeTo, relativePoint, x, y = widget:GetPoint(1)
        -- Recorded even when there is no point to read: the entry is what
        -- says "we have touched this one", and without it a frame moved on a
        -- build that answers nil would be measured again next time and the
        -- original lost for good.
        counterAnchor[widget] = { point, relativeTo, relativePoint, x, y }
    end

    local x, y = ns.TextOffset(text)
    widget:ClearAllPoints()
    widget:SetPoint(text.anchor, item, text.anchor, x, y)
end

local function RestoreCounter(widget)
    local saved = counterAnchor[widget]
    if not saved then return end
    counterAnchor[widget] = nil

    widget:ClearAllPoints()
    if saved[1] then
        widget:SetPoint(saved[1], saved[2], saved[3], saved[4] or 0, saved[5] or 0)
    end
end

local function BarFill(item)
    if not item then return nil end

    local fill = item.Bar
    if fill and fill.SetStatusBarTexture then return fill end

    for _, child in ipairs({ item:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "StatusBar"
            and child.SetStatusBarTexture then
            return child
        end
    end
    return nil
end
CDM.BarFill = function(_, item) return BarFill(item) end

---------------------------------------------------------------------------
-- Which live item frame stands for which spell
--
-- It lived in Screen.lua while the screen was the only thing that asked. The
-- reminders ask the same question - "is the frame for Bone Shield active" is
-- this lookup followed by ItemIsActive - and a second walk building a second
-- table is two answers to one question that drift apart on the first talent
-- change. One index, one owner, both readers.
--
-- Rebuilt on demand rather than on a timer: the screen rebuilds it once per
-- render pass, and anything else asking in between gets that pass's answer,
-- which is the same frame the screen is looking at.
---------------------------------------------------------------------------
local itemBySpell = {}
local itemViewer  = {}   -- which viewer an item came from: it decides its shape

function CDM:RebuildItemIndex()
    wipe(itemBySpell)
    wipe(itemViewer)

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
            itemViewer[item] = viewer
        end)
    end
end

-- The live frame for a spell, or nil. `fresh` rebuilds first, for a caller
-- that is not riding the screen's render pass.
function CDM:ItemForSpell(spellID, fresh)
    if not spellID then return nil end
    if fresh then self:RebuildItemIndex() end
    return itemBySpell[spellID]
end

-- Which of Blizzard's two templates a frame came out of: "icon" or "bar".
function CDM:ItemShape(item)
    local viewer = itemViewer[item]
    return (viewer and viewer.kind) or "icon"
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

    if item.IsActive then
        local ok, active = pcall(item.IsActive, item)
        if ok then return active and true or false end
    end
    if item.IsShown then
        local ok, shown = pcall(item.IsShown, item)
        if ok then return shown and true or false end
    end
    return nil
end

---------------------------------------------------------------------------
-- The duration HANDLE, which is how a bar can run backwards
--
-- Mirroring Blizzard's bar copies its value, and a value that drains can only
-- be made to grow by subtracting it from its maximum. On this patch that is
-- arithmetic on a secret and it is exactly what an addon may not do. So the
-- switch called "Fill up" did nothing at all on any bar the Cooldown Manager
-- times, which is most of them - a setting that silently does nothing, and
-- the owner reported it as such.
--
-- The engine already knows how to do this. A StatusBar takes a DURATION
-- OBJECT and a direction: SetTimerDuration(durObj, interpolation, direction)
-- with Enum.StatusBarTimerDirection.RemainingTime or .ElapsedTime. Drain and
-- grow are the same call with one argument changed, the client animates it,
-- and no number is ever read into Lua. Read off working code
-- (EllesmereUICdmBuffBars.lua:4501-4518 and :4088-4094), never invented.
--
-- TWO SOURCES, because a bar cell holds one of two things:
--
--   a tracked BUFF   C_UnitAuras.GetAuraDuration(unit, auraInstanceID) - the
--                    aura's own remaining time. The instance ID can be a
--                    secret, and passing a secret to the query hard errors on
--                    a restricted unit, so ns.CanCompute guards it exactly as
--                    ItemStacks does.
--   a COOLDOWN       C_Spell.GetSpellCooldownDuration(spellID) - the handle
--                    tracks haste and cooldown reduction on its own.
--
-- The aura is asked FIRST. A buff-bar cell is showing you the buff, not the
-- cooldown of the spell that applied it, and asking in the other order would
-- fill the bar to the wrong clock while looking entirely plausible.
--
-- Returns nil when nothing answers, and every caller falls back to the value
-- mirror - which is today's behaviour, unchanged.
---------------------------------------------------------------------------
function CDM:DurationHandle(item, spellID)
    if item then
        local get = C_UnitAuras and C_UnitAuras.GetAuraDuration
        local instanceID, unit = item.auraInstanceID, item.auraDataUnit
        if get and unit and ns.CanCompute(instanceID) then
            local ok, durObj = pcall(get, unit, instanceID)
            if ok and durObj then return durObj end
        end
    end

    if Usable(spellID) then
        local get = C_Spell and C_Spell.GetSpellCooldownDuration
        if get then
            local ok, durObj = pcall(get, spellID)
            if ok and durObj then return durObj end
        end
    end
    return nil
end

-- Can this client drive a StatusBar off a duration handle at all? Asked once
-- per bar rather than assumed, because the whole path is newer than the rest
-- of this file and a missing Enum member is one greyed row, not an error.
function CDM:CanDriveTimer(bar)
    return bar and type(bar.SetTimerDuration) == "function"
        and Enum and Enum.StatusBarTimerDirection
        and Enum.StatusBarTimerDirection.ElapsedTime ~= nil
        and true or false
end

-- style comes from ns.Bars:Style, so every number here has already been
-- resolved the same way it will be for our own drawn cells.
--
-- shape says which of Blizzard's two templates this frame is: "icon" or
-- "bar". It decides ONE thing, and that thing is load-bearing - see below.
function CDM:Skin(item, style, shape)
    if not item then return end
    local state = Hold(item)

    StripDecorations(item)

    local zoom = style.iconZoom

    if shape == "bar" then
        -- A BUFF-BAR FRAME IS ALREADY A WHOLE BAR.
        --
        -- Blizzard's TrackedBar template carries a square icon at one end, a
        -- StatusBar that fills with the remaining time, and its own name and
        -- timer text. Forcing its icon to fill the frame - which is exactly
        -- right for the icon template, and the fix that made six adopted
        -- icons one size in 4.5.0 - smears that icon across the full width of
        -- the bar. Which is the one thing a tracking bar must never look like,
        -- and it is what the owner saw the first time one was on screen.
        --
        -- So its parts are left where its own template put them. Only the
        -- crop is applied, because that is about the art rather than the
        -- layout.
        if item.Icon then
            pcall(item.Icon.SetTexCoord, item.Icon, zoom, 1 - zoom, zoom, 1 - zoom)
        end

        -- Its fill DOES get our texture and colour, which is the one part of
        -- the template that is a surface rather than a layout. Without this
        -- the texture picker had no effect on the most bar-like thing the
        -- addon puts on screen, and the two renderers - Blizzard's bar and
        -- the one we draw ourselves - sat side by side wearing different
        -- textures with one setting between them.
        local fill = BarFill(item)
        if fill then
            local key = style.fillTexture
            if key and ns.Media.IsKnown("statusbar", key) then
                pcall(fill.SetStatusBarTexture, fill, ns.Media.Statusbar(key))
            end
            local colour = style.fillColor
            pcall(fill.SetStatusBarColor, fill, colour[1], colour[2], colour[3],
                style.fillAlpha)
        end
    else
        -- The art has to be told to fill the frame. Sizing the FRAME is not
        -- enough: each viewer's template anchors its own icon texture its own
        -- way - a fixed size here, an inset there - so six adopted icons in
        -- one row came out at six sizes, sitting at six different offsets,
        -- while the cells behind them were a perfectly even grid.
        --
        -- Re-anchored on every pass, because these frames are re-decorated
        -- when the pool hands them out again.
        if item.Icon then
            item.Icon:ClearAllPoints()
            item.Icon:SetAllPoints(item)
            pcall(item.Icon.SetTexCoord, item.Icon, zoom, 1 - zoom, zoom, 1 - zoom)
        end

        -- Same for the sweep, or the cooldown would darken a rectangle that is
        -- not the icon it belongs to. A bar frame's cooldown is its fill and
        -- is left alone with everything else.
        if item.Cooldown then
            item.Cooldown:ClearAllPoints()
            item.Cooldown:SetAllPoints(item)
        end
    end

    -- The plate goes on the item at BACKGROUND, under its own icon texture.
    -- Ours would have to guess whether Blizzard's frame draws above or below
    -- our cell, and the answer depends on frame levels we do not own.
    if not state.plate then
        state.plate = item:CreateTexture(nil, "BACKGROUND")
        state.plate:SetAllPoints(item)
    end
    ns.PaintSurface(state.plate, style)

    -- The border lives on a frame of ITS OWN, above the cooldown swipe. A
    -- texture on the item would be painted under the item's own child frames
    -- whatever layer it claims, and the swipe is one of them - the border
    -- would darken along with the icon as the cooldown ran.
    if not state.chrome then
        state.chrome = ns.CreateChrome(item)
    end
    -- On a bar the edge goes OUTSIDE. The last pixel of the fill and the
    -- leading spark are the parts you read, and a border sitting on them is
    -- what the owner meant by "the border is in front of the background".
    ns.PaintBorder(state.chrome, style, shape == "bar")

    local cooldown = item.Cooldown
    if cooldown then
        local swipe = style.swipeColor
        pcall(cooldown.SetSwipeColor, cooldown, swipe[1], swipe[2], swipe[3],
            style.swipeAlpha)
        pcall(cooldown.SetDrawEdge, cooldown, style.showEdge)
        pcall(cooldown.SetHideCountdownNumbers, cooldown, not style.countdown.show)

        if style.countdown.show then
            -- Not StyleNumbers directly: the number does not exist until a
            -- cooldown runs, so the style has to be remembered and re-applied
            -- when it appears. See ns.StyleCountdown.
            ns.StyleCountdown(cooldown, style.countdown)
        end
    end

    -- Stacks and charges are Blizzard's own child FRAMES. Alpha, never Hide -
    -- the same rule that applies to the item itself.
    --
    -- ONE SETTING EACH, not one setting for both. Blizzard never puts these
    -- two numbers on the same frame - a cooldown item carries ChargeCount and
    -- a buff item carries Applications - so sharing a style was invisible on
    -- any single icon. It was not invisible across a screen: "charges top
    -- left, stacks bottom right" was simply not expressible.
    for _, pair in ipairs({
        { "ChargeCount",  style.charges },
        { "Applications", style.stacks },
    }) do
        local widget, text = Counter(item, pair[1]), pair[2]
        if widget then
            pcall(widget.SetAlpha, widget, text.show and 1 or 0)

            -- THE FRAME MOVES, NOT THE TEXT INSIDE IT.
            --
            -- These counters are frames Blizzard anchors once, and the font
            -- string inside is written by its own layout - re-anchoring that
            -- is a fight, and the engine wins it every time the count
            -- changes. Moving the frame is one call that stays put, and it
            -- takes the number with it whatever Blizzard does inside.
            ns.StyleNumberFont(widget, text)
            pcall(MoveCounter, widget, item, text)
        end
    end
end

-- Hands an item frame back to Blizzard: the hooks stay (hooks cannot be
-- removed) but with nothing recorded they do nothing. Alpha is restored
-- explicitly, or a released frame would keep whatever we last forced on it.
function CDM:Release(item)
    local state = adopted[item]
    if not state then return end
    state.anchor = nil
    state.width, state.height = nil, nil
    if state.alpha then
        state.alpha = nil
        item:SetAlpha(1)
    end
    -- THE STRIPPED DECORATIONS GO BACK, at the alpha they had before we
    -- silenced them. They used to stay at zero for the rest of the session,
    -- and that was not a limitation of the approach - nothing had recorded
    -- the old value. The cost was real: switching the takeover off handed
    -- Blizzard back a Cooldown Manager with no borders and no range veil,
    -- from an addon that had just said it was letting go.
    for _, key in ipairs(DECORATIONS) do Undim(item[key]) end
    -- And the counters go back where Blizzard had them. Same rule as the
    -- decorations above: a frame handed back still wearing our layout is a
    -- mark left by an addon that has just said it let go.
    for _, key in ipairs({ "ChargeCount", "Applications" }) do
        local widget = Counter(item, key)
        if widget then pcall(RestoreCounter, widget) end
    end
    for _, region in ipairs({ item:GetRegions() }) do Undim(region) end
    if item.Cooldown then
        for _, region in ipairs({ item.Cooldown:GetRegions() }) do Undim(region) end
    end

    -- And its rounded corners. The mask was taken OFF the icon rather than
    -- redefined - see Unmask - so putting it back is one call and the icon is
    -- Blizzard's own shape again.
    Remask(item.Icon)

    -- Our own plate and border are ours. Leaving either on a frame Blizzard
    -- is drawing again would be a mark from an addon that says it let go.
    if state.plate then state.plate:Hide() end
    if state.chrome then state.chrome:Hide() end
end

function CDM:IsPinned(item)
    local state = adopted[item]
    return state ~= nil and state.anchor ~= nil
end

---------------------------------------------------------------------------
-- What is actually ON one of Blizzard's item frames
--
-- The decoration list in StripDecorations was read off a working addon, and
-- a working addon on a DIFFERENT build. When icons still do not match after
-- stripping, the answer is not to guess another region name - it is to look
-- at what this client actually put there.
--
-- Prints every region of the first adopted frame: type, layer, atlas or
-- texture, alpha, and whether it is one of the named fields we already know
-- about. Anything that turns up unnamed and visible is the thing still
-- making that icon look different.
---------------------------------------------------------------------------
function CDM:DumpSkin()
    local target, targetSpell

    -- Every pinned frame first: what we ASKED for against what is actually
    -- there. A size or an anchor that does not match is not a styling
    -- problem, it is somebody overwriting us - and the two have completely
    -- different fixes.
    -- Which template each frame came out of. Blizzard's two are restyled
    -- differently on purpose - a bar frame is already a whole bar and its
    -- parts are left alone - so a report that does not say which is which
    -- cannot answer "why does this one look different".
    local shapeOf = {}
    for _, viewer in ipairs(self.VIEWERS) do
        self:ForEachItem(viewer.key, function(item)
            shapeOf[item] = viewer.kind
        end)
    end

    ns.Print("|cffffd100--- pinned icons: asked for / actually ---|r")
    local count = 0

    for item, state in pairs(adopted) do
        if state.anchor then
            count = count + 1
            local spellID = self:ItemSpellID(item)
            local point, relativeTo, relativePoint = item:GetPoint(1)

            -- On SCREEN, not in the frame's own coordinate space. A frame at
            -- scale 1.2 reports 36 and draws 43, and reporting the 36 is how
            -- five icons were declared correct while three of them were
            -- visibly the wrong size.
            local scale = item:GetEffectiveScale() or 1
            local cellScale = (state.anchor and state.anchor[2]
                and state.anchor[2]:GetEffectiveScale()) or scale

            local wantW = (state.width or 0) * cellScale
            local wantH = (state.height or 0) * cellScale
            local gotW = (item:GetWidth() or 0) * scale
            local gotH = (item:GetHeight() or 0) * scale
            local sizeOK = math.abs(gotW - wantW) < 1 and math.abs(gotH - wantH) < 1
            local anchorOK = relativeTo == state.anchor[2]
                and point == state.anchor[1] and relativePoint == state.anchor[3]

            ns.Print(string.format("%s %s |cff888888%d|r |cff7ec6d4%s|r  "
                .. "%.0fx%.0f px%s  scale %.2f%s  anchor %s%s",
                (sizeOK and anchorOK) and "|cff40ff40ok|r" or "|cffff4040NO|r",
                ns.SpellName(spellID) or "?", spellID or 0,
                shapeOf[item] or "?",
                gotW, gotH,
                sizeOK and "" or string.format(" |cffff4040(asked %.0fx%.0f)|r",
                    wantW, wantH),
                item:GetScale() or 1,
                math.abs(scale - cellScale) < 0.001 and ""
                    or string.format(" |cffff4040(cell is %.2f)|r", cellScale),
                tostring(point) .. "/" .. tostring(relativePoint),
                anchorOK and "" or string.format(" |cffff4040(asked %s/%s, and it "
                    .. "is on a different frame)|r", state.anchor[1], state.anchor[3])))

            if not target then
                target = item
                targetSpell = spellID
            end
        end
    end

    if count == 0 then
        ns.Print("No adopted icon to look at - put a Cooldown Manager spell "
            .. "on a bar first.")
        return
    end

    -- Named fields first, so anything found in the region walk that is NOT
    -- one of these stands out as something we do not handle.
    local named = {}
    for _, key in ipairs({ "Icon", "Border", "Shadow", "IconShadow",
        "DebuffBorder", "CooldownFlash", "SpellActivationAlert", "Cooldown",
        "ChargeCount", "Applications" }) do
        local widget = target[key]
        if widget then named[widget] = key end
    end

    ns.Print("|cffffd100--- skin report:", ns.SpellName(targetSpell) or "?",
        "(" .. tostring(targetSpell) .. ") ---|r")
    ns.Print(string.format("frame %.0fx%.0f, alpha %.2f, shown %s, template %s",
        target:GetWidth() or 0, target:GetHeight() or 0, target:GetAlpha(),
        tostring(target:IsShown()), shapeOf[target] or "?"))

    -- Child FRAMES, not just regions. A buff-bar frame keeps its fill in a
    -- StatusBar of its own, so a bar that has gone blank has gone blank
    -- somewhere the region walk below cannot see.
    for _, child in ipairs({ target:GetChildren() }) do
        local kind = child.GetObjectType and child:GetObjectType() or "?"
        ns.Print(string.format("  child %s |cff888888a=%.2f shown %s %.0fx%.0f|r",
            kind, child:GetAlpha() or 1, tostring(child:IsShown()),
            child:GetWidth() or 0, child:GetHeight() or 0))
    end

    for _, region in ipairs({ target:GetRegions() }) do
        local kind = region.GetObjectType and region:GetObjectType() or "?"
        local layer = region.GetDrawLayer and region:GetDrawLayer() or "-"
        local atlas = region.GetAtlas and region:GetAtlas()
        local texture = region.GetTexture and region:GetTexture()
        local alpha = region.GetAlpha and region:GetAlpha() or 1

        local label = named[region] or "|cff888888(unnamed)|r"
        local what = atlas and ("atlas " .. atlas)
            or (texture and ("texture " .. tostring(texture)))
            or "-"

        -- Only what is still VISIBLE can be what you are looking at.
        local mark = (alpha > 0 and region:IsShown()) and "|cff40ff40*|r" or " "

        ns.Print(string.format("%s %s |cff888888%s %s|r a=%.2f  %s",
            mark, label, kind, layer, alpha, what))
    end

    if target.Icon and target.Icon.GetTexCoord then
        local left, _, _, _, right, _, _, bottom = target.Icon:GetTexCoord()
        ns.Print(string.format("Icon texcoord %.3f %.3f %.3f", left or 0,
            right or 0, bottom or 0))
    end

    -- The number that actually decides whether the corners are round. A mask
    -- region can still be listed above while no longer being APPLIED to the
    -- icon, which is the whole point of removing it rather than redefining
    -- it - so this is the line to read, not the mask's texture id.
    if target.Icon and target.Icon.GetNumMaskTextures then
        local ok, masks = pcall(target.Icon.GetNumMaskTextures, target.Icon)
        if ok then
            ns.Print(string.format("masks still on the icon: %s%d|r",
                (masks or 0) > 0 and "|cffff4040" or "|cff40ff40", masks or 0))
        end
    end

    ns.Print("|cffffd100A green * is still drawn. Anything unnamed with a "
        .. "green * is what we are not stripping.|r")
end

---------------------------------------------------------------------------
-- Is another addon holding the same frames?
--
-- There is ONE set of Cooldown Manager item frames, and every addon that
-- "does cooldowns" on this patch works by adopting them. Two addons doing
-- that to the same frame both hook SetPoint and both re-assert their own
-- anchor, so whichever ran last wins - per frame, so the icons end up split
-- between two layouts. It looks like a bug in whichever one you are looking
-- at, and it is not one.
--
-- Detected rather than assumed: a short moment after pinning, an item whose
-- anchor is no longer ours was taken by somebody else. That works against
-- any addon, including ones that do not exist yet.
---------------------------------------------------------------------------

-- Only ones confirmed to adopt these frames, by reading their code on this
-- machine. Used to NAME the culprit, never to decide there is one.
local KNOWN_ADOPTERS = {
    ["EllesmereUICooldownManager"] = "EllesmereUI's Cooldown Manager",
}

local function LoadedAdopters()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if not isLoaded then return nil end

    local names
    for addon, label in pairs(KNOWN_ADOPTERS) do
        local ok, loaded = pcall(isLoaded, addon)
        if ok and loaded then
            names = names and (names .. ", " .. label) or label
        end
    end
    return names
end

-- For the Diagnostics page, which has to answer before a single bar exists -
-- so it asks who is LOADED rather than waiting for an icon to be taken.
function CDM:RivalName()
    return LoadedAdopters()
end

function CDM:CheckForRivals()
    if self.rivalReported then return end

    local stolen = 0
    for item, state in pairs(adopted) do
        if state.anchor then
            local _, relativeTo = item:GetPoint(1)
            if relativeTo ~= state.anchor[2] then stolen = stolen + 1 end
        end
    end

    if stolen == 0 then return end
    self.rivalReported = true

    local who = LoadedAdopters()
    ns.Print("|cffff4040" .. stolen .. " of your cooldown icons were taken back "
        .. "by another addon.|r")
    if who then
        ns.Print("It is " .. who .. ". It adopts the same frames this addon "
            .. "does, and there is only one set of them.")
    else
        ns.Print("Something else on this client adopts the same frames this "
            .. "addon does, and there is only one set of them.")
    end
    ns.Print("Run one or the other, not both: disable that addon's cooldown "
        .. "module, or leave these cooldowns off your bars.")
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
