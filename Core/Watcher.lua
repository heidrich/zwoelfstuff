---------------------------------------------------------------------------
-- Watcher - determines whether a tracked aura is on the player.
--
-- Five routes, tried in order, because patch 12.x closes off the obvious
-- ones. Measured in game on 12.1: EVERY buff on the player came back secret
-- (0 readable, 18 secret), so routes 1, 2 and 4 are dead whenever the game
-- restricts aura data - which it does in combat.
--
--   1) GetPlayerAuraBySpellID  - ID goes INTO the query, nothing secret is
--      compared. Returns nil for restricted auras.
--   2) GetAuraDataBySpellName  - covers auras whose applied ID differs from
--      the tooltip or talent ID. Same restriction applies.
--   3) Blizzard's cooldown viewers - these DO hand out plain spell IDs and
--      readable auraInstanceIDs even in combat, but only for buffs the
--      Cooldown Manager actually tracks.
--   4) Icon match over the aura list - only works while icons stay readable.
--   5) Proc glow. C_SpellActivationOverlay.IsSpellOverlayed(spellID) is a
--      plain boolean that never touches aura data. A rotational proc that
--      lights up an action button is detectable this way even when the aura
--      itself is completely invisible to addons. Timing then comes from our
--      own clock and our own duration constant - plain numbers we own.
---------------------------------------------------------------------------
local _, ns = ...

local Watcher = {}
ns.Watcher = Watcher

-- All four Blizzard viewers: a proc can be registered in the essential or
-- utility category too, not only in the buff ones.
local VIEWERS = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

---------------------------------------------------------------------------
-- Route 1 + 2: direct aura queries
---------------------------------------------------------------------------

-- Never raises: a secret-flagged spell can make the query itself throw.
local function QueryBySpellID(spellID)
    local byID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not byID then return nil end
    local ok, aura = pcall(byID, spellID)
    if ok then return aura end
    return nil
end

local function QueryByName(spellID)
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not byName then return nil end
    local name = ns.SpellName(spellID)
    if not name then return nil end

    local ok, aura = pcall(byName, "player", name, "HELPFUL")
    if ok and aura then return aura end

    ok, aura = pcall(byName, "player", name, "HARMFUL")
    if ok then return aura end
    return nil
end

---------------------------------------------------------------------------
-- Route 3: Blizzard's cooldown viewers
---------------------------------------------------------------------------
local function CooldownInfoMatches(info, spellID, wantName)
    if not info then return false end

    if info.spellID == spellID or info.overrideSpellID == spellID then
        return true
    end

    if info.linkedSpellIDs then
        for _, linked in ipairs(info.linkedSpellIDs) do
            if linked == spellID then return true end
        end
    end

    if wantName and info.spellID then
        local name = ns.SpellName(info.spellID)
        if name and name == wantName then return true end
    end

    return false
end

-- Returns unit, auraInstanceID when a viewer currently shows this buff.
local function QueryViaCooldownViewer(spellID)
    local getInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not getInfo then return nil end

    local wantName = ns.SpellName(spellID)

    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do
                -- IsShown, not IsVisible: the viewer itself may be hidden by
                -- a UI suite while still tracking correctly.
                if frame:IsShown() then
                    local cdID = frame.cooldownID
                        or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
                    if cdID then
                        -- The match is wrapped too: comparing a field that
                        -- silently turns secret is the bug this addon has
                        -- already shipped once.
                        local ok, info = pcall(getInfo, cdID)
                        local matched = ok and select(2,
                            pcall(CooldownInfoMatches, info, spellID, wantName))
                        if matched then
                            local unit = frame.auraDataUnit or "player"
                            local instanceID = frame.auraInstanceID
                            if not ns.CanCompute(instanceID) then
                                instanceID = nil   -- presence known, timing not
                            end
                            return unit, instanceID
                        end
                    end
                end
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Route 4: icon match over the player's aura list
--
-- The icon of OUR spell ID is always plain, so comparing it against a
-- readable aura icon is legal. Two buffs can share an icon, hence last place
-- among the aura routes.
---------------------------------------------------------------------------
local function QueryByIcon(spellID)
    local getByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getByIndex then return nil end

    local wantTexture = ns.SpellTexture(spellID)
    if not ns.CanCompute(wantTexture) then return nil end

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for index = 1, 60 do
            local ok, aura = pcall(getByIndex, "player", index, filter)
            if not ok or not aura then break end
            if ns.CanCompute(aura.icon) and aura.icon == wantTexture then
                return aura
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Route 5: proc glow
--
-- The last resort that does not involve aura data at all. When a proc lights
-- up an action button, IsSpellOverlayed on the GLOWING spell is a plain
-- boolean. The buff itself stays invisible, but the proc does not.
---------------------------------------------------------------------------
local glowActive, glowStart = false, 0

