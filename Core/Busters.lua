---------------------------------------------------------------------------
-- Busters.lua - the next scripted hit, and whether you are ready for it
--
-- Blizzard runs an encounter timeline on this client - the same feed
-- DBM and BigWigs moved onto when the combat log went away - and it is
-- readable: C_EncounterTimeline.GetEventList, GetEventInfo,
-- GetEventTimeRemaining, plus three events when entries appear, change
-- state and go. The REMAINING TIME IS A REAL NUMBER (BigWigs feeds it
-- straight into its bar arithmetic, which is how that was established);
-- the spell NAME and ICON are display-only secrets, and the SEVERITY is a
-- secret too - which is why this panel cannot filter "tank busters only"
-- and does not pretend to. It shows the soonest thing the fight has
-- scheduled, whatever it is.
--
-- Under it: your defensives, the ones picked on the Timeline page, each
-- coloured by ns.History's estimate of whether it is back. The pairing IS
-- the feature - the question mid-pull is never "what is my cooldown", it
-- is "does what I have left cover what is coming".
---------------------------------------------------------------------------
local _, ns = ...

local Busters = {}
ns.Busters = Busters

-- eventId -> { duration } - only what WE need to keep. Remaining time is
-- asked live on every paint; caching a countdown is how clocks drift.
local tracked = {}

---------------------------------------------------------------------------
-- Pure rules, exported for the self test
---------------------------------------------------------------------------

-- Which of the remaining times is soonest. Takes a plain map of
-- id -> seconds, answers id and seconds, nils when there is nothing. Kept
-- pure because the harness has no timeline to ask.
function Busters.Soonest(remainingByID)
    local bestID, best
    for id, remaining in pairs(remainingByID) do
        if type(remaining) == "number" and remaining >= 0
            and (best == nil or remaining < best) then
            bestID, best = id, remaining
        end
    end
    return bestID, best
end

-- The defensive strip's layout: how wide the panel has to be for n icons.
-- One rule for the panel and the mover, or the mover box lies about the
-- panel again - the exact drift the reminders mover had.
local ICON, GAP, PAD = 30, 4, 8
local BAR_H, NAME_H = 14, 16

function Busters.Extent(iconCount)
    local wide = math.max(220, iconCount * (ICON + GAP) - GAP + PAD * 2)
    local tall = PAD + NAME_H + 2 + BAR_H + 6 + ICON + PAD
    return wide, tall
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel
local icons = {}

local function BuildPanel()
    local C = ns.UI.C

    panel = CreateFrame("Frame", "ZwoelfStuffBustersPanel", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:Hide()
    Busters.panel = panel

    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)
    panel.bg:SetColorTexture(C.windowBg[1], C.windowBg[2], C.windowBg[3], 0.85)

    panel.edge = ns.CreateBorder(panel, 1, "BORDER")
    panel.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    panel.name = panel:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(panel.name, nil, 12, "OUTLINE")
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    panel.name:SetJustifyH("LEFT")

    panel.clock = panel:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(panel.clock, nil, 12, "OUTLINE")
    panel.clock:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
    panel.clock:SetJustifyH("RIGHT")

    -- Our own StatusBar, run on our own numbers. Nothing here mirrors a
    -- Blizzard value, so no secret ever reaches it.
    panel.bar = CreateFrame("StatusBar", nil, panel)
    panel.bar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + NAME_H + 2))
    panel.bar:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    panel.bar:SetHeight(BAR_H)
    panel.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    panel.bar:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    panel.bar.back = panel.bar:CreateTexture(nil, "BACKGROUND")
    panel.bar.back:SetAllPoints(panel.bar)
    panel.bar.back:SetColorTexture(C.well[1], C.well[2], C.well[3], 0.9)
end

local function EnsureIcon(i)
    if icons[i] then return icons[i] end
    local C = ns.UI.C

    local btn = CreateFrame("Frame", nil, panel)
    btn:SetSize(ICON, ICON)

    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints(btn)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.edge = ns.CreateBorder(btn, 1, "BORDER")
    btn.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    btn.left = btn:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(btn.left, nil, 11, "OUTLINE")
    btn.left:SetPoint("CENTER", btn, "CENTER", 0, 0)

    icons[i] = btn
    return btn
end

---------------------------------------------------------------------------
-- Showing
---------------------------------------------------------------------------

