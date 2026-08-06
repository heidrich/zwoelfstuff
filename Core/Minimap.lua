---------------------------------------------------------------------------
-- Minimap button - click to open the settings.
--
-- Self-built, no LibDBIcon. The round look comes from a circular alpha mask
-- (Interface\CharacterFrame\TempPortraitAlphaMask, verified in use by current
-- addons on this client) applied to three stacked textures: an accent rim, a
-- dark backdrop, and the icon itself.
--
-- The button is dragged around the minimap edge and its angle is saved, which
-- is what every minimap button does and what people expect.
---------------------------------------------------------------------------
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BUTTON_SIZE = 32

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

    local button = CreateFrame("Button", "DKstuffMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- Accent rim, dark plate, icon - all masked to a circle.
    local accent = ns.db.accent

    local rim = button:CreateTexture(nil, "BACKGROUND")
    rim:SetAllPoints(button)
    rim:SetColorTexture(accent[1], accent[2], accent[3], 1)
    rim:SetMask(MASK)
    button.rim = rim

    local plate = button:CreateTexture(nil, "BORDER")
    plate:SetPoint("CENTER")
    plate:SetSize(BUTTON_SIZE - 4, BUTTON_SIZE - 4)
    plate:SetColorTexture(0.05, 0.05, 0.06, 1)
    plate:SetMask(MASK)

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
        GameTooltip:AddLine("|cff7ec6d4DK|r|cffff7a3dstuff|r")
        GameTooltip:AddLine("|cffffffffLeft click|r  settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cffffffffRight click|r  toggle co-tank panel", 0.7, 0.7, 0.7)
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

    local texture = ns.db.spellIDs[1] and ns.SpellTexture(ns.db.spellIDs[1])
    self.button.icon:SetTexture(texture or ns.WHITE)

    local accent = ns.db.accent
    self.button.rim:SetColorTexture(accent[1], accent[2], accent[3], 1)

    self:UpdatePosition()
    self.button:SetShown(db.show and true or false)
end

function MinimapButton:SetShown(shown)
    ns.db.minimap.show = shown and true or false
    self:Refresh()
    ns.Print("Minimap button",
        ns.db.minimap.show and "|cff40ff40shown|r" or "|cffff4040hidden|r")
end
