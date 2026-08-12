---------------------------------------------------------------------------
-- RaidBar - the buttons a raid leader needs in his hands.
--
-- Owner, 2026-08-12: "ich moechte ein neues feature und m+ und raids -> Raid
-- Bar. das ist eine Funktion aus Method raid tools, da kann ich eine bar
-- erstellen, welche alle marker, pings anzeigt, pull cooldown startet,
-- abbricht, ready check macht und gruppen buffs anzeigt mit fenstern etc."
-- And how it should be built: "nutze dazu das bewaehrte layout wo ich mir die
-- bar zusammen stellen kann."
--
-- SO IT IS THE EXTERNALS PANEL'S SHAPE, not a second invention: a lattice of
-- places, a list on the right to pick from, one thing per place. The same
-- gesture builds both, and the same self test walks the arithmetic - see
-- ns.LatticeCell, which is now shared rather than copied.
--
-- WHAT IS DIFFERENT, and it decides most of this file: nearly every button
-- here does something the game will not let an addon do on its own.
--
--   * Putting a skull on the target, placing a flare on the ground and
--     sending a ping are PROTECTED on this patch. Checked, not assumed:
--     MRT's marks bar switches to SecureActionButtonTemplate the moment it
--     detects Midnight, and calls SetRaidTarget directly only on the older
--     clients. So every one of those buttons is a SecureActionButton and the
--     PLAYER presses it; this addon never does.
--   * A ready check and a pull timer are not. They are plain calls, and they
--     are refused by the game itself when you have no lead or assist - which
--     is a better refusal than one written here, because it cannot go stale.
--
-- AND THEREFORE: THE BAR IS NOT REBUILT IN COMBAT. A protected button's
-- attributes, size, place and visibility are all frozen for the fight. Every
-- path that would touch them goes through ApplyLayout, which parks the work
-- and does it on the way out of combat. This is not caution - a SetAttribute
-- in combat is a Lua error in everybody's chat frame, once per pull.
---------------------------------------------------------------------------
local _, ns = ...

local RaidBar = {}
ns.RaidBar = RaidBar

---------------------------------------------------------------------------
-- WHAT CAN GO ON THE BAR
--
-- One table, and the page's third column is drawn from it - so a button
-- added here appears in the picker by existing, the same rule the externals
-- list follows.
--
-- kind:   how the click is delivered. "marker", "worldmarker" and "ping" are
--         secure and carry a macro; "call" is ours and runs Lua.
-- group:  the heading it is filed under in the picker.
-- label:  what it is called. Looked up through L at DRAW time, never here.
---------------------------------------------------------------------------
-- The eight raid target icons, in the game's own order. Their names are the
-- client's own globals when it has them - RAID_TARGET_1 is "Star" in English
-- and the right word in every other language - and the English fallback is
-- for the harness, which has no globals at all.
local MARK_NAMES = {
    "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull",
}

-- WHICH RAID ICON A WORLD MARKER IS DRAWN WITH. Blizzard ships no separate
-- art for the eight flares, and their colours do not run in the same order as
-- the raid icons: world marker 1 is blue, which is the SQUARE's colour.
-- Read off MRT's worldMarksList rather than guessed, so the button on the bar
-- is the colour of the flare that lands on the floor.
local WORLD_MARK_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }

local ACTIONS = {}
RaidBar.ACTIONS = ACTIONS

