---------------------------------------------------------------------------
-- OptionsCooldowns.lua - the Cooldowns page
--
-- The page the module switch belongs to, and today it answers exactly one
-- question that nothing else in the addon can: WHO IS MANAGING THESE FRAMES.
--
-- NO THIRD COLUMN. There is no list to pick from yet - the spell picker
-- arrives with the bars. When it does, it comes from SpellPane.lua like the
-- reminders' and the death log's do, rather than a third copy.
--
-- WHY THERE IS NO "SWITCH THEIR ADDON OFF" BUTTON. It could be built -
-- C_AddOns.DisableAddOn plus a reload, which is how EllesmereUI's own power
-- button works. It is not built because this addon has never once asked for a
-- reload and has no way of confirming anything, so the first thing either
-- would ever be used for would be turning off somebody ELSE'S addon. Naming
-- it and letting them do it in their own addon list costs them one click and
-- costs us no way to get it wrong.
---------------------------------------------------------------------------
local _, ns = ...

local UI = ns.UI

local Page = {}
ns.OptionsCooldowns = Page

function Page:BuildPage(page, width)
    local L = ns.L
    local grid = UI.Page(page, width)

    ---------------------------------------------------------------------
    -- Who else is doing this
    ---------------------------------------------------------------------
    grid:Section(L["Who is managing your cooldowns"])

    local rivals = ns.Cooldowns and ns.Cooldowns.Rivals
    local others = rivals and rivals.Others() or {}

    if #others > 0 then
        local names = {}
        for index, entry in ipairs(others) do names[index] = entry.label end
        grid:Note(L("Also managing cooldowns on this account: %s.",
            table.concat(names, ", ")))
        grid:Note(L["Blizzard owns these frames and only one addon can hold "
            .. "them. Whichever loads second finds them already taken, and "
            .. "what you get on screen depends on the order they happened to "
            .. "load in - which is why this is a choice rather than something "
            .. "either addon can work around. Leave Cooldowns switched off to "
            .. "keep theirs, or switch theirs off in the game's addon list and "
            .. "switch this on."])
    else
        grid:Note(L["Nothing else on this account is managing them."])
    end

    -- HOW IT DECIDED, because a check that reports something surprising and
    -- will not say why is a check people stop believing. It is also the line
    -- that explains why an addon they think of as a cooldown addon is not
    -- listed: it never said so about itself.
    grid:Note(L["Read from what each addon says about itself in its own "
        .. "description, so an addon that manages cooldowns without ever "
        .. "saying so is not found. Addons switched off for this character "
        .. "are not counted."])

    ---------------------------------------------------------------------
    -- What Blizzard's own Cooldown Manager knows
    ---------------------------------------------------------------------
    grid:Section(L["Blizzard's Cooldown Manager"])
    grid:Note(L["Everything here comes from Blizzard's Cooldown Manager - it "
        .. "already knows the spells, binds the auras and has the timing, "
        .. "none of which an addon can do for itself on this patch. The "
        .. "reminders, the death log and the spell pickers all read it, and "
        .. "they go on doing so whether this module is on or off."])

    grid:Buttons({
        { text = L["What it holds"], onClick = function()
            ns.CDM:Dump()
        end },
    })

    return grid
end
