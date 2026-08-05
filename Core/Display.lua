---------------------------------------------------------------------------
-- Display - renders the isolated aura, in either of two modes:
--   "icon" : square icon, cooldown swipe, remaining time, stacks
--   "bar"  : icon plus a status bar with spell name and remaining time
--
-- Secret-value rules (patch 12.0+) shape this file:
--   * the icon and the name come from OUR spell ID, never from the aura
--   * the swipe is armed from a DurationObject, the only carrier a cooldown
--     frame accepts since 12.0.1
--   * the remaining time is drawn by the engine's own countdown, because
--     "expirationTime - GetTime()" is arithmetic on a secret and would raise
--   * stacks go through GetAuraApplicationDisplayCount, which applies the
--     "hide below 2" rule engine-side so we never compare anything
--
-- Nothing here is protected, so combat lockdown is a non-issue.
---------------------------------------------------------------------------
local _, ns = ...

local Display = {}
ns.Display = Display

local UPDATE_INTERVAL = 0.05

---------------------------------------------------------------------------
-- Engine-side accessors (all pcall-guarded: a secret-flagged spell can make
-- the query itself raise, and one bad aura must not kill the display)
---------------------------------------------------------------------------
local function GetDurationObject(unit, auraInstanceID)
    if not unit or not ns.CanCompute(auraInstanceID) then return nil end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if not fn then return nil end
    local ok, durObj = pcall(fn, unit, auraInstanceID)
    if ok then return durObj end
    return nil
end

local function ClearCooldown(cd)
    if cd.Clear then
        cd:Clear()
    else
        cd:SetCooldown(0, 0)
    end
end

-- Arms a cooldown frame. Test entries carry plain numbers we own; live
-- entries must go through the duration object.
local function ArmCooldown(cd, entry, showNumbers)
    cd:SetHideCountdownNumbers(not showNumbers)

    -- Plain timing we own (test preview, or a proc-glow driven entry) can go
    -- through SetCooldown; only secret timing needs the duration object.
    if entry.plainDuration then
        cd:SetCooldown(entry.plainStart, entry.plainDuration)
        return true
    end

    local durObj = GetDurationObject(entry.unit or "player", entry.auraInstanceID)
    if durObj and cd.SetCooldownFromDurationObject then
        cd:SetCooldownFromDurationObject(durObj)
        cd:SetDrawSwipe(true)
        return true
    end

    ClearCooldown(cd)
    return false
end

-- minCount 2 means the engine itself blanks a single application, which is
-- exactly the "only show stacks above 1" rule - without us comparing.
local function ApplyStacks(fontString, entry, show)
    if not show then
        fontString:SetText("")
        return
    end
    if entry.plainStacks then
        fontString:SetText(entry.plainStacks)
        return
    end

    local fn = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if fn and ns.CanCompute(entry.auraInstanceID) then
        local ok, text = pcall(fn, entry.unit or "player", entry.auraInstanceID, 2, 999)
        if ok then
            fontString:SetText(text or "")
            return
        end
    end
    fontString:SetText("")
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function BuildIconMode(root)
    local icon = CreateFrame("Frame", nil, root)
    icon:SetAllPoints(root)

    icon.bg = icon:CreateTexture(nil, "BACKGROUND")
    icon.bg:SetAllPoints(icon)
    icon.bg:SetColorTexture(0, 0, 0, 0.9)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon.tex)
    icon.cd:SetDrawEdge(false)
    icon.cd:SetDrawSwipe(true)
    icon.cd:SetSwipeColor(0, 0, 0, 0.7)
    icon.cd.noCooldownCount = true  -- the engine draws the number, not OmniCC

    icon.border = ns.CreateBorder(icon, 1, "OVERLAY")

    icon.textLayer = CreateFrame("Frame", nil, icon)
    icon.textLayer:SetAllPoints(icon)
    icon.textLayer:SetFrameLevel(icon.cd:GetFrameLevel() + 2)

    icon.stacks = icon.textLayer:CreateFontString(nil, "OVERLAY")
    icon.stacks:SetPoint("BOTTOMRIGHT", icon.textLayer, "BOTTOMRIGHT", -2, 2)

    return icon
end