local function Add(entry)
    ACTIONS[#ACTIONS + 1] = entry
    return entry
end

for index = 1, 8 do
    Add({
        key = "mark" .. index, kind = "marker", group = "Markers",
        marker = index, label = MARK_NAMES[index],
        -- The client's own word for it, when there is one.
        globalLabel = "RAID_TARGET_" .. index,
        texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index,
    })
end

Add({
    key = "markclear", kind = "marker", group = "Markers", marker = 0,
    label = "Clear markers",
    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
})

for index = 1, 8 do
    Add({
        key = "world" .. index, kind = "worldmarker", group = "World markers",
        marker = index, label = "World marker " .. index,
        texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
            .. WORLD_MARK_ICON[index],
    })
end

Add({
    key = "worldclear", kind = "worldmarker", group = "World markers",
    marker = 0, label = "Clear world markers",
    texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
})

-- THE PINGS. The game's own ping wheel, reached the only way an addon may
-- reach it: a macro on a button the player presses. The atlases are the
-- client's own chat-ping art, which is what the wheel itself draws - so the
-- button on the bar is the picture people already know.
local PINGS = {
    { key = "pingattack",  label = "Attack",     atlas = "ping_chat_attack",
      command = "attack",  global = "PING_TYPE_ATTACK" },
    { key = "pingassist",  label = "Assist",     atlas = "ping_chat_assist",
      command = "assist",  global = "PING_TYPE_ASSIST" },
    { key = "pingonmyway", label = "On my way",  atlas = "ping_chat_onmyway",
      command = "onmyway", global = "PING_TYPE_ON_MY_WAY" },
    { key = "pingwarning", label = "Warning",    atlas = "ping_chat_warning",
      command = "warning", global = "PING_TYPE_WARNING" },
}

for _, ping in ipairs(PINGS) do
    Add({
        key = ping.key, kind = "ping", group = "Ping", label = ping.label,
        atlas = ping.atlas, command = ping.command, globalLabel = ping.global,
    })
end

-- OURS. Three things that are not protected, so they are plain calls with a
-- plain script - and each one says why it did nothing when it does nothing.
Add({
    key = "readycheck", kind = "call", group = "The group",
    label = "Ready check", needsLead = true,
    texture = "Interface\\RaidFrame\\ReadyCheck-Ready",
    Run = function() return RaidBar.ReadyCheck() end,
})

Add({
    key = "pull", kind = "call", group = "The group", label = "Pull timer",
    needsLead = true,
    texture = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    -- Left starts the timer, right cancels it. Two things on one button
    -- because they are the same thought a second apart, and because a bar
    -- with a Pull and an Unpull on it is a bar with a button you press once
    -- a month.
    Run = function(_, button)
        if button == "RightButton" then return RaidBar.Pull(0) end
        return RaidBar.Pull(RaidBar.Config().pullSeconds or 10)
    end,
})

Add({
    key = "raidcheck", kind = "call", group = "The group", label = "Raid check",
    -- Our own window, so it wears our own mark. The client has no picture for
    -- "is everybody fed", and a borrowed icon that means something else in the
    -- game is worse than none.
    texture = ns.ICON_TEXTURE,
    Run = function() return ns.RaidCheck:Toggle() end,
})

local byKey = {}
for _, entry in ipairs(ACTIONS) do byKey[entry.key] = entry end

function RaidBar.Get(key) return byKey[key] end

-- WHAT TO CALL IT ON SCREEN. The client's own word wins - a German player
-- reading "Totenkopf" on the eighth marker is reading the word the raid
-- leader just said out loud - and our own English falls back through L for
-- everything the client has no name for.
function RaidBar.Label(entry)
    if not entry then return "" end
    if entry.globalLabel then
        local word = _G[entry.globalLabel]
        if type(word) == "string" and word ~= "" then return word end
    end
    return ns.L[entry.label]
end

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
RaidBar.MAX_ROWS = 4
RaidBar.MAX_COLUMNS = 16
RaidBar.MAX_SLOTS = RaidBar.MAX_ROWS * RaidBar.MAX_COLUMNS

-- HOW MANY PLACES CAN CARRY A KEY. Twelve, and the number is in Bindings.xml
-- as twelve <Binding> lines - the file is static, so this is one of the very
-- few numbers in this addon that exists in two places. The self test holds
-- them together.
RaidBar.KEYS = 12

local function Clamp(value, low, high)
    value = math.floor(tonumber(value) or low)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- THE BAR EVERYBODY WANTS ON THE FIRST EVENING, laid out once.
--
-- The externals panel deliberately starts empty: it is a set you build for
-- your own dungeons, and there is no sensible guess. This one is the
-- opposite - eight markers, a clear, a ready check and a pull is what a marks
-- bar IS, and somebody who has to assemble that by hand before the feature
-- does anything has been handed a kit, not a feature.
--
-- Seeded ONCE, under its own flag. A migration that runs twice would refill
-- places somebody has emptied on purpose.
local SEED = {
    "mark1", "mark2", "mark3", "mark4", "mark5", "mark6", "mark7", "mark8",
    "markclear", "readycheck", "pull", "raidcheck",
}

function RaidBar.Config()
    ns.db.raidBar = ns.db.raidBar or {}
    local cfg = ns.db.raidBar
    cfg.cells = cfg.cells or {}

    if not cfg.seeded then
        cfg.seeded = true
        for index, key in ipairs(SEED) do
            if cfg.cells[index] == nil then cfg.cells[index] = key end
        end
    end

    cfg.rows = Clamp(cfg.rows or 1, 1, RaidBar.MAX_ROWS)
    cfg.columns = Clamp(cfg.columns or 12, 1, RaidBar.MAX_COLUMNS)
    cfg.pullSeconds = Clamp(cfg.pullSeconds or 10, 1, 60)

    return cfg
end

function RaidBar.Rows() return RaidBar.Config().rows end
function RaidBar.Columns() return RaidBar.Config().columns end

function RaidBar.Count()
    local cfg = RaidBar.Config()
    return cfg.rows * cfg.columns
end

function RaidBar.SetRows(value)
    RaidBar.Config().rows = Clamp(value, 1, RaidBar.MAX_ROWS)
    RaidBar.Refresh()
end

function RaidBar.SetColumns(value)
    RaidBar.Config().columns = Clamp(value, 1, RaidBar.MAX_COLUMNS)
    RaidBar.Refresh()
end

function RaidBar.ActionAt(index)
    return RaidBar.Config().cells[index]
end

function RaidBar.SetSlot(index, key)
    if index < 1 or index > RaidBar.MAX_SLOTS then return end
    if key and not byKey[key] then return end
    local cfg = RaidBar.Config()

    -- One button in one place. Putting it somewhere else MOVES it, the same
    -- rule the externals slots follow - two Skulls on one bar is two places
    -- doing one job and a key bound to the wrong one.
    if key then
        for other, held in pairs(cfg.cells) do
            if held == key and other ~= index then cfg.cells[other] = nil end
        end
    end

    cfg.cells[index] = key
    RaidBar.Refresh()
end

function RaidBar.ClearSlot(index)
    RaidBar.Config().cells[index] = nil
    RaidBar.Refresh()
end

function RaidBar.SlotOf(key)
    local cfg = RaidBar.Config()
    for index = 1, RaidBar.Count() do
        if cfg.cells[index] == key then return index end
    end
    return nil
end

function RaidBar.IsPicked(key) return RaidBar.SlotOf(key) ~= nil end

function RaidBar.Pick(key, preferred)
    if not byKey[key] then return nil end
    if RaidBar.IsPicked(key) then return RaidBar.SlotOf(key) end

    local cfg = RaidBar.Config()
    if preferred and preferred >= 1 and preferred <= RaidBar.Count() then
        RaidBar.SetSlot(preferred, key)
        return preferred
    end
    for index = 1, RaidBar.Count() do
        if not cfg.cells[index] then
            RaidBar.SetSlot(index, key)
            return index
        end
    end
    return nil
end

function RaidBar.Drop(key)
    local index = RaidBar.SlotOf(key)
    if index then RaidBar.ClearSlot(index) end
end

-- Every place that has something in it, in bar order. One list, two readers:
-- the bar draws from it and a key presses into it. Unlike the externals
-- panel, a place is never dropped for who is in the group - a marker is a
-- marker whoever is standing next to you.
function RaidBar.Shown()
    local out = {}
    local cfg = RaidBar.Config()
    for index = 1, RaidBar.Count() do
        if cfg.cells[index] then out[#out + 1] = cfg.cells[index] end
    end
    return out
end

---------------------------------------------------------------------------
-- WHAT A CLICK ACTUALLY SENDS
--
-- Pure and exported, because it is the one thing about this feature the
-- desktop can check: the harness has no secure buttons and no game to press
-- them, but a macro with the wrong word in it is a button that does nothing
-- in a raid, and that is exactly the failure nobody notices until it matters.
--
-- The slash commands come from the CLIENT'S OWN globals. SLASH_TARGET_MARKER1
-- is "/tm" in English and something else in Spanish and Portuguese, and a
-- hardcoded "/tm" is a bar that silently does nothing for those players -
-- which is a real bug MRT carries a special case for.
---------------------------------------------------------------------------
function RaidBar.MarkerMacro(index, clear, command)
    command = command or SLASH_TARGET_MARKER1 or "/tm"
    if clear or index == 0 then return command .. " 0" end
    -- The bang is "toggle": pressing the same marker twice takes it off,
    -- which is what everybody expects from a marks bar and what the game's
    -- own flyout does.
    return command .. " !" .. index
end

function RaidBar.WorldMarkerMacro(index, clear, setCommand, clearCommand)
    setCommand = setCommand or SLASH_WORLD_MARKER1 or "/wm"
    clearCommand = clearCommand or SLASH_CLEAR_WORLD_MARKER1 or "/cwm"
    if clear or index == 0 then
        return clearCommand .. " " .. (ALL or "all")
    end
    return setCommand .. " " .. index
end

-- A ping goes at whatever the cursor is over, which for a bar button is the
-- bar. So it is aimed at the TARGET, the way MRT's row is - "attack that",
-- pressed while you are looking at the thing you mean.
function RaidBar.PingMacro(command, slash, word)
    slash = slash or SLASH_PING1 or "/ping"
    return slash .. " [@target] " .. (word or command)
end

---------------------------------------------------------------------------
-- The two calls that are not protected
---------------------------------------------------------------------------
-- Whether the game would let you. Asked before the call rather than after,
-- because the client's own refusal is a red line in the chat frame that does
-- not say which addon caused it.
function RaidBar.MayLead()
    if not IsInGroup or not IsInGroup() then return false, "not in a group" end
    if IsInRaid and IsInRaid() then
        local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
        local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
        if not (ns.Truth(leader, false) or ns.Truth(assist, false)) then
            return false, "no lead"
        end
    end
    return true
end

function RaidBar.ReadyCheck()
    local may, why = RaidBar.MayLead()
    if not may then
        ns.Print("|cffff8040" .. (why == "not in a group"
            and ns.L["You are not in a group."]
            or ns.L["You need lead or assist for that."]) .. "|r")
        return false
    end
    if DoReadyCheck then DoReadyCheck() end
    return true
end

-- THE PULL TIMER IS THE GAME'S OWN.
--
-- C_PartyInfo.DoCountdown is the countdown Blizzard added for exactly this,
-- and it is the one every boss mod already watches - so one call puts the
-- number on everybody's screen, including the people running BigWigs or DBM
-- and the people running neither. Sending private messages on those two
-- addons' channels as well, which MRT does, would give anybody running them
-- two bars counting the same seconds.
--
-- Zero cancels, which is the same call and not a second feature.
function RaidBar.Pull(seconds)
    seconds = math.floor(tonumber(seconds) or 0)

    local may, why = RaidBar.MayLead()
    if not may then
        ns.Print("|cffff8040" .. (why == "not in a group"
            and ns.L["You are not in a group."]
            or ns.L["You need lead or assist for that."]) .. "|r")
        return false
    end

    -- 12.x REFUSES TO START ONE IN COMBAT, and says so through its own lock.
    -- Checked rather than attempted: the failure is otherwise a silent
    -- nothing on a button somebody pressed on purpose.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("|cffff8040" .. ns.L["Not while in combat"] .. ".|r")
        return false
    end

    if not (C_PartyInfo and C_PartyInfo.DoCountdown) then
        return false
    end

    C_PartyInfo.DoCountdown(seconds)
    if seconds > 0 then
        ns.Print(string.format("|cffffd100%s|r %d", ns.L["Pull"], seconds))
    else
        ns.Print("|cff888888" .. ns.L["Cancel the pull"] .. "|r")
    end
    return true
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local panel
local pending = false

function RaidBar.Frame() return panel end

function RaidBar.Style()
    local cfg = RaidBar.Config()
    return {
        borderSize      = math.max(0, cfg.borderSize or 1),
        borderColor     = cfg.borderColor or { 0, 0, 0 },
        borderTexture   = cfg.borderTexture or "None",
        borderGradient  = cfg.borderGradient,
        backdrop        = cfg.backdrop ~= false,
        backdropColor   = cfg.backdropColor or { 0, 0, 0 },
        backdropAlpha   = cfg.backdropAlpha or 0.9,
        backdropTexture = cfg.backdropTexture or "Blizzard",
        backdropGradient = cfg.backdropGradient,
        iconZoom        = cfg.iconZoom or 0.06,
    }
end

function RaidBar.BindingName(index)
    return "CLICK ZwoelfStuffRaidBar" .. index .. ":LeftButton"
end

function RaidBar.Key(index)
    if not GetBindingKey then return nil end
    local ok, key = pcall(GetBindingKey, RaidBar.BindingName(index))
    if not ok then return nil end
    return ns.ShortKey(key)
end

---------------------------------------------------------------------------
-- ONE PLACE ON THE BAR
--
-- A SecureActionButton whichever action lands in it, including the three that
-- do not need to be one. Two kinds of button would mean rebuilding the frame
-- whenever a place changes from a marker to a ready check - and a frame
-- cannot be un-made in this game, so that is a leak with extra steps.
--
-- A secure button with no `type` set runs its OnClick script like any other
-- button, which is exactly what the unprotected three want.
---------------------------------------------------------------------------
local function BuildSlot(index)
    local slot = CreateFrame("Button", "ZwoelfStuffRaidBar" .. index, panel,
        "SecureActionButtonTemplate")
    slot:SetFrameStrata("MEDIUM")

    -- BOTH DIRECTIONS, and this is the one that has cost this addon an
    -- evening before: with "AnyUp" alone a secure button never fires for
    -- anybody who has "cast on key down" switched on, which is the default.
    slot:RegisterForClicks("AnyDown", "AnyUp")

    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints(slot)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)

    slot.chrome = ns.CreateChrome(slot)

    slot.key = ns.UI.Label(slot, "", 10, ns.UI.C.textDim)
    slot.key:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -2, -2)
    slot.key:SetWordWrap(false)

    slot.hover = ns.CreateBorder(slot, 2, "OVERLAY")
    slot.hover:SetColor(ns.UI.C.accent[1], ns.UI.C.accent[2],
        ns.UI.C.accent[3], 1)
    slot.hover:Hide()

    slot:SetScript("OnEnter", function(self)
        self.hover:Show()
        local entry = self.action and byKey[self.action]
        if not (GameTooltip and entry) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(RaidBar.Label(entry))
        if entry.kind == "marker" and entry.marker ~= 0 then
            GameTooltip:AddLine(ns.L["Right-click clears every marker."],
                0.61, 0.64, 0.69)
        elseif entry.kind == "worldmarker" and entry.marker ~= 0 then
            GameTooltip:AddLine(ns.L["Right-click takes this one away."],
                0.61, 0.64, 0.69)
        elseif entry.key == "pull" then
            GameTooltip:AddLine(string.format("%s %d - %s",
                ns.L["Pull"], RaidBar.Config().pullSeconds or 10,
                ns.L["Right-click cancels it."]), 0.61, 0.64, 0.69)
        end
        GameTooltip:Show()
    end)

    slot:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- THE UNPROTECTED THREE. A secure button whose `type` was cleared falls
    -- through to here; one whose type is set never reaches it, because the
    -- game handles the press itself.
    slot:SetScript("OnClick", function(self, button)
        local entry = self.action and byKey[self.action]
        if entry and entry.Run then entry.Run(self, button) end
    end)

    return slot
