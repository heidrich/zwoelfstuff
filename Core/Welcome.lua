---------------------------------------------------------------------------
-- Welcome - the first window a character ever sees.
--
-- Owner, 2026-08-09, choosing when it opens: "option 3 und option im addon
-- das neu zu starten" - once per character, once more when an update brings a
-- module that character has never been offered, and reachable on purpose at
-- any time from Settings or /zs welcome.
--
-- WHAT IT IS FOR, and it is only this: which of the features do you want
-- running. It is not a tour, it does not explain the bars, and it has no
-- "next" button - a first-run wizard with four pages is three pages nobody
-- reads and one decision buried in them.
--
-- WHY IT WRITES THE ANSWER WHEN IT CLOSES, not when a switch is flipped: the
-- switches take effect immediately - that is what Modules:Set does - but
-- "this character has been asked" is only true once they have finished
-- asking. Somebody who reloads mid-way is asked again, which is the right way
-- round.
---------------------------------------------------------------------------
local _, ns = ...

local Welcome = {}
ns.Welcome = Welcome

-- 560 UNTIL THE EIGHTH MODULE. Owner, with a photograph of the window:
-- "hier musste noch den screen breiter machen."
--
-- What the picture showed was two faults on top of each other, and widening
-- only cures one of them. The row itself was letting the second line run
-- under the control - see UI.Row, where the sublabel now stops at the slot
-- like the label always has - so the raid bar's blurb was drawn straight
-- through the NEW badge. With that fixed the sentence would have been CUT
-- instead, which is better and still not right: it is one of eight rows the
-- whole window exists to let somebody read.
--
-- 700 gives the longest blurb its line and takes the foot's three wrapped
-- lines down to two. It is a dialog, not the main window, and it is centred
-- on a screen that is holding a 1382-wide one behind it.
local WIDTH = 700
local PAD = 20
local ROW_H = 44

-- NO LIT HEADER HERE EITHER. It was a gradient - UI.KeyArt, now gone - and
-- the owner threw it out of the rail on sight: "lass den verlauf weg, das
-- sieht unmoeglich aus." Keeping it on this one window would leave the addon
-- with exactly one surface that looks like that, which is worse than none.
--
-- HEAD_TOP stays as a name at nought rather than being deleted from thirty
-- offsets below: every one of them is written as HEAD_TOP + something, and
-- editing thirty numbers to remove one is how a layout picks up a typo.
local HEAD_TOP = 0

local frame

