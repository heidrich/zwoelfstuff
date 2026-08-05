---------------------------------------------------------------------------
-- DKstuff - isolates single auras into their own display.
--
-- Blizzard's Cooldown Manager only offers spells that exist in the
-- C_CooldownViewer data set. Auras outside that set - Boiling Point
-- (spell 1265968) among them - can never be added there, not even through
-- CDM addons, because their spell pickers enumerate the very same data set.
--
-- This file: namespace, defaults, saved variables, shared helpers, commands.
---------------------------------------------------------------------------
local ADDON, ns = ...

ns.ADDON = ADDON
ns.version = "4.0.0"

-- The aura this addon was built for: the Boiling Point buff, 15s, Blood
-- Death Knight. Everything user-facing resolves the name from the client at
-- runtime (ns.SpellName / aura.name) - the ID is the only fixed fact here.
ns.PRIMARY_SPELL_ID = 1265968

ns.WHITE = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- One tracking group. Groups are the general form of "show me these auras":
-- any number of them, icons or bars, laid out in rows, columns or a grid.
--
-- Font sizes of 0 mean "derive it from the element size" - see Auto() in
-- Groups.lua. They are numbers rather than nil so the option steppers have
-- something to edit.
---------------------------------------------------------------------------
ns.GROUP_DEFAULTS = {
    name       = "Tracker",
    enabled    = true,

    style      = "icon",       -- "icon" | "bar"
    -- "fixed"   - one slot per spell, YOUR order, gaps stay open
    -- "dynamic" - engine picks and sorts, stays compact, positions move
    layoutMode = "fixed",

    unit       = "player",     -- player | target | focus | pet
    filter     = "HELPFUL",    -- HELPFUL | HARMFUL
    onlyMine   = false,        -- adds the PLAYER token to the filter
    spells     = {},           -- in fixed mode this list IS the sort order
    max        = 8,            -- dynamic mode only: how many buttons exist

    -- Layout. All of these apply live, in combat included.
    growthH     = "RIGHT",     -- RIGHT | LEFT
    growthV     = "DOWN",      -- DOWN | UP
    axis        = "horizontal",-- horizontal: lines are rows | vertical: columns
    wrapAfter   = 0,           -- 0 = never wrap
    spacing     = 4,
    lineSpacing = 4,
    sort        = "default",   -- default | important  (dynamic mode)

    -- Element size
    iconSize   = 40,
    barWidth   = 200,
    barHeight  = 22,

    -- Looks
    borderSize    = 1,
    borderColor   = { 0.00, 0.00, 0.00 },
    barColor      = { 1.00, 0.44, 0.16 },
    backdropAlpha = 0.90,
    trackAlpha    = 0.08,

    showSwipe  = true,
    showTimer  = true,
    showStacks = true,
    showName   = true,         -- bar style, fixed mode only
    showIcon   = true,         -- bar style
    showLabel  = false,        -- icon style, fixed mode only

    timerAnchor = "CENTER",    -- CENTER | BOTTOM | TOP
    timerSize   = 0,           -- 0 = auto
    stackSize   = 0,
    nameSize    = 0,

    scale    = 1.0,
    alpha    = 1.0,
    point    = "CENTER",
    relPoint = "CENTER",
    x        = 0,
    y        = -220,
}

