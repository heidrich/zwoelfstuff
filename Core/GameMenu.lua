---------------------------------------------------------------------------
-- ZwoelfStuff in the game menu (Escape).
--
-- Where people look for an interface addon after the first day. The minimap
-- button and /zs are both faster, and both assume you remember they are
-- there; the pause menu is where you look when you do not.
--
-- APPENDED UNDER THE LAST BUTTON, NEVER INSERTED IN THE MIDDLE.
--
-- Blizzard lays this menu out from a pool and re-anchors every button each
-- time it opens. An entry in the middle means pushing everything below it
-- down by hand on every Layout, on top of the offsets Blizzard has just set -
-- read back with GetPoint and rewritten, every pass, for ever. Appending
-- costs one anchor, moves nothing of Blizzard's, and so has nothing that can
-- get out of step with it.
---------------------------------------------------------------------------
local _, ns = ...

local GameMenu = {}
ns.GameMenu = GameMenu

local LABEL = "|cff7ec6d4Zwoelf|r|cffff7a3dStuff|r"

-- What the menu uses between two entries when it cannot be measured. Only
-- ever reached on a build whose menu is not laid out the way this assumes.
local FALLBACK_GAP = 12

---------------------------------------------------------------------------
-- The arithmetic, separated from the frames
--
-- Both of these are one-liners that are easy to get wrong and impossible to
-- see: pick the wrong two buttons and our entry hangs off the middle of the
-- menu; get the gap backwards and it overlaps the one above it. Neither
-- throws, and both need the pause menu open to look at.
--
-- So they take plain values and are checked by /zs test, which is the lesson
-- the snapping bug taught: a rule that cannot be run is a rule that gets
-- diagnosed by reading, and reading was wrong three times.
---------------------------------------------------------------------------

-- The two lowest of a list, by whatever `bottomOf` says their bottom edge is.
-- Anything it answers nil for is not in the running at all.
function GameMenu.TwoLowest(list, bottomOf)
    local lowest, lowestY, second, secondY

    for _, item in ipairs(list or {}) do
        local y = bottomOf(item)
        if y then
            if not lowestY or y < lowestY then
                second, secondY = lowest, lowestY
                lowest, lowestY = item, y
            elseif not secondY or y < secondY then
                second, secondY = item, y
            end
        end
    end

    return lowest, second
end

-- The space Blizzard leaves between two stacked entries, measured off the two
-- it has just placed. A hard-coded number is right until Blizzard changes its
-- spacing, and then it is wrong in a way nobody ever reports.
function GameMenu.GapBetween(lowerTop, upperBottom)
    if type(lowerTop) ~= "number" or type(upperBottom) ~= "number" then
        return FALLBACK_GAP
    end

    -- Negative or absurd means these two are not stacked the way this assumes
    -- - side by side, or one of them caught mid-animation. The fallback is
    -- then better than arithmetic on a layout we did not understand.
    local gap = upperBottom - lowerTop
    if gap < 0 or gap > 40 then return FALLBACK_GAP end
    return gap
end

