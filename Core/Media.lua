---------------------------------------------------------------------------
-- Media - fonts, bar textures and border textures.
--
-- WHY A LIBRARY AND NOT OUR OWN.
--
-- The rest of this addon is built from scratch on purpose: the window, the
-- widgets, the look. Media is the exception, and the reason is not effort.
--
-- LibSharedMedia is a REGISTRY, not a design. Every UI addon on a machine
-- registers what it ships into it - ElvUI's textures, EllesmereUI's, the ones
-- that came with WeakAuras, whatever fonts somebody installed years ago. Ask
-- it for the list and the user sees the media they already have and already
-- picked out, under the names they already know. Ship our own instead and
-- they get a second, smaller, unfamiliar set, and the one thing they wanted
-- is not in it.
--
-- So this file is deliberately thin. It answers three questions - what is
-- available, what does this key point at, and did the list just change - and
-- it never decides what anything looks like.
--
-- Nothing here is required. With no other addon installed the lists hold
-- Blizzard's own handful, which is why every lookup falls back rather than
-- failing: a saved texture name from an addon that has since been uninstalled
-- must not take a bar down with it.
---------------------------------------------------------------------------
local _, ns = ...

local Media = {}
ns.Media = Media

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
Media.lib = LSM

-- What a missing key falls back to. Blizzard's own, so they exist on every
-- client whether or not a single other addon is installed.
-- SOUND IS NOT LISTED, AND THAT IS THE HONEST ANSWER RATHER THAN A GAP.
-- The four below are file paths because Blizzard ships those as files. Its
-- sounds are SoundKit ids and FileDataIDs, so there is no path to name here -
-- and inventing one would hand every caller a string that plays nothing. A
-- sound lookup that finds nothing therefore returns nil, and exactly one
-- place in this file knows that: Media.PlaySound.
local FALLBACK = {
    font      = "Fonts\\FRIZQT__.TTF",
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    border    = "Interface\\Tooltips\\UI-Tooltip-Border",
    background = "Interface\\Buttons\\WHITE8X8",
}

-- The names our own defaults use. Registered by LibSharedMedia itself, so
-- they are present the moment the library loads.
--
-- EVERY KIND A PICKER CAN OPEN NEEDS AN ENTRY HERE, and that is not tidiness:
-- Media.List falls back to `{ Media.DEFAULT[kind] }` when the library is
-- absent or its list is empty, and for a kind that is missing here that is
-- `{ nil }` - a table of length zero, and a dropdown with no rows. `sound`
-- and `background` were both missing; the second was a latent one nobody had
-- opened a picker on yet.
Media.DEFAULT = {
    font       = "Friz Quadrata TT",
    statusbar  = "Blizzard",
    border     = "None",
    background = "None",
    sound      = "None",
}

-- The panel wants a NARROW GROTESK, and Arial Narrow is it.
--
-- Expressway used to stand in front of it here, taken from whatever addon had
-- installed it. Two things were wrong with that. The file on this machine is
-- the BOLD cut whatever it calls itself, so the window came out heavier than
-- it was drawn - owner: "ich wuerde ggf auch mal die fette schrift rausnehmen,
-- dann wirds eleganter". And a default that changes depending on which OTHER
-- addons happen to be installed is not a default; two players comparing
-- screenshots of the same version see different type.
--
-- Arial Narrow is registered by LibSharedMedia itself, so it is there on every
-- client, on its own. Expressway stays in the picker for anyone who has it.
local PANEL_FONTS = { "Arial Narrow", "Friz Quadrata TT" }

function Media.PanelFont()
    if LSM then
        for _, name in ipairs(PANEL_FONTS) do
            if LSM:Fetch("font", name, true) then return name end
        end
    end
    return Media.DEFAULT.font
end

