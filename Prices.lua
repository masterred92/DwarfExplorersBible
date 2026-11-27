-- Prices.lua: a pluggable price-source layer. Each source reads an installed price addon through its
-- public API; the first source in your order that has a price wins, and every price carries its source.
-- APIs checked in each addon's own source (see README "Price sources").
local _, ns = ...
local C = ns.Compat
local P = { list = {}, byId = {} }
ns.Prices = P

local function pos(v) v = C.SafeNumber(v); if v and v > 0 then return math.floor(v) end return nil end

-- spec = { id, label, available = fn() -> bool, get = fn(itemID) -> copper or nil }
function P.Register(spec)
  if type(spec) ~= "table" or type(spec.id) ~= "string" or P.byId[spec.id] then return false end
  if type(spec.get) ~= "function" or type(spec.available) ~= "function" then return false end
  P.byId[spec.id] = spec
  P.list[#P.list + 1] = spec
  return true
end

-- Kenny's PriceLog: KennyPriceLog.GetLatest(itemID) -> { p = copper, t = time }.
P.Register({ id = "pricelog", label = "PriceLog",
  available = function() return type(KennyPriceLog) == "table" and type(KennyPriceLog.GetLatest) == "function" end,
  get = function(id) local r = KennyPriceLog.GetLatest(id); return r and pos(r.p), r and r.t end })

-- Auctionator: Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID) (Source/API/v1/GetAuctionPrice.lua).
P.Register({ id = "auctionator", label = "Auctionator",
  available = function() return type(Auctionator) == "table" and type(Auctionator.API) == "table"
    and type(Auctionator.API.v1) == "table" and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function" end,
  get = function(id) return pos(Auctionator.API.v1.GetAuctionPriceByItemID("Dwarf Explorer's Bible", id)) end })

-- TradeSkillMaster: TSM_API.GetCustomPriceValue(customPriceStr, itemString) (Core/API.lua). No Forever build yet.
P.Register({ id = "tsm", label = "TSM",
  available = function() return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function" end,
  get = function(id)
    local s = "i:" .. id
    return pos(TSM_API.GetCustomPriceValue("DBMarket", s)) or pos(TSM_API.GetCustomPriceValue("DBMinBuyout", s))
  end })

-- Auctioneer: AucAdvanced.API.GetMarketValue(itemLink, serverKey) (Auc-Advanced/CoreAPI.lua).
P.Register({ id = "auctioneer", label = "Auctioneer",
  available = function() return type(AucAdvanced) == "table" and type(AucAdvanced.API) == "table"
    and type(AucAdvanced.API.GetMarketValue) == "function" end,
  -- Pass the numeric itemID: GetMarketValue turns a number into a link itself. A bare "item:123" string is
  -- not a hyperlink, so Auctioneer's DecodeLink rejects it and prints "Link is not item" to chat.
  get = function(id) return pos(AucAdvanced.API.GetMarketValue(id)) end })

-- Our own cache, filled from AH searches you do yourself (always available).
P.Register({ id = "scan", label = "Dwarf Explorer's Bible scan",
  available = function() return true end,
  get = function(id) local r = P.cache and P.cache[id]; return r and pos(r.p), r and r.t end })

-- Bundled Forever baseline (optional ns.BaselinePrices = { market, capturedAt, prices = { [itemID] = copper } }).
-- Always last: any live source beats it. Its time is the capture time, so the UI can say "Forever baseline (Nov 27)".
P.Register({ id = "baseline", label = "Forever baseline",
  available = function() local b = ns.BaselinePrices; return type(b) == "table" and type(b.prices) == "table" end,
  get = function(id) local b = ns.BaselinePrices; return pos(b.prices[id]), C.SafeNumber(b.capturedAt) end })

P.DEFAULT_ORDER = { "pricelog", "auctionator", "tsm", "auctioneer", "scan", "baseline" }
P.LAST = { baseline = true } -- never moved ahead of a live source by /deb prefer or /deb order