end

---------------------------------------------------------------------------
-- WHAT A PLACE IS TOLD TO DO
--
-- Every attribute is written here and nowhere else, so "which attributes does
-- a world marker need" has one answer. Attributes are only ever set out of
-- combat - ApplyLayout is the only caller and it refuses in combat.
---------------------------------------------------------------------------
local function DressSlot(slot, key)
    local entry = key and byKey[key]
    slot.action = key

    -- Cleared first, every time. A place that was a marker and is now a ready
    -- check would otherwise keep casting the marker macro, because the game
    -- reads the attribute and never asks our script.
    slot:SetAttribute("type", nil)
    slot:SetAttribute("macrotext", nil)
    slot:SetAttribute("macrotext1", nil)
    slot:SetAttribute("macrotext2", nil)
    slot:SetAttribute("marker", nil)
    slot:SetAttribute("action1", nil)
    slot:SetAttribute("action2", nil)

    if not entry then return end

    if entry.kind == "marker" then
        slot:SetAttribute("type", "macro")
        slot:SetAttribute("macrotext1",
            RaidBar.MarkerMacro(entry.marker, entry.marker == 0))
        slot:SetAttribute("macrotext2", RaidBar.MarkerMacro(0, true))

    elseif entry.kind == "worldmarker" then
        -- THE SECURE HANDLER, not a macro, and the difference is a patch old:
        -- 12.x carries a "worldmarker" button type that takes the number and
        -- the action as attributes. MRT switched to it for Midnight and left
        -- the macro route for the older clients; so does this, because a
        -- client that has no such type would silently do nothing.
        if RaidBar.HasWorldMarkerType() then
            slot:SetAttribute("type", "worldmarker")
            slot:SetAttribute("marker", tostring(entry.marker))
            slot:SetAttribute("action1", entry.marker == 0 and "clear" or "set")
            slot:SetAttribute("action2", "clear")
        else
            slot:SetAttribute("type", "macro")
            slot:SetAttribute("macrotext1",
                RaidBar.WorldMarkerMacro(entry.marker, entry.marker == 0))
            slot:SetAttribute("macrotext2",
                RaidBar.WorldMarkerMacro(entry.marker, true))
        end

    elseif entry.kind == "ping" then
        slot:SetAttribute("type", "macro")
        slot:SetAttribute("macrotext",
            RaidBar.PingMacro(entry.command, nil,
                entry.globalLabel and _G[entry.globalLabel] or nil))
    end
