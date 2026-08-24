---------------------------------------------------------------------------
-- THE PLAYER CARD - what the magnifier on the raid check opens.
--
-- Owner, 2026-08-23: "cool waehre wenn wir vor den spielern eine lupe haben,
-- wenn drauf klickt, inspect mit gear und talenten." So: one click on the
-- glass beside a name, and this card shows what the server told Core/Gear.lua
-- about that person - every worn slot with its item level, which of them is
-- missing an enchant, the spec, the hero tree, and the talent string ready
-- to copy into the game's own import.
--
-- IT DRAWS WHAT WAS READ AND SAYS SO WHEN NOTHING WAS. An inspect answers
-- seconds later or, out of range, not at all - and a card that filled the
-- wait with the last person's gear would be lying with somebody else's
-- numbers. The card is keyed to a GUID, redraws when that guid's answer
-- lands, and shows its reading line until then.
---------------------------------------------------------------------------
local _, ns = ...

local PlayerCard = {}
ns.PlayerCard = PlayerCard

local UI = ns.UI
local C = UI.C

local CARD_W = 470
local ROW_H = 24
local PANEL_W = 240
local PICK = 20

local TICK_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TICK_NOT = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local card

---------------------------------------------------------------------------
-- Small lookups
---------------------------------------------------------------------------
local function ClassColour(class)
    local colours = RAID_CLASS_COLORS
    local entry = colours and class and colours[class]
    if not entry then return C.text end
    return { entry.r, entry.g, entry.b }
end

local function SpecName(class, specID)
    if not (class and specID and ns.Specs) then return nil end
    local list = ns.Specs.Table()
    local specs = list and list[class]
    if not specs then return nil end
    for _, spec in pairs(specs) do
        if spec.id == specID then return spec.name end
    end
    return nil
end

-- THE PERSON, NOT THE SEAT. Unit tokens reshuffle when the roster
-- changes: party3 is somebody else after one leaver. The guid taken at
-- click time is who this card is about, and every read goes back through
-- it - nil when they are no longer reachable under any token.
local function UnitOfCard()
    if not (card and card.guid) then return nil end
    if card.unit then
        local held = UnitGUID and UnitGUID(card.unit)
        if ns.CanCompute(held) and held == card.guid then
            return card.unit
        end
    end
    for _, member in ipairs(ns.Roster and ns.Roster() or {}) do
        local held = UnitGUID and UnitGUID(member.unit)
        if ns.CanCompute(held) and held == card.guid then
            card.unit = member.unit
            return member.unit
        end
    end
    return nil
end