function Busters:Config()
    local db = ns.db
    if not db then return {} end
    db.busters = db.busters or {}
    -- The bars' rule set with the reminders' one changed default: combat
    -- furniture shows in combat. Seeded on first read, so a profile from
    -- before this feature gets the same answer as a fresh one.
    if db.busters.show == nil then
        db.busters.show = {
            mode    = "rules",
            combat  = "in",
            target  = "any",
            group   = "any",
            resting = "any",
            where   = { none = true, party = true, raid = true,
                        scenario = true, pvp = true, arena = true },
            specs   = {},
        }
    end
    return db.busters
end

function Busters:ShouldShow()
    if self.placing then return true end
    -- Evaluate reads enabled AND the show rule; asking it twice here would
    -- be the second copy of the rule that always drifts.
    return ns.Visibility:Evaluate(self:Config())
end

-- Edit Mode forces the panel up, or there is nothing to drag outside a
-- fight - same escape, same reason as the reminders and the co-tank panel.
function Busters:SetPlacing(on)
    self.placing = on and true or false
    self:Refresh()
end

function Busters:ApplyPosition()
    if not panel then return end
    local cfg = self:Config()
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -220)
end

function Busters:SavePosition()
    if not panel then return end
    local cfg = ns.db.busters
    if not cfg then return end
    local x, y = panel:GetCenter()
    local px, py = UIParent:GetCenter()
    cfg.x = math.floor(x - px + 0.5)
    cfg.y = math.floor(y - py + 0.5)
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- Asks the client for every tracked event's remaining time, OUR copy of the
-- answers only ever holding readable numbers.
local function RemainingNow()
    local out = {}
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventTimeRemaining) then
        return out
    end
    for id in pairs(tracked) do
        local ok, remaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, id)
        if ok and type(remaining) == "number" then
            out[id] = remaining
        end
    end
    return out
end

local function PaintEvent()
    local C = ns.UI.C
    local id, remaining = Busters.Soonest(RemainingNow())

    if not id then
        if Busters.placing then
            panel.name:SetText("Next scripted hit")
            panel.clock:SetText("12.3")
            panel.bar:SetMinMaxValues(0, 1)
            panel.bar:SetValue(0.6)
        else
            panel.name:SetText("Nothing scheduled")
            panel.clock:SetText("")
            panel.bar:SetMinMaxValues(0, 1)
            panel.bar:SetValue(0)
        end
        panel.name:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        return
    end

    local entry = tracked[id]
    local duration = (entry and entry.duration) or math.max(remaining, 1)

    -- The name is a display-only secret. SetText may draw it; building a
    -- string around it may not, which is why the clock is its own string.
    local shown = false
    if C_EncounterTimeline.GetEventInfo then
        local ok, info = pcall(C_EncounterTimeline.GetEventInfo, id)
        if ok and info and info.spellName ~= nil then
            local okSet = pcall(panel.name.SetText, panel.name, info.spellName)
            shown = okSet
        end
    end
    if not shown then panel.name:SetText("Next scripted hit") end
    panel.name:SetTextColor(C.text[1], C.text[2], C.text[3])

    panel.clock:SetText(string.format("%.1f", remaining))
    panel.bar:SetMinMaxValues(0, duration)
    panel.bar:SetValue(math.max(0, math.min(remaining, duration)))
end

