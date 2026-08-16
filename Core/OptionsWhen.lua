---------------------------------------------------------------------------
-- OptionsWhen - the "when to show it" block, built once, used by every page
--
-- ns.Visibility is the one evaluator in the addon for "is this thing on the
-- screen at all": mode, combat, group, target, rested, the six kinds of
-- place, the role, and what "does not apply" looks like. Its EDITOR existed
-- twice - once on the cooldowns page, once on the reminders page, typed out
-- both times - and the third customer (the answer bar, 2026-08-16, asked
-- for on Discord: "display conditions wie beim taunt button") is where a
-- third copy stops being a copy and becomes a builder. One block, one
-- vocabulary, one order of rows; a page hands over WHERE the rule lives and
-- WHAT to repaint, and gets back the rows it built.
--
--   ns.OptionsWhen.Build(grid, {
--       holder = function() return <table carrying .show> end,
--       apply  = function() ... end,     -- repaint the thing on screen
--       title  = "When to show it",      -- optional; nil = no section header
--       anchor = "an-when",              -- optional section key (collapsible)
--       open   = true,                   -- optional; a keyed section opens
--       relevant = function() return bool end,
--                          -- optional; false hides the whole block (a page
--                          -- with nothing selected). The builder is the ONE
--                          -- writer of its rows' relevance - a page must not
--                          -- SetRelevant them itself, or two writers fight.
--   })
--
-- The rule is read without creating and written on the first write - the
-- same promise Store makes: a table that grew an empty `show` by being
-- looked at is a rewrite. Places are seeded FULL on the first tick, because
-- the stored table is a filter and writing only the one key somebody just
-- switched off would hide the thing from five places nobody touched.
---------------------------------------------------------------------------
local _, ns = ...

local OptionsWhen = {}
ns.OptionsWhen = OptionsWhen

-- SEED A "WHERE" OR "ROLES" TABLE FULL, from the vocabulary it filters on.
-- Pure, exported for the self test: the seed has to name every key or the
-- first untick hides everything else.
function OptionsWhen.SeedAll(list)
    local seeded = {}
    for _, entry in ipairs(list or {}) do seeded[entry.key] = true end
    return seeded
end

-- The value a set-of-switches row shows: no stored list means "allowed",
-- and so does a key the list has never heard of. Pure.
function OptionsWhen.Allowed(set, key)
    if type(set) ~= "table" then return true end
    if set[key] == nil then return true end
    return set[key] and true or false
end

