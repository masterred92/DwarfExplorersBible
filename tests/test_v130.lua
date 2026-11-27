-- 1.3.0: bag/bank counts, shopping list, alts, Make now / Best skill-up, seeds, profit lines, remembered vendors,
-- baseline prices, cross-realm DropShare, Where to farm, DEBDATA sharing and the tab slash commands.
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
TooltipDataProcessor = { AddTooltipPostCall = function() end }
hooksecurefunc = function() end
HandleModifiedItemClick = function() end
IsAltKeyDown = function() return false end
local shift = false
IsShiftKeyDown = function() return shift end

-- Bags (0-4) and Forever's bank (Enum.BagIndex.Characterbanktab = -2, CharacterBankTab_1 = 6, 1 bank bag).
Enum = { TooltipDataType = { Item = 0 }, BagIndex = { Characterbanktab = -2, CharacterBankTab_1 = 6 }, ItemClass = { Tradegoods = 7 } }
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_CHARACTER_BANK_SLOTS = 4, 4, 1
local bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [-2] = {}, [6] = {} }
local function setBag(bag, list) bags[bag] = list end
C_Container = {
  GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) local s = bags[bag] and bags[bag][slot]; return s and { itemID = s[1], stackCount = s[2] } or nil end,
}
local zone, subzone, level = "Dun Morogh", "Kharanos", 8
GetRealZoneText = function() return zone end
GetSubZoneText = function() return subzone end
UnitLevel = function() return level end
UnitFullName = function(u) if u == "player" then return "Kenny", "TestRealm" end end
local npcName = "Thrynn Bouden"
UnitName = function(u) if u == "player" then return "Kenny" elseif u == "npc" then return npcName end end
-- Zone levels for the map tests (the client answers C_Map.GetMapLevels at runtime).
local LEVELS = { ["Dun Morogh"] = { 1, 10 }, ["Loch Modan"] = { 10, 20 }, ["Badlands"] = { 35, 45 }, ["Searing Gorge"] = { 43, 50 },
  ["Elwynn Forest"] = { 1, 10 }, ["Winterspring"] = { 55, 60 }, ["Alterac Mountains"] = { 30, 40 } }