local function IsOverlayed(spellID)
    -- Namespaced form only. The old global is deprecated, and the dump
    -- reports it if this namespace ever goes missing, so a silent fallback
    -- would only hide a real problem.
    local isOverlayed = C_SpellActivationOverlay
        and C_SpellActivationOverlay.IsSpellOverlayed
    if not isOverlayed or not spellID then return false end
    local ok, on = pcall(isOverlayed, spellID)
    return (ok and on) and true or false
end

-- Kept as its own step so the rising edge (and therefore the start time) is
-- captured no matter how often the resolver runs.
function Watcher:PollGlow()
    local spellID = ns.db.glowSpellID
    if not spellID then
        glowActive = false
        return
    end

    local on = IsOverlayed(spellID)
    if on and not glowActive then
        glowStart = GetTime()
    end
    glowActive = on
end

---------------------------------------------------------------------------
-- Resolution
---------------------------------------------------------------------------

-- First configured spell that is currently on the player wins, so the
-- list doubles as a priority list.
function Watcher:GetActiveAura()
    self:PollGlow()

    for _, spellID in ipairs(ns.db.spellIDs) do
        local aura = QueryBySpellID(spellID) or QueryByName(spellID)
        if aura then
            return {
                spellID        = spellID,
                unit           = "player",
                auraInstanceID = aura.auraInstanceID,
                data           = aura,
                route          = "aura",
            }
        end

        local unit, instanceID = QueryViaCooldownViewer(spellID)
        if unit then
            return {
                spellID        = spellID,
                unit           = unit,
                auraInstanceID = instanceID,
                route          = "viewer",
            }
        end

        local byIcon = QueryByIcon(spellID)
        if byIcon then
            return {
                spellID        = spellID,
                unit           = "player",
                auraInstanceID = ns.CanCompute(byIcon.auraInstanceID)
                    and byIcon.auraInstanceID or nil,
                data           = byIcon,
                route          = "icon",
            }
        end
    end

    -- Glow is configured globally rather than per aura, so it runs last and
    -- drives whichever spell sits first in the list.
    if glowActive then
        return {
            spellID       = ns.db.spellIDs[1] or ns.PRIMARY_SPELL_ID,
            route         = "glow",
            stamp         = glowStart,
            plainStart    = glowStart,
            plainDuration = ns.db.glowDuration,
        }
    end

    return nil
end

function Watcher:Publish()
    ns.Display:Update(self:GetActiveAura())
end

---------------------------------------------------------------------------
-- Tracked spell list
---------------------------------------------------------------------------
function Watcher:RebuildTracked()
    if self.frame then
        self:Publish()
    end
end

function Watcher:IsTracked(spellID)
    for _, id in ipairs(ns.db.spellIDs) do
        if id == spellID then return true end
    end
    return false
end