-- AND THE OTHER SIDE OF THAT SAME DECISION, which is the owner's own split:
-- "standard Fonts ausserhalb von der addon font ist expressway". The window
-- above keeps Arial Narrow; what the addon writes OUT ON THE SCREEN is set in
-- Expressway - ns.SCREEN_FONT, named once in Init.lua.
--
-- WHY THIS IS NOT THE THING THE COMMENT ABOVE ARGUES AGAINST. That paragraph
-- is about a default that CHANGES depending on which other addons you have.
-- This one does not: the profile stores the string "Expressway" whether the
-- client has the file or not, so every player on this version is asking for
-- the same face and the picker shows them the same answer. What differs is
-- only what the engine can actually load, and the chain below makes that
-- difference as small as it can be made.
--
-- THE CHAIN, and the order is the whole point: a narrow grotesk, then another
-- narrow grotesk, then whatever there is. Falling straight to Blizzard's
-- serif - which is what Media.Font did for any missing name - turns "we do
-- not ship this font" into a completely different design rather than a
-- slightly different one.
--
-- THE ONLY WAY TO MAKE IT EXACT IS TO SHIP THE FILE. Nothing here can conjure
-- a font the machine does not have, and this addon ships no .ttf today. Named
-- rather than papered over: until Expressway is embedded, a player without it
-- gets Arial Narrow and a screenshot that does not match ours.
local SCREEN_FONTS = { "Expressway", "Arial Narrow", "Friz Quadrata TT" }

function Media.ScreenFont()
    if LSM then
        for _, name in ipairs(SCREEN_FONTS) do
            if LSM:Fetch("font", name, true) then return name end
        end
    end
    return Media.DEFAULT.font
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
local function Fetch(kind, key)
    if not (LSM and key) then return FALLBACK[kind] end
    local path = LSM:Fetch(kind, key, true)
    return path or FALLBACK[kind]
end

-- THE ONE LOOKUP THAT DOES NOT FALL STRAIGHT TO BLIZZARD'S FALLBACK.
--
-- Every other kind here answers `path or FALLBACK[kind]`, and for a texture
-- that is right: a missing bar texture and a plain white one look like the
-- same kind of thing. A missing FACE does not. FRIZQT is a serif at a
-- different weight and a different width, so one player without Expressway
-- was not getting "the design with one font substituted", he was getting a
-- different design - and every size, every offset and every band width in
-- this addon is measured against a narrow grotesk.
--
-- So a name the client cannot load falls through SCREEN_FONTS first, and
-- only what is left over lands on FRIZQT. Blizzard's own font is still the
-- last word rather than an error: a client with no LibSharedMedia at all is
-- a client where nothing can be looked up, and drawing nothing is worse than
-- drawing the wrong face.
function Media.Font(key)
    if not LSM then return FALLBACK.font end

    if key then
        local path = LSM:Fetch("font", key, true)
        if path then return path end
    end

    for _, name in ipairs(SCREEN_FONTS) do
        local path = LSM:Fetch("font", name, true)
        if path then return path end
    end
    return FALLBACK.font
end
function Media.Statusbar(key) return Fetch("statusbar", key) end
function Media.Border(key)    return Fetch("border", key) end
function Media.Background(key) return Fetch("background", key) end

-- THE ONE THAT IS NOT ALWAYS A STRING. The library stores the NUMBER 1 for
-- its own "None" entry, and every other kind here always answers with a path.
-- So this is the one lookup whose result must not be handed to string:find or
-- string:lower - and the one caller allowed to hold it is directly below.
function Media.Sound(key)     return Fetch("sound", key) end

-- THE ONE SINK, for the same reason ns.Tint is one: a sound that can be a
-- path, a number, a name for silence or nothing at all is four cases, and
-- four callers would each get a different three of them right.
--
-- Answers with whether a noise actually went out, which is what lets the
-- throttle above it start its clock on a sound that played rather than on one
-- that was asked for. A name left behind by an addon somebody has since
-- uninstalled fetches nothing and says so.
function Media.PlaySound(key, channel)
    if not key or key == "" or key == "None" then return false end

    local path = Media.Sound(key)
    if not path then return false end

    if not PlaySoundFile then return false end
    local ok, willPlay = pcall(PlaySoundFile, path, channel or "Master")
    return (ok and willPlay) and true or false
end

---------------------------------------------------------------------------
-- WHICH ADDON PUT THIS HERE, and leaving some of it out
--
-- A registry is only useful while it can be read. One sound pack on this
-- machine registers 188 entries, the pack beside it another 188, and the
-- owner's words on opening the picker were "die exwind sounds muessen alle
-- raus oder geblockt werden, das sind 1000". He is right: a list nobody can
-- scroll to the end of is the same as no list.
--
-- BY THE FOLDER, NOT BY THE NAME. Those 188 all happen to share a bracketed
-- prefix, and matching on it would work today and break the moment somebody
-- renames a pack or another addon adopts the same habit. The PATH says which
-- addon a file belongs to and cannot be spelt two ways.
--
-- THE FILTER IS NOT THIS FILE'S OPINION. Media answers what is available and
-- never decides what anything should be - so whoever owns the policy hands a
-- predicate in, and this only applies it. Core/Sounds.lua sets the one for
-- sounds; nothing sets one for fonts or textures, and those lists are
-- therefore exactly what they always were.
---------------------------------------------------------------------------
local filters = {}