local byMap = {}
C_Map = { GetBestMapForUnit = function() return 27 end, GetMapLevels = function(id) local l = byMap[id]; if l then return l[1], l[2] end return 0, 0 end }
-- PriceLog (Kenny's own addon) as the live source.
local plPrices = { [2589] = 33, [2996] = 200, [2447] = 20, [2449] = 15, [2770] = 12 }
KennyPriceLog = { GetLatest = function(id) local p = plPrices[id]; return p and { p = p, t = M.now - 120 } or nil end }

local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
M.advance(1)
for name, l in pairs(LEVELS) do byMap[ns.Zones.zones[name].map] = l end
local RM, P, I, A, V, W, PL, S, SE, N, Dr, DS, SD = ns.RM, ns.Prices, ns.Inventory, ns.Alts, ns.Vendors, ns.Where, ns.Planner,
  ns.Shopping, ns.Seeds, ns.Nav, ns.Drops, ns.DropShare, ns.ShareData
local db = KennyDwarfExplorersBibleDB
local function bump() ns.Cache.Bump() end

M.check(db.schema == 4 and type(db.alts) == "table" and db.chars == nil, "schema 4: characters live in db.alts")
M.check(type(db.vendors.list) == "table" and type(db.shopping.items) == "table" and type(db.gather) == "table" and type(db.sightShares) == "table",
  "schema 4 tables: vendors, shopping, gather, sightShares")
local me = db.alts["TestRealm-Horde-Kenny"]
M.check(me and me.name == "Kenny" and me.realm == "TestRealm" and me.faction == "Horde", "this character's record has name, realm, faction")

-- 1. Inventory: debounced bag scans, combat, bank cache, bounded tracking ----------------------------------------
setBag(0, { { 2589, 2 }, { 117, 5 }, { 268415, 3 } })
local scans = I.scans
M.fire("BAG_UPDATE_DELAYED"); M.fire("BAG_UPDATE_DELAYED"); M.fire("BAG_UPDATE_DELAYED")
M.check(I.scans == scans, "bag events wait for the debounce")
M.advance(0.6)
M.check(I.scans == scans + 1, "a burst of bag events reads the bags once")
M.check(I.Count(2589).bags == 2 and I.Count(268415).bags == 3, "bag counts for tracked items")
M.check(me.bags[117] == nil, "items DEB has no use for are not saved")
M.combat = true
setBag(1, { { 2589, 1 } })
M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
M.check(I.Count(2589).bags == 2 and I.pending, "no bag scan in combat; it waits")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
M.check(I.Count(2589).bags == 3 and not I.pending, "the bags are read when combat ends")
setBag(1, {})
M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
setBag(-2, { { 2589, 4 } }); setBag(6, { { 2318, 2 } })
M.fire("BANKFRAME_OPENED"); M.advance(1)
M.check(I.Count(2589).bank == 4 and I.Count(2318).bank == 2, "bank and bank bags counted while open")
M.fire("BANKFRAME_CLOSED")
setBag(-2, {}); setBag(6, {})
M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
local c = I.Count(2589)
M.check(c.bank == 4 and c.bags == 2 and c.mine == 6, "bank counts are kept after the bank closes")
M.check(#I.BagSlots(268415) == 1 and I.BagSlots(268415)[1].bag == 0 and I.BagSlots(268415)[1].slot == 3, "bag slots for a highlight")

-- 2. Alts: who can craft, who has mats --------------------------------------------------------------------------
db.alts["TestRealm-Horde-Bankalt"] = { name = "Bankalt", realm = "TestRealm", faction = "Horde", learned = { [2996] = true },
  skills = { Tailoring = 75 }, bags = { [2589] = 1, [2318] = 5 }, bank = { [2320] = 3 } }
db.alts["TestRealm-Alliance-Ally"] = { name = "Ally", realm = "TestRealm", faction = "Alliance", learned = {}, skills = { Tailoring = 10 },
  bags = { [2589] = 50 }, bank = {} }
db.alts["OtherRealm-Horde-Far"] = { name = "Far", realm = "OtherRealm", faction = "Horde", learned = { [2996] = true }, skills = {}, bags = { [2589] = 9 }, bank = {} }
bump()
local chars = A.Characters()
M.check(#chars == 3 and chars[1].isMe, "characters on this realm, you first (other realms left out)")
c = I.Count(2589)
M.check(c.alts == 1 and c.total == 7 and #c.holders == 3, "alt counts: only same-faction alts count as mailable")
local who = A.WhoCanCraft(2996)
M.check(who[1].name == "Bankalt" and who[1].knows and who[1].skill == 75, "who can craft: the alt who knows it first")
M.check(A.CraftText(who[1]) == "Bankalt · Tailoring 75 · Knows recipe", "who can craft text")
local mats = A.WhoHasMats("light leather")
M.check(#mats == 1 and mats[1].itemID == 2318 and mats[1].total == 7, "who has mats, filtered by item name")
M.check(#A.WhoHasMats("bankalt") >= 3, "who has mats, filtered by character name")

-- 3. Baseline prices and the price resolver ---------------------------------------------------------------------
local b = ns.BaselinePrices
M.check(type(b) == "table" and b.market == "forever.normal.horde.us" and b.capturedAt == 1795815488,
  "bundled BaselinePrices.lua: market forever.normal.horde.us, capturedAt 1795815488")
local n, ok = 0, true
for id, copper in pairs(b.prices) do
  n = n + 1
  if type(id) ~= "number" or id < 1 or id ~= math.floor(id) then ok = false end
  if type(copper) ~= "number" or copper < 1 or copper ~= math.floor(copper) then ok = false end
end
M.check(n == 598 and ok, "598 positive integer itemIDs and copper prices")
M.check(b.prices[2589] == 24 and b.prices[118] == 5 and b.prices[3858] == 1044, "known reagent copper values")
M.check(#P.Order(RM.Settings().sources) == 6 and P.Order("baseline,pricelog")[6] == "baseline", "baseline is always the last source")
-- PriceLog already has 2589 at 33c; a live source must beat the bundled 24c.
local r = RM.Resolve(2589, "sell")
M.check(r.price == 33 and r.source == "pricelog" and r.label == "PriceLog", "a live PriceLog price beats the bundled baseline")
-- 4306 (Silk Cloth) is in the bundle (199c) and not in PriceLog; a scan still wins.
P.cache[4306] = { p = 50, t = M.now - 10 }; bump()
r = RM.Resolve(4306, "sell")
M.check(r.price == 50 and r.source == "scan" and r.label == "Dwarf Explorer's Bible scan", "a live scan beats the bundled baseline")
P.cache[4306] = nil; bump()
r = RM.Resolve(3858, "sell")
M.check(r.price == 1044 and r.source == "baseline" and r.label == "Forever baseline" and r.t == 1795815488,
  "the bundled baseline fills in with its label and capture time")
ns.BaselinePrices = { market = "test", capturedAt = M.now - 3600, prices = { [2589] = 99, [3858] = 500 } }
bump()
r = RM.Resolve(2589, "sell")
M.check(r.price == 33 and r.source == "pricelog", "a live source beats the baseline")
r = RM.Resolve(3858, "sell")
M.check(r.price == 500 and r.label == "Forever baseline" and r.t == M.now - 3600 and r.ageSeconds == 3600,
  "the baseline fills in with its label and capture time")
ns.BaselinePrices = nil
r = RM.Resolve(3858, "sell")
M.check(r.price == nil and r.kind == "none", "no baseline file: nothing is made up")
r = RM.Resolve(2320, "buy")
M.check(r.kind == "vendor" and r.price == 10, "buy side: the Forever vendor price")
plPrices[2320] = 500
r = RM.Resolve(2320, "buy")
M.check(r.kind == "vendor" and r.price == 10, "an inflated AH price never beats the vendor")
plPrices[2320] = 4
r = RM.Resolve(2320, "buy")
M.check(r.kind == "ah" and r.price == 4, "a cheaper AH price wins on the buy side")
plPrices[2320] = nil

-- 4. Profit: never 0g for a missing price; buy-all vs mats in bags --------------------------------------------
local bolt = RM.byProduct[2996][1]
local pr = RM.Profit(bolt)
M.check(pr.profit and not pr.incomplete and pr.ageSeconds == 120, "profit with every price known, with its age")
plPrices[2589] = nil
pr = RM.Profit(bolt)
M.check(pr.profit == nil and pr.incomplete and pr.unpriced[1] == 2589, "missing reagent price: incomplete, profit nil (never 0g)")
local pl = RM.ProfitLines(bolt)
M.check(pl.buyAll.profit == nil and pl.buyAll.incomplete and pl.withBags.profit == pl.value and not pl.withBags.incomplete,
  "mats in bags cover the unpriced reagent: that line has a profit, buy-all doesn't")
plPrices[2589] = 33
pl = RM.ProfitLines(bolt)
M.check(pl.owned == 2 and not pl.single and pl.buyAll.cost == 66 and pl.withBags.cost == 0, "owned count and both cost lines")
setBag(0, { { 268415, 3 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
me.bank[2589] = nil; bump()
pl = RM.ProfitLines(bolt)
M.check(pl.owned == 0 and pl.single, "nothing owned: one line")
setBag(0, { { 2589, 2 }, { 268415, 3 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
me.bank[2589] = 4; bump()

-- 5. Remembered vendors: MERCHANT_SHOW with zone and subzone, goods, caps, in-zone first ----------------------
local merchant = {}
GetMerchantNumItems = function() return #merchant end
GetMerchantItemID = function(i) return merchant[i] and merchant[i].id end
C_MerchantFrame = { GetItemInfo = function(i) local m = merchant[i]; return m and { price = m.price, stackCount = m.stack or 1, numAvailable = m.avail or -1 } end }
merchant = { { id = 2320, price = 10 }, { id = 2321, price = 100, avail = 3 }, { id = 117, price = 25 }, { id = 2678, price = 50, stack = 5 } }
M.fire("MERCHANT_SHOW")
local key = V.Key("Thrynn Bouden", "Dun Morogh", "Kharanos")
local goods = V.GetVendorGoods(key)
M.check(goods and goods.npc == "Thrynn Bouden" and goods.zone == "Dun Morogh" and goods.subzone == "Kharanos", "merchant remembered with zone and subzone")
local byId = {}
for _, g in ipairs(goods.goods) do byId[g.itemID] = g end
M.check(byId[2320] and byId[2320].price == 10 and not byId[2320].limited, "goods: unlimited item and price")
M.check(byId[2321] and byId[2321].price == 100 and byId[2321].limited, "goods: limited stock is marked")
M.check(byId[2678] and byId[2678].price == 10, "goods: price per item for stacks")
M.check(byId[117] == nil, "goods: only crafting materials are kept")
M.check(V.Text(V.Best(2320)) == "Vendor: Thrynn Bouden (Kharanos, Dun Morogh)", "vendor text with subzone")
V.Record({ { id = 2320, unit = 8, avail = -1 } }, "Yanni Stoutheart", "Loch Modan", "Thelsamar")
V.Record({ { id = 2320, unit = 9, avail = -1 } }, "Drake Lindgren", "Elwynn Forest", "Goldshire")
local vs = V.GetVendorsForItem(2320, "Dun Morogh")
M.check(#vs == 3 and vs[1].npc == "Thrynn Bouden" and vs[1].inZone and vs[1].distance == 0, "vendors for an item: in-zone first even when dearer")
M.check(vs[2].npc == "Yanni Stoutheart" and not vs[2].inZone and vs[2].distance < vs[3].distance, "then the nearest zone")
vs = V.GetVendorsForItem(2320, "Elwynn Forest")
M.check(vs[1].npc == "Drake Lindgren", "in-zone first from another zone")
M.check(RM.Resolve(2320, "buy").price == 8, "the cheapest remembered vendor prices the buy side")
for i = 1, V.MAX_VENDORS + 5 do V.Record({ { id = 2320, unit = 10, avail = -1 } }, "Vendor" .. i, "Dun Morogh", "", M.now + i) end
M.check(V.Count() == V.MAX_VENDORS, "remembered merchants are capped")
local many = {}
for _, rr in ipairs(RM.recipes) do for _, g in ipairs(rr.reagents) do if #many < V.MAX_ITEMS + 20 and not many[g.id] then many[g.id] = true; many[#many + 1] = { id = g.id, unit = 5, avail = -1 } end end end
V.Record(many, "Big Vendor", "Dun Morogh", "", M.now + 999)
M.check(#V.GetVendorGoods(V.Key("Big Vendor", "Dun Morogh", "")).goods == V.MAX_ITEMS, "goods per merchant are capped")
-- Back to a clean vendor list for the next sections.
db.vendors.list = {}; V.Attach(db)
M.fire("MERCHANT_SHOW")
V.Record({ { id = 2320, unit = 8, avail = -1 } }, "Yanni Stoutheart", "Loch Modan", "Thelsamar")

-- 6. Where to farm -----------------------------------------------------------------------------------------------
-- Linen in a starter zone: mobs counted in this zone come first.
Dr.ApplyShare("lnshareaaaa1", { kills = { [706] = 20, [6] = 40 }, drops = { [706] = { [2589] = { loots = 20, seen = 5 } }, [6] = { [2589] = { loots = 40, seen = 20 } } },
  names = { [706] = "Frostmane Troll Whelp", [6] = "Kobold Vermin" } }, "aaaa0001")
Dr.NoteZone(706, "Dun Morogh")
Dr.NoteZone(6, "Elwynn Forest")
bump()
local wf = W.WhereToFarm(2589, "Dun Morogh", 8)
M.check(wf.here and wf.here.inCurrentZone and wf.here.mobs[1].name == "Frostmane Troll Whelp" and wf.here.mobs[1].pct == 25,
  "Linen in Dun Morogh: the local mob first, with its rate")
M.check(wf.nearby[1] and wf.nearby[1].zone == "Elwynn Forest" and wf.nearby[1].mobs[1].pct == 50, "a better rate elsewhere is listed after it")
M.check(W.TooltipText(2589) == "Farm here: Dun Morogh (Frostmane Troll Whelp, 25%)", "tooltip phrase: Farm here")
-- Copper and Peacebloom: your own gathering sightings in this zone come first.
W.Note(2770, "mine", "Dun Morogh"); W.Note(2770, "mine", "Loch Modan"); W.Note(2770, "mine", "Loch Modan")
W.Note(2447, "herb", "Dun Morogh")
GetNumLootItems = function() return 1 end
GetLootSlotLink = function() return "|cffffffff|Hitem:2447::::::::8:::::|h[Peacebloom]|h|r" end
M.check(W.OnGatherLoot("herb") == 1, "a herb loot window records a sighting")
GetNumLootItems = function() return 0 end
wf = W.WhereToFarm(2770, "Dun Morogh", 8)
M.check(wf.here and wf.here.gather[1].kind == "mine" and wf.nearby[1].zone == "Loch Modan", "Copper in Dun Morogh: mine here first, then Loch Modan")
M.check(W.TooltipText(2770) == "Mine here: Dun Morogh", "tooltip phrase: Mine here")
wf = W.WhereToFarm(2447, "Dun Morogh", 8)
M.check(wf.here and wf.here.gather[1].kind == "herb" and wf.here.gather[1].n == 2, "Peacebloom in Dun Morogh: herb here")
M.check(W.TooltipText(2447) == "Herb here: Dun Morogh", "tooltip phrase: Herb here")
-- Mithril from a starter zone: not local; the nearest zone that suits your level comes first.
W.Note(3858, "mine", "Badlands"); W.Note(3858, "mine", "Searing Gorge"); W.Note(3858, "mine", "Winterspring"); W.Note(3858, "mine", "Alterac Mountains")
wf = W.WhereToFarm(3858, "Dun Morogh", 40)
M.check(wf.here == nil and #wf.nearby == 4, "Mithril in Dun Morogh: nothing local")
M.check(wf.nearby[1].levelFit == "ok" and wf.nearby[#wf.nearby].zone == "Winterspring", "nearest level-appropriate zone first, other continent last")
M.check(wf.nearby[1].cost <= wf.nearby[2].cost and wf.nearby[2].cost <= wf.nearby[3].cost, "nearby zones sorted by distance and level fit")
local wf12 = W.WhereToFarm(3858, "Dun Morogh", 12)
local sg
for _, e in ipairs(wf12.nearby) do if e.zone == "Searing Gorge" then sg = e end end
M.check(sg and sg.levelFit == "high" and sg.levelMin == 43, "zones above your level are marked and pushed back")
M.check(W.TooltipText(3858):find("^Nearest: ") ~= nil, "tooltip phrase: Nearest")
-- Vendors block: exact price from the remembered merchant, in-zone first; bundled Forever price as fallback.
wf = W.WhereToFarm(2320, "Dun Morogh", 8)
M.check(wf.vendors[1].npc == "Thrynn Bouden" and wf.vendors[1].inZone and wf.vendorPrice.price == 10 and wf.vendorPrice.source == "merchant",
  "vendors block: in-zone merchant and its exact price")
wf = W.WhereToFarm(2324, "Dun Morogh", 8)
M.check(#wf.vendors == 0 and wf.vendorPrice and wf.vendorPrice.source == "Forever data" and wf.vendorPrice.price == ns.Data.buy[2324],
  "vendors block: bundled Forever vendor price when no merchant was seen")
wf = W.WhereToFarm(12359, "Dun Morogh", 8)
M.check(wf.empty, "nothing known: empty, nothing made up")

-- 7. Shopping list: Vendor / Grab from Alt / AH, vendor groups with copper subtotals -------------------------
-- Bags + bank: 6 Linen. Bankalt: 1 Linen, 5 Light Leather, 3 Coarse Thread.
M.check(S.AddRecipe(bolt, 4) == 1, "add a recipe's missing mats (8 Linen needed, 6 held)")
M.check(S.AddItem(2320, 4) and S.AddItem(2321, 2) and S.AddItem(2318, 6) and S.AddItem(3858, 5) and S.AddItem(2770, 3), "add single items")
M.check(S.Has(2589) and S.Count() == 6, "six lines on the list")
local secs = S.Sections("Dun Morogh")
local function rowOf(list, id) for _, x in ipairs(list) do if x.itemID == id then return x end end end
local linen = rowOf(secs.ah.rows, 2589)
M.check(linen and linen.need == 8 and linen.fromAlt == 1 and linen.buy == 1 and linen.estCost == 33, "Linen: need 8, hold 6, 1 from the alt, buy 1 at the AH")
M.check(rowOf(secs.alt.rows, 2318) and rowOf(secs.alt.rows, 2318).altHolders[1].name == "Bankalt", "Light Leather: grab from Bankalt")
local thread = secs.vendor.groups[1]
M.check(thread.npc == "Thrynn Bouden" and thread.rows[1].itemID == 2320 and thread.rows[1].buy == 1 and thread.subtotal == 10,
  "Coarse Thread: grouped under the in-zone merchant, copper subtotal (4 needed, 3 on the alt)")
local forever = secs.vendor.groups[#secs.vendor.groups]
M.check(forever.key == "forever" and rowOf(forever.rows, 2321) and forever.subtotal == 200, "Fine Thread (limited stock only): Forever vendor price group last")
M.check(secs.vendor.subtotal == 210, "vendor section subtotal in copper")
local mith = rowOf(secs.ah.rows, 3858)
M.check(mith and mith.estCost == nil and mith.incomplete and secs.ah.incomplete and secs.incomplete, "no price: estCost nil and incomplete, never 0g")
M.check(secs.ah.subtotal == 33 + 36 and secs.total == 210 + 69, "AH subtotal counts only known prices")
M.check(S.NeedText(linen) == "Need 8 (have 2 bags, 4 bank): buy 1", "need text")
S.SetDone(2770, true)
secs = S.Sections("Dun Morogh")
M.check(rowOf(secs.done.rows, 2770) and not rowOf(secs.ah.rows, 2770), "mark done")
M.check(S.ClearDone() == 1 and not S.Has(2770) and S.Count() == 5, "Clear done")
M.check(S.Remove(3858) and S.Count() == 4, "remove one line")
for i = 1, S.MAX_ITEMS + 5 do S.AddItem(100000 + i, 1) end
M.check(S.Count() == S.MAX_ITEMS, "the list is capped")
M.check(S.ClearAll() == S.MAX_ITEMS and S.Count() == 0, "Clear all")
-- Click-to-fill the AH search (only on a click, only with the AH open, never in combat).
local searched, started = nil, 0
AuctionHouseFrame = M.frameObj("AuctionHouseFrame")
rawset(AuctionHouseFrame, "SetSearchText", function(_, t) searched = t; return true end)
AuctionHouseFrame.SearchBar = { StartSearch = function() started = started + 1 end }
M.check(select(2, S.SearchAH(2589)) == "closed" and searched == nil, "AH search refused while the AH is closed")
M.fire("AUCTION_HOUSE_SHOW")
M.combat = true
M.check(select(2, S.SearchAH(2589)) == "combat" and searched == nil, "AH search refused in combat")
M.combat = false
M.check(S.SearchAH(2589) and searched == "Linen Cloth" and started == 1, "AH search fills the name and starts that search")
M.check(S.Status():find("Click any row", 1, true) ~= nil, "status line with the AH open")
M.fire("AUCTION_HOUSE_CLOSED")
M.check(S.Status():find("Open the Auction House", 1, true) ~= nil, "status line with the AH closed")

-- 8. Make now and Best skill-up -------------------------------------------------------------------------------
me.skills.Tailoring = 30
me.learned[2996] = true
bump()
M.check(ns.Planner.MaxCrafts(bolt) == 3 and PL.MaxCrafts(bolt, true) == 3, "Make now: 6 Linen in bags + bank = 3 bolts")
setBag(0, { { 268415, 3 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
me.bank[2589] = 1; bump()
M.check(PL.MaxCrafts(bolt) == 0 and PL.MaxCrafts(bolt, true) == 1, "Make now with alts counts mailable alts' mats")
local list = RM.FilterList({ { r = bolt, pr = RM.Profit(bolt) } }, { filterMakeNow = true, makeNowAlts = false })
M.check(#list == 0, "Make now filter hides what you can't craft yet")
list = RM.FilterList({ { r = bolt, pr = RM.Profit(bolt) } }, { filterMakeNow = true, makeNowAlts = true })
M.check(#list == 1, "Make now filter with alts")
M.check(math.abs(PL.SkillChance(bolt) - 0.8) < 1e-9, "yellow skill-up chance (grey - skill) / (grey - yellow)")
local function fake(skill, grey, product) return { prof = "Tailoring", skill = skill, grey = grey, product = product, min = 1, max = 1, reagents = { { id = 2320, n = 1 } } } end
local orange, yellowA, green, greyR = fake(40, 60, 900001), fake(20, 50, 900002), fake(10, 40, 900003), fake(5, 20, 900004)
local yellowB = { prof = "Tailoring", skill = 20, grey = 50, product = 900005, min = 1, max = 1, reagents = { { id = 2320, n = 5 } } }
local sorted = PL.SortSkillUp({ { r = greyR }, { r = green }, { r = yellowB }, { r = yellowA }, { r = orange } })
M.check(sorted[1].r == orange and sorted[2].r == yellowA and sorted[3].r == yellowB and sorted[4].r == green and sorted[5].r == greyR,
  "Best skill-up: orange > yellow > green, cheapest per skill point first")
M.check(PL.SkillChance(orange) == 1 and PL.SkillChance(greyR) == 0, "orange always, grey never")
setBag(0, { { 2589, 2 }, { 268415, 3 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
me.bank[2589] = 4; bump()

-- 9. Seeds, Greenhouse, Hybridizer ---------------------------------------------------------------------------
M.check(SE.IsSeedItem(268415) and SE.IsSeedItem(279964) and SE.IsSeedItem(279947) and not SE.IsSeedItem(2589), "seed items recognised")
local rows = SE.Rows("all")
M.check(#rows == 1 and rows[1].itemID == 268415 and not rows[1].ready and rows[1].hint == "Needs a Greenhouse in your bags",
  "seeds without a Greenhouse: shown, not ready")
M.check(rows[1].role:find("Peacebloom or Earthroot", 1, true) and rows[1].role:find("reported", 1, true), "what it grows into (reported)")
M.check(rows[1].value == 20 and rows[1].recipes == 0, "AH value of the best crop")
setBag(0, { { 2589, 2 }, { 268415, 3 }, { 279964, 1 }, { 268418, 2 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
rows = SE.Rows("ready")
local function seedRow(list, id) for _, x in ipairs(list) do if x.itemID == id then return x end end end
M.check(seedRow(rows, 268415) and seedRow(rows, 268415).canPlant and seedRow(rows, 279964), "Greenhouse in bags: ready to plant")
local scarce = seedRow(SE.Rows("all"), 268418)
M.check(scarce and not scarce.canHybridize and scarce.role:find("Can't be hybridized since the Nov 19 hotfix", 1, true), "Scarce seeds: no hybridizing")
M.check(SE.Summary().text == "Seeds in bags: 5 · Greenhouse ready", "seed summary line")
M.check(#SE.BagSlots(279964) == 1, "bag highlight slots for the Greenhouse")
setBag(0, { { 2589, 2 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
M.check(SE.Summary().empty, "no seeds: empty state")

-- 10. Compact tooltips: 1-2 lines, Shift for more -------------------------------------------------------------
tipLines = {}
RM.AddTooltipLines(GameTooltip, 2589, false)
M.check(#tipLines == 4, "default tooltip: two lines, the 'here' cue and the Shift hint")
M.check(tipLines[2]:find("You have 6 (2 bags, 4 bank)", 1, true) and not tipLines[2]:find("Farm here", 1, true), "line 2: counts and worth")
M.check(tipLines[3]:find("^Farm here: Dun Morogh") ~= nil, "line 3: its own 'Farm here' line")
M.check(tipLines[4] == "Hold Shift for full crafting breakdown", "quiet Shift hint")
tipLines = {}
RM.AddTooltipLines(GameTooltip, 2589, true)
M.check(#tipLines > 2 and table.concat(tipLines, "\n"):find("Bankalt", 1, true), "Shift: price age and alts")

-- 11. DropShare: cross-realm names, self-echo ------------------------------------------------------------------
M.check(Dr.NormalizeSender("Bob-Area 52") == "bob-area52" and Dr.NormalizeSender("bob-Area-52") == "bob-area52", "realm spaces and hyphens stripped, case ignored")
M.check(Dr.NormalizeSender("Bob") == "bob-testrealm", "a short name is on your realm")
M.check(Dr.SameSender(Dr.NormalizeSender("Bob-TestRealm"), Dr.NormalizeSender("Bob")) and not Dr.SameSender("bob-testrealm", "bob-otherrealm"),
  "same player across name forms; another realm is another player")
M.check(DS.IsSelf("Kenny") and DS.IsSelf("Kenny-TestRealm") and DS.IsSelf("kenny-Test Realm") and not DS.IsSelf("Kenny-OtherRealm"), "self-echo detection")
M.group.inGroup = true
M.addonMessages = {}
DS.OnAddonMessage("DEBDROPS", "A:someoneelse1:0badf00d", "PARTY", "Kenny-TestRealm")
DS.OnAddonMessage("DEBDATA", "A:someoneelse1:0badf00d", "PARTY", "Kenny")
M.advance(1)
M.check(#M.addonMessages == 0, "your own echo is ignored")

-- 12. DEBDATA: sharing vendor and gathering sightings between Bible users -------------------------------------
local mySid = Dr.SourceId()
local snap = SD.PersonalSnapshot()
M.check(#snap.vendors == 2 and #snap.gather > 0 and snap.mobs[706] and snap.mobs[706]["Dun Morogh"] == 1, "your snapshot: vendors, gathering, mob zones")
local text = SD.Encode(mySid, snap)
local back = SD.Decode(text)
local tb
for _, v in ipairs(back.vendors) do if v.npc == "Thrynn Bouden" then tb = v end end
M.check(tb and tb.zone == "Dun Morogh" and tb.subzone == "Kharanos" and tb.items[2320].p == 10 and tb.items[2321].limited, "encode/decode round trip: vendors")
M.check(#back.gather == #snap.gather and back.mobs[706]["Dun Morogh"] == 1, "encode/decode round trip: gathering and mob zones")
M.check(select(4, DS.Decode(text)) == "malformed", "a 1.2.1 drop decoder rejects a DEB2 string cleanly")
M.check(select(4, SD.Decode(DS.EncodePersonal())) == "malformed", "the sightings decoder ignores DEB1 strings")
-- Sanitize: escape codes, control characters, over-long names.
local dirty = { vendors = { { npc = "|cffff0000Evil|r\1Vendor|Hitem:1|h[x]|h", zone = "Dun Morogh" .. string.rep("z", 100), subzone = "a|Tb|tc",
  items = { [2320] = { p = 7 } } } }, gather = { { id = 2770, k = "mine", zone = "Loch\2Modan", n = 1 }, { id = 2770, k = "bogus", zone = "X", n = 1 } }, mobs = {} }
local dec = SD.Decode(SD.Encode("dirtysrc01", dirty))
M.check(dec.vendors[1].npc == "EvilVendor[x]" and #dec.vendors[1].zone == SD.MAX_TEXT and dec.vendors[1].subzone == "ac", "received text: escape codes, control characters and length stripped")
M.check(#dec.gather == 1 and dec.gather[1].zone == "LochModan", "received gathering: unknown kinds dropped")
M.check(select(4, SD.Decode(text:gsub(":(%x+):", ":00000000:", 1))) == "bad checksum", "bad checksum rejected")
-- Caps.
local big = { vendors = {}, gather = {}, mobs = {} }
for i = 1, 50 do
  local items = {}
  for j = 1, 60 do items[j] = { p = j } end
  big.vendors[i] = { npc = "V" .. i, zone = "Dun Morogh", items = items }
end
for i = 1, 400 do big.gather[i] = { id = i, k = "herb", zone = "Dun Morogh", n = 1 } end
for i = 1, 400 do big.mobs[i] = { ["Dun Morogh"] = 1, A = 1, B = 1, C = 1, D = 1, E = 1 } end
dec = SD.Decode(SD.Encode("bigsource01", big))
local maxGoods = 0
for _, v in ipairs(dec.vendors) do local n = 0; for _ in pairs(v.items) do n = n + 1 end; maxGoods = math.max(maxGoods, n) end
local nMobs, maxZones = 0, 0
for _, z in pairs(dec.mobs) do nMobs = nMobs + 1; local n = 0; for _ in pairs(z) do n = n + 1 end; maxZones = math.max(maxZones, n) end
M.check(#dec.vendors == SD.MAX_VENDORS and maxGoods == SD.MAX_GOODS and #dec.gather <= SD.MAX_GATHER and nMobs <= SD.MAX_MOBS and maxZones == SD.MAX_MOB_ZONES,
  "received sightings are capped (vendors, goods, gathering, mobs, zones per mob)")
for i = 1, SD.MAX_SOURCES + 5 do SD.Apply(("capsource%03d"):format(i), { vendors = {}, gather = {}, mobs = {} }, ("%08x"):format(i)) ; M.now = M.now + 1 end
M.check(SD.Sources() == SD.MAX_SOURCES and db.sightShares["capsource001"] == nil, "sources capped, oldest dropped")
db.sightShares = {}; SD.Attach(db)

-- Sync round trip: Bob's sightings arrive in chunks over PARTY.
local bobSnap = { vendors = { { npc = "Gearcutter Cogspinner", zone = "Ironforge", subzone = "The Great Forge", items = { [2321] = { p = 90 }, [3371] = { p = 4, limited = true } } } },
  gather = { { id = 3858, k = "mine", zone = "Loch Modan", n = 3 } }, mobs = { [1162] = { ["Loch Modan"] = 7 } } }
local bobText = SD.Encode("bobsource01", bobSnap)
local chunks = DS.BuildChunks(bobText)
local allSmall = #chunks > 0
for _, ch in ipairs(chunks) do if #ch > DS.MAX_CHUNK then allSmall = false end end
M.check(allSmall, "chunks fit in 240 bytes")
for _, ch in ipairs(chunks) do SD.OnAddonMessage("DEBDATA", ch, "WHISPER", "Bob-TestRealm") end
M.check(db.sightShares["bobsource01"] == nil, "whispers are ignored")
for _, ch in ipairs(chunks) do DS.OnAddonMessage("DEBDATA", ch, "PARTY", "Bob-TestRealm") end
M.check(db.sightShares["bobsource01"] == nil and next(db.dropShares or {}) ~= nil, "the 1.2.1 drop channel ignores DEBDATA frames")
for _, ch in ipairs(chunks) do SD.OnAddonMessage("DEBDATA", ch, "PARTY", "Bob-TestRealm") end
local got = db.sightShares["bobsource01"]
M.check(got and got.sender == "bob-testrealm" and got.vendors[1].npc == "Gearcutter Cogspinner", "sync: Bob's sightings stored, bound to Bob")
local gv = V.GetVendorsForItem(2321, "Dun Morogh")
local shared
for _, v in ipairs(gv) do if v.npc == "Gearcutter Cogspinner" then shared = v end end
M.check(shared and shared.shared and shared.subzone == "The Great Forge" and shared.price == 90, "shared merchants show up in vendor lookups")
M.check(V.GetVendorGoods(V.Key("Gearcutter Cogspinner", "Ironforge", "The Great Forge")).shared, "GetVendorGoods for a shared merchant")
wf = W.WhereToFarm(3858, "Dun Morogh", 40)
M.check(wf.nearby[1].zone == "Loch Modan" and wf.nearby[1].gather[1].n == 3, "shared gathering sightings feed Where to farm")
M.check(W.MobZones(1162)["Loch Modan"] == 7, "shared mob zones feed Where to farm")
local evil = SD.Encode("bobsource01", { vendors = {}, gather = { { id = 2589, k = "herb", zone = "Fake", n = 99 } }, mobs = {} })
for _, ch in ipairs(DS.BuildChunks(evil)) do SD.OnAddonMessage("DEBDATA", ch, "GUILD", "Eve-TestRealm") end
M.check(#db.sightShares["bobsource01"].gather == 1 and db.sightShares["bobsource01"].gather[1].id == 3858, "another sender can't overwrite Bob's sightings")
SD.OnAddonMessage("DEBDATA", "Z:nonsense", "PARTY", "Bob-TestRealm")
SD.OnAddonMessage("DEBDATA", "D:zz:1:1:" .. string.rep("x", 300), "PARTY", "Bob-TestRealm")
SD.OnAddonMessage("DEBNOPE", "A:bobsource01:12345678", "PARTY", "Bob-TestRealm")
M.check(true, "unknown or broken frames are ignored without errors")

-- Sending: combat and lockdown wait; DEBDROPS keeps its own prefix and format.
M.addonMessages = {}
M.combat = true
M.check(SD.Flush() == false and SD.Pending(), "no sending in combat")
M.combat = false
M.lockdown = true
M.check(SD.Flush() == false, "no sending in chat lockdown")
M.lockdown = false
M.check(SD.Flush(), "flush out of combat")
M.advance(60)
local dataMsgs, dropMsgs, badLen, badChan = 0, 0, false, false
for _, m in ipairs(M.addonMessages) do
  if m.prefix == "DEBDATA" then dataMsgs = dataMsgs + 1 elseif m.prefix == "DEBDROPS" then dropMsgs = dropMsgs + 1 end
  if #m.message > 240 then badLen = true end
  if not DS.ALLOWED_CHANNELS[m.chatType] then badChan = true end
end
M.check(dataMsgs >= 2 and not badLen and not badChan, "sightings sent as DEBDATA announce + chunks, 240 bytes or less, PARTY only")
local firstData
for _, m in ipairs(M.addonMessages) do if m.prefix == "DEBDATA" and m.message:match("^D:") then firstData = firstData or m.message end end
M.check(firstData and firstData:find("DEB2:" .. mySid, 1, true), "DEBDATA chunks carry the DEB2 string")
M.addonMessages = {}
db.dropKills[1162], db.drops[1162] = 3, { [2589] = { seen = 1, loots = 3 } }
Dr.InvalidateCombined()
DS.OnPersonalChange(); DS.Flush(); M.advance(60)
local dropFrame
for _, m in ipairs(M.addonMessages) do if m.prefix == "DEBDROPS" and m.message:match("^D:") then dropFrame = m.message end end
M.check(dropFrame and dropFrame:find("DEB1:", 1, true) and not dropFrame:find("DEB2:", 1, true), "DEBDROPS still sends the 1.2.1 DEB1 format")

-- Export / import: DEB1 line unchanged plus a DEB2 line; import takes either or both.
local exportText = SD.ExportText()
local l1, l2 = exportText:match("^(DEB1:[^\n]*)\n(DEB2:[^\n]*)$")
M.check(l1 and l2 and l1 == DS.EncodePersonal(), "export: the DEB1 line as 1.2.1 wrote it, then the DEB2 line")
local d1, d2 = SD.SplitImport(exportText)
M.check(d1 == l1 and d2 == l2, "import splits the pasted lines")
db.dropShareId = "newowner0001"
db.dropShares, db.sightShares = {}, {}
Dr.Attach(db); SD.Attach(db); bump()
local okImp, res = SD.ImportText(exportText, true)
M.check(okImp and res.drops[1] and res.sightings[1] and db.sightShares[mySid] and #db.sightShares[mySid].vendors == 2, "export/import round trip (drops + sightings)")
okImp = SD.ImportText(l2, true)
M.check(okImp, "import a DEB2 line on its own")
db.sightShares = {}; SD.Attach(db)
okImp, res = SD.ImportText(l1, true)
M.check(okImp and res.sightings == nil and next(db.sightShares) == nil, "a 1.2.1 DEB1 line imports as before")
M.check(select(2, DS.Decode(exportText)) == nil, "1.2.1 import of both lines fails cleanly (checksum), nothing applied")
M.prints = {}
SD.ImportText("garbage", false)
M.check(M.printed("couldn't read that drop string."), "unreadable text: the 1.2.1 message")
DS.OpenExport()
local ew = _G["KennyDwarfExplorersBibleDropExportWindow"]
M.check(ew.edit:GetText():find("^DEB1:") and ew.edit:GetText():find("\nDEB2:", 1, true), "/deb export shows both lines")

-- 13. Tabs and slash commands -------------------------------------------------------------------------------
M.prints = {}
M.slash("/deb", "shop")
M.check(N.CurrentTab() == "shopping" and RM.ShownPane() == "shopping" and not M.printed("Shopping list is empty"), "/deb shop opens the Shopping tab (no chat summary once the window has tabs)")
M.check(N.Summary("shopping"):find("Shopping list is empty", 1, true) ~= nil, "chat summary still available")
local seen = {}
N.RegisterTabHandler(function(tab) seen[#seen + 1] = tab end)
M.slash("/deb", "seeds"); M.slash("/deb", "alts"); M.slash("/deb", "materials"); M.slash("/deb", "shopping")
M.check(table.concat(seen, ",") == "seeds,alts,materials,shopping", "tab handler called for /deb seeds, alts, materials, shopping")
M.slash("/deb", "shop 2589 4")
M.check(S.Has(2589) and db.shopping.items[2589].need == 4, "/deb shop <item> <count> adds a line")
M.slash("/deb", "shop clear")
M.check(S.Count() == 0, "/deb shop clear")
M.check(not N.ShowTab("flips"), "unknown tabs refused")
for _, cmd in ipairs({ "mattip", "kmt", "pricelog", "kpl", "nflip", "neutralflip", "goldspot", "kspot" }) do
  for k in pairs(SlashCmdList) do
    for i = 1, 5 do if _G["SLASH_" .. k .. i] == "/" .. cmd then M.check(false, "slash clash /" .. cmd) end end
  end
end
M.done("1.3.0")
