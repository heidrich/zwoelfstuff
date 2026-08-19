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
        .. "lieutenant casting at you\". It cannot name the spell: on this "
        .. "patch nobody can, not this addon and not the boss mods (see "
        .. "the note under Which casts count). What it can say is who is "
        .. "casting, how dangerous they are, and whether it is coming at you.",
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

        grid:Note("\"At you\" is the game's own answer and it is not always "
            .. "given: inside a dungeon the target's name and class can be "
            .. "withheld, and then the honest answer is |cffffd100At "
            .. "somebody the game will not name|r. Leave that one on unless "
            .. "you would rather miss a warning than see a spare one. The "
            .. "bar's own stripe never has this problem - the client draws "
            .. "it without telling us.")

        grid:Section("Only these mobs", "ca-mobs", false)

        local mobNote = grid:Note("")
        mobNote.Refresh = function()
            local cfg = select(2, ns.OptionsCastAlerts:Current())
            local mobs = cfg and cfg.mobs
            local count = 0
            if type(mobs) == "table" then
                for _ in pairs(mobs) do count = count + 1 end
            end
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

    grid:Note("The spell being cast cannot be named on this patch - its id "
        .. "is a secret value, which is why the boss mods went quiet about "
        .. "trash in Midnight too. Its |cffffd100icon|r, its bar and "
        .. "whether it can be kicked all come straight from the game, and "
        .. "the mark down the left of the bar is the game's own answer to "
        .. "\"is this one on you\".")

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

    grid:Note("Which of the two you are looking at is decided inside the "
        .. "client: whether a cast can be interrupted is withheld from "
        .. "addons on this patch, so the colour is chosen by the engine and "
        .. "never by a line of ours.")

    UI.Toggle(grid:FullRow("Icon", { controlWidth = 124 }),
        BarGet("showIcon", true), BarSet("showIcon"))

    UI.Slider(grid:FullRow("Icon size", { controlWidth = 124 }), {
        get = BarGet("iconSize", 26), set = BarSet("iconSize"),
        min = 10, max = 64, step = 1, apply = Apply })

    UI.Toggle(grid:FullRow("The spell's name", { controlWidth = 124 }),
        BarGet("showName", true), BarSet("showName"))

    UI.Toggle(grid:FullRow("Who it is aimed at", { controlWidth = 124 }),
        BarGet("showTarget", true), BarSet("showTarget"))

    UI.Slider(grid:FullRow("The \"on you\" mark", { controlWidth = 124 }), {
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
        .. "|cffffd100%rank|r is what kind of mob it is. The spell cannot "
        .. "be a token - on this patch its name is withheld from addons.")

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
-- THE THIRD COLUMN - the mobs you have met, by instance
---------------------------------------------------------------------------
function Page:BuildSide(sideHost, pad)
    local side = CreateFrame("Frame", nil, sideHost)
    side:SetAllPoints(sideHost)
    side:Hide()

    local title = UI.Label(side, "Mobs you have met", UI.FS.card, C.text)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -18)

    local hint = UI.Label(side,
        "Click one to narrow the selected alert to it.",
        UI.FS.meta, C.textFaint)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", side, "RIGHT", -pad, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)

    local listHost = CreateFrame("Frame", nil, side)
    listHost:SetPoint("TOPLEFT", side, "TOPLEFT", pad, -(UI.HEADER_H + 16))
    listHost:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -pad, pad)

    local rowWidth = UI.INSPECTOR_W - pad * 2 - 8
    local _, content = UI.ScrollArea(listHost, rowWidth, 8)

    local rows, headings = {}, {}

    local none = UI.Hint(content,
        "Nothing yet. Walk into a dungeon with this switched on and every "
        .. "mob that casts something turns up here, under the place you "
        .. "met it.")
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -8)
    none:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -8)
    none:Hide()

    local RANK_BADGE = {
        standard = "mob", lieutenant = "lieutenant", boss = "boss",
    }

    side.Refresh = function()
        local editor = ns.OptionsCastAlerts
        local _, cfg = editor:Current()
        local ledger = ns.Casts.Ledger()
        local y, usedRows, usedHeads = 0, 0, 0

        for _, place in ipairs(ledger) do
            usedHeads = usedHeads + 1
            local heading = headings[usedHeads]
            if not heading then
                heading = UI.ListHeading(content, rowWidth, 22)
                headings[usedHeads] = heading
            end
            heading:SetText(place.place, #place.mobs)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            heading:Show()
            y = y + 26

            for _, entry in ipairs(place.mobs) do
                usedRows = usedRows + 1
                local row = rows[usedRows]
                if not row then
                    row = UI.SpellRow(content, rowWidth, 30)
                    row:SetScript("OnClick", function(self)
                        local _, current = editor:Current()
                        if not current then
                            ns.Print("Make an alert first - the New alert "
                                .. "button on the Alerts tab.")
                            return
                        end
                        current.mobs = current.mobs or {}
                        if current.mobs[self.dkMob] then
                            current.mobs[self.dkMob] = nil
                            if next(current.mobs) == nil then
                                current.mobs = nil
                            end
                        else
                            current.mobs[self.dkMob] = true
                        end
                        editor:Apply()
                        ns.OptionsCasts:Refresh()
                        side.Refresh()
                    end)
                    rows[usedRows] = row
                end

                row.dkMob = entry.mob
                -- No spell icon to show: the cast's icon belongs to a cast
                -- that is over. The rank is the drawing here.
                row.icon:SetTexture(ns.WHITE)
                row.name:SetText(entry.mob)

                local picked = cfg and type(cfg.mobs) == "table"
                    and cfg.mobs[entry.mob] == true
                row:SetUsed(picked and "watched" or nil, true)
                row:SetTrailing(picked and "Watched"
                    or (RANK_BADGE[entry.rank or ""] or "seen"),
                    picked and "cell" or nil)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row:Show()
                y = y + 31
            end
        end

        for index = usedRows + 1, #rows do rows[index]:Hide() end
        for index = usedHeads + 1, #headings do headings[index]:Hide() end
        none:SetShown(usedRows == 0)
        content:SetHeight(math.max(1, y))
    end

    return side
end
