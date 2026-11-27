-- Where.lua: "Farm here / nearest spot". Where can I get this material, starting with the zone I'm standing in?
-- Built only from what DEB has seen: mobs whose drops you (or Bible users in your party/guild) counted, with the
-- zones they were killed in; nodes you gathered (herb / mine / skin / fish) and the zone you were in; merchants you
-- opened. Zones, their continents and centres come from the client's map tables (Zones.lua, generated); level
-- ranges come from the client at runtime (C_Map.GetMapLevels). No bundled mob, node or coordinate list.
local _, ns = ...
local C = ns.Compat
local W = {}
ns.Where = W
local RM = ns.RM
local db

W.MAX_ZONES = 60          -- zones with gathering sightings kept
W.MAX_PER_ZONE = 60       -- items per zone
W.OTHER_CONTINENT = 30000 -- yards added for a zone on another continent
W.UNKNOWN_ZONE = 60000    -- a zone name the map tables don't have (instance, new area)
W.LEVEL_YARDS = 600       -- each level a zone starts above you counts like this many yards
W.KINDS = { herb = "Herb", mine = "Mine", skin = "Skin", fish = "Fish", mob = "Farm" }

function W.Attach(d)
  db = d
  db.gather = type(db.gather) == "table" and db.gather or {}
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- Record one gathering sighting (yours): item, kind (herb/mine/skin/fish), zone. Bounded per zone and in zones.
function W.Note(itemID, kind, zone, now)
  if not (db and type(itemID) == "number" and W.KINDS[kind] and kind ~= "mob" and type(zone) == "string" and zone ~= "") then return false end
  local z = db.gather[zone]
  if not z then
    if count(db.gather) >= W.MAX_ZONES then
      local oldest, at
      for k, v in pairs(db.gather) do
        local t = 0
        for _, e in pairs(v) do t = math.max(t, e.t or 0) end
        if not oldest or t < at then oldest, at = k, t end
      end
      db.gather[oldest] = nil
    end
    z = {}; db.gather[zone] = z
  end
  local e = z[itemID]
  if not e then
    if count(z) >= W.MAX_PER_ZONE then
      local low, lowN
      for id, v in pairs(z) do if not lowN or (v.n or 0) < lowN then low, lowN = id, v.n or 0 end end
      z[low] = nil
    end
    e = { k = kind, n = 0 }; z[itemID] = e
  end
  e.k, e.n, e.t = kind, (e.n or 0) + 1, now or C.Now()
  if ns.Cache then ns.Cache.Bump() end
  return true
end