local function BuildBarMode(root)
    local bar = CreateFrame("Frame", nil, root)
    bar:SetAllPoints(root)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0, 0, 0, 0.9)

    bar.tex = bar:CreateTexture(nil, "ARTWORK")
    bar.tex:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    bar.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    bar.status = CreateFrame("StatusBar", nil, bar)
    bar.status:SetPoint("TOPLEFT", bar.tex, "TOPRIGHT", 1, 0)
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    bar.status:SetStatusBarTexture(ns.WHITE)
    bar.status:SetMinMaxValues(0, 1)
    bar.status:SetValue(1)

    bar.track = bar.status:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar.status)
    bar.track:SetColorTexture(1, 1, 1, 0.08)

    bar.border = ns.CreateBorder(bar, 1, "OVERLAY")

    bar.textLayer = CreateFrame("Frame", nil, bar)
    bar.textLayer:SetAllPoints(bar.status)
    bar.textLayer:SetFrameLevel(bar.status:GetFrameLevel() + 2)

    -- A cooldown frame with the swipe switched off is used purely as an
    -- engine-drawn timer: it is the only way to show a secret remaining time.
    bar.cd = CreateFrame("Cooldown", nil, bar.textLayer, "CooldownFrameTemplate")
    bar.cd:SetPoint("RIGHT", bar.textLayer, "RIGHT", -4, 0)
    bar.cd:SetDrawSwipe(false)
    bar.cd:SetDrawEdge(false)
    bar.cd:SetDrawBling(false)
    bar.cd.noCooldownCount = true

    bar.name = bar.textLayer:CreateFontString(nil, "OVERLAY")
    bar.name:SetPoint("LEFT", bar.textLayer, "LEFT", 5, 0)
    bar.name:SetPoint("RIGHT", bar.cd, "LEFT", -4, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)

    return bar
end

function Display:Create()
    if self.root then return end

    local root = CreateFrame("Frame", "DKstuffFrame", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:EnableMouse(false)
    root:RegisterForDrag("LeftButton")
    root:Hide()

    root:SetScript("OnDragStart", function(frame)
        if not ns.db.locked then frame:StartMoving() end
    end)
    root:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        Display:SavePosition()
        if ns.Options.Refresh then ns.Options:Refresh() end
    end)

    self.root = root
    self.icon = BuildIconMode(root)
    self.bar = BuildBarMode(root)
    self.glow = ns.Glow.Attach(root)

    local hint = root:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("BOTTOM", root, "TOP", 0, 4)
    ns.StyleFont(hint, 11)
    hint:SetText("DKstuff - drag me")
    hint:Hide()
    self.moveHint = hint
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function Display:ApplyLayout()
    if not self.root then return end
    local db = ns.db
    local root = self.root

    root:SetScale(db.scale)
    root:SetAlpha(db.alpha)
    root:ClearAllPoints()
    root:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)

    local accent = db.accent

    if db.mode ~= "bar" then
        root:SetSize(db.iconSize, db.iconSize)
        ns.StyleFont(self.icon.stacks, math.max(8, db.iconSize * 0.26))
        self.icon.border:SetColor(accent[1], accent[2], accent[3], 1)
        self.icon:Show()
        self.bar:Hide()
    else
        root:SetSize(db.barWidth, db.barHeight)
        self.bar.tex:SetWidth(db.barHeight - 2)
        self.bar.cd:SetSize(db.barHeight * 1.9, db.barHeight - 4)
        ns.StyleFont(self.bar.name, math.max(9, db.barHeight * 0.46))
        self.bar.status:SetStatusBarColor(accent[1], accent[2], accent[3], 1)
        self.bar.border:SetColor(accent[1], accent[2], accent[3], 1)
        self.bar:Show()
        self.icon:Hide()
    end

    self.glow:SetColor(db.glowColor[1], db.glowColor[2], db.glowColor[3])
    self.glow:SetSize(root:GetWidth(), root:GetHeight())

    -- The slot button is anchored to the proxy, which fills root, so it
    -- follows every size change without being touched.
    self:BuildEngine()

    self:Invalidate()
    if self.testEntry then
        self:Render(self.testEntry)
    elseif self.unlocked then
        self:RenderPreview()
    else
        self:Update(ns.Watcher:GetActiveAura())
    end
end

function Display:SavePosition()
    local point, _, relPoint, x, y = self.root:GetPoint(1)
    if not point then return end
    local db = ns.db
    db.point, db.relPoint = point, relPoint
    db.x, db.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

function Display:ResetPosition()
    local db = ns.db
    db.point, db.relPoint = ns.DEFAULTS.point, ns.DEFAULTS.relPoint
    db.x, db.y = ns.DEFAULTS.x, ns.DEFAULTS.y
    self:ApplyLayout()
end

