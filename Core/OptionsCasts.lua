---------------------------------------------------------------------------
-- OptionsCasts.lua - the "Casts on you" page.
--
-- Three tabs on the answer page's shape, because it is the same idea from
-- the same end: a surface, a book of alerts about it, and the voice that
-- speaks them.
--
--   Bar     what the bar shows and which casts count at all
--   Alerts  the reminders page, on ns.CastAlerts (third instance of the
--           class - Core/OptionsReminders.lua's editor does all of it)
--   Voice   what is said out loud, and by whom
--
-- THE THIRD COLUMN is the mobs you have met, filed under the instance you
-- met them in - owner, 2026-08-18, with two screenshots of EXBoss's Trash CD
-- page: "rechte leiste alle mobs und buster nach dungon / raids sortiert.
-- schoen mit icons, namen etc." It cannot be a list of SPELLS, because on
-- 12.x a cast's id is a secret value and a list of ids could never be
-- matched against what is in front of you (the header of Core/Casts.lua has
-- the whole argument, with the code that proves it). It is a list of
-- CASTERS, which are readable, and clicking one is a filter that works.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI
local C = UI.C

local Page = {}
ns.OptionsCasts = Page

---------------------------------------------------------------------------
-- THE ALERTS EDITOR - the reminders page on the cast alerts' book
--
-- Its spec says only what differs from a reminder: a reminder watches a
-- spell, and an alert here watches a KIND of cast, so the "What it watches"
-- slot has nothing to hold and the trigger block is two sets of chips.
---------------------------------------------------------------------------
local ALERT_SPEC = {
    prefix    = "ca",
    intro     = "A line on your screen while a mob is casting - \"A "
        .. "lieutenant casting at you\". It says who is casting, how "
        .. "dangerous they are, and whether it is coming at you.",
    newLabel  = "New alert",
    full      = "Twelve alerts is the lot",
    emptyHint = "Nothing selected. Press New alert.",
    -- No sound row: the voice below is this book's noise, and two ways to
    -- make a sound for one event is the setting nobody can explain.
    sound     = nil,

    -- WHAT IT WATCHES, in place of the reminders' spell slot.
    Trigger = function(_, grid, Body, Get, Set, Apply)
        grid:Section("Which casts this one watches", "ca-what", true)

        for _, rank in ipairs(ns.Casts.RANKS) do
            local key = rank.key
            Body(UI.Toggle(
                grid:FullRow(rank.text, {
                    sublabel = rank.note, controlWidth = 124 }),
                function()
                    local cfg = select(2, ns.OptionsCastAlerts:Current())
                    if not cfg then return false end
                    return type(cfg.ranks) ~= "table" or cfg.ranks[key] == true
                end,
                function(value)
                    local cfg = select(2, ns.OptionsCastAlerts:Current())
                    if not cfg then return end
                    cfg.ranks = cfg.ranks or {}
                    cfg.ranks[key] = value and true or false
                    Apply()
                end))
        end

        grid:Note("A mob's rank is its level: the rank and file, the named "
            .. "ones between bosses, and bosses. That is how the boss mods "
            .. "tell them apart too.")

        grid:Section("Who it is aimed at", "ca-aim", true)

        for _, aim in ipairs(ns.Casts.AIMS) do
            local key = aim.key
            Body(UI.Toggle(
                grid:FullRow(aim.text, { controlWidth = 124 }),
                function()
                    local cfg = select(2, ns.OptionsCastAlerts:Current())
                    if not cfg then return false end
                    return type(cfg.aims) ~= "table" or cfg.aims[key] == true
                end,
                function(value)
                    local cfg = select(2, ns.OptionsCastAlerts:Current())
                    if not cfg then return end
                    cfg.aims = cfg.aims or {}
                    cfg.aims[key] = value and true or false
                    Apply()
                end))
        end

        grid:Note("Inside a dungeon the target is sometimes not named; "
            .. "those casts count as |cffffd100At somebody the game will "
            .. "not name|r. Leave that one on unless you would rather miss "
            .. "a warning than see a spare one.")

        grid:Section("Only these mobs", "ca-mobs", false)

        local mobNote = grid:Note("")
        mobNote.Refresh = function()
            local cfg = select(2, ns.OptionsCastAlerts:Current())
            local count = ns.Casts.PickedCount(cfg and cfg.mobs)
            if count == 0 then
                mobNote:SetText("Every mob. Click one in the list on the "
                    .. "right to narrow this alert to it.")
            else
                mobNote:SetText(("%d mob%s picked - this alert is quiet for "
                    .. "everything else. Click a picked one again to drop "
                    .. "it."):format(count, count == 1 and "" or "s"))
            end
        end

        local clearRow = grid:FullRow("Watch every mob again",
            { controlWidth = 124 })
        Body(clearRow)
        local clear = UI.Button(clearRow.slot, "Clear", 84, function()
            local cfg = select(2, ns.OptionsCastAlerts:Current())
            if not cfg then return end
            cfg.mobs = nil
            ns.OptionsCasts:Refresh()
        end, "quiet")
        clear:SetPoint("RIGHT", clearRow.slot, "RIGHT", 0, 0)

        grid:Section("What it says out loud", "ca-voice", false)

        local voiceRow = grid:FullRow("This alert's line",
            { controlWidth = 190 })
        Body(voiceRow)
        local voice = UI.Input(voiceRow.slot, 190, function(text)
            local cfg = select(2, ns.OptionsCastAlerts:Current())
            if not cfg then return end
            cfg.voice = text or ""
            Apply()
        end, false, "leave empty for the module's line")
        voice:SetPoint("RIGHT", voiceRow.slot, "RIGHT", 0, 0)

        grid:Note("Spoken when this alert appears, if the voice on the Voice "
            .. "tab is switched on. Empty means the line that tab has for "
            .. "the mob's rank.")

        return function(cfg)
            mobNote.Refresh()
            if voice.SetText and not (voice.HasFocus and voice:HasFocus()) then
                voice:SetText(cfg.voice or "")
            end
        end
    end,

    StateLine = function(book, cfg)
        local state, why = book:State(cfg)
        if not state then
            return "Cannot tell - " .. (why or "no reason given")
        end
        if state == "casting" then return "Something it watches is casting." end
        return "Nothing it watches is casting."
    end,
}

ns.OptionsCastAlerts = ns.RemindersEditor.New(ns.CastAlerts, ALERT_SPEC)

---------------------------------------------------------------------------
-- Shorthands, the same five every page in this addon defines
---------------------------------------------------------------------------
local function Cfg() return ns.Casts.Config() end
local function Bar() return ns.Casts.Config().bar end
local function Voice() return ns.Casts.Config().voice end

local function Apply()
    ns.CastBar:ApplyLayout()
    ns.CastBar:Refresh()
end

local function BarGet(key, fallback)
    return function()
        local value = Bar()[key]
        if value == nil then return fallback end
        return value
    end
end

local function BarSet(key)
    return function(value)
        Bar()[key] = value
        Apply()
    end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local STAGE_H = 96
local BAND_HEAD = 32
local STRIP_GAP = 8

function Page:BuildPage(page, width)
    local grid = UI.Page(page, width, { tooltipNotes = true, sticky = true })

    ---------------------------------------------------------------------
    -- THE BAND: the bar itself, live, above the tabs
    --
    -- THE PREVIEW IS THE REAL BAR, reparented - the rule this addon has
    -- broken once and written down twice (Core/OptionsCoTanks.lua:10-16,
    -- Core/OptionsReminders.lua:16-22). A second drawing of a bar would
    -- drift from the one on screen the first time either changed.
    ---------------------------------------------------------------------
    local band = grid.sticky
    UI.Fill(band, "BACKGROUND", C.windowBg)

    local bandTitle = UI.Eyebrow(band, "The bar, as it is right now")
    bandTitle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -10)

    local host = CreateFrame("Frame", nil, band)
    host:SetPoint("TOPLEFT", band, "TOPLEFT", 0, -BAND_HEAD)
    host:SetPoint("TOPRIGHT", band, "TOPRIGHT", -14, -BAND_HEAD)
    host:SetHeight(STAGE_H - 34)
    self.stage = host

    -- AN EMPTY BAND READS AS BROKEN. With the module off the bar refuses
    -- to draw, so the band says why instead of showing a void.
    local stageHint = UI.Hint(host, "The module is off - switch it on to "
        .. "see the bar.")
    stageHint:SetPoint("CENTER", host, "CENTER", 0, 0)
    stageHint:Hide()
    self.stageHint = stageHint

    local strip
    strip = UI.TabStrip(band, { "Bar", "Alerts", "Voice" }, function(name)
        grid:ShowTab(name)
        strip:Select(name)
    end)
    strip:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, STRIP_GAP)
    strip:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, STRIP_GAP)
    grid.strip = strip

    band.Fit = function()
        band:SetHeight(BAND_HEAD + host:GetHeight() + 10 + 34 + STRIP_GAP)
        strip:Layout()
    end
    band.Fit()

    ---------------------------------------------------------------------
    grid:Tab("Bar")

    -- SAID BEFORE ANYTHING ELSE ON THE PAGE. The badge beside the title
    -- carries it on every tab; this is the sentence that says what "coming
    -- soon" actually means for somebody standing here with the switch in
    -- their hand.
    grid:Note("|cffffd100Beta.|r Every part of it works and none of it "
        .. "has been through a real week of dungeons. It stays switched off "
        .. "until you switch it on, and nothing here runs while it is off. "
        .. "If something is wrong with it, say so on the Discord.")

    grid:Note("What the mob in front of you is casting, on a bar where you "
        .. "are already looking. To put it somewhere, open |cffffd100Edit "
        .. "mode|r at the top of the list on the left.")

    grid:Section("Which casts count")

    for _, rank in ipairs(ns.Casts.RANKS) do
        local key = rank.key
        UI.Toggle(grid:FullRow(rank.text,
            { sublabel = rank.note, controlWidth = 124 }),
            function()
                local ranks = Cfg().ranks
                return type(ranks) ~= "table" or ranks[key] == true
            end,
            function(value)
                local cfg = Cfg()
                cfg.ranks = cfg.ranks or {}
                cfg.ranks[key] = value and true or false
                ns.Casts:Scan()
                Apply()
            end)
    end

    grid:Note("The bar shows the cast's |cffffd100icon|r, its length and "
        .. "whether it can be kicked - all straight from the game. The mark "
        .. "above the bar means it is aimed at you.")

    grid:Section("Who it is aimed at")

    for _, aim in ipairs(ns.Casts.AIMS) do
        local key = aim.key
        UI.Toggle(grid:FullRow(aim.text, { controlWidth = 124 }),
            function()
                local aims = Cfg().aims
                return type(aims) ~= "table" or aims[key] == true
            end,
            function(value)
                local cfg = Cfg()
                cfg.aims = cfg.aims or {}
                cfg.aims[key] = value and true or false
                ns.Casts:Scan()
                Apply()
            end)
    end

    grid:Section("How it looks", "ca-look")

    UI.Toggle(grid:FullRow("Show the bar", { controlWidth = 124 }),
        BarGet("enabled", true), BarSet("enabled"))

    UI.MediaPicker(grid:FullRow("Texture",
        { controlWidth = 190, icon = "media-texture" }), "statusbar",
        BarGet("texture", "ZS Smooth"), BarSet("texture"), Apply)

    UI.Slider(grid:FullRow("Width", { controlWidth = 124 }), {
        get = BarGet("width", 260), set = BarSet("width"),
        min = 80, max = 600, step = 5, apply = Apply })

    UI.Slider(grid:FullRow("Height", { controlWidth = 124 }), {
        get = BarGet("height", 26), set = BarSet("height"),
        min = 8, max = 60, step = 1, apply = Apply })

    UI.Slider(grid:FullRow("Scale", { controlWidth = 124 }), {
        get = BarGet("scale", 1), set = BarSet("scale"),
        min = 0.5, max = 2.5, step = 0.05, apply = Apply,
        format = function(value) return string.format("%.2f", value) end })

    UI.Swatch(grid:FullRow("Colour", { controlWidth = 124 }),
        function()
            local colour = Bar().color or { 0.8, 0.24, 0.2 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Bar().color = { r, g, b } end, Apply)

    UI.Swatch(grid:FullRow("When it cannot be kicked",
        { controlWidth = 124 }),
        function()
            local colour = Bar().uninterruptibleColor or { 0.45, 0.45, 0.52 }
            return colour[1], colour[2], colour[3]
        end,
        function(r, g, b) Bar().uninterruptibleColor = { r, g, b } end, Apply)

    grid:Note("Which of the two you are looking at is decided by the game.")

    UI.Toggle(grid:FullRow("Icon", { controlWidth = 124 }),
        BarGet("showIcon", true), BarSet("showIcon"))

    UI.Slider(grid:FullRow("Icon size", { controlWidth = 124 }), {
        get = BarGet("iconSize", 26), set = BarSet("iconSize"),
        min = 10, max = 64, step = 1, apply = Apply })

    UI.Toggle(grid:FullRow("The spell's name", { controlWidth = 124 }),
        BarGet("showName", true), BarSet("showName"))

    UI.Toggle(grid:FullRow("Who it is aimed at", { controlWidth = 124 }),
        BarGet("showTarget", true), BarSet("showTarget"))

    UI.Dropdown(grid:FullRow("The \"on you\" mark",
        { sublabel = "The game itself decides when this shows - it is the "
            .. "one answer on the bar that cannot be wrong",
          controlWidth = 190 }),
        ns.Casts.MARKS, BarGet("atMeMark", "both"), BarSet("atMeMark"),
        { apply = Apply })

    -- UI.Input takes a PARENT and a WIDTH, not a getter and a setter - the
    -- shape every other input on this page uses. Written the other way here
    -- first, and the desk stayed green through it: the harness's SetSize
    -- takes whatever it is handed, so a function passed as a width sailed
    -- past every check and would have thrown on the first page build in the
    -- client. A stub that forgets agrees with every mistake.
    local wordRow = grid:FullRow("What it says", { controlWidth = 190 })
    local wordBox = UI.Input(wordRow.slot, 190, function(text)
        local cfg = Bar()
        cfg.atMeText = (text and text ~= "") and text or "ON YOU"
        Apply()
    end, false, "ON YOU")
    wordBox:SetPoint("RIGHT", wordRow.slot, "RIGHT", 0, 0)
    wordRow.Refresh = function()
        if wordBox.SetText and not (wordBox.HasFocus and wordBox:HasFocus()) then
            wordBox:SetText(Bar().atMeText or "ON YOU")
        end
    end
    wordRow.Refresh()

    UI.Slider(grid:FullRow("How wide the stripe is", { controlWidth = 124 }), {
        get = BarGet("atMeWidth", 4), set = BarSet("atMeWidth"),
        min = 0, max = 16, step = 1, apply = Apply,
        format = function(value) return string.format("%dpx", value) end })

    UI.MediaPicker(grid:FullRow("Font",
        { controlWidth = 190, icon = "media-font" }), "font",
        BarGet("font", ""), BarSet("font"), Apply)

    UI.Slider(grid:FullRow("Text size", { controlWidth = 124 }), {
        get = BarGet("fontSize", 12), set = BarSet("fontSize"),
        min = 8, max = 24, step = 1, apply = Apply })

    UI.Dropdown(grid:FullRow("Edge", { controlWidth = 150 }),
        ns.Media.OUTLINES, BarGet("outline", "OUTLINE"),
        BarSet("outline"), { apply = Apply })

    ns.OptionsWhen.Build(grid, {
        title = "When to show it",
        anchor = "ca-when",
        open = false,
        holder = Bar,
        apply = Apply,
    })

    grid:Section("Trying it out", "ca-test")

    UI.Toggle(grid:FullRow("Test mode",
        { sublabel = "Three invented casts, so you can see the bar and "
            .. "place it without a dungeon", controlWidth = 124 }),
        function() return ns.Casts:Testing() end,
        function(value)
            ns.Casts:SetTestMode(value)
            ns.Options:Refresh()
        end)

    ---------------------------------------------------------------------
    grid:LazyTab("Alerts", function()
        grid:Tab("Alerts")
        ns.OptionsCastAlerts:BuildInto(grid, width)
    end)

    ---------------------------------------------------------------------
    grid:LazyTab("Voice", function()
        grid:Tab("Voice")
        Page:BuildVoice(grid, width)
    end)

    grid.tab = "Bar"
    grid:Layout()
    strip:Layout()
    strip:Select("Bar")

    page.Refresh = function()
        band.Fit()
        self:BorrowBar()
        self.stageHint:SetShown(not ns.Modules:IsOn("casts"))
        local editor = ns.OptionsCastAlerts
        if editor and editor.Paint then editor.Paint() end
        grid:Refresh()
    end

    self.grid = grid
    page:SetScript("OnHide", function() Page:ReleaseBar() end)
    return grid
end

---------------------------------------------------------------------------
-- The preview: the real bar, borrowed
---------------------------------------------------------------------------
function Page:BorrowBar()
    -- The band is a demonstration, not a mirror of an empty world: while
    -- this page is up, the invented casts run whenever nothing real is
    -- casting - the bar draws and the alerts fire, which is the point.
    if ns.Casts then ns.Casts:SetPreview(true) end
    local panel = ns.CastBar.Frame()
    if not (panel and self.stage) then return end
    if ns.CastBar.hosted then
        self:FitBar()
        return
    end

    local cfg = Bar()
    self.homePoint = { cfg.point, cfg.relPoint, cfg.x, cfg.y }
    self.homeScale = panel:GetScale()

    ns.CastBar.hosted = true
    panel:SetParent(self.stage)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.stage, "CENTER", 0, 0)
    ns.CastBar:ApplyLayout()
    ns.CastBar:Refresh()
    panel:Show()
    self:FitBar()
