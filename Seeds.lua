-- Seeds.lua: herb seeds, the Greenhouse and the Seed Hybridizer in your bags and bank, what each seed is for, and
-- whether you're ready to plant. Seeds and camp actions come from the client data (Data.camp, Data.campOff); the
-- crops come from GROWS below, which is REPORTED (Icy Veins), not datamined. It never plants or uses anything:
-- the UI shows a hint and can light up the bag slots (Inventory.BagSlots).
local _, ns = ...
local C = ns.Compat
local S = {}
ns.Seeds = S
local RM = ns.RM

-- What a planted seed grows into. REPORTED by Icy Veins (Nov 2026): "Commonplace -> Peacebloom or Earthroot,
-- Uncommon -> Silverleaf or Kingsblood, Scarce -> Ghost Mushroom". Unusual seeds: no report yet.
-- https://www.icy-veins.com/wow-forever/news/greenhouse-blueprint-found-how-herbalism-seeds-work-in-wow-forever/
S.GROWS = { [268415] = { 2447, 2449 }, [268416] = { 765, 3356 }, [268418] = { 8845 } }
S.GROWS_SOURCE = "reported (Icy Veins)"

local places -- { ["Greenhouse"] = itemID, ["Seed Hybridizer"] = itemID } from the camp rows' place names

local function placeItems()
  if places then return places end
  places = {}
  local D = ns.Data
  local want = {}
  for _, list in pairs(RM.byCamp) do for _, c in ipairs(list) do if c.place ~= "" then want[c.place] = true end end end
  for id, name in pairs(D and D.names or {}) do
    if want[name] and RM.byProduct[id] then places[name] = id end
  end
  return places
end

-- Seeds = items a Plant Seeds or Hybridize Seeds camp action uses (or used, Data.campOff).
function S.IsSeed(id)
  if RM.CampOff(id) then return true end
  for _, c in ipairs(RM.byCamp[id] or {}) do
    if c.action == "Plant Seeds" or c.action == "Hybridize Seeds" then return true end
  end
  return false
end

function S.IsSeedItem(id)
  if S.IsSeed(id) then return true end
  for _, pid in pairs(placeItems()) do if pid == id then return true end end
  return false
end

function S.Places() return placeItems() end

local function campOf(id, action)
  for _, c in ipairs(RM.byCamp[id] or {}) do if c.action == action then return c end end
  return nil
end

-- What the item is for, in plain English.
function S.Role(id, kind)
  if kind == "greenhouse" then return "Greenhouse: plant 1 seed in it (crop grows in about 8 minutes)" end
  if kind == "hybridizer" then return "Seed Hybridizer: combine 2 seeds of one kind (can fail)" end
  local parts = {}
  local grows = S.GROWS[id]
  if campOf(id, "Plant Seeds") then
    if grows then
      local names = {}
      for _, g in ipairs(grows) do names[#names + 1] = RM.Name(g) end
      parts[#parts + 1] = "Greenhouse seed · grows into " .. table.concat(names, " or ") .. ", " .. S.GROWS_SOURCE
    else
      parts[#parts + 1] = "Greenhouse seed · crop not reported yet"
    end
  end
  local hyb = campOf(id, "Hybridize Seeds")
  if hyb then parts[#parts + 1] = ("Hybridizer: %d of these%s"):format(hyb.n, hyb.canFail and " (can fail)" or "") end
  local off = RM.CampOff(id)
  if off then parts[#parts + 1] = off end
  return table.concat(parts, " · ")
end

-- AH value of the best crop (what one crop fetches), or nil when no crop has a price.
function S.OutputValue(id)
  local best
  for _, g in ipairs(S.GROWS[id] or {}) do
    local r = RM.Resolve(g, "sell")
    if r.price and (not best or r.price > best) then best = r.price end
  end
  return best
end

-- Rows for the Seeds tab. filter "ready" keeps rows you can act on now.
-- { { itemID, name, kind = "seed"|"greenhouse"|"hybridizer", bags, bank, role, grows = { itemIDs }, value,
--   recipes = n (recipes using it), canPlant, canHybridize, ready, hint } }
function S.Rows(filter)
  local list = ns.Cache.Get("seeds.rows", S.Build)
  if filter ~= "ready" then return list end
  local out = {}
  for _, r in ipairs(list) do if r.ready then out[#out + 1] = r end end
  return out
end

function S.Build()
  local I = ns.Inventory
  local pl = placeItems()
  local gh, hy = pl["Greenhouse"], pl["Seed Hybridizer"]
  local ghBags = gh and I.Count(gh).bags or 0
  local hyBags = hy and I.Count(hy).bags or 0
  local rows = {}
  local ids = {}
  for id in pairs(RM.byCamp) do if S.IsSeed(id) then ids[#ids + 1] = id end end
  for id in pairs(ns.Data and ns.Data.campOff or {}) do if not RM.byCamp[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local h = I.Count(id)
    if h.mine > 0 then
      local plant, hyb = campOf(id, "Plant Seeds"), campOf(id, "Hybridize Seeds")
      local canPlant = plant ~= nil and h.bags >= plant.n and ghBags > 0
      local canHyb = hyb ~= nil and not RM.CampOff(id) and h.bags >= hyb.n and hyBags > 0
      rows[#rows + 1] = { itemID = id, name = RM.Name(id), kind = "seed", bags = h.bags, bank = h.bank, role = S.Role(id, "seed"),
        grows = S.GROWS[id], value = S.OutputValue(id), recipes = #(RM.byReagent[id] or {}), canPlant = canPlant,
        canHybridize = canHyb, ready = canPlant or canHyb,
        hint = canPlant and "Use your Greenhouse, then plant from your bags"
          or (canHyb and "Use your Seed Hybridizer, then combine from your bags")
          or (h.bags == 0 and "In your bank" or (plant and ghBags == 0 and "Needs a Greenhouse in your bags") or nil) }
    end
  end
  for kind, pid in pairs({ greenhouse = gh, hybridizer = hy }) do
    local h = I.Count(pid)
    if h.mine > 0 then
      rows[#rows + 1] = { itemID = pid, name = RM.Name(pid), kind = kind, bags = h.bags, bank = h.bank, role = S.Role(pid, kind),
        recipes = #(RM.byReagent[pid] or {}), ready = h.bags > 0, hint = h.bags > 0 and "Use it from your bags at a camp" or "In your bank" }
    end
  end
  table.sort(rows, function(a, b)
    if (a.kind == "seed") ~= (b.kind == "seed") then return b.kind == "seed" end
    return a.itemID < b.itemID
  end)
  return rows
end

-- Top bar: { seeds = n in bags, greenhouse = bool, hybridizer = bool, text } ("Seeds in bags: 6 · Greenhouse ready").
function S.Summary()
  local rows = S.Rows()
  local n, gh, hy = 0, false, false
  for _, r in ipairs(rows) do
    if r.kind == "seed" then n = n + r.bags elseif r.kind == "greenhouse" then gh = r.bags > 0 else hy = r.bags > 0 end
  end
  local bits = { "Seeds in bags: " .. n }
  if gh then bits[#bits + 1] = "Greenhouse ready" end
  if hy then bits[#bits + 1] = "Hybridizer ready" end
  return { seeds = n, greenhouse = gh, hybridizer = hy, empty = #rows == 0, text = table.concat(bits, " · ") }
end

S.EMPTY = "No seeds, greenhouse or hybridizer items found in your bags or bank."

function S.BagSlots(itemID) return ns.Inventory.BagSlots(C.SafeNumber(itemID)) end