function OptionsWhen.Build(grid, opts)
    local UI, L, V = ns.UI, ns.L, ns.Visibility
    opts = opts or {}
    local holder = opts.holder or function() return nil end
    local apply = opts.apply or function() end
    local relevant = opts.relevant

    -- A keyed section starts COLLAPSED unless told otherwise (Grid:Section);
    -- this block is the whole point of the tab it usually sits on, so it
    -- opens by default and a page may say `open = false`.
    if opts.title then
        grid:Section(opts.title, opts.anchor, opts.open ~= false)
    end

    local function Rule(key, fallback)
        return function()
            local cfg = holder()
            local rule = type(cfg) == "table" and cfg.show or nil
            local value = type(rule) == "table" and rule[key] or nil
            if value == nil then return fallback end
            return value
        end
    end

    local function Write(key)
        return function(value)
            local cfg = holder()
            if type(cfg) ~= "table" then return end
            if type(cfg.show) ~= "table" then cfg.show = {} end
            cfg.show[key] = value
            apply()
        end
    end

    local rows = {}
    local mode = Rule("mode", "always")
    rows.mode = UI.Dropdown(grid:FullRow(L["Show"], { controlWidth = 190 }),
        ns.SHOW_MODES, mode, Write("mode"), { apply = apply })

    -- THE ROWS THAT ONLY MEAN ANYTHING UNDER "Only when...". SetRelevant
    -- rather than hidden: a rule row is not a row you might want, it is a
    -- row about a mode you have not chosen.
    local ruleRows = {}
    local function Keep(row)
        if row then ruleRows[#ruleRows + 1] = row end
        return row
    end

    Keep(UI.Dropdown(grid:FullRow(L["Combat"],
        { controlWidth = 190, icon = "cond-combat" }),
        ns.SHOW_COMBAT, Rule("combat", "any"), Write("combat"),
        { apply = apply }))
    Keep(UI.Dropdown(grid:FullRow(L["Group"],
        { controlWidth = 190, icon = "cond-group" }),
        ns.SHOW_GROUP, Rule("group", "any"), Write("group"),
        { apply = apply }))
    Keep(UI.Dropdown(grid:FullRow(L["Target"],
        { controlWidth = 190, icon = "cond-target" }),
        ns.SHOW_TARGET, Rule("target", "any"), Write("target"),
        { apply = apply }))
    Keep(UI.Dropdown(grid:FullRow(L["Rested"],
        { controlWidth = 190, icon = "cond-rested" }),
        ns.SHOW_RESTING, Rule("resting", "any"), Write("resting"),
        { apply = apply }))

    -- ONE SWITCH PER ENTRY for the two set-shaped rules - the places and the
    -- roles. Written as FALSE and never as nil: a missing key reads as
    -- "allowed" (see ns.Visibility's Allows), so unticking one by clearing
    -- the key would silently undo itself.
    local function Switches(list, field)
        for _, entry in ipairs(list) do
            Keep(UI.Toggle(grid:FullRow(entry.text,
                { controlWidth = 124, icon = entry.icon }),
                function()
                    local cfg = holder()
                    local set = type(cfg) == "table" and type(cfg.show) == "table"
                        and cfg.show[field] or nil
                    return OptionsWhen.Allowed(set, entry.key)
                end,
                function(value)
                    local cfg = holder()
                    if type(cfg) ~= "table" then return end
                    if type(cfg.show) ~= "table" then cfg.show = {} end
                    if type(cfg.show[field]) ~= "table" then
                        cfg.show[field] = OptionsWhen.SeedAll(list)
                    end
                    cfg.show[field][entry.key] = value and true or false
                    apply()
                end))
        end
    end
    Switches(ns.SHOW_WHERE, "where")
    Switches(ns.SHOW_ROLES, "roles")

    -- WHAT "DOES NOT APPLY" LOOKS LIKE. Nought is gone; anything above it is
    -- a ghost you can still arrange against. `scale` because the box is
    -- typed into as well as dragged (4.82.0 shipped a row without it).
    Keep(UI.Slider(grid:FullRow(L["Otherwise"], { controlWidth = 124 }), {
        min = 0, max = 1, step = 0.05, scale = 100,
        format = function(value)
            if (value or 0) <= 0 then return L["gone"] end
            return string.format("%d%%", math.floor((value or 0) * 100 + 0.5))
        end,
        get = Rule("hiddenAlpha", 0),
        set = Write("hiddenAlpha"),
        apply = apply,
    }))

    -- WHY IT IS NOT ON SCREEN RIGHT NOW, in the evaluator's own words, so
    -- the panel and the thing can never disagree about which rule won.
    local why = grid:Note("")

    grid.widgets[#grid.widgets + 1] = { Refresh = function()
        local has = (relevant == nil) or (relevant() and true or false)
        local on = has and mode() == "rules"
        rows.mode:SetRelevant(has)
        for _, row in ipairs(ruleRows) do row:SetRelevant(on) end
        local cfg = holder()
        local reason = has and type(cfg) == "table" and V and V:Explain(cfg) or nil
        if not has then
            why:SetText("")
        elseif reason then
            why:SetText("|cffff7a3dRight now:|r " .. reason)
        else
            why:SetText("|cff888888Every rule has to agree. One you have not "
                .. "set cannot be the reason something is missing.|r")
        end
    end }

    rows.rules = ruleRows
    return rows
end
