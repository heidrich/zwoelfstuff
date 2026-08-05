---------------------------------------------------------------------------
-- Probe - "does this spell ID actually bind, and when?"
--
-- The recurring problem this addon keeps hitting: a spell's cast ID is not
-- the ID of the aura it applies, and under patch 12.x secret values an addon
-- cannot look at an aura to find out. Every previous answer came from a
-- database or from memory, and both have been wrong.
--
-- This asks the only authority that cannot be wrong: the game engine on this
-- character. A hidden one-slot container is bound to the candidate ID, and
-- the engine shows its button exactly while that aura is on the unit. We
-- never read the aura, never read the button - we register OnShow and OnHide
-- INSIDE the initializer, which is the one window where touching the button
-- is legal, and let the engine tell us.
--
-- So the output is not an opinion. "UP at +4.1s" means the engine bound that
-- exact ID at that moment.
---------------------------------------------------------------------------
local _, ns = ...

local Probe = {}
ns.Probe = Probe

local DEFAULT_SECONDS = 20

---------------------------------------------------------------------------
-- Reporting
---------------------------------------------------------------------------
local function Elapsed(session)
    return GetTime() - session.started
end

local function OnBound(session)
    session.hits = session.hits + 1
    ns.Print(string.format("|cff40ff40UP|r   +%.1fs   %s (%d)",
        Elapsed(session), session.name, session.spellID))
end

local function OnUnbound(session)
    -- The engine hides the button once on creation, before anything is bound;
    -- reporting that would read as "the aura just fell off".
    if session.hits == 0 then return end
    ns.Print(string.format("|cffff8040DOWN|r +%.1fs", Elapsed(session)))
end

local function Finish(session)
    if session.finished then return end
    session.finished = true

    if session.ticker then session.ticker:Cancel() end
    ns.Engine:Retire(session.container)

    ns.Print("|cffffd100----------------------------------------|r")
    if session.hits > 0 then
        ns.Print(string.format(
            "|cff40ff40%d (%s) IS trackable|r - the engine bound it %d time%s.",
            session.spellID, session.name, session.hits, session.hits == 1 and "" or "s"))
        ns.Print("Add it to a tracking group and it will show exactly like this.")
    else
        ns.Print(string.format("|cffff4040%d (%s) never bound|r on %s in %ds.",
            session.spellID, session.name, session.unit, session.seconds))
        ns.Print("Either the aura was not up, or this ID is the CAST spell and the")
        ns.Print("applied aura carries a different one. |cffffd100/dks dump|r while it is up.")
    end
end

---------------------------------------------------------------------------
-- Running a probe
---------------------------------------------------------------------------
function Probe:Start(spellID, seconds, unit)
    if not spellID then
        ns.Print("Usage: |cffffd100/dks probe <spellID> [seconds]|r")
        return
    end

    if not ns.Engine:IsAvailable() then
        ns.Print("|cffff4040The aura engine is not available on this client.|r")
        return
    end

    -- Container creation is a synchronous engine parse; older builds refuse
    -- it outright in combat.
    if ns.Engine:IsLocked() then
        ns.Print("|cffff4040Cannot start a probe in combat.|r Try again out of combat.")
        return
    end

    if self.session and not self.session.finished then
        Finish(self.session)
    end

    seconds = math.max(5, math.min(120, tonumber(seconds) or DEFAULT_SECONDS))
    unit = unit or "player"

    if not self.host then
        self.host = CreateFrame("Frame", nil, UIParent)
        self.host:SetSize(1, 1)
        self.host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self.host:Hide()   -- never rendered; only its slot's visibility matters
    end

    local session = {
        spellID  = spellID,
        name     = ns.SpellName(spellID) or "unknown to this client",
        unit     = unit,
        seconds  = seconds,
        started  = GetTime(),
        hits     = 0,
    }
    self.session = session

    local container = ns.Engine:CreateContainer(self.host)
    if not container then
        ns.Print("|cffff4040Could not create the probe container.|r")
        return
    end
    session.container = container

    -- Both polarities: a debuff answers the same question as a buff, and the
    -- caller should not have to know which one it is beforehand.
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        pcall(container.AddAuraSlot, container, "dksProbe" .. filter,
            ns.Engine:Filter(filter), {
                candidateFilters = { includeSpellIDs = { [spellID] = true } },
                initializeFrame  = function(button)
                    -- Inside the creation window: the only legal moment to
                    -- touch this button. The engine drives its visibility, so
                    -- its own show/hide IS the answer - we never inspect it.
                    ns.Engine:MakeDisplayOnly(button)
                    button:SetSize(1, 1)
                    button:SetScript("OnShow", function()
                        if not session.finished then OnBound(session) end
                    end)
                    button:SetScript("OnHide", function()
                        if not session.finished then OnUnbound(session) end
                    end)
                end,
            })
    end

    ns.Engine:Bind(container, unit)
    -- The host stays hidden, but a hidden parent hides the slot too, and then
    -- OnShow can never fire. Park it off screen instead.
    self.host:Show()
    self.host:SetAlpha(0)

    ns.Print("|cffffd100----------------------------------------|r")
    ns.Print(string.format("Probing |cffffd100%d|r (%s) on %s for %ds.",
        spellID, session.name, unit, seconds))
    ns.Print("Go and make the aura happen - stand in it, press the button, whatever it takes.")

    session.ticker = C_Timer.NewTimer(seconds, function() Finish(session) end)
end

function Probe:Stop()
    if self.session and not self.session.finished then
        Finish(self.session)
    end
end
