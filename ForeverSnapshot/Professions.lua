local _, Snapshot = ...
local state, bookOpen, queued

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function savedState()
    if state then return state end
    local guid = call(UnitGUID, "player")
    if not guid then return nil end
    local newest
    for _, s in pairs(ForeverSnapshotDB and ForeverSnapshotDB.characters or {}) do
        if s.character and s.character.guid == guid and s.professions
            and (not newest or (s.capturedAt or 0) > (newest.capturedAt or 0)) then
            newest = s
        end
    end
    state = newest and newest.professions or {entries = {}, books = {}}
    return state
end

local function readLevels()
    if not GetProfessions or not GetProfessionInfo then return nil, "apiUnavailable" end
    local entries, count = {}, 0
    -- The primary and secondary slots can contain holes.
    for slot, index in pairs({GetProfessions()}) do
        local name, _, rank, cap, _, _, id, modifier = GetProfessionInfo(index)
        if not id or not name or type(rank) ~= "number" or type(cap) ~= "number" then
            return nil, "incompleteRoster"
        end
        entries[id] = {skillLineID = id, name = name, rank = rank, maxRank = cap,
            modifier = modifier, primary = slot <= 2}
        count = count + 1
    end
    -- A transient empty response during loading cannot prove all skills were dropped.
    if count == 0 then return nil, "emptyRoster" end
    return entries
end

function Snapshot.ProfessionSnapshot()
    local s = savedState()
    if not s then return nil end
    local ok, entries, reason = pcall(readLevels)
    s.levelsCheckedAt = time()
    s.levelsAvailable = ok and entries ~= nil
    s.levelsStatus = s.levelsAvailable and "captured" or (ok and reason or "apiError")
    if s.levelsAvailable then
        s.entries, s.levelsCapturedAt = entries, time()
        for id in pairs(s.books) do
            if not entries[id] then s.books[id] = nil end
        end
    end
    return s
end

local function scanBook(s)
    local api = C_TradeSkillUI
    if not api or not api.GetAllRecipeIDs or not api.GetRecipeInfo
        or not api.GetBaseProfessionInfo or not api.IsTradeSkillReady
        or not api.IsTradeSkillLinked or not api.IsTradeSkillGuild
        or not api.IsNPCCrafting then return nil, "apiUnavailable" end
    if not api.IsTradeSkillReady() or (api.IsDataSourceChanging and api.IsDataSourceChanging()) then
        return nil, "notReady"
    end
    if api.IsTradeSkillLinked() or api.IsTradeSkillGuild() or api.IsNPCCrafting() then
        return nil, "notPlayerBook"
    end
    if not s.levelsAvailable then return nil, "rosterUnavailable" end
    local info = api.GetBaseProfessionInfo()
    local id = info and info.professionID
    if not id or not s.entries[id] then return nil, "notCurrentProfession" end
    local ids = api.GetAllRecipeIDs()
    if not ids or #ids == 0 then return nil, "emptyEnumeration" end
    local book = {skillLineID = id, name = s.entries[id].name,
        capturedAt = time(), rankAtCapture = s.entries[id].rank,
        source = "C_TradeSkillUI.GetAllRecipeIDs", enumerationComplete = true,
        scope = "clientEnumeratedRecipes", recipes = {}, learnedCount = 0, unlearnedCount = 0}
    for _, recipeID in ipairs(ids) do
        local recipe = api.GetRecipeInfo(recipeID)
        if not recipe or not recipe.name or type(recipe.learned) ~= "boolean" then
            return nil, "incompleteRecipeInfo"
        end
        local entry = {recipeID = recipeID, name = recipe.name, learned = recipe.learned,
            relativeDifficulty = recipe.relativeDifficulty, canSkillUp = recipe.canSkillUp,
            numSkillUps = recipe.numSkillUps, disabled = recipe.disabled,
            disabledReason = recipe.disabledReason, craftable = recipe.craftable}
        entry.craftableCount = call(api.GetCraftableCount, recipeID)
        entry.itemLink = call(api.GetRecipeItemLink, recipeID)
        -- Recipe ownership must survive a cold reagent/item cache.
        local schematic = call(api.GetRecipeSchematic, recipeID, false)
        if schematic then
            entry.outputItemID = schematic.outputItemID
            entry.quantityMin, entry.quantityMax = schematic.quantityMin, schematic.quantityMax
            if schematic.reagentSlotSchematics then
                entry.reagentSlots = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    local saved = {quantityRequired = slot.quantityRequired, alternatives = {}}
                    for _, reagent in ipairs(slot.reagents or {}) do
                        saved.alternatives[#saved.alternatives + 1] = {
                            itemID = reagent.itemID, currencyID = reagent.currencyID}
                    end
                    entry.reagentSlots[#entry.reagentSlots + 1] = saved
                end
            end
        end
        book.recipes[recipeID] = entry
        if recipe.learned then book.learnedCount = book.learnedCount + 1
        else book.unlearnedCount = book.unlearnedCount + 1 end
    end
    return book, "captured"
end

function Snapshot.CaptureProfessionRecipes()
    if not bookOpen then return end
    local s = Snapshot.ProfessionSnapshot()
    if not s then return end
    local ok, book, reason = pcall(scanBook, s)
    s.lastRecipeScan = {at = time(), status = ok and reason or "apiError"}
    if ok and book then s.books[book.skillLineID] = book end
end

local events = CreateFrame("Frame")
for _, event in ipairs({"SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_CLOSE"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_CLOSE" then bookOpen = false return end
    if event == "TRADE_SKILL_SHOW" then bookOpen = true end
    if event == "TRADE_SKILL_DATA_SOURCE_CHANGING" then return end
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Snapshot.ProfessionSnapshot()
        Snapshot.CaptureProfessionRecipes()
        if Snapshot.RequestSnapshot then Snapshot.RequestSnapshot("professionUpdate") end
    end)
end)