end

function Page:FitBar()
    local panel = ns.CastBar.Frame()
    if not (panel and self.stage) then return end
    local room = self.stage:GetWidth() or 1
    local high = self.stage:GetHeight() or 1
    local wide = panel:GetWidth() or 1
    local tall = panel:GetHeight() or 1
    if wide <= 0 or tall <= 0 then return end
    panel:SetScale(math.min(1, room / wide, high / tall))
end

function Page:ReleaseBar()
    if ns.Casts then ns.Casts:SetPreview(false) end
    local panel = ns.CastBar.Frame()
    if not (panel and ns.CastBar.hosted) then return end
    ns.CastBar.hosted = nil
    panel:SetParent(UIParent)
    panel:SetScale(self.homeScale or 1)
    ns.CastBar:ApplyLayout()
    ns.CastBar:Refresh()
end

function Page:Refresh()
    if self.grid then self.grid:Refresh() end
end

---------------------------------------------------------------------------
-- THE VOICE TAB
--
-- Owner, 2026-08-18: "wir brauchen auch ne gute text to speech db mit
-- frauen und maenner stimme. die von blizzard ist der horror" - and then the
-- name for it: "in wow nennt sich das voice packs", "big wigs voice hab ich
-- drauf, aber big wigs used nicht jeder".
--
-- So this reads whatever the machine has rather than shipping a voice of its
-- own. A voice pack is a folder of .ogg files: BigWigs_Voice keys its by
-- spell id, the DBM packs by phrase name ("tankheal.ogg", "swapsoon.ogg",
-- "defensive.ogg"), and both register nothing with LibSharedMedia - so the
-- addon's own media picker is the door for anything that DOES register, and
-- the client's own text-to-speech is the fallback that always exists.
---------------------------------------------------------------------------
local function VoiceGet(key, fallback)
    return function()
        local value = Voice()[key]
        if value == nil then return fallback end
        return value
    end
