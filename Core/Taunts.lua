---------------------------------------------------------------------------
-- Taunts - saying that you took it, and asking the other tank to.
--
-- Roadmap item 6, the owner's own order: "10, dann 6, dann 1."
--
-- WHAT IS KNOWABLE, and the whole design follows from it:
--
--   YOUR taunt          UNIT_SPELLCAST_SUCCEEDED on "player" is the one
--                       combat fact this client still hands an addon. It is
--                       what History.lua already runs on.
--   the target's NAME   readable, even in a dungeon. UnitGUID is withheld
--                       for every mob on 12.0 and UnitName is not - measured
--                       in game, see the handoff.
--   the OTHER tank's    NOT knowable. Since 12.0.5 another player's INSTANT
--   taunt               cast is not announced at all, and every taunt in the
--                       game is instant. The combat log is closed. So this
--                       addon cannot tell you the co-tank taunted, and the
--                       settings page says so rather than pretending.
--   "swap at X stacks"  NOT knowable, and not in 12.1 either: a foreign
--                       aura's value cannot be read, only displayed.
--
-- What is left is exactly what a tank actually needs from a swap: TELL THE
-- OTHER TANK. A message in chat reaches them whatever addons they run, which
-- is better than anything an addon-to-addon channel could do here.
--
-- IT IS OFF UNTIL ASKED FOR. A feature that starts writing in party chat
-- after an update is the worst surprise this addon could hand somebody.
---------------------------------------------------------------------------
local _, ns = ...

local Taunts = {}
ns.Taunts = Taunts

