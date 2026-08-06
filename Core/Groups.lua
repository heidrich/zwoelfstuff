---------------------------------------------------------------------------
-- Groups - tracking bars: any number of them, icons or bars, arranged in
-- rows, columns or a grid, in an order you control.
--
-- TWO LAYOUT MODES, and the difference matters:
--
--   "fixed"   One engine SLOT per spell. Every spell owns one position, in
--             YOUR order, forever. A spell that is down leaves its place
--             empty rather than letting the next one slide into it, so the
--             bar never rearranges itself mid-pull and muscle memory holds.
--             The spell of each slot is known to us, so bars can show names.
--
--   "dynamic" One engine GROUP. The engine decides which aura lands in which
--             button and sorts them itself, so the display stays compact -
--             but positions move as auras come and go, and we cannot know
--             which aura a given button is showing (that is exactly the
--             secret the engine keeps), so bars show no name.
--
-- Fixed is the default because "so you can sort it yourself" was the point.
--
-- HOW THE POSITIONS STAY EDITABLE
--
-- An engine button's subtree is locked after initializeFrame - reads and
-- writes both - so a button can never be moved or resized afterwards. The way
-- around it is the one EllesmereUI uses for Ebon Might: give every slot a
-- plain proxy frame we own, anchor the engine button to that proxy inside the
-- creation window, and from then on move the PROXY. Two-point anchoring makes
-- the button follow its proxy's size and position forever.
--
-- So size, position, spacing, growth and wrapping are all live. Only what is
-- baked into the widgets - fonts, colours, which spells, the style - needs a
-- rebuild, which is why RebuildSignature exists.
---------------------------------------------------------------------------
local _, ns = ...

local Groups = {}
ns.Groups = Groups

Groups.runtime = {}          -- [index] = { anchor, slots, containers, ... }
Groups.pendingRebuild = nil  -- set while a rebuild waits for combat to end

---------------------------------------------------------------------------
-- Skin: what a single aura widget looks like.
--
-- Everything here runs INSIDE initializeFrame, the only window in which an
-- engine button may be touched. An uncaught error in here aborts the engine's
-- whole frame batch and kills the group, so every optional decoration is
-- pcall-armoured and only the essentials are allowed to fail loudly.
---------------------------------------------------------------------------

local function SkinIcon(button, host, cfg, spellID)
    button:SetAllPoints(host)
    ns.Engine:MakeDisplayOnly(button)

    local size = cfg.iconSize

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetColorTexture(0, 0, 0, cfg.backdropAlpha)

    local icon = button:CreateTexture(nil, "ARTWORK")
    local inset = cfg.borderSize
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)   -- binds the aura's own (secret) texture

    if cfg.showSwipe then
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetSwipeColor(0, 0, 0, 0.7)
        cd:SetHideCountdownNumbers(true)   -- our own text, below
        cd.noCooldownCount = true
        button:SetDurationCooldown(cd)
    end

    if cfg.borderSize > 0 then
        local border = ns.CreateBorder(button, cfg.borderSize, "OVERLAY")
        local c = cfg.borderColor
        border:SetColor(c[1], c[2], c[3], 1)
    end

    -- Text rides its own frame so the cooldown swipe cannot cover it.
    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(button)
    textLayer:SetFrameLevel(button:GetFrameLevel() + 4)

    if cfg.showStacks then
        pcall(function()
            local stacks = textLayer:CreateFontString(nil, "OVERLAY")
            ns.StyleFont(stacks, cfg.stackSize or math.max(8, size * 0.30))
            stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            -- minCount 2 makes the engine blank a single application, which
            -- is the "only show stacks above 1" rule without us comparing.
            button:SetApplicationCount(stacks, { minCount = 2 })
        end)
    end

    if cfg.showTimer then
        pcall(function()
            local duration = textLayer:CreateFontString(nil, "OVERLAY")
            -- Fonted BEFORE registration: the engine writes into the string
            -- immediately and an unfonted one hard-errors.
            ns.StyleFont(duration, cfg.timerSize or math.max(9, size * 0.38))
            duration:SetPoint(cfg.timerAnchor, button, cfg.timerAnchor,
                cfg.timerAnchor == "CENTER" and 0 or 1,
                cfg.timerAnchor == "CENTER" and 0 or -1)
            ns.Engine.BindDurationText(button, duration)
        end)
    end

    -- A fixed slot knows its own spell, so it can show something while the
    -- aura is down. Dynamic buttons cannot - the engine keeps that secret.
    if spellID and cfg.showLabel then
        pcall(function()
            local label = textLayer:CreateFontString(nil, "OVERLAY")
            ns.StyleFont(label, math.max(8, size * 0.24))
            label:SetPoint("TOP", button, "BOTTOM", 0, -1)
            label:SetText(ns.SpellName(spellID) or "")
        end)
    end