end

-- Whether this client knows the secure world-marker button. Its own function
-- so the harness can answer no and the 12.1 sweep has one place to look.
function RaidBar.HasWorldMarkerType()
    -- The type arrived with the same patch as the restriction it works
    -- around. C_Ping is the marker for that generation of the API and is what
    -- MRT keys its own switch off.
    return C_Ping ~= nil
end

function RaidBar:Create()
    if panel then return panel end

    panel = CreateFrame("Frame", "ZwoelfStuffRaidBar", UIParent)
    panel:SetSize(200, 26)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel.slots = {}

    RaidBar.panel = panel
    self:ApplyLayout()
    return panel
end

---------------------------------------------------------------------------
-- WHERE IT SITS AND WHAT IS ON IT
--
-- The one walk. Edit Mode moves the bar, the options page rearranges it and
-- the roster changes what it should be showing, and all three come through
-- here rather than each doing a version of it.
---------------------------------------------------------------------------
function RaidBar:ApplyLayout()
    if not panel then return end

    -- IN COMBAT, NOTHING. Every line below touches a protected button, and
    -- the game answers a SetAttribute in a fight with an error in everybody's
    -- chat frame. Parked and done on the way out - see the watcher.
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return
    end
    pending = false

    local cfg = RaidBar.Config()
    local size = cfg.size or 26
    local gap = cfg.gap or 2
    local rows, columns = cfg.rows, cfg.columns
    local vertical = cfg.growth == "down"

    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -220)

    local shown = 0
    for _, key in ipairs(RaidBar.Shown()) do
        shown = shown + 1
        local slot = panel.slots[shown] or BuildSlot(shown)
        panel.slots[shown] = slot

        local column, line = ns.LatticeCell(shown, rows, columns, vertical)

        slot:SetSize(size, size)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", panel, "TOPLEFT",
            column * (size + gap), -(line * (size + gap)))

        DressSlot(slot, key)

        local entry = byKey[key]
        if entry and entry.atlas and slot.icon.SetAtlas then
            slot.icon:SetAtlas(entry.atlas)
        else
            slot.icon:SetTexture(entry and entry.texture or nil)
        end

        -- The key belongs to the PLACE, so only the first twelve wear one -
        -- there are twelve <Binding> lines and a thirteenth place could never
        -- have a key however it is drawn.
        slot.key:SetText(shown <= RaidBar.KEYS and (RaidBar.Key(shown) or "") or "")

        local style = RaidBar.Style()
        ns.PaintSurface(slot.bg, style)
        ns.PaintBorder(slot.chrome, style, false)
        local zoom = style.iconZoom
        -- An atlas carries its own coordinates; cropping it draws a corner of
        -- the wrong picture. Only our square icon files are zoomed.
        if not (entry and entry.atlas) then
            slot.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end

        slot:Show()
    end

    for index = shown + 1, #panel.slots do
        DressSlot(panel.slots[index], nil)
        panel.slots[index]:Hide()
    end

    local wide, tall = ns.LatticeExtent(shown, rows, columns, vertical)
    panel:SetSize(math.max(1, wide * size + (wide - 1) * gap),
        math.max(1, tall * size + (tall - 1) * gap))

    panel:SetScale(math.max(0.3, math.min(3, cfg.scale or 1)))
    panel:SetAlpha(math.max(0, math.min(1, cfg.alpha or 1)))

    panel:SetShown(shown > 0 and self:ShouldShow())
