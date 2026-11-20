-- Drops.lua: learns which trade goods each mob drops, from corpses you loot yourself. It only reads the loot window
-- you opened (GetNumLootItems / GetLootSlotType / GetLootSlotInfo / GetLootSlotLink / GetLootSourceInfo); it never
-- loots, targets or clicks anything. Every client value goes through the secret guards in Compat.lua: if the mob's
-- GUID or any item in the window is hidden, the whole window is skipped, so a rate is never built from a partial look;
-- every corpse GUID that could still be read is then marked done, so reopening it half-looted can't count it either.
-- No third-party loot data: everything shown comes from your own kills.
local _, ns = ...
local C, Core, M = ns.Compat, ns.Core, ns.RM
local L = {}
ns.Drops = L

L.MIN_LOOTS = 20        -- a rate is shown only after this many of your own kills of that mob
L.GATHER_WINDOW = 1.5   -- seconds: a loot window this soon after a gathering / opening / pick pocket cast of yours
L.DONE_SIZE = 200       -- corpse GUIDs remembered (across /reload) so a corpse is counted once
local TRADE_GOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local SLOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

local db
local lastCast = nil    -- { at = C.Clock(), kind = "skin" | "open" | "pickpocket" }, from your own UNIT_SPELLCAST_SUCCEEDED
local fromTarget = false   -- the last window read fell back to your dead target (no GetLootSourceInfo answer)

-- Saved data: drops[creatureID][itemID] = { loots = kills counted, seen = kills it dropped in }; kills[creatureID] =
-- corpses counted; names[creatureID] = mob name (learned from your target or the mob tooltip); done = recent GUIDs.
function L.Attach(d)
  db = d
  db.drops = type(db.drops) == "table" and db.drops or {}
  db.dropKills = type(db.dropKills) == "table" and db.dropKills or {}
  db.mobNames = type(db.mobNames) == "table" and db.mobNames or {}
  db.dropDone = type(db.dropDone) == "table" and db.dropDone or {}
end

