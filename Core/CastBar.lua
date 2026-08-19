---------------------------------------------------------------------------
-- THE CAST BAR - one line that says what is being cast at you.
--
-- It is the game's own cast, drawn where a tank is already looking instead
-- of on a nameplate somewhere behind the boss. Everything on it comes from
-- the engine and most of it is a SECRET VALUE (see the header of
-- Core/Casts.lua): the spell's name goes to SetText, its icon to SetTexture,
-- its progress to SetCooldownFromDurationObject, and Blizzard's own
-- "important" flag to SetAlphaFromBoolean. Not one of them is read.
--
-- THE ONE QUESTION A TANK ASKS is "is that one coming at me", and the engine
-- is the only thing allowed to answer it: PlayerIsSpellTarget hands back a
-- secret boolean and SetAlphaFromBoolean draws it, so the stripe down the
-- left of this bar is certain while no line of Lua ever tested anything.
-- Beside it sits the best-effort word (co-tank / group / somebody), which
-- Core/Casts.lua reads from the target's role and class when the game will
-- give them up, and which says "somebody" rather than guessing when it will
-- not. Both are on the bar because they answer at different times: the
-- stripe never lies and cannot be written into a rule; the word can be, and
-- is honest about not knowing.
---------------------------------------------------------------------------
local _, ns = ...

local CastBar = {}
ns.CastBar = CastBar

local panel

local function Cfg()
    return ns.Casts.Config().bar
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
function CastBar:Create()
    if panel then return panel end

    panel = CreateFrame("Frame", "ZwoelfStuffCastBar", UIParent)
    panel:SetSize(260, 26)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(false)
    panel:Hide()

    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)

    -- THE FILL. A StatusBar whose value the engine drives through a
    -- cooldown-style duration object: on this patch the cast's start and end
    -- times are secret and arithmetic on them raises, so nothing here counts
    -- anything. SetTimerDuration is the door (it is what Blizzard's own
    -- nameplate bars use since 12.0); where the client is older the bar
    -- simply sits full, which is honest rather than wrong.
    panel.fill = CreateFrame("StatusBar", nil, panel)
    panel.fill:SetMinMaxValues(0, 1)
    panel.fill:SetValue(1)

    panel.track = panel.fill:CreateTexture(nil, "BACKGROUND")
    panel.track:SetAllPoints(panel.fill)

    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    panel.iconEdge = ns.CreateBorder(panel, 1, "OVERLAY")

    -- IS IT AIMED AT YOU. The one question a tank actually asks, and the
    -- engine is the only thing that may answer it: PlayerIsSpellTarget gives
    -- back a SECRET boolean, and SetAlphaFromBoolean is the setter that takes
    -- one. So this stripe is either there or it is not, decided inside the
    -- client, and no line of ours ever tested anything. EXBoss marks its own
    -- bars exactly this way (Modules/Tools/MythicCast.lua:844).
    --
    -- It is a full-height stripe rather than a word, because a word would
    -- have to be written by Lua and a stripe is a texture the engine fades.
    panel.atMe = panel:CreateTexture(nil, "OVERLAY")
    panel.atMe:SetAlpha(0)

    -- And the same trick for "the game calls this one important"
    -- (C_Spell.IsSpellImportant, secret) - the glow EllesmereUI draws on its
    -- nameplates (EllesmereUINameplates.lua:7162).
    panel.important = panel:CreateTexture(nil, "OVERLAY")
    panel.important:SetColorTexture(1, 0.55, 0.1, 0.35)
    panel.important:SetAlpha(0)

    local text = panel:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(text, nil, 12, "OUTLINE")
    text:SetJustifyH("LEFT")
    panel.name = text

    local aim = panel:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(aim, nil, 12, "OUTLINE")
    aim:SetJustifyH("RIGHT")
    panel.aim = aim

    panel.chrome = ns.CreateChrome(panel)

    CastBar.panel = panel
    self:ApplyLayout()
    return panel
end

function CastBar.Frame()
    return panel
end