end

function RaidBar:ShouldShow()
    if not ns.Modules:IsOn("raidbar") then return false end
    if RaidBar.placing then return true end
    local cfg = RaidBar.Config()
    if cfg.onlyInGroup ~= false and not IsInGroup() then return false end
    if cfg.onlyInInstance then
        local _, kind = IsInInstance()
        if kind == "none" then return false end
    end
    return true
end

function RaidBar.Refresh()
    if not panel then return end
    RaidBar:ApplyLayout()
end

-- Whether the bar is currently one fight behind. The diagnostics line reads
-- it, because "my bar did not change" and "my bar is waiting for the pull to
-- end" look identical on screen.
function RaidBar.Pending() return pending end

-- Edit Mode writes cfg.x and cfg.y exactly and ApplyLayout puts the bar
-- there. Nothing else moves this frame, so there is no position to measure
-- back - the same fix the externals panel carries, and for the same reason:
-- GetCenter answers in the frame's own scale and the bar jumped every time.
function RaidBar:SavePosition() end

function RaidBar:SetPlacing(on)
    RaidBar.placing = on and true or false
    RaidBar.Refresh()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    -- Out of combat, and something was parked. This is the whole reason the
    -- event is registered: the bar catches up the moment it is allowed to.
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    RaidBar.Refresh()
end)

