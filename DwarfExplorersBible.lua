-- Dwarf Explorer's Bible: pick a material, see everything it crafts into, what it's worth and where it goes next.
-- Inspired by the Guide in Terraria. Written from scratch (MIT). Reads data, never automates anything.
local ADDON, ns = ...
local C, Core, P, D = ns.Compat, ns.Core, ns.Prices, ns.Data
local M = {}
ns.RM = M
KennyDwarfExplorersBible = M

local SCHEMA = 4
-- filter* are the window's "Show only" boxes, remembered between sessions; only "My professions" starts ticked.
-- filterMakeNow = "Make now" (craftable from your bags + bank; makeNowAlts adds what your alts hold).
-- bestSkillUp sorts orange > yellow > green, cheapest per skill point.
local DEFAULTS = { sources = table.concat(P.DEFAULT_ORDER, ","), tooltip = true, altClick = true, ahCut = 0.05, chainDepth = 3,
  filterKnown = false, filterMine = true, filterPriced = false, filterMakeNow = false, makeNowAlts = false, bestSkillUp = false }
local db, settings, char, charKey
M.byReagent, M.byProduct, M.recipes, M.byCamp = {}, {}, {}, {}

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
  local product, mn, mx, prof, yellow, grey, spell, rg = row:match("^(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*)$")
  if not product then return nil end
  -- yellow/grey are the skill levels where the recipe turns yellow and grey in Forever's profession window.
  local r = { product = tonumber(product), min = tonumber(mn), max = tonumber(mx), prof = profs[tonumber(prof)] or "?",
    skill = tonumber(yellow), grey = tonumber(grey), spell = tonumber(spell), reagents = {}, origin = "data" }
  for id, n in rg:gmatch("(%d+):(%d+)") do r.reagents[#r.reagents + 1] = { id = tonumber(id), n = tonumber(n) } end
  return r
end

-- Camp action row: spellID;reagent:count;action;place[;can fail] (e.g. Plant Seeds at a Greenhouse). These use an
-- item up without crafting one, so they are listed apart from recipes. "can fail": Blizzard says the action can fail
-- (Hybridize Seeds since the Nov 19 hotfix; the chance isn't published).
function M.ParseCamp(row)
  local spell, id, n, action, rest = row:match("^(%d+);(%d+):(%d+);([^;]*);(.*)$")
  if not spell then return nil end
  local place, note = rest:match("^([^;]*);(.*)$")
  place = place or rest
  return { spell = tonumber(spell), id = tonumber(id), n = tonumber(n), action = action, place = place, canFail = note == "can fail" }
end

function M.BuildIndex()
  M.byReagent, M.byProduct, M.recipes, M.byCamp = {}, {}, {}, {}
  for _, row in ipairs(D.recipes) do local r = M.ParseRow(row, D.professions); if r then addRecipe(r) end end
  for _, row in ipairs(D.camp or {}) do
    local c = M.ParseCamp(row)
    if c then M.byCamp[c.id] = M.byCamp[c.id] or {}; table.insert(M.byCamp[c.id], c) end
  end
  -- Recipes you've learned that the bundled data doesn't have (new in Forever, or enchants).
  for _, r in pairs(db and db.extra or {}) do
    if type(r) == "table" and r.product and not M.byProduct[r.product] then r.origin = "scan"; addRecipe(r) end
  end
end

function M.Name(id)
  return C.GetItemName(id) or (D.names[id]) or (db and db.names[id]) or ("item " .. tostring(id))
end

-- Recipe products Blizzard keeps out of the client until release (shown under the recipe's name).
function M.IsHidden(id) return D.hidden ~= nil and D.hidden[id] == true end
-- Items or tool types a recipe needs in your bags (Blacksmith Hammer, Runed Golden Rod...).
function M.Tools(r) return r and r.spell and D.tools and D.tools[r.spell] or nil end
-- Copies of a potion that the client says can't be used in profession recipes.
function M.NoRecipe(id) return D.noRecipe ~= nil and D.noRecipe[id] == true end
-- Reagents Blizzard says a Forever vendor sells: the AH price should never be above the vendor's.
function M.VendorCapped(id) return D.vendorCap ~= nil and D.vendorCap[id] ~= nil end
function M.CampUses(id) return M.byCamp[id] end
-- One line per camp use: "Plant Seeds (1) at a Greenhouse".
function M.CampText(c)
  return ("%s (%d)%s%s"):format(c.action, c.n, c.place ~= "" and (" at a " .. c.place) or "", c.canFail and " (can fail)" or "")
end
-- Why an item no longer goes into a camp action it used to (e.g. Scarce Herb Seeds and the Seed Hybridizer).
function M.CampOff(id) return D.campOff and D.campOff[id] end

-- Known recipes ---------------------------------------------------------------------------
function M.Knows(r) return char ~= nil and char.learned[r.product] == true end
function M.Char() return char end
function M.CharKey() return charKey end
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
-- Both go through P.Resolve, the one price resolver (see Prices.lua).
function M.Resolve(id, side) return P.Resolve(id, side, settings and settings.sources) end
-- What an item fetches: price, label, sourceId, time (or nil).
function M.Price(id)
  local r = M.Resolve(id, "sell")
  if not r.price then return nil end
  return r.price, r.label, r.source, r.t
end

-- What a reagent costs you: a vendor that sells it (remembered or bundled), unless the AH is cheaper; a vendor-capped
-- reagent never costs more than the vendor price you have seen. Returns price, label.
function M.ReagentPrice(id)
  local r = M.Resolve(id, "buy")
  return r.price, r.label
end

local function older(a, b) if a == nil then return b end if b == nil then return a end return math.max(a, b) end

-- Crafts per item made: average of min/max, less the AH cut (what one craft brings you).
function M.CraftValue(r)
  local pr = M.Resolve(r.product, "sell")
  if not pr.price then return nil, nil end
  return math.floor(pr.price * (r.min + r.max) / 2 * (1 - (settings and settings.ahCut or 0.05))), pr.ageSeconds
end

-- { cost, value, profit, missing, incomplete, unpriced = { itemIDs }, ageSeconds }. cost = sum(reagent unit price x count);
-- value = product price x items made per craft less the AH cut. profit is nil unless every reagent AND the product
-- are priced, so a missing price never reads as 0g and never makes a recipe look more profitable than it is.
-- ageSeconds = age of the oldest price used (nil when no price has a known time).
function M.Profit(r)
  local cost, missing, unpriced, age = 0, false, {}, nil
  for _, g in ipairs(r.reagents) do
    local rp = M.Resolve(g.id, "buy")
    if rp.price then cost = cost + rp.price * g.n; age = older(age, rp.ageSeconds)
    else missing = true; unpriced[#unpriced + 1] = g.id end
  end
  local value, vAge = M.CraftValue(r)
  age = older(age, vAge)
  if not value then missing = true; unpriced[#unpriced + 1] = r.product end
  local profit = (value and not missing) and (value - cost) or nil
  return { cost = cost, value = value, profit = profit, missing = missing, incomplete = missing, unpriced = unpriced, ageSeconds = age }
end

-- Buy-all vs mats-in-bags, for one craft. buyAll = every reagent bought; withBags = only what your bags + bank
-- don't cover (out of pocket). owned = reagent units you already hold toward this craft. single = true when you
-- own none (show one line). A reagent you must buy with no known price makes that line incomplete (profit nil).
function M.ProfitLines(r)
  local base = M.Profit(r)
  local I = ns.Inventory
  local oop, oopMissing, owned = 0, false, 0
  for _, g in ipairs(r.reagents) do
    local have = I and I.Count(g.id).mine or 0
    local use = math.min(have, g.n)
    owned = owned + use
    local buy = g.n - use
    if buy > 0 then
      local rp = M.Resolve(g.id, "buy")
      if rp.price then oop = oop + rp.price * buy else oopMissing = true end
    end
  end
  local value = base.value
  local withIncomplete = oopMissing or value == nil
  return {
    value = value, owned = owned, single = owned == 0, ageSeconds = base.ageSeconds, unpriced = base.unpriced,
    incomplete = base.incomplete,
    buyAll = { cost = base.cost, profit = base.profit, incomplete = base.incomplete },
    withBags = { cost = oop, profit = (not withIncomplete) and (value - oop) or nil, incomplete = withIncomplete },
  }
end

-- Recipe difficulty for your skill, the way the profession window colours it.
function M.Difficulty(r)
  local s = M.Skill(r.prof)
  if not (s and r.skill and r.grey and r.grey > 0) then return nil end
  if s < r.skill then return "orange" end
  if s < (r.skill + r.grey) / 2 then return "yellow" end
  if s < r.grey then return "green" end
  return "grey"
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

-- True when text starts one of the words in name ("copp" matches "Handful of Copper Bolts", "opper" doesn't).
-- Both are lower case. A word starts after anything that isn't a letter, digit or apostrophe.
function M.WordStartMatch(name, text)
  local init = 1
  while true do
    local i = name:find(text, init, true)
    if not i then return false end
    if i == 1 or not name:sub(i - 1, i - 1):match("[%w']") then return true end
    init = i + 1
  end
end

-- Item ids with a word starting with text (case-insensitive) that are used in, made by or used up by a recipe or
-- camp action. An exact name match comes first, then most uses.
function M.Search(text, limit)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local out, exact = {}, {}
  if text == "" then return out end
  local function try(id, name)
    if not name or not (M.byReagent[id] or M.byProduct[id] or M.byCamp[id]) then return end
    local lname = name:lower()
    if M.WordStartMatch(lname, text) then out[#out + 1] = id; exact[id] = lname == text end
  end
  for id, name in pairs(D.names) do try(id, name) end
  for id, name in pairs(db and db.names or {}) do if not D.names[id] then try(id, name) end end
  table.sort(out, function(a, b)
    if exact[a] ~= exact[b] then return exact[a] end
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

-- "Show only" filters ------------------------------------------------------------------------
-- Your professions are the ones the addon has seen in your profession windows.
function M.HasProfessions() return char ~= nil and next(char.skills) ~= nil end
function M.MyProfession(r) return char ~= nil and char.skills[r.prof] ~= nil end

-- Keeps the entries ({ r, pr }) that pass the ticked filters. Until you've opened a profession window there is
-- nothing to match "My professions" against, so that box lets everything through.
function M.FilterList(list, f)
  f = f or settings
  local mine = f.filterMine and M.HasProfessions()
  local out = {}
  local PL = ns.Planner
  for _, e in ipairs(list) do
    if (not f.filterKnown or M.Knows(e.r)) and (not mine or M.MyProfession(e.r)) and (not f.filterPriced or e.pr.profit ~= nil)
      and (not f.filterMakeNow or (PL and PL.MaxCrafts(e.r, f.makeNowAlts) > 0)) then
      out[#out + 1] = e
    end
  end
  if f.bestSkillUp and PL then PL.SortSkillUp(out) end
  return out
end

-- The most profitable recipe that uses itemID (unpriced ones only when nothing is priced), or nil.
function M.BestNext(itemID)
  local list = M.UsesOf(itemID)
  return list[1]
end

function M.CountKeys(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

function M.Settings() return settings end
function M.DB() return db end

-- Tooltip lines ----------------------------------------------------------------------------
-- Compact by default: line 1 what the item is for (and its best use), line 2 what you hold and what it's worth, then
-- at most one vendor line and one "here" line (bright green when it's in your zone), and a quiet Shift hint. Hold
-- Shift for the full breakdown: price age, alts holding it, best recipes, what it's made from, every remembered
-- vendor, the nearest spot, which alts can craft it, and the alt-click hint.
local function shiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end
local HERE = { 0.45, 1.0, 0.50 }
local GOLDC = { 1, 0.82, 0 }

function M.HaveText(have)
  if not have or have.mine <= 0 then return nil end
  return ("You have %d (%d bags, %d bank)"):format(have.mine, have.bags, have.bank)
end

-- The most profitable use, cached (it prices every recipe that uses the item).
function M.BestUse(itemID)
  local K = ns.Cache
  local function build() return M.UsesOf(itemID)[1] or false end
  local best = K and K.Get("bestuse." .. tostring(itemID), build) or build()
  return best or nil
end

-- One vendor line: the remembered merchant in your zone first (green), else the nearest one (gold). Returns
-- text, isHere, the full vendor list.
function M.VendorTipLine(itemID)
  local V = ns.Vendors
  if not V then return nil, false, {} end
  local list = V.GetVendorsForItem(itemID)
  local v
  for _, x in ipairs(list) do if not x.limited then v = x break end end
  v = v or list[1]
  if not v then return nil, false, list end
  local where = v.subzone and (v.subzone .. ", " .. v.zone) or v.zone
  return ("%s: %s (%s) — %s%s"):format(v.inZone and "Vendor here" or "Vendor", v.npc, where, C.Money(v.price), v.limited and " (limited stock)" or ""),
    v.inZone == true and not v.limited, list
end

-- "Farm here: <zone> (<mob>, <rate>%)" / "Mine here: <zone>" when it's found in your zone, else nil (vendors have their own line).
function M.HereTipLine(itemID)
  local W = ns.Where
  local t = W and W.TooltipText(itemID)
  if t and t:find("^%a+ here: ") and not t:find("^Vendor here") then return t end
  return nil
end

local function addLines(tooltip, itemID, expanded)
  local uses = M.byReagent[itemID]
  local made = M.byProduct[itemID]
  local camp = M.byCamp[itemID]
  local I = ns.Inventory
  if expanded == nil then expanded = shiftDown() end
  if M.NoRecipe(itemID) then tooltip:AddLine("This copy can't be used in recipes (Dwarf Explorer's Bible)", 1, 0.45, 0.45) end
  local campOff = M.CampOff(itemID)
  if not uses and not made and not camp and not campOff then return end
  -- Line 1: what it's for, and its best use.
  local what = {}
  if uses then
    local best = M.BestUse(itemID)
    local bestText = best and best.pr.profit and best.pr.profit > 0 and (", best " .. M.Name(best.r.product) .. " +" .. C.Money(best.pr.profit)) or ""
    what[#what + 1] = ("Used in %d recipe%s%s (Dwarf Explorer's Bible)"):format(#uses, #uses == 1 and "" or "s", bestText)
  end
  if camp then
    local parts = {}
    for _, c in ipairs(camp) do parts[#parts + 1] = M.CampText(c) end
    what[#what + 1] = "Camp: " .. table.concat(parts, ", ")
  end
  if campOff then what[#what + 1] = campOff end
  if #what == 0 then what[1] = "Made by a recipe (Dwarf Explorer's Bible)" end
  tooltip:AddLine(table.concat(what, " · "), 0.4, 0.8, 1, true)
  -- Line 2: what you hold and what it's worth.
  local worth = {}
  local have = I and I.Count(itemID)
  worth[#worth + 1] = M.HaveText(have)
  -- MatTooltip already shows an AH price on every trade good: don't show a second one.
  local mt = type(_G["KennyMatTooltip"]) == "table" and _G["KennyMatTooltip"]
  local mtShows = mt and mt.IsMat and mt.Settings and (mt.Settings() or {}).enabled and mt.IsMat(itemID)
  if M.VendorCapped(itemID) then
    local cap = P.Cap(itemID)
    worth[#worth + 1] = "Sold by a vendor in Forever: don't pay more at the AH" .. (cap and (" (" .. C.Money(cap) .. ")") or "")
  end
  local sell = M.Resolve(itemID, "sell")
  if sell.price and not mtShows then worth[#worth + 1] = "AH " .. C.Money(sell.price) .. " (" .. sell.label .. ")" end
  if #worth > 0 then tooltip:AddLine(table.concat(worth, " · "), 0.85, 0.85, 0.85, true) end
  -- Optional cues: one vendor line, one "here" line.
  local vline, vhere, vendors = M.VendorTipLine(itemID)
  if vline then local c = vhere and HERE or GOLDC; tooltip:AddLine(vline, c[1], c[2], c[3], true) end
  local here = M.HereTipLine(itemID)
  if here then tooltip:AddLine(here, HERE[1], HERE[2], HERE[3], true) end
  local alts = false
  for _, h in ipairs(have and have.holders or {}) do if not h.isMe then alts = true end end
  local more = (uses and #uses > 0) or made ~= nil or #vendors > 1 or alts or (sell.price and sell.ageSeconds)
  if not expanded then
    if more then tooltip:AddLine("Hold Shift for full crafting breakdown", 0.5, 0.5, 0.5) end
    return
  end
  if sell.price and sell.ageSeconds then tooltip:AddLine("  price seen " .. M.Ago(sell.ageSeconds) .. " ago", 0.6, 0.6, 0.6) end
  if have then
    for _, h in ipairs(have.holders) do
      if not h.isMe then tooltip:AddLine(("  %s: %d (%d bags, %d bank)"):format(h.name, h.bags + h.bank, h.bags, h.bank), 0.6, 0.8, 0.6) end
    end
  end
  if uses and #uses > 0 then
    local list = M.UsesOf(itemID)
    tooltip:AddLine("Best uses:", 1, 0.82, 0)
    for i = 1, math.min(5, #list) do
      local e = list[i]
      local p = e.pr.profit
      tooltip:AddDoubleLine("  " .. M.Name(e.r.product), p and ((p >= 0 and "+" or "-") .. C.Money(math.abs(p))) or "no price",
        1, 1, 1, p and (p >= 0 and 0.2 or 1) or 0.6, p and (p >= 0 and 1 or 0.4) or 0.6, p and (p >= 0 and 0.2 or 0.4) or 0.6)
    end
    if #list > 5 then tooltip:AddLine(("  +%d more"):format(#list - 5), 0.6, 0.6, 0.6) end
  end
  if made and made[1] then
    local r = made[1]
    local parts = {}
    for _, g in ipairs(r.reagents) do parts[#parts + 1] = g.n .. " " .. M.Name(g.id) end
    tooltip:AddLine("Made from: " .. table.concat(parts, ", ") .. " (" .. r.prof .. ((r.skill or 0) > 0 and (" " .. r.skill) or "") .. ")", 0.85, 0.85, 0.85, true)
    local A = ns.Alts
    local n = 0
    for _, row in ipairs(A and A.WhoCanCraft(r) or {}) do
      if not row.isMe and n < 2 then n = n + 1; tooltip:AddLine("  " .. A.CraftText(row), 0.6, 0.8, 0.6) end
    end
  end
  if #vendors > 0 then
    tooltip:AddLine("Vendors you've seen:", 1, 0.82, 0)
    for i = 1, math.min(5, #vendors) do
      local v = vendors[i]
      tooltip:AddDoubleLine("  " .. v.npc .. " (" .. (v.subzone and (v.subzone .. ", " .. v.zone) or v.zone) .. ")",
        C.Money(v.price) .. (v.limited and " (limited)" or ""), 0.9, 0.9, 0.9, 1, 1, 1)
    end
    if #vendors > 5 then tooltip:AddLine(("  +%d more"):format(#vendors - 5), 0.6, 0.6, 0.6) end
  end
  if not here and ns.Where then
    local t = ns.Where.TooltipText(itemID)
    if t and t:find("^Nearest: ") then tooltip:AddLine(t, 0.85, 0.85, 0.85, true) end
  end
  if (uses or camp) and settings.altClick then tooltip:AddLine("  Alt-click: what can I make?", 0.5, 0.5, 0.5) end
end
M.AddTooltipLines = addLines

local tipDone, tipHooked = setmetatable({}, { __mode = "k" }), {}
local function OnItemTooltip(tooltip, data)
  if not db or not settings.tooltip or not data then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local itemID = C.SafeNumber(data.id)
  -- The post-call can run more than once for one tooltip build (e.g. a recipe and the item it makes, or a
  -- refresh); add our lines once per item per build. Kept in our own weak table, never on Blizzard's frame.
  local done = tipDone[tooltip]
  if itemID and done and done[itemID] then return end
  if itemID then
    if not done then
      done = {}; tipDone[tooltip] = done
      if not tipHooked[tooltip] and tooltip.HookScript then
        tipHooked[tooltip] = true
        tooltip:HookScript("OnTooltipCleared", function(t) tipDone[t] = nil end)
      end
    end
    done[itemID] = true Core.SafeCall("tooltip", addLines, tooltip, itemID) end
end

-- Events ---------------------------------------------------------------------------------
local migrations = {
  [1] = function(d) d.chars = d.chars or {}; d.extra = d.extra or {}; d.names = d.names or {}; d.cache = d.cache or {} end,
  -- 1.2.0: trade-goods drops learned from your own kills (see Drops.lua).
  [2] = function(d) d.drops = d.drops or {}; d.dropKills = d.dropKills or {}; d.mobNames = d.mobNames or {}; d.dropDone = d.dropDone or {} end,
  -- Drop sharing: imported/synced snapshots, kept apart from your own kills (see DropShare.lua).
  [3] = function(d) d.dropShares = d.dropShares or {} end,
  -- 1.3.0: per-character records move to alts (known recipes, skills, bag/bank counts); new namespaced sub-tables.
  [4] = function(d)
    d.alts = d.alts or {}
    for key, c in pairs(d.chars or {}) do
      if type(c) == "table" and not d.alts[key] then
        -- key = "Realm-Faction-Name" (the realm may itself contain "-")
        local realm, faction, name = tostring(key):match("^(.-)%-([^%-]+)%-([^%-]+)$")
        d.alts[key] = { learned = c.learned or {}, skills = c.skills or {}, name = name, realm = realm, faction = faction }
      end
    end
    d.chars = nil
    d.vendors, d.shopping = d.vendors or {}, d.shopping or {}
  end,
}

-- Small shared time formats: Ago(754) = "12m", Duration(1120) = "18m 40s".
function M.Ago(sec)
  sec = math.max(0, math.floor(C.SafeNumber(sec) or 0))
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return math.floor(sec / 60) .. "m" end
  if sec < 86400 then return math.floor(sec / 3600) .. "h" end
  return math.floor(sec / 86400) .. "d"
end
function M.Duration(sec)
  sec = math.max(0, math.floor(C.SafeNumber(sec) or 0))
  if sec >= 3600 then return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60) end
  return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60)
end

-- Modules (Inventory, Alts, Vendors, Shopping, Seeds) add themselves here; Init attaches each.
M.modules = {}
function M.AddModule(mod) M.modules[#M.modules + 1] = mod end

function M.Init()
  db = Core.Migrate(KennyDwarfExplorersBibleDB, migrations, SCHEMA)
  db.alts, db.extra, db.names, db.cache = db.alts or {}, db.extra or {}, db.names or {}, db.cache or {}
  KennyDwarfExplorersBibleDB = db
  settings = Core.Settings(db.settings, DEFAULTS)
  local name = tostring(UnitName and C.Safe(UnitName("player")) or "?")
  local key = C.RealmFaction() .. "-" .. name
  db.alts[key] = db.alts[key] or { learned = {}, skills = {} }
  char, charKey = db.alts[key], key
  char.learned, char.skills = char.learned or {}, char.skills or {}
  char.name = name
  char.realm = tostring(GetRealmName and C.Safe(GetRealmName()) or "realm")
  char.faction = tostring(UnitFactionGroup and C.Safe(UnitFactionGroup("player")) or "faction")
  char.seen = C.Now()
  local rk = C.RealmFaction()
  db.cache[rk] = db.cache[rk] or {}
  P.cache = db.cache[rk]
  db.vendor = db.vendor or {}
  P.vendorCache = db.vendor
  db.vendorCap = db.vendorCap or {}
  P.capCache = db.vendorCap
  M.BuildIndex()
  if ns.Drops then ns.Drops.Attach(db) end
  for _, mod in ipairs(M.modules) do Core.SafeCall("attach", mod.Attach, db, char, charKey) end
  if ns.Cache then ns.Cache.Reset() end
end

local f = CreateFrame("Frame")
local scanPending = false
local function queueScan()
  -- TRADE_SKILL_LIST_UPDATE fires on every filter/search change; scan at most once per half second.
  if scanPending then return end
  scanPending = true
  local function run() scanPending = false; if not C.InCombat() then Core.SafeCall("tradeskill", M.ScanTradeSkill) end end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
M.QueueScan = queueScan
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    f:UnregisterEvent("ADDON_LOADED")
    M.Init()
  elseif event == "MERCHANT_SHOW" then
    Core.SafeCall("merchant", function()
      local rows = P.MerchantRows()
      P.ReadMerchant(rows)
      if ns.Vendors then ns.Vendors.Record(rows) end
    end)
  elseif event == "AUCTION_HOUSE_SHOW" then P.ahOpen = true
  elseif event == "AUCTION_HOUSE_CLOSED" then P.ahOpen = false; if ns.Cache then ns.Cache.Bump() end
  elseif event == "PLAYER_LOGIN" then
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
    if hooksecurefunc and HandleModifiedItemClick then
      hooksecurefunc("HandleModifiedItemClick", function(link)
        if settings.altClick and IsAltKeyDown and IsAltKeyDown() and type(link) == "string" then
          local id = tonumber(link:match("item:(%d+)"))
          if id and (M.byReagent[id] or M.byProduct[id] or M.byCamp[id]) and M.Open then M.Open(id) end
        end
      end)
    end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    queueScan()
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if C.InCombat() then return end
    Core.SafeCall("browse", function()
      local rows = C.AHBrowse()
      for _, r in ipairs(rows) do P.Remember(r.itemID, r.price, C.Now()) end
    end)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if C.InCombat() then return end
    local id = C.SafeNumber(arg1)
    Core.SafeCall("commodity", function()
      if not id then return end
      local minP
      for _, r in ipairs(C.AHCommodity(id)) do if not minP or r.price < minP then minP = r.price end end
      if minP then P.Remember(id, minP, C.Now()) end
    end)
  end
end)

-- Slash ---------------------------------------------------------------------------------
SLASH_KENNYDWARFEXPLORERSBIBLE1 = "/deb"
SLASH_KENNYDWARFEXPLORERSBIBLE2 = "/craftguide"
SlashCmdList.KENNYDWARFEXPLORERSBIBLE = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  local lc = cmd:lower()
  if not settings then return end
  local Nav = ns.Nav
  if lc == "" then if M.Toggle then M.Toggle() end
  elseif Nav and Nav.SLASH[lc] then Nav.Slash(lc, arg)
  elseif lc == "sources" then
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > ") .. ". Installed: " .. table.concat(P.Installed(), ", "))
  elseif lc == "prefer" and P.byId[arg:lower()] then
    arg = arg:lower()
    settings.sources = arg .. "," .. settings.sources
    settings.sources = table.concat(P.Order(settings.sources), ",")
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > "))
  elseif lc == "prefer" then
    Core.Print("unknown source '" .. arg .. "'. Source ids: pricelog, auctionator, tsm, auctioneer, scan, baseline")
  elseif lc == "order" and arg ~= "" then
    settings.sources = table.concat(P.Order(arg), ",")
    Core.Print("price order: " .. table.concat(P.Order(settings.sources), " > "))
  elseif lc == "tooltip" then settings.tooltip = not settings.tooltip; Core.Print("tooltip line " .. (settings.tooltip and "on" or "off"))
  elseif lc == "altclick" then settings.altClick = not settings.altClick; Core.Print("alt-click " .. (settings.altClick and "on" or "off"))
  elseif lc == "export" then
    if ns.DropShare then ns.DropShare.OpenExport() end
  elseif lc == "import" then
    if ns.DropShare then ns.DropShare.OpenImport() end
  elseif lc == "report" then
    Core.ShowReport({ "schema " .. tostring(db.schema), "recipes " .. #M.recipes .. " (data " .. tostring(D.build) .. ")", "price sources: " .. table.concat(P.Installed(), ", "), "mobs with learned drops: " .. M.CountKeys(db.drops),
      "shared drop sources: " .. M.CountKeys(db.dropShares), "order " .. settings.sources,
      "characters " .. M.CountKeys(db.alts), "vendors " .. M.CountKeys(db.vendors.list), "shopping " .. M.CountKeys(db.shopping.items) })
  elseif lc == "help" then
    Core.Print("/deb [item, link or name] | materials | shop | seeds | alts | sources | prefer <id> | order a,b,c | tooltip | altclick | export | import | report")
    Core.Print("source ids: pricelog, auctionator, tsm, auctioneer, scan, baseline (always last)")
  else
    local id = M.ParseItem(msg)
    if id and M.Open then M.Open(id) else Core.Print("no recipe uses '" .. msg .. "'. /deb help") end
  end
end
