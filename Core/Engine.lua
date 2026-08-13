---------------------------------------------------------------------------
-- Engine - the sanctioned way to show auras that addons may not read.
--
-- Patch 12.x makes aura data secret. Measured on this character: every buff
-- came back secret, so no addon can identify an aura by ID, name or icon.
-- The engine can. Blizzard_AuraContainer lets an addon DECLARE what it wants
-- to see and hand over the widgets; the engine then binds the aura, shows the
-- button only while it is up, and drives icon, duration, bar and stacks
-- itself. The addon never touches a secret value.
--
-- THE CONTRACT (read before changing anything here)
--
--   1. Content first, unit LAST.  SetUnit re-evaluates event registrations,
--      and those are gated on the container already having groups or slots.
--      Setting the unit before declaring content leaves UNIT_AURA
--      unregistered and the container silently never updates. Finish with
--      UpdateAllAuras().
--   2. The button subtree may only be built inside initializeFrame. That
--      callback is the single legal window for creating children, anchoring,
--      registering regions and disabling mouse input. Afterwards the subtree
--      is denied to addon code - reads AND writes both.
--   3. An uncaught error inside initializeFrame aborts the engine's whole
--      CreateFrameBatch and kills the group. Optional decoration is pcalled.
--   4. A FontString handed to SetDurationText must be a DESCENDANT of the
--      button, and must have its font set BEFORE registration.
--   5. Groups are add-only. A settings change that alters the baked skin
--      needs a NEW container; the old one is retired, not mutated.
--
-- Verified against these 12.1 implementations on this machine - every call
-- below appears in working, version-matched code, none of it is guessed:
--   EllesmereUI/EllesmereUI_AuraKit.lua                  container + button
--   EllesmereUINameplates/EUI_Nameplates_AuraContainers  flow layout + sort
--   EllesmereUIResourceBars/EUI_ResourceBars_EbonMight121  single secret buff
--   EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers  SetDurationBar
---------------------------------------------------------------------------
local _, ns = ...

local Engine = {}
ns.Engine = Engine

---------------------------------------------------------------------------
-- Availability
---------------------------------------------------------------------------

-- Probed once and cached. Returns false on any client that lacks the API, so
-- callers can fall back instead of erroring.
--
-- There is NO "Blizzard_AuraContainer" addon to load. The AuraContainer frame
-- type and CustomAuraContainerTemplate are built into the client; every
-- reference implementation simply calls CreateFrame (EllesmereUI gates on the
-- build number, NorthernSkyRaidTools pcalls the creation). An earlier version
-- of this function tried to LoadAddOn("Blizzard_AuraContainer") first and
-- returned false when that failed - which it always did, because the addon
-- does not exist. The engine therefore reported itself unavailable on every
-- client, and every engine-backed feature silently fell back or showed
-- nothing: the display's aura slot, the co-tank aura strips, and every
-- tracking group.
--
-- The only honest test is to build one and see.
function Engine:IsAvailable()
    if self.available ~= nil then return self.available end
    self.available = false
    self.unavailableReason = nil

    if type(CreateFrame) ~= "function" then
        self.unavailableReason = "CreateFrame is missing"
        return false
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent,
        "CustomAuraContainerTemplate")
    if not ok or not container then
        -- Naming the build matters: without it this reads like a broken
        -- addon rather than a client that simply predates the API.
        local version = GetBuildInfo and select(1, GetBuildInfo()) or "?"
        local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
        self.unavailableReason = string.format(
            "this client is %s (%s) - AuraContainer arrives in 12.1", version, build)
        return false
    end

    for _, method in ipairs({ "AddAuraGroup", "AddAuraSlot", "SetUnit" }) do
        if type(container[method]) ~= "function" then
            self.unavailableReason = "AuraContainer exists but has no " .. method
            return false
        end
    end

    -- Keep the probe parked rather than destroying it; frames cannot be freed.
    container:Hide()
    self.probeContainer = container
    self.available = true
    return true
end

-- Why IsAvailable said no. Empty when it said yes.
function Engine:UnavailableReason()
    self:IsAvailable()
    return self.unavailableReason
end

-- Container creation and unit binding are synchronous engine parses. Newer
-- builds allow them in combat, older ones refuse; callers queue either way.
function Engine:IsLocked()
    return UnitAffectingCombat("player") or InCombatLockdown()
end

---------------------------------------------------------------------------
-- Filter strings
--
-- The engine batches aura parsing per container by EXACT filter string, so
-- the token order has to be canonical: polarity first, then the rest sorted.
---------------------------------------------------------------------------
local filterCache = {}