function Media.SetFilter(kind, fn)
    filters[kind] = fn
end

-- The addon folder a media key lives in, lower case, or nil for anything
-- that is not in an addon at all - Blizzard's own files, and the library's
-- "None", which is a number rather than a path.
function Media.Provider(kind, key)
    if not (LSM and key) then return nil end
    local path = LSM:Fetch(kind, key, true)
    if type(path) ~= "string" then return nil end
    return path:lower():match("addons[\\/]([^\\/]+)[\\/]")
end

-- Every provider that has put something into one kind, with how many. What
-- the settings page needs in order to offer them as a list rather than
-- asking somebody to type a folder name.
function Media.Providers(kind)
    local counts, order = {}, {}
    if not LSM then return counts, order end

    for _, name in ipairs(LSM:List(kind) or {}) do
        local who = Media.Provider(kind, name)
        if who then
            if not counts[who] then order[#order + 1] = who end
            counts[who] = (counts[who] or 0) + 1
        end
    end
    table.sort(order, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    return counts, order
end

-- Sorted names, ready for a picker. An empty list is impossible in practice
-- and handled anyway: the picker then shows the one default.
function Media.List(kind)
    if not LSM then return { Media.DEFAULT[kind] } end

    local list = LSM:List(kind)
    if not list or #list == 0 then return { Media.DEFAULT[kind] } end

    -- LSM keeps its own order; copied rather than returned directly, because
    -- the caller must not be able to sort the library's own table.
    local allow = filters[kind]
    local out = {}
    for _, name in ipairs(list) do
        if not allow or allow(name) then out[#out + 1] = name end
    end

    -- NEVER EMPTY, whatever was filtered out. Somebody who has switched off
    -- every provider they have would otherwise be left with a dropdown of no
    -- rows, which is the one state a control must never be in - and it would
    -- take away the "None" that means silence.
    if #out == 0 then return { Media.DEFAULT[kind] } end
    return out
end

function Media.IsKnown(kind, key)
    if not (LSM and key) then return false end
    return LSM:IsValid(kind, key)
end

-- Ours, or somebody else's?
--
-- Asked of the PATH, not of the name. The textures this addon ships all carry
-- a "ZS " prefix so they sort together, but a prefix is a convention and this
-- has to be right for fonts and borders too - where we ship none today and
-- might tomorrow. The registry knows where every file actually lives.
function Media.IsOurs(kind, key)
    if not (LSM and key) then return false end
    local path = LSM:Fetch(kind, key, true)
    if type(path) ~= "string" then return false end
    return path:lower():find("addons\\zwoelfstuff\\", 1, true) ~= nil
end

-- The same list, in the two groups the picker shows it in: what we shipped
-- first, then what the user's other addons brought.
--
-- Deliberately NOT alphabetical across the two. At forty-odd entries that is
-- the difference between finding and searching: the twenty you can rely on
-- being there sit together at the top, and everything else follows.
function Media.Grouped(kind)
    local ours, theirs = {}, {}
    for _, name in ipairs(Media.List(kind)) do
        local into = Media.IsOurs(kind, name) and ours or theirs
        into[#into + 1] = name
    end
    return ours, theirs
end

---------------------------------------------------------------------------
-- Staying current
--
-- Media arrives late: an addon that loads after this one registers its
-- textures when IT is ready, so a list built at login is short and a list
-- built on demand is right. The callback is for anything already on screen.
---------------------------------------------------------------------------
local listeners = {}

function Media.OnChanged(fn)
    listeners[#listeners + 1] = fn
end

if LSM and LSM.RegisterCallback then
    LSM.RegisterCallback(Media, "LibSharedMedia_Registered", function()
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end

---------------------------------------------------------------------------
-- Text
--
-- One place that turns "which font, how big, outlined?" into a styled font
-- string, so no caller has to remember that an empty flag string and nil mean
-- different things to SetFont.
---------------------------------------------------------------------------
Media.OUTLINES = {
    { value = "",              text = "None" },
    { value = "OUTLINE",       text = "Outline" },
    { value = "THICKOUTLINE",  text = "Thick outline" },
    { value = "MONOCHROME",    text = "Monochrome" },
}

---------------------------------------------------------------------------
-- Surfaces and edges
--
-- Both renderers - Blizzard's adopted frames and our own drawn cells - paint
-- these the same way, so they live here rather than twice.
---------------------------------------------------------------------------

-- TWO REUSED COLOUR OBJECTS, not two fresh ones per call.
--
-- SetGradient copies the values at call time, so one shared pair is safe
-- across every texture in the addon - and tinting runs on every style pass,
-- which is often enough that CreateColor here would be two tables of garbage
-- each time. Read off EllesmereUIUnitFrames.lua:1171-1179, which says the
-- same thing about the same call.
--
-- The plain-table fallback is not defensiveness for its own sake: it is what
-- makes this file loadable in the desktop harness, where there is no client
-- and therefore no CreateColor. A colour object IS four fields, and the four
-- fields are all SetGradient reads.
local function ColourObject()
    if CreateColor then return CreateColor(1, 1, 1, 1) end
    return { r = 1, g = 1, b = 1, a = 1 }
end

local gradA, gradB = ColourObject(), ColourObject()

-- Colour a texture, solid or as a gradient. THE ONE SINK, so the fill, the
-- backdrop and every threshold overlay cannot end up doing it three ways.
--
-- gradient is optional and shaped { on, color, direction }. Absent, off, or
-- on a client with no SetGradient, this is exactly the flat tint it replaced.
--
-- THE VERTEX COLOUR IS RESET TO WHITE FIRST. A gradient MULTIPLIES the vertex
-- colour, so a texture still carrying its flat tint comes out as the tint
-- times the ramp - darker at both ends and never the colours that were
-- picked. That is not a subtle bug in the picture, but it is a silent one in
-- the code, because both calls succeed.
function ns.Tint(texture, colour, alpha, gradient)
    if not texture then return end

    local r, g, b = colour[1], colour[2], colour[3]
    alpha = alpha or 1

    -- SOLID IS A RAMP OF ONE COLOUR, and it is set as one on purpose.
    --
    -- There is no ClearGradient and SetVertexColor does NOT undo a gradient:
    -- once a texture has one it keeps it. Switching the setting off, or
    -- picking a flat look after a gradient one, left the ramp on screen until
    -- a reload - a control that worked in one direction only, which is a
    -- worse version of the defect the whole feature was written to avoid.
    local second = colour
    local orientation, swap = "HORIZONTAL", false

    if gradient and gradient.on then
        second = gradient.color or colour
        orientation, swap = ns.Layout.GradientOrder(gradient.direction)
    end

    if not texture.SetGradient then
        texture:SetVertexColor(r, g, b, alpha)
        return
    end

    -- The SECOND colour carries the first one's alpha. A gradient that fades
    -- out is a separate wish from a gradient that changes colour, and there
    -- is no control for it - so it must not happen by accident because a
    -- swatch handed back three numbers and a nil.
    -- The four fields directly, not SetRGBA. Same thing - that method only
    -- assigns them - and it is what the reference does when it reuses a pair
    -- of colour objects (EllesmereUICdmBuffBars.lua:3945-3948). It also keeps
    -- the static check quiet, which otherwise reports SetRGBA as undefined on
    -- every build because CreateColor's return type is not declared anywhere.
    if swap then
        gradA.r, gradA.g, gradA.b, gradA.a = second[1], second[2], second[3], alpha
        gradB.r, gradB.g, gradB.b, gradB.a = r, g, b, alpha
    else
        gradA.r, gradA.g, gradA.b, gradA.a = r, g, b, alpha
        gradB.r, gradB.g, gradB.b, gradB.a = second[1], second[2], second[3], alpha
    end

    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetGradient(orientation, gradA, gradB)
end

-- The plate behind an icon. A colour texture when no texture is chosen,
-- because a flat fill is sharper than a bar texture stretched over a square.
function ns.PaintSurface(texture, style)
    if not texture then return end

    local colour = style.backdropColor
    local key = style.backdropTexture

    if key and Media.IsKnown("statusbar", key) then
        texture:SetTexture(Media.Statusbar(key))
    else
        -- White, then tinted - NOT SetColorTexture(r, g, b) as it was.
        -- SetColorTexture bakes the colour into the texture itself, and a
        -- gradient set on top of a texture that is already orange is orange
        -- times the ramp. The colour has to arrive as a vertex colour for
        -- either path to work, and ns.Tint is the only thing that sets it.
        texture:SetColorTexture(1, 1, 1, 1)
    end

    ns.Tint(texture, colour, style.backdropAlpha, style.backdropGradient)
    texture:SetShown(style.backdrop)
end

-- The frame a border is drawn on: its own, above whatever the parent draws.
-- BackdropTemplate is what carries an edge file; without it only the
-- pixel border works, which is a missing texture option rather than a
-- missing border.
function ns.CreateChrome(parent)
    local ok, chrome = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
    if not ok or not chrome then
        chrome = CreateFrame("Frame", nil, parent)
    end

    chrome:SetAllPoints(parent)
    chrome:SetFrameLevel(parent:GetFrameLevel() + 5)
    chrome.pixel = ns.CreateBorder(chrome, 1, "OVERLAY")
    return chrome
end

-- outside moves the edge OFF the thing it frames.
--
-- On an icon the border belongs on top: the art fills the frame edge to edge,
-- and a line drawn just inside it is what reads as a crisp icon. On a BAR it
-- does not - the last pixel of the fill and the leading spark are the parts
-- you actually read, and a border sitting on them looks like a mistake. So a
-- bar-shaped cell frames itself from just outside instead.
--
-- Both renderers - Blizzard's adopted frames and our own drawn cells - pass
-- the same flag from the same place. A rule either of them decided for itself
-- is a rule they would eventually disagree about.
function ns.PaintBorder(chrome, style, outside)
    if not chrome then return end

    local size = style.borderSize
    local colour = style.borderColor
    local key = style.borderTexture

    local parent = chrome:GetParent()
    if parent then
        local pad = outside and size or 0
        chrome:ClearAllPoints()
        chrome:SetPoint("TOPLEFT", parent, "TOPLEFT", -pad, pad)
        chrome:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pad, -pad)
    end

    -- Shown, every time. CDM:Release hides the whole chrome frame when it
    -- hands an item back to Blizzard, and nothing here ever turned it on
    -- again - so a spell that left a bar and came back had no border for the
    -- rest of the session, and the textures below were being set on a frame
    -- nobody could see. The empty case is handled by hiding the CONTENTS
    -- rather than the frame.
    chrome:Show()

    if size <= 0 then
        chrome.pixel:Hide()
        if chrome.SetBackdrop then chrome:SetBackdrop(nil) end
        return
    end

    -- The crisp one-pixel line, drawn from colour textures. Sharper than any
    -- edge file at small sizes, which is why it stays the default.
    if not key or key == "None" or not Media.IsKnown("border", key) then
        if chrome.SetBackdrop then chrome:SetBackdrop(nil) end
        chrome.pixel:SetThickness(size)
        chrome.pixel:SetTint(colour, 1, style.borderGradient)
        chrome.pixel:Show()
        return
    end

    if not chrome.SetBackdrop then return end

    chrome.pixel:Hide()
    -- Edge files are drawn from a strip and need real room; the thickness
    -- slider runs 0-4, so it is scaled into the 6-24 an edge file expects.
    chrome:SetBackdrop({ edgeFile = Media.Border(key), edgeSize = size * 6 })
    -- ONE COLOUR, and the panel says so where the setting is.
    -- SetBackdropBorderColor is a single tint over the whole nine-slice;
    -- there is no per-edge access and therefore no gradient. Silently taking
    -- the second colour and dropping it is exactly the defect this addon
    -- spent a session removing.
    chrome:SetBackdropBorderColor(colour[1], colour[2], colour[3], 1)
end

function Media.ApplyFont(fontString, key, size, flags, colour)
    if not fontString then return end

    local path = Media.Font(key)
    -- A font file that will not load leaves the string with NO font, and the
    -- next SetText raises rather than doing nothing. Falling back is the
    -- difference between a wrong typeface and a broken bar.
    if not fontString:SetFont(path, size, flags or "") then
        fontString:SetFont(FALLBACK.font, size, flags or "")
    end

    if colour then
        fontString:SetTextColor(colour[1], colour[2], colour[3], colour[4] or 1)
    end
end
