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
  get = function(id) return pos(Auctionator.API.v1.GetAuctionPriceByItemID("What Can I Make?", id)) end })

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
  get = function(id) return pos(AucAdvanced.API.GetMarketValue("item:" .. id)) end })

-- Our own cache, filled from AH searches you do yourself (always available).
P.Register({ id = "scan", label = "What Can I Make? scan",
  available = function() return true end,
  get = function(id) local r = P.cache and P.cache[id]; return r and pos(r.p), r and r.t end })

P.DEFAULT_ORDER = { "pricelog", "auctionator", "tsm", "auctioneer", "scan" }

-- Order from settings (comma list), unknown ids dropped, missing ids appended in default order.
function P.Order(setting)
  local out, seen = {}, {}
  for idv in tostring(setting or ""):gmatch("[^,%s]+") do
    if P.byId[idv] and not seen[idv] then out[#out + 1] = idv; seen[idv] = true end
  end
  for _, idv in ipairs(P.DEFAULT_ORDER) do if not seen[idv] then out[#out + 1] = idv; seen[idv] = true end end
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

-- Passive cache from your own AH searches (browse results and commodity searches). Never searches by itself.
function P.Remember(itemID, unit, now)
  unit = pos(unit)
  if not (P.cache and itemID and unit) then return end
  local r = P.cache[itemID]
  if not r or (now - (r.t or 0)) > 3600 or unit < r.p then P.cache[itemID] = { p = unit, t = now } end
end
