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
            .. "keep theirs, or switch theirs off and switch this on."])

        -----------------------------------------------------------------
        -- ONE BUTTON PER ADDON, AND IT ASKS TWICE
        --
        -- Owner, 2026-08-15: "einen button einbauen, das man andere cdm
        -- abstellt, das kann elle ui auch."
        --
        -- Two steps, disarming itself after four seconds - the same pattern
        -- as deleting a profile, which is the other place in this addon
        -- where one click does something you cannot take back in the same
        -- second. It reloads the interface, and a reload nobody expected is
        -- indistinguishable from a crash.
        --
        -- One button per addon rather than one for all of them. Two names on
        -- one button is a press whose consequences the label cannot state.
        -----------------------------------------------------------------
        -- KEPT ON THE PAGE, so the desk can prove the button was actually
        -- made. Without a handle the only evidence that this branch works is
        -- that building it did not throw - and a `grid:Buttons` that quietly
        -- returned nothing would pass that, then do nothing on click for
        -- everybody who has a conflict, which is the only person who ever
        -- sees this branch at all.
        page.rivalButtons = {}

        for _, entry in ipairs(others) do
            local dependents = ns.Cooldowns.Rivals.Dependents(entry.folder)
            local armed, button = false, nil
            local idle = L("Switch off %s", entry.label)

            local _, made = grid:Buttons({
                {
                    text = idle,
                    onClick = function()
                        local handle = button
                        if not handle then return end
                        if not armed then
                            armed = true
                            handle:SetText(L["Do it and reload?"])
                            -- Disarms itself. A button left sitting on
                            -- "really?" is one somebody clicks on their way
                            -- past a week later.
                            C_Timer.After(4, function()
                                armed = false
                                if handle and handle.SetText then
                                    handle:SetText(idle)
                                end
                            end)
                            return
                        end

                        armed = false
                        handle:SetText(idle)

                        local ok, why = ns.Cooldowns.Rivals.Disable(entry.folder)
                        if not ok then
                            ns.Print("|cffff4040Not switched off|r - "
                                .. (why or "?") .. ".")
                            return
                        end
                        ReloadUI()
                    end,
                },
            })
            button = made
            page.rivalButtons[#page.rivalButtons + 1] = made

            if #dependents > 0 then
                -- THE ONE THING THEIR POWER BUTTON DOES NOT SAY. Disabling
                -- does not cascade: an addon that lists this one as a
                -- dependency just stops loading, silently.
                grid:Note(L("Careful: %s would stop loading as well, because "
                    .. "it needs that addon.", table.concat(dependents, ", ")))
            end
            grid:Note(L["Switches that addon off, switches Cooldowns on here, "
                .. "and reloads. Nothing is deleted - it is the same tick as "
                .. "in the game's own addon list, and putting it back there "
                .. "puts everything back with it."])
        end
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