function Watcher:AddSpell(spellID)
    if self:IsTracked(spellID) then
        ns.Print("Already tracked:", spellID)
        return false
    end

    table.insert(ns.db.spellIDs, spellID)
    self:RebuildTracked()
    if ns.Options.Refresh then ns.Options:Refresh() end

    ns.Print("Now tracking", spellID, "-",
        ns.SpellName(spellID) or "|cff888888name unknown to this client|r")
    return true
end

function Watcher:RemoveSpell(spellID)
    for index, id in ipairs(ns.db.spellIDs) do
        if id == spellID then
            table.remove(ns.db.spellIDs, index)
            self:RebuildTracked()
            if ns.Options.Refresh then ns.Options:Refresh() end
            ns.Print("Stopped tracking", spellID)
            if #ns.db.spellIDs == 0 then
                ns.Print("|cffffd100The list is now empty - nothing will be shown.|r")
            end
            return true
        end
    end

    ns.Print("Not tracked:", spellID)
    return false
end

---------------------------------------------------------------------------
-- Glow configuration
---------------------------------------------------------------------------
function Watcher:SetGlowSpell(spellID)
    ns.db.glowSpellID = spellID
    glowActive, glowStart = false, 0

    if spellID then
        ns.Print("Proc glow source set to", spellID, "-",
            ns.SpellName(spellID) or "|cff888888unknown|r")
        if not (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) then
            ns.Print("|cffff4040IsSpellOverlayed is missing on this client - route 5 cannot work.|r")
        end
    else
        ns.Print("Proc glow source cleared.")
    end

    self:RebuildTracked()
    if ns.Options.Refresh then ns.Options:Refresh() end
end

-- Prints every proc glow the game raises, so the spell ID that lights up
-- when the buff procs can simply be read off the chat frame.
function Watcher:ToggleGlowLog()
    if self.glowLog then
        self.glowLog:UnregisterAllEvents()
        self.glowLog:SetScript("OnEvent", nil)
        self.glowLog = nil
        ns.Print("Glow logging |cffff4040off|r.")
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    frame:SetScript("OnEvent", function(_, event, spellID)
        local on = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        local tag = on and "|cff40ff40GLOW ON |r" or "|cff888888glow off|r"
        if ns.CanCompute(spellID) then
            ns.Print(tag, spellID, ns.SpellName(spellID) or "?")
        else
            ns.Print(tag, "|cffff4040(spell id is secret)|r")
        end
    end)

    self.glowLog = frame
    ns.Print("Glow logging |cff40ff40on|r. Trigger the proc, note the spell ID,")
    ns.Print("then set it with |cffffd100/dks glow <spellID>|r. |cffffd100/dks glowlog|r again to stop.")
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
local function Verdict(found)
    return found and "|cff40ff40FOUND|r" or "|cffff4040not found|r"
end

function Watcher:Check(spellID)
    local name = ns.SpellName(spellID)
    ns.Print(string.format("Checking |cffffd100%d|r (%s):", spellID,
        name or "|cff888888name unknown to this client|r"))

    local byID = QueryBySpellID(spellID)
    ns.Print("  1 by spell ID:      ", Verdict(byID))

    local byName = name and QueryByName(spellID)
    ns.Print("  2 by name:          ", Verdict(byName))

    local unit, instanceID = QueryViaCooldownViewer(spellID)
    ns.Print("  3 by cooldown viewer:", Verdict(unit),
        unit and (instanceID and "|cff888888(with timing)|r"
            or "|cffffd100(presence only, no timing)|r") or "")

    ns.Print("  4 by icon match:    ", Verdict(QueryByIcon(spellID)))

    self:PollGlow()
    if ns.db.glowSpellID then
        ns.Print("  5 by proc glow:     ", Verdict(glowActive),
            string.format("|cff888888(watching %d)|r", ns.db.glowSpellID))
    else
        ns.Print("  5 by proc glow:      |cffffd100not configured|r",
            "|cff888888- use /dks glowlog|r")
    end
end

