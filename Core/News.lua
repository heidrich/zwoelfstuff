---------------------------------------------------------------------------
-- News - what changed since the last time you played.
--
-- Owner, 2026-08-14: "bitte eine NEW Screen einbauen, wenn neue version, muss
-- beim erstmal im spiel der NEW screen aufpoppen, mit Neue Funktionen und Bug
-- fixes etc, schoen aufgearbeitet und ok button. mit hot links direkt zu den
-- einzelnen funktionen."
--
-- IT HAS NO CONTENT OF ITS OWN, and that is the whole design. ns.CHANGELOG is
-- already written for the person playing rather than for whoever picks the
-- code up next - that is stated at the top of the file - and a second list
-- saying the same things in other words is the second-copy trap: one of them
-- gets the next release and the other quietly becomes last month's news. So
-- this window RENDERS the changelog, and a release is announced by writing
-- the changelog entry, which was already the job.
--
-- THE THREE RULES IT FOLLOWS
--
--   Never on a fresh install. Somebody who has just installed the addon does
--   not want twelve versions of history; they want the welcome window, which
--   is a different window with a different question. A first run STAMPS the
--   current version and shows nothing.
--
--   Account-wide, not per character. Reading the news on one character means
--   you have read it. Filing it per character means an alt run greets you
--   with a wall of text you cleared an hour ago.
--
--   Never over a fight. Same rule the welcome window follows, for the same
--   reason: the first thing this addon does after a login must not be a
--   window across somebody's pull.
--
-- THE HOT LINKS. A line may carry one, and it opens the thing the line is
-- about - an options page, or a window that is not in the options at all.
-- They are OPTIONAL and a line is still a plain string, because six hundred
-- existing changelog lines are plain strings and rewriting them to add a
-- field none of them uses would be a migration for nothing.
---------------------------------------------------------------------------
local _, ns = ...

local News = {}
ns.News = News

local WIDTH, PAD = 720, 20
local MAX_VERSIONS = 4

---------------------------------------------------------------------------
-- Which versions are new to you - pure
---------------------------------------------------------------------------