local function BuildFrame()
    local UI = ns.UI
    local C = UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffWelcomeFrame", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    -- The addon's own mark, the same file the game shows in its addon list.
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEAD_TOP + PAD))
    logo:SetTexture("Interface\\AddOns\\ZwoelfStuff\\Media\\logo")

    -- The brand in its two colours, which is how the TOC, the minimap tooltip
    -- and every chat line already write it. One spelling everywhere.
    local title = UI.Label(frame, "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r",
        UI.FS.title, C.text)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)

    local version = UI.Label(frame, "", UI.FS.meta, C.textGhost)
    version:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -PAD, -PAD - 8)
    version:SetJustifyH("RIGHT")

    -- ONE LINE UNDER THE NAME, AND IT SAYS WHAT THE ADDON IS. The strapline
    -- that stood here until 2026-08-15 counted the features and told you to
    -- pick some - narrating the rows under it - and went on his word ("den
    -- text raus"). This one is his too (2026-08-16): "A Tank and Group Play
    -- addon" - not a count, not an instruction, the one sentence a stranger
    -- needs. The rule stays at its fixed offset, so nothing below moves.
    local subline = UI.Label(frame, "A Tank and Group Play addon", UI.FS.meta,
        C.textDim)
    subline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEAD_TOP + PAD + 62))
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEAD_TOP + PAD + 62))

    ---------------------------------------------------------------------
    -- SOMEBODY ELSE IS ALREADY DOING ONE OF THESE.
    --
    -- Owner, 2026-08-15: "baue direkt noch einen check ein, ob der user einen
    -- anderen cdm nutzt ... eine warnung und eine wahl."
    --
    -- The Cooldown Manager is the only feature here that can COLLIDE. Two
    -- addons claiming Blizzard's cooldown frames produce a broken screen that
    -- neither of them can diagnose, because the frames belong to neither.
    --
    -- ONE CONTROL, NOT TWO. The choice he asked for is the switch on the
    -- Cooldowns row directly underneath - this strip is the reason for it, not
    -- a second way to set it. A warning with its own pair of buttons beside a
    -- toggle that sets the same thing is two answers to one question, and the
    -- day they disagree is the day nobody can say which one won.
    --
    -- IT IS ALSO NOT AN OFFER TO SWITCH THEIR ADDON OFF. That can be done -
    -- C_AddOns.DisableAddOn plus a reload, which is how EllesmereUI's own
    -- power button works - and the first window this addon ever shows is not
    -- where somebody's other addons get turned off. That offer lives on the
    -- Cooldowns page, where it is a deliberate press.
    ---------------------------------------------------------------------
    -- IT SITS IN THE LAYOUT CHAIN WHETHER IT SHOWS OR NOT, and carries its own
    -- top margin inside its HEIGHT rather than in its anchor. A strip anchored
    -- ten pixels down leaves those ten pixels behind when it is hidden, and
    -- the rows below drift by ten on every screen that has no conflict - which
    -- is nearly all of them, so the wrong case would be the one nobody sees.
    local warn = CreateFrame("Frame", nil, frame)
    warn:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, 0)
    warn:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", 0, 0)
    warn:SetHeight(0.01)
    warn:Hide()
    -- C.warning AND NOT C.danger. The palette says danger is for
    -- "destructive actions ONLY" - a button that will delete something. This
    -- is a state of the world somebody should know about, and painting it in
    -- the delete colour is how that colour stops meaning delete.
    UI.Fill(warn, "BACKGROUND", C.surface)
    local warnEdge = ns.CreateBorder(warn, 1, "BORDER")
    warnEdge:SetColor(C.warning[1], C.warning[2], C.warning[3], 0.55)

    warn.text = UI.Label(warn, "", UI.FS.meta, C.text)
    warn.text:SetPoint("TOPLEFT", warn, "TOPLEFT", 12, -9)
    warn.text:SetWidth(WIDTH - PAD * 2 - 24)
    warn.text:SetJustifyH("LEFT")

    -- THE WAY OUT OF THE CONFLICT, offered where the conflict is reported.
    -- Owner, 2026-08-15: "einen button einbauen, das man andere cdm abstellt,
    -- das kann elle ui auch."
    --
    -- Two steps and a four-second disarm, the same as deleting a profile -
    -- this reloads the interface, and an unexpected reload reads as a crash.
    --
    -- ONLY WHEN THERE IS EXACTLY ONE. Two addons cannot be named on one
    -- button, and a button whose label cannot state what the press does has
    -- no business being the first thing somebody sees. With more than one the
    -- strip sends them to the Cooldowns page, which has a button each.
    warn.armed = false
    warn.button = UI.Button(warn, "", nil, function()
        local folder = warn.folder
        if not folder then return end
        if not warn.armed then
            warn.armed = true
            warn.button:SetText(ns.L["Do it and reload?"])
            C_Timer.After(4, function()
                warn.armed = false
                if warn.button and warn.idle then warn.button:SetText(warn.idle) end
            end)
            return
        end

        warn.armed = false
        local ok, why = ns.Cooldowns.Rivals.Disable(folder)
        if not ok then
            ns.Print("|cffff4040Not switched off|r - " .. (why or "?") .. ".")
            warn.button:SetText(warn.idle or "")
            return
        end
        -- REMEMBERED BEFORE THE RELOAD, not by the OnHide that will never
        -- run: a reload tears the frame down without hiding it, so a
        -- character who came in through this button would be asked all over
        -- again on the way back up.
        Welcome:Remember()
        ReloadUI()
    end, "ghost")
    warn.button:SetPoint("TOPRIGHT", warn, "TOPRIGHT", -12, 0)

    frame.warn = warn

    -- ONE ROW PER MODULE, built from the registry rather than typed out. A
    -- fifth module has to appear here by existing - a welcome screen that has
    -- to be edited to mention a new feature is a welcome screen that will one
    -- day fail to mention one.
    frame.rows = {}
    local previous
    for _, entry in ipairs(ns.Modules:All()) do
        -- A hidden entry draws no row at all - "als wenn es nicht drin
        -- waere". The rows table is appended rather than index-keyed for
        -- exactly this line: a skipped index would leave a hole ipairs
        -- stops at, and every row after the hidden one would silently
        -- stop refreshing.
        if not entry.hidden then
            -- controlWidth 96: the toggle sits at the right end of the slot
            -- and the NEW badge at its left end, so the two never overlap
            -- and the label knows where to stop.
            local row = UI.Row(frame, ns.L[entry.title], {
                sublabel = ns.L[entry.blurb],
                icon = entry.glyph,
                controlWidth = 96,
            })
            row:SetHeight(ROW_H)
            row:SetPoint("LEFT", frame, "LEFT", PAD, 0)
            row:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
            if previous then
                row:SetPoint("TOP", previous, "BOTTOM", 0, 0)
            else
                row:SetPoint("TOP", warn, "BOTTOM", 0, -4)
            end
            previous = row

            row.badge = UI.Badge(row.slot, ns.L["NEW"], "current")
            row.badge:SetPoint("LEFT", row.slot, "LEFT", 0, 0)
            row.badge:Hide()

            UI.Toggle(row, function() return ns.Modules:IsOn(entry.key) end,
                function(value) ns.Modules:Set(entry.key, value) end)

            row.moduleKey = entry.key
            frame.rows[#frame.rows + 1] = row
        end
    end

    local footer = UI.Label(frame, "You can change this at any time under "
        .. "Settings, and nothing here is permanent - a module you switch off "
        .. "keeps everything you set up in it.", UI.FS.meta, C.textFaint)
    footer:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -PAD)
    footer:SetJustifyH("LEFT")

    -- AND THEN THE ADDON IS OPEN. Owner, 2026-08-10: "beim welcome screen,
    -- wenn ich da auf lets go klicke, sollte das addon auf gehen" - and he is
    -- right about what the sentence promises: this window asks which features
    -- you want, and "let's go" is an answer that expects to arrive SOMEWHERE.
    -- Closing onto an empty screen leaves the newcomer exactly where they
    -- were, with a settings window they have not found yet.
    --
    -- Escape still just closes, which is the difference between the two ways
    -- out: one is "yes, show me" and the other is "not now".
    local go = UI.Button(frame, ns.L["Let's go"], 130, function()
        Welcome:Close()
        if ns.Options then ns.Options:Open() end
    end, "primary")
    go:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -PAD)

    -- AND THE OTHER WAY OUT, DRAWN THIS TIME.
    --
    -- Escape has always closed this window and always counted as answered -
    -- that is the paragraph above - but a keypress nobody is told about is not
    -- an exit. This is the first window the addon ever shows: somebody who
    -- does not want to decide right now was being offered one button, and one
    -- button that opens a settings window is not an answer to "not yet".
    --
    -- A ghost, not a second button. It must be findable and it must not
    -- compete with the answer the window is actually asking for.
    local notNow = UI.Button(frame, ns.L["Not now"], nil, function()
        Welcome:Close()
    end, "ghost")
    notNow:SetPoint("RIGHT", go, "LEFT", -8, 0)

    -- The sentence stops where the two buttons start. Measured, not typed: the
    -- ghost is as wide as its own word - see UI.ButtonWidth - so a number here
    -- would be wrong the day the word changes.
    footer:SetWidth(WIDTH - PAD * 2 - (130 + 8 + notNow:GetWidth() + 16))

    -- WHERE THIS ADDON LIVES, along the very foot: the two stores, the
    -- source and the Discord, each with its mark, from the one list the rail
    -- and the About page read (owner, 2026-08-16: "im welcome screen unten
    -- auch einbauen und entsprechend verlinken"). Ghosts, not buttons: this
    -- window is asking one question and these are not the answer to it. A
    -- click opens the copy box, which is the honest link inside a game.
    local LINK_ROW = 24
    local previousLink
    for _, entry in ipairs(ns.LINKS) do
        local link = UI.GhostButton(frame, entry.name, function()
            UI.CopyBox(entry.name, entry.url,
                "Ctrl+C copies it, then paste it into your browser. Esc "
                .. "closes. An addon cannot open a browser itself - the "
                .. "client has no call for it, by design.")
        end)
        if entry.icon then link:SetIcon(entry.icon) end
        if previousLink then
            link:SetPoint("LEFT", previousLink, "RIGHT", 10, 0)
        else
            link:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD - 6, PAD - 2)
        end
        previousLink = link
    end

    -- The height is what the rows added up to, not a number typed once and
    -- wrong after the fifth module. The warning strip is NOT in it: it is only
    -- there for somebody who has a conflict, so its height is added in Show
    -- where the answer is known. The link row at the foot is its own line
    -- under the sentence and the buttons.
    frame.baseHeight = HEAD_TOP + PAD + 62 + 4 + #frame.rows * ROW_H + PAD
        + math.max(footer:GetStringHeight(), UI.BUTTON_H) + PAD
        + LINK_ROW
    frame:SetHeight(frame.baseHeight)

    frame.version = version

    -- ESC closes it, and closing it by any route counts as answered.
    table.insert(UISpecialFrames, "ZwoelfStuffWelcomeFrame")
    frame:SetScript("OnHide", function() Welcome:Remember() end)