-- The command that ends the guessing. Must be run WHILE the buff is up.
function Watcher:Dump()
    local target = ns.db.spellIDs[1] or ns.PRIMARY_SPELL_ID
    local wantTexture = ns.SpellTexture(target)

    ns.Print(string.format("=== dump for |cffffd100%d|r (%s), icon %s ===",
        target, ns.SpellName(target) or "?", tostring(wantTexture)))
    ns.Print(string.format("  in combat: %s",
        UnitAffectingCombat("player") and "|cff40ff40yes|r" or "|cffffd100NO|r"))

    -- Which APIs actually exist. Without this, "API missing" and "aura not
    -- found" are indistinguishable - a real defect in earlier versions.
    ns.Print("  APIs:")
    local APIS = {
        { "GetPlayerAuraBySpellID", C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID },
        { "GetAuraDataBySpellName", C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName },
        { "GetAuraDataByIndex", C_UnitAuras and C_UnitAuras.GetAuraDataByIndex },
        { "GetAuraDuration", C_UnitAuras and C_UnitAuras.GetAuraDuration },
        { "GetAuraApplicationDisplayCount", C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount },
        { "GetCooldownViewerCooldownInfo", C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo },
        { "GetCooldownViewerCategorySet", C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet },
        { "IsSpellOverlayed", C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed },
        { "issecretvalue", issecretvalue },
    }
    for _, entry in ipairs(APIS) do
        print(string.format("      %s %s",
            entry[2] and "|cff40ff40ok  |r" or "|cffff4040MISSING|r", entry[1]))
    end

    -- Proc glow: the route that still works when every aura is secret.
    ns.Print("  proc glow:")
    local glowID = ns.db.glowSpellID
    if not glowID then
        print("      |cffffd100not configured|r - try |cffffffff/dks glow Blood Boil|r")
    else
        print(string.format("      watching %d (%s): %s", glowID,
            ns.SpellName(glowID) or "?",
            IsOverlayed(glowID) and "|cff40ff40GLOWING|r" or "|cff888888dark|r"))

        -- Tests the "empowered = spell override" hypothesis: if the empowered
        -- Blood Boil is a different spell, this is an exact, unambiguous
        -- signal rather than a glow that several procs share.
        local getOverride = C_Spell and C_Spell.GetOverrideSpell
        if getOverride then
            local ok, override = pcall(getOverride, glowID)
            if ok and ns.CanCompute(override) then
                print(string.format("      override -> %s %s%s", tostring(override),
                    ns.SpellName(override) or "?",
                    override ~= glowID and "  |cff40ff40<== EMPOWERED|r" or ""))
            end
        else
            print("      |cff888888C_Spell.GetOverrideSpell unavailable|r")
        end
    end

    -- Does the Cooldown Manager data set know this spell at all? This is the
    -- direct test of the premise the whole addon rests on.
    local getSet = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    local getInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if getSet and getInfo then
        local total, hit = 0, false
        for category = 0, 3 do
            for _, includeAll in ipairs({ false, true }) do
                local ok, ids = pcall(getSet, category, includeAll)
                if ok and ids then
                    for _, cdID in ipairs(ids) do
                        total = total + 1
                        local okInfo, info = pcall(getInfo, cdID)
                        if okInfo and info then
                            if info.spellID == target or info.overrideSpellID == target then
                                hit = true
                                print(string.format(
                                    "      |cff40ff40IN CDM DATA|r category %d cd=%s spell=%s",
                                    category, tostring(cdID), tostring(info.spellID)))
                            end
                        end
                    end
                end
            end
        end
        ns.Print(string.format("  cdm data set: %d entries scanned, target %s",
            total, hit and "|cff40ff40present|r" or "|cffff4040absent|r"))
    end

    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        local pool = viewer and viewer.itemFramePool

        if not viewer then
            ns.Print(string.format("  %s: |cffff4040missing|r", viewerName))
        elseif not (pool and pool.EnumerateActive) then
            ns.Print(string.format("  %s: |cffffd100no itemFramePool|r", viewerName))
        else
            local total = 0
            local lines = {}
            for frame in pool:EnumerateActive() do
                total = total + 1
                local cdID = frame.cooldownID
                    or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
                local sid
                if getInfo and cdID then
                    local ok, info = pcall(getInfo, cdID)
                    if ok and info then sid = info.spellID end
                end
                lines[#lines + 1] = string.format("      %s spell=%s %s%s",
                    frame:IsShown() and "|cff40ff40[on] |r" or "|cff888888[off]|r",
                    tostring(sid), sid and (ns.SpellName(sid) or "?") or "",
                    ns.CanCompute(frame.auraInstanceID) and " |cff888888+timing|r" or "")
            end
            ns.Print(string.format("  %s: %d entries", viewerName, total))
            for _, line in ipairs(lines) do print(line) end
        end
    end

    local getByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getByIndex then
        ns.Print("  GetAuraDataByIndex unavailable.")
        return
    end

    ns.Print("  player buffs:")
    local readable, secret = 0, 0
    for index = 1, 60 do
        local ok, aura = pcall(getByIndex, "player", index, "HELPFUL")
        if not ok or not aura then break end

        if ns.CanCompute(aura.spellId) and ns.CanCompute(aura.name) then
            readable = readable + 1
            -- aura.icon can be secret even when the name is not.
            local iconMatch = ns.CanCompute(aura.icon) and aura.icon == wantTexture
            print(string.format("      |cffffd100%s|r %s%s", tostring(aura.spellId),
                aura.name, iconMatch and "  |cff40ff40<== ICON MATCH|r" or ""))
        else
            secret = secret + 1
        end
    end
    ns.Print(string.format("  %d readable, |cffff7a3d%d secret|r.", readable, secret))
    if readable == 0 and secret > 0 then
        ns.Print("  |cffffd100Every buff is secret - routes 1, 2 and 4 cannot work here.|r")
        ns.Print("  |cffffd100Use |r|cffffffff/dks glowlog|r|cffffd100 and drive it off the proc glow.|r")
    end
