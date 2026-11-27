-- Vendors.lua: remembers what each merchant you open sells, for how much, and where (KennyDwarfExplorersBibleDB.vendors):
-- list[npc|zone|subzone] = { npc, zone, subzone, t, items = { [itemID] = { p = copper per item, limited = true|nil } } }.
-- Read on MERCHANT_SHOW from the merchant window; it never buys anything. Bounded: MAX_VENDORS merchants (the one
-- you saw longest ago goes first) and MAX_ITEMS crafting goods each. Merchants other Bible users shared with you
-- (ShareData.lua) are kept apart in db.sightShares and only added in for lookups.
local _, ns = ...
local C = ns.Compat
local V = {}
ns.Vendors = V
local RM = ns.RM
local store
local index, indexAt = nil, -1

V.MAX_VENDORS = 60
V.MAX_ITEMS = 150

function V.Attach(d)
  d.vendors = d.vendors or {}
  d.vendors.list = d.vendors.list or {}
  store = d.vendors
  index = nil
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function prune()
  while count(store.list) > V.MAX_VENDORS do
    local oldest, at
    for key, v in pairs(store.list) do
      if not oldest or (v.t or 0) < at then oldest, at = key, v.t or 0 end
    end
    store.list[oldest] = nil
  end
end

-- Crafting goods only: items a bundled or learned recipe uses (reagents), or a camp action uses.
function V.IsCraftingGood(id) return RM.byReagent[id] ~= nil or RM.byCamp[id] ~= nil end

function V.Key(npc, zone, subzone) return tostring(npc) .. "|" .. tostring(zone) .. "|" .. tostring(subzone or "") end

-- rows from Prices.MerchantRows(): { { id, unit, avail, stack } }. npc/zone/subzone default to the open merchant
-- (UnitName("npc")) and where you stand (GetRealZoneText / GetSubZoneText).
function V.Record(rows, npc, zone, subzone, now)
  if not store or type(rows) ~= "table" then return false end
  npc = npc or (UnitName and C.Safe(UnitName("npc")))
  if type(npc) ~= "string" or npc == "" then return false end
  zone = zone or C.GetZone() or "?"
  if subzone == nil then subzone = GetSubZoneText and C.Safe(GetSubZoneText()) or "" end
  if subzone == zone then subzone = "" end
  local items, n = {}, 0
  for _, r in ipairs(rows) do
    if n >= V.MAX_ITEMS then break end
    if V.IsCraftingGood(r.id) then items[r.id] = { p = r.unit, limited = r.avail ~= -1 or nil }; n = n + 1 end
  end
  local key = V.Key(npc, zone, subzone)
  if n == 0 then
    if store.list[key] then store.list[key] = nil; index = nil end
    return false
  end
  store.list[key] = { npc = npc, zone = zone, subzone = subzone ~= "" and subzone or nil, t = now or C.Now(), items = items }
  prune()
  index = nil
  if ns.Cache then ns.Cache.Bump() end
  if ns.ShareData then ns.ShareData.OnPersonalChange() end
  return true
end

-- Your own merchants, for sharing: { key = record }.
function V.Own() return store and store.list or {} end

local function buildIndex()
  index = {}
  local seen = {}
  local function add(key, v, shared)
    if seen[key] then return end
    seen[key] = true
    for id, it in pairs(v.items or {}) do
      local list = index[id]
      if not list then list = {}; index[id] = list end
      list[#list + 1] = { key = key, npc = v.npc, zone = v.zone, subzone = v.subzone, price = it.p, limited = it.limited == true,
        t = v.t, shared = shared or nil }
    end
  end
  for key, v in pairs(store and store.list or {}) do add(key, v, false) end
  local d = KennyDwarfExplorersBibleDB
  for _, sh in pairs(d and d.sightShares or {}) do
    for _, v in ipairs(sh.vendors or {}) do add(V.Key(v.npc, v.zone, v.subzone), v, true) end
  end
  for _, list in pairs(index) do
    table.sort(list, function(a, b)
      if a.limited ~= b.limited then return not a.limited end
      if a.price ~= b.price then return a.price < b.price end
      return (a.t or 0) > (b.t or 0)
    end)
  end
  indexAt = ns.Cache and ns.Cache.Version() or 0
end

-- Every remembered merchant that sells itemID, cheapest unlimited stock first: { { key, npc, zone, subzone, price, limited, t, shared } }.
function V.SoldBy(itemID)
  if not index or indexAt ~= (ns.Cache and ns.Cache.Version() or 0) then buildIndex() end
  return index[itemID] or {}
end

-- GetVendorsForItem(itemID[, zoneName]): like SoldBy, but merchants in zoneName come first (inZone = true), then
-- by distance between zones (Where.Distance), then unlimited stock and price. Each row gets inZone and distance.
function V.GetVendorsForItem(itemID, zoneName)
  zoneName = zoneName or C.GetZone()
  local W = ns.Where
  local out = {}
  for _, v in ipairs(V.SoldBy(itemID)) do
    local row = {}
    for k, x in pairs(v) do row[k] = x end
    row.inZone = v.zone == zoneName
    row.distance = row.inZone and 0 or (W and W.Distance(zoneName, v.zone)) or nil
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    if a.inZone ~= b.inZone then return a.inZone end
    local da, db2 = a.distance or math.huge, b.distance or math.huge
    if da ~= db2 then return da < db2 end
    if a.limited ~= b.limited then return not a.limited end
    if a.price ~= b.price then return a.price < b.price end
    return a.npc < b.npc
  end)
  return out
end

-- GetVendorGoods(vendorKey): { npc, zone, subzone, t, shared, goods = { { itemID, name, price, limited } } } (by name) or nil.
function V.GetVendorGoods(key)
  local v, shared = store and store.list[key], false
  if not v then
    local d = KennyDwarfExplorersBibleDB
    for _, sh in pairs(d and d.sightShares or {}) do
      for _, sv in ipairs(sh.vendors or {}) do if V.Key(sv.npc, sv.zone, sv.subzone) == key then v, shared = sv, true end end
    end
  end
  if not v then return nil end
  local goods = {}
  for id, it in pairs(v.items or {}) do goods[#goods + 1] = { itemID = id, name = RM.Name(id), price = it.p, limited = it.limited == true } end
  table.sort(goods, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.itemID < b.itemID end)
  return { key = key, npc = v.npc, zone = v.zone, subzone = v.subzone, t = v.t, shared = shared, goods = goods }
end

-- Your remembered merchants, newest first: { { key, npc, zone, subzone, t, goods = n } }.
function V.List()
  local out = {}
  for key, v in pairs(store and store.list or {}) do out[#out + 1] = { key = key, npc = v.npc, zone = v.zone, subzone = v.subzone, t = v.t, goods = count(v.items or {}) } end
  table.sort(out, function(a, b) if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end return a.key < b.key end)
  return out
end

-- Cheapest remembered merchant with unlimited stock, or nil.
function V.Best(itemID)
  local first = V.SoldBy(itemID)[1]
  if first and not first.limited then return first end
  return nil
end

-- "Vendor: Tharynn Bouden (Elwynn Forest)" / "Vendor: Tharynn Bouden (Goldshire, Elwynn Forest)"
function V.Text(v)
  if not v then return nil end
  return ("Vendor: %s (%s)"):format(v.npc, v.subzone and (v.subzone .. ", " .. v.zone) or v.zone)
end

-- True when Materials should show a [Vendor] tag on this reagent.
function V.Tag(itemID) return V.Best(itemID) ~= nil end

function V.Count() return store and count(store.list) or 0 end
function V.IndexAge() return indexAt end
RM.AddModule(V)
