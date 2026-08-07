---------------------------------------------------------------------------
-- ZwoelfStuff - your own cooldown bars, built on Blizzard's Cooldown Manager.
--
-- Spells go in a grid you arrange, and every bar is styled on its own. What
-- the Cooldown Manager carries is adopted rather than redrawn; what it does
-- NOT carry - auras like Boiling Point, which is not in the C_CooldownViewer
-- data set and can never be added to it - is recorded and drawn by us.
--
-- This file: namespace, defaults, saved variables, shared helpers, commands.
---------------------------------------------------------------------------
local ADDON, ns = ...

ns.ADDON = ADDON
ns.version = "4.11.0"

-- The addon's own mark, used by the minimap button. Kept next to the TOC's
-- IconTexture line so the two cannot drift apart.
ns.ICON_TEXTURE = "Interface\\AddOns\\ZwoelfStuff\\Media\\logo"

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
    -- 3: the puzzle got its own two coordinate fields. Before that a cell's
    --    x/y meant a position in the puzzle and a nudge everywhere else, and
    --    switching arrangement silently reinterpreted one as the other.
    -- 4: Arc and Diagonal removed; bars on either move onto Grid.
    -- 5: the one fill setting becomes two - which END the fill sits at, and
    --    whether it grows or drains. They were shipped as one and the label
    --    described the half that was not implemented.
    -- 6: the spells on a bar move to a per-class-and-spec table.
    -- 7: EVERY setting moves under the character it was made on. See
    --    ns.OpenProfile - the owner's rule is that a change to the UI belongs
    --    to the character and realm that made it, and no keying by class or
    --    spec can stop two characters of one class overwriting each other.
    --    Version 6 is therefore now a split INSIDE one character's profile:
    --    the spec you are in decides which spells its bars hold.
    -- See Bars:Migrate.
    dbVersion  = 7,

    -- Bars: a grid of cells, each holding one spell from Blizzard's Cooldown
    -- Manager. Seeded once on first run and never re-seeded, so a deleted
    -- bar stays deleted.
    bars       = {},

    -- Saved looks, by name. A preset carries ns.BAR_STYLE_KEYS only - sizes,
    -- spacing and colours - never the spells or the grid shape.
    barPresets = {},

    -- Highest bar id handed out so far. Ids are never reused, because an
    -- anchor points at one and a recycled id would silently re-attach a bar
    -- to whatever took the old one's place.
    lastBarID  = 0,

    -- The recorded procs, the hand-made aura links and the list of shipped
    -- procs somebody threw away are NOT here. They are measurements, shared
    -- by every character on the account - see ns.OpenProfile and
    -- ACCOUNT_DEFAULTS below, and ns.account.* is how they are read.

    -- The font every piece of text on every bar uses unless that one piece
    -- has been given its own. One place to change it, and no need to visit
    -- three sections on four bars to change a typeface.
    font       = "Friz Quadrata TT",

    -- Whether the bars REPLACE Blizzard's Cooldown Manager display or sit
    -- next to it. On by default, and the setting says what off costs: taking
    -- a cooldown onto our bar leaves a hole in Blizzard's row, because its
    -- layout does not know the frame moved. See Core/Screen.lua.
    takeOverCDM = true,

    -- How unlock and build mode behave. Saved rather than reset each time,
    -- because these are working habits: somebody who arranges on a 20-pixel
    -- grid with snapping off wants that again tomorrow, and re-setting it at
    -- the top of every session is the kind of small tax that makes a tool
    -- feel like it is not on your side.
    editMode = {
        grid         = false,
        gridStep     = 40,
        snap         = true,
        snapDistance = 10,
        snapToGrid   = false,
        dim          = 0.35,
        showCoords   = false,
    },

    -- Parked with the 12.1 stack; kept so nothing is lost when it returns.
    groups     = {},

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
    print("|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r:", ...)
end

---------------------------------------------------------------------------
-- Which class and spec is playing
--
-- "DEATHKNIGHT:250". The key everything per-character is filed under: the
-- recorded procs, and since 4.10.0 the spells on each bar as well.
--
-- Returns the key AND whether the spec is really known. Right after login the
-- API can answer 0 for a while, and filing anything under "DEATHKNIGHT:0" is
-- how a character's picks end up somewhere nothing will ever look for them.
-- Callers that WRITE have to check the second value; callers that read do not.
---------------------------------------------------------------------------
local specKey, specKnown

