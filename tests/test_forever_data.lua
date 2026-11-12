-- Checks the bundled Forever data (client tables + server hotfixes) and the 1.1.0 tooltip/price additions.
-- Expected values come from Forever's client DB2 tables and wago.tools hotfix rows for build 70888.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.installLDB()
local tipLines = {}
GameTooltip = M.frameObj("GameTooltip")
rawset(GameTooltip, "AddLine", function(_, t) tipLines[#tipLines + 1] = t end)
rawset(GameTooltip, "AddDoubleLine", function(_, a, b) tipLines[#tipLines + 1] = a .. " = " .. b end)
UISpecialFrames, tinsert = {}, table.insert
GetMoneyString = function(c) return c .. "c" end
local postCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCalls[#postCalls + 1] = fn end }
Enum = { TooltipDataType = { Item = 0 } }
hooksecurefunc = function() end

local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
local RM, P, D = ns.RM, ns.Prices, ns.Data

local function bySpell(spell)
  for _, r in ipairs(RM.recipes) do if r.spell == spell then return r end end
end
local function reagentsOf(r)
  local t = {}
  for _, g in ipairs(r.reagents) do t[g.id] = g.n end
  return t
end
local function tooltipFor(id)
  tipLines = {}
  GameTooltip.OnTooltipCleared = nil
  RM.AddTooltipLines(GameTooltip, id)
  return table.concat(tipLines, "\n")
end

M.check(D.build == "1.60.1.70888", "data stamped with its client build")
M.check(#RM.recipes == 2090, "2,090 bundled recipes (1,971 in 1.0.5): " .. #RM.recipes)

-- 1. Herbalism, Skinning and Fishing camp crafts (skill levels after the hotfix).
local camp = {
  { 1229705, "Herbalism", 20, 20, { [2447] = 1, [765] = 1 } },                -- Incense Candle: Peacebloom, Silverleaf
  { 1262980, "Herbalism", 140, 140, { [4470] = 2, [8836] = 1, [8831] = 1 } }, -- Greenhouse: Simple Wood, Arthas' Tears, Purple Lotus
  { 1263070, "Herbalism", 300, 300, { [13465] = 4, [8925] = 1, [14047] = 2 } }, -- Seed Hybridizer: Mountain Silversage, Crystal Vial, Runecloth
  { 1229517, "Skinning", 20, 20, { [2318] = 3, [4470] = 2 } },                -- Camp Chair: Light Leather, Simple Wood
  { 1262985, "Skinning", 140, 140, { [2319] = 3, [5784] = 2, [2321] = 1 } },  -- Field Guide: Medium Leather, Slimy Murloc Scale, Fine Thread
  { 1262982, "Skinning", 300, 300, { [4470] = 2, [4234] = 4, [3575] = 1 } },  -- Trapper's Workbench: Simple Wood, Heavy Leather, Iron Bar
  { 1229745, "Fishing", 20, 20, { [6291] = 1, [3371] = 1 } },                 -- Fish Bowl: Raw Brilliant Smallfish, Empty Vial
  { 1262990, "Fishing", 140, 140, { [4470] = 2, [8925] = 1, [8365] = 2 } },   -- Fishing Rack: Simple Wood, Crystal Vial, Raw Mithril Head Trout
  { 1262998, "Fishing", 300, 300, { [4470] = 5, [14048] = 2, [273295] = 1 } }, -- Fishing Hut: Simple Wood, Bolt of Runecloth, Seasonal Fish Steaks
}
for _, c in ipairs(camp) do
  local r = bySpell(c[1])
  local ok = r and r.prof == c[2] and r.skill == c[3] and r.grey == c[4]
  if ok then for id, n in pairs(c[5]) do if reagentsOf(r)[id] ~= n then ok = false end end end
  M.check(ok, "camp craft " .. c[1] .. " (" .. c[2] .. ") with hotfixed skill and its reagents")
end
local herb = 0
for _, r in ipairs(RM.UsesOf(2447)) do if r.r.prof == "Herbalism" then herb = herb + 1 end end
M.check(herb == 1, "Peacebloom now lists the Incense Candle")

-- 2. Herb seeds: Greenhouse and Seed Hybridizer uses instead of 'used in 0 recipes'.
local seeds = RM.CampUses(268415)
M.check(seeds and #seeds == 2, "Commonplace Herb Seeds have two camp uses")
local plant, hyb
for _, c in ipairs(seeds or {}) do
  if c.action == "Plant Seeds" then plant = c elseif c.action == "Hybridize Seeds" then hyb = c end
end
M.check(plant and plant.n == 1 and plant.place == "Greenhouse", "plant 1 seed at a Greenhouse")
M.check(hyb and hyb.n == 2 and hyb.place == "Seed Hybridizer", "hybridize 2 seeds at a Seed Hybridizer")
for _, id in ipairs({ 268416, 268417, 268418 }) do M.check(RM.CampUses(id) and #RM.CampUses(id) == 2, "seed " .. id .. " camp uses") end
M.check(RM.CampUses(268419) == nil, "fifth seed tier (item still hidden) left out")
local tip = tooltipFor(268415)
M.check(tip:find("Camp: Plant Seeds (1) at a Greenhouse, Hybridize Seeds (2) at a Seed Hybridizer", 1, true), "seed tooltip names both camp uses")
M.check(not tip:find("Used in", 1, true), "seeds aren't counted as recipes")
M.check(RM.Search("herb seeds")[1] ~= nil and RM.ParseItem("commonplace herb seeds") == 268415, "seeds can be searched")

-- 3. Recipes whose product isn't in the client's item table: Blizzard reveals most of them through ItemSparse
-- hotfixes (named from those); the rest stay listed under the recipe's name and flagged hidden.
local stompers = bySpell(1292924)
M.check(stompers and stompers.product == 273887 and RM.Name(273887) == "Grovekeeper Stompers" and not RM.IsHidden(273887),
  "Grovekeeper Stompers back in, named from its hotfix item record")
M.check(reagentsOf(stompers)[248825] == 18, "Grovekeeper Stompers use 18 Fel Leather")
local tier = 0
for _, e in ipairs(RM.UsesOf(248825)) do
  if e.r.prof == "Leatherworking" and e.r.spell >= 1292920 and e.r.spell <= 1292976 then tier = tier + 1 end
end
M.check(tier == 32, "Fel Leather feeds the 32 Artisan's Tier Leatherworking pieces: " .. tier)
local rd = bySpell(1250775)
M.check(rd and rd.prof == "Alchemy" and reagentsOf(rd)[3818] == 3 and reagentsOf(rd)[3358] == 1, "Revealing Draught: 3 Fadeleaf + 1 Khadgar's Whisker")
M.check(RM.IsHidden(250326) and RM.Name(250326) == "Revealing Draught", "Revealing Draught still hidden, named by its recipe")
local stew = bySpell(1255241)
M.check(stew and reagentsOf(stew)[252948] and RM.Name(252948) == "Cleansed Felbloom", "Cleansing Stew back in (its reagent revealed by hotfix)")
local hidden = 0
for _ in pairs(D.hidden) do hidden = hidden + 1 end
M.check(hidden == 12, "12 recipes still hidden in the client: " .. hidden)
M.check(bySpell(1213709) == nil, "leftover Season of Discovery recipes stay out")

-- 4. Skill levels from the server hotfixes.
local tr = bySpell(1263031)
M.check(tr and tr.skill == 125 and tr.grey == 125, "Tanning Rack 125/125 (was 140/145)")
M.check(bySpell(3326).grey == 90, "Coarse Grinding Stone gives skill-ups to 90 (was 75)")
M.check(bySpell(1283400).skill == 95 and bySpell(1283400).grey == 95, "Journeyman Campfire 95/95")
M.check(bySpell(1291341).grey == 205, "Expert Campfire grey at 205")
M.check(bySpell(1229432).grey == 20, "Camp Tent grey at 20")

-- 5. Tailoring bags after the Nov 11 hotfix.
M.check(reagentsOf(bySpell(12079))[4339] == 5, "Red Mageweave Bag: 5 Bolt of Mageweave")
M.check(reagentsOf(bySpell(6693))[4305] == 5 and reagentsOf(bySpell(6693))[4234] == 3, "Green Silk Pack: 5 Bolt of Silk, 3 Heavy Leather")
M.check(reagentsOf(bySpell(6695))[4305] == 6, "Black Silk Pack: 6 Bolt of Silk")
M.check(reagentsOf(bySpell(3758))[2997] == 5, "Green Woolen Bag: 5 Bolt of Woolen Cloth")
M.check(reagentsOf(bySpell(6688))[2997] == 5, "Red Woolen Bag: 5 Bolt of Woolen Cloth")

-- 6. Poisons and Comprehension.
local poisons = 0
for _, r in ipairs(RM.recipes) do if r.prof == "Poisons" then poisons = poisons + 1 end end
M.check(poisons == 26, "26 Poisons recipes")
local bp = bySpell(6510)
M.check(bp and bp.prof == "Poisons" and reagentsOf(bp)[3818], "Blinding Powder uses Fadeleaf")
local study = bySpell(1302508)
M.check(study and study.prof == "Comprehension" and reagentsOf(study)[17056] == 1, "Study (Comprehension): 1 Light Feather")

-- 7. Vendor-capped reagents: Black Lotus.
M.check(RM.VendorCapped(13468), "Black Lotus is flagged as vendor-sold in Forever")
tip = tooltipFor(13468)
M.check(tip:find("Sold by a vendor in Forever", 1, true), "Black Lotus tooltip says a vendor sells it")
C_AuctionHouse = { GetBrowseResults = function() return { { itemKey = { itemID = 13468 }, minPrice = 90000, totalQuantity = 2 } } end }
M.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
M.check(RM.ReagentPrice(13468) == 90000, "no vendor price seen yet: AH price")
GetMerchantNumItems = function() return 2 end
GetMerchantItemID = function(i) return ({ 13468, 3818 })[i] end
C_MerchantFrame = { GetItemInfo = function(i)
  if i == 1 then return { price = 40000, stackCount = 1, numAvailable = 3 } end
  return { price = 50, stackCount = 1, numAvailable = 2 } end }
M.fire("MERCHANT_SHOW")
local cp, cl = RM.ReagentPrice(13468)
M.check(cp == 40000 and cl == "vendor cap", "limited-stock vendor price caps Black Lotus' cost")
M.check(P.vendorCache[3818] == nil and P.Cap(3818) == nil, "other limited-stock items still ignored")
M.check(tooltipFor(13468):find("(40000c)", 1, true), "tooltip shows the vendor price once seen")

-- 8. Potion copies that can't be used in recipes.
for _, id in ipairs({ 287966, 287967, 287968, 287969, 287975, 287976, 287977 }) do
  M.check(RM.NoRecipe(id) and tooltipFor(id):find("can't be used in recipes", 1, true), "no-recipe copy " .. id .. " warned")
end
M.check(not RM.NoRecipe(3385) and not tooltipFor(3385):find("can't be used", 1, true), "the real Lesser Mana Potion isn't warned")

-- 11. Tools a recipe needs.
local salv = RM.Tools(bySpell(1263056))
M.check(salv and table.concat(salv, ","):find("Runed Golden Rod", 1, true), "Arcane Salvager needs a Runed Golden Rod (Nov 10 hotfix)")
M.done("Forever data")