end

local function VoiceSet(key)
    return function(value) Voice()[key] = value end
end

function Page:BuildVoice(grid, width)
    grid:Note("Spoken when an alert appears. It is off until you pick "
        .. "something, on purpose: a line read out on every cast is the "
        .. "fastest way to switch a feature off for good.")

    grid:Section("Switched on")

    UI.Toggle(grid:FullRow("Say the line", { controlWidth = 124 }),
        VoiceGet("enabled", false), VoiceSet("enabled"))

    UI.Toggle(grid:FullRow("Only when it is aimed at you",
        { controlWidth = 124 }),
        VoiceGet("onlyAtMe", true), VoiceSet("onlyAtMe"))

    UI.Slider(grid:FullRow("Wait between lines", { controlWidth = 124 }), {
        get = VoiceGet("gap", 2.0), set = VoiceSet("gap"),
        min = 0, max = 10, step = 0.5,
        format = function(value) return string.format("%.1fs", value) end })

    grid:Note("Three mobs starting the same cast in one pull is one "
        .. "sentence, not three on top of each other.")

    grid:Section("What it says")

    for _, rank in ipairs(ns.Casts.RANKS) do
        local key = rank.key
        local row = grid:FullRow(rank.text, { controlWidth = 190 })
        local input = UI.Input(row.slot, 190, function(text)
            Voice().lines = Voice().lines or {}
            Voice().lines[key] = text or ""
        end, false, "say nothing")
        input:SetPoint("RIGHT", row.slot, "RIGHT", 0, 0)
        row.Refresh = function()
            local lines = Voice().lines or {}
            if input.SetText and not (input.HasFocus and input:HasFocus()) then
                input:SetText(lines[key] or "")
            end
        end
    end

    grid:Note("|cffffd100%who|r becomes you, your co-tank, the group or "
        .. "somebody; |cffffd100%mob|r is the caster's name; "
        .. "|cffffd100%rank|r is what kind of mob it is. "
        .. "|cffffd100%spell|r names the cast when the mob has exactly one "
        .. "known ability - otherwise it says \"something\".")

    grid:Section("Whose voice", "ca-voice-who")

    -- A RECORDED LINE FIRST. Anything registered with LibSharedMedia is in
    -- this picker already - that is the same door every other sound in this
    -- addon comes through, so a voice pack that registers itself needs no
    -- code here at all.
    UI.MediaPicker(grid:FullRow("A recorded line",
        { controlWidth = 190 }), "sound",
        VoiceGet("sound", ""), VoiceSet("sound"),
        function()
            local name = Voice().sound
            if name and name ~= "" then ns.Sounds.Preview(name) end
        end, "Settings")

    grid:Note("Voice packs are folders of sound files - BigWigs +Voice, the "
        .. "DBM packs and their community ones. Whatever a pack registers "
        .. "with the shared media library shows up in this list. Leave it "
        .. "empty and the line is read out by the client's own voice "
        .. "instead, which is the one that is always there.")

    local voices = UI.Dropdown(grid:FullRow("The client's voice",
        { controlWidth = 190 }),
        function()
            local list = {}
            local ok, all = pcall(function()
                return C_VoiceChat and C_VoiceChat.GetTtsVoices
                    and C_VoiceChat.GetTtsVoices()
            end)
            if ok and type(all) == "table" then
                for _, entry in ipairs(all) do
                    list[#list + 1] = {
                        value = entry.voiceID,
                        text = entry.name or ("Voice " .. tostring(entry.voiceID)),
                    }
                end
            end
            -- AN EMPTY LIST, NOT A ROW THAT MEANS NOTHING. A menu entry
            -- without a value is a line somebody can press to no effect, and
            -- the desk guard says so in as many words. `emptyText` is the
            -- door for "there is nothing to pick".
            return list
        end,
        VoiceGet("voiceID", nil), VoiceSet("voiceID"),
        { width = 190, emptyText = "None this client offers" })

    UI.Slider(grid:FullRow("How loud", { controlWidth = 124 }), {
        get = VoiceGet("volume", 100), set = VoiceSet("volume"),
        min = 0, max = 100, step = 5,
        format = function(value) return string.format("%d%%", value) end })

    grid:Buttons({
        { text = "Say one now", onClick = function()
            local cfg = Voice()
            local line = (cfg.lines and cfg.lines.boss) or "Tank hit"
            local was = cfg.enabled
            cfg.enabled = true
            local spoke = ns.Casts.Speak(
                ns.CastRules.Words(line, "boss", "me", "the boss"), cfg)
            cfg.enabled = was
            if not spoke then
                ns.Print("Nothing was said - pick a recorded line or a "
                    .. "client voice first.")
            end
        end },
    })