-- "4.81.0" -> 4, 81, 0. A version with a suffix on it ("4.81.0-beta") keeps
-- the numbers it has and ignores the rest, rather than answering nil and
-- making every comparison against it false.
function News.Parts(version)
    local out = {}
    if type(version) ~= "string" then return out end
    for piece in version:gmatch("%d+") do
        out[#out + 1] = tonumber(piece)
    end
    return out
end

-- Is `a` newer than `b`? Compared piece by piece as NUMBERS, because "4.9.0"
-- is newer than "4.81.0" as a string and older as a version, and a window
-- that gets that backwards either shouts every login or never opens again.
function News.Newer(a, b)
    if type(b) ~= "string" or b == "" then return true end
    local left, right = News.Parts(a), News.Parts(b)
    for index = 1, math.max(#left, #right) do
        local one, two = left[index] or 0, right[index] or 0
        if one ~= two then return one > two end
    end
    return false
end

-- The entries worth showing, newest first, capped. The cap is not a silent
-- one: whoever draws this is told how many were left out so it can say so.
-- Somebody coming back after three months does not want to scroll a year.
function News.Since(log, seen, cap)
    local out, dropped = {}, 0
    for _, entry in ipairs(log or {}) do
        if entry.version and News.Newer(entry.version, seen) then
            if #out < (cap or MAX_VERSIONS) then
                out[#out + 1] = entry
            else
                dropped = dropped + 1
            end
        end
    end
    return out, dropped
end

-- A changelog line is either a plain string or a table carrying a link.
-- Both shapes answer this, so the renderer never has to ask which it got.
function News.LineText(line)
    if type(line) == "string" then return line end
    if type(line) == "table" and type(line.text) == "string" then
        return line.text
    end
    return ""
end

function News.LineLink(line)
    if type(line) ~= "table" then return nil end
    local link = line.link
    if type(link) ~= "table" or type(link.label) ~= "string" then return nil end
    if type(link.page) ~= "string" and type(link.open) ~= "string" then
        return nil
    end
    return link
end

---------------------------------------------------------------------------
-- WHERE A HOT LINK GOES
--
-- Two kinds, because the features are two kinds. Most live on a page of the
-- options window and `page` names its key. Some are their own window and
-- belong to nobody's settings page - the group death log is one - so `open`
-- names an entry here instead. A named table rather than a function stored
-- in the changelog: the changelog is DATA, and data that can run is data
-- nobody can read at a glance.
---------------------------------------------------------------------------
News.OPENERS = {
    raiddeaths = function() if ns.RaidDeaths then ns.RaidDeaths:Toggle() end end,
    death      = function() if ns.Death then ns.Death:Show() end end,
    replay     = function() if ns.Replay then ns.Replay:Toggle() end end,
    welcome    = function() if ns.Welcome then ns.Welcome:Show() end end,
}

-- Whether a link can actually be followed. Checked when the button is BUILT,
-- so a link naming something that has been renamed away is left off the
-- window rather than drawn as a button that does nothing.
function News.CanFollow(link)
    if type(link) ~= "table" then return false end
    if link.open then return News.OPENERS[link.open] ~= nil end
    if link.page then
        for _, entry in ipairs(ns.OPTIONS_PAGES or {}) do
            if entry.key == link.page then return true end
        end
        -- The page list is built inside Options.lua and is not exported on
        -- every path; a page link is allowed through when it cannot be
        -- checked, because Options:Open ignores a key it does not know and
        -- simply opens the window.
        return ns.OPTIONS_PAGES == nil
    end
    return false
end

function News.Follow(link)
    if type(link) ~= "table" then return end
    if link.open and News.OPENERS[link.open] then
        News.OPENERS[link.open]()
        return
    end
    if link.page and ns.Options then ns.Options:Open(link.page) end
end

---------------------------------------------------------------------------
-- Remembering that you have read it
---------------------------------------------------------------------------
local function Store()
    return ns.account
end

function News.Seen()
    local store = Store()
    return store and store.newsSeen or nil
end

function News.Remember(version)
    local store = Store()
    if store then store.newsSeen = version or ns.version end
end

-- WHETHER TO OPEN AT ALL, and the first-run rule is the load-bearing half.
-- Returns the entries to draw and how many were left out, or nil.
function News.Due()
    local store = Store()
    if not store then return nil end

    -- Never on a fresh install: stamp and stay quiet. The welcome window is
    -- what greets a new installation, and two windows on top of each other
    -- on somebody's first login is how both get dismissed unread.
    if not store.newsSeen then
        News.Remember(ns.version)
        return nil
    end

    local entries, dropped = News.Since(ns.CHANGELOG, store.newsSeen,
        MAX_VERSIONS)
    if #entries == 0 then return nil end
    return entries, dropped
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame

-- The foot line, pure, so the wording is checkable without a frame.
function News.FootLine(entries, dropped)
    local versions = #(entries or {})
    if versions == 0 then return "" end
    local line = versions == 1 and "One update while you were away."
        or string.format("%d updates while you were away.", versions)
    if (dropped or 0) > 0 then
        line = line .. string.format("  %d older %s not shown - the whole "
            .. "list is under Changelog.", dropped,
            dropped == 1 and "one is" or "ones are")
    end
    return line
end

function News.Title(entries)
    local newest = (entries or {})[1]
    if not newest then return "What's new" end
    return "What's new in " .. tostring(newest.version)
end

local function BuildFrame()
    local UI, C = ns.UI, ns.UI.C

    frame = CreateFrame("Frame", "ZwoelfStuffNews", UIParent)
    frame:SetSize(WIDTH, 520)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    UI.Fill(frame, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(frame, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)

    frame.title = UI.Label(frame, "", UI.FS.card, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -18)

    frame.sub = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -UI.HEADER_H)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -UI.HEADER_H)

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(UI.HEADER_H + 12))
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 60)
    local _, content = UI.ScrollArea(host, WIDTH - PAD * 2 - 8, 8)
    frame.content = content
    frame.width = WIDTH - PAD * 2 - 8

    -- The pools. Three kinds of thing go into this list - a version heading,
    -- a paragraph, and a link button - and each is reused rather than rebuilt,
    -- because opening this window twice in one session must not leave a
    -- second set of frames behind the first.
    frame.heads, frame.lines, frame.links = {}, {}, {}

    frame.ok = UI.Button(frame, "OK", 120, function() News:Close() end,
        "primary")
    frame.ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 16)

    -- The whole list, for somebody who wants more than the last few versions.
    frame.all = UI.Button(frame, "Changelog", 120, function()
        News:Close()
        if ns.Options then ns.Options:Open("changelog") end
    end)
    frame.all:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 16)

    frame.foot = UI.Label(frame, "", UI.FS.meta, C.textFaint)
    frame.foot:SetPoint("LEFT", frame.all, "RIGHT", 12, 0)
    frame.foot:SetPoint("RIGHT", frame.ok, "LEFT", -12, 0)
    frame.foot:SetJustifyH("LEFT")

    table.insert(UISpecialFrames, "ZwoelfStuffNews")
    return frame
