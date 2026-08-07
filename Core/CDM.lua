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
            ns.StyleNumbers(cooldown, style.countdown)
        end
    end

    -- Stacks and charges are Blizzard's own child FRAMES. Alpha, never Hide -
    -- the same rule that applies to the item itself.
    for _, widget in ipairs({ item.ChargeCount, item.Applications }) do
        if widget then
            pcall(widget.SetAlpha, widget, style.stacks.show and 1 or 0)
            ns.StyleNumbers(widget, style.stacks)
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