end

---------------------------------------------------------------------------
-- THE ENEMY CARD - one mob, its model and everything it casts
--
-- Owner, with a screenshot of MDT's enemy page: "bei klick muss ein modal
-- aufgehen mit 3d avatar und der spell liste und allen faehigkeiten."
--
-- The abilities are the reason this is worth building. Nothing in this addon
-- may read the spell of a cast happening in front of you - but these ids came
-- out of a table, so every one of them can be named, drawn and given the
-- game's own tooltip. It is the one place in the whole feature where a spell
-- has a name.
--
-- ONE CARD, REUSED. Built on first open, refilled after that: a window per
-- mob is 462 frames that can never be freed.
---------------------------------------------------------------------------
local mobCard

local CARD_W, CARD_H = 580, 430

-- WHAT A MARK MEANS FOR THE PERSON READING IT, one clause each. The words
-- come from Rules.SpellMarks (Core/Casts.lua), which decodes MDT's letters.
local MARK_LINES = {
    kickable = { text = "Can be kicked." },
    magic    = { text = "Magic - dispel or steal it." },
    enrage   = { text = "Enrage - soothe it." },
    poison   = { text = "Applies a poison." },
    bleed    = { text = "Applies a bleed." },
    curse    = { text = "Applies a curse." },
    disease  = { text = "Applies a disease." },
}
local MODEL_W = 190