end

-- For the checks: a local is invisible to every test in the addon, which is
-- how the reminder movers went two versions without a cog and nothing noticed.
function News.Window() return frame end

function News:Paint(entries, dropped)
    if not frame then return end
    local UI, C = ns.UI, ns.UI.C

    frame.title:SetText(News.Title(entries))
    frame.sub:SetText("Everything that changed since you last played.")
    frame.foot:SetText(News.FootLine(entries, dropped))

    local heads, lines, links = 0, 0, 0
    local y = 0

    for _, entry in ipairs(entries or {}) do
        heads = heads + 1
        local head = frame.heads[heads]
        if not head then
            head = UI.Label(frame.content, "", UI.FS.row, C.hot)
            frame.heads[heads] = head
        end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
        head:SetText(string.format("%s  |cff626a76%s|r",
            tostring(entry.version), tostring(entry.date or "")))
        head:Show()
        y = y + 24

        for _, raw in ipairs(entry.lines or {}) do
            lines = lines + 1
            local label = frame.lines[lines]
            if not label then
                label = UI.Label(frame.content, "", UI.FS.meta, C.textBody)
                label:SetJustifyH("LEFT")
                label:SetSpacing(3)
                frame.lines[lines] = label
            end
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 8, -y)
            label:SetWidth(frame.width - 8)
            label:SetText(News.LineText(raw))
            label:Show()
            y = y + math.max(20, (label:GetStringHeight() or 0) + 6)

            -- THE HOT LINK, under the line it belongs to. Only when it can
            -- actually be followed: a button that opens nothing is worse
            -- than no button, and a renamed page would leave exactly that.
            local link = News.LineLink(raw)
            if link and News.CanFollow(link) then
                links = links + 1
                local button = frame.links[links]
                if not button then
                    button = UI.Button(frame.content, "", 180, nil, "link")
                    frame.links[links] = button
                end
                button.label:SetText(link.label)
                button:SetScript("OnClick", function()
                    News:Close()
                    News.Follow(link)
                end)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, -y)
                button:Show()
                y = y + 26
            end
        end

        y = y + 14
    end

    for index = heads + 1, #frame.heads do frame.heads[index]:Hide() end
    for index = lines + 1, #frame.lines do frame.lines[index]:Hide() end
    for index = links + 1, #frame.links do frame.links[index]:Hide() end

    frame.content:SetHeight(math.max(1, y))
end

function News:Show(entries, dropped)
    if not ns.UI then return end
    entries = entries or News.Since(ns.CHANGELOG, nil, MAX_VERSIONS)
    if not frame then BuildFrame() end
    News:Paint(entries, dropped or 0)
    frame:Show()
end

-- CLOSING IS WHAT MARKS IT READ, not opening. Somebody who reloads while the
-- window is up is shown it again, which is the right way round - the same
-- rule the welcome window follows and for the same reason.
function News:Close()
    if frame then frame:Hide() end
    News.Remember(ns.version)
end

function News:Toggle()
    if frame and frame:IsShown() then
        News:Close()
        return
    end
    local entries, dropped = News.Since(ns.CHANGELOG, nil, MAX_VERSIONS)
    News:Show(entries, dropped)
end

-- Login. Opens only when the version has moved on, never on a fresh install,
-- and never across a fight.
function News:ShowIfDue()
    local entries, dropped = News.Due()
    if not entries then return end

    if InCombatLockdown and InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(listener)
            listener:UnregisterAllEvents()
            News:Show(entries, dropped)
        end)
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() News:Show(entries, dropped) end)
    else
        News:Show(entries, dropped)
    end
end