end

function Watcher:Scan()
    self:Dump()
end

function Watcher:Status()
    ns.Print("Status:")
    for _, id in ipairs(ns.db.spellIDs) do
        local byID = QueryBySpellID(id)
        local byName = QueryByName(id)
        local unit = QueryViaCooldownViewer(id)
        local route = byID and "aura by ID" or byName and "aura by name"
            or unit and "cooldown viewer" or nil
        ns.Print(string.format("  |cffffd100%d|r %s - %s", id,
            ns.SpellName(id) or "|cff888888(name unknown)|r",
            route and ("|cff40ff40active|r via " .. route) or "|cff888888not active|r"))
    end

    self:PollGlow()
    ns.Print("  proc glow:", ns.db.glowSpellID
        and string.format("%d (%s) - %s", ns.db.glowSpellID,
            ns.SpellName(ns.db.glowSpellID) or "?",
            glowActive and "|cff40ff40glowing|r" or "|cff888888dark|r")
        or "|cffffd100not configured|r")

    ns.Print("  mode:", ns.db.mode, "| locked:", tostring(ns.db.locked),
        "| always show:", tostring(ns.db.alwaysShow))
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Watcher:Start()
    if self.frame then return end

    local frame = CreateFrame("Frame")
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

    -- The UNIT_AURA payload is deliberately ignored: reading it would mean
    -- touching secret fields.
    frame:SetScript("OnEvent", function()
        Watcher:Publish()
    end)

    -- Secret procs produce no readable event, and the cooldown viewer binds
    -- its frames a moment after the aura lands. A light poll covers both;
    -- 0.1s is well below reaction time and costs a few C calls per tick.
    self.ticker = C_Timer.NewTicker(0.1, function()
        Watcher:Publish()
    end)

    self.frame = frame
    self:Publish()
end