local function BuildMobCard()
    if mobCard then return mobCard end

    local card = CreateFrame("Frame", "ZwoelfStuffMobCard", UIParent)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- ABOVE THE OPTIONS WINDOW IT IS OPENED FROM, and above its inspector.
    card:SetFrameStrata("DIALOG")
    card:EnableMouse(true)
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    card:Hide()

    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(card)
    bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 1)

    local edge = ns.CreateBorder(card, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    ---------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------
    card.title = UI.Label(card, "", UI.FS.card, C.text)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
    card.title:SetJustifyH("LEFT")

    card.rank = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.rank:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.rank:SetJustifyH("LEFT")

    local close = UI.GhostButton(card, "Close", function()
        card:Hide()
    end)
    close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -14)

    local rule = card:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -54)
    rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -54)
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)

    ---------------------------------------------------------------------
    -- The model, in a well of its own
    ---------------------------------------------------------------------
    local well = CreateFrame("Frame", nil, card)
    well:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -64)
    well:SetSize(MODEL_W, 220)
    local wellBg = well:CreateTexture(nil, "BACKGROUND")
    wellBg:SetAllPoints(well)
    wellBg:SetColorTexture(C.well[1], C.well[2], C.well[3], 1)
    local wellEdge = ns.CreateBorder(well, 1, "BORDER")
    wellEdge:SetColor(C.separator[1], C.separator[2], C.separator[3], 1)

    card.model = CreateFrame("PlayerModel", nil, well)
    card.model:SetPoint("TOPLEFT", well, "TOPLEFT", 1, -1)
    card.model:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -1, 1)
    card.model:Hide()

    -- WHEN THERE IS NO MODEL TO SHOW. An empty sunken box reads as a broken
    -- window; a line saying so reads as an answer.
    card.noModel = UI.Hint(well, "No model for this one.")
    card.noModel:SetPoint("CENTER", well, "CENTER", 0, 0)
    card.noModel:Hide()

    ---------------------------------------------------------------------
    -- The readings, beside the model
    ---------------------------------------------------------------------
    local statW = CARD_W - MODEL_W - 14 - 14 - 12
    card.stats = {}
    for index, caption in ipairs({ "NPC Id", "Level", "Creature type", "Health" }) do
        local stat = UI.Stat(card, caption)
        -- Two per row: four tiles down the side of a 220-pixel model would
        -- each be shorter than their own caption.
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        stat:SetWidth((statW - 8) / 2)
        stat:ClearAllPoints()
        stat:SetPoint("TOPLEFT", well, "TOPRIGHT",
            12 + col * ((statW - 8) / 2 + 8),
            -row * (UI.STAT_H + 8))
        card.stats[index] = stat
    end

    ---------------------------------------------------------------------
    -- Everything it casts
    ---------------------------------------------------------------------
    card.spellTitle = UI.Label(card, "Abilities", UI.FS.card, C.text)
    card.spellTitle:SetPoint("TOPLEFT", well, "TOPRIGHT", 12,
        -(UI.STAT_H * 2 + 8 + 14))
    card.spellTitle:SetJustifyH("LEFT")

    local listHost = CreateFrame("Frame", nil, card)
    listHost:SetPoint("TOPLEFT", card.spellTitle, "BOTTOMLEFT", 0, -8)
    listHost:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 52)

    local listWidth = statW
    local _, content = UI.ScrollArea(listHost, listWidth, 8)
    card.content = content
    card.listWidth = listWidth
    card.spellRows = {}

    card.noSpells = UI.Hint(content, "Nothing recorded for this one.")
    card.noSpells:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
    card.noSpells:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -4)
    card.noSpells:Hide()

    ---------------------------------------------------------------------
    -- The one action this card offers
    ---------------------------------------------------------------------
    card.watch = UI.Button(card, "Watch this mob", 160, function()
        if card.OnWatch then card.OnWatch() end
    end)
    card.watch:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, 14)

    card.watchNote = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.watchNote:SetPoint("LEFT", card.watch, "RIGHT", 10, 0)
    card.watchNote:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    card.watchNote:SetJustifyH("LEFT")
    card.watchNote:SetWordWrap(false)

    -- ESCAPE CLOSES IT, through the game's own list rather than a key handler
    -- of ours competing for the keyboard - the same road Keys.lua takes.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ZwoelfStuffMobCard")
    end

    mobCard = card
    return card
end

-- A number a person reads at a glance. 24,290,000 is four digits of noise.
local function ShortHealth(value)
    if type(value) ~= "number" or value <= 0 then return nil end
    if value >= 1e6 then return ("%.2fm"):format(value / 1e6) end
    if value >= 1e3 then return ("%.0fk"):format(value / 1e3) end
    return tostring(value)
end