-- THE LIST, and it is not from memory. Read out of NorthernSkyRaidTools'
-- shipping Reminders.lua, which keys exactly this set as `Taunts` - the same
-- door the externals list came through (MRT's DEFTAR). Cross-checked against
-- its LibDFramework spell table, which files the same ids per spec.
--
-- Death Grip is in the list because it taunts in Blood and only in Blood; a
-- Frost death knight pressing it is not taking anything, so the spec is
-- checked before it announces.
Taunts.SPELLS = {
    { spellID = 355,    class = "WARRIOR" },      -- Taunt
    { spellID = 56222,  class = "DEATHKNIGHT" },  -- Dark Command
    { spellID = 49576,  class = "DEATHKNIGHT", spec = 250 },  -- Death Grip, Blood
    { spellID = 62124,  class = "PALADIN" },      -- Hand of Reckoning
    { spellID = 115546, class = "MONK" },         -- Provoke
    { spellID = 6795,   class = "DRUID" },        -- Growl
    { spellID = 185245, class = "DEMONHUNTER" },  -- Torment
}

local byID = {}
for _, entry in ipairs(Taunts.SPELLS) do byID[entry.spellID] = entry end

function Taunts.Get(spellID) return byID[spellID] end

-- Pure: is this cast a taunt, for somebody of this spec. `specID` may be nil
-- (the client answers 0 for a while after login) and a nil spec must not
-- swallow a real taunt - only Death Grip is ever refused by it.
function Taunts.IsTaunt(spellID, specID)
    local entry = byID[spellID]
    if not entry then return false end
    if entry.spec and specID and entry.spec ~= specID then return false end
    return true
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- ENGLISH, both of them. The addon ships in English and these are the words
-- it puts in OTHER people's chat; a German default in an English addon was
-- the one German sentence a French tank could not switch off without
-- retyping it (owner, 2026-08-16: "die platzhalter texte muessen ueberall
-- auf en sein").
Taunts.DEFAULT_MESSAGE = "Taunt: %t"
Taunts.DEFAULT_ASK = "%n, please taunt!"

-- THE BUTTON'S LOOK, under the SAME key names a bar uses - so ns.PaintSurface
-- and ns.PaintBorder paint it without knowing what it is, exactly as the
-- externals panel is painted. There is no second renderer in this addon and
-- there is not about to be a third.
Taunts.BUTTON_DEFAULTS = {
    size            = 44,
    scale           = 1.0,
    alpha           = 1.0,
    borderSize      = 1,
    borderTexture   = "None",
    backdrop        = true,
    backdropAlpha   = 1.00,
    backdropTexture = "Blizzard",
    iconZoom        = 0.08,
}

function Taunts.Config()
    ns.db.taunts = ns.db.taunts or {}
    local cfg = ns.db.taunts

    for key, value in pairs(Taunts.BUTTON_DEFAULTS) do
        if cfg[key] == nil then cfg[key] = value end
    end
    cfg.borderColor = cfg.borderColor or ns.SurfaceColor()
    cfg.backdropColor = cfg.backdropColor or ns.SurfaceColor()

    -- The channels are seeded HERE and not in ns.DEFAULTS, for the reason the
    -- externals ones are: a channel you switch OFF is stored by being
    -- missing, and ApplyDefaults fills in what is missing - so a default
    -- would switch it back on at every login and no amount of clicking would
    -- keep it off.
    cfg.channels = cfg.channels or {}
    if next(cfg.channels) == nil then cfg.channels.GROUP = true end

    return cfg
end

function Taunts.ChannelOn(value)
    return Taunts.Config().channels[value] and true or false
end

function Taunts.ToggleChannel(value)
    local cfg = Taunts.Config()
    cfg.channels[value] = (not cfg.channels[value]) or nil
    for _ in pairs(cfg.channels) do return end
    cfg.channels.GROUP = true
end

---------------------------------------------------------------------------
-- WHO THE OTHER TANK IS
--
-- Pure, and it takes the roster as a list for the same reason the externals
-- one does: a raid with three tanks in it is not something a self test can
-- arrange in game.
--
-- Answers the FIRST other tank. In a five-man there is at most one, and in a
-- raid the person you are swapping with is the one you have named - which is
-- what the assignment is for.
---------------------------------------------------------------------------
function Taunts.CoTank(roster, assignedName)
    if type(roster) ~= "table" then return nil end

    if assignedName then
        for _, member in ipairs(roster) do
            if member.name == assignedName and not member.isPlayer then
                return member, "assigned"
            end
        end
        -- Named somebody who has left. Falling back to the rule is right and
        -- saying so matters - the same rule the externals slots follow.
    end

    for _, member in ipairs(roster) do
        if not member.isPlayer and member.role == "TANK" then
            return member, "the other tank"
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- What it says
---------------------------------------------------------------------------
-- %s the taunt, %t what you taunted, %n the other tank.
function Taunts.Message(template, spellName, targetName, personName)
    if type(template) ~= "string" or template == "" then
        template = Taunts.DEFAULT_MESSAGE
    end
    return ns.Chat.Fill(template, {
        s = spellName, t = targetName, n = personName,
    })
end

---------------------------------------------------------------------------
-- Announcing
---------------------------------------------------------------------------
-- TWO PRESSES IN A SECOND ARE ONE ANNOUNCE. A taunt that does not land is
-- pressed again immediately, and a tank who spams their own group because
-- their first taunt missed will switch the feature off and never come back.
Taunts.QUIET = 2.0
local lastAt = 0

-- Pure, so the rule can be checked without a clock: has enough time passed.
function Taunts.MaySpeak(now, previous, quiet)
    if not previous then return true end
    return (now - previous) >= (quiet or Taunts.QUIET)
end

-- Whether an announce should happen AT ALL, before anything is written. Pure,
-- because every one of these is a state that has to be arranged rather than
-- waited for.
function Taunts.ShouldAnnounce(cfg, inGroup, inInstance)
    if not cfg.announce then return false, "switched off" end
    if cfg.onlyInGroup ~= false and not inGroup then
        return false, "not in a group"
    end
    if cfg.onlyInInstance and not inInstance then
        return false, "not in an instance"
    end
    return true
end

local function InInstance()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside and true or false
end

-- The one this whole file exists for. Answers whether it said anything, and
-- why not when it did not - the diagnostic prints that line rather than
-- leaving "it does nothing" as the only description.
function Taunts.Announce(spellID, targetName)
    local cfg = Taunts.Config()

    local ok, why = Taunts.ShouldAnnounce(cfg, IsInGroup(), InInstance())
    if not ok then return false, why end

    local now = GetTime and GetTime() or 0
    if not Taunts.MaySpeak(now, lastAt > 0 and lastAt or nil, cfg.quiet) then
        return false, "just said it"
    end

    local roster = ns.Roster()
    local person = Taunts.CoTank(roster, cfg.assigned)

    local going = ns.Chat.Where(cfg.channels)
    for index = #going, 1, -1 do
        if going[index].channel == "WHISPER" and not person then
            table.remove(going, index)
        end
    end
    if #going == 0 then
        return false, "there is nowhere to send it"
    end

    local text = Taunts.Message(cfg.message,
        ns.SpellName(spellID) or "Taunt", targetName, person and person.name)

    local sent, note = ns.Chat.Post(text, going, person and person.name)
    if sent then lastAt = now end
    return sent, note
end

-- "Your turn" - the other half of a swap, and the half an addon CAN do
-- something about. Bind it to a key with a macro: /zs taunt ask
function Taunts.Ask()
    local cfg = Taunts.Config()
    local person, why = Taunts.CoTank(ns.Roster(), cfg.assigned)

    local going = ns.Chat.Where(cfg.channels)
    for index = #going, 1, -1 do
        if going[index].channel == "WHISPER" and not person then
            table.remove(going, index)
        end
    end
    if #going == 0 then
        return false, "there is nowhere to send it - you are not in a group"
    end

    local text = Taunts.Message(cfg.ask or Taunts.DEFAULT_ASK,
        nil, nil, person and person.name)
    local sent, note = ns.Chat.Post(text, going, person and person.name)

    -- The addon channel too, so a co-tank running this gets a button rather
    -- than a line. A taunt request names no spell: whoever answers presses
    -- their OWN taunt, whatever their class calls it.
    if sent then ns.Comm.Send(ns.Comm.REQUEST, ns.Comm.TAUNT) end

    return sent, note or why
end

---------------------------------------------------------------------------
-- Watching
--
-- One event, on the player's own unit. Not the combat log - that is closed on
-- 12.0 - and not a hook on the action bars, which would miss a macro.
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")

-- The handler, with a name on it: the desktop harness cannot fire an event,
-- so without this the whole path from "a spell was cast" to "something was
-- said" would only ever run for the first time on their screen.
function Taunts.OnCast(spellID)
    if not ns.db then return end
    if not ns.Modules:IsOn("cotanks") then return end

    -- The spec, out of the key everything per-character is filed under. Nil
    -- while the client is still answering 0, and nil is allowed to pass: only
    -- Death Grip is ever refused for being the wrong spec, and a missed
    -- announce is better than a swallowed one.
    local key, known = ns.SpecKey()
    local specID = known and tonumber(key:match(":(%d+)$")) or nil
    if not Taunts.IsTaunt(spellID, specID) then return end

    -- THE TARGET IS READ NOW OR NEVER. The event carries no target, and a
    -- moment later the mob may be dead, out of range or replaced by whatever
    -- you tabbed to. A name that is not readable is left out of the sentence
    -- rather than guessed at.
    local seen = UnitName("target")
    local targetName = (ns.CanCompute(seen) and type(seen) == "string")
        and seen or nil

    return Taunts.Announce(spellID, targetName)
end

function Taunts:Start()
    if self.started then return end
    self.started = true

    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:SetScript("OnEvent", function(_, _, _, _, spellID)
        Taunts.OnCast(spellID)
    end)
end

---------------------------------------------------------------------------
-- THE BUTTON ON YOUR SCREEN
--
-- Owner: "kann man das nicht einbauen, also fertiges dynamisches macro, und
-- als button zum stylen mit icon auswahl?" - so three ways in, and they all
-- run the same Ask:
--
--   this button      click it. Placed in Edit Mode like everything else this
--                    addon draws, and painted by the bar's own painters.
--   a keybinding     Bindings.xml, so it is in the game's own key list under
--                    ZwoelfStuff rather than something you have to build.
--   a macro          made and kept up to date BY the addon, for people who
--                    want it on an action bar with everything else.
--
-- None of them is protected: a chat message on a click is the player's own
-- action, which is the same ground the externals panel already stands on.
---------------------------------------------------------------------------
local button

function Taunts.Frame() return button end

-- WHICH ICON. Your own class taunt unless you picked something else - which
-- is the right default because it is the picture you already press.
function Taunts.Icon()
    local cfg = Taunts.Config()
    if cfg.icon then return cfg.icon end

    local _, class = UnitClass("player")
    for _, entry in ipairs(Taunts.SPELLS) do
        if entry.class == class then
            local texture = ns.SpellTexture(entry.spellID)
            if texture then return texture end
        end
    end
    -- Nothing to go on: the question mark, which is what the game itself uses
    -- for a macro with no icon.
    return 134400
end

function Taunts.Style()
    local cfg = Taunts.Config()
    return {
        borderSize       = math.max(0, cfg.borderSize or 1),
        borderColor      = cfg.borderColor or ns.SurfaceColor(),
        borderTexture    = cfg.borderTexture or "None",
        borderGradient   = cfg.borderGradient,
        backdrop         = cfg.backdrop ~= false,
        backdropColor    = cfg.backdropColor or ns.SurfaceColor(),
        backdropAlpha    = cfg.backdropAlpha or 1,
        backdropTexture  = cfg.backdropTexture or "Blizzard",
        backdropGradient = cfg.backdropGradient,
        iconZoom         = cfg.iconZoom or 0.08,
    }
end

-- WHETHER THE BUTTON IS WANTED, as a pure function of the settings and where
-- you are - the same shape as ShouldAnnounce above, and for the same reason:
-- the desk can ask it every way without a group.
--
--   button           off -> never
--   buttonOnlyInGroup (default on) -> only with somebody else in the group
--   buttonOnlyInRaid  (default off) -> only in a RAID. A dungeon has one
--                    tank; a button asking the other one is asking nobody.
--                    Owner, 2026-08-16: "only when in raid, weil es
--                    eigentlich keinen sinn macht das in einer 5er gruppe
--                    anzuzeigen."
function Taunts.ButtonWanted(cfg, inGroup, inRaid)
    if not cfg.button then return false end
    if cfg.buttonOnlyInGroup ~= false and not inGroup then return false end
    if cfg.buttonOnlyInRaid and not inRaid then return false end
    return true
end

function Taunts:ShouldShow()
    local cfg = Taunts.Config()
    if not ns.Modules:IsOn("cotanks") then return false end
    if Taunts.placing then return true end
    return Taunts.ButtonWanted(cfg, IsInGroup(), IsInRaid())
end

function Taunts:Create()
    if button then return button end

    button = CreateFrame("Button", "ZwoelfStuffTauntButton", UIParent)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp")
    button:Hide()

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)

    button.chrome = ns.CreateChrome(button)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    button.hover = ns.CreateBorder(button, 2, "OVERLAY")
    button.hover:SetColor(ns.UI.C.accent[1], ns.UI.C.accent[2],
        ns.UI.C.accent[3], 1)
    button.hover:Hide()

    button:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Ask for a taunt")
        local person = Taunts.CoTank(ns.Roster(), Taunts.Config().assigned)
        GameTooltip:AddLine(person
            and ("Tells |cffffd100" .. person.name .. "|r to take it")
            or "|cff888888Nobody else here is tanking|r", 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    button:SetScript("OnClick", function()
        local sent, why = Taunts.Ask()
        if not sent then ns.Print("|cffff8040" .. tostring(why) .. ".|r") end
    end)

    self:ApplyLayout()
    return button
end

function Taunts:ApplyLayout()
    if not button then return end
    local cfg = Taunts.Config()
    local size = math.max(16, cfg.size or 44)

    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", cfg.x or -260, cfg.y or -220)
    button:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))
    button:SetAlpha(math.max(0, math.min(1, cfg.alpha or 1)))

    local style = Taunts.Style()
    ns.PaintSurface(button.bg, style)
    ns.PaintBorder(button.chrome, style, false)

    button.icon:SetTexture(Taunts.Icon())
    local zoom = style.iconZoom
    button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

    button:SetShown(self:ShouldShow())
