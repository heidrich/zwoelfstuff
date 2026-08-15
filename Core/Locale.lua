---------------------------------------------------------------------------
-- Locale - the addon in the language the player reads.
--
-- Owner, 2026-08-12: "ich moechte das du eine komplette loca einbaust, mit
-- den gaengigen wow sprachen" - and from the day before, the part that decides
-- the SHAPE of this: "das Loca Feature kommt als naechstes! Kein Modul, das
-- ist fest in den settings."
--
-- So this is not a module. It cannot be switched off, it has no page of its
-- own and no boot step: it is one row on the Settings page and a table that is
-- there from the first line of the addon onwards.
--
-- THE KEY IS THE ENGLISH SENTENCE, and that is the whole design.
--
--   UI.Button(frame, L["Not now"], ...)
--
-- rather than L.WELCOME_NOT_NOW. Three things follow from it, and all three
-- are the reason it was chosen over a table of symbols:
--
--   1. A MISSING TRANSLATION IS THE ENGLISH WORD, not a raw key on a button.
--      Every language file may be as incomplete as it is, at any moment,
--      without a single screen breaking. This addon ships nine translations
--      that are not finished; with symbolic keys that would be nine broken
--      screens.
--   2. MIGRATION IS SAFE. Wrapping a string that is already drawn changes
--      nothing until somebody switches language - so the migration can be
--      done a page at a time instead of in one commit that has to be perfect.
--   3. THE SOURCE STAYS READABLE. `L["Set keys"]` says what the button says.
--      `L.EDITMODE_ACTION_1` needs a second file open to read the first.
--
-- WHAT IT COSTS, measured rather than assumed: every language table is
-- resident, because which language to use is decided from the PROFILE and the
-- profile is not open yet when these files load. See Languages.lua, which
-- carries the number.
--
-- ONE RULE FOR EVERY CALLER, and the self test enforces it: never look a
-- string up at FILE SCOPE. At file scope the profile is not open, the answer
-- is always English, and it is then frozen into a table for the session. Look
-- it up where it is drawn - which is where every widget in this addon takes
-- its text anyway.
---------------------------------------------------------------------------
local _, ns = ...

local Locale = {}
ns.Locale = Locale

-- THE LANGUAGES THE CLIENT ITSELF SHIPS IN, and nothing else. A language WoW
-- does not run in is a language nobody can be reading this addon in.
--
-- `native` is the name in that language and not in English: somebody looking
-- for their own language in a list finds "Deutsch", not "German" - which is a
-- word they may not know.
--
-- enGB is deliberately absent. The client answers "enGB" from GetLocale, and
-- it is the same strings as enUS; see Resolve.
Locale.LANGUAGES = {
    { code = "enUS", native = "English" },
    { code = "deDE", native = "Deutsch" },
    { code = "esES", native = "Español" },
    { code = "esMX", native = "Español (AL)" },
    { code = "frFR", native = "Français" },
    { code = "itIT", native = "Italiano" },
    { code = "ptBR", native = "Português" },
    { code = "ruRU", native = "Русский" },
    { code = "koKR", native = "한국어" },
    { code = "zhCN", native = "简体中文" },
    { code = "zhTW", native = "繁體中文" },
}

local known = {}
for _, entry in ipairs(Locale.LANGUAGES) do known[entry.code] = entry end

function Locale.Known(code) return known[code] end

-- Every table, filled by Languages.lua. enUS is the MASTER: its keys are the
-- list of strings this addon localises at all, and the self test holds every
-- other table to it - a key that is not in enUS is a translation of something
-- that is never asked for, which is a typo that shows as English forever.
Locale.TABLES = {}

function Locale.Register(code, table_)
    Locale.TABLES[code] = table_
    return table_
end

---------------------------------------------------------------------------
-- WHICH LANGUAGE
--
-- Pure, and it takes the world rather than reading it, because "the client is
-- French and the profile says German" is not a state a test can arrange in
-- game. Three answers in order of authority:
--
--   the profile   somebody chose. A choice outranks everything, including a
--                 client that disagrees with it.
--   the client    GetLocale, which is what "auto" means.
--   English       the last resort, and never a failure: every key IS its
--                 English string.
---------------------------------------------------------------------------
function Locale.Resolve(chosen, clientLocale)
    if chosen and chosen ~= "auto" and known[chosen] then return chosen end

    -- The British client is the American strings. Blizzard ships one set for
    -- both and so does everybody else.
    if clientLocale == "enGB" then return "enUS" end
    if clientLocale and known[clientLocale] then return clientLocale end

    return "enUS"
end

-- What the profile holds, or "auto" when it has never been asked.
function Locale.Chosen()
    return (ns.db and ns.db.language) or "auto"