ns.DEFAULTS = {
    dbVersion  = 2,

    -- Bars: a grid of cells, each holding one spell from Blizzard's Cooldown
    -- Manager. Seeded once on first run and never re-seeded, so a deleted
    -- bar stays deleted.
    bars       = {},

    -- Parked with the 12.1 stack; kept so nothing is lost when it returns.
    groups     = {},

    -- Which auras to isolate, in priority order (first present one wins).
    spellIDs   = { ns.PRIMARY_SPELL_ID },

    mode       = "icon",     -- "icon" | "bar"
    locked     = true,

    -- Where the tracked aura comes from.
    --   "auto"  - engine aura slot when available, our own drawing otherwise
    --   "glow"  - never use the engine slot; drive everything off the proc
    -- The engine slot shows the REAL buff with real duration and stacks; the
    -- glow route is a proxy that cannot tell two procs on one button apart.
    source     = "auto",

    -- Icon mode
    iconSize   = 54,

    -- Bar mode
    barWidth   = 210,
    barHeight  = 26,

    scale      = 1.0,
    alpha      = 1.0,

    -- Keep the display on screen while the aura is down, greyed out.
    alwaysShow    = false,
    inactiveAlpha = 0.40,

    -- Route 5: the proc glow. glowSpellID is the spell whose action button
    -- lights up, which is NOT the buff itself - Boiling Point empowers Blood
    -- Boil (50842), so that is what glows. Duration is our own constant,
    -- because the game will not tell an addon how long a secret aura lasts.
    glowSpellID   = 50842,
    glowDuration  = 15,

    -- The remaining time is drawn by the engine's cooldown countdown; a
    -- secret expirationTime cannot be turned into text by an addon.
    showTimer  = true,
    showStacks = true,
    showName   = true,       -- bar mode only
    glow       = true,
    sound      = false,

    accent     = { 1.00, 0.44, 0.16 },  -- border / bar fill
    glowColor  = { 1.00, 0.62, 0.20 },

    -- Anchor, relative to UIParent only (no frame names in saved vars).
    point      = "CENTER",
    relPoint   = "CENTER",
    x          = 0,
    y          = -160,

    -- Minimap button. angle is degrees around the minimap centre.
    minimap = {
        show   = true,
        locked = false,
        angle  = 200,
    },

    -- Co-tank panel: one row per tank in the group.
    coTanks = {
        enabled     = true,
        includeSelf = true,
        onlyInGroup = true,   -- hide when playing solo
        locked      = true,

        width       = 240,
        rowHeight   = 22,
        iconSize    = 22,
        spacing     = 6,
        maxDebuffs  = 8,
        maxBuffs    = 8,
        scale       = 1.0,

        accent      = { 0.36, 0.62, 0.86 },

        point       = "CENTER",
        relPoint    = "CENTER",
        x           = -340,
        y           = 140,
    },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Recursive default fill: adds missing keys, never overwrites user values.
function ns.ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            ns.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function ns.Print(...)
    print("|cff7ec6d4DK|r|cffff7a3dstuff|r:", ...)
end

function ns.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

-- Resolves a spell name to its ID using the player's own client, so no spell
-- ID ever has to be hardcoded or guessed.
function ns.SpellIDByName(name)
    if not name or name == "" then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and info and info.spellID then return info.spellID end
    return nil
end

function ns.SpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.iconID
end

-- Font paths are read from live font objects, so no hardcoded path can break.
--
-- Two fonts, because they have different jobs. The number font is built for
-- digits over a busy 3D scene - tight, heavy, outlined - and it is the right
-- choice for a cooldown countdown on an icon. It is the wrong choice for
-- panel text, where it reads cramped and slightly wrong at every size. Panel
-- text uses the client's own UI font instead.
function ns.StyleFont(fontString, size, flags)
    local path = NumberFontNormalLarge:GetFont()
    fontString:SetFont(path, size, flags or "OUTLINE")
end

function ns.StyleUIFont(fontString, size, flags)
    local path = GameFontHighlight and GameFontHighlight:GetFont()
    if not path then path = NumberFontNormalLarge:GetFont() end
    fontString:SetFont(path, size, flags or "")
end

function ns.FormatTime(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    elseif remaining >= 10 then
        return string.format("%d", math.floor(remaining))
    end
    return string.format("%.1f", remaining)
end

-- One-pixel border built from color textures - no texture files, no library.
function ns.CreateBorder(frame, thickness, layer)
    local border = { thickness = thickness or 1 }
    local edges = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

    for _, edge in ipairs(edges) do
        border[edge] = frame:CreateTexture(nil, layer or "OVERLAY")
    end

    function border:SetColor(r, g, b, a)
        for _, edge in ipairs(edges) do
            self[edge]:SetColorTexture(r, g, b, a or 1)
        end
    end

    -- This is a plain table of four textures, not a frame, so it has none of
    -- the frame visibility methods by default - callers reasonably expect
    -- them, and their absence only shows up at runtime.
    function border:SetShown(shown)
        for _, edge in ipairs(edges) do
            self[edge]:SetShown(shown and true or false)
        end
    end

    function border:Show() self:SetShown(true) end
    function border:Hide() self:SetShown(false) end

    function border:SetThickness(t)
        self.thickness = t

        self.TOP:ClearAllPoints()
        self.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        self.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        self.TOP:SetHeight(t)

        self.BOTTOM:ClearAllPoints()
        self.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        self.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        self.BOTTOM:SetHeight(t)

        self.LEFT:ClearAllPoints()
        self.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -t)
        self.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, t)
        self.LEFT:SetWidth(t)

        self.RIGHT:ClearAllPoints()
        self.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -t)
        self.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, t)
        self.RIGHT:SetWidth(t)
    end

    border:SetThickness(border.thickness)
    border:SetColor(0, 0, 0, 1)
    return border