end

-- This character has now been asked about everything we ship.
function Welcome:Remember()
    if ns.db then ns.db.welcomeSeen = ns.Modules.GENERATION end
end

-- Both routes out of the window, and both write the answer. Remember is
-- idempotent, so a close that comes through the button AND then through
-- OnHide costs one assignment twice - which is the right way round: a window
-- that only remembers through one of its two exits is a window that asks
-- again for everybody who pressed Escape.
function Welcome:Close()
    self:Remember()
    if frame then frame:Hide() end
end

-- fresh: the module keys to call out as new. On a first run that list is
-- deliberately EMPTY - "everything is new" is not information - so nothing
-- here has to know which of the two cases it is any more. It used to: the
-- strapline said one thing on a first run and another after an update, and
-- the strapline is gone.
function Welcome:Show(fresh)
    if not ns.UI then return end
    if not frame then BuildFrame() end

    frame.version:SetText("v" .. (ns.version or "?"))

    local isFresh = {}
    for _, key in ipairs(fresh or {}) do isFresh[key] = true end

    for _, row in ipairs(frame.rows) do
        row.badge:SetShown(isFresh[row.moduleKey] and true or false)
        if row.Refresh then row.Refresh() end
    end

    -- THE CONFLICT LINE, decided every time the window opens rather than once
    -- when it was built: somebody can enable another cooldown addon and come
    -- back to this window from Settings in the same session, and a strip
    -- computed at build time would still be describing the old answer.
    local warn = frame.warn
    -- ONLY WHILE THE COOLDOWNS MODULE IS OFFERED AT ALL. The strip explains
    -- a switch that sits "below" it; with the module hidden there is no
    -- switch below, and a warning about a feature this window no longer
    -- mentions is the window talking to itself.
    local offered = ns.Modules:Get("cooldowns")
    offered = offered ~= nil and not offered.hidden
    local rivals = offered and ns.Cooldowns and ns.Cooldowns.Rivals or nil
    local clash, others = false, {}
    if rivals then clash, others = rivals.Any() end
    if clash and rivals then
        warn.text:SetText(ns.L(
            "%s is already managing your cooldowns. Two addons cannot hold "
            .. "the same cooldown frames - one of them loses, and which one "
            .. "depends on the order they loaded. Cooldowns is switched off "
            .. "below; turn it on to use ours instead, and switch theirs off "
            .. "in your addon list.", rivals.Describe()))

        -- The button only when one addon can be named. Rebuilt every time the
        -- window opens because the armed state must not survive a close: a
        -- button that reopens already saying "really?" is one press from a
        -- reload nobody asked for.
        warn.armed = false
        if #others == 1 then
            warn.folder = others[1].folder
            warn.idle = ns.L("Switch off %s", others[1].label)
            warn.button:SetText(warn.idle)
            warn.button:Show()
        else
            warn.folder, warn.idle = nil, nil
            warn.button:Hide()
        end

        -- MEASURED, not a constant: the sentence names another addon, and how
        -- long that name is is not ours to know. The button sits above the
        -- text on its own line, so both are counted.
        local buttonRoom = (#others == 1)
            and (warn.button:GetHeight() + 6) or 0
        warn.text:ClearAllPoints()
        warn.text:SetPoint("TOPLEFT", warn, "TOPLEFT", 12, -9 - buttonRoom)
        warn:SetHeight(warn.text:GetStringHeight() + 18 + buttonRoom)
        warn:Show()
    else
        warn:SetHeight(0.01)
        warn:Hide()
    end
    frame:SetHeight(frame.baseHeight + (clash and warn:GetHeight() + 10 or 0))

    frame:Show()
end

-- Login. Opens only if this character has never been asked, or an update
-- brought a module it has not been offered.
function Welcome:ShowIfDue()
    if not ns.db then return end

    -- The third return - "nobody has ever been asked on this character" - is
    -- deliberately not taken. Its only reader was the strapline, and on a
    -- first run `fresh` is empty anyway, which is the same information in the
    -- form the window actually uses. WelcomeDue still answers it; it is a pure
    -- rule with its own tests and losing a caller is not a reason to change it.
    local due, fresh = ns.Modules.WelcomeDue(ns.db.welcomeSeen)
    if not due then return end

    -- NOT IN COMBAT. Somebody who logs in mid-pull gets a window over the
    -- fight, and the first thing this addon ever does must not be that. It
    -- waits for the fight to end instead - the question keeps.
    if InCombatLockdown and InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(listener)
            listener:UnregisterAllEvents()
            Welcome:Show(fresh)
        end)
        return
    end

    -- A beat after login, for the same reason every other window in this
    -- addon waits: the client is still building its own frames, and a window
    -- that appears during that lands behind them.
    C_Timer.After(1.5, function() Welcome:Show(fresh) end)
end
