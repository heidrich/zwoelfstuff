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

    -- THE ICON LIVES IN ITS OWN LITTLE FRAME, and that is not tidiness.
    -- ns.CreateBorder anchors its four edges to the frame it is MADE FROM,
    -- and this border was made from the panel - so it drew a second edge
    -- around the whole bar, on top of the chrome, and left the icon bare.
    -- A texture cannot be given one directly (it has no CreateTexture), so
    -- the icon gets a frame of its own and the border belongs to that.
    panel.iconBox = CreateFrame("Frame", nil, panel)
    panel.icon = panel.iconBox:CreateTexture(nil, "ARTWORK")
    panel.icon:SetAllPoints(panel.iconBox)
    panel.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    panel.iconEdge = ns.CreateBorder(panel.iconBox, 1, "OVERLAY")

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

    -- THE WORDS, AND THEY ARE OURS. Not one character of this comes off the
    -- cast: it is a fixed string this file owns, so it may be written into a
    -- font string like any other label. What the ENGINE decides is whether
    -- you can see it, through the same SetAlphaFromBoolean that fades the
    -- stripe - which is the only way a certain answer becomes something you
    -- can read. We may not test that boolean; we may hand it over.
    --
    -- Above the bar rather than on it, so it never has to share a line with
    -- the spell name or crowd the aim word out of one.
    local onYou = panel:CreateFontString(nil, "OVERLAY")
    ns.Media.ApplyFont(onYou, nil, 14, "OUTLINE")
    onYou:SetJustifyH("CENTER")
    onYou:SetAlpha(0)
    panel.onYou = onYou

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
    panel.iconBox:ClearAllPoints()
    panel.iconBox:SetSize(iconSize, iconSize)
    panel.iconBox:SetPoint("RIGHT", panel, "LEFT", -4, 0)
    panel.iconBox:SetShown(cfg.showIcon ~= false)
    panel.iconEdge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)

    panel.important:ClearAllPoints()
    panel.important:SetAllPoints(panel)

    local accent = C.accent
    panel.atMe:ClearAllPoints()
    panel.atMe:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.atMe:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panel.atMe:SetWidth(math.max(2, tonumber(cfg.atMeWidth) or 4))
    panel.atMe:SetColorTexture(accent[1], accent[2], accent[3], 1)

    -- THE WORDS. Its own size, because the whole point of it is to be read
    -- without looking; the empty string falls back rather than drawing a
    -- mark made of nothing.
    local word = cfg.atMeText
    if type(word) ~= "string" or word == "" then word = "ON YOU" end
    ns.Media.ApplyFont(panel.onYou, cfg.font ~= "" and cfg.font or nil,
        (tonumber(cfg.fontSize) or 12) + 2, cfg.outline or "OUTLINE")
    panel.onYou:ClearAllPoints()
    panel.onYou:SetPoint("BOTTOM", panel, "TOP", 0, 3)
    panel.onYou:SetText(word)
    panel.onYou:SetTextColor(accent[1], accent[2], accent[3])

    -- WHICH HALVES EXIST AT ALL is decided here, once, off the setting.
    -- Refresh only ever decides whether a half that exists is VISIBLE, and
    -- it is the engine that decides that.
    local stripe, words = ns.CastRules.Mark(cfg.atMeMark)
    panel.atMe:SetShown(stripe)
    panel.onYou:SetShown(words)

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

-- ONE MARK, FADED BY THE ENGINE. A file-local rather than a closure inside
-- Refresh, because Refresh runs ten times a second and a closure per call is
-- garbage that never stops - the owner's rule about the resting state.
--
-- The fallback is the readable half, not an always-on mark: where the client
-- will not answer, a stripe that is always lit means nothing at all.
local function DrawMark(region, atMe, readable)
    if not region:IsShown() then return end
    if atMe ~= nil and region.SetAlphaFromBoolean then
        pcall(region.SetAlphaFromBoolean, region, atMe, 255, 0)
    else
        region:SetAlpha(readable and 1 or 0)
    end
end

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
        -- BOTH HALVES LIT while it is being placed: you are putting the mark
        -- somewhere, so you have to be able to see where it lands.
        panel.atMe:SetAlpha(1)
        panel.onYou:SetAlpha(1)
        panel:Show()
        return
    end

    -- THE NAME AND THE ICON, BOTH POSSIBLY SECRET, both only ever handed to
    -- a setter that declares one. EllesmereUI's own Mythic+ cast bars say it
    -- in as many words on this patch - "the live texture may be SECRET,
    -- SetTexture accepts it" (EUI_MythicTimer_TargetedSpellBars.lua:376) -
    -- and its draw is line for line this one.
    --
    -- THROUGH pcall ALL THE SAME, and not out of superstition. If a client
    -- ever refuses one of these, an unguarded call takes the whole refresh
    -- with it: everything below here - the timer, the kick colour, the mark
    -- that says it is coming at you - stops being drawn, and the bar is left
    -- wearing whatever the last cast put on it. Guarded, one blank field
    -- costs one blank field, and CastBar.refused says which so /zs casts can
    -- report it instead of leaving somebody to guess.
    local wrote = false
    if cfg.showName ~= false and type(entry.name) ~= "nil" then
        wrote = pcall(panel.name.SetText, panel.name, entry.name)
        CastBar.refusedName = not wrote
    end
    if not wrote then
        if cfg.showMob ~= false and entry.mob then
            panel.name:SetText(entry.mob)
        else
            panel.name:SetText("")
        end
    end

    local drew = false
    if type(entry.texture) ~= "nil" then
        drew = pcall(panel.icon.SetTexture, panel.icon, entry.texture)
        CastBar.refusedIcon = not drew
    end
    -- WHERE THERE IS NO TEXTURE THE ID MAY STILL ANSWER. EllesmereUI's
    -- fallback (same file, :380) and it costs nothing: in the world the id
    -- is readable and this fills the icon in; in a key it is secret, the
    -- pcall fails, and we are exactly where we were.
    if not drew and type(entry.spellID) ~= "nil" and C_Spell
        and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, entry.spellID)
        if ok and type(info) == "table" and info.iconID then
            drew = pcall(panel.icon.SetTexture, panel.icon, info.iconID)
        end
    end
    if not drew then panel.icon:SetTexture(nil) end

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

    -- IS IT ON YOU. Secret in, alpha out, decision inside the client - and
    -- now for both halves of the mark, the stripe and the words. Which of
    -- them exist was decided in ApplyLayout; all that happens here is that
    -- the engine fades whichever are there.
    local atMe = ns.Casts.AtMe(entry.unit)
    DrawMark(panel.atMe, atMe, entry.aim == "me")
    DrawMark(panel.onYou, atMe, entry.aim == "me")

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
