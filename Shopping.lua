-- Shopping.lua: a short shopping list (KennyDwarfExplorersBibleDB.shopping) split into what to buy at a Vendor, what
-- to Grab from an Alt (another character on this realm and faction holds it) and what to buy at the AH. Each line
-- uses the one item-count resolver (Inventory.Count) and the one price resolver (Prices.Resolve). A line you must
-- buy with no known price has estCost = nil and incomplete = true, never 0g. Click-to-fill only types the item's
-- name into the open Auction House search and starts that search on your click; it never buys.
local _, ns = ...
local C = ns.Compat
local S = {}
ns.Shopping = S
local RM = ns.RM
local store

S.MAX_ITEMS = 60

function S.Attach(d)
  d.shopping = d.shopping or {}
  d.shopping.items = d.shopping.items or {}
  d.shopping.order = d.shopping.order or {}
  store = d.shopping
end

local function changed() if ns.Cache then ns.Cache.Bump() end end

function S.Has(id) return store ~= nil and store.items[id] ~= nil end

-- Add need units of itemID (adds up when already listed). from = what it's for ("Bolt of Linen Cloth" or "manual").
function S.AddItem(itemID, need, from)
  itemID, need = C.SafeNumber(itemID), math.floor(C.SafeNumber(need) or 1)
  if not (store and itemID and need > 0) then return false end
  local e = store.items[itemID]
  if not e then
    if #store.order >= S.MAX_ITEMS then return false, "full" end
    e = { need = 0, from = from or "manual", t = C.Now() }
    store.items[itemID] = e
    store.order[#store.order + 1] = itemID
  elseif from and e.from ~= from and not e.from:find(from, 1, true) then
    e.from = e.from .. ", " .. from
  end
  e.need, e.done = e.need + need, nil
  changed()
  return true
end

-- Add the reagents of recipe r for `crafts` crafts that your bags + bank don't already cover. A line keeps the
-- full amount needed; each row works out what is still short from your current bags + bank.
function S.AddRecipe(r, crafts)
  crafts = math.max(1, math.floor(C.SafeNumber(crafts) or 1))
  local I, added = ns.Inventory, 0
  local from = RM.Name(r.product)
  for _, g in ipairs(r.reagents) do
    local need = g.n * crafts
    if need > (I and I.Count(g.id).mine or 0) and S.AddItem(g.id, need, from) then added = added + 1 end
  end
  return added
end

function S.SetDone(itemID, done)
  local e = store and store.items[itemID]
  if not e then return false end
  e.done = done and true or nil
  changed()
  return true
end

function S.Remove(itemID)
  if not (store and store.items[itemID]) then return false end
  store.items[itemID] = nil
  for i = #store.order, 1, -1 do if store.order[i] == itemID then table.remove(store.order, i) end end
  changed()
  return true
end

function S.ClearDone()
  local n = 0
  for _, id in ipairs({ unpack(store and store.order or {}) }) do
    if store.items[id].done then S.Remove(id); n = n + 1 end
  end
  return n
end

function S.ClearAll()
  if not store then return 0 end
  local n = #store.order
  store.items, store.order = {}, {}
  changed()
  return n
end

-- The vendor this line would be bought from: a remembered merchant with unlimited stock (in your zone first, then
-- the nearest), else the bundled Forever vendor price. { key, npc, zone, subzone, price } or nil.
local function vendorFor(itemID, zone)
  local V = ns.Vendors
  for _, v in ipairs(V and V.GetVendorsForItem(itemID, zone) or {}) do
    if not v.limited then return v end
  end
  return nil
end

-- One row per listed item:
-- { itemID, name, need, from, done, bags, bank, have, short, fromAlt, buy, altHolders = { { name, n } },
--   category = "done" | "have" | "alt" | "vendor" | "ah", unitPrice, estCost (nil = unknown), incomplete,
--   priceLabel, ageSeconds, vendor = { key, npc, zone, subzone, price } (vendor rows) }
function S.Row(itemID, zone)
  local e = store.items[itemID]
  local I = ns.Inventory
  local h = I and I.Count(itemID) or { bags = 0, bank = 0, mine = 0, alts = 0, holders = {} }
  local row = { itemID = itemID, name = RM.Name(itemID), need = e.need, from = e.from, done = e.done == true,
    bags = h.bags, bank = h.bank, have = h.mine, altHolders = {} }
  row.short = math.max(0, e.need - h.mine)
  row.fromAlt = math.min(row.short, h.alts)
  row.buy = row.short - row.fromAlt
  for _, x in ipairs(h.holders) do
    if x.mailable then row.altHolders[#row.altHolders + 1] = { name = x.name, n = x.bags + x.bank } end
  end
  if row.done then row.category = "done"
  elseif row.short == 0 then row.category = "have"
  elseif row.buy == 0 then row.category = "alt"
  end
  local pr = RM.Resolve(itemID, "buy")
  local v = pr.kind == "vendor" and vendorFor(itemID, zone)
  row.unitPrice = (v and v.price) or pr.price
  row.priceLabel, row.ageSeconds = pr.label, pr.ageSeconds
  if not row.category then row.category = pr.kind == "vendor" and "vendor" or "ah" end
  if row.category == "vendor" then
    row.vendor = v or { key = "forever", npc = nil, zone = nil, price = pr.price }
  end
  if row.buy > 0 then
    row.estCost = row.unitPrice and row.unitPrice * row.buy or nil
    row.incomplete = row.estCost == nil
  else
    row.estCost, row.incomplete = 0, false
  end
  return row
end

function S.Rows(zone)
  if not store then return {} end
  zone = zone or C.GetZone()
  return ns.Cache.Get("shopping.rows." .. tostring(zone), function()
    local out = {}
    for _, id in ipairs(store.order) do out[#out + 1] = S.Row(id, zone) end
    return out
  end)
end

-- The tab's sections:
-- { vendor = { groups = { { key, npc, zone, subzone, label, rows, subtotal } }, subtotal },
--   alt = { rows }, ah = { rows, subtotal, incomplete }, have = { rows }, done = { rows },
--   total (known cost of vendor + AH lines), incomplete (a line to buy has no price) }
-- Vendor groups: one per merchant, subtotal in copper; lines with only the bundled Forever price go in one group
-- with key "forever".
function S.Sections(zone)
  local secs = { vendor = { groups = {}, subtotal = 0 }, alt = { rows = {} }, ah = { rows = {}, subtotal = 0, incomplete = false },
    have = { rows = {} }, done = { rows = {} }, total = 0, incomplete = false }
  local byKey = {}
  for _, row in ipairs(S.Rows(zone)) do
    local c = row.category
    if c == "vendor" then
      local v = row.vendor
      local g = byKey[v.key]
      if not g then
        g = { key = v.key, npc = v.npc, zone = v.zone, subzone = v.subzone, rows = {}, subtotal = 0,
          label = v.npc and ns.Vendors.Text(v) or "Any vendor (Forever vendor price)" }
        byKey[v.key] = g
        secs.vendor.groups[#secs.vendor.groups + 1] = g
      end
      g.rows[#g.rows + 1] = row
      g.subtotal = g.subtotal + (row.estCost or 0)
      secs.vendor.subtotal = secs.vendor.subtotal + (row.estCost or 0)
    elseif c == "ah" then
      table.insert(secs.ah.rows, row)
      if row.estCost then secs.ah.subtotal = secs.ah.subtotal + row.estCost else secs.ah.incomplete = true end
    else
      table.insert(secs[c].rows, row)
    end
  end
  table.sort(secs.vendor.groups, function(a, b)
    if (a.key == "forever") ~= (b.key == "forever") then return b.key == "forever" end
    return a.label < b.label
  end)
  secs.total = secs.vendor.subtotal + secs.ah.subtotal
  secs.incomplete = secs.ah.incomplete
  return secs
end

-- "Need 12 (have 4 bags, 2 bank → buy 6)" / "... → 6 from Bankalt"
function S.NeedText(row)
  local tail
  if row.buy > 0 then tail = "buy " .. row.buy
  elseif row.fromAlt > 0 then tail = row.fromAlt .. " from " .. (row.altHolders[1] and row.altHolders[1].name or "an alt")
  else tail = "have enough" end
  return ("Need %d (have %d bags, %d bank → %s)"):format(row.need, row.bags, row.bank, tail)
end

-- Banner line for the tab.
function S.Status()
  if S.AHOpen() then return "Click any row to search it at the Auction House." end
  return "Open the Auction House to click-fill searches. Remembered vendors shown below."
end

function S.AHOpen()
  return ns.Prices.ahOpen == true and AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown() == true
end

-- Click-to-fill (call from a row's OnClick only): types the item name into the AH search box and runs that search.
-- Uses AuctionHouseFrame:SetSearchText and its SearchBar:StartSearch (Blizzard_AuctionHouseUI, Forever 1.60.1).
-- Returns true, or false and why ("closed", "combat", "mode", "name").
function S.SearchAH(itemID)
  if not S.AHOpen() then return false, "closed" end
  if C.InCombat() then return false, "combat" end
  local name = C.GetItemName(itemID) or RM.Name(itemID)
  if type(name) ~= "string" or name == "" or name:find("^item %d") then return false, "name" end
  if not AuctionHouseFrame:SetSearchText(name) then return false, "mode" end
  local bar = AuctionHouseFrame.SearchBar
  if bar and bar.StartSearch then bar:StartSearch() end
  return true
end

function S.Count() return store and #store.order or 0 end
RM.AddModule(S)