end

Locale.active = "enUS"

local activeTable

-- THE TABLE THE LOOKUP READS. Set by Use, and nil for English on purpose:
-- English has no table to consult, because the key IS the English string, so
-- the lookup below falls straight through and costs one comparison.
function Locale:Use(code)
    code = known[code] and code or "enUS"
    self.active = code
    activeTable = (code ~= "enUS") and Locale.TABLES[code] or nil
    return code
end

-- Login, and again whenever the row on the Settings page is changed.
function Locale:Apply()
    return self:Use(Locale.Resolve(Locale.Chosen(),
        GetLocale and GetLocale() or nil))
end

---------------------------------------------------------------------------
-- The lookup
--
-- An unknown key answers ITSELF, which is why nothing can break: the worst
-- outcome of a missing, misspelt or half-finished translation is the English
-- sentence that was already there.
--
-- __newindex throws. A translation belongs in Languages.lua; assigning into L
-- at runtime would put one language's string into every later session of a
-- different one, and it would be found weeks later.
---------------------------------------------------------------------------
ns.L = setmetatable({}, {
    __index = function(_, key)
        if activeTable then
            local hit = activeTable[key]
            -- Empty is treated as absent. A translator leaving a blank line
            -- means "not done", never "this button has no label".
            if type(hit) == "string" and hit ~= "" then return hit end
        end
        return key
    end,

    -- L("%d of %d", a, b) - the same lookup, then string.format. Its own door
    -- rather than string.format(L["..."], ...) everywhere, because a
    -- translation that drops a placeholder would throw inside format and take
    -- the page down with it. Here it is caught and the English one is used.
    __call = function(_, key, ...)
        local text = ns.L[key]
        if select("#", ...) == 0 then return text end
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
        -- The translation is malformed. Say so once, then behave.
        local fallbackOk, fallback = pcall(string.format, key, ...)
        return fallbackOk and fallback or key
    end,

    __newindex = function()
        error("ns.L is read-only - translations belong in Core/Languages.lua", 2)
    end,
})

---------------------------------------------------------------------------
-- HOW FINISHED EACH LANGUAGE IS
--
-- Not decoration. Nine of these tables are incomplete, and a number that says
-- so is the difference between "the addon is broken in French" and "France is
-- at 60% and here is what is left". Pure: it takes the tables as arguments so
-- the self test can hold a made-up pair to it.
---------------------------------------------------------------------------
function Locale.Measure(master, translation)
    local total, done = 0, 0
    for key in pairs(master or {}) do
        total = total + 1
        local hit = translation and translation[key]
        if type(hit) == "string" and hit ~= "" then done = done + 1 end
    end
    return done, total
end

function Locale.Coverage(code)
    if code == "enUS" then
        local master = Locale.TABLES.enUS or {}
        local count = 0
        for _ in pairs(master) do count = count + 1 end
        return count, count
    end
    return Locale.Measure(Locale.TABLES.enUS, Locale.TABLES[code])
end

-- Every key that language has not answered yet, sorted, so the list is the
-- same twice running and can be pasted to a translator.
function Locale.Missing(code)
    local out = {}
    local master, translation = Locale.TABLES.enUS or {}, Locale.TABLES[code]
    for key in pairs(master) do
        local hit = translation and translation[key]
        if type(hit) ~= "string" or hit == "" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- /zs loca
---------------------------------------------------------------------------
function Locale:Dump(which)
    local L = ns.L
    ns.Print("|cffffd100language|r - " .. self.active
        .. " (" .. (Locale.Chosen() == "auto"
            and ("auto, this client is " .. tostring(GetLocale and GetLocale() or "?"))
            or "chosen") .. ")")

    if which and known[which] then
        local missing = Locale.Missing(which)
        local done, total = Locale.Coverage(which)
        ns.Print(string.format("  %s  %d of %d", which, done, total))
        for index = 1, math.min(#missing, 40) do
            ns.Print("    |cff888888" .. missing[index] .. "|r")
        end
        if #missing > 40 then
            ns.Print(string.format("    |cff888888... and %d more|r",
                #missing - 40))
        end
        return
    end

    for _, entry in ipairs(Locale.LANGUAGES) do
        local done, total = Locale.Coverage(entry.code)
        local percent = total > 0 and math.floor(done / total * 100) or 0
        ns.Print(string.format("  %s %s  %d%%  |cff888888%d of %d|r",
            entry.code == self.active and "|cff40ff40>|r" or " ",
            entry.code, percent, done, total))
    end
    ns.Print("  |cff888888" .. L["Missing lines are shown in English."]
        .. "|r")
end
