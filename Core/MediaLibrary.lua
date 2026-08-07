---------------------------------------------------------------------------
-- MediaLibrary - the bar textures this addon ships.
--
-- WHY SHIP ANY, WHEN Core/Media.lua ARGUES FOR THE OPPOSITE.
--
-- That file says the media list should be whatever the user's OTHER addons
-- registered, under the names they already know, and that shipping a second
-- unfamiliar set is worse than shipping none. That is still true - and it is
-- an argument about the LIST, not about the contents.
--
-- The registry is shared. Everything here goes into LibSharedMedia under
-- names that say where they came from, next to everything ElvUI, WeakAuras
-- and the rest put there. Nobody gets a smaller list; everybody gets a longer
-- one, and it works the other way round too - these are available to every
-- addon on the machine that reads the same registry.
--
-- HOW THEY ARE MADE.
--
-- Generated rather than drawn: each one is a formula for "how bright is this
-- bar at this height", rendered to a 256x64 TGA. They are WHITE-BASED on
-- purpose, because a status bar texture is tinted by whoever draws it - a
-- texture with colour baked in can only ever be the one colour.
--
-- The vertical profile is what matters. A status bar is stretched across
-- whatever width it is given, so the horizontal detail in the striped and
-- segmented ones is measured in PIXELS at generation time and survives that
-- stretch; everything else is a gradient that does not care.
---------------------------------------------------------------------------
local _, ns = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

local PATH = "Interface\\AddOns\\ZwoelfStuff\\Media\\statusbars\\"

-- Name, file. The names carry the ZS prefix so they sort together in a list
-- that also holds four other addons' worth of textures - which is the whole
-- reason for a shared registry, and also the reason a set of twenty
-- unprefixed names would be a nuisance in it.
local BARS = {
    { "ZS Flat",       "flat" },
    { "ZS Smooth",     "smooth" },
    { "ZS Velvet",     "velvet" },
    { "ZS Charcoal",   "charcoal" },
    { "ZS Gloss",      "gloss" },
    { "ZS Glass",      "glass" },
    { "ZS Steel",      "steel" },
    { "ZS Bevel",      "bevel" },
    { "ZS Inset",      "inset" },
    { "ZS Neon",       "neon" },
    { "ZS Outline",    "outline" },
    { "ZS Ridged",     "ridged" },
    { "ZS Aluminium",  "aluminium" },
    { "ZS Stripes",    "stripes" },
    { "ZS Blocks",     "blocks" },
    { "ZS Pixel",      "pixel" },
    { "ZS Cylinder",   "cylinder" },
    { "ZS Hairline",   "hairline" },
    { "ZS Split",      "split" },
    { "ZS Frost",      "frost" },
}

for _, entry in ipairs(BARS) do
    LSM:Register("statusbar", entry[1], PATH .. entry[2])
end

-- What the addon starts on. Blizzard's own is the safe default and it is what
-- every bar written before this file existed already carries, so nothing
-- changes under anybody - this is only the answer for a fresh install.
ns.SHIPPED_BAR_DEFAULT = "ZS Smooth"
