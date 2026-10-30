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
local hooks = {}
hooksecurefunc = function(name, fn) hooks[name] = fn end
HandleModifiedItemClick = function() end
local alt = false
IsAltKeyDown = function() return alt end

-- Profession window mock (C_TradeSkillUI, Forever 16001 docs): you know Linen Bandage (1251).
local linked = false
C_TradeSkillUI = {
  GetFilteredRecipeIDs = function() return { 3275, 99001 } end,
  GetRecipeInfo = function() return { learned = true } end,
  IsTradeSkillLinked = function() return linked end,
  GetRecipeSchematic = function(id)
    if id == 3275 then return { outputItemID = 1251, quantityMin = 1, quantityMax = 1, name = "Linen Bandage", reagentSlotSchematics = {} } end
    return { outputItemID = 990001, quantityMin = 1, quantityMax = 1, name = "Forever Gizmo",
      reagentSlotSchematics = { { required = true, quantityRequired = 2, reagents = { { itemID = 2589 } } } } }
  end,
  GetProfessionInfoByRecipeID = function() return { professionName = "First Aid", skillLevel = 40 } end,
}

local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
local RM, P = ns.RM, ns.Prices
M.check(#RM.recipes > 1000, "bundled recipes loaded: " .. #RM.recipes)
M.check(#postCalls == 1 and hooks.HandleModifiedItemClick, "tooltip and alt-click hooked")
M.check(M.ldbObjects.DwarfExplorersBible and M.ldbObjects.DwarfExplorersBible.type == "launcher", "LDB launcher")

-- Linen Cloth (2589) is used in Linen Bandage (1251) and Bolt of Linen Cloth (2996).
local uses = RM.UsesOf(2589)
local found = {}
for _, e in ipairs(uses) do found[e.r.product] = e end
M.check(found[1251] and found[2996], "linen cloth -> bandage and bolt")
M.check(found[1251].r.prof == "First Aid", "profession on the recipe")

-- Learned scan (debounced: a burst of list updates scans once)
local scans = 0
local orig = C_TradeSkillUI.GetFilteredRecipeIDs
C_TradeSkillUI.GetFilteredRecipeIDs = function() scans = scans + 1; return orig() end
M.fire("TRADE_SKILL_SHOW"); M.fire("TRADE_SKILL_LIST_UPDATE"); M.fire("TRADE_SKILL_LIST_UPDATE")
M.advance(1)
M.check(scans == 1, "profession scan debounced to one per burst")
M.check(RM.Knows(found[1251].r), "bandage known after profession scan")
M.check(not RM.Knows(found[2996].r), "bolt not known")
M.check(RM.Skill("First Aid") == 40, "skill level stored")
M.check(RM.Difficulty(found[1251].r) == "yellow", "difficulty from Forever's yellow/grey levels (30/60, you 40)")
M.check(RM.byProduct[990001] and RM.byProduct[990001][1].origin == "scan", "recipe missing from data added from your own window")
linked = true
KennyDwarfExplorersBibleDB.chars["TestRealm-Horde-Kenny"].learned[2996] = nil
C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 1 } end
C_TradeSkillUI.GetRecipeSchematic = function() return { outputItemID = 2996, reagentSlotSchematics = {} } end
M.fire("TRADE_SKILL_SHOW"); M.advance(1)
M.check(not RM.Knows(found[2996].r), "linked profession windows are ignored")
linked = false

-- Price sources: nothing installed -> scan cache only.
M.check(RM.Price(2589) == nil, "no price yet")
C_AuctionHouse = { GetBrowseResults = function() return { { itemKey = { itemID = 2589 }, minPrice = 25, totalQuantity = 40 } } end }
M.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
local p, label, id = RM.Price(2589)
M.check(p == 25 and id == "scan" and label == "Dwarf Explorer's Bible scan", "scan cache from your own AH browse")
C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
C_AuctionHouse.GetCommoditySearchResultInfo = function() return { unitPrice = 900, quantity = 3 } end
M.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2996)
M.check(RM.Price(2996) == 900, "commodity search cached")

-- Auctionator (API v1)
local callers = {}
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, item) callers[#callers + 1] = caller
  if item == 2589 then return 30 end end } } }
p, label = RM.Price(2589)
M.check(p == 30 and label == "Auctionator" and callers[1] == "Dwarf Explorer's Bible", "Auctionator source")
-- TSM
TSM_API = { GetCustomPriceValue = function(str, item) if item == "i:2589" and str == "DBMarket" then return 31 end
  if item == "i:2996" and str == "DBMinBuyout" then return 950 end end }
SlashCmdList.KENNYDWARFEXPLORERSBIBLE("prefer tsm")
p, label = RM.Price(2589)
M.check(p == 31 and label == "TSM", "TSM DBMarket preferred")
M.check(RM.Price(2996) == 950, "TSM falls back to DBMinBuyout")
-- Auctioneer
-- GetMarketValue must get the numeric id: a bare "item:N" string makes Auctioneer print "Link is not item".
AucAdvanced = { API = { GetMarketValue = function(link) assert(type(link) == "number", "Auctioneer needs an itemID or a real link")
  if link == 2589 then return 32, 10 end end } }
