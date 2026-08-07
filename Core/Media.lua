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
local FALLBACK = {
    font      = "Fonts\\FRIZQT__.TTF",
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    border    = "Interface\\Tooltips\\UI-Tooltip-Border",
    background = "Interface\\Buttons\\WHITE8X8",
}

-- The names our own defaults use. Registered by LibSharedMedia itself, so
-- they are present the moment the library loads.
Media.DEFAULT = {
    font      = "Friz Quadrata TT",
    statusbar = "Blizzard",
    border    = "None",
}

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
local function Fetch(kind, key)
    if not (LSM and key) then return FALLBACK[kind] end
    local path = LSM:Fetch(kind, key, true)
    return path or FALLBACK[kind]
end

function Media.Font(key)      return Fetch("font", key) end
function Media.Statusbar(key) return Fetch("statusbar", key) end
function Media.Border(key)    return Fetch("border", key) end
function Media.Background(key) return Fetch("background", key) end

-- Sorted names, ready for a picker. An empty list is impossible in practice
-- and handled anyway: the picker then shows the one default.
function Media.List(kind)
    if not LSM then return { Media.DEFAULT[kind] } end

    local list = LSM:List(kind)
    if not list or #list == 0 then return { Media.DEFAULT[kind] } end

    -- LSM keeps its own order; copied rather than returned directly, because
    -- the caller must not be able to sort the library's own table.
    local out = {}
    for index, name in ipairs(list) do out[index] = name end
    return out
end

function Media.IsKnown(kind, key)
    if not (LSM and key) then return false end
    return LSM:IsValid(kind, key)
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

-- The plate behind an icon. A colour texture when no texture is chosen,
-- because a flat fill is sharper than a bar texture stretched over a square.
function ns.PaintSurface(texture, style)
    if not texture then return end

    local colour = style.backdropColor
    local key = style.backdropTexture

    if key and Media.IsKnown("statusbar", key) then
        texture:SetTexture(Media.Statusbar(key))
        texture:SetVertexColor(colour[1], colour[2], colour[3], style.backdropAlpha)
    else
        texture:SetColorTexture(colour[1], colour[2], colour[3], style.backdropAlpha)
    end

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
        chrome.pixel:SetColor(colour[1], colour[2], colour[3], 1)
        chrome.pixel:Show()
        return
    end

    if not chrome.SetBackdrop then return end

    chrome.pixel:Hide()
    -- Edge files are drawn from a strip and need real room; the thickness
    -- slider runs 0-4, so it is scaled into the 6-24 an edge file expects.
    chrome:SetBackdrop({ edgeFile = Media.Border(key), edgeSize = size * 6 })
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