function Display:SetUnlocked(unlocked)
    if not self.root then return end
    self.unlocked = unlocked and true or false
    ns.db.locked = not self.unlocked
    self.root:EnableMouse(self.unlocked)

    if self.unlocked then
        self.moveHint:Show()
        self:RenderPreview()
        ns.Print("Display unlocked - drag it into place, then lock it again.")
    else
        self:SavePosition()
        self.moveHint:Hide()
        self:Invalidate()
        if self.testEntry then
            self:Render(self.testEntry)
        else
            self:Update(ns.Watcher:GetActiveAura())
        end
        ns.Print("Display locked.")
    end

    if ns.Options.Refresh then ns.Options:Refresh() end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local function PaintIcon(region, spellID)
    local tex = ns.SpellTexture(spellID)
    if tex then
        region:SetTexture(tex)
        region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        region:SetVertexColor(1, 1, 1, 1)
    else
        -- Spell unknown to this client build: show a flat accent tile rather
        -- than the green "missing texture" square.
        local accent = ns.db.accent
        region:SetTexture(ns.WHITE)
        region:SetTexCoord(0, 1, 0, 1)
        region:SetVertexColor(accent[1], accent[2], accent[3], 1)
    end
end

-- Dims the composite, never the root: the engine's aura button is a child of
-- root and would inherit a lowered alpha, which would grey out the real buff.
function Display:SetInactiveLook(inactive)
    local db = ns.db
    local composite = (db.mode ~= "bar") and self.icon or self.bar
    local iconTex = composite.tex

    iconTex:SetDesaturated(inactive and true or false)
    if inactive then
        iconTex:SetVertexColor(0.55, 0.55, 0.55, 1)
        composite:SetAlpha(db.inactiveAlpha)
    else
        composite:SetAlpha(1)
    end
    self.root:SetAlpha(db.alpha)
end

---------------------------------------------------------------------------
-- Engine slot (primary source when available)
--
-- The engine may read the secret aura we may not. It binds spell IDs we
-- name, shows the button only while the aura is up, and drives icon,
-- duration and stacks itself.
---------------------------------------------------------------------------
-- One engine slot, bound to whatever is in the tracked spell list. The slot
-- button is anchored to a proxy we own, so size and position stay editable
-- afterwards - an engine button's own subtree is locked once its initializer
-- returns.
--
-- The slot's spell set is baked in, so changing the tracked list needs a new
-- container. Containers cannot be freed, only parked, which is why this is
-- keyed on a signature rather than rebuilt on every layout pass.
function Display:BuildEngine()
    -- Engine.lua is parked until 12.1; on a 12.0 client it is not even
    -- loaded, so this whole path is skipped and the proc-glow route drives
    -- the display on its own.
    if not (ns.Engine and ns.Engine:IsAvailable()) then return end

    local signature = table.concat(ns.db.spellIDs, ",")
        .. ":" .. tostring(ns.db.showTimer) .. ":" .. tostring(ns.db.showStacks)
    if self.engineSignature == signature then return end

    -- Rebuilding in combat is refused; keep the previous slot running until
    -- combat ends rather than tearing it down for nothing.
    if self.auraContainer and ns.Engine:IsLocked() then
        self.enginePending = true
        return
    end
    self.enginePending = false
    self.engineSignature = signature

    if not self.auraProxy then
        local proxy = CreateFrame("Frame", nil, self.root)
        proxy:SetAllPoints(self.root)
        proxy:SetFrameLevel(self.root:GetFrameLevel() + 3)
        self.auraProxy = proxy
    end

    if self.auraContainer then ns.Engine:Retire(self.auraContainer) end
    self.engineWired = false

    local container = ns.Engine:CreateContainer(self.auraProxy)
    self.auraContainer = container
    if not container then return end

    local include = {}
    for _, id in ipairs(ns.db.spellIDs) do include[id] = true end

    local proxy = self.auraProxy
    local db = ns.db
    local ok = pcall(container.AddAuraSlot, container, "dksMain",
        ns.Engine:Filter("HELPFUL"), {
            candidateFilters = { includeSpellIDs = include },
            initializeFrame  = function(button)
                button:SetAllPoints(proxy)
                ns.Engine:MakeDisplayOnly(button)

                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                button:SetIcon(icon)

                local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                cooldown:SetAllPoints(icon)
                cooldown:SetDrawEdge(false)
                cooldown:SetSwipeColor(0, 0, 0, 0.7)
                cooldown:SetHideCountdownNumbers(true)
                cooldown.noCooldownCount = true
                button:SetDurationCooldown(cooldown)

                local edge = ns.CreateBorder(button, 1, "OVERLAY")
                local accent = db.accent
                edge:SetColor(accent[1], accent[2], accent[3], 1)

                local textLayer = CreateFrame("Frame", nil, button)
                textLayer:SetAllPoints(button)
                textLayer:SetFrameLevel(button:GetFrameLevel() + 4)

                if db.showStacks then
                    pcall(function()
                        local stacks = textLayer:CreateFontString(nil, "OVERLAY")
                        ns.StyleFont(stacks, math.max(8, db.iconSize * 0.26))
                        stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                        button:SetApplicationCount(stacks, { minCount = 2 })
                    end)
                end

                if db.showTimer then
                    pcall(function()
                        local duration = textLayer:CreateFontString(nil, "OVERLAY")
                        ns.StyleFont(duration, math.max(9, db.iconSize * 0.40))
                        duration:SetPoint("CENTER", button, "CENTER", 0, 0)
                        ns.Engine.BindDurationText(button, duration)
                    end)
                end
            end,
        })

    if ok then
        self.engineWired = ns.Engine:Bind(container, "player")
    end