end

function Taunts.Refresh()
    if button then ns.Taunts:ApplyLayout() end
end

function Taunts:SavePosition()
    -- NOTHING, on purpose. Working the position out again from GetCenter
    -- minus UIParent:GetCenter() mixes two coordinate spaces the moment this
    -- carries a scale of its own, and the frame jumps every time edit mode
    -- closes. The mover writes cfg.x and cfg.y exactly; nothing else moves
    -- this. See the long note in Externals.lua.
end

-- Edit Mode is open and this button is one of the things being placed. Same
-- door the co-tank panel and the externals panel are opened through - never
-- by reading a field off EditMode, which is a file-local there and answers
-- nil forever.
function Taunts:SetPlacing(on)
    Taunts.placing = on and true or false
    if not Taunts.placing then self:SavePosition() end
    Taunts.Refresh()
end

---------------------------------------------------------------------------
-- THE MACRO THE ADDON KEEPS
--
-- Owner: "fertiges dynamisches macro". So the addon writes it, names it and
-- keeps its icon in step - all you do is drag it onto a bar.
--
-- SIXTEEN CHARACTERS is the limit on a macro name, which is why it is not
-- called "ZwoelfStuff Taunt". CreateMacro and EditMacro both refuse in
-- combat, so the refusal is a sentence rather than an error.
---------------------------------------------------------------------------
Taunts.MACRO_NAME = "ZS Taunt"
Taunts.MACRO_BODY = "/zs taunt ask"