local function ItemIcon(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    return nil
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function BuildSlotRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    if index % 2 == 0 then
        UI.Fill(row, "BACKGROUND", C.rowAlt or C.control, 0.35)
    end

    row.slotName = UI.Label(row, "", UI.FS.meta, C.textFaint)
    row.slotName:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slotName:SetWidth(86)
    row.slotName:SetJustifyH("LEFT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 90, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.item = UI.Label(row, "", UI.FS.meta, C.textBody)
    row.item:SetPoint("LEFT", row, "LEFT", 114, 0)
    row.item:SetPoint("RIGHT", row, "RIGHT", -74, 0)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)

    row.level = UI.Label(row, "", UI.FS.meta, C.textBody)
    row.level:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    row.level:SetWidth(40)
    row.level:SetJustifyH("RIGHT")

    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(12, 12)
    row.mark:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    -- The item itself on hover - the game's tooltip already knows how to
    -- say everything about a link, gems and enchant lines included.
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

function PlayerCard.Create()
    if card then return card end

    card = CreateFrame("Frame", "ZwoelfStuffPlayerCard", UIParent)
    card:SetSize(CARD_W, 596)
    card:SetPoint("CENTER", UIParent, "CENTER", 40, 0)
    card:SetFrameStrata("DIALOG")
    card:EnableMouse(true)
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    card:SetClampedToScreen(true)
    card:Hide()

    UI.Fill(card, "BACKGROUND", C.windowBg)
    local edge = ns.CreateBorder(card, 1, "BORDER")
    edge:SetColor(C.overlayEdge[1], C.overlayEdge[2], C.overlayEdge[3], 1)

    card.name = UI.Label(card, "", UI.FS.card, C.text)
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", UI.PAD, -16)

    card.spec = UI.Label(card, "", UI.FS.meta, C.textDim)
    card.spec:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)

    local close = CreateFrame("Button", nil, card)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -UI.PAD, -12)
    local cross = UI.Glyph(close, "ui-close", 12, C.textDim)
    cross:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() card:Hide() end)

    -- The one number a raid leader reads first, where a stat tile would put
    -- it: big, right, beside the close.
    card.level = UI.Label(card, "", UI.FS.card, C.text)
    card.level:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(UI.PAD + 30), -16)
    card.levelCaption = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.levelCaption:SetPoint("TOPRIGHT", card.level, "BOTTOMRIGHT", 0, -2)

    local rule = card:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.separator[1], C.separator[2], C.separator[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -62)
    rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -62)

    card.rows = {}
    local y = -70
    for index, entry in ipairs(ns.Gear.SLOTS) do
        local row = BuildSlotRow(card, index)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", UI.PAD, y)
        row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -UI.PAD, y)
        row.slot = entry
        card.rows[index] = row
        y = y - ROW_H
    end

    -- The reading line sits over the rows and speaks while they are empty.
    card.state = UI.Hint(card, "")
    card.state:SetPoint("TOP", card, "TOP", 0, y / 2 - 35)

    y = y - 10
    card.talentTitle = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.talentTitle:SetPoint("TOPLEFT", card, "TOPLEFT", UI.PAD, y)

    card.hero = UI.Label(card, "", UI.FS.meta, C.textBody)
    card.hero:SetPoint("TOPRIGHT", card, "TOPRIGHT", -UI.PAD, y)

    y = y - 20
    card.loadout = UI.Input(card, CARD_W - UI.PAD * 2, function() end)
    card.loadout:SetPoint("TOPLEFT", card, "TOPLEFT", UI.PAD, y)
    -- A talent string is far past the input's forty-letter default, and
    -- clicking in should hand over the whole thing, not a cursor.
    card.loadout.input:SetMaxLetters(0)
    card.loadout.input:HookScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- The box is a handover, not a form: typing into it changes nobody's
    -- talents, so what was read is put back on every keystroke.
    card.loadout.input:SetScript("OnTextChanged", function(self)
        if card.loadoutText and self:GetText() ~= card.loadoutText then
            self:SetText(card.loadoutText)
            self:HighlightText()
        end
        card.loadout.UpdateGhost()
    end)

    card.copyHint = UI.Label(card, "", UI.FS.meta, C.textFaint)
    card.copyHint:SetPoint("TOPLEFT", card.loadout, "BOTTOMLEFT", 0, -6)

    -- THE SKILLUNG, DOCKED. Owner, 2026-08-24: "rechts neben dem gear
    -- fenster direkt das skill fenster andocken, damit man direkt die
    -- skillung sieht" - "nicht nur den string". Drawn from the same answer
    -- the string comes from: every chosen talent at its place on the
    -- board, the shared class-and-spec tree on top, the hero tree under
    -- its name. Only what is CHOSEN is drawn - the shape of the build is
    -- what a glance needs, not the game's whole window. A child of the
    -- card, so it moves, hides and closes with it.
    local skills = CreateFrame("Frame", nil, card)
    skills:SetPoint("TOPLEFT", card, "TOPRIGHT", 2, 0)
    skills:SetSize(PANEL_W, 596)
    UI.Fill(skills, "BACKGROUND", C.windowBg)
    local skillsEdge = ns.CreateBorder(skills, 1, "BORDER")
    skillsEdge:SetColor(C.overlayEdge[1], C.overlayEdge[2],
        C.overlayEdge[3], 1)
    skills.title = UI.Label(skills, "", UI.FS.card, C.text)
    skills.title:SetPoint("TOPLEFT", skills, "TOPLEFT", 12, -12)
    skills.hero = UI.Label(skills, "", UI.FS.meta, C.textDim)
    skills.hero:SetPoint("TOPLEFT", skills, "TOPLEFT", 12, -424)
    skills.icons = {}
    skills:Hide()
    card.skills = skills

    local refresh = UI.Button(card, ns.L["Refresh"], nil, function()
        -- Through the guid, not the remembered token: after a roster
        -- shuffle the token is somebody else, and forgetting THAT
        -- person's gear would spend the inspect queue on the wrong
        -- player while this card waits forever.
        local unit = UnitOfCard()
        if unit and ns.Gear then
            ns.Gear.Refresh(unit)
            PlayerCard.Redraw()
        end
    end)
    refresh:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -UI.PAD, 12)
    card.refresh = refresh

    table.insert(UISpecialFrames, "ZwoelfStuffPlayerCard")
    return card
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function BuildPick(parent)
    local pick = CreateFrame("Frame", nil, parent)
    pick:SetSize(PICK, PICK)
    local tex = pick:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(pick)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pick.tex = tex
    pick.rank = UI.Label(pick, "", 10, C.text)
    pick.rank:SetPoint("BOTTOMRIGHT", pick, "BOTTOMRIGHT", 2, -2)
    pick:EnableMouse(true)
    pick:SetScript("OnEnter", function(self)
        if not self.spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pick
end

-- One board, scaled into its rectangle. The picks keep their RELATIVE
-- places - the trait tree's own coordinates, normalized over what is
-- chosen - so the class half, the spec half and the middle gap appear by
-- themselves without this code knowing which node is which.
local function PlaceBoard(skills, picks, hero, top, height, used)
    local subset = {}
    for _, pick in ipairs(picks) do
        if (pick.hero == true) == hero then subset[#subset + 1] = pick end
    end
    if #subset == 0 then return used end

    local minX, maxX, minY, maxY
    for _, pick in ipairs(subset) do
        if minX == nil or pick.x < minX then minX = pick.x end
        if maxX == nil or pick.x > maxX then maxX = pick.x end
        if minY == nil or pick.y < minY then minY = pick.y end
        if maxY == nil or pick.y > maxY then maxY = pick.y end
    end

    local width = PANEL_W - 16 - PICK
    local room = height - PICK
    for _, pick in ipairs(subset) do
        used = used + 1
        local icon = skills.icons[used]
        if not icon then
            icon = BuildPick(skills)
            skills.icons[used] = icon
        end
        local fx = (maxX > minX) and (pick.x - minX) / (maxX - minX) or 0.5
        local fy = (maxY > minY) and (pick.y - minY) / (maxY - minY) or 0.5
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", skills, "TOPLEFT",
            8 + fx * width, -(top + fy * room))
        icon.spell = pick.spell
        local texture
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, art = pcall(C_Spell.GetSpellTexture, pick.spell)
            if ok then texture = art end
        end
        icon.tex:SetTexture(texture)
        icon.rank:SetText((pick.most or 1) > 1
            and tostring(pick.rank or 1) or "")
        icon:Show()
    end
    return used
end

local function PaintBuild(data)
    local skills = card.skills
    if not skills then return end
    local picks = data and data.build
    if not picks then
        skills:Hide()
        return
    end
    skills:Show()
    skills.title:SetText(ns.L["Talents"])
    skills.hero:SetText(data.hero or "")
    local used = 0
    used = PlaceBoard(skills, picks, false, 40, 350, used)
    used = PlaceBoard(skills, picks, true, 448, 120, used)
    for index = used + 1, #skills.icons do skills.icons[index]:Hide() end
end

function PlayerCard.Redraw()
    if not (card and card:IsShown()) then return end

    local L = ns.L
    local colour = ClassColour(card.class)
    card.name:SetText(card.memberName or "")
    card.name:SetTextColor(colour[1], colour[2], colour[3])
    card.levelCaption:SetText(L["Item level"])
    card.talentTitle:SetText(L["Talents"])

    local guid = card.guid
    local data = guid and ns.Gear and ns.Gear.Of(guid) or nil

    local unit = UnitOfCard()
    local specID = ns.Specs and unit and ns.Specs.Of(unit) or nil
    local spec = SpecName(card.class, specID)
    card.spec:SetText(spec or "")

    card.level:SetText(data and data.ilvl and tostring(data.ilvl) or "-")

    for _, row in ipairs(card.rows) do
        local facts = data and data.slots and data.slots[row.slot.id] or nil
        row.slotName:SetText(ns.Gear.SlotLabel(row.slot))
        row.link = facts and facts.link or nil
        row.icon:SetTexture(facts and ItemIcon(facts.item) or nil)
        row.item:SetText(facts and facts.link or (data and "-" or ""))
        row.level:SetText(facts and facts.ilvl
            and tostring(math.floor(facts.ilvl + 0.5)) or "")

        -- The mark only where an enchant is DUE: a missing head enchant
        -- is a cross, a back that takes none this season stays unmarked.
        row.mark:Hide()
        if facts then
            local due = ns.Gear.ENCHANTABLE[row.slot.id]
                or (row.slot.id == 17
                    and ns.Gear.OffhandWantsEnchant(facts.link))
            if due then
                row.mark:SetTexture(facts.enchanted and TICK_READY
                    or TICK_NOT)
                row.mark:Show()
            end
        end
    end

    card.hero:SetText(data and data.hero or "")
    card.loadoutText = data and data.loadout or ""
    card.loadout:SetText(card.loadoutText)
    card.loadout:SetShown(card.loadoutText ~= "")
    card.copyHint:SetShown(card.loadoutText ~= "")
    card.copyHint:SetText(L["Click the string, then Ctrl-C. The talent window imports it."])

    if data then
        card.state:SetText("")
        card.state:Hide()
    else
        card.state:SetText(L["Reading. If nothing arrives, they are out of range."])
        card.state:Show()
    end

    PaintBuild(data)
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function PlayerCard.Show(member)
    if not (member and member.unit) then return false end
    local guid = UnitGUID and UnitGUID(member.unit)
    if not ns.CanCompute(guid) then return false end

    PlayerCard.Create()
    card.unit = member.unit
    card.guid = guid
    card.class = member.class
    card.memberName = member.name

    if ns.Gear then ns.Gear.Want(member.unit) end
    if ns.Specs then ns.Specs.Want(member.unit) end

    card:Show()
    PlayerCard.Redraw()
    return true
end

function PlayerCard.Hide()
    if card then card:Hide() end
end

function PlayerCard.IsShown()
    return card and card:IsShown() and true or false
end

function PlayerCard.Frame() return card end

-- An answer landing is the moment the card was waiting for - but only the
-- answer about the person it shows.
if ns.Gear and ns.Gear.OnLearned then
    ns.Gear.OnLearned(function(guid)
        if card and card:IsShown() and card.guid == guid then
            PlayerCard.Redraw()
        end
    end)
end
if ns.Specs and ns.Specs.OnLearned then
    ns.Specs.OnLearned(function()
        if card and card:IsShown() then PlayerCard.Redraw() end
    end)
end

-- A ROSTER CHANGE EMPTIES THE INSPECT QUEUE (Specs wipes its wants - the
-- tokens in them just changed meaning). Whoever this open card is still
-- waiting on has to be wanted AGAIN, or its reading line would sit there
-- for good with no request in flight anywhere.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
    if not (card and card:IsShown()) then return end
    local unit = UnitOfCard()
    if unit and ns.Gear and card.guid and not ns.Gear.Of(card.guid) then
        ns.Gear.Want(unit)
    end
    PlayerCard.Redraw()
end)
