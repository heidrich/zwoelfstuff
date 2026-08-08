---------------------------------------------------------------------------
-- Minimap button - click to open the settings.
--
-- Self-built, no LibDBIcon. Three stacked layers: an accent rim, a dark plate
-- and the icon.
--
-- THE RIM AND THE PLATE ARE A FILE, NOT A COLOUR FILL.
--
-- They used to be SetColorTexture with a circular alpha mask over the top, and
-- they came out SQUARE - the owner's "der bg ragt immer aus den kreisen raus".
-- A mask works by multiplying a texture's alpha channel, and a solid colour
-- fill has no texture for it to multiply, so the mask did nothing to the two
-- layers that were fills and everything to the one that was a real file. The
-- icon was round and the two plates behind it were not.
--
-- So the disc is a file too: white, alpha-shaped, tinted per layer with
-- SetVertexColor - exactly the technique the icon set already uses, one file
-- serving both the accent rim and the near-black plate. Two cuts, because this
-- button is 32 units and the interface is rarely at 1:1; see Media/mkdisc.
--
-- The button is dragged around the minimap edge and its angle is saved, which
-- is what every minimap button does and what people expect.
---------------------------------------------------------------------------
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BUTTON_SIZE = 32

-- Long brackets: the path opens with \A, which is not a legal Lua escape and
-- takes the whole file down at load if this is ever written as a quoted string.
local DISC_SMALL = [[Interface\AddOns\ZwoelfStuff\Media\disc-64]]
local DISC_LARGE = [[Interface\AddOns\ZwoelfStuff\Media\disc-128]]

local function Disc()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    return scale > 1.25 and DISC_LARGE or DISC_SMALL
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
local function Radius()
    -- Derived from the live minimap so it still sits on the edge when a UI
    -- suite has resized it.
    return (Minimap:GetWidth() / 2) + 8
end

function MinimapButton:UpdatePosition()
    if not self.button then return end
    local angle = math.rad(ns.db.minimap.angle or 200)
    local radius = Radius()
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate(button)
    local centerX, centerY = Minimap:GetCenter()
    if not centerX then return end

    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
    ns.db.minimap.angle = angle
    MinimapButton:UpdatePosition()
    button:SetButtonState("NORMAL")
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function MinimapButton:Create()
    if self.button then return end
    if not Minimap then return end

    local button = CreateFrame("Button", "ZwoelfStuffMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- Accent rim, dark plate, icon - all masked to a circle. The colour comes
    -- from the design system rather than a saved setting: it is the addon's
    -- own mark, and one accent everywhere is the point of having one.
    local accent = ns.UI.C.accent

    local disc = Disc()

    local rim = button:CreateTexture(nil, "BACKGROUND")
    rim:SetAllPoints(button)
    rim:SetTexture(disc)
    rim:SetVertexColor(accent[1], accent[2], accent[3], 1)
    button.rim = rim

    local plate = button:CreateTexture(nil, "BORDER")
    plate:SetPoint("CENTER")
    plate:SetSize(BUTTON_SIZE - 4, BUTTON_SIZE - 4)
    plate:SetTexture(disc)
    plate:SetVertexColor(0.05, 0.05, 0.06, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(BUTTON_SIZE - 8, BUTTON_SIZE - 8)
    icon:SetMask(MASK)
    button.icon = icon

    button:SetScript("OnDragStart", function(self)
        if ns.db.minimap.locked then return end
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        -- Right click used to toggle the co-tank panel. That module is parked
        -- until 12.1, so ns.CoTanks is nil and calling it is a crash. Guarded
        -- rather than removed: the binding returns with the module.
        if mouseButton == "RightButton" and ns.CoTanks then
            ns.db.coTanks.enabled = not ns.db.coTanks.enabled
            ns.CoTanks:Refresh()
            ns.Print("Co-tank panel",
                ns.db.coTanks.enabled and "|cff40ff40on|r" or "|cffff4040off|r")
        else
            ns.Options:Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r")
        GameTooltip:AddLine("|cffffffffClick|r  open the window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cffffffffDrag|r  move around the minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = button
    self:Refresh()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function MinimapButton:Refresh()
    if not self.button then return end
    local db = ns.db.minimap

    -- The addon's own icon, not a spell's. It used to show whatever aura was
    -- being tracked, which changed under the user and made the button hard to
    -- find again on a busy minimap.
    self.button.icon:SetTexture(ns.ICON_TEXTURE)

    -- SetVertexColor, not SetColorTexture: this is a tint on the disc file,
    -- and re-setting the texture here would throw the shape away.
    local accent = ns.UI.C.accent
    self.button.rim:SetVertexColor(accent[1], accent[2], accent[3], 1)

    self:UpdatePosition()
    self.button:SetShown(db.show and true or false)
end

function MinimapButton:SetShown(shown)
    ns.db.minimap.show = shown and true or false
    self:Refresh()
    ns.Print("Minimap button",
        ns.db.minimap.show and "|cff40ff40shown|r" or "|cffff4040hidden|r")
end