function Taunts.MacroExists()
    if not GetMacroIndexByName then return false end
    local index = GetMacroIndexByName(Taunts.MACRO_NAME)
    return (index or 0) > 0, index
end

-- Answers what happened, in a sentence, because every one of these is a thing
-- the person pressing the button needs to be told rather than left to guess.
function Taunts.MakeMacro()
    if InCombatLockdown and InCombatLockdown() then
        return false, "not while you are in combat - the game will not let an addon write a macro then"
    end
    if not (CreateMacro and EditMacro) then
        return false, "this client has no macro API"
    end

    local icon = Taunts.Icon()
    local exists, index = Taunts.MacroExists()

    if exists then
        local ok = pcall(EditMacro, index, Taunts.MACRO_NAME, icon,
            Taunts.MACRO_BODY)
        if not ok then return false, "the macro could not be updated" end
        return true, "updated - it is already on your bars"
    end

    -- `nil` for perCharacter: the general tab. A tank plays one character at
    -- a time and a macro that only exists on one of them is a surprise on the
    -- next. The general tab is also the one with room in it.
    local ok, created = pcall(CreateMacro, Taunts.MACRO_NAME, icon,
        Taunts.MACRO_BODY, nil)
    if not ok or not created then
        return false, "no free macro slot - the general tab holds 120"
    end
    return true, "made - drag it onto a bar from the macro window"