local function PaintStrip()
    local C = ns.UI.C
    local picked = {}
    for spellID in pairs((ns.db and ns.db.defensives) or {}) do
        picked[#picked + 1] = spellID
    end
    table.sort(picked)

    local now = GetTime()
    for i, spellID in ipairs(picked) do
        local btn = EnsureIcon(i)
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT",
            PAD + (i - 1) * (ICON + GAP), PAD)
        btn.tex:SetTexture(ns.SpellTexture(spellID) or 134400)

        local remaining = ns.History:Estimate(spellID, now)
        if remaining == nil then
            -- Cannot tell. Full colour, no number - the icon says "this is
            -- one of yours", and claiming ready would be a guess in green.
            btn.tex:SetDesaturated(false)
            btn.tex:SetVertexColor(1, 1, 1, 0.9)
            btn.left:SetText("")
            btn.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
        elseif remaining <= 0 then
            btn.tex:SetDesaturated(false)
            btn.tex:SetVertexColor(1, 1, 1, 1)
            btn.left:SetText("")
            btn.edge:SetColor(C.inUse[1], C.inUse[2], C.inUse[3], 1)
        else
            btn.tex:SetDesaturated(true)
            btn.tex:SetVertexColor(0.7, 0.7, 0.7, 0.9)
            btn.left:SetText(remaining >= 60
                and string.format("%dm", math.floor(remaining / 60 + 0.5))
                or string.format("%d", math.floor(remaining + 0.5)))
            btn.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
        end
        btn:Show()
    end
    for i = #picked + 1, #icons do icons[i]:Hide() end

    local wide, tall = Busters.Extent(#picked)
    panel:SetSize(wide, tall)
end

local ticker = 0
local function OnUpdate(_, elapsed)
    ticker = ticker + elapsed
    if ticker < 0.2 then return end
    ticker = 0
    PaintEvent()
    PaintStrip()
end

function Busters:Refresh()
    if not ns.UI then return end
    if not panel then BuildPanel() end

    if self:ShouldShow() then
        self:ApplyPosition()
        PaintEvent()
        PaintStrip()
        panel:SetScript("OnUpdate", OnUpdate)
        panel:Show()
    else
        panel:SetScript("OnUpdate", nil)
        panel:Hide()
    end
end

---------------------------------------------------------------------------
-- The probe - run it DURING a boss with a timeline on screen:
-- /zs timeline probe. Prints what this client will actually say about an
-- event, field by field, so "severity is secret" stops being hearsay.
---------------------------------------------------------------------------
local function Verdict(value)
    if value == nil then return "|cff888888absent|r" end
    if not ns.CanCompute(value) then return "|cffff8040SECRET|r" end
    return "|cff40ff40" .. tostring(value) .. "|r"
end

function Busters:Probe()
    ns.Print("|cffffd100timeline probe|r")
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then
        ns.Print("  C_EncounterTimeline is |cffff4040not on this client|r.")
        return
    end
    local ok, list = pcall(C_EncounterTimeline.GetEventList)
    if not ok or type(list) ~= "table" then
        ns.Print("  GetEventList |cffff4040threw or answered nothing|r.")
        return
    end
    ns.Print(string.format("  %d event%s scheduled.", #list, #list == 1 and "" or "s"))

    local id = list[1]
    if id == nil then return end

    if C_EncounterTimeline.GetEventState then
        local okS, state = pcall(C_EncounterTimeline.GetEventState, id)
        ns.Print("  state = " .. (okS and Verdict(state) or "|cffff4040throws|r"))
    end
    if C_EncounterTimeline.GetEventTimeRemaining then
        local okR, remaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, id)
        ns.Print("  remaining = " .. (okR and Verdict(remaining) or "|cffff4040throws|r"))
    end
    if C_EncounterTimeline.GetEventInfo then
        local okI, info = pcall(C_EncounterTimeline.GetEventInfo, id)
        if okI and type(info) == "table" then
            ns.Print("  the first event, every field:")
            local keys = {}
            for key in pairs(info) do keys[#keys + 1] = tostring(key) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                ns.Print("    " .. key .. " = " .. Verdict(info[key]))
            end
        else
            ns.Print("  GetEventInfo |cffff4040threw or answered nothing|r.")
        end
    end
end

---------------------------------------------------------------------------
-- The timeline, listened to
---------------------------------------------------------------------------

-- Login mid-fight primes off the full list - BigWigs' StartBars does the
-- same walk for the same reason.
local function Prime()
    wipe(tracked)
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then return end
    local ok, list = pcall(C_EncounterTimeline.GetEventList)
    if not ok or type(list) ~= "table" then return end
    for _, id in ipairs(list) do
        local entry = { }
        if C_EncounterTimeline.GetEventInfo then
            local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, id)
            if okInfo and info and ns.CanCompute(info.duration)
                and type(info.duration) == "number" then
                entry.duration = info.duration
            end
        end
        tracked[id] = entry
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
listener:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
listener:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
listener:RegisterEvent("PLAYER_ENTERING_WORLD")
listener:RegisterEvent("PLAYER_REGEN_DISABLED")
listener:RegisterEvent("PLAYER_REGEN_ENABLED")
listener:SetScript("OnEvent", function(_, event, payload)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        -- The payload is the event info table. Its id and duration are not
        -- secret (BigWigs' own comment, verified by its arithmetic); the id
        -- is guarded anyway before it becomes a table key.
        if type(payload) == "table" and ns.CanCompute(payload.id) then
            local entry = {}
            if ns.CanCompute(payload.duration) and type(payload.duration) == "number" then
                entry.duration = payload.duration
            end
            tracked[payload.id] = entry
        end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        if ns.CanCompute(payload) and payload ~= nil then
            tracked[payload] = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Prime()
    end
    -- Every arm falls through to Refresh: combat starts and ends are what
    -- the visibility rule reads, and a timeline change may need the panel.
    Busters:Refresh()
end)
