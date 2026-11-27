-- Drops.lua: learns which trade goods each mob drops, from corpses you loot yourself. It only reads the loot window
-- you opened (GetNumLootItems / GetLootSlotType / GetLootSlotInfo / GetLootSlotLink / GetLootSourceInfo); it never
-- loots, targets or clicks anything. Every client value goes through the secret guards in Compat.lua: if the mob's
-- GUID or any item in the window is hidden, the whole window is skipped, so a rate is never built from a partial look;
-- every corpse GUID that could still be read is then marked done, so reopening it half-looted can't count it either.
-- No bundled loot database. Rates come from corpses you loot, plus drop strings you import
-- or that other Dwarf Explorer's Bible users in your party or guild share with you.
-- Shared counts are stored apart from your own and added together for display; the list of
-- corpse GUIDs used to avoid double-counting (dropDone) is never shared.
local _, ns = ...
local C, Core, M = ns.Compat, ns.Core, ns.RM
local L = {}
ns.Drops = L

L.MIN_LOOTS = 20        -- a rate is shown only after this many of your own kills of that mob
L.GATHER_WINDOW = 1.5   -- seconds: a loot window this soon after a gathering / opening / pick pocket cast of yours
L.DONE_SIZE = 200       -- corpse GUIDs remembered (across /reload) so a corpse is counted once
local TRADE_GOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local SLOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

local db, combinedCache
local lastCast = nil    -- { at = C.Clock(), kind = "skin" | "open" | "pickpocket" }, from your own UNIT_SPELLCAST_SUCCEEDED
local fromTarget = false   -- the last window read fell back to your dead target (no GetLootSourceInfo answer)

-- Saved data: drops[creatureID][itemID] = { loots = kills counted, seen = kills it dropped in }; kills[creatureID] =
-- corpses counted; names[creatureID] = mob name (learned from your target or the mob tooltip); done = recent GUIDs.
local function invalidateCombined() combinedCache = nil end
function L.InvalidateCombined() invalidateCombined() end

function L.NewShareId()
  local t = (C.Now() or 0) % 4294967296
  local r = (math.random(0, 65535) + (math.floor((C.Clock() or 0) * 1000) % 65536)) % 65536
  return ("%08x%04x"):format(t, r)
end

function L.Attach(d)
  db = d
  db.drops = type(db.drops) == "table" and db.drops or {}
  db.dropKills = type(db.dropKills) == "table" and db.dropKills or {}
  db.mobNames = type(db.mobNames) == "table" and db.mobNames or {}
  db.dropDone = type(db.dropDone) == "table" and db.dropDone or {}
  db.dropShares = type(db.dropShares) == "table" and db.dropShares or {}
  if type(db.dropShareId) ~= "string" or not db.dropShareId:match("^[%w]+$") or #db.dropShareId < 6 or #db.dropShareId > 32 then
    db.dropShareId = L.NewShareId()
  end
  invalidateCombined()
end

function L.SourceId() return db and db.dropShareId end

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
  if counted > 0 then invalidateCombined() end
  return counted
end

-- Your target's name for the mob it is, when the client shows it.
local function learnTargetName(corpses)
  if not (UnitGUID and UnitName) then return end
  local guid = str(UnitGUID("target"))
  local cid = guid and corpses[guid] and L.CreatureID(guid)
  local name = cid and str(UnitName("target"))
  if name then db.mobNames[cid] = name; invalidateCombined() end
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
  local n = L.Record(corpses)
  if n > 0 and ns.DropShare and ns.DropShare.OnPersonalChange then ns.DropShare.OnPersonalChange() end
  return n
end

-- Your own successful casts (registered for "player" only). Only the spells in Data.lootCasts (SpellEffect open
-- lock / skinning / pickpocket, from DB2) count; Auto Shot, Shoot and combat spells don't. A hidden spell ID is
-- ignored rather than guessed.
function L.OnCast(unit, _, spellID)
  if unit ~= "player" or C.IsSecret(spellID) then return end
  local kind = ns.Data and ns.Data.lootCasts and ns.Data.lootCasts[C.SafeNumber(spellID) or -1]
  if kind then lastCast = { at = C.Clock(), kind = kind } end
end

-- Personal snapshot only (what you looted yourself). Used for export and sync; never includes dropDone or imports.
function L.PersonalSnapshot()
  local kills, drops, names = {}, {}, {}
  for cid, n in pairs(db and db.dropKills or {}) do
    if type(cid) == "number" and type(n) == "number" and n > 0 then kills[cid] = n end
  end
  for cid, rec in pairs(db and db.drops or {}) do
    if type(cid) == "number" and type(rec) == "table" then
      for id, e in pairs(rec) do
        if type(id) == "number" and type(e) == "table" and type(e.seen) == "number" and type(e.loots) == "number"
          and e.seen > 0 and e.loots > 0 then
          drops[cid] = drops[cid] or {}
          drops[cid][id] = { loots = e.loots, seen = e.seen }
        end
      end
    end
  end
  for cid, name in pairs(db and db.mobNames or {}) do
    if type(cid) == "number" and type(name) == "string" and name ~= "" then names[cid] = name end
  end
  return { kills = kills, drops = drops, names = names }
end