end

-- True while the engine slot is the display. The glow route then only drives
-- the proc flash, and the addon's own icon stays out of the way.
function Display:UsingEngine()
    return ns.Engine ~= nil and ns.db.source ~= "glow" and self.engineWired == true
end

-- Only runs for auras whose timing is readable (non-secret). Secret auras
-- keep a full bar and rely on the engine-drawn countdown instead.
local function OnUpdate(frame, elapsed)
    local self = Display
    self.accum = (self.accum or 0) + elapsed
    if self.accum < UPDATE_INTERVAL then return end
    self.accum = 0

    local fill = self.barFill
    if not fill then
        frame:SetScript("OnUpdate", nil)
        return
    end

    local remaining = fill.expiration - GetTime()
    if remaining <= 0 then
        frame:SetScript("OnUpdate", nil)
        self.bar.status:SetValue(0)
        return
    end
    self.bar.status:SetValue(remaining)
end

-- Drives the bar fill. Returns true when an animated fill was armed.
function Display:ApplyBarFill(entry)
    self.barFill = nil
    self.root:SetScript("OnUpdate", nil)

    local duration, expiration
    if entry.plainDuration then
        duration, expiration = entry.plainDuration, entry.plainStart + entry.plainDuration
    else
        local data = entry.data
        duration = data and data.duration
        expiration = data and data.expirationTime
        if not (ns.CanCompute(duration) and ns.CanCompute(expiration) and duration > 0) then
            -- Secret timing: a static full bar, the countdown carries the info.
            self.bar.status:SetMinMaxValues(0, 1)
            self.bar.status:SetValue(1)
            return false
        end
    end

    self.bar.status:SetMinMaxValues(0, duration)
    self.bar.status:SetValue(math.max(0, expiration - GetTime()))
    self.barFill = { expiration = expiration }
    self.accum = UPDATE_INTERVAL
    self.root:SetScript("OnUpdate", OnUpdate)
    return true
end

-- Renders a live aura entry {spellID, auraInstanceID, data}. Pass nil to hide.
function Display:Render(entry)
    if not self.root then return end
    local db = ns.db

    if not entry then
        self.current = nil
        self.barFill = nil
        self.root:SetScript("OnUpdate", nil)
        self.glow:Stop()
        if self.unlocked then
            self:RenderPreview()
        elseif db.alwaysShow then
            self:RenderInactive()
        elseif self:UsingEngine() then
            -- The engine button owns its own visibility, so root must stay
            -- shown: hiding it would hide the real buff along with it.
            self.icon:Hide()
            self.bar:Hide()
            self.root:Show()
        else
            self.root:Hide()
        end
        return
    end

    self:SetInactiveLook(false)

    -- A proc is either "nothing was up and now something is", or a demonstrably
    -- different aura instance. Instance IDs that cannot be read report nil,
    -- which counts as unchanged so the glow never spams.
    local isNewProc = (self.current == nil)
    if not isNewProc then
        isNewProc = ns.SameValue(self.current.auraInstanceID, entry.auraInstanceID) == false
    end
    self.current = entry

    -- Engine mode: the aura button already shows icon, swipe, timer and
    -- stacks. All that is left for us is the proc flash.
    if self:UsingEngine() then
        if not db.alwaysShow then
            self.icon:Hide()
            self.bar:Hide()
        end
        self.root:Show()
        if isNewProc and db.glow then self.glow:Play() end
        return
    end

    if db.mode ~= "bar" then
        PaintIcon(self.icon.tex, entry.spellID)
        ArmCooldown(self.icon.cd, entry, db.showTimer)
        self.icon.cd:Show()
        ApplyStacks(self.icon.stacks, entry, db.showStacks)
        self.root:SetScript("OnUpdate", nil)
    else
        PaintIcon(self.bar.tex, entry.spellID)
        self.bar.name:SetText(db.showName and (ns.SpellName(entry.spellID) or "") or "")
        ArmCooldown(self.bar.cd, entry, db.showTimer)
        self.bar.cd:Show()
        self:ApplyBarFill(entry)
    end

    self.root:Show()

    if isNewProc then
        if db.glow then self.glow:Play() end
        if db.sound then
            local kit = SOUNDKIT and (SOUNDKIT.UI_POWER_AURA_GENERATED or SOUNDKIT.RAID_WARNING)
            if kit then PlaySound(kit, "Master") end
        end
    end
