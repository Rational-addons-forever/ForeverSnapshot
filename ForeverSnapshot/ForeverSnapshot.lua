local addon, Snapshot = ...
local started = GetTime()
local ready = false
local key, hud

-- Missing or protected API values are omitted rather than guessed.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local values = {pcall(fn, ...)}
    if not values[1] then return nil end
    for i = 2, 12 do
        local v = values[i]
        if issecretvalue and issecretvalue(v) then values[i] = nil end
    end
    return unpack(values, 2, 12)
end
local function sum(a, b, c)
    if type(a) ~= "number" then return nil end
    return a + (b or 0) + (c or 0)
end
local function capture(reason)
    local now = time()
    local s = {schemaVersion = 2, capturedAt = now, reason = reason,
        sessionStartedAt = now - math.floor(GetTime() - started),
        secondsSinceReloadOrLogin = math.floor(GetTime() - started)}
    local _, class = safe(UnitClass, "player")
    s.character = {name = safe(UnitName, "player"), realm = safe(GetRealmName),
        guid = safe(UnitGUID, "player"), class = class, level = safe(UnitLevel, "player")}
    local xp, maximum = safe(UnitXP, "player"), safe(UnitXPMax, "player")
    s.xp = {current = xp, maximum = maximum, rested = safe(GetXPExhaustion)}
    if xp and maximum and maximum > 0 then s.xp.percent = 100 * xp / maximum end
    s.location = {zone = safe(GetZoneText), subzone = safe(GetSubZoneText),
        instance = safe(IsInInstance)}
    if C_Map then
        local id = safe(C_Map.GetBestMapForUnit, "player")
        s.location.mapID = id
        local position = id and safe(C_Map.GetPlayerMapPosition, id, "player")
        if position then
            local x, y = safe(position.GetXY, position)
            if x and y then s.location.x, s.location.y = x * 100, y * 100 end
        end
    end
    local stats = {health = safe(UnitHealth, "player"), maxHealth = safe(UnitHealthMax, "player"),
        dodgePercent = safe(GetDodgeChance), parryPercent = safe(GetParryChance),
        blockPercent = safe(GetBlockChance), blockValue = safe(GetShieldBlock),
        critPercent = safe(GetCritChance), attributes = {}, resistances = {}}
    for i, name in ipairs({"strength", "agility", "stamina", "intellect", "spirit"}) do
        local base, effective, positive, negative = safe(UnitStat, "player", i)
        stats.attributes[name] = {base = base, effective = effective, positive = positive, negative = negative}
    end
    local base, effective = safe(UnitArmor, "player")
    stats.baseArmor, stats.armor = base, effective
    local defense, modifier = safe(UnitDefense, "player")
    stats.defenseBase, stats.defenseModifier = defense, modifier
    stats.defense = sum(defense, modifier)
    local ap, pos, neg = safe(UnitAttackPower, "player")
    stats.attackPower = sum(ap, pos, neg)
    local low, high, offLow, offHigh = safe(UnitDamage, "player")
    local speed, offSpeed = safe(UnitAttackSpeed, "player")
    stats.weapon = {minimum = low, maximum = high, speed = speed,
        offhandMinimum = offLow, offhandMaximum = offHigh, offhandSpeed = offSpeed}
    for i, name in ipairs({"holy", "fire", "nature", "frost", "shadow", "arcane"}) do
        local _, total = safe(UnitResistance, "player", i)
        stats.resistances[name] = total
    end
    s.stats = stats
    s.equipment = {}
    for slot = 1, 19 do
        local link = safe(GetInventoryItemLink, "player", slot)
        local id = safe(GetInventoryItemID, "player", slot)
        local current, max = safe(GetInventoryItemDurability, slot)
        local name, quality, itemLevel
        if link then
            local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
            local n, _, q, level = safe(getInfo, link)
            name, quality, itemLevel = n, q, level
        end
        s.equipment[slot] = {itemID = id, link = link, name = name, quality = quality,
            itemLevel = itemLevel, durability = current, maxDurability = max}
    end
    local form = safe(GetShapeshiftForm)
    local formName
    if form and form > 0 then
        local _, _, _, spellID = safe(GetShapeshiftFormInfo, form)
        if C_Spell and spellID then
            local info = safe(C_Spell.GetSpellInfo, spellID)
            formName = info and info.name
        end
        s.stanceSpellID = spellID
    end
    s.stanceIndex, s.stanceName = form, formName
    s.inCombat = safe(UnitAffectingCombat, "player")
    s.buffs = {}
    for i = 1, 40 do
        local b
        if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
            local data = safe(C_UnitAuras.GetBuffDataByIndex, "player", i)
            if not data then break end
            b = {name = data.name, spellID = data.spellId, count = data.applications,
                duration = data.duration, expirationTime = data.expirationTime}
        else
            local name, _, count, _, duration, expiration, _, _, _, spellID = safe(UnitBuff, "player", i)
            if not name then break end
            b = {name = name, spellID = spellID, count = count, duration = duration, expirationTime = expiration}
        end
        s.buffs[#s.buffs + 1] = b
    end
    s.professions = Snapshot.ProfessionSnapshot()
    ForeverSnapshotDB.characters[key] = s
end
local function snapshot(reason)
    if not ready then return end
    local ok, err = pcall(capture, reason)
    if not ok then ForeverSnapshotDB.lastError = {at = time(), message = tostring(err)}
    else ForeverSnapshotDB.lastError = nil end
end
Snapshot.RequestSnapshot = snapshot
local function setupHUD()
    hud = CreateFrame("Frame", "ForeverSnapshotHUD", UIParent)
    hud:SetSize(270, 28)
    local p = ForeverSnapshotDB.position
    if p then hud:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else hud:SetPoint("TOP", UIParent, "TOP", 0, -65) end
    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) self:StartMoving() end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        ForeverSnapshotDB.position = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    local background = hud:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.65)
    local label = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints()
    hud:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Forever Snapshot")
        GameTooltip:AddLine("Time since this UI loaded, including login.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move. /reload writes fresh data to disk.", 1, 1, 1)
        GameTooltip:Show()
    end)
    hud:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local elapsed = 1
    hud:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        local seconds = math.floor(GetTime() - started)
        label:SetText(string.format("Time since last reload: %02d:%02d:%02d",
            math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60))
    end)
    hud:SetShown(not ForeverSnapshotDB.hidden)
end
local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addon then
        ForeverSnapshotDB = ForeverSnapshotDB or {}
        ForeverSnapshotDB.characters = ForeverSnapshotDB.characters or {}
        key = (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
        ready = true
        setupHUD()
        C_Timer.NewTicker(5, function() snapshot("periodic") end)
    elseif event == "PLAYER_ENTERING_WORLD" then snapshot("enteringWorld")
    elseif event == "PLAYER_LOGOUT" then snapshot("logoutOrReload") end
end)
SLASH_FOREVERSNAPSHOT1 = "/fsnap"
SlashCmdList.FOREVERSNAPSHOT = function(message)
    if not ready then return end
    message = string.lower(message or "")
    if message == "hide" or message == "show" then
        ForeverSnapshotDB.hidden = message == "hide"
        hud:SetShown(not ForeverSnapshotDB.hidden)
    else
        Snapshot.CaptureProfessionRecipes()
        snapshot("manual")
        print("Forever Snapshot: captured in memory. Open each profession to capture its recipes, then /reload to save. /fsnap hide or show toggles the timer.")
    end
end