-- Order from settings (comma list), unknown ids dropped, missing ids appended in default order.
function P.Order(setting)
  local out, seen = {}, {}
  for idv in tostring(setting or ""):gmatch("[^,%s]+") do
    if P.byId[idv] and not seen[idv] and not P.LAST[idv] then out[#out + 1] = idv; seen[idv] = true end
  end
  for _, idv in ipairs(P.DEFAULT_ORDER) do if not seen[idv] and not P.LAST[idv] then out[#out + 1] = idv; seen[idv] = true end end
  for _, idv in ipairs(P.DEFAULT_ORDER) do if P.LAST[idv] then out[#out + 1] = idv end end
  return out
end

-- price (copper), sourceLabel, sourceId, time  -- or nil.
function P.Get(itemID, setting)
  if type(itemID) ~= "number" then return nil end
  for _, idv in ipairs(P.Order(setting)) do
    local s = P.byId[idv]
    local okA, avail = pcall(s.available)
    if okA and avail then
      local ok, price, t = pcall(s.get, itemID)
      if ok and price then return price, s.label, s.id, t end
    end
  end
  return nil
end

function P.Installed()
  local out = {}
  for _, s in ipairs(P.list) do local ok, a = pcall(s.available); if ok and a then out[#out + 1] = s.label end end
  return out
end

-- The one price resolver every module uses ------------------------------------------------------
-- side "sell" (what an item fetches): live AH -> your source order (PriceLog first by default, baseline last).
-- side "buy" (what a reagent costs you): the same AH price, but a vendor that sells it
-- (remembered from a merchant you opened, else the bundled Forever price) wins unless the AH is cheaper, and a
-- vendor-capped reagent never costs more than the vendor price you've seen. "Live" = a price DEB saw in an AH
-- search while the AH is open, under LIVE_SECONDS old. Never a made-up 0: no price gives price = nil, kind "none".
-- Returns { price, kind = "vendor"|"ah"|"none", source = id, label, t, ageSeconds (nil = unknown),
--   vendor = { npc, zone, price, t } when a remembered vendor sells it, capped = true when the vendor cap applied }.
P.LIVE_SECONDS = 900
local function result(price, kind, source, label, t, now)
  t = C.SafeNumber(t)
  local age = (t and t > 0) and math.max(0, now - t) or nil
  return { price = price, kind = kind, source = source, label = label, t = t, ageSeconds = age }
end

local function ahPrice(itemID, setting, now)
  local live = P.cache and P.cache[itemID]
  if P.ahOpen and live and live.t and now - live.t <= P.LIVE_SECONDS and pos(live.p) then
    return pos(live.p), "live AH", "live", live.t
  end
  return P.Get(itemID, setting)
end

function P.Resolve(itemID, side, setting)
  local now = C.Now()
  itemID = C.SafeNumber(itemID)
  if not itemID then return result(nil, "none", nil, nil, nil, now) end
  local price, label, id, t = ahPrice(itemID, setting, now)
  if side ~= "buy" then
    if not price then return result(nil, "none", nil, nil, nil, now) end
    return result(price, "ah", id, label, t, now)
  end
  local V = ns.Vendors
  local seen = V and V.Best and V.Best(itemID)
  local vendor = (seen and seen.price) or P.Vendor(itemID)
  if vendor and (not price or vendor <= price) then
    local r = result(vendor, "vendor", "vendor", "vendor", seen and seen.t, now)
    r.vendor = seen
    return r
  end
  if ns.Data and ns.Data.vendorCap and ns.Data.vendorCap[itemID] then
    local cap = P.Cap(itemID)
    if cap and (not price or cap < price) then
      local r = result(cap, "vendor", "vendorCap", "vendor cap", nil, now); r.capped = true; return r
    end
  end
  if not price then return result(nil, "none", nil, nil, nil, now) end
  return result(price, "ah", id, label, t, now)
end

-- Passive cache from your own AH searches (browse results and commodity searches). Never searches by itself.
function P.Remember(itemID, unit, now)
  unit = pos(unit)
  if not (P.cache and itemID and unit) then return end
  local r = P.cache[itemID]
  if not r or (now - (r.t or 0)) > 3600 or unit < r.p then
    P.cache[itemID] = { p = unit, t = now }
    if ns.Cache then ns.Cache.Bump() end
  end
end

-- Vendor prices ------------------------------------------------------------------------------
-- Per-unit price at a vendor, for reagents a vendor sells (thread, flux, vials, spices, dyes...).
-- Learned from merchant windows you open (unlimited stock only, like Auctionator), else the bundled Forever price.
function P.Vendor(itemID)
  local v = P.vendorCache and P.vendorCache[itemID]
  if v then return v end
  local D = ns.Data
  return D and D.buy and D.buy[itemID] or nil
end

-- Vendor price you have seen for a reagent Blizzard says a vendor sells (Data.vendorCap), even when the vendor
-- has limited stock. Used only as a ceiling on that reagent's cost, never as a price for anything else.
function P.Cap(itemID)
  return P.capCache and P.capCache[itemID] or nil
end

-- Rows of the open merchant window: { { id, unit (copper per item), avail (-1 = unlimited), stack } }.
-- Gold-priced rows only (currency and extended-cost rows are skipped). Shared by ReadMerchant and Vendors.lua.
function P.MerchantRows()
  local rows = {}
  if not (GetMerchantNumItems and GetMerchantItemID) then return rows end
  for i = 1, (C.SafeNumber(GetMerchantNumItems()) or 0) do
    local id = C.SafeNumber(GetMerchantItemID(i))
    local price, stack, avail
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = C_MerchantFrame.GetItemInfo(i)
      if info and not info.currencyID and not info.hasExtendedCost then price, stack, avail = info.price, info.stackCount, info.numAvailable end
    elseif GetMerchantItemInfo then
      local _, _, p, s, a, _, _, ext = GetMerchantItemInfo(i)
      if not ext then price, stack, avail = p, s, a end
    end
    price, stack, avail = C.SafeNumber(price), C.SafeNumber(stack), C.SafeNumber(avail)
    if id and price and price > 0 and stack and stack > 0 then
      rows[#rows + 1] = { id = id, unit = math.max(1, math.floor(price / stack + 0.5)), avail = avail, stack = stack }
    end
  end
  return rows
end

-- Reads the open merchant window. Called on MERCHANT_SHOW; reads only, buys nothing.
function P.ReadMerchant(rows)
  if not P.vendorCache then return 0 end
  local n = 0
  for _, r in ipairs(rows or P.MerchantRows()) do
    if r.avail == -1 then P.vendorCache[r.id] = r.unit; n = n + 1
    elseif P.capCache and ns.Data and ns.Data.vendorCap and ns.Data.vendorCap[r.id] then P.capCache[r.id] = r.unit; n = n + 1 end
  end
  if n > 0 and ns.Cache then ns.Cache.Bump() end
  return n
end