---------------------------------------------------------------------------
-- Placing and layout
---------------------------------------------------------------------------
function CastBar:ApplyLayout()
    if not panel then return end
    local cfg = Cfg()
    local C = ns.UI.C

    local width = math.max(60, tonumber(cfg.width) or 260)
    local height = math.max(10, tonumber(cfg.height) or 26)
    panel:SetSize(width, height)

    -- NOT WHILE THE OPTIONS PAGE HAS IT. Every slider on that page ends
    -- here, and a preview that jumps back to the screen on each one is the
    -- co-tank panel's old bug (Core/OptionsCoTanks.lua says the same).
    if not self.hosted then
        panel:SetScale(tonumber(cfg.scale) or 1)
        panel:ClearAllPoints()
        panel:SetPoint(cfg.point or "CENTER", UIParent,
            cfg.relPoint or "CENTER", cfg.x or 0, cfg.y or 0)
    end

    local inset = math.max(0, tonumber(cfg.borderSize) or 1)
    panel.fill:ClearAllPoints()
    panel.fill:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -inset)
    panel.fill:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, inset)
    panel.fill:SetStatusBarTexture(ns.Media.Statusbar(cfg.texture))

    local iconSize = math.max(8, tonumber(cfg.iconSize) or height)
    panel.icon:ClearAllPoints()
    panel.icon:SetSize(iconSize, iconSize)
    panel.icon:SetPoint("RIGHT", panel, "LEFT", -4, 0)
    panel.icon:SetShown(cfg.showIcon ~= false)
    panel.iconEdge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    panel.important:ClearAllPoints()
    panel.important:SetAllPoints(panel)

    local accent = C.accent
    panel.atMe:ClearAllPoints()
    panel.atMe:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.atMe:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panel.atMe:SetWidth(math.max(2, tonumber(cfg.atMeWidth) or 4))
    panel.atMe:SetColorTexture(accent[1], accent[2], accent[3], 1)

    ns.Media.ApplyFont(panel.name, cfg.font ~= "" and cfg.font or nil,
        cfg.fontSize or 12, cfg.outline or "OUTLINE")
    ns.Media.ApplyFont(panel.aim, cfg.font ~= "" and cfg.font or nil,
        cfg.fontSize or 12, cfg.outline or "OUTLINE")

    panel.name:ClearAllPoints()
    panel.name:SetPoint("LEFT", panel.fill, "LEFT", 6, 0)
    panel.aim:ClearAllPoints()
    panel.aim:SetPoint("RIGHT", panel.fill, "RIGHT", -6, 0)
    panel.name:SetPoint("RIGHT", panel.aim, "LEFT", -8, 0)

    local surface = ns.SurfaceColor()
    panel.bg:SetColorTexture(surface[1], surface[2], surface[3],
        tonumber(cfg.bgAlpha) or 0.85)
    panel.track:SetColorTexture(surface[1], surface[2], surface[3], 1)
    panel.chrome.pixel:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
end

function CastBar:SavePosition()
    if not panel or self.hosted then return end
    local cfg = Cfg()
    cfg.point, cfg.relPoint = "CENTER", "CENTER"
    local x, y = panel:GetCenter()
    local px, py = UIParent:GetCenter()
    if x and y and px and py then
        cfg.x = math.floor(x - px + 0.5)
        cfg.y = math.floor(y - py + 0.5)
    end
end

function CastBar:SetPlacing(on)
    self.placing = on and true or false
    self:Refresh()
end

---------------------------------------------------------------------------
-- Drawing
--
-- ONE ENTRY AT A TIME: the foremost cast, which is the one aimed at you if
-- there is one. A tank reading a bar mid-pull reads one line.
---------------------------------------------------------------------------
local AIM_WORDS = {
    me      = "ON YOU",
    tank    = "co-tank",
    group   = "group",
    unknown = "somebody",
    nobody  = "",
}

function CastBar:ShouldShow(entry)
    if not ns.Modules:IsOn("casts") then return false end
    local cfg = Cfg()
    if cfg.enabled == false then return false end
    if self.placing then return true end
    if ns.Casts:Testing() then return true end
    if not entry then return false end
    if cfg.show and ns.Visibility and not ns.Visibility:Evaluate(cfg) then
        return false
    end
    return true
end