function Engine:Filter(...)
    local key = table.concat({ ... }, "|")
    local cached = filterCache[key]
    if cached then return cached end

    local base, rest = nil, {}
    for i = 1, select("#", ...) do
        local token = select(i, ...)
        if token == "HELPFUL" or token == "HARMFUL" then
            base = token
        elseif token and token ~= "" then
            rest[#rest + 1] = token
        end
    end
    table.sort(rest)

    local out
    if base and #rest > 0 then
        out = base .. "|" .. table.concat(rest, "|")
    else
        out = base or table.concat(rest, "|")
    end

    filterCache[key] = out
    return out
end

---------------------------------------------------------------------------
-- Duration text formatting
---------------------------------------------------------------------------
local durationFormatter

-- "8.4" below ten seconds, "24" below a minute, "2m" above it. Falls back to
-- the engine default when the formatter API is unavailable.
local function GetDurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    durationFormatter = false

    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        local down = Enum.NumericRuleFormatRounding.Down
        local ok = pcall(formatter.SetBreakpoints, formatter, {
            { threshold = 0,  format = "%.1f", step = 0.1, rounding = down },
            { threshold = 10, format = "%d",   step = 1,   rounding = down },
            { threshold = 60, format = "%dm",  step = 1,   rounding = down,
              components = { { div = 60 } } },
        })
        if ok then durationFormatter = formatter end
    end

    return durationFormatter or nil
end

Engine.GetDurationFormatter = GetDurationFormatter

-- Degrades in steps: a rejected options table must not abort the whole
-- registration and leave the button textless.
local function BindDurationText(button, fontString)
    local formatter = GetDurationFormatter()
    if formatter and pcall(button.SetDurationText, button, fontString,
        { textFormatter = formatter }) then
        return true
    end
    return pcall(button.SetDurationText, button, fontString, {})
end

Engine.BindDurationText = BindDurationText

-- The engine drives a StatusBar straight from the aura's (secret) duration -
-- GPU side, no OnUpdate, and it works for auras we cannot read at all.
local function BindDurationBar(button, bar)
    local opts = {}
    if Enum and Enum.StatusBarInterpolation then
        opts.interpolation = Enum.StatusBarInterpolation.Immediate
    end
    if Enum and Enum.StatusBarTimerDirection then
        opts.direction = Enum.StatusBarTimerDirection.RemainingTime
    end
    if pcall(button.SetDurationBar, button, bar, opts) then return true end
    return pcall(button.SetDurationBar, button, bar)
end

Engine.BindDurationBar = BindDurationBar

-- THE SWIPE, and it is the one an aura icon actually wants.
--
-- A StatusBar is a bar beside the icon; this is the round sweep ON it, the
-- shape every player already reads as "time left" because that is what a
-- cooldown looks like. The engine drives it from the aura's own duration
-- OBJECT rather than from numbers we would have to read - so it is exact,
-- it costs no OnUpdate, and an aura that gets EXTENDED mid-fight sweeps to
-- the new end instead of finishing early and lying.
--
-- Two things this cannot do, both learned rather than assumed:
--
--   * The Cooldown frame must be created inside initializeFrame like every
--     other child, and it must not be touched afterwards. The engine takes
--     OWNERSHIP at registration - a SetCooldown of ours from outside fights
--     it and wins for one frame, which reads as a flicker.
--   * An engine-bound cooldown draws no widget countdown of its own. The
--     number belongs to SetDurationText; leaving the widget's own numbers on
--     puts two clocks on one icon.
local function BindDurationCooldown(button, cooldown)
    if not (button and cooldown and button.SetDurationCooldown) then
        return false
    end
    return (pcall(button.SetDurationCooldown, button, cooldown))
end

-- There is deliberately no "does this client have the swipe" question to ask
-- beforehand: SetDurationCooldown lives on the BUTTON, and a button exists
-- only inside initializeFrame. The return value above IS the answer, at the
-- only moment it can honestly be given.
Engine.BindDurationCooldown = BindDurationCooldown

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

-- AuraContainerSortMethod is a plain global table, not an Enum member, and it
-- does not exist on every build.
function Engine:SortMethod(name)
    local methods = AuraContainerSortMethod
    if not methods then return nil end
    if name == "important" then return methods.ImportantOnly end
    return methods.Default
end

---------------------------------------------------------------------------
-- Flow layout
--
-- 12.1 renamed the SetAuraLayout* family to SetFlowLayout*; both names are
-- resolved per call so a mismatched build degrades instead of erroring.
---------------------------------------------------------------------------
local function CallEither(frame, newName, oldName, ...)
    local fn = frame[newName] or frame[oldName]
    if not fn then return false end
    return pcall(fn, frame, ...)
end

-- layout = {
--   anchorPoint,          -- "TOPLEFT" ...  where the first element sits
--   growthH, growthV,     -- "RIGHT"/"LEFT", "DOWN"/"UP"
--   maxLineSize,          -- pixels; nil = unlimited (no wrapping)
--   vertical,             -- true: lines are COLUMNS instead of rows
--   padding = {l, r, t, b},
-- }
function Engine:ApplyLayout(container, layout)
    if not (container and layout) then return end

    if layout.anchorPoint then
        CallEither(container, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint",
            layout.anchorPoint)
    end
    if layout.growthH and layout.growthV then
        CallEither(container, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
            layout.growthH, layout.growthV)
    end
    if layout.padding then
        local p = layout.padding
        CallEither(container, "SetFlowLayoutPadding", "SetAuraLayoutPadding",
            p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0)
    end

    -- nil resets to unlimited on both API generations.
    CallEither(container, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth",
        layout.maxLineSize)

    -- Flow axis exists only on newer builds; without it the container keeps
    -- the classic row behaviour, which is a degradation, not a failure.
    local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
    if axes and container.SetFlowLayoutAxis then
        pcall(container.SetFlowLayoutAxis, container,
            layout.vertical and axes.Vertical or axes.Horizontal)
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

-- The parent should be a plain frame the addon owns ("proxy"): all moving,
-- scaling and anchoring happens on it, never on engine-bound widgets.
function Engine:CreateContainer(parent, layout)
    if not self:IsAvailable() then return nil end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent,
        "CustomAuraContainerTemplate")
    if not ok or not container then return nil end

    -- The engine drains its parse and layout phases from an OnUpdate armed in
    -- run-when-visible mode, so the container needs a renderable rect from the
    -- very first dirty mark. It replaces the size on every layout pass.
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetSize(1, 1)

    -- A container is a display surface, never an input one. Left mouse-enabled
    -- it lies over its own proxy and swallows every click meant for it - which
    -- is exactly the frame the addon drags to move the display, so unlocking
    -- appeared to do nothing at all.
    pcall(container.EnableMouse, container, false)
    if container.SetMouseClickEnabled then
        pcall(container.SetMouseClickEnabled, container, false)
    end
    if container.SetMouseMotionEnabled then
        pcall(container.SetMouseMotionEnabled, container, false)
    end

    self:ApplyLayout(container, layout)
    return container