end

---------------------------------------------------------------------------
-- The keybinding's way in
--
-- A global, because Bindings.xml runs a plain line of Lua and cannot see this
-- file's locals. The two BINDING_ strings are what the game shows in its own
-- key list; without them the row reads as the raw binding name.
---------------------------------------------------------------------------
BINDING_HEADER_ZWOELFSTUFF = "ZwoelfStuff"
BINDING_NAME_ZWOELFSTUFF_TAUNT_ASK = "Ask the other tank to taunt"

function ZwoelfStuff_TauntAsk()
    local sent, why = Taunts.Ask()
    if not sent then ns.Print("|cffff8040" .. tostring(why) .. ".|r") end
end

---------------------------------------------------------------------------
-- What it would do, printed
---------------------------------------------------------------------------
-- WHAT IT IS ACTUALLY PAINTED WITH. "the colour does nothing" has two very
-- different causes - a setting that never reached the painter, and a black
-- line on a black plate - and this tells them apart in one line.
local function StyleLine(style)
    local colour = style.borderColor or ns.SurfaceColor()
    -- FLOORED. A colour channel is a fraction; %02x on 0.77 * 255 truncates
    -- on the client's Lua 5.1 and RAISES on 5.4. It survived this long
    -- because the default border is black and 0.0 is integer-representable -
    -- so the crash was waiting for the first person to pick a colour and then
    -- type /zs externals.
    local red = math.floor((colour[1] or 0) * 255)
    local green = math.floor((colour[2] or 0) * 255)
    local blue = math.floor((colour[3] or 0) * 255)
    return string.format(
        "border %d px, |cff%02x%02x%02x#%02x%02x%02x|r, texture %s; backdrop %s",
        style.borderSize or 0,
        red, green, blue, red, green, blue,
        tostring(style.borderTexture),
        style.backdrop == false and "off" or "on")
end

function Taunts:Dump()
    ns.Print("|cffffd100taunts|r - what a taunt of yours would do.")

    local cfg = Taunts.Config()
    local ok, why = Taunts.ShouldAnnounce(cfg, IsInGroup(), InInstance())
    ns.Print("  announce: " .. (ok and "|cff40ff40yes|r"
        or ("|cff888888no - " .. tostring(why) .. "|r")))

    local person = Taunts.CoTank(ns.Roster(), cfg.assigned)
    ns.Print("  the other tank: " .. (person and ("|cff40ff40" .. person.name .. "|r")
        or "|cff888888nobody here|r"))

    local going = ns.Chat.Where(cfg.channels)
    local names = {}
    for _, where in ipairs(going) do names[#names + 1] = where.channel end
    ns.Print("  channels: " .. (#names > 0 and table.concat(names, ", ")
        or "|cff888888nowhere|r"))

    ns.Print("  it would say: |cffffd100"
        .. Taunts.Message(cfg.message, "Dark Command", "Heavyweight Golem",
            person and person.name) .. "|r")

    ns.Print("  the button: " .. (Taunts.Config().button and "on" or "off")
        .. ", " .. StyleLine(Taunts.Style()))

    local _, class = UnitClass("player")
    local mine = {}
    for _, entry in ipairs(Taunts.SPELLS) do
        if entry.class == class then
            mine[#mine + 1] = ns.SpellName(entry.spellID)
                or tostring(entry.spellID)
        end
    end
    ns.Print("  watching: " .. (#mine > 0 and table.concat(mine, ", ")
        or "|cff888888your class has no taunt in the list|r"))
end