end

-- Creates the starter group, exactly once per saved-variables file. Guarded
-- by a flag rather than by "is the list empty", so a user who deletes every
-- group does not get one handed back at the next login.
function ns.SeedGroups()
    if ns.db.groupsSeeded then return end
    ns.db.groupsSeeded = true

    local seed = {}
    ns.ApplyDefaults(seed, ns.GROUP_DEFAULTS)
    seed.name = ns.SpellName(ns.PRIMARY_SPELL_ID) or "Tracker"
    seed.spells = {}
    for _, id in ipairs(ns.db.spellIDs) do
        seed.spells[#seed.spells + 1] = id
    end

    ns.db.groups[#ns.db.groups + 1] = seed
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")

boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        DKstuffDB = DKstuffDB or {}
        ns.db = ns.ApplyDefaults(DKstuffDB, ns.DEFAULTS)

        -- A wiped spell list would leave the addon silently doing nothing.
        if #ns.db.spellIDs == 0 then
            ns.db.spellIDs = { ns.PRIMARY_SPELL_ID }
        end

        ns.Bars:Seed()
        ns.Bars:Prepare()

    elseif event == "PLAYER_LOGIN" then
        -- Each feature boots on its own. They used to run in one straight
        -- line, so the first error took every later feature down with it -
        -- one broken tracking group meant no co-tank panel and no minimap
        -- button, which looks like "the whole addon is dead" and hides which
        -- part actually failed. Errors are reported, never swallowed.
        local function Boot(name, fn)
            local ok, err = pcall(fn)
            if not ok then
                ns.Print("|cffff4040" .. name .. " failed to start.|r Everything else still runs.")
                geterrorhandler()(err)
            end
            return ok
        end

        Boot("Display", function()
            ns.Display:Create()
            ns.Display:ApplyLayout()
        end)
        Boot("Watcher", function() ns.Watcher:Start() end)
        Boot("Cooldown Manager", function() ns.CDM:HookPools() end)
        Boot("Minimap button", function() ns.MinimapButton:Create() end)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ToNumber(value, min, max)
    local n = tonumber(value)
    if not n then return nil end
    if min and n < min then n = min end
    if max and n > max then n = max end
    return n
end

local usage = {
    "|cff7ec6d4DK|r|cffff7a3dstuff|r - commands:",
    "  |cffffd100/dks|r - open the settings window",
    "  |cffffd100/dks unlock|r / |cffffd100lock|r - move the display",
    "  |cffffd100/dks test|r - 15s preview so you can position it",
    "  |cffffd100/dks icon|r / |cffffd100bar|r - switch display mode",
    "  |cffffd100/dks size <n>|r - icon size",
    "  |cffffd100/dks width <n>|r / |cffffd100height <n>|r - bar size",
    "  |cffffd100/dks scale <n>|r - overall scale",
    "  |cffffd100/dks add <spellID>|r / |cffffd100remove <spellID>|r / |cffffd100list|r",
    "  |cffffd100/dks check <spellID>|r - is that aura findable right now?",
    "  |cffffd100/dks status|r - what is tracked and what is active",
    "  |cffffd100/dks scan|r - list the buffs an addon is allowed to read",
    "  |cffffd100/dks dump|r - full diagnosis, run it WHILE the buff is up",
    "  |cffffd100/dks glowlog|r - log every proc glow, to find the right spell ID",
    "  |cffffd100/dks glow <spellID>|r - drive the display off that proc glow",
    "  |cffffd100/dks glowduration <s>|r - how long the proc lasts (default 15)",
    "  |cffffd100/dks source engine|r / |cffffd100glow|r - real buff vs. proc proxy",
    "  |cffffd100/dks bars|r - list your bars (|cffffd100add <name>|r / |cffffd100remove <n>|r)",
    "  |cffffd100/dks cdm|r - what Blizzard's Cooldown Manager currently holds",
    "  |cffffd100/dks reset|r - restore defaults",
}

SLASH_DKSTUFF1 = "/dks"
SLASH_DKSTUFF2 = "/dkstuff"

SlashCmdList.DKSTUFF = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    local db = ns.db

    if cmd == "" then
        ns.Options:Toggle()

    elseif cmd == "unlock" or cmd == "lock" then
        ns.Display:SetUnlocked(cmd == "unlock")

    elseif cmd == "test" then
        ns.Display:StartTest()

    elseif cmd == "icon" or cmd == "bar" then
        db.mode = cmd
        ns.Display:ApplyLayout()

    elseif cmd == "size" then
        db.iconSize = ToNumber(rest, 20, 200) or db.iconSize
        ns.Display:ApplyLayout()

    elseif cmd == "width" then
        db.barWidth = ToNumber(rest, 60, 600) or db.barWidth
        ns.Display:ApplyLayout()

    elseif cmd == "height" then
        db.barHeight = ToNumber(rest, 10, 80) or db.barHeight
        ns.Display:ApplyLayout()

    elseif cmd == "scale" then
        db.scale = ToNumber(rest, 0.4, 3.0) or db.scale
        ns.Display:ApplyLayout()

    elseif cmd == "add" then
        local id = ToNumber(rest)
        if id then
            ns.Watcher:AddSpell(id)
        else
            ns.Print("Usage: /dks add <spellID>")
        end

    elseif cmd == "remove" or cmd == "rem" then
        local id = ToNumber(rest)
        if id then
            ns.Watcher:RemoveSpell(id)
        else
            ns.Print("Usage: /dks remove <spellID>")
        end

    elseif cmd == "check" then
        local id = ToNumber(rest)
        if id then
            ns.Watcher:Check(id)
        else
            ns.Watcher:Check(db.spellIDs[1] or ns.PRIMARY_SPELL_ID)
        end

    elseif cmd == "status" then
        ns.Watcher:Status()

    elseif cmd == "scan" then
        ns.Watcher:Scan()

    elseif cmd == "dump" then
        ns.Watcher:Dump()

    elseif cmd == "minimap" then
        local sub = rest:lower()
        if sub == "on" or sub == "show" then
            ns.MinimapButton:SetShown(true)
        elseif sub == "off" or sub == "hide" then
            ns.MinimapButton:SetShown(false)
        elseif sub == "lock" or sub == "unlock" then
            db.minimap.locked = (sub == "lock")
            ns.Print("Minimap button", db.minimap.locked and "locked" or "unlocked")
        else
            ns.MinimapButton:SetShown(not db.minimap.show)
        end

    elseif cmd == "source" then
        local sub = rest:lower()
        if sub == "engine" or sub == "auto" then
            db.source = "auto"
        elseif sub == "glow" then
            db.source = "glow"
        else
            ns.Print("Usage: |cffffd100/dks source engine|r  or  |cffffd100/dks source glow|r")
            ns.Print("Current:", db.source == "glow" and "glow (proxy)" or "engine slot",
                "| engine available:",
                (ns.Engine and ns.Engine:IsAvailable()) and "|cff40ff40yes|r"
                or "|cffff4040no - needs patch 12.1|r")
            return
        end
        ns.Display:ApplyLayout()
        ns.Print("Aura source:", db.source == "glow" and "proc glow" or "engine slot")

    elseif cmd == "cdm" then
        ns.CDM:Dump()

    elseif cmd == "bars" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()

        if sub == "add" then
            local index = ns.Bars:Add(arg ~= "" and arg or nil, "icon")
            ns.Print("Added bar", index, "-", ns.Bars:Get(index).name)
        elseif sub == "remove" or sub == "rem" then
            local index = ToNumber(arg)
            if index and ns.Bars:Remove(index) then
                ns.Print("Removed bar", index)
            else
                ns.Print("Usage: |cffffd100/dks bars remove <number>|r")
            end
        else
            if ns.Bars:Count() == 0 then
                ns.Print("No bars yet - open |cffffd100/dks|r and press New icon bar.")
            end
            for i, cfg in ipairs(ns.Bars:All()) do
                local filled = 0
                for cell = 1, ns.Bars:CellCount(cfg) do
                    if cfg.cells[cell] then filled = filled + 1 end
                end
                ns.Print(string.format("%d. %s |cff888888(%s, %dx%d, %d filled)|r%s",
                    i, cfg.name, cfg.kind, cfg.rows, cfg.columns, filled,
                    cfg.enabled and "" or " |cffff4040disabled|r"))
            end
        end

    elseif cmd == "glowlog" then
        ns.Watcher:ToggleGlowLog()

    elseif cmd == "glow" then
        if rest == "off" or rest == "none" then
            ns.Watcher:SetGlowSpell(nil)
        else
            -- Accepts a spell ID or a spell name; the name is resolved by the
            -- client, so nothing has to be hardcoded.
            local id = ToNumber(rest) or ns.SpellIDByName(rest)
            if id then
                ns.Watcher:SetGlowSpell(id)
            elseif rest ~= "" then
                ns.Print("Could not resolve |cffffd100" .. rest .. "|r to a spell.")
                ns.Print("Try the numeric ID from |cffffd100/dks glowlog|r.")
            else
                ns.Print("Usage: |cffffd100/dks glow Blood Boil|r  or  |cffffd100/dks glow <spellID>|r  or  |cffffd100/dks glow off|r")
            end
        end

    elseif cmd == "glowduration" then
        db.glowDuration = ToNumber(rest, 1, 120) or db.glowDuration
        ns.Print("Proc duration set to", db.glowDuration, "seconds.")

    elseif cmd == "list" then
        for _, id in ipairs(db.spellIDs) do
            ns.Print(id, "-", ns.SpellName(id) or "|cff888888unknown to the client|r")
        end

    elseif cmd == "reset" then
        DKstuffDB = {}
        ns.db = ns.ApplyDefaults(DKstuffDB, ns.DEFAULTS)
        ns.Bars:Seed()
        ns.Bars:Prepare()
        ns.Display:ApplyLayout()
        ns.Watcher:RebuildTracked()
        ns.Bars:Changed()
        if ns.Options.Refresh then ns.Options:Refresh() end
        ns.Print("Settings reset to defaults.")

    else
        for _, line in ipairs(usage) do print(line) end
    end
end

function DKstuff_OnAddonCompartmentClick()
    ns.Options:Toggle()
end