end

local function SkinBar(button, host, cfg, spellID)
    button:SetAllPoints(host)
    ns.Engine:MakeDisplayOnly(button)

    local height = cfg.barHeight

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetColorTexture(0, 0, 0, cfg.backdropAlpha)

    local inset = cfg.borderSize
    local iconWidth = 0

    if cfg.showIcon then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", inset, inset)
        icon:SetWidth(height - inset * 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)
        iconWidth = height - inset * 2
    end

    -- The engine drains this bar straight from the aura's secret duration,
    -- GPU side. It is the only way a bar can track an aura we cannot read.
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetPoint("TOPLEFT", button, "TOPLEFT", inset + iconWidth + (iconWidth > 0 and 1 or 0), -inset)
    bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    bar:SetStatusBarTexture(ns.WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetColorTexture(1, 1, 1, cfg.trackAlpha)

    local fill = bar:GetStatusBarTexture()
    if fill then
        local c = cfg.barColor
        fill:SetVertexColor(c[1], c[2], c[3], 1)
    end

    ns.Engine.BindDurationBar(button, bar)

    if cfg.borderSize > 0 then
        local border = ns.CreateBorder(button, cfg.borderSize, "OVERLAY")
        local c = cfg.borderColor
        border:SetColor(c[1], c[2], c[3], 1)
    end

    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(bar)
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 4)

    local timer
    if cfg.showTimer then
        pcall(function()
            timer = textLayer:CreateFontString(nil, "OVERLAY")
            ns.StyleFont(timer, cfg.timerSize or math.max(9, height * 0.46))
            timer:SetPoint("RIGHT", textLayer, "RIGHT", -4, 0)
            ns.Engine.BindDurationText(button, timer)
        end)
    end

    -- Only a fixed slot can be named: it is bound to one spell ID, which is
    -- ours and therefore plain. In dynamic mode the engine alone knows which
    -- aura is in which button, so there is nothing truthful to write here.
    if cfg.showName and spellID then
        pcall(function()
            local name = textLayer:CreateFontString(nil, "OVERLAY")
            ns.StyleFont(name, cfg.nameSize or math.max(9, height * 0.44))
            name:SetPoint("LEFT", textLayer, "LEFT", 4, 0)
            if timer then
                name:SetPoint("RIGHT", timer, "LEFT", -4, 0)
            else
                name:SetPoint("RIGHT", textLayer, "RIGHT", -4, 0)
            end
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
            name:SetText(ns.SpellName(spellID) or "")
        end)
    end

    if cfg.showStacks then
        pcall(function()
            local stacks = textLayer:CreateFontString(nil, "OVERLAY")
            ns.StyleFont(stacks, math.max(8, height * 0.40))
            stacks:SetPoint("LEFT", textLayer, "LEFT", 4, 0)
            button:SetApplicationCount(stacks, { minCount = 2 })
        end)
    end
end

---------------------------------------------------------------------------
-- Config normalisation
--
-- One resolved table per group, so the skin functions never reach into the
-- saved variables and every default lives in exactly one place.
---------------------------------------------------------------------------
-- Font sizes are stored as 0 for "derive it from the element size". A plain
-- `cfg.timerSize or fallback` would never reach the fallback, because 0 is
-- truthy in Lua - so the zero is turned into a nil here, once.
local function Auto(value)
    if value and value > 0 then return value end
    return nil
