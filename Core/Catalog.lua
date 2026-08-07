---------------------------------------------------------------------------
-- Catalog - the browsable spell list, generated from the LIVE CLIENT.
--
-- Nothing in here is a hardcoded spell table. Every ID, name, icon and spec
-- assignment is read out of the running game, for three reasons:
--   * a hardcoded list is wrong the day a patch lands, and silently so
--   * it would only ever cover one class, one spec, one talent build
--   * spell IDs recalled from memory are guesses, and guesses are what this
--     whole addon exists to avoid
--
-- Three sources, in descending order of usefulness:
--
--   1. TALENTS - what you actually have picked right now. Walked through
--      C_Traits from the active config, so it follows every respec.
--   2. SPELLBOOK - every skill line the client knows. The spellbook carries
--      the OTHER specs' lines too (they come back with a non-zero offSpecID),
--      which is what makes a Blood / Frost / Unholy split possible without
--      ever switching spec.
--   3. COOLDOWN MANAGER - Blizzard's own curated data set. These are the
--      auras the engine is guaranteed to have timing for, so they are worth
--      calling out separately.
--
-- Rebuilt on spec change, talent change and spellbook change; cached in
-- between, because walking the trait tree is not free.
---------------------------------------------------------------------------
local _, ns = ...

local Catalog = {}
ns.Catalog = Catalog

Catalog.sections = nil

---------------------------------------------------------------------------
-- Talents: what is picked right now
---------------------------------------------------------------------------

-- Walks the active loadout and returns { [spellID] = true } for every
-- talent the player has actually purchased ranks in.
local function CollectTalents()
    local picked = {}

    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
        return picked
    end

    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then return picked end

    local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or not configInfo or not configInfo.treeIDs then return picked end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and nodes then
            for _, nodeID in ipairs(nodes) do
                local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                -- ranksPurchased is the honest test: a node can be visible,
                -- available and still not chosen.
                if okNode and node and node.ranksPurchased and node.ranksPurchased > 0 then
                    -- activeEntry is the selected choice on a choice node;
                    -- plain nodes only carry entryIDs.
                    local entryID = node.activeEntry and node.activeEntry.entryID
                    if not entryID and node.entryIDs then entryID = node.entryIDs[1] end

                    if entryID then
                        local okEntry, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
                        if okEntry and entry and entry.definitionID then
                            local okDef, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
                            if okDef and def and def.spellID then
                                picked[def.spellID] = true
                            end
                        end
                    end
                end
            end
        end
    end

    return picked
end

---------------------------------------------------------------------------
-- Spellbook: every line, including the specs you are not playing
---------------------------------------------------------------------------
local function SpellEntry(spellID, talented)
    return {
        id       = spellID,
        name     = ns.SpellName(spellID) or ("Spell " .. spellID),
        icon     = ns.SpellTexture(spellID),
        passive  = (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID)) or false,
        talented = talented or false,
    }
end

