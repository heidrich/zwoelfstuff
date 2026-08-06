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
    if self.available ~= nil then return self.available end

    self.available = false
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

-- The spell a given item frame stands for. overrideSpellID wins: a talent
-- that replaces a spell reports the replacement there, and that is what the
-- player actually casts and sees.
function CDM:ItemSpellID(item)
    local info = self:GetInfo(self:ItemCooldownID(item))
    if not info then return nil end
    return info.overrideSpellID or info.spellID
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

function CDM:Catalogue()
    -- Keyed by SPELL, not by cooldown. Several cooldownIDs can point at one
    -- spell - the live frame and the static entry both do - and a picker that
    -- lists the same spell three times is noise: the user picks a spell, and
    -- that is what a cell stores.
    local bySpell = {}

    local function Add(cooldownID, viewerKey, live)
        if not cooldownID then return end
        local info = self:GetInfo(cooldownID)
        if not info then return end

        local spellID = info.overrideSpellID or info.spellID
        if not spellID then return end

        local existing = bySpell[spellID]
        if existing then
            -- The live pool wins: it knows which viewer actually shows it,
            -- which is what the user sees on screen.
            if viewerKey and not existing.viewer then
                existing.viewer = viewerKey
                existing.cooldownID = cooldownID
            end
            if live then existing.known = true end
            return
        end

        bySpell[spellID] = {
            cooldownID = cooldownID,
            spellID    = spellID,
            viewer     = viewerKey,
            name       = ns.SpellName(spellID) or ("Spell " .. spellID),
            icon       = ns.SpellTexture(spellID),
            -- A frame in a live pool is on screen, so it is talented by
            -- definition; anything else has to be asked about.
            known      = live or ns.IsSpellKnown(spellID),
        }
    end

    for _, viewer in ipairs(self.VIEWERS) do
        self:ForEachItem(viewer.key, function(item)
            Add(self:ItemCooldownID(item), viewer.key, true)
        end)
    end

    -- Enum.CooldownViewerCategory rather than hardcoded numbers: the values
    -- are Blizzard's to change, and iterating the enum survives that.
    --
    -- The second argument true means "including what is not talented". Those
    -- are wanted: they are listed and greyed, so a bar can be built for a
    -- build you are about to switch into instead of the list silently missing
    -- half the class.
    local categories = Enum and Enum.CooldownViewerCategory
    local getSet = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    if categories and getSet then
        for _, category in pairs(categories) do
            local viewerKey = self:CategoryViewer(category)
            local ok, set = pcall(getSet, category, true)
            if ok and type(set) == "table" then
                for _, cooldownID in ipairs(set) do Add(cooldownID, viewerKey) end
            end
        end
    end

    local out = {}
    for _, entry in pairs(bySpell) do out[#out + 1] = entry end

    -- pairs() has no order, so the spell ID is the tiebreaker: without one the
    -- list would reshuffle two same-named spells every time it is built.
    table.sort(out, function(a, b)
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

local function Reassert(state, frame)
    if state.applying then return end
    state.applying = true
    if state.anchor then
        local a = state.anchor
        frame:ClearAllPoints()
        frame:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
    if state.width then
        frame:SetSize(state.width, state.height)
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
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local OVERLAY_FILE  = 6707800
local SQUARE_MASK   = "Interface\\Buttons\\WHITE8X8"

local function Dim(region, alsoHide)
    if not region then return end
    pcall(region.SetAlpha, region, 0)
    if alsoHide then pcall(region.Hide, region) end
end

-- Blizzard rounds its icons with a mask texture. Replacing the mask with a
-- plain white square is what squares them off - the corners cannot be set
-- any other way, because they are not a border.
local function SquareMasks(frame)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("MaskTexture") then
            pcall(region.SetTexture, region, SQUARE_MASK)
        end
    end
end

local function StripDecorations(item, state)
    if state.stripped then return end
    state.stripped = true

    Dim(item.Border)
    Dim(item.Shadow)
    Dim(item.IconShadow)
    Dim(item.DebuffBorder)
    Dim(item.CooldownFlash)
    Dim(item.SpellActivationAlert, true)

    SquareMasks(item)
    SquareMasks(item.Cooldown)

    -- One shared texture lightens some icons and not others. Matched by atlas
    -- AND by file id, because the same art is reachable either way.
    for _, region in ipairs({ item:GetRegions() }) do
        if region ~= item.Icon and region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            local texture = region.GetTexture and region:GetTexture()
            if atlas == OVERLAY_ATLAS or texture == OVERLAY_FILE then
                Dim(region, true)
            end
        end
    end
end

-- style comes from ns.Bars:Style, so every number here has already been
-- resolved the same way it will be for our own drawn cells.
function CDM:Skin(item, style)
    if not item then return end
    local state = Hold(item)

    StripDecorations(item, state)

    local zoom = style.iconZoom
    if item.Icon then
        pcall(item.Icon.SetTexCoord, item.Icon, zoom, 1 - zoom, zoom, 1 - zoom)
    end

    -- The plate goes on the item at BACKGROUND, under its own icon texture.
    -- Ours would have to guess whether Blizzard's frame draws above or below
    -- our cell, and the answer depends on frame levels we do not own.
    if not state.plate then
        state.plate = item:CreateTexture(nil, "BACKGROUND")
        state.plate:SetAllPoints(item)
    end
    local plate = style.backdropColor
    state.plate:SetColorTexture(plate[1], plate[2], plate[3], style.backdropAlpha)
    state.plate:SetShown(style.backdrop)

    -- The border lives on a frame of ITS OWN, above the cooldown swipe. A
    -- texture on the item would be painted under the item's own child frames
    -- whatever layer it claims, and the swipe is one of them - the border
    -- would darken along with the icon as the cooldown ran.
    if not state.chrome then
        local chrome = CreateFrame("Frame", nil, item)
        chrome:SetAllPoints(item)
        chrome:SetFrameLevel(item:GetFrameLevel() + 5)
        state.chrome = chrome
        state.border = ns.CreateBorder(chrome, 1, "OVERLAY")
    end

    local edge = style.borderColor
    state.border:SetThickness(style.borderSize)
    state.border:SetColor(edge[1], edge[2], edge[3], 1)
    state.border:SetShown(style.borderSize > 0)

    local cooldown = item.Cooldown
    if cooldown then
        local swipe = style.swipeColor
        pcall(cooldown.SetSwipeColor, cooldown, swipe[1], swipe[2], swipe[3],
            style.swipeAlpha)
        pcall(cooldown.SetDrawEdge, cooldown, style.showEdge)
        pcall(cooldown.SetHideCountdownNumbers, cooldown, not style.showCountdown)

        if style.showCountdown then
            ns.StyleNumbers(cooldown, style.countdownSize, style.countdownColor,
                style.countdownAnchor)
        end
    end

    -- Stacks and charges are Blizzard's own child FRAMES. Alpha, never Hide -
    -- the same rule that applies to the item itself.
    for _, widget in ipairs({ item.ChargeCount, item.Applications }) do
        if widget then
            pcall(widget.SetAlpha, widget, style.showStacks and 1 or 0)
            ns.StyleNumbers(widget, style.stackSize, style.stackColor)
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
    -- The stripped decorations are NOT put back. They cannot be: an alpha of
    -- zero is all we know, not what it was before. The border is ours though,
    -- and leaving it on a frame Blizzard is drawing again would be a mark
    -- from an addon that says it let go.
    if state.chrome then state.chrome:Hide() end
end

function CDM:IsPinned(item)
    local state = adopted[item]
    return state ~= nil and state.anchor ~= nil
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