-- Combined view: your own counts plus every imported or synced source, summed by creature and item.
-- Each source is stored under dropShares[sourceId] and replaced (not added again) when that same
-- source is imported or received later, so pasting one string twice does not double the numbers.
local function addCounts(dstKills, dstDrops, dstNames, src)
  if type(src) ~= "table" then return end
  for cid, n in pairs(src.kills or src.dropKills or {}) do
    if type(cid) == "number" and type(n) == "number" then dstKills[cid] = (dstKills[cid] or 0) + n end
  end
  for cid, rec in pairs(src.drops or {}) do
    if type(cid) == "number" and type(rec) == "table" then
      dstDrops[cid] = dstDrops[cid] or {}
      for id, e in pairs(rec) do
        if type(id) == "number" and type(e) == "table" and type(e.seen) == "number" and type(e.loots) == "number" then
          local cur = dstDrops[cid][id]
          if not cur then dstDrops[cid][id] = { loots = e.loots, seen = e.seen }
          else cur.loots = cur.loots + e.loots; cur.seen = cur.seen + e.seen end
        end
      end
    end
  end
  for cid, name in pairs(src.names or src.mobNames or {}) do
    if type(cid) == "number" and type(name) == "string" and name ~= "" and not dstNames[cid] then dstNames[cid] = name end
  end
end

function L.Combined()
  if combinedCache then return combinedCache end
  local kills, drops, names = {}, {}, {}
  addCounts(kills, drops, names, { kills = db and db.dropKills, drops = db and db.drops, names = db and db.mobNames })
  for _, sh in pairs(db and db.dropShares or {}) do addCounts(kills, drops, names, sh) end
  combinedCache = { kills = kills, drops = drops, names = names }
  return combinedCache
end

L.MAX_SHARES = 50

-- Short name, lower-cased, with any -Realm suffix removed (CHAT_MSG_ADDON senders are Name-Realm).
function L.NormalizeSender(sender)
  if type(sender) ~= "string" or sender == "" then return nil end
  return (sender:match("^([^%-]+)") or sender):lower()
end

local function shareCount()
  local n = 0
  for _ in pairs(db and db.dropShares or {}) do n = n + 1 end
  return n
end

-- Drop the oldest synced snapshots until there is room for one more (cap MAX_SHARES).
local function pruneShares()
  while shareCount() >= L.MAX_SHARES do
    local oldest, oldestAt
    for sid, sh in pairs(db.dropShares) do
      local at = (type(sh) == "table" and sh.at) or 0
      if not oldest or at < oldestAt then oldest, oldestAt = sid, at end
    end
    if not oldest then break end
    db.dropShares[oldest] = nil
  end
end

-- Replace this source's snapshot. Same source + same hash is a no-op (no double count).
-- Never writes dropDone. Returns ok, kind ("added"/"replaced"/"same"/"own"/"empty"/"sender").
-- sender, when given (addon comms), is bound to the source on first receipt; a different
-- sender cannot later overwrite that snapshot.
function L.ApplyShare(sourceId, snap, hash, sender)
  if not db then return false, "not loaded" end
  if type(sourceId) ~= "string" or sourceId == "" then return false, "empty" end
  if sourceId == db.dropShareId then return false, "own" end
  if type(snap) ~= "table" then return false, "empty" end
  local existing = db.dropShares[sourceId]
  if existing and hash and existing.hash == hash then return true, "same" end
  local norm = sender and L.NormalizeSender(sender)
  if norm and existing and existing.sender and existing.sender ~= norm then
    return false, "sender"
  end
  if not existing then pruneShares() end
  local kills, drops, names = {}, {}, {}
  addCounts(kills, drops, names, snap)
  db.dropShares[sourceId] = {
    hash = hash, kills = kills, drops = drops, names = names,
    at = (C.Now and C.Now()) or (C.Clock and C.Clock()) or 0,
    sender = (existing and existing.sender) or norm,
  }
  invalidateCombined()
  return true, existing and "replaced" or "added"
end

function L.MobName(cid)
  if db and db.mobNames[cid] then return db.mobNames[cid] end
  for _, sh in pairs(db and db.dropShares or {}) do
    if sh.names and sh.names[cid] then return sh.names[cid] end
  end
  return "NPC " .. tostring(cid)
end
function L.Kills(cid) local c = L.Combined(); return c.kills[cid] or 0 end
function L.Label(n) return ("from %d kills"):format(n) end
function L.Percent(e) return math.floor(e.seen * 100 / e.loots + 0.5) end

-- Trade goods a mob drops, once MIN_LOOTS combined kills have been counted, most likely first.
function L.RatesFor(cid)
  local out = {}
  local rec = L.Combined().drops[cid]
  for id, e in pairs(rec or {}) do
    if e.loots >= L.MIN_LOOTS and e.seen > 0 then out[#out + 1] = { item = id, loots = e.loots, seen = e.seen } end
  end
  table.sort(out, function(a, b)
    if a.seen * b.loots ~= b.seen * a.loots then return a.seen * b.loots > b.seen * a.loots end
    return a.item < b.item
  end)
  return out
end

-- Mobs that dropped itemID. rows = those with MIN_LOOTS or more combined kills (most likely first); kills = all
-- counted kills of every mob that has dropped it, shown or not (the UI's title counts only rows); learning = how
-- many mobs are still under the threshold.
function L.SourcesOf(itemID)
  local rows, kills, learning = {}, 0, 0
  local all = L.Combined()
  -- Walk every cid that appears in combined drops.
  for cid, rec in pairs(all.drops or {}) do
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
  if name and db.mobNames[cid] ~= name then db.mobNames[cid] = name; invalidateCombined() end
  local kills = L.Kills(cid)
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