end

local function Resolve(cfg)
    local isBar = cfg.style == "bar"
    return {
        style         = cfg.style,
        iconSize      = cfg.iconSize,
        barWidth      = cfg.barWidth,
        barHeight     = cfg.barHeight,
        elementWidth  = isBar and cfg.barWidth or cfg.iconSize,
        elementHeight = isBar and cfg.barHeight or cfg.iconSize,

        borderSize    = cfg.borderSize,
        borderColor   = cfg.borderColor,
        barColor      = cfg.barColor,
        backdropAlpha = cfg.backdropAlpha,
        trackAlpha    = cfg.trackAlpha,

        showSwipe     = cfg.showSwipe,
        showTimer     = cfg.showTimer,
        showStacks    = cfg.showStacks,
        showName      = cfg.showName,
        showIcon      = cfg.showIcon,
        showLabel     = cfg.showLabel,

        timerAnchor   = cfg.timerAnchor,
        timerSize     = Auto(cfg.timerSize),
        stackSize     = Auto(cfg.stackSize),
        nameSize      = Auto(cfg.nameSize),
    }
end

-- Everything that gets BAKED into the widgets. When this string changes the
-- group has to be rebuilt; when it does not, a settings change is just a
-- reposition and costs nothing.
local function RebuildSignature(cfg)
    local parts = {
        cfg.style, cfg.layoutMode, cfg.unit, cfg.filter,
        tostring(cfg.onlyMine), tostring(cfg.max), tostring(cfg.sort),
        tostring(cfg.borderSize), tostring(cfg.backdropAlpha), tostring(cfg.trackAlpha),
        tostring(cfg.showSwipe), tostring(cfg.showTimer), tostring(cfg.showStacks),
        tostring(cfg.showName), tostring(cfg.showIcon), tostring(cfg.showLabel),
        cfg.timerAnchor,
        tostring(cfg.timerSize), tostring(cfg.stackSize), tostring(cfg.nameSize),
    }

    for _, colorKey in ipairs({ "borderColor", "barColor" }) do
        local c = cfg[colorKey]
        parts[#parts + 1] = string.format("%.2f/%.2f/%.2f", c[1], c[2], c[3])
    end

    -- Font size scales off the element size when not overridden, so the sizes
    -- are baked too and belong in the signature.
    parts[#parts + 1] = string.format("%d/%d/%d", cfg.iconSize, cfg.barWidth, cfg.barHeight)

    for _, spellID in ipairs(cfg.spells) do
        parts[#parts + 1] = tostring(spellID)
    end

    return table.concat(parts, ":")
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

-- Which corner the grid grows out of, derived from the growth directions so
-- the anchor stays put while the bar fills.
local function AnchorCorner(cfg)
    local vertical = (cfg.growthV == "UP") and "BOTTOM" or "TOP"
    local horizontal = (cfg.growthH == "LEFT") and "RIGHT" or "LEFT"
    return vertical .. horizontal
end

-- Grid position of element i (1-based). Returns x/y offsets from the corner.
local function CellOffset(cfg, i, elementW, elementH)
    local perLine = (cfg.wrapAfter and cfg.wrapAfter > 0) and cfg.wrapAfter or math.huge
    local zero = i - 1

    local col, row
    if cfg.axis == "vertical" then
        -- Lines are columns: fill downwards first, wrap sideways.
        row = perLine == math.huge and zero or (zero % perLine)
        col = perLine == math.huge and 0 or math.floor(zero / perLine)
    else
        col = perLine == math.huge and zero or (zero % perLine)
        row = perLine == math.huge and 0 or math.floor(zero / perLine)
    end

    local dx = col * (elementW + cfg.spacing)
    local dy = row * (elementH + cfg.lineSpacing)

    if cfg.growthH == "LEFT" then dx = -dx end
    if cfg.growthV == "DOWN" then dy = -dy end

    return dx, dy
end

-- Total extent, used to size the anchor frame so it can be grabbed and so
-- the unlock outline matches what the group actually occupies.
local function GridExtent(cfg, count, elementW, elementH)
    if count < 1 then return elementW, elementH end

    local perLine = (cfg.wrapAfter and cfg.wrapAfter > 0) and cfg.wrapAfter or count
    local cols, rows
    if cfg.axis == "vertical" then
        rows = math.min(count, perLine)
        cols = math.ceil(count / perLine)
    else
        cols = math.min(count, perLine)
        rows = math.ceil(count / perLine)
    end

    return cols * elementW + (cols - 1) * cfg.spacing,
           rows * elementH + (rows - 1) * cfg.lineSpacing
end

---------------------------------------------------------------------------
-- Runtime construction
---------------------------------------------------------------------------

-- Deliberately unnamed. Anchors are reused across group deletions (see
-- Groups:Remove), and a global name would collide the moment an index is
-- rebuilt for a different group.
local function CreateAnchor(index)
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetSize(1, 1)

    -- Unlocked, the anchor needs something you can actually see and hit. A
    -- group whose auras are all down is otherwise an invisible rectangle, and
    -- "unlock" looks broken because there is nothing on screen to grab.
    anchor.dragFill = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.dragFill:SetAllPoints(anchor)
    anchor.dragFill:SetColorTexture(1, 0.82, 0, 0.13)
    anchor.dragFill:Hide()

    anchor.outline = ns.CreateBorder(anchor, 1, "OVERLAY")
    anchor.outline:SetColor(1, 0.82, 0, 1)
    anchor.outline:Hide()

    anchor.hint = anchor:CreateFontString(nil, "OVERLAY")
    anchor.hint:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    ns.StyleFont(anchor.hint, 11)
    anchor.hint:Hide()

    anchor:SetScript("OnDragStart", function(frame)
        if frame.dkUnlocked then frame:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        Groups:SavePosition(index)
        if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
    end)

    return anchor
end

-- A plain frame per slot. The engine button gets anchored to it once, inside
-- the creation window, and follows it for the rest of its life.
--
-- Pooled per position, because frames cannot be freed in this API and a
-- rebuild happens every time a baked setting changes. The button from the
-- previous build still hangs off the same proxy, but its container was
-- retired and hidden, so it renders nothing.
local function GetSlotProxy(rt, position)
    local proxy = rt.proxyPool[position]
    if not proxy then
        proxy = CreateFrame("Frame", nil, rt.anchor)
        proxy:SetFrameLevel(rt.anchor:GetFrameLevel() + position)
        rt.proxyPool[position] = proxy
    end
    proxy:Show()
    return proxy
end

-- Placeholder shown while the group is unlocked, so it can be positioned
-- without waiting for the auras to actually come up.
-- Reused along with its proxy: a rebuild re-points and re-textures it rather
-- than creating a second one on the same frame.
local function BuildPreview(proxy, cfg, resolved, spellID)
    local preview = proxy.dkPreview

    if not preview then
        preview = CreateFrame("Frame", nil, proxy)
        preview:SetAllPoints(proxy)
        preview:SetFrameLevel(proxy:GetFrameLevel() + 1)

        local bg = preview:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(preview)
        bg:SetColorTexture(0, 0, 0, 0.85)

        preview.icon = preview:CreateTexture(nil, "ARTWORK")
        preview.icon:SetDesaturated(true)

        preview.border = ns.CreateBorder(preview, 1, "OVERLAY")
        preview.border:SetColor(1, 0.82, 0, 0.8)

        proxy.dkPreview = preview
    end

    local icon = preview.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", preview, "TOPLEFT", 1, -1)
    if cfg.style == "bar" and resolved.showIcon then
        icon:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 1, 1)
        icon:SetWidth(resolved.barHeight - 2)
    else
        icon:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -1, 1)
    end

    local texture = spellID and ns.SpellTexture(spellID)
    if texture then
        icon:SetTexture(texture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetVertexColor(1, 1, 1, 1)
    else
        -- Spell unknown to this client build: a flat accent tile rather than
        -- the green "missing texture" square.
        local c = resolved.borderColor
        icon:SetTexture(ns.WHITE)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetVertexColor(c[1], c[2], c[3], 0.5)
    end

    preview:Hide()
    return preview
end

---------------------------------------------------------------------------
-- Build / rebuild one group
---------------------------------------------------------------------------
function Groups:BuildGroup(index)
    local cfg = ns.db.groups[index]
    if not cfg then return end

    local rt = self.runtime[index]
    if not rt then
        rt = { anchor = CreateAnchor(index), slots = {}, containers = {}, proxyPool = {} }
        self.runtime[index] = rt
    end

    -- Retire whatever was there: engine content is add-only and its widget
    -- subtrees are locked, so a changed skin means new frames, never edits.
    for _, container in ipairs(rt.containers) do ns.Engine:Retire(container) end
    wipe(rt.containers)
    for _, slot in ipairs(rt.slots) do slot.proxy:Hide() end
    wipe(rt.slots)

    rt.signature = RebuildSignature(cfg)
    rt.built = false

    if not (cfg.enabled and ns.Engine:IsAvailable()) then
        self:ApplyLayout(index)
        return
    end

    local resolved = Resolve(cfg)
    local filter = ns.Engine:Filter(cfg.filter, cfg.onlyMine and "PLAYER" or nil)
    local skin = (cfg.style == "bar") and SkinBar or SkinIcon

    if cfg.layoutMode == "dynamic" then
        -- One group, engine-owned layout and sorting. The buttons are the
        -- engine's own frames, so the flow layout does the positioning and we
        -- only move the container's parent.
        local container = ns.Engine:CreateContainer(rt.anchor)
        if container then
            local include = {}
            for _, spellID in ipairs(cfg.spells) do include[spellID] = true end

            ns.Engine:AddGroup(container, {
                key             = "dks" .. index,
                filter          = filter,
                max             = cfg.max,
                includeSpellIDs = include,
                sort            = cfg.sort,
                layout          = {
                    elementWidth   = resolved.elementWidth,
                    elementHeight  = resolved.elementHeight,
                    elementSpacing = cfg.spacing,
                    lineSpacing    = cfg.lineSpacing,
                },
                initialize      = function(button)
                    -- No host frame in dynamic mode: the engine sizes and
                    -- places the button, so the skin decorates it in place.
                    skin(button, button, resolved, nil)
                end,
            })
            ns.Engine:Bind(container, cfg.unit)
            rt.containers[1] = container
            rt.container = container
        end
    else
        -- Fixed: one slot per spell on ONE container, each slot bound to
        -- exactly its own spell and anchored to a proxy we can move forever
        -- after.
        --
        -- Many slots sharing one container with an identical filter string is
        -- the shape the reference uses (EllesmereUICdmTbbDecimals builds one
        -- container and one slot per tracked bar, all "HELPFUL", each with
        -- its own includeSpellIDs), so it is not a source of collisions. Do
        -- not "fix" this into a container per slot: container creation is a
        -- synchronous engine parse and the reference explicitly avoids it.
        local container = ns.Engine:CreateContainer(rt.anchor)
        if container then
            rt.containers[1] = container
            rt.container = container

            for i, spellID in ipairs(cfg.spells) do
                local proxy = GetSlotProxy(rt, i)
                local slot = { proxy = proxy, spellID = spellID, position = i }

                -- The error is captured and REPORTED. A silent pcall here is
                -- how a group ends up quietly showing fewer icons than it was
                -- asked for with nothing saying why - the same mistake that
                -- hid a non-existent API for two sessions.
                local ok, err = pcall(container.AddAuraSlot, container,
                    "dks" .. index .. "_" .. i, filter, {
                        candidateFilters = { includeSpellIDs = { [spellID] = true } },
                        sortMethod       = ns.Engine:SortMethod(cfg.sort),
                        initializeFrame  = function(button)
                            skin(button, proxy, resolved, spellID)
                            -- Bind tracking, registered in the creation window
                            -- like everything else. It turns "only one icon
                            -- appears" into a per-spell answer: registered but
                            -- never bound means the ID is wrong, not the code.
                            button:HookScript("OnShow", function()
                                slot.everBound = true
                            end)
                        end,
                    })

                slot.registered = ok
                if not ok then
                    slot.error = tostring(err)
                    ns.Print(string.format(
                        "|cffff4040Spell %d could not be registered|r in \"%s\": %s",
                        spellID, cfg.name, slot.error))
                    proxy:Hide()
                else
                    slot.preview = BuildPreview(proxy, cfg, resolved, spellID)
                end

                rt.slots[#rt.slots + 1] = slot
            end

            ns.Engine:Bind(container, cfg.unit)
        end
    end

    rt.built = true
    self:ApplyLayout(index)
end

---------------------------------------------------------------------------
-- Layout - runs live, in combat included, because it only touches our own
-- proxy frames and the container's flow settings.
---------------------------------------------------------------------------
function Groups:ApplyLayout(index)
    local cfg = ns.db.groups[index]
    local rt = self.runtime[index]
    if not (cfg and rt) then return end

    local anchor = rt.anchor
    local resolved = Resolve(cfg)
    local elementW, elementH = resolved.elementWidth, resolved.elementHeight

    anchor:SetScale(cfg.scale)
    anchor:SetAlpha(cfg.alpha)
    anchor:ClearAllPoints()
    anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)

    local count = (cfg.layoutMode == "dynamic") and cfg.max or #cfg.spells
    local width, height = GridExtent(cfg, count, elementW, elementH)
    anchor:SetSize(math.max(width, 1), math.max(height, 1))

    local corner = AnchorCorner(cfg)

    if cfg.layoutMode == "dynamic" then
        if rt.container then
            -- One element per line means the line size is one element wide;
            -- the fraction keeps a second element from squeezing in.
            local perLine = cfg.wrapAfter or 0
            local maxLineSize
            if perLine > 0 then
                local along = (cfg.axis == "vertical") and elementH or elementW
                local gap = (cfg.axis == "vertical") and cfg.lineSpacing or cfg.spacing
                maxLineSize = perLine * along + (perLine - 1) * gap + 0.4
            end

            ns.Engine:ApplyLayout(rt.container, {
                anchorPoint = corner,
                growthH     = cfg.growthH,
                growthV     = cfg.growthV,
                maxLineSize = maxLineSize,
                vertical    = cfg.axis == "vertical",
            })
            rt.container:ClearAllPoints()
            rt.container:SetPoint(corner, anchor, corner, 0, 0)
        end
    else
        -- The slot buttons are children of the container, which the engine
        -- never resizes when it holds only slots. Matching it to the anchor
        -- costs nothing and removes any chance of a 1x1 parent clipping them.
        if rt.container then
            rt.container:ClearAllPoints()
            rt.container:SetAllPoints(anchor)
        end

        for i, slot in ipairs(rt.slots) do
            local dx, dy = CellOffset(cfg, i, elementW, elementH)
            slot.proxy:ClearAllPoints()
            slot.proxy:SetPoint(corner, anchor, corner, dx, dy)
            slot.proxy:SetSize(elementW, elementH)
            -- A slot the engine refused to register keeps its place in the
            -- order but shows nothing; hiding it would silently close the gap
            -- and make the group look like it had fewer spells than it has.
            slot.proxy:SetShown(slot.registered ~= false)
        end
    end

    anchor:SetShown(cfg.enabled)
    self:ApplyUnlockLook(index)
end

---------------------------------------------------------------------------
-- Unlock / preview
---------------------------------------------------------------------------
function Groups:ApplyUnlockLook(index)
    local cfg = ns.db.groups[index]
    local rt = self.runtime[index]
    if not (cfg and rt) then return end

    local unlocked = rt.anchor.dkUnlocked and true or false

    rt.anchor:EnableMouse(unlocked)
    rt.anchor.outline:SetShown(unlocked)
    rt.anchor.dragFill:SetShown(unlocked)
    rt.anchor.hint:SetShown(unlocked)
    if unlocked then
        rt.anchor.hint:SetText(cfg.name .. " - drag me")
        -- An unlocked group must be visible even when it is switched off or
        -- has nothing to show; otherwise it cannot be positioned in advance.
        rt.anchor:Show()
    end

    for _, slot in ipairs(rt.slots) do
        if slot.preview then slot.preview:SetShown(unlocked) end
    end
end

function Groups:SetUnlocked(index, unlocked)
    local rt = self.runtime[index]
    if not rt then return end

    rt.anchor.dkUnlocked = unlocked and true or false
    if not unlocked then self:SavePosition(index) end
    self:ApplyUnlockLook(index)
end

function Groups:SetAllUnlocked(unlocked)
    for index in ipairs(ns.db.groups) do
        self:SetUnlocked(index, unlocked)
    end
    ns.Print(unlocked
        and "Tracking groups unlocked - drag them into place, then lock again."
        or  "Tracking groups locked.")
end

function Groups:SavePosition(index)
    local cfg = ns.db.groups[index]
    local rt = self.runtime[index]
    if not (cfg and rt) then return end

    local point, _, relPoint, x, y = rt.anchor:GetPoint(1)
    if not point then return end
    cfg.point, cfg.relPoint = point, relPoint
    cfg.x, cfg.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

---------------------------------------------------------------------------
-- Refresh
--
-- Cheap path first: if nothing baked has changed, a settings edit is only a
-- reposition. Only a changed signature costs a rebuild, and a rebuild in
-- combat is deferred - creating containers and binding units are synchronous
-- engine parses, and older builds refuse them outright.
---------------------------------------------------------------------------
function Groups:Refresh(index)
    if index then
        local rt = self.runtime[index]
        local cfg = ns.db.groups[index]
        if not cfg then return end

        if rt and rt.built and rt.signature == RebuildSignature(cfg) then
            self:ApplyLayout(index)
            return
        end

        if ns.Engine:IsLocked() then
            self.pendingRebuild = self.pendingRebuild or {}
            self.pendingRebuild[index] = true
            if rt then self:ApplyLayout(index) end
            return
        end

        self:BuildGroup(index)
        return
    end

    -- Runtime objects outlive their config: a removed group, or a /zs reset
    -- that swaps the whole saved-variables table, leaves anchors on screen
    -- with nothing behind them. Park those before refreshing the rest.
    for runtimeIndex, rt in pairs(self.runtime) do
        if not ns.db.groups[runtimeIndex] then
            for _, container in ipairs(rt.containers) do ns.Engine:Retire(container) end
            rt.anchor:Hide()
            self.runtime[runtimeIndex] = nil
        end
    end

    for i in ipairs(ns.db.groups) do self:Refresh(i) end
end

-- Debounced, so dragging a size slider does not rebuild once per pixel.
function Groups:RefreshSoon(index)
    if self.refreshTimer then self.refreshTimer:Cancel() end
    self.refreshTimer = C_Timer.NewTimer(0.25, function()
        Groups.refreshTimer = nil
        Groups:Refresh(index)
    end)
end

---------------------------------------------------------------------------
-- Group management
---------------------------------------------------------------------------
function Groups:Add(name, style)
    local cfg = {}
    ns.ApplyDefaults(cfg, ns.GROUP_DEFAULTS)
    cfg.style = style or cfg.style
    cfg.name = name or ((style == "bar" and "Bars " or "Icons ") .. (#ns.db.groups + 1))
    cfg.spells = {}

    -- Stagger new groups so a second one does not land exactly on the first.
    cfg.y = ns.GROUP_DEFAULTS.y - (#ns.db.groups * 60)

    ns.db.groups[#ns.db.groups + 1] = cfg
    self:Refresh(#ns.db.groups)
    return #ns.db.groups
end

function Groups:Remove(index)
    if not ns.db.groups[index] then return false end

    table.remove(ns.db.groups, index)

    -- Runtime objects are keyed by position, so every group after this one
    -- now points at different config. Their anchors are REUSED rather than
    -- recreated - frames cannot be freed in this API, so throwing them away
    -- and building fresh ones would leak one anchor per deletion. Forcing a
    -- signature miss makes each surviving index rebuild against its new
    -- config; Refresh() parks the now-surplus tail.
    for _, rt in pairs(self.runtime) do rt.signature = nil end
    self:Refresh()
    return true
end

function Groups:AddSpell(index, spellID)
    local cfg = ns.db.groups[index]
    if not cfg then return false end

    for _, existing in ipairs(cfg.spells) do
        if existing == spellID then return false end
    end

    cfg.spells[#cfg.spells + 1] = spellID
    self:Refresh(index)
    return true
end

function Groups:RemoveSpell(index, spellID)
    local cfg = ns.db.groups[index]
    if not cfg then return false end

    for i, existing in ipairs(cfg.spells) do
        if existing == spellID then
            table.remove(cfg.spells, i)
            self:Refresh(index)
            return true
        end
    end
    return false
end

-- The spell list IS the sort order in fixed mode, so moving an entry is how
-- sorting works.
function Groups:MoveSpell(index, from, to)
    local cfg = ns.db.groups[index]
    if not cfg then return false end
    if not cfg.spells[from] or to < 1 or to > #cfg.spells then return false end

    local spellID = table.remove(cfg.spells, from)
    table.insert(cfg.spells, to, spellID)
    self:Refresh(index)
    return true
end

---------------------------------------------------------------------------
-- Status
--
-- Answers "why do I only see one icon" per spell, instead of leaving it to
-- guesswork. Three states, and they mean different things:
--   not registered - the engine refused the slot; that is a bug here
--   registered, never bound - the slot works, the ID is wrong or the aura
--                             has genuinely not been up since the rebuild
--   bound - it has appeared at least once and the setup is correct
---------------------------------------------------------------------------
function Groups:Status()
    if #ns.db.groups == 0 then
        ns.Print("No tracking groups. |cffffd100/zs group add <name>|r")
        return
    end

    ns.Print("|cffffd100----------------------------------------|r")
    if not ns.Engine:IsAvailable() then
        ns.Print("|cffff4040The aura engine is not available|r - "
            .. (ns.Engine:UnavailableReason() or "reason unknown"))
        ns.Print("Nothing can bind an aura without it; every group stays empty.")
        return
    end

    for index, cfg in ipairs(ns.db.groups) do
        local rt = self.runtime[index]
        ns.Print(string.format("|cffffd100%d. %s|r  %s, %s, %d spells%s",
            index, cfg.name, cfg.style, cfg.layoutMode, #cfg.spells,
            cfg.enabled and "" or "  |cffff4040disabled|r"))

        if cfg.layoutMode == "dynamic" then
            ns.Print("   |cff888888auto mode - the engine fills the slots, nothing to list|r")
        elseif not rt then
            ns.Print("   |cffff4040never built|r")
        else
            for _, slot in ipairs(rt.slots) do
                local state
                if slot.registered == false then
                    state = "|cffff4040slot refused|r  " .. (slot.error or "")
                elseif slot.everBound then
                    state = "|cff40ff40bound|r"
                else
                    state = "|cffff8040registered, never seen|r"
                end
                ns.Print(string.format("   %d  %s  |cff888888%d|r  %s",
                    slot.position or 0, ns.SpellName(slot.spellID) or "?",
                    slot.spellID, state))
            end
        end
    end

    ns.Print("|cff888888\"registered, never seen\" means the slot works and the aura|r")
    ns.Print("|cff888888has not been up. Confirm the ID with /zs probe <id>.|r")
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Groups:Create()
    self:Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    local pending = Groups.pendingRebuild
    if not pending then return end
    Groups.pendingRebuild = nil
    for index in pairs(pending) do
        Groups:BuildGroup(index)
    end
end)