-- The two bottom-most buttons Blizzard has just placed: the one to hang ours
-- under, and the one above it, which is what makes the gap measurable.
local function BottomButtons()
    local pool = GameMenuFrame and GameMenuFrame.buttonPool
    if not (pool and pool.EnumerateActive) then return nil end

    local buttons = {}
    for button in pool:EnumerateActive() do
        buttons[#buttons + 1] = button
    end

    return GameMenu.TwoLowest(buttons, function(button)
        return button:IsShown() and button:GetBottom() or nil
    end)
end

-- Where the button goes, run after every one of Blizzard's own layout passes.
function GameMenu:Place()
    local button = self.button
    if not button then return end

    -- STOOD DOWN IN COMBAT. Pressing it closes the pause menu, and closing a
    -- protected panel from addon code during a fight is exactly what gets
    -- blocked - a button that does nothing when pressed is worse than no
    -- button at all. Nothing is resized either, so for as long as the fight
    -- lasts the menu keeps Blizzard's own height.
    -- ns.db checked as well: this runs from a hook Blizzard calls, and a
    -- throw in there lands in the pause menu rather than in ours.
    if InCombatLockdown() or not ns.db or ns.db.gameMenu == false then
        button:Hide()
        return
    end

    local lowest, second = BottomButtons()
    if not lowest then
        button:Hide()
        return
    end

    -- Blizzard's own size, whatever it happens to be on this build. Ours
    -- being four pixels narrower than the rest is the sort of thing that
    -- makes an addon look bolted on.
    local width, height = lowest:GetWidth(), lowest:GetHeight()
    if not (width and height and width > 0 and height > 0) then
        button:Hide()
        return
    end

    local gap = GameMenu.GapBetween(lowest:GetTop(),
        second and second:GetBottom() or nil)

    -- THE NEIGHBOUR'S OWN FONT, read each time rather than chosen once.
    --
    -- This menu is skinned by half the interface suites people run, and a
    -- skin changes the font on Blizzard's pooled buttons without telling
    -- anybody. Borrowing it is the only way our line reads as one of the menu
    -- entries instead of as an addon that turned up. Our own panel font is
    -- the fallback, for a build where the label cannot be reached.
    local neighbour = lowest.GetFontString and lowest:GetFontString()
    local path, size, flags = nil, nil, nil
    if neighbour then path, size, flags = neighbour:GetFont() end
    -- The size as well as the path: SetFont with a nil size is an error, not
    -- a default, and this is reading a font off somebody else's font string.
    if path and type(size) == "number" then
        button.label:SetFont(path, size, flags or "")
    end

    button:SetSize(width, height)
    button:ClearAllPoints()
    button:SetPoint("TOP", lowest, "BOTTOM", 0, -gap)
    button:Show()

    -- And the frame grows to hold it. Read fresh rather than remembered:
    -- Layout has just worked out the natural height and this runs after it,
    -- so the number is correct even on the day the menu has one entry fewer.
    GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + height + gap)
end

function GameMenu:Create()
    if self.button then return end
    if not (GameMenuFrame and GameMenuFrame.Layout) then return end

    -- NO TEMPLATE. MainMenuFrameButtonTemplate brings its own artwork, and
    -- that artwork is a red plate - Blizzard's menu does not look like that
    -- because every button in it is restyled, by Blizzard's own code or by
    -- whichever skin is running. Ours is not in that pool and never will be,
    -- so it came out as the raw template: a red slab among grey entries.
    --
    -- A bare frame carries no artwork to be left over. What is left is the
    -- word, in the menu's own font, on the menu's own ground - which is what
    -- the other entries look like whatever is skinning them.
    local button = CreateFrame("Button", "ZwoelfStuffGameMenuButton",
        GameMenuFrame)
    -- Hidden until a layout pass has placed it, so it never appears for one
    -- frame in the corner it was created in.
    button:Hide()

    button.label = button:CreateFontString(nil, "OVERLAY")
    button.label:SetPoint("CENTER")
    button.label:SetText(LABEL)
    -- Until the first Place borrows the neighbour's font. A font string with
    -- no font at all draws nothing, so this is not a nicety.
    ns.StyleUIFont(button.label, 14)

    -- The one thing a bare frame does lose: any sign that it can be pressed.
    -- A faint lift on hover rather than a border or a plate - enough to say
    -- the row is live, not enough to be a style of its own.
    local hover = button:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(button)
    hover:SetColorTexture(1, 1, 1, 0.07)
    hover:Hide()

    button:SetScript("OnEnter", function() hover:Show() end)
    button:SetScript("OnLeave", function() hover:Hide() end)

    button:SetScript("OnClick", function()
        HideUIPanel(GameMenuFrame)
        ns.Options:Toggle()
    end)

    self.button = button

    -- A RE-ENTRY GUARD RATHER THAN A REMEMBERED HEIGHT.
    --
    -- Setting the height can make the frame lay itself out again, and reading
    -- GetHeight on that second pass would return the height we just set -
    -- every open a little taller than the last. Remembering the first height
    -- instead is the other way to stop that, and it goes wrong the day the
    -- menu has one button fewer than it had at login.
    local adjusting = false

    hooksecurefunc(GameMenuFrame, "Layout", function()
        if adjusting then return end
        adjusting = true
        GameMenu:Place()
        adjusting = false
    end)
end

-- The setting, from the options panel. Applied at once rather than at the
-- next open: the menu is very likely shut right now, but "I unticked it and
-- nothing happened" is a bug report either way.
function GameMenu:SetShown(shown)
    ns.db.gameMenu = shown and true or false
    if self.button and GameMenuFrame and GameMenuFrame:IsShown() then
        self:Place()
    elseif self.button and not ns.db.gameMenu then
        self.button:Hide()
    end
end