function ns.SpecKey()
    if specKnown then return specKey, true end

    local _, class = UnitClass("player")
    if not class then return nil, false end

    local specID = 0
    local info = C_SpecializationInfo
    if info and info.GetSpecialization and info.GetSpecializationInfo then
        local ok, index = pcall(info.GetSpecialization)
        if ok and index then
            local okID, id = pcall(info.GetSpecializationInfo, index)
            if okID and id then specID = id end
        end
    end

    specKey = class .. ":" .. specID
    specKnown = specID ~= 0
    return specKey, specKnown
end

-- A spec change makes the cached answer wrong, and nothing else does.
function ns.ForgetSpecKey()
    specKey, specKnown = nil, nil
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

-- Has the character got this spell in the build it is in right now?
--
-- C_SpellBook.IsSpellKnownOrInSpellBook, not the older IsPlayerSpell that the
-- reference CDM picker still calls: that one is flagged deprecated, and
-- BigWigs on this client already uses the current form. It touches no aura
-- data, so it is legal on 12.0.
--
-- A missing API means "assume known": greying out everything would be far
-- worse than greying out nothing.
function ns.IsSpellKnown(spellID)
    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
    if not (isKnown and spellID) then return true end
    local ok, known = pcall(isKnown, spellID)
    if not ok then return true end
    return known and true or false
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