local function str(v)
  v = C.Safe(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

-- npcID from a creature GUID ("Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"). Players, pets, vehicles,
-- game objects and items return nil: they aren't mobs.
function L.CreatureID(guid)
  guid = str(guid)
  if not guid then return nil end
  local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
  if kind ~= "Creature" then return nil end
  return tonumber(npc)
end

local function isDone(guid)
  for _, g in ipairs(db.dropDone) do if g == guid then return true end end
  return false
end

local function markDone(guid)
  local list = db.dropDone
  list[#list + 1] = guid
  while #list > L.DONE_SIZE do table.remove(list, 1) end
end

-- Corpse GUIDs one slot came from. Returns a list, or false when the client hid any of it.
local function slotSources(slot)
  if GetLootSourceInfo then
    local raw = { GetLootSourceInfo(slot) }
    local out = {}
    for i = 1, #raw, 2 do
      local guid = raw[i]
      if C.IsSecret(guid) or C.IsSecret(raw[i + 1]) then return false end
      guid = str(guid)
      if not guid then return false end
      out[#out + 1] = guid
    end
    if #out > 0 then return out end
  end
  -- Client without GetLootSourceInfo (or no answer): the dead mob you're targeting.
  fromTarget = true
  local dead = UnitIsDead and C.Safe(UnitIsDead("target"))
  local guid = UnitGUID and UnitGUID("target")
  if C.IsSecret(guid) then return false end
  guid = str(guid)
  if guid and dead == true then return { guid } end
  return false
end

-- Reads the open loot window. Returns { [guid] = { [itemID] = true } } (trade goods only, every corpse in the window,
-- including ones with no trade goods), or nil and why it was skipped.
function L.ReadWindow()
  if not (GetNumLootItems and GetLootSlotInfo and GetLootSlotLink) then return nil, "no loot API" end
  fromTarget = false
  local n = GetNumLootItems()
  if C.IsSecret(n) then return nil, "hidden" end
  n = C.SafeNumber(n)
  if not n or n <= 0 then return nil, "empty" end
  local corpses = {}
  for slot = 1, n do
    local kind = GetLootSlotType and GetLootSlotType(slot)
    if C.IsSecret(kind) then return nil, "hidden" end
    local _, name, quantity = GetLootSlotInfo(slot)
    if C.IsSecret(name) or C.IsSecret(quantity) then return nil, "hidden" end
    local srcs = slotSources(slot)
    if not srcs then return nil, "hidden source" end
    for _, g in ipairs(srcs) do corpses[g] = corpses[g] or {} end
    if kind == nil or kind == SLOT_ITEM then
      local link = GetLootSlotLink(slot)
      if C.IsSecret(link) then return nil, "hidden" end
      link = str(link)
      local id = link and tonumber(link:match("item:(%d+)"))
      if kind == SLOT_ITEM and not id then return nil, "hidden item" end
      if id then
        local classID = C.GetItemClass(id)
        if not classID then return nil, "hidden item" end
        if classID == TRADE_GOODS then
          for _, g in ipairs(srcs) do corpses[g][id] = true end
        end
      end
    end
  end
  return corpses
end

-- Every corpse GUID in the open window that the client lets us read (used to retire a window we had to skip).
-- The dead-target fallback is used only when the client can't name the window's sources, and not right after an
-- Opening-type cast (that window is a chest or a node; the target's corpse is still unlooted).
function L.ReadableCorpses(recent)
  local out = {}
  local n = GetNumLootItems and C.SafeNumber(GetNumLootItems()) or 0
  if GetLootSourceInfo then
    for slot = 1, n do
      local raw = { GetLootSourceInfo(slot) }
      for i = 1, #raw, 2 do
        local guid = str(raw[i])
        if guid and L.CreatureID(guid) then out[guid] = true end
      end
    end
  end
  if next(out) == nil and recent ~= "open" then
    local guid = UnitGUID and str(UnitGUID("target"))
    if guid and UnitIsDead and C.Safe(UnitIsDead("target")) == true and L.CreatureID(guid) then out[guid] = true end
  end
  return out
end

-- Marks corpses done without counting them. Only creature GUIDs (never chests or players).
local function retire(guids)
  for guid in pairs(guids) do
    if L.CreatureID(guid) and not isDone(guid) then markDone(guid) end
  end
end

-- Counts each creature corpse once. A newly seen item starts at the mob's kill count: those earlier corpses were
-- read in full and didn't have it.
function L.Record(corpses)
  local counted = 0
  for guid, items in pairs(corpses) do
    local cid = L.CreatureID(guid)
    if cid and not isDone(guid) then
      markDone(guid)
      local kills = (db.dropKills[cid] or 0) + 1
      db.dropKills[cid] = kills
      local rec = db.drops[cid] or {}
      db.drops[cid] = rec
      for _, e in pairs(rec) do e.loots = e.loots + 1 end
      for id in pairs(items) do
        if not rec[id] then rec[id] = { loots = kills, seen = 0 } end
        rec[id].seen = rec[id].seen + 1
      end
      counted = counted + 1
    end
  end
  return counted
end

-- Your target's name for the mob it is, when the client shows it.
local function learnTargetName(corpses)
  if not (UnitGUID and UnitName) then return end
  local guid = str(UnitGUID("target"))
  local cid = guid and corpses[guid] and L.CreatureID(guid)
  local name = cid and str(UnitName("target"))
  if name then db.mobNames[cid] = name end
end

function L.OnLootOpened(isFromItem)
  if not db then return 0, "not loaded" end
  if C.Safe(isFromItem) ~= false and isFromItem ~= nil then return 0, "item" end
  if IsFishingLoot then
    local fishing = IsFishingLoot()
    if C.IsSecret(fishing) or fishing then return 0, "fishing" end
  end
  local recent = lastCast and C.Clock() - lastCast.at <= L.GATHER_WINDOW and lastCast.kind
  -- Pick Pocket: the mob is still alive, so leave it unmarked and count its corpse when you kill and loot it.
  if recent == "pickpocket" then return 0, "pick pocket" end
  local corpses, why = L.ReadWindow()
  if not corpses then
    if why ~= "empty" and why ~= "no loot API" then retire(L.ReadableCorpses(recent)) end
    return 0, why
  end
  if recent == "skin" or recent == "open" then
    -- Skinning (or herbs / ore from a corpse) or an Opening-type cast right after your cast: not the kill's loot.
    -- Retire the corpses the window names, so a reopened, half-emptied window can't be counted later. When the
    -- corpse is only your dead target (no source info), retire it only after a skinning-type cast: after Opening the
    -- window is a chest or node and the target's own loot is still to come.
    if not fromTarget or recent == "skin" then retire(corpses) end
    return 0, "gathering"
  end
  learnTargetName(corpses)
  return L.Record(corpses)
end

-- Your own successful casts (registered for "player" only). Only the spells in Data.lootCasts (SpellEffect open
-- lock / skinning / pickpocket, from DB2) count; Auto Shot, Shoot and combat spells don't. A hidden spell ID is
-- ignored rather than guessed.
function L.OnCast(unit, _, spellID)
  if unit ~= "player" or C.IsSecret(spellID) then return end
  local kind = ns.Data and ns.Data.lootCasts and ns.Data.lootCasts[C.SafeNumber(spellID) or -1]
  if kind then lastCast = { at = C.Clock(), kind = kind } end
end

function L.MobName(cid) return (db and db.mobNames[cid]) or ("NPC " .. tostring(cid)) end
function L.Kills(cid) return db and db.dropKills[cid] or 0 end
function L.Label(n) return ("from your %d kills"):format(n) end
function L.Percent(e) return math.floor(e.seen * 100 / e.loots + 0.5) end

-- Trade goods a mob drops, once you've counted MIN_LOOTS of its corpses, most likely first.
function L.RatesFor(cid)
  local out = {}
  local rec = db and db.drops[cid]
  for id, e in pairs(rec or {}) do
    if e.loots >= L.MIN_LOOTS and e.seen > 0 then out[#out + 1] = { item = id, loots = e.loots, seen = e.seen } end
  end
  table.sort(out, function(a, b)
    if a.seen * b.loots ~= b.seen * a.loots then return a.seen * b.loots > b.seen * a.loots end
    return a.item < b.item
  end)
  return out
end

-- Mobs that dropped itemID. rows = those with MIN_LOOTS or more kills (most likely first); kills = all your counted
-- kills of every mob that has dropped it, shown or not (the UI's title counts only rows); learning = how many mobs
-- are still under the threshold.
function L.SourcesOf(itemID)
  local rows, kills, learning = {}, 0, 0
  for cid, rec in pairs(db and db.drops or {}) do
    local e = rec[itemID]
    if e and e.seen > 0 then
      kills = kills + e.loots
      if e.loots >= L.MIN_LOOTS then rows[#rows + 1] = { cid = cid, loots = e.loots, seen = e.seen }
      else learning = learning + 1 end
    end
  end
  table.sort(rows, function(a, b)
    if a.seen * b.loots ~= b.seen * a.loots then return a.seen * b.loots > b.seen * a.loots end
    return a.cid < b.cid
  end)
  return { rows = rows, kills = kills, learning = learning }
end

-- Mob tooltip: one line per trade good it drops, once you've counted enough of its corpses.
function L.AddUnitLines(tooltip, guid, name)
  local cid = L.CreatureID(guid)
  if not cid or not db then return end
  name = str(name)
  if name then db.mobNames[cid] = name end
  local kills = db.dropKills[cid] or 0
  if kills > 0 and kills < L.MIN_LOOTS then
    -- Mist (BCD3E6), the style table's idle text colour.
    tooltip:AddLine(("Learning drops: %d of %d kills"):format(kills, L.MIN_LOOTS), 0.74, 0.83, 0.90)
    return
  end
  local rates = L.RatesFor(cid)
  if #rates == 0 then return end
  tooltip:AddLine("Trade goods (Dwarf Explorer's Bible, " .. L.Label(rates[1].loots) .. "):", 0.4, 0.8, 1)
  for i = 1, math.min(#rates, 6) do
    local e = rates[i]
    tooltip:AddDoubleLine("  " .. M.Name(e.item), L.Percent(e) .. "%", 1, 1, 1, 1, 1, 1)
  end
end

local function OnUnitTooltip(tooltip, data)
  if not db or not data or tooltip ~= GameTooltip then return end
  local settings = M.Settings()
  if settings and not settings.tooltip then return end
  local guid = data.guid
  if C.IsSecret(guid) then return end
  local line = type(data.lines) == "table" and data.lines[1]
  Core.SafeCall("unit tooltip", L.AddUnitLines, tooltip, guid, line and line.leftText)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("LOOT_OPENED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
  if event == "LOOT_OPENED" then
    Core.SafeCall("loot", L.OnLootOpened, arg2)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    L.OnCast(arg1, arg2, arg3)
  elseif event == "PLAYER_LOGIN" then
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end
  end
end)