end

-- Static stand-in shown while the frame is unlocked, so it can be positioned
-- without waiting for a real proc.
function Display:RenderPreview()
    if not self.root then return end
    local db = ns.db
    local spellID = db.spellIDs[1] or ns.PRIMARY_SPELL_ID

    self.current = nil
    self.barFill = nil
    self.root:SetScript("OnUpdate", nil)
    self:SetInactiveLook(false)

    if db.mode ~= "bar" then
        PaintIcon(self.icon.tex, spellID)
        ClearCooldown(self.icon.cd)
        self.icon.stacks:SetText(db.showStacks and "2" or "")
    else
        PaintIcon(self.bar.tex, spellID)
        self.bar.name:SetText(db.showName and (ns.SpellName(spellID) or ("Spell " .. spellID)) or "")
        ClearCooldown(self.bar.cd)
        self.bar.status:SetMinMaxValues(0, 1)
        self.bar.status:SetValue(0.56)
    end

    self.root:Show()
end

-- Shown instead of hiding when "always show" is on and the aura is down.
function Display:RenderInactive()
    local db = ns.db
    local spellID = db.spellIDs[1] or ns.PRIMARY_SPELL_ID

    self.current = nil
    self.barFill = nil
    self.root:SetScript("OnUpdate", nil)

    if db.mode ~= "bar" then
        PaintIcon(self.icon.tex, spellID)
        ClearCooldown(self.icon.cd)
        self.icon.cd:Hide()
        self.icon.stacks:SetText("")
    else
        PaintIcon(self.bar.tex, spellID)
        self.bar.name:SetText(db.showName and (ns.SpellName(spellID) or "") or "")
        ClearCooldown(self.bar.cd)
        self.bar.cd:Hide()
        self.bar.status:SetMinMaxValues(0, 1)
        self.bar.status:SetValue(0)
    end

    self:SetInactiveLook(true)
    self.root:Show()
end

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
function Display:StartTest()
    local spellID = ns.db.spellIDs[1] or ns.PRIMARY_SPELL_ID

    self.current = nil
    self.testEntry = {
        spellID       = spellID,
        route         = "test",
        plainStart    = GetTime(),
        plainDuration = 15,
        plainStacks   = "2",
    }
    self:Render(self.testEntry)
    ns.Print("Preview running for 15s.")

    if self.testTimer then self.testTimer:Cancel() end
    self.testTimer = C_Timer.NewTimer(15, function() Display:StopTest() end)
end

function Display:StopTest()
    self.testEntry = nil
    if self.testTimer then
        self.testTimer:Cancel()
        self.testTimer = nil
    end
    self:Invalidate()
    self:Update(ns.Watcher:GetActiveAura())
end

-- Identity of what is currently on screen. The watcher polls, so re-arming
-- the cooldown on every tick would restart the swipe ten times a second.
local function RenderKey(entry)
    -- "none" rather than nil, so the very first "nothing is up" update still
    -- renders (the always-show state has to appear at login).
    if not entry then return "none" end
    local instance = ns.CanCompute(entry.auraInstanceID) and entry.auraInstanceID or "?"
    -- stamp distinguishes consecutive procs on routes that carry no aura
    -- instance (proc glow), so a re-proc still re-renders and re-glows.
    return string.format("%s:%s:%s:%s", tostring(entry.spellID), tostring(instance),
        tostring(entry.route), tostring(entry.stamp or "-"))
end

function Display:Invalidate()
    self.renderKey = nil
end

-- Entry point for the watcher. Test mode wins over live data so a real proc
-- cannot yank the preview away while the user is positioning the frame.
function Display:Update(entry)
    if self.testEntry then return end

    local key = RenderKey(entry)
    if key == self.renderKey then return end
    self.renderKey = key

    self:Render(entry)
end

-- A tracked-spell change during combat leaves the old slot running and the
-- rebuild queued; replay it the moment the engine will accept it again.
local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
    if not Display.enginePending then return end
    Display:BuildEngine()
    Display:Invalidate()
    Display:Update(ns.Watcher:GetActiveAura())
end)