end

-- spec = {
--   key, filter, max, includeSpellIDs, sort,
--   layout = { elementWidth, elementHeight, elementSpacing, lineSpacing },
--   initialize = function(button) ... end,
-- }
function Engine:AddGroup(container, spec)
    if not container then return false end

    local options = {
        maxFrameCount   = spec.max,
        sortMethod      = self:SortMethod(spec.sort),
        initializeFrame = spec.initialize,
        layout          = spec.layout,
    }
    if spec.includeSpellIDs and next(spec.includeSpellIDs) then
        options.candidateFilters = { includeSpellIDs = spec.includeSpellIDs }
    end

    return (pcall(container.AddAuraGroup, container, spec.key or "dk",
        spec.filter, options))
end

-- Unit LAST - see contract rule 1. UpdateAllAuras forces the first parse
-- instead of waiting for the next aura event.
--
-- Shows the container as well, so a container that was parked by Retire and
-- is later rebound comes back rather than staying invisibly bound.
function Engine:Bind(container, unit)
    if not container then return false end
    local ok = pcall(container.SetUnit, container, unit)
    if ok then
        pcall(container.UpdateAllAuras, container)
        container:Show()
    end
    return ok
end

-- Parks a container that is being retired. Frames cannot be freed, so unbind
-- the unit (which stops the engine billing us for its parse) and hide it.
function Engine:Retire(container)
    if not container then return end
    if not pcall(container.SetUnit, container, "none") then
        pcall(container.SetUnit, container, nil)
    end
    container:Hide()
end

---------------------------------------------------------------------------
-- Button skinning helpers, for use INSIDE initializeFrame only
---------------------------------------------------------------------------

-- Engine aura buttons come mouse-enabled. A display-only overlay with clicks
-- alive is an invisible click blocker over its whole rect for as long as the
-- aura is up - it swallows clicks meant for the world. This is the only legal
-- moment to turn that off.
function Engine:MakeDisplayOnly(button)
    if button.SetMouseClickEnabled then
        pcall(button.SetMouseClickEnabled, button, false)
    end
    if button.SetMouseMotionEnabled then
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end