local function CollectSpellBook(picked, sections, seen)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemType
        and Enum and Enum.SpellBookItemType and Enum.SpellBookSpellBank) then
        return
    end

    local bank = Enum.SpellBookSpellBank.Player
    local okCount, lineCount = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okCount or not lineCount then return end

    for lineIndex = 1, lineCount do
        local okLine, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIndex)
        if okLine and line and line.itemIndexOffset and line.numSpellBookItems
            and line.numSpellBookItems > 0 and not line.shouldHide then

            local entries = {}
            local first, last = line.itemIndexOffset + 1,
                                line.itemIndexOffset + line.numSpellBookItems

            for slot = first, last do
                local okType, itemType, actionID, spellID = pcall(
                    C_SpellBook.GetSpellBookItemType, slot, bank)
                local id = okType and (spellID or actionID) or nil

                if id and itemType == Enum.SpellBookItemType.Spell and not seen[id] then
                    seen[id] = true
                    entries[#entries + 1] = SpellEntry(id, picked[id])
                end
            end

            if #entries > 0 then
                -- offSpecID is 0 (not nil) on the line of the spec you are
                -- currently playing; any other value names an inactive spec.
                local offSpec = line.offSpecID or 0
                sections[#sections + 1] = {
                    key      = "line" .. lineIndex,
                    title    = line.name or ("Line " .. lineIndex),
                    specID   = offSpec ~= 0 and offSpec or nil,
                    isActive = offSpec == 0,
                    entries  = entries,
                }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Cooldown Manager: Blizzard's own curated set
---------------------------------------------------------------------------
local function CollectCooldownViewer(picked, seen)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        return nil
    end

    local entries, added = {}, {}

    -- Categories 0-3: essential, utility, tracked buff, tracked bar.
    for category = 0, 3 do
        local okSet, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if okSet and ids then
            for _, cooldownID in ipairs(ids) do
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if okInfo and info then
                    -- One resolver for the whole addon: it prefers the
                    -- override only when the player actually has it, because
                    -- Blizzard keeps reporting one after the talent is gone.
                    local id = ns.CDM and ns.CDM:InfoSpellID(info)
                        or (info.overrideSpellID or info.spellID)
                    if id and not added[id] then
                        added[id] = true
                        seen[id] = true
                        entries[#entries + 1] = SpellEntry(id, picked[id])
                    end
                end
            end
        end
    end

    if #entries == 0 then return nil end
    return {
        key     = "cdm",
        title   = "Cooldown Manager",
        note    = "Blizzard tracks these itself - timing is guaranteed.",
        entries = entries,
    }
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function SortEntries(entries)
    table.sort(entries, function(a, b)
        -- Talented first: that is what you came to pick from.
        if a.talented ~= b.talented then return a.talented end
        if a.passive ~= b.passive then return b.passive end
        return (a.name or "") < (b.name or "")
    end)
end

function Catalog:Build()
    local picked = CollectTalents()
    local sections, seen = {}, {}

    -- The talent section repeats IDs that also live in the spellbook, on
    -- purpose: "what did I actually pick" is the question people open this
    -- list with. It is built from its own id set, so `seen` stays untouched.
    local talentEntries = {}
    for spellID in pairs(picked) do
        talentEntries[#talentEntries + 1] = SpellEntry(spellID, true)
    end
    if #talentEntries > 0 then
        SortEntries(talentEntries)
        sections[#sections + 1] = {
            key     = "talents",
            title   = "Your talents",
            note    = "Read from your active loadout - follows every respec.",
            entries = talentEntries,
        }
    end

    local cdm = CollectCooldownViewer(picked, seen)
    if cdm then
        SortEntries(cdm.entries)
        sections[#sections + 1] = cdm
    end

    CollectSpellBook(picked, sections, seen)
    for _, section in ipairs(sections) do SortEntries(section.entries) end

    self.sections = sections
    return sections
end

function Catalog:Get()
    if not self.sections then self:Build() end
    return self.sections
end

function Catalog:Invalidate()
    self.sections = nil
end

-- Returns the entries of one section, filtered by a lowercase search string
-- matched against name and spell ID.
function Catalog:Search(section, query)
    if not section then return {} end
    if not query or query == "" then return section.entries end

    query = query:lower()
    local out = {}
    for _, entry in ipairs(section.entries) do
        if entry.name:lower():find(query, 1, true)
            or tostring(entry.id):find(query, 1, true) then
            out[#out + 1] = entry
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Invalidation
--
-- SPELLS_CHANGED fires a lot during login; the catalog is only rebuilt when
-- something actually asks for it, so dropping the cache is cheap.
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
watcher:SetScript("OnEvent", function()
    Catalog:Invalidate()
    if ns.Options and ns.Options.OnCatalogChanged then
        ns.Options:OnCatalogChanged()
    end
end)