---------------------------------------------------------------------------
-- Open the card on one mob. `onWatch` is called when the button is pressed,
-- and `watched` decides what the button says.
---------------------------------------------------------------------------
function ns.ShowMobCard(entry, spec)
    if type(entry) ~= "table" then return end
    spec = spec or {}

    local card = BuildMobCard()
    card.entry = entry

    card.title:SetText(entry.mob or "Unknown")

    local RANK_WORD = {
        boss = "Boss", lieutenant = "Lieutenant", standard = "Ordinary mob",
    }
    local RANK_COLOUR = {
        boss = C.harm, lieutenant = C.warning, standard = C.textFaint,
    }
    local word = RANK_WORD[entry.rank or ""]
    local colour = RANK_COLOUR[entry.rank or ""] or C.textFaint
    card.rank:SetText(spec.place and word and (word .. "  ·  " .. spec.place)
        or word or spec.place or "")
    card.rank:SetTextColor(colour[1], colour[2], colour[3])

    ---------------------------------------------------------------------
    -- The model. Two doors, the same pair Death.PaintArt uses - a creature
    -- id first because MDT's own enemy tooltip points at raw npc ids, then
    -- the display id. NOT portrait-zoomed: the list is where the head shots
    -- are, and this is the whole figure the owner asked for.
    ---------------------------------------------------------------------
    local shown = false
    if entry.npc and card.model.SetCreature then
        shown = pcall(card.model.SetCreature, card.model, entry.npc)
    end
    if not shown and entry.display and card.model.SetDisplayInfo then
        shown = pcall(card.model.SetDisplayInfo, card.model, entry.display)
    end
    if shown then
        pcall(card.model.SetPosition, card.model, 0, 0, -0.35)
        pcall(card.model.SetFacing, card.model, 0.5)
        pcall(card.model.SetCamDistanceScale, card.model, 1.15)
        card.model:Show()
        card.noModel:Hide()
    else
        card.model:Hide()
        card.noModel:Show()
    end

    ---------------------------------------------------------------------
    -- The readings
    ---------------------------------------------------------------------
    -- A folded row stands for more than one id; the card says so instead
    -- of quietly showing half the truth.
    local idText = entry.npc and tostring(entry.npc) or "—"
    if type(entry.npcs) == "table" and #entry.npcs > 1 then
        idText = idText .. " +" .. (#entry.npcs - 1)
    end
    card.stats[1]:Set(idText)
    card.stats[2]:Set(entry.level and tostring(entry.level) or "—")
    card.stats[3]:Set(entry.kind or "—")
    card.stats[4]:Set(ShortHealth(entry.health) or "—")

    ---------------------------------------------------------------------
    -- Every ability, with the game's own tooltip on each
    ---------------------------------------------------------------------
    local spells = type(entry.spells) == "table" and entry.spells or {}
    card.spellTitle:SetText(#spells == 1 and "1 ability"
        or (#spells .. " abilities"))

    local y, used = 0, 0
    for _, spellID in ipairs(spells) do
        used = used + 1
        local row = card.spellRows[used]
        if not row then
            row = UI.SpellRow(card.content, card.listWidth, 30)
            -- Nothing here is dragged onto a bar: this list is a reference,
            -- and a row that lifts off under the cursor promises otherwise.
            row:RegisterForDrag()
            row:SetScript("OnDragStart", nil)
            row:SetScript("OnDragStop", nil)
            card.spellRows[used] = row
        end

        row.dkSpellID = spellID
        row.dkPayload = nil
        row.dkHot = true
        wipe(row.dkLines)

        local name = spellID
        if C_Spell and C_Spell.GetSpellName then
            local ok, got = pcall(C_Spell.GetSpellName, spellID)
            if ok and type(got) == "string" and got ~= "" then name = got end
        end
        row.name:SetText(name)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetTexture((ns.SpellTexture and ns.SpellTexture(spellID))
            or ns.WHITE)
        row:SetUsed(nil, true)

        -- WHAT MDT KNOWS ABOUT IT, on the row and in the tip. The trailing
        -- slot shows the marks when there are any, the id when there are
        -- none - the id then still stands in the tip, so two spells sharing
        -- a name stay tellable apart either way.
        local marks = ns.CastRules.SpellMarks(spellID)
        if marks then
            local kick = false
            for _, word in ipairs(marks) do
                if word == "kickable" then kick = true end
                row.dkLines[#row.dkLines + 1] = MARK_LINES[word]
                    or { text = word }
            end
            row.dkLines[#row.dkLines + 1] = {
                text = "Id " .. spellID,
                r = C.textGhost[1], g = C.textGhost[2], b = C.textGhost[3],
            }
            row:SetTrailing(table.concat(marks, " · "),
                nil, kick and C.hot or C.textDim)
        else
            row:SetTrailing(tostring(spellID), nil, C.textGhost)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -y)
        row:Show()
        y = y + 31
    end

    for index = used + 1, #card.spellRows do card.spellRows[index]:Hide() end
    card.noSpells:SetShown(used == 0)
    card.content:SetHeight(math.max(1, y))

    ---------------------------------------------------------------------
    -- The action
    ---------------------------------------------------------------------
    card.OnWatch = spec.onWatch
    card.watch:SetShown(spec.onWatch ~= nil)
    if spec.onWatch then
        card.watch.label:SetText(spec.watched and "Stop watching" or "Watch this mob")
        card.watchNote:SetText(spec.watched
            and "The selected alert only fires for this mob."
            or "Narrows the selected alert to this mob.")
    else
        card.watchNote:SetText("")
    end

    card:Show()
    card:Raise()
end

---------------------------------------------------------------------------
-- THE THIRD COLUMN - the mobs you have met, by instance
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, "Mobs of the season", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side,
        "Click one to open it. Right-click watches it.",
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", side, "RIGHT", -pad, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8

    -- FINDING ONE OF 462 IS TYPING, NOT SCROLLING. The search covers mob
    -- names AND ability names - "who casts Barkbreaker" is the question a
    -- tank actually stands there with. The chips under it are a VIEW
    -- filter for this list alone; the bar's "which casts count" on the Bar
    -- tab is a setting, and the two answer different questions.
    local search = UI.Input(side, rowWidth, function() end, false,
        "Search mobs and abilities")
    search:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    search:SetPoint("RIGHT", side, "RIGHT", -pad, 0)
    search:SetHeight(24)
    search:SetIcon("ui-search")

    local ranksOn = { boss = true, lieutenant = true, standard = true }
    local chips
    chips = UI.ChipRow(side, rowWidth, {
        chips = {
            { key = "boss",       text = "Bosses" },
            { key = "lieutenant", text = "Lieutenants" },
            { key = "standard",   text = "Mobs" },
        },
        isOn = function(key) return ranksOn[key] end,
        onSelect = function(key)
            ranksOn[key] = not ranksOn[key]
            chips.Refresh()
            side.Refresh()
        end,
    })
    chips:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)

    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -10)
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    local rows, headings = {}, {}

    local none = UI.Hint(content, "")
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -8)
    none:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -8)
    none:Hide()

    local RANK_BADGE = {
        standard = "mob", lieutenant = "lieutenant", boss = "boss",
    }

    -- WHAT EACH RANK IS WORTH, in colour. Owner: "das sollten die
    -- entsprechenden farben haben". A traffic light off the existing tokens
    -- rather than three new ones - the boss is the harm colour the death
    -- window uses, the lieutenant is the warning amber, and rank and file
    -- stay quiet so the other two can be picked out at a glance.
    local RANK_COLOUR = {
        boss       = C.harm,
        lieutenant = C.warning,
        standard   = C.textFaint,
    }

    -- A MOB'S OWN FACE, not the icon of one of its spells.
    --
    -- Owner: "bei der liste muss der 2d avatar drin sein". This can be done
    -- on the first pass now and could not be before: the flat portrait call
    -- wants a DISPLAY id, the addon never had one for a creature it had not
    -- already loaded a model of - which is why its own self test has always
    -- reported "0 flat portraits" - and MobData carries one for all 462.
    local function PaintMobFace(icon, entry)
        if entry.display and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
            -- Portraits are drawn whole. The 0.08 inset every spell icon in
            -- this window wears would crop the face.
            icon:SetTexCoord(0, 1, 0, 1)
            if pcall(SetPortraitTextureFromCreatureDisplayID, icon, entry.display) then
                return true
            end
        end
        -- No display id: the mob's first spell still says more than nothing.
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local spells = entry.spells
        if type(spells) == "table" and spells[1] and ns.SpellTexture then
            local texture = ns.SpellTexture(spells[1])
            if texture then
                icon:SetTexture(texture)
                return true
            end
        end
        icon:SetTexture(ns.WHITE)
        return false
    end

    ---------------------------------------------------------------------
    -- VIEW STATE, not settings: which groups are folded, which ranks the
    -- chips let through, what the search box holds. Gone on reload, on
    -- purpose - this belongs to the view, not to the profile.
    ---------------------------------------------------------------------
    local query = ""
    local open = {}
    local catalog, hay
    local NONE = {}

    -- The words a row can be found by: its name and every ability name,
    -- lowered once and kept. Lazy - 462 rows resolve ~1700 spell names,
    -- and nobody pays that before the first keystroke.
    local function Haystack(entry)
        local text = hay[entry]
        if not text then
            local parts = { (entry.mob or ""):lower() }
            for _, id in ipairs(entry.spells or NONE) do
                local name = ns.SpellName and ns.SpellName(id)
                if type(name) == "string" then
                    parts[#parts + 1] = name:lower()
                end
                local marks = ns.CastRules.SpellMarks(id)
                if marks then
                    for _, word in ipairs(marks) do
                        parts[#parts + 1] = word
                    end
                end
            end
            text = table.concat(parts, " ")
            hay[entry] = text
        end
        return text
    end

    local function RowWanted(entry, ranksToo)
        if ranksToo and ranksOn[entry.rank or "standard"] == false then
            return false
        end
        if query ~= "" then
            return Haystack(entry):find(query, 1, true) ~= nil
        end
        return true
    end

    -- Which keys a row writes into an alert's picked-mobs table: one per
    -- variant, so a watch covers every id that wears this name.
    local function KeysOf(entry)
        if type(entry.npcs) == "table" and entry.npcs[1] ~= nil then
            return entry.npcs
        end
        local key = ns.CastRules.MobKey(entry.mob, entry.npc)
        if key ~= nil then return { key } end
        return nil
    end

    local function IsOpen(place, here)
        local state = open[place]
        if state == nil then return place == here end
        return state
    end

    -- WHICH CATALOG PLACE THE GROUND YOU STAND ON IS. The catalog names
    -- dungeons in English; GetInstanceInfo answers in the client's own
    -- language - so the match runs over the Challenge Mode map id, whose
    -- UI name the same client localizes. English stays as the fallback,
    -- and no match means no group floats.
    local herePlace
    local localName
    local function PlaceOfHere()
        local here = ns.Casts.Where and ns.Casts.Where() or nil
        if not here or not catalog then return nil end
        if not localName then
            localName = {}
            if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                for _, place in ipairs(catalog) do
                    if place.map then
                        local ok, name = pcall(C_ChallengeMode.GetMapUIInfo,
                            place.map)
                        if ok and type(name) == "string" and name ~= "" then
                            localName[place.place] = name
                        end
                    end
                end
            end
        end
        for _, place in ipairs(catalog) do
            if place.place == here or localName[place.place] == here then
                return place.place
            end
        end
        return nil
    end

    side.SetQuery = function(text)
        query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        side.Refresh()
    end
    side.SetRank = function(key, on)
        ranksOn[key] = on and true or false
        chips.Refresh()
        side.Refresh()
    end
    search.input:SetScript("OnTextChanged", function()
        search.UpdateGhost()
        side.SetQuery(search.input:GetText())
    end)

    side.Refresh = function()
        local editor = ns.OptionsCastAlerts
        local _, cfg = editor:Current()
        catalog = catalog or ns.Casts.Catalog()
        hay = hay or {}
        local y, usedRows, usedHeads = 0, 0, 0

        -- The dungeon you are STANDING in leads and starts open; the rest
        -- keep their alphabetical order, folded until asked. A search
        -- overrules the folding - a hit behind a closed group is a hit
        -- nobody finds.
        herePlace = PlaceOfHere()
        local here = herePlace
        local groups = {}

        -- WATCHED FIRST, as its own group: what the selected alert filters
        -- on is the one set of rows worth finding without a search. Keys an
        -- old profile picked that no season row claims still get a line -
        -- a filter you cannot see is a filter you cannot take off.
        local pickedMobs = cfg and type(cfg.mobs) == "table"
            and next(cfg.mobs) and cfg.mobs or nil
        if pickedMobs then
            local mine, claimed = {}, {}
            for _, place in ipairs(catalog) do
                for _, entry in ipairs(place.mobs) do
                    local hit = false
                    for _, id in ipairs(entry.npcs or NONE) do
                        if pickedMobs[id] then
                            hit, claimed[id] = true, true
                        end
                    end
                    if entry.mob and pickedMobs[entry.mob] then
                        hit, claimed[entry.mob] = true, true
                    end
                    if hit then mine[#mine + 1] = entry end
                end
            end
            for key in pairs(pickedMobs) do
                if not claimed[key] then
                    mine[#mine + 1] = {
                        mob = type(key) == "string" and key
                            or ("NPC " .. tostring(key)),
                        npc = tonumber(key),
                        npcs = { key },
                    }
                end
            end
            if #mine > 0 then
                groups[#groups + 1] =
                    { place = "Watched", mobs = mine, pinned = true }
            end
        end

        local lead = #groups + 1
        for _, place in ipairs(catalog) do
            if place.place == here then
                table.insert(groups, lead, place)
            else
                groups[#groups + 1] = place
            end
        end

        local filtered = query ~= "" or not (ranksOn.boss
            and ranksOn.lieutenant and ranksOn.standard)

        for _, group in ipairs(groups) do
            local shown = {}
            for _, entry in ipairs(group.mobs) do
                if RowWanted(entry, not group.pinned) then
                    shown[#shown + 1] = entry
                end
            end

            if #shown > 0 or not filtered then
            local isOpen = group.pinned or query ~= ""
                or IsOpen(group.place, here)

            usedHeads = usedHeads + 1
            local heading = headings[usedHeads]
            if not heading then
                heading = UI.ListHeading(content, rowWidth, 22)
                -- The heading is the fold's handle: "+ NAME" closed, plain
                -- open - the same mark the window's own sections wear.
                heading:EnableMouse(true)
                heading:SetScript("OnMouseDown", function(self)
                    if not self.dkPlace then return end
                    open[self.dkPlace] = not IsOpen(self.dkPlace, herePlace)
                    side.Refresh()
                end)
                heading:SetScript("OnEnter", function(self)
                    if not self.dkPlace then return end
                    self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
                end)
                heading:SetScript("OnLeave", function(self)
                    self.label:SetTextColor(C.textDim[1], C.textDim[2],
                        C.textDim[3])
                end)
                headings[usedHeads] = heading
            end
            heading.dkPlace = not group.pinned and group.place or nil
            heading:SetText((isOpen and "" or "+ ") .. group.place, #shown)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            heading:Show()
            y = y + 26

            for _, entry in ipairs(isOpen and shown or NONE) do
                usedRows = usedRows + 1
                local row = rows[usedRows]
                if not row then
                    row = UI.SpellRow(content, rowWidth, 30)

                    -- WATCHING IS ONE FUNCTION, CALLED FROM TWO PLACES - the
                    -- right-click here and the card's own button. Two copies
                    -- of "toggle this key, drop the table when it empties"
                    -- is how the two quietly stop agreeing.
                    local function ToggleWatch(keys)
                        local _, current = editor:Current()
                        if not current then
                            ns.Print("Make an alert first - the New alert "
                                .. "button on the Alerts tab.")
                            return
                        end
                        if type(keys) ~= "table" or keys[1] == nil then
                            return
                        end
                        current.mobs = current.mobs or {}
                        -- One press covers every variant id the row stands
                        -- for: on if none was, off as one.
                        local on = false
                        for _, key in ipairs(keys) do
                            if current.mobs[key] then on = true end
                        end
                        for _, key in ipairs(keys) do
                            current.mobs[key] = not on and true or nil
                        end
                        if next(current.mobs) == nil then
                            current.mobs = nil
                        end
                        editor:Apply()
                        ns.OptionsCasts:Refresh()
                        side.Refresh()
                    end

                    -- Owner: "bei klick muss ein modal aufgehen". So the
                    -- left button opens the card, and watching moves to the
                    -- right button and to the card's own button - it stays
                    -- one press either way.
                    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    row:SetScript("OnClick", function(self, button)
                        if button == "RightButton" then
                            ToggleWatch(self.dkKeys)
                            return
                        end
                        local _, current = editor:Current()
                        local watched = false
                        if current and type(current.mobs) == "table" then
                            for _, key in ipairs(self.dkKeys or NONE) do
                                if current.mobs[key] then watched = true end
                            end
                        end
                        ns.ShowMobCard(self.dkEntry, {
                            place = self.dkPlace,
                            watched = watched,
                            onWatch = function() ToggleWatch(self.dkKeys) end,
                        })
                    end)
                    rows[usedRows] = row
                end

                row.dkKeys = KeysOf(entry)
                row.dkEntry = entry
                row.dkPlace = group.place
                row.dkHot = true

                PaintMobFace(row.icon, entry)
                row.name:SetText(entry.mob)

                local picked = false
                if cfg and type(cfg.mobs) == "table" then
                    for _, key in ipairs(row.dkKeys or NONE) do
                        if cfg.mobs[key] then picked = true end
                    end
                end
                row:SetUsed(picked and "watched" or nil, true)
                local badge = RANK_BADGE[entry.rank or ""] or "mob"
                row:SetTrailing(picked and "Watched" or badge,
                    picked and "cell" or nil,
                    RANK_COLOUR[entry.rank or ""])

                -- WHAT THE CURSOR IS TOLD. The row had none of this: the
                -- tooltip is a spell tooltip and left immediately when there
                -- was no spell id, so the whole column was silent.
                row.dkSpellID = nil
                row.dkTipTitle = entry.mob
                wipe(row.dkLines)
                local said = RANK_BADGE[entry.rank or ""]
                if said then
                    local rc = RANK_COLOUR[entry.rank or ""] or C.textDim
                    row.dkLines[#row.dkLines + 1] = {
                        text = said:gsub("^%l", string.upper),
                        r = rc[1], g = rc[2], b = rc[3],
                    }
                end
                if entry.kind then
                    row.dkLines[#row.dkLines + 1] = { text = entry.kind }
                end
                if type(entry.npcs) == "table" and #entry.npcs > 1 then
                    row.dkLines[#row.dkLines + 1] = {
                        text = #entry.npcs .. " variants",
                    }
                end
                if entry.forces then
                    row.dkLines[#row.dkLines + 1] = {
                        text = entry.forces .. " forces",
                    }
                end
                local count = type(entry.spells) == "table" and #entry.spells or 0
                row.dkLines[#row.dkLines + 1] = {
                    text = count == 1 and "1 ability" or (count .. " abilities"),
                }
                row.dkLines[#row.dkLines + 1] = {
                    text = picked and "Click to open. Right-click stops watching it."
                        or "Click to open. Right-click watches it.",
                    r = C.hot[1], g = C.hot[2], b = C.hot[3],
                }

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row:Show()
                y = y + 31
            end
            end
        end

        for index = usedRows + 1, #rows do rows[index]:Hide() end
        for index = usedHeads + 1, #headings do headings[index]:Hide() end
        none:SetText(filtered and "Nothing matches."
            or "The season list is missing.")
        none:SetShown(usedHeads == 0)
        side.drawnRows, side.drawnHeads = usedRows, usedHeads
        content:SetHeight(math.max(1, y))
    end

    -- The pools are visible so the self test can read what a drawn row
    -- knows, instead of trusting that drawing happened.
    side.rows, side.headings = rows, headings
    Page.side = side
    return side
end