-- Every font string inside a widget, styled with the number font. Used on
-- Blizzard's cooldown countdown, which has no stable name - it is simply a
-- region of the Cooldown widget, so it is found rather than looked up.
--
-- anchor moves the text off centre. Blizzard's engine sets its own baseline
-- for the countdown, so ours is applied on top rather than instead - which
-- also means an anchor of CENTER is left alone, because that is already
-- where the engine puts it and re-anchoring it can only go wrong.
function ns.StyleNumbers(widget, text)
    if not (widget and text) then return end

    for _, region in ipairs({ widget:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            ns.Media.ApplyFont(region, text.font, text.size, text.outline,
                text.color)

            -- Left alone at CENTER with no offset: that is already where
            -- Blizzard's engine puts its countdown, and re-anchoring it can
            -- only go wrong. Anywhere else we have to say so ourselves.
            if text.anchor ~= "CENTER" or text.x ~= 0 or text.y ~= 0 then
                local inset = 2
                local x = (text.anchor:find("LEFT") and inset
                    or text.anchor:find("RIGHT") and -inset or 0) + text.x
                local y = (text.anchor:find("TOP") and -inset
                    or text.anchor:find("BOTTOM") and inset or 0) + text.y
                region:ClearAllPoints()
                region:SetPoint(text.anchor, widget, text.anchor, x, y)
            end
        end
    end
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

-- Creates the starter group for the parked 12.1 tracking-group module,
-- exactly once per saved-variables file. Guarded by a flag rather than by "is
-- the list empty", so a user who deletes every group does not get one handed
-- back at the next login.
function ns.SeedGroups()
    if ns.db.groupsSeeded then return end
    ns.db.groupsSeeded = true

    local seed = {}
    ns.ApplyDefaults(seed, ns.GROUP_DEFAULTS)
    seed.name = ns.SpellName(ns.PRIMARY_SPELL_ID) or "Tracker"
    seed.spells = { ns.PRIMARY_SPELL_ID }

    ns.db.groups[#ns.db.groups + 1] = seed
end

---------------------------------------------------------------------------
-- WHOSE SETTINGS THESE ARE
--
-- Owner, 2026-08-07: "mach ich eine änderung am ui oder egal was, muss das
-- unter dem charakter namen und server gespeichert werden".
--
-- So the file holds one profile per character, keyed "Name - Realm" - the
-- same key EllesmereUI uses on this client, verified rather than invented.
-- Everything you can change is in there: the bars, their looks, where they
-- sit, the font, unlock-mode habits, the minimap button.
--
-- WHAT STAYS SHARED, and it is not a UI setting: the recorded procs, the
-- aura links and the list of shipped procs somebody threw away. Those are
-- MEASUREMENTS - hours of playing to collect, identical for anyone of that
-- class and spec, and impossible to type back in. Filing them per character
-- would make every alt start the recording again from nothing.
--
-- The owner's own reason for the split, verbatim: "sonst wird das pro klasse
-- oder spec ja jedes mal überschrieben". Two characters of one class were
-- writing over each other, and no keying by class or spec can fix that -
-- only keying by the character.
---------------------------------------------------------------------------
function ns.CharacterKey()
    local name = UnitName("player")
    if not name then return nil end
    local realm = GetRealmName and GetRealmName() or ""
    return name .. " - " .. realm
end

-- The measurements, shared by every character on the account.
local ACCOUNT_DEFAULTS = {
    procs       = {},
    auraLinks   = {},
    procsHidden = {},
}

function ns.OpenProfile()
    local store = ZwoelfStuffDB

    -- A file written before profiles existed: everything in it belonged to
    -- whoever was playing, so it becomes that character's profile and the
    -- measurements are lifted out to the account.
    if store.chars == nil then
        local old = {}
        for key, value in pairs(store) do
            old[key] = value
            store[key] = nil
        end

        store.account = {}
        for key in pairs(ACCOUNT_DEFAULTS) do
            store.account[key] = old[key]
            old[key] = nil
        end

        store.chars = {}
        local key = ns.CharacterKey()
        if key and next(old) then store.chars[key] = old end
    end

    store.account = ns.ApplyDefaults(store.account or {}, ACCOUNT_DEFAULTS)
    ns.account = store.account

    local key = ns.CharacterKey() or "unknown"
    store.chars[key] = store.chars[key] or {}
    ns.db = ns.ApplyDefaults(store.chars[key], ns.DEFAULTS)
    ns.profileKey = key
end

-- Every other character with a profile, newest list built on demand because
-- it changes whenever somebody else logs out.
function ns.OtherProfiles()
    local out = {}
    if not (ZwoelfStuffDB and ZwoelfStuffDB.chars) then return out end

    for key, profile in pairs(ZwoelfStuffDB.chars) do
        if key ~= ns.profileKey and type(profile) == "table" then
            out[#out + 1] = { key = key, bars = #(profile.bars or {}) }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")

boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ZwoelfStuffDB = ZwoelfStuffDB or {}
        ns.OpenProfile()

        -- Before Seed and before Prepare: everything below this line reads a
        -- bar, and a migration that runs after the first read is a migration
        -- that fixed nothing.
        ns.Bars:Migrate()
        ns.Bars:Seed()
        ns.Bars:Prepare()

        -- Auras deliberately has no seeding step, and calling one here used to
        -- throw on every login. Its recorder registers itself when the file
        -- loads, and the shipped procs are merged when the list is READ -
        -- copying them into saved variables would freeze today's data into
        -- every profile and make the next update invisible.

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

        Boot("Cooldown Manager", function()
            ns.CDM:HookPools()
            -- The spell list is a live view of the Cooldown Manager, so a
            -- talent or spec change has to reach an open window.
            ns.CDM:OnChanged(function() ns.Options:OnCatalogChanged() end)
        end)
        -- After the Cooldown Manager, and not before: the first render claims
        -- Blizzard's item frames, and there is nothing to claim until its
        -- pools have been walked once.
        Boot("Bars", function() ns.Screen:Start() end)
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

-- Only commands that exist. A usage list that offers a command the addon no
-- longer has is worse than no list: it sends people looking for a feature.
local usage = {
    "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r - commands:",
    "  |cffffd100/zs|r - open the window",
    "  |cffffd100/zs unlock|r / |cffffd100lock|r - move the bars around the screen",
    "  |cffffd100/zs build|r - take a bar apart slot by slot, on screen",
    "",
    "  Bars",
    "  |cffffd100/zs bars|r - list them (|cffffd100add <name>|r / |cffffd100remove <n>|r)",
    "  |cffffd100/zs cdm|r - what Blizzard's Cooldown Manager currently holds",
    "  |cffffd100/zs skin|r - what is actually drawn on one adopted icon",
    "",
    "  Auras",
    "  |cffffd100/zs auras|r - the procs seen on this spec, and what drives them",
    "  |cffffd100/zs auras export|r - hand this spec's set back so it ships",
    "  |cffffd100/zs auras icon <glowID> <spellID>|r - which icon a proc shows",
    "  |cffffd100/zs auras bind <glowID> <auraID>|r - name the buff (12.1 route)",
    "  |cffffd100/zs auras forget <glowID>|r - drop one, shipped ones included",
    "  |cffffd100/zs auras remember|r - put every forgotten one back",
    "",
    "  |cffffd100/zs test|r - run the addon's own checks and report failures",
    "  |cffffd100/zs minimap|r - show or hide the minimap button",
    "  |cffffd100/zs reset|r - restore defaults, keeping recorded procs",
}

SLASH_ZWOELFSTUFF1 = "/zs"
SLASH_ZWOELFSTUFF2 = "/zwoelfstuff"

SlashCmdList.ZWOELFSTUFF = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    local db = ns.db

    if cmd == "" then
        ns.Options:Toggle()

    elseif cmd == "unlock" or cmd == "lock" then
        ns.EditMode:SetUnlocked(cmd == "unlock")

    elseif cmd == "build" then
        -- Unlocks first if it has to. "Build" names an intent, not a mode you
        -- have to be in something else to reach.
        ns.EditMode:OpenBuild()

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

    elseif cmd == "cdm" then
        ns.CDM:Dump()

    elseif cmd == "skin" then
        ns.Screen:DumpCells()
        ns.CDM:DumpSkin()

    elseif cmd == "test" then
        ns.SelfTest:Run()

    elseif cmd == "auras" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()

        -- The numbers, wherever they sit in the argument. Anchoring the match
        -- to the whole string meant a pasted line with a note after the ID
        -- ("49020  Obliterate") was rejected as "no number given", which reads
        -- as the command being broken rather than the paste being untidy.
        local first, second = arg:match("(%d+)%D+(%d+)")
        if not first then first = arg:match("(%d+)") end

        if sub == "export" then
            ns.Auras:Export()

        elseif sub == "bind" then
            -- Two IDs: the ability that lights up, then the aura itself.
            if first and second then
                ns.Auras:SetAura(tonumber(first), tonumber(second))
            else
                ns.Print("Usage: |cffffd100/zs auras bind <glowID> <auraID>|r")
                ns.Print("The first is the ability whose button lights up, the second")
                ns.Print("is the buff itself - only patch 12.1 needs the second one.")
            end

        elseif sub == "icon" then
            if first and second then
                ns.Auras:SetDisplay(tonumber(first), tonumber(second))
            else
                ns.Print("Usage: |cffffd100/zs auras icon <glowID> <spellID>|r")
            end

        elseif sub == "remember" then
            ns.Auras:Remember()

        elseif sub == "forget" then
            local id = tonumber(first)
            if not id then
                ns.Print("Usage: |cffffd100/zs auras forget <glowID>|r")
                ns.Print("|cffffd100/zs auras remember|r puts every forgotten one back.")
            elseif not ns.Auras:Forget(id) then
                ns.Print("No proc recorded on", id, "for this spec.")
                ns.Print("The ID is the one on the RIGHT in |cffffd100/zs auras|r - "
                    .. "the ability that lights up, not the icon shown.")
            end

        else
            ns.Auras:Dump()
        end

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
                ns.Print("Usage: |cffffd100/zs bars remove <number>|r")
            end
        else
            if ns.Bars:Count() == 0 then
                ns.Print("No bars yet - open |cffffd100/zs|r and press New icon bar.")
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

    elseif cmd == "reset" then
        -- Recorded procs survive. They are measurements that took hours of
        -- playing to collect and cannot be typed back in, so they are not
        -- "settings" - /zs auras forget is how those go away.
        local procs = ns.account.procs
        ZwoelfStuffDB = {}
        ns.db = ns.ApplyDefaults(ZwoelfStuffDB, ns.DEFAULTS)
        ns.account.procs = procs or ns.account.procs
        ns.Bars:Seed()
        ns.Bars:Prepare()
        ns.Auras:Invalidate()
        ns.Bars:Changed()
        if ns.Options.Refresh then ns.Options:Refresh() end
        ns.Print("Settings reset to defaults. Recorded procs kept.")

    else
        for _, line in ipairs(usage) do print(line) end
    end
end

function ZwoelfStuff_OnAddonCompartmentClick()
    ns.Options:Toggle()
end