function CastBar:Refresh()
    if not panel then return end

    local entry = ns.Casts:Current()
    if not self:ShouldShow(entry) then
        panel:Hide()
        return
    end

    local cfg = Cfg()

    -- PLACING WITH NOTHING CASTING still has to show a bar, or there is
    -- nothing on screen to put anywhere. Same reasoning as the raid bar's.
    if not entry then
        panel.name:SetText("Cast bar")
        panel.aim:SetText("")
        panel.icon:SetTexture(nil)
        panel.important:SetAlpha(0)
        panel.atMe:SetAlpha(1)
        panel:Show()
        return
    end

    -- THE NAME AND THE ICON, BOTH POSSIBLY SECRET, both only ever handed to
    -- a setter. `type(x) ~= "nil"` is the one question allowed of them.
    if cfg.showName ~= false and type(entry.name) ~= "nil" then
        panel.name:SetText(entry.name)
    elseif cfg.showMob ~= false and entry.mob then
        panel.name:SetText(entry.mob)
    else
        panel.name:SetText("")
    end

    if type(entry.texture) ~= "nil" then
        panel.icon:SetTexture(entry.texture)
    else
        panel.icon:SetTexture(nil)
    end

    if cfg.showTarget ~= false then
        panel.aim:SetText(AIM_WORDS[entry.aim or "nobody"] or "")
        local C = ns.UI.C
        local colour = entry.aim == "me" and C.accent or C.textDim
        panel.aim:SetTextColor(colour[1], colour[2], colour[3])
    else
        panel.aim:SetText("")
    end

    -- THE FILL. The duration object drives it engine-side; when there is
    -- none (an older client, or a channel the API will not describe) the bar
    -- sits full rather than empty - a cast IS happening, and an empty bar
    -- would say the opposite.
    --
    -- The third argument is the FILL DIRECTION and it is not decoration: a
    -- cast fills up towards the hit, a channel drains away from it. Argument
    -- order read off EXBoss/Modules/Tools/MythicCast.lua:1175.
    local fill = panel.fill
    if entry.duration ~= nil and fill.SetTimerDuration then
        fill:SetMinMaxValues(0, 1)
        local interpolation = Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.None or nil
        pcall(fill.SetTimerDuration, fill, entry.duration, interpolation,
            entry.isChannel and 1 or 0)
    else
        fill:SetValue(1)
    end

    -- WHETHER IT CAN BE KICKED, and this one is the sharpest example of the
    -- whole patch: `notInterruptible` is a SECRET boolean, so the colour is
    -- chosen inside the engine by SetVertexColorFromBoolean and never by an
    -- `if` of ours. Two colour objects go in, one comes out on the texture.
    -- EXBoss draws the same distinction the same way (MythicCast.lua:1168),
    -- and its comment says it in as many words: never boolean-test this.
    local colour = cfg.color or { 0.8, 0.24, 0.2 }
    local shielded = cfg.uninterruptibleColor or { 0.45, 0.45, 0.52 }
    local texture = fill.GetStatusBarTexture and fill:GetStatusBarTexture()
    local painted = false
    if texture and texture.SetVertexColorFromBoolean and CreateColor
        and entry.notInterruptible ~= nil then
        painted = pcall(texture.SetVertexColorFromBoolean, texture,
            entry.notInterruptible,
            CreateColor(shielded[1], shielded[2], shielded[3], 1),
            CreateColor(colour[1], colour[2], colour[3], 1))
    end
    if not painted then
        fill:SetStatusBarColor(colour[1], colour[2], colour[3])
    end

    -- IS IT ON YOU. Secret in, alpha out, decision inside the client.
    local atMe = ns.Casts.AtMe(entry.unit)
    if atMe ~= nil and panel.atMe.SetAlphaFromBoolean then
        pcall(panel.atMe.SetAlphaFromBoolean, panel.atMe, atMe, 255, 0)
    else
        -- No engine answer: fall back to the readable half rather than to a
        -- stripe that is always on. A mark that means nothing is worse than
        -- no mark.
        panel.atMe:SetAlpha(entry.aim == "me" and 1 or 0)
    end

    -- IMPORTANT: the engine decides. A secret boolean into the one setter
    -- that takes one; where the setter is missing, no glow.
    local important = ns.Casts.Important(entry.spellID)
    if important ~= nil and panel.important.SetAlphaFromBoolean then
        pcall(panel.important.SetAlphaFromBoolean, panel.important, important,
            255, 0)
    else
        panel.important:SetAlpha(0)
    end

    panel:Show()
end