-- Crafting materials in the open loot window (after a gathering cast or while fishing). Hidden values skip the window.
function W.LootItems()
  local out = {}
  if not (GetNumLootItems and GetLootSlotLink) then return out end
  local n = C.SafeNumber(GetNumLootItems()) or 0
  for slot = 1, n do
    local link = GetLootSlotLink(slot)
    if C.IsSecret(link) then return {} end
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id and (RM.byReagent[id] or RM.byCamp[id]) then out[#out + 1] = id end
  end
  return out
end

-- Called by Drops.lua when a loot window comes from your own gathering cast or from fishing.
function W.OnGatherLoot(kind)
  local zone = C.GetZone()
  local n = 0
  for _, id in ipairs(W.LootItems()) do if W.Note(id, kind, zone) then n = n + 1 end end
  if n > 0 and ns.ShareData then ns.ShareData.OnPersonalChange() end
  return n
end

-- Your sightings plus shared ones: { [zone] = { [itemID] = { k, n } } } (shared counts added).
function W.AllGather()
  local function build()
    local out = {}
    local function add(zone, id, k, n)
      out[zone] = out[zone] or {}
      local e = out[zone][id]
      if not e then out[zone][id] = { k = k, n = n } else e.n = e.n + n end
    end
    for zone, z in pairs(db and db.gather or {}) do for id, e in pairs(z) do add(zone, id, e.k, e.n or 1) end end
    for _, sh in pairs(db and db.sightShares or {}) do
      for _, g in ipairs(sh.gather or {}) do add(g.zone, g.id, g.k, g.n or 1) end
    end
    return out
  end
  return ns.Cache and ns.Cache.Get("where.gather", build) or build()
end

-- Mob zones: yours (Drops) plus shared ones. { zone = kills }
function W.MobZones(cid)
  local out = {}
  local Dr = ns.Drops
  for z, n in pairs(Dr and Dr.MobZones(cid) or {}) do out[z] = (out[z] or 0) + n end
  for _, sh in pairs(db and db.sightShares or {}) do
    for z, n in pairs(sh.mobs and sh.mobs[cid] or {}) do out[z] = (out[z] or 0) + n end
  end
  return out
end

-- Player position -------------------------------------------------------------------------
function W.PlayerZone()
  local zone = C.GetZone()
  local sub = GetSubZoneText and C.Safe(GetSubZoneText()) or nil
  local map = C_Map and C_Map.GetBestMapForUnit and C.SafeNumber(C_Map.GetBestMapForUnit("player"))
  return zone, (sub ~= "" and sub or nil), map
end
function W.PlayerLevel() return UnitLevel and C.SafeNumber(UnitLevel("player")) or nil end

-- Zone level range from the client (C_Map.GetMapLevels), or nil.
function W.Levels(zone)
  local z = ns.Zones and ns.Zones.zones[zone]
  if not (z and C_Map and C_Map.GetMapLevels) then return nil end
  local ok, lo, hi = pcall(C_Map.GetMapLevels, z.map)
  lo, hi = ok and C.SafeNumber(lo), ok and C.SafeNumber(hi)
  if lo and hi and hi > 0 then return lo, hi end
  return nil
end

-- Yards between two zone centres (nil when either isn't a known zone; other continent adds OTHER_CONTINENT).
function W.Distance(a, b)
  local Z = ns.Zones and ns.Zones.zones
  local za, zb = Z and Z[a], Z and Z[b]
  if not (za and zb) then return nil end
  local d = math.floor(math.sqrt((za.x - zb.x) ^ 2 + (za.y - zb.y) ^ 2))
  if za.cont ~= zb.cont then d = d + W.OTHER_CONTINENT end
  return d
end

-- How far a zone is for you: its distance, plus LEVEL_YARDS per level it starts above you.
function W.Reach(fromZone, zone, level)
  local d = W.Distance(fromZone, zone)
  if fromZone == zone then d = 0 end
  local cost = d or W.UNKNOWN_ZONE
  local lo, hi = W.Levels(zone)
  local fit
  if lo and level then
    if level < lo then fit = "high"; cost = cost + (lo - level) * W.LEVEL_YARDS
    elseif level > hi then fit = "low" else fit = "ok" end
  end
  return cost, d, fit, lo, hi
end

-- WhereToFarm(itemID, zoneName, playerLevel) -> {
--   itemID, zone, level,
--   here = zone entry for zoneName (or nil),  nearby = other zone entries, nearest first (distance + level fit),
--   unplaced = { mobs that drop it with no zone seen yet },
--   vendors = { { npc, zone, subzone, price, limited, inZone, distance, shared } } (in-zone first, then nearest),
--   vendorPrice = { price, source = "merchant" | "Forever data", vendor } or nil,  empty = true when nothing known }
-- zone entry = { zone, inCurrentZone, mobs = { { cid, name, pct, kills } }, gather = { { kind, n } },
--   distance (yards or nil), levelMin, levelMax, levelFit = "ok" | "high" | "low" | nil, cost }
function W.WhereToFarm(itemID, zoneName, playerLevel)
  itemID = C.SafeNumber(itemID)
  local pz = W.PlayerZone()
  zoneName = zoneName or pz
  playerLevel = playerLevel or W.PlayerLevel()
  local out = { itemID = itemID, zone = zoneName, level = playerLevel, nearby = {}, unplaced = {}, vendors = {} }
  if not itemID then out.empty = true return out end
  local byZone = {}
  local function entry(zone)
    local e = byZone[zone]
    if not e then
      local cost, d, fit, lo, hi = W.Reach(zoneName, zone, playerLevel)
      e = { zone = zone, inCurrentZone = zone == zoneName, mobs = {}, gather = {}, distance = d, cost = cost,
        levelFit = fit, levelMin = lo, levelMax = hi }
      byZone[zone] = e
    end
    return e
  end
  local Dr = ns.Drops
  for _, row in ipairs(Dr and Dr.SourcesOf(itemID).rows or {}) do
    local mob = { cid = row.cid, name = Dr.MobName(row.cid), pct = Dr.Percent(row), kills = row.loots }
    local zones = W.MobZones(row.cid)
    if next(zones) == nil then out.unplaced[#out.unplaced + 1] = mob
    else for z in pairs(zones) do table.insert(entry(z).mobs, mob) end end
  end
  for zone, items in pairs(W.AllGather()) do
    local g = items[itemID]
    if g then table.insert(entry(zone).gather, { kind = g.k, n = g.n }) end
  end
  for _, e in pairs(byZone) do
    table.sort(e.mobs, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.cid < b.cid end)
    table.sort(e.gather, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.kind < b.kind end)
    if e.inCurrentZone then out.here = e else out.nearby[#out.nearby + 1] = e end
  end
  table.sort(out.nearby, function(a, b) if a.cost ~= b.cost then return a.cost < b.cost end return a.zone < b.zone end)
  local V = ns.Vendors
  out.vendors = V and V.GetVendorsForItem(itemID, zoneName) or {}
  local first = out.vendors[1]
  if first and not first.limited then out.vendorPrice = { price = first.price, source = "merchant", vendor = first }
  else
    local D = ns.Data
    local bundled = D and ((D.buy and D.buy[itemID]))
    local cap = ns.Prices and ns.Prices.Cap(itemID)
    if bundled then out.vendorPrice = { price = bundled, source = "Forever data" }
    elseif cap then out.vendorPrice = { price = cap, source = "merchant", capped = true } end
  end
  out.empty = out.here == nil and #out.nearby == 0 and #out.unplaced == 0 and #out.vendors == 0 and out.vendorPrice == nil
  return out
end

-- Short label for a zone entry: "<zone> (<mob>, <rate>%)" / "Dun Morogh (mine)".
function W.EntryText(e)
  local bits = {}
  local m = e.mobs[1]
  if m then bits[#bits + 1] = ("%s, %d%%"):format(m.name or ("mob " .. m.cid), m.pct) end
  for _, g in ipairs(e.gather) do bits[#bits + 1] = g.kind end
  return e.zone .. (#bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "")
end

-- Verb for a zone entry: "Farm here" (mobs), "Mine here", "Herb here"...
function W.Verb(e)
  if #e.mobs > 0 then return W.KINDS.mob end
  local g = e.gather[1]
  return g and W.KINDS[g.kind] or W.KINDS.mob
end

-- One compact tooltip phrase, or nil: "Mine here: Dun Morogh", "Farm here: <zone> (<mob>, <rate>%)",
-- "Nearest: Loch Modan (mine)", "Vendor here: Tharynn Bouden 10c".
function W.TooltipText(itemID)
  local zone = C.GetZone()
  local key = "where.tip." .. tostring(itemID) .. "." .. tostring(zone)
  local r = ns.Cache and ns.Cache.Get(key, function() return W.WhereToFarm(itemID, zone) end) or W.WhereToFarm(itemID, zone)
  if r.here then
    local e = r.here
    if #e.mobs > 0 then return "Farm here: " .. W.EntryText(e) end
    return W.Verb(e) .. " here: " .. e.zone
  end
  local v = r.vendors[1]
  if v and v.inZone and not v.limited then return ("Vendor here: %s %s"):format(v.npc, C.Money(v.price)) end
  local n = r.nearby[1]
  if n then return "Nearest: " .. W.EntryText(n) end
  return nil
end

RM.AddModule(W)