---------------------------------------------------------------------------
-- /zs raidbar
---------------------------------------------------------------------------
function RaidBar:Dump()
    ns.Print("|cffffd100raid bar|r - what is on it, and what a press would send.")

    if not ns.Modules:IsOn("raidbar") then
        ns.Print("  |cffff4040The Raid Bar module is switched off.|r")
    end
    if pending then
        ns.Print("  |cffff8040Waiting for combat to end before it is rebuilt.|r")
    end

    local cfg = RaidBar.Config()
    local places = {}
    for index = 1, RaidBar.Count() do
        places[#places + 1] = tostring(cfg.cells[index] or "-")
    end
    ns.Print(string.format("  %d x %d, running %s: %s",
        cfg.rows, cfg.columns, cfg.growth == "down" and "down" or "across",
        table.concat(places, " ")))

    local may, why = RaidBar.MayLead()
    ns.Print(string.format("  ready check and pull: %s",
        may and "|cff40ff40allowed|r"
            or ("|cffff8040" .. tostring(why) .. "|r")))
    ns.Print(string.format("  secure world markers: %s",
        RaidBar.HasWorldMarkerType() and "yes (12.x button type)"
            or "no (macro route)"))

    for index = 1, RaidBar.Count() do
        local key = cfg.cells[index]
        local entry = key and byKey[key]
        if entry then
            local sends = "-"
            if entry.kind == "marker" then
                sends = RaidBar.MarkerMacro(entry.marker, entry.marker == 0)
            elseif entry.kind == "worldmarker" then
                sends = RaidBar.HasWorldMarkerType()
                    and ("worldmarker " .. entry.marker)
                    or RaidBar.WorldMarkerMacro(entry.marker, entry.marker == 0)
            elseif entry.kind == "ping" then
                sends = RaidBar.PingMacro(entry.command)
            elseif entry.kind == "call" then
                sends = "runs in the addon"
            end
            ns.Print(string.format("    %d %s |cff888888%s|r  %s", index,
                RaidBar.Label(entry), sends,
                index <= RaidBar.KEYS and (RaidBar.Key(index) or "") or ""))
        end
    end
end