SlashCmdList.KENNYDWARFEXPLORERSBIBLE("order auctioneer,scan")
p, label = RM.Price(2589)
M.check(p == 32 and label == "Auctioneer", "Auctioneer source")
M.check(P.Order(RM.Settings().sources)[2] == "scan" and #P.Order(RM.Settings().sources) == 5, "order keeps all sources")
-- PriceLog
KennyPriceLog = { GetLatest = function(item) if item == 2589 then return { p = 33, t = 1 } end end }
SlashCmdList.KENNYDWARFEXPLORERSBIBLE("prefer pricelog")
p, label = RM.Price(2589)
M.check(p == 33 and label == "PriceLog", "PriceLog source")
-- A source that errors is skipped.
KennyPriceLog.GetLatest = function() error("boom") end
p, label = RM.Price(2589)
M.check(p == 32 and label == "Auctioneer", "erroring source skipped")
-- Back to scan only
Auctionator, TSM_API, AucAdvanced, KennyPriceLog = nil, nil, nil, nil
M.check(RM.Price(2589) == 25, "falls back to scan cache when addons are gone")

-- Profit: bolt = 2 linen (2*25=50), sells 900 * 0.95 = 855 -> +805
local bolt = RM.Profit(found[2996].r)
M.check(bolt.cost == 50 and bolt.value == 855 and bolt.profit == 805 and not bolt.missing, "profit after AH cut")
M.check(RM.UsesOf(2589)[1].r.product == 2996, "priced, profitable recipe sorted first")
-- A recipe with an unpriced reagent shows no profit (never an overstated one).
local partial = { product = 2996, min = 1, max = 1, reagents = { { id = 2589, n = 2 }, { id = 999999, n = 1 } } }
local pp = RM.Profit(partial)
M.check(pp.profit == nil and pp.missing and pp.cost == 50, "missing reagent price -> no profit figure")
-- Vendor-sold reagents use the vendor price (bundled Forever price), like Auctionator's crafting module.
local vp, vl = RM.ReagentPrice(2320)
M.check(vp == 10 and vl == "vendor", "Coarse Thread priced at the vendor (10c)")
-- Stack counts: 2x reagent at its price, product made x2 per craft -> value doubles.
local twice = RM.Profit({ product = 2996, min = 2, max = 2, reagents = { { id = 2589, n = 2 } } })
M.check(twice.cost == 50 and twice.value == 1710 and twice.profit == 1660, "items-per-craft and reagent counts in profit")
-- Merchant window read (unlimited stock only, extended-cost items ignored).
GetMerchantNumItems = function() return 3 end
GetMerchantItemID = function(i) return ({ 2320, 2321, 4470 })[i] end
C_MerchantFrame = { GetItemInfo = function(i)
  if i == 1 then return { price = 50, stackCount = 5, numAvailable = -1 } end
  if i == 2 then return { price = 100, stackCount = 1, numAvailable = 3 } end
  return { price = 10, stackCount = 1, numAvailable = -1, hasExtendedCost = true } end }
M.fire("MERCHANT_SHOW")
M.check(RM.ReagentPrice(2320) == 10 and P.vendorCache[2320] == 10 and P.vendorCache[2321] == nil and P.vendorCache[4470] == nil,
  "merchant prices learned per unit, limited/extended-cost skipped")

-- Chains: linen -> bolt -> (bolt is used in tailoring) ...
local chain = RM.Chain(2589, 2)
local boltNode
for _, n in ipairs(chain.next) do if n.recipe.product == 2996 then boltNode = n.node end end
M.check(boltNode and #boltNode.next > 0, "chain follows bolt of linen to its uses")
M.check(#RM.Chain(2589, 0).next == 0, "chain depth respected")

-- Search and slash
local hits = RM.Search("linen cloth")
local has = {}
for _, h in ipairs(hits) do has[h] = true end
M.check(has[2589] and has[2996], "search by name")
M.check(RM.ParseItem("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r") == 2589, "parse link")
SlashCmdList.KENNYDWARFEXPLORERSBIBLE("linen cloth")
M.check(RM.State().id ~= nil and RM.Frame():IsShown(), "slash opens the guide")
SlashCmdList.KENNYDWARFEXPLORERSBIBLE("2589")
M.check(RM.State().id == 2589, "slash by id")
local a = RM.RowText(RM.UsesOf(2589)[1])
M.check(a:find("Bolt of Linen Cloth", 1, true) and a:find("Tailoring", 1, true), "row text")
RM.Navigate(2996, true)
M.check(RM.State().history[#RM.State().history] == 2589, "navigating keeps a back history")

-- Alt-click
alt = true
hooks.HandleModifiedItemClick("|Hitem:2996::|h[Bolt]|h")
M.check(RM.State().id == 2996, "alt-click opens the item")
alt = false

-- Tooltip
postCalls[1](GameTooltip, { id = 2589 })
local before = #tipLines
postCalls[1](GameTooltip, { id = 2589 })
M.check(#tipLines == before, "tooltip lines not added twice in one tooltip build")
local joined = table.concat(tipLines, "\n")
M.check(joined:find("Used in %d+ recipes"), "tooltip 'used in N recipes'")
M.check(joined:find("Dwarf Explorer's Bible scan", 1, true), "tooltip shows the price source")
M.done("DwarfExplorersBible")
