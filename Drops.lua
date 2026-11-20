-- Drops.lua: learns which trade goods each mob drops, from corpses you loot yourself. It only reads the loot window
-- you opened (GetNumLootItems / GetLootSlotType / GetLootSlotInfo / GetLootSlotLink / GetLootSourceInfo); it never
-- loots, targets or clicks anything. Every client value goes through the secret guards in Compat.lua: if the mob's
-- GUID or any item in the window is hidden, the whole window is skipped, so a rate is never built from a partial look.
-- No third-party loot data: everything shown comes from your own kills.
local _, ns = ...
local C, Core, M = ns.Compat, ns.Core, ns.RM
local L = {}
ns.Drops = L

L.MIN_LOOTS = 20        -- a rate is shown only after this many of your own kills of that mob
L.GATHER_WINDOW = 1.5   -- seconds: a loot window this soon after one of your casts may be skinning/mining/herbing
L.DONE_SIZE = 200       -- corpse GUIDs remembered (across /reload) so a corpse is counted once
local TRADE_GOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local SLOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

local db
local lastCast = nil

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
  local corpses, why = L.ReadWindow()
  if not corpses then return 0, why end
  if lastCast and C.Clock() - lastCast <= L.GATHER_WINDOW then
    -- Skinning (or mining a corpse) right after a cast of yours: not the kill's loot. Mark the corpse so a
    -- reopened, half-emptied window can't be counted later either.
    for guid in pairs(corpses) do if not isDone(guid) then markDone(guid) end end
    return 0, "gathering"
  end
  learnTargetName(corpses)
  return L.Record(corpses)
end

-- A cast of yours just before a loot window: skinning, mining, herbing or opening, not a kill's loot.
function L.OnCast(unit)
  if C.IsSecret(unit) or unit == "player" then lastCast = C.Clock() end
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
-- kills of every mob that has dropped it; learning = how many mobs are still under the threshold.
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
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "LOOT_OPENED" then
    Core.SafeCall("loot", L.OnLootOpened, arg2)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    L.OnCast(arg1)
  elseif event == "PLAYER_LOGIN" then
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end
  end
end)
