-- What Can I Make?: pick a material, see everything it crafts into, what it's worth and where it goes next.
-- Inspired by the Guide in Terraria. Written from scratch (MIT). Reads data, never automates anything.
local ADDON, ns = ...
local C, Core, P, D = ns.Compat, ns.Core, ns.Prices, ns.Data
local M = {}
ns.RM = M
KennyWhatCanIMake = M

local SCHEMA = 1
local DEFAULTS = { sources = table.concat(P.DEFAULT_ORDER, ","), tooltip = true, altClick = true, ahCut = 0.05, chainDepth = 3 }
local db, settings, char
M.byReagent, M.byProduct, M.recipes = {}, {}, {}

-- Recipe index ---------------------------------------------------------------------------
local function addRecipe(r)
  M.recipes[#M.recipes + 1] = r
  M.byProduct[r.product] = M.byProduct[r.product] or {}
  table.insert(M.byProduct[r.product], r)
  for _, g in ipairs(r.reagents) do
    M.byReagent[g.id] = M.byReagent[g.id] or {}
    table.insert(M.byReagent[g.id], r)
  end
end

function M.ParseRow(row, profs)
  local product, mn, mx, prof, skill, rec, rg = row:match("^(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*)$")
  if not product then return nil end
  local r = { product = tonumber(product), min = tonumber(mn), max = tonumber(mx), prof = profs[tonumber(prof)] or "?",
    skill = tonumber(skill), recipeItem = tonumber(rec) ~= 0 and tonumber(rec) or nil, reagents = {}, origin = "data" }
  for id, n in rg:gmatch("(%d+):(%d+)") do r.reagents[#r.reagents + 1] = { id = tonumber(id), n = tonumber(n) } end
  return r
end

function M.BuildIndex()
  M.byReagent, M.byProduct, M.recipes = {}, {}, {}
  for _, row in ipairs(D.recipes) do local r = M.ParseRow(row, D.professions); if r then addRecipe(r) end end
  -- Recipes you've learned that the bundled data doesn't have (new in Forever, or enchants).
  for _, r in pairs(db and db.extra or {}) do
    if type(r) == "table" and r.product and not M.byProduct[r.product] then r.origin = "scan"; addRecipe(r) end
  end
end

function M.Name(id)
  return C.GetItemName(id) or (D.names[id]) or (db and db.names[id]) or ("item " .. tostring(id))
end

-- Known recipes ---------------------------------------------------------------------------
function M.Knows(r) return char ~= nil and char.learned[r.product] == true end
function M.Skill(prof) return char and char.skills[prof] end

-- Record what the open profession window says you know. Ignores linked, guild and NPC crafting windows.
function M.ScanTradeSkill()
  local T = C_TradeSkillUI
  if not (T and T.GetFilteredRecipeIDs and T.GetRecipeInfo and char) then return 0 end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return 0 end
  local n = 0
  for _, rid in ipairs(T.GetFilteredRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(rid)
    if info and C.Safe(info.learned) == true then
      local sch = T.GetRecipeSchematic and T.GetRecipeSchematic(rid, false)
      local out = sch and C.SafeNumber(sch.outputItemID)
      if out then
        char.learned[out] = true; n = n + 1
        local pinfo = T.GetProfessionInfoByRecipeID and T.GetProfessionInfoByRecipeID(rid)
        local prof = pinfo and C.Safe(pinfo.parentProfessionName or pinfo.professionName) or "?"
        if pinfo and C.SafeNumber(pinfo.skillLevel) then char.skills[prof] = C.SafeNumber(pinfo.skillLevel) end
        if not M.byProduct[out] then
          local r = { product = out, min = C.SafeNumber(sch.quantityMin) or 1, max = C.SafeNumber(sch.quantityMax) or 1,
            prof = prof, skill = 0, reagents = {}, origin = "scan" }
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local g = slot.reagents and slot.reagents[1]
            local gid = g and C.SafeNumber(g.itemID)
            if gid and C.Safe(slot.required) ~= false then r.reagents[#r.reagents + 1] = { id = gid, n = C.SafeNumber(slot.quantityRequired) or 1 } end
          end
          if #r.reagents > 0 then db.extra[out] = r; addRecipe(r) end
        end
        local nm = C.Safe(sch.name); if nm then db.names[out] = nm end
      end
    end
  end
  return n
end

-- Prices and profit -------------------------------------------------------------------------
function M.Price(id) return P.Get(id, settings and settings.sources) end

-- { cost, value, profit, missing } ; missing = true when a reagent or the product has no price.
function M.Profit(r)
  local cost, missing = 0, false
  for _, g in ipairs(r.reagents) do
    local p = M.Price(g.id)
    if p then cost = cost + p * g.n else missing = true end
  end
  local pp = M.Price(r.product)
  local value = pp and math.floor(pp * (r.min + r.max) / 2 * (1 - (settings and settings.ahCut or 0.05))) or nil
  if not value then missing = true end
  return { cost = cost, value = value, profit = value and (value - cost) or nil, missing = missing }
end

-- Recipes that use itemID, best profit first (unpriced last), then skill.
function M.UsesOf(itemID)
  local list = {}
  for _, r in ipairs(M.byReagent[itemID] or {}) do list[#list + 1] = { r = r, pr = M.Profit(r) } end
  table.sort(list, function(a, b)
    local pa, pb = a.pr.profit, b.pr.profit
    if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
    if pa and pb and pa ~= pb then return pa > pb end
    if a.r.skill ~= b.r.skill then return a.r.skill < b.r.skill end
    return a.r.product < b.r.product
  end)
  return list
end

-- Where a crafted item goes next: tree { id, next = { {recipe, node}, ... } } to `depth`, no cycles.
function M.Chain(itemID, depth, seen)
  depth = depth or (settings and settings.chainDepth) or 3
  seen = seen or {}
  local node = { id = itemID, next = {} }
  if depth <= 0 or seen[itemID] then return node end
  seen[itemID] = true
  for _, r in ipairs(M.byReagent[itemID] or {}) do
    node.next[#node.next + 1] = { recipe = r, node = M.Chain(r.product, depth - 1, seen) }
  end
  seen[itemID] = nil
  return node
end

-- Item ids whose name contains text (case-insensitive) and that are used in or made by a recipe.
function M.Search(text, limit)
  text = (text or ""):lower()
  local out = {}
  if text == "" then return out end
  local function try(id, name)
    if name and name:lower():find(text, 1, true) and (M.byReagent[id] or M.byProduct[id]) then out[#out + 1] = id end
  end
  for id, name in pairs(D.names) do try(id, name) end
  for id, name in pairs(db and db.names or {}) do if not D.names[id] then try(id, name) end end
  table.sort(out, function(a, b)
    local ua, ub = #(M.byReagent[a] or {}), #(M.byReagent[b] or {})
    if ua ~= ub then return ua > ub end
    return a < b
  end)
  for i = #out, (limit or 50) + 1, -1 do out[i] = nil end
  return out
end

function M.ParseItem(arg)
  arg = arg or ""
  local id = tonumber(arg) or tonumber(arg:match("item:(%d+)"))
  if id then return id end
  local hits = M.Search(arg, 1)
  return hits[1]
end

function M.Settings() return settings end
function M.DB() return db end

-- Tooltip line ---------------------------------------------------------------------------
local function addLines(tooltip, itemID)
  local uses = M.byReagent[itemID]
  local made = M.byProduct[itemID]
  if not uses and not made then return end
  if uses then tooltip:AddLine(("Used in %d recipe%s (What Can I Make?)"):format(#uses, #uses == 1 and "" or "s"), 0.4, 0.8, 1) end
  local p, label = M.Price(itemID)
  if p then tooltip:AddDoubleLine("  Auction (" .. label .. ")", C.Money(p), 0.7, 0.7, 0.7, 1, 1, 1) end
  if uses and settings.altClick then tooltip:AddLine("  Alt-click: what can I make?", 0.5, 0.5, 0.5) end
end
M.AddTooltipLines = addLines

local function OnItemTooltip(tooltip, data)
  if not db or not settings.tooltip or not data then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local itemID = C.SafeNumber(data.id)
  if itemID then Core.SafeCall("tooltip", addLines, tooltip, itemID) end
end

-- Events ---------------------------------------------------------------------------------
local migrations = { [1] = function(d) d.chars = d.chars or {}; d.extra = d.extra or {}; d.names = d.names or {}; d.cache = d.cache or {} end }

function M.Init()
  db = Core.Migrate(KennyWhatCanIMakeDB, migrations, SCHEMA)
  db.chars, db.extra, db.names, db.cache = db.chars or {}, db.extra or {}, db.names or {}, db.cache or {}
  KennyWhatCanIMakeDB = db
  settings = Core.Settings(db.settings, DEFAULTS)
  local key = C.RealmFaction() .. "-" .. tostring(UnitName and C.Safe(UnitName("player")) or "?")
  db.chars[key] = db.chars[key] or { learned = {}, skills = {} }
  char = db.chars[key]
  local rk = C.RealmFaction()
  db.cache[rk] = db.cache[rk] or {}
  P.cache = db.cache[rk]
  M.BuildIndex()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    M.Init()
  elseif event == "PLAYER_LOGIN" then
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
    if hooksecurefunc and HandleModifiedItemClick then
      hooksecurefunc("HandleModifiedItemClick", function(link)
        if settings.altClick and IsAltKeyDown and IsAltKeyDown() and type(link) == "string" then
          local id = tonumber(link:match("item:(%d+)"))
          if id and (M.byReagent[id] or M.byProduct[id]) and M.Open then M.Open(id) end
        end
      end)
    end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    if not C.InCombat() then Core.SafeCall("tradeskill", M.ScanTradeSkill) end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    Core.SafeCall("browse", function() for _, r in ipairs(C.AHBrowse()) do P.Remember(r.itemID, r.price, C.Now()) end end)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = C.SafeNumber(arg1)
    Core.SafeCall("commodity", function()
      local best = C.AHCommodity(id)[1]
      if id and best then P.Remember(id, best.price, C.Now()) end
    end)
  end
end)

-- Slash ---------------------------------------------------------------------------------
SLASH_KENNYWHATCANIMAKE1 = "/wcim"
SLASH_KENNYWHATCANIMAKE2 = "/craftguide"
SlashCmdList.KENNYWHATCANIMAKE = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  local lc = cmd:lower()
  if lc == "" then if M.Toggle then M.Toggle() end
  elseif lc == "sources" then
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > ") .. ". Installed: " .. table.concat(P.Installed(), ", "))
  elseif lc == "prefer" and P.byId[arg] then
    settings.sources = arg .. "," .. settings.sources
    settings.sources = table.concat(P.Order(settings.sources), ",")
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > "))
  elseif lc == "order" and arg ~= "" then
    settings.sources = table.concat(P.Order(arg), ",")
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > "))
  elseif lc == "tooltip" then settings.tooltip = not settings.tooltip; Core.Print("tooltip line " .. (settings.tooltip and "on" or "off"))
  elseif lc == "altclick" then settings.altClick = not settings.altClick; Core.Print("alt-click " .. (settings.altClick and "on" or "off"))
  elseif lc == "report" then
    Core.ShowReport({ "schema " .. tostring(db.schema), "recipes " .. #M.recipes, "price sources: " .. table.concat(P.Installed(), ", "),
      "order " .. settings.sources })
  elseif lc == "help" then
    Core.Print("/wcim [item, link or name] | sources | prefer <id> | order a,b,c | tooltip | altclick | report")
    Core.Print("source ids: pricelog, auctionator, tsm, auctioneer, scan")
  else
    local id = M.ParseItem(msg)
    if id and M.Open then M.Open(id) else Core.Print("no recipe uses '" .. msg .. "'. /wcim help") end
  end
end
