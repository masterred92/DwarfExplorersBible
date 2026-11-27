-- 1.3.0 Stage 2: the tabbed window (Materials | Shopping | Seeds | Alts), the Right Here / Nearest Spot card, the
-- Materials planner filters, the Shopping / Seeds / Alts panes, compact Shift-expand tooltips, Export / Import, fit
-- of every fixed-width label in 12 pt FRIZQT, and combat safety (no layout call while InCombatLockdown()).
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.installLDB()
local tipLines, tipColors = {}, {}
GameTooltip = M.frameObj("GameTooltip")
rawset(GameTooltip, "AddLine", function(_, t, r, g, b) tipLines[#tipLines + 1] = t; tipColors[#tipLines] = { r, g, b } end)
rawset(GameTooltip, "AddDoubleLine", function(_, a, b) tipLines[#tipLines + 1] = a .. " = " .. b end)
UISpecialFrames, tinsert = {}, table.insert
GetMoneyString = function(c) return c .. "c" end
TooltipDataProcessor = { AddTooltipPostCall = function() end }
hooksecurefunc = function() end
HandleModifiedItemClick = function() end
IsAltKeyDown = function() return false end
local shift = false
IsShiftKeyDown = function() return shift end
Enum = { TooltipDataType = { Item = 0 }, BagIndex = { Characterbanktab = -2, CharacterBankTab_1 = 6 }, ItemClass = { Tradegoods = 7 } }
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_CHARACTER_BANK_SLOTS = 4, 4, 1
local bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [-2] = {}, [6] = {} }
local function setBag(bag, list) bags[bag] = list end
C_Container = {
  GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) local s = bags[bag] and bags[bag][slot]; return s and { itemID = s[1], stackCount = s[2] } or nil end,
}
local zone, level = "Dun Morogh", 8
GetRealZoneText = function() return zone end
GetSubZoneText = function() return "Kharanos" end
UnitLevel = function() return level end
UnitFullName = function(u) if u == "player" then return "Kenny", "TestRealm" end end
local LEVELS = { ["Dun Morogh"] = { 1, 10 }, ["Loch Modan"] = { 10, 20 }, ["Elwynn Forest"] = { 1, 10 } }
local byMap = {}
C_Map = { GetBestMapForUnit = function() return 27 end, GetMapLevels = function(id) local l = byMap[id]; if l then return l[1], l[2] end return 0, 0 end }
local plPrices = { [2589] = 33, [2996] = 200, [2447] = 20, [2449] = 15, [2770] = 12, [2840] = 30, [2318] = 25, [2319] = 40 }
KennyPriceLog = { GetLatest = function(id) local p = plPrices[id]; return p and { p = p, t = M.now - 7200 } or nil end }
-- Record sizes so the tests can read them (the mock's SetSize is a no-op).
local origCreate = CreateFrame
CreateFrame = function(...)
  local f = origCreate(...)
  rawset(f, "SetSize", function(self, w, h) rawset(self, "w", w); rawset(self, "h", h) end)
  return f
end

local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
M.advance(1)
for name, l in pairs(LEVELS) do byMap[ns.Zones.zones[name].map] = l end
local RM, N, S, SE, A, V, W, Dr = ns.RM, ns.Nav, ns.Shopping, ns.Seeds, ns.Alts, ns.Vendors, ns.Where, ns.Drops
local db = KennyDwarfExplorersBibleDB
local function bump() ns.Cache.Bump() end
local me = db.alts["TestRealm-Horde-Kenny"]
me.skills.Tailoring = 50
me.learned[2996] = true
setBag(0, { { 2589, 6 }, { 2318, 1 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)

-- Widths in 12 pt FRIZQT (colour codes and |T textures stripped; a texture counts 14 px).
local FW = dofile("tests/friz12_widths.lua")
local function width(s)
  s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local tex = 0
  s = s:gsub("|T.-|t", function() tex = tex + 14; return "" end)
  local w = tex
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + (FW[ch] or 7) end
  return w
end
local function txt(fs) return rawget(fs, "text_") or "" end

-- 1. Window size, tab bar ----------------------------------------------------------------------------------------
local L = RM.LAYOUT
M.check(L.width == 660 and L.height == 702, "window 660 x 702")
M.check(4 * L.tabW + 3 * L.tabGap == L.width - 28, "4 tabs x 152 + 3 gaps x 8 = 632 px usable width")
RM.Open()
local Wn = RM.Frame()
M.check(N.CurrentTab() == "materials" and RM.ShownPane() == "materials", "opens on Materials")
local names = {}
for i, tab in ipairs(N.TABS) do
  local b = Wn.tabs[tab]
  names[#names + 1] = txt(b.label)
  local p = b.points[1]
  M.check(b.w == 152 and b.h == 26 and p[1] == "TOPLEFT" and p[2] == 14 + (i - 1) * 160 and p[3] == -38, "tab " .. tab .. ": 152 x 26 at x " .. (14 + (i - 1) * 160) .. ", y -38")
  M.check(width(txt(b.label)) + 16 <= 152, "tab label fits: " .. txt(b.label))
end
M.check(table.concat(names, " | ") == "Materials | Shopping | Seeds | Alts", "tab order: Materials | Shopping | Seeds | Alts")
M.check(Wn.tabs.materials.active and Wn.tabs.materials.bar.shown and not Wn.tabs.shopping.active and not Wn.tabs.shopping.bar.shown, "active tab: gold top bar; idle tabs: none")
-- Clicking a tab: one pane shown, the others hidden, and the footer key follows.
for _, tab in ipairs({ "shopping", "seeds", "alts", "materials" }) do
  Wn.tabs[tab].scripts.OnClick(Wn.tabs[tab])
  local only = true
  for t, p in pairs(Wn.panes) do if (t == tab) ~= (p.shown == true) then only = false end end
  M.check(N.CurrentTab() == tab and only and Wn.tabs[tab].active, "click " .. tab .. ": only its pane shows")
  M.check(txt(Wn.key) == RM.FOOT_KEYS[tab], "footer key for " .. tab)
end
M.slash("/deb", "seeds")
M.check(RM.ShownPane() == "seeds", "/deb seeds shows the Seeds pane")
M.slash("/deb", "alts")
M.check(RM.ShownPane() == "alts", "/deb alts shows the Alts pane")
-- The search always opens Materials.
Wn.search.text_ = "linen cloth"
Wn.search.scripts.OnEnterPressed(Wn.search)
M.check(RM.ShownPane() == "materials" and RM.State().id == 2589, "search Enter jumps to Materials on the item")
M.slash("/deb", "shop")
RM.Open(2840)
M.check(RM.ShownPane() == "materials" and RM.State().id == 2840, "RM.Open(id) from another tab switches to Materials")

-- 2. Right Here / Nearest Spot card -------------------------------------------------------------------------------
local card = Wn.card
M.check(card.w == 632 and card.h == 38 and card.points[1][2] == 14 and card.points[1][3] == -154, "card: fixed 632 x 38 at y -154")
M.check(L.cardTop + L.cardH <= L.filtersTop and L.headerTop + 44 <= L.cardTop, "card sits between the header and the filters")
-- Nothing known
local c = RM.CalloutCard(12359, "Dun Morogh", 8)
M.check(c.kind == "none" and c.pill == nil and c.detail:find("Crafted item", 1, true), "crafted, nothing known: quiet Mist line")
RM.Navigate(12359, true)
M.check(card.quiet.shown and not card.pill.shown and not card.pillBg.shown and txt(card.quiet):find("Crafted item", 1, true), "window: quiet line, no pill")
-- Farm here: a mob counted in this zone.
Dr.ApplyShare("lnshareaaaa1", { kills = { [706] = 20, [6] = 40 }, drops = { [706] = { [2589] = { loots = 20, seen = 5 } }, [6] = { [2589] = { loots = 40, seen = 20 } } },
  names = { [706] = "Frostmane Troll Whelp", [6] = "Kobold Vermin" } }, "aaaa0001")
Dr.NoteZone(706, "Dun Morogh"); Dr.NoteZone(6, "Elwynn Forest"); bump()
c = RM.CalloutCard(2589, "Dun Morogh", 8)
M.check(c.kind == "farmHere" and c.style == "here" and c.pill == "Farm right here in Dun Morogh" and c.detail:find("Mobs: Frostmane Troll Whelp 25%", 1, true),
  "farm here: green pill + local mobs with rate")
-- Nearest spot elsewhere with the level band.
c = RM.CalloutCard(2589, "Loch Modan", 15)
M.check(c.kind == "nearest" and c.style == "away" and c.pill:find("^Nearest spot: ") and c.pill:find("%(%d+–%d+%)$"), "nearest spot: '<Zone> (lo–hi)' pill: " .. tostring(c.pill))
-- Mining sighting: gather summary.
W.Note(2770, "mine", "Dun Morogh"); W.Note(2770, "mine", "Dun Morogh"); bump()
c = RM.CalloutCard(2770, "Dun Morogh", 8)
M.check(c.kind == "farmHere" and c.detail == "You mined it there 2 times", "farm here: gathering kind and count")
-- Vendors: in your zone beats farming; elsewhere shows NPC, zone, price.
V.Record({ { id = 2320, unit = 10, avail = -1 } }, "Thrynn Bouden", "Dun Morogh", "Kharanos")
V.Record({ { id = 2321, unit = 100, avail = -1 } }, "Yanni Stoutheart", "Loch Modan", "Thelsamar")
V.Record({ { id = 2589, unit = 50, avail = -1 } }, "Cloth Seller", "Dun Morogh", "")
bump()
c = RM.CalloutCard(2320, "Dun Morogh", 8)
M.check(c.kind == "vendorHere" and c.pill == "Vendor here" and c.detail == "Thrynn Bouden (Kharanos, Dun Morogh) — 10c", "vendor here: NPC (subzone, zone) — exact price")
c = RM.CalloutCard(2589, "Dun Morogh", 8)
M.check(c.kind == "vendorHere" and c.detail:find("· Farmable here", 1, true), "vendor here and farmable: the cue is appended")
c = RM.CalloutCard(2321, "Dun Morogh", 8)
M.check(c.kind == "vendor" and c.style == "away" and c.pill == "Vendor" and c.detail == "Yanni Stoutheart (Thelsamar, Loch Modan) — 100c", "vendor elsewhere: gold pill, NPC, zone, price")
-- Unplaced mobs (no zone seen yet).
Dr.ApplyShare("lnshareaaaa2", { kills = { [99] = 20 }, drops = { [99] = { [2592] = { loots = 20, seen = 4 } } }, names = { [99] = "Wool Mob" } }, "aaaa0002"); bump()
c = RM.CalloutCard(2592, "Dun Morogh", 8)
M.check(c.kind == "unplaced" and c.detail:find("Wool Mob", 1, true), "drops from mobs with no zone yet")
-- The window card follows the item; its frame is never resized.
RM.Navigate(2320, true)
M.check(card.kind == "vendorHere" and card.pill.shown and txt(card.pill) == "Vendor here" and txt(card.detail):find("Thrynn Bouden", 1, true), "window card: vendor here")
local cardPoints = #card.points
RM.Navigate(2321, true); RM.Navigate(2589, true)
M.check(#card.points == cardPoints and card.w == 632 and card.h == 38, "card never moves or resizes")
-- Pill and badge fills are anchored to their text once (no width set at run time).
M.check(#card.pillBg.points == 2 and card.pillBg.points[1][2] == card.pill, "pill fill anchored to its text")

-- 3. Header: counts, freshness badge, + Shop --------------------------------------------------------------------
RM.Navigate(2589, true)
M.check(txt(Wn.counts):find("You have 6 (6 bags, 0 bank)", 1, true), "header counts include bags and bank")
M.check(txt(Wn.priceFrom) == "PriceLog 2h ago" and Wn.badgeBg.shown, "freshness badge: 'PriceLog 2h ago'")
M.check(RM.FreshnessBadge(12359) == "Forever baseline (Nov 27)", "bundled baseline badge: 'Forever baseline (Nov 27)'")
ns.BaselinePrices = { capturedAt = os.time({ year = 2026, month = 11, day = 7, hour = 12 }), prices = { [4306] = 900 } }
M.check(RM.FreshnessBadge(4306) == "Forever baseline (Nov 7)", "baseline badge: 'Forever baseline (Nov 7)'")
M.check(RM.FreshnessBadge(12359) == "", "no price: no badge")
RM.Navigate(12359, true)
M.check(not Wn.badgeBg.shown, "no badge fill without a price")
RM.Navigate(2996, true)   -- Bolt of Linen Cloth: crafted, so + Shop adds its missing mats
local n, msg = RM.ShopHeaderAction(2996)
M.check(n == 0 and msg:find("already have", 1, true), "+ Shop: 6 Linen in bags covers one Bolt (needs 2)")
setBag(0, { { 2318, 1 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
n = RM.ShopHeaderAction(2996)
M.check(n == 1 and S.Has(2589), "+ Shop on a crafted item adds its missing mats")
n = RM.ShopHeaderAction(2770)
M.check(n == 1 and S.Has(2770), "+ Shop on a raw material adds the item itself")
S.ClearAll()

-- 4. Materials rows: reagent counts, two profit lines, + to Shopping, filters ------------------------------------
setBag(0, { { 2589, 1 }, { 2318, 1 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
RM.SetFilter("filterMine", false)
RM.Navigate(2589, true)
local bolt
for _, e in ipairs(RM.State().list) do if e.r.product == 2996 then bolt = e end end
local _, money, reag = RM.RowText(bolt)
M.check(reag:find("2 Linen Cloth (1)", 1, true) and reag:find("|cffff5959", 1, true), "reagent line: '2 Linen Cloth (1)' in soft red when short")
M.check(money:find("buy all", 1, true) and money:find("w/ bags", 1, true), "both profit lines when you hold some mats: " .. money)
setBag(0, { { 2318, 1 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
_, money = RM.RowText(bolt)
M.check(not money:find("buy all", 1, true) and money:find("^|cff33ff33%+"), "one profit figure when you hold none: " .. money)
setBag(0, { { 2589, 6 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
_, _, reag = RM.RowText(bolt)
M.check(reag:find("|cffffffff2 Linen Cloth (6)|r", 1, true), "reagent line in white when you have enough")
-- Vendor tag on a reagent a remembered merchant sells (Coarse Thread at Thrynn Bouden).
local leatherRow
for _, r in ipairs(RM.byReagent[2320] or {}) do leatherRow = leatherRow or r end
M.check(leatherRow and RM.ReagentLine(leatherRow):find("[Vendor]", 1, true), "[Vendor] tag on a vendor-sold reagent")
-- + on a row adds the recipe's missing mats.
M.prints = {}
local row1 = Wn.rows[1]
row1.add.scripts.OnClick(row1.add)
M.check(M.printed("to Shopping") or M.printed("already have"), "row +: tells you what it did")
S.ClearAll()
-- Make now / alts / Best skill-up
RM.SetFilter("filterMakeNow", true)
local st = RM.State()
local okMake = #st.list > 0
for _, e in ipairs(st.list) do if ns.Planner.MaxCrafts(e.r) < 1 then okMake = false end end
M.check(okMake and Wn.fMake.checked and Wn.fAlts.shown, "Make now: only what your bags + bank can craft; 'Count my alts' mats' appears")
M.check(db.settings.filterMakeNow == true, "Make now is remembered")
RM.SetFilter("filterMakeNow", false)
M.check(not Wn.fAlts.shown, "'Count my alts' mats' hidden with Make now off")
RM.SetFilter("filterMakeNow", true); setBag(0, {}); M.fire("BAG_UPDATE_DELAYED"); M.advance(1); RM.Refresh()
M.check(#st.list == 0 and Wn.empty.shown and txt(Wn.empty) == "No recipes match these filters. Try unchecking Make now or Known.", "empty state for filters")
RM.SetFilter("filterMakeNow", false)
setBag(0, { { 2589, 6 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1)
Wn.skillBtn.scripts.OnClick(Wn.skillBtn)
M.check(RM.Settings().bestSkillUp and txt(Wn.skillBtn):find("Best skill-up", 1, true) and txt(Wn.skillBtn):find("|T", 1, true), "Best skill-up toggle: on, with a tick")
local rank, sorted = ns.Planner.RANK, true
for i = 2, #st.list do
  local a, b = rank[RM.Difficulty(st.list[i - 1].r) or "grey"] or 5, rank[RM.Difficulty(st.list[i].r) or "grey"] or 5
  if a > b then sorted = false end
end
M.check(sorted, "Best skill-up: orange, yellow, green, then grey")
Wn.skillBtn.scripts.OnClick(Wn.skillBtn)
M.check(not RM.Settings().bestSkillUp and txt(Wn.skillBtn) == "Best skill-up", "toggle off")
M.check(txt(Wn.count):find("^%d+ of %d+$") ~= nil, "'N of M' count on the hint line")
RM.State().id = nil; RM.Refresh()
M.check(Wn.empty.shown and txt(Wn.empty) == "Type a material above or click an item in your bags to see what it crafts.", "no item: friendly empty state")
RM.Navigate(2589, false)

-- 5. Fit: every fixed-width label in 12 pt FRIZQT ----------------------------------------------------------------
-- Filter row: four checkboxes from x 12 (24 px box, text, 14 px gap), then Best skill-up (118) and Made from (96).
local filtersRight = 12
for i, label in ipairs({ "Known", "My professions", "Has a price", "Make now" }) do filtersRight = filtersRight + 24 + width(label) + (i < 4 and 14 or 0) end
local skillLeft = L.width - 14 - 96 - 6 - 118
M.check(filtersRight + 8 <= skillLeft, ("filter row fits: checkboxes end at %d, Best skill-up starts at %d"):format(filtersRight, skillLeft))
M.check(width(RM.READY .. " Best skill-up") + 16 <= 118 and width("Made from") + 16 <= 96, "toggle and mode button labels fit")
M.check(width("Count my alts' mats") + 20 + 330 < L.width - 16 - width("999 of 999") - 8, "'Count my alts' mats' fits between the hint and the count")
M.check(width("Open a profession window once to use this filter.") + 14 < 330, "the hint ends before the alts checkbox")
for _, t in ipairs({ "Clear done", "Clear all", "Click again" }) do M.check(width(t) + 16 <= 96, "Shopping button fits: " .. t) end
M.check(width("Ready to plant") + 16 <= 124 and width("All") + 16 <= 70, "Seeds toggles fit")
M.check(width("Who can craft") + 16 <= 118 and width("Who has mats") + 16 <= 118, "Alts toggles fit")
M.check(width("Export Drops") + 16 <= 110 and width("Import Drops") + 16 <= 110 and width("+ Shop") + 16 <= 64, "share and + Shop buttons fit")
for _, s in ipairs({ "Ready to plant", "Ready to hybridize", "Needs a Greenhouse", "In your bank", "In your bags" }) do
  M.check(width(s) <= 616 - 44 - 422 - 8 - 8, "seed status fits beside the role line: " .. s)
end
M.check(width("Vendor total: 999g 99s 99c") <= 200 - 8, "Shopping header right text fits")
for _, t in pairs(RM.SHOP_STATUS) do M.check(width(t) <= RM.SHOP_STATUS_W, "Shopping status line fits: " .. t) end
-- Status runs from x 14; the total is right-aligned at -16 and is at most about 270 px wide with coin icons.
M.check(14 + RM.SHOP_STATUS_W + 8 <= L.width - 16 - 270, "Shopping status line ends before the total")
M.check(L.rowsTop + L.rows * L.rowH + 10 + 18 + L.chainH + 10 + 4 + 18 <= RM.LayoutY().footRule, "drops line ends above the footer rule")
M.check(L.listTop + L.listRows * L.rowH <= RM.LayoutY().footRule - 8 and L.listTop + L.seedRows * L.rowH <= RM.LayoutY().footRule, "list wells end above the footer")

-- 6. Shopping pane -----------------------------------------------------------------------------------------------
db.alts["TestRealm-Horde-Bankalt"] = { name = "Bankalt", realm = "TestRealm", faction = "Horde", learned = { [2996] = true },
  skills = { Tailoring = 75 }, bags = { [2589] = 1, [2318] = 5 }, bank = { [2320] = 3 } }
bump()
N.ShowTab("shopping")
local lists = RM.PaneLists()
local shop = lists.shopping
M.check(shop.empty.shown and txt(shop.empty) == RM.SHOP_EMPTY, "empty Shopping: one friendly sentence")
S.AddItem(2589, 8, "Bolt of Linen Cloth"); S.AddItem(2320, 4, "Heavy Armor Kit"); S.AddItem(2321, 2); S.AddItem(2318, 4); S.AddItem(3858, 5); S.AddItem(2678, 2)
RM.RefreshTab("shopping")
local E = RM.ShoppingEntries("Dun Morogh")
local function find(kind, pat) for i, e in ipairs(E) do if e.kind == kind and (e.text or e.name or ""):find(pat, 1, true) then return e, i end end end
local vsec, vi = find("section", "Vendor")
local thrynn, ti = find("group", "Thrynn Bouden (Kharanos, Dun Morogh)")
local forever = find("group", "Vendor (visit merchant to remember NPC)")
local _, ai = find("section", "Grab from Alt")
local ahsec, hi = find("section", "AH")
M.check(vsec and vi == 1 and vsec.right:find("^Vendor total: "), "Vendor section first, with its exact copper total")
M.check(thrynn and ti == 2 and thrynn.right == "subtotal 10c", "vendor group: NPC (subzone, zone) with copper subtotal")
M.check(forever ~= nil, "vendor-sold with no remembered NPC: 'Vendor (visit merchant to remember NPC)'")
M.check(ai and hi and vi < ai and ai < hi, "sections in order: Vendor, Grab from Alt, AH")
local coarse = find("item", "Coarse Thread")
M.check(coarse and coarse.line2 == "Need 1 × 10c = 10c" and coarse.right1 == "10c", "vendor row: 'Need N × unit = line copper'")
local leather = find("item", "Light Leather")
M.check(leather and leather.category == "alt" and leather.line2 == "On Bankalt: 5 bags, 0 bank  ·  grab 4", "alt row: 'On Bankalt: 5 bags, 0 bank'")
local mith = find("item", "Mithril")
M.check(mith and mith.category == "ah" and mith.right1:find("no price yet", 1, true) and ahsec.right:find("+ unpriced", 1, true), "AH row without a price: never 0g")
local linenRow = find("item", "Linen Cloth")
M.check(linenRow and linenRow.right1 == "~33c" and linenRow.right2 == "price 2h old" and linenRow.line2:find("^Need 8"), "AH row: estimate, need text, price age")
M.check(txt(RM.Frame().panes.shopping and lists.shopping.slots[1].hdr) == "Vendor", "first slot shows the Vendor header")
M.check(RM.ShoppingFor():find("Bolt of Linen Cloth", 1, true) and RM.ShoppingFor():find("Heavy Armor Kit", 1, true), "'Missing for:' lists what the lines are for")
M.check(RM.ShoppingTotal():find("^Total ~") and RM.ShoppingTotal():find("unpriced", 1, true), "total with '+ unpriced'")
-- Tick done, remove, clear.
local slot
for _, s in ipairs(shop.slots) do if rawget(s, "entry") and s.entry.itemID == 3858 then slot = s end end
M.check(slot and slot.check.shown and slot.remove.shown, "item rows have a done tick and a remove button")
slot.check.checked = true; slot.check.scripts.OnClick(slot.check)
M.check(db.shopping.items[3858].done, "tick marks the line done")
E = RM.ShoppingEntries("Dun Morogh")
M.check(find("section", "Done") and find("item", "Mithril").category == "done", "done lines move to a Done section")
for _, s in ipairs(shop.slots) do if rawget(s, "entry") and s.entry.itemID == 2321 then slot = s end end
slot.remove.scripts.OnClick(slot.remove)
M.check(not S.Has(2321), "remove button takes the line off")
-- Clear done, Clear all (asks twice).
local panes = RM.Frame().panes
local function button(pane, label)
  for _, f in ipairs(M.frames) do if rawget(f, "text_") == label then return f end end
end
local clearDone = button(panes.shopping, "Clear done")
clearDone.scripts.OnClick(clearDone)
M.check(not S.Has(3858), "Clear done")
local clearAll = button(panes.shopping, "Clear all")
clearAll.scripts.OnClick(clearAll)
M.check(S.Count() > 0 and txt(clearAll) == "Click again", "Clear all: first click only arms it")
clearAll.scripts.OnClick(clearAll)
M.check(S.Count() == 0 and txt(clearAll) == "Clear all", "second click clears")
clearAll.scripts.OnClick(clearAll); M.advance(5)
M.check(not clearAll.armed and txt(clearAll) == "Clear all", "an armed Clear all resets after 4 seconds")
-- Status line and click-to-search.
S.AddItem(2589, 8)
RM.RefreshTab("shopping")
M.check(txt(panes.shopping and lists.shopping.slots[1].hdr) ~= "", "rows back after adding")
local searched = 0
AuctionHouseFrame = M.frameObj("AuctionHouseFrame")
rawset(AuctionHouseFrame, "SearchBar", { StartSearch = function() end })
rawset(AuctionHouseFrame, "SetSearchText", function(_, name) searched = searched + 1; AuctionHouseFrame.lastSearch = name; return true end)
ns.Prices.ahOpen = true
for _, s in ipairs(shop.slots) do if rawget(s, "entry") and s.entry.itemID == 2589 then slot = s end end
slot.scripts.OnClick(slot)
M.check(searched == 1 and AuctionHouseFrame.lastSearch == "Linen Cloth", "AH open: clicking a row searches it")
ns.Prices.ahOpen = false
slot.scripts.OnClick(slot)
M.check(searched == 1, "AH closed: no search")
S.ClearAll()

-- 7. Seeds pane --------------------------------------------------------------------------------------------------
N.ShowTab("seeds")
local seeds = RM.PaneLists().seeds
M.check(seeds.empty.shown and txt(seeds.empty) == SE.EMPTY, "no seeds: friendly sentence")
setBag(0, { { 268415, 3 }, { 279964, 1 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1); bump()
RM.RefreshTab("seeds")
local se = RM.SeedEntries("all")
local commonplace
for _, e in ipairs(se) do if e.itemID == 268415 then commonplace = e end end
M.check(commonplace and commonplace.name:find("(bags 3, bank 0)", 1, true) and commonplace.line2:find("Peacebloom or Earthroot", 1, true)
  and commonplace.right1 == "~20c" and commonplace.right2:find("Ready to plant", 1, true), "seed row: counts, role, crop value, ready")
M.check(seeds.slots[1].shown and not seeds.empty.shown, "rows shown")
RM.SetSeedFilter("ready")
M.check(RM.SeedFilter() == "ready" and #seeds.entries >= 1, "Ready to plant filter")
setBag(0, { { 268415, 3 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1); bump(); RM.RefreshTab("seeds")
M.check(#seeds.entries == 0 and txt(seeds.empty):find("Nothing is ready", 1, true), "nothing ready: says so")
RM.SetSeedFilter("all")
M.check(#seeds.entries == 1 and RM.SeedShortHint(seeds.entries[1].row) == "Needs a Greenhouse", "seed without a Greenhouse: short status")
tipLines = {}
seeds.slots[1].scripts.OnEnter(seeds.slots[1])
M.check(table.concat(tipLines, "\n"):find("In your bags: bag 1 slot 1", 1, true) and table.concat(tipLines, "\n"):find("never uses or plants", 1, true), "seed tooltip: bag slot, never automated")
setBag(0, { { 2589, 6 } }); M.fire("BAG_UPDATE_DELAYED"); M.advance(1); bump()

-- 8. Alts pane ---------------------------------------------------------------------------------------------------
db.alts["TestRealm-Horde-Bankalt"] = nil; bump()
N.ShowTab("alts")
local al = RM.PaneLists().alts
M.check(al.empty.shown and txt(al.empty) == RM.ALTS_EMPTY, "only one character: the 'log in on your other characters' sentence")
db.alts["TestRealm-Horde-Bankalt"] = { name = "Bankalt", realm = "TestRealm", faction = "Horde", learned = { [2996] = true },
  skills = { Tailoring = 75 }, bags = { [2589] = 1, [2318] = 5 }, bank = { [2320] = 3 } }
db.alts["TestRealm-Horde-Lowbie"] = { name = "Lowbie", realm = "TestRealm", faction = "Horde", learned = {}, skills = { Tailoring = 1 }, bags = {}, bank = {} }
bump()
RM.State().selected = nil
RM.Navigate(2996, false)
local ae, ctx = RM.AltEntries("craft", "")
M.check(ctx:find("^Who can craft: Bolt of Linen Cloth") and ae[1].name:find("^Bankalt · Tailoring 75 · Knows recipe") and ae[1].line2:find("Can craft it", 1, true),
  "who can craft: the alt who knows it first")
local low
for _, e in ipairs(ae) do if e.name:find("^Lowbie") then low = e end end
local need = ns.RM.byProduct[2996][1].skill
M.check(need and need > 1 and low and low.line2:find(("Skill 1, needs %d"):format(need), 1, true), "an alt below the recipe's skill: 'Skill 1, needs N'")
ae, ctx = RM.AltEntries("craft", "bolt of wool")
M.check(ctx:find("Bolt of Woolen Cloth", 1, true), "typing a crafted item in the box picks it")
RM.SetAltsMode("mats")
M.check(RM.AltsMode() == "mats", "Who has mats mode")
ae = RM.AltEntries("mats", "")
local linenMats
for _, e in ipairs(ae) do if e.itemID == 2589 then linenMats = e end end
M.check(linenMats and linenMats.name:find("Linen Cloth |cffffffff— 7 total", 1, true) and linenMats.line2:find("Kenny 6", 1, true) and linenMats.line2:find("Bankalt 1", 1, true),
  "who has mats: totals per character")
M.check(#RM.AltEntries("mats", "bankalt") >= 1 and #RM.AltEntries("mats", "zzzz") == 0, "the filter box filters by item or character")
RM.SetAltsFilter("light lea")
local first = al.slots[1]
M.check(rawget(first, "entry") and first.entry.itemID == 2318, "filtered list on screen")
first.scripts.OnClick(first)
M.check(RM.ShownPane() == "materials" and RM.State().id == 2318, "clicking a mats row opens it in Materials")
RM.SetAltsFilter(""); RM.SetAltsMode("craft")

-- 9. Compact tooltips: vendor line, here line, Shift-expand -----------------------------------------------------
tipLines, tipColors = {}, {}
RM.AddTooltipLines(GameTooltip, 2320, false)
local vline
for i, l in ipairs(tipLines) do if l:find("^Vendor here: ") then vline = i end end
M.check(vline and tipLines[vline] == "Vendor here: Thrynn Bouden (Kharanos, Dun Morogh) — 10c" and tipColors[vline][1] == 0.45 and tipColors[vline][2] == 1,
  "local vendor: one bright green 'Vendor here' line")
tipLines, tipColors = {}, {}
RM.AddTooltipLines(GameTooltip, 2321, false)
for i, l in ipairs(tipLines) do if l:find("^Vendor: ") then vline = i end end
M.check(tipLines[vline] == "Vendor: Yanni Stoutheart (Thelsamar, Loch Modan) — 100c" and tipColors[vline][1] == 1 and tipColors[vline][2] == 0.82,
  "vendor elsewhere: one gold 'Vendor' line")
tipLines = {}
RM.AddTooltipLines(GameTooltip, 2589, false)
local compact = #tipLines
M.check(compact <= 5 and tipLines[#tipLines] == "Hold Shift for full crafting breakdown", "compact by default, quiet Shift hint last (" .. compact .. " lines)")
M.check(tipLines[1]:find("best Bolt of Linen Cloth +", 1, true) ~= nil, "line 1: best use with profit")
tipLines = {}
shift = true
RM.AddTooltipLines(GameTooltip, 2589)
local full = table.concat(tipLines, "\n")
shift = false
M.check(#tipLines > compact + 3 and full:find("Best uses:", 1, true) and full:find("Vendors you've seen:", 1, true) and full:find("Cloth Seller", 1, true)
  and not full:find("Hold Shift", 1, true), "Shift: best uses and every remembered vendor, in place")
tipLines = {}
RM.AddTooltipLines(GameTooltip, 2996, true)
full = table.concat(tipLines, "\n")
M.check(full:find("Made from: 2 Linen Cloth", 1, true) and full:find("Bankalt · Tailoring 75 · Knows recipe", 1, true), "Shift on a crafted item: reagents and which alt can craft it")
-- Secret item ids never reach the tooltip lines.
M.secret[2589] = true
tipLines = {}
ns.Compat.SafeNumber(2589)
M.check(ns.Compat.SafeNumber(2589) == nil, "secret ids are dropped by C.SafeNumber (tooltip guard)")
M.secret[2589] = nil

-- 10. Export / Import (DEBDATA second line) -----------------------------------------------------------------------
N.ShowTab("materials")
Wn.exportBtn.scripts.OnClick(Wn.exportBtn)
local ew = _G["KennyDwarfExplorersBibleDropExportWindow"]
local exportText = ew.edit:GetText()
M.check(exportText:find("^DEB1:") and exportText:find("\nDEB2:", 1, true), "Export Drops: line 1 drops, line 2 sightings (vendors + gathering)")
Wn.importBtn.scripts.OnClick(Wn.importBtn)
local iw = _G["KennyDwarfExplorersBibleDropImportWindow"]
M.check(iw.shown and txt(iw.title):find("one or both lines", 1, true), "Import window asks for one or both lines")
tipLines = {}
Wn.exportBtn.scripts.OnEnter(Wn.exportBtn)
M.check(table.concat(tipLines, "\n"):find("Line 2: vendors and gathering spots", 1, true), "Export tooltip explains both lines")

-- 11. Combat safety: no SetPoint / SetSize / SetWidth / SetHeight / ClearAllPoints while in combat ----------------
local layoutCalls, afterCalls = 0, 0
local seen = {}
local function watch(obj)
  if seen[obj] then return end
  seen[obj] = true
  for _, k in ipairs({ "SetPoint", "SetSize", "SetWidth", "SetHeight", "ClearAllPoints", "SetAllPoints" }) do
    local prev = rawget(obj, k)
    rawset(obj, k, function(...) if M.combat then layoutCalls = layoutCalls + 1 else afterCalls = afterCalls + 1 end if prev then return prev(...) end end)
  end
  for _, kid in ipairs(rawget(obj, "kids") or {}) do watch(kid) end
end
for _, f in ipairs(M.frames) do watch(f) end
for _, f in ipairs(M.frames) do for _, kid in ipairs(rawget(f, "kids") or {}) do watch(kid) end end
S.AddItem(2589, 8); S.AddItem(2320, 2)
M.combat = true
for _, tab in ipairs({ "shopping", "seeds", "alts", "materials" }) do Wn.tabs[tab].scripts.OnClick(Wn.tabs[tab]) end
RM.Navigate(2840, true); RM.Navigate(2996, true); RM.GoBack()
Wn.rows[2].scripts.OnEnter(Wn.rows[2]); Wn.rows[1].scripts.OnEnter(Wn.rows[1])
RM.SetFilter("filterMakeNow", true); RM.SetFilter("filterMakeNow", false)
Wn.skillBtn.scripts.OnClick(Wn.skillBtn); Wn.skillBtn.scripts.OnClick(Wn.skillBtn)
RM.UpdateSearch("copp"); RM.UpdateSearch("")
RM.SetDropsOverlay(true); RM.SetDropsOverlay(false)
N.ShowTab("shopping")
for _, s in ipairs(shop.slots) do if rawget(s, "entry") and s.entry.itemID == 2589 then s.check.checked = true; s.check.scripts.OnClick(s.check) end end
RM.SetSeedFilter("ready"); RM.SetSeedFilter("all")
N.ShowTab("alts"); RM.SetAltsMode("mats"); RM.SetAltsFilter("linen"); RM.SetAltsFilter(""); RM.SetAltsMode("craft")
RM.Open(2589)
M.check(layoutCalls == 0, "in combat: tabs, navigation, filters, search, overlay and every pane change no layout (" .. layoutCalls .. " calls)")
M.check(RM.LayoutPending(), "width-dependent layout is queued for after combat")
M.check(RM.ShownPane() == "materials" and RM.State().id == 2589 and Wn.chain[1].id == 2589, "still works in combat: page, strip text")
M.combat = false
afterCalls = 0
M.fire("PLAYER_REGEN_ENABLED")
M.check(not RM.LayoutPending() and afterCalls > 0, "combat over: the skipped layout runs once")
S.ClearAll()

-- 12. Style rules: 12 pt fonts, in-game textures, FRIZQT glyphs ------------------------------------------------
local okFonts = { GameFontNormal = true, GameFontHighlight = true, GameFontDisable = true, GameFontNormalLarge = true,
  GameFontHighlightLarge = true, GameFontNormalHuge = true }
for _, file in ipairs({ "UI.lua", "UITabs.lua" }) do
  local src = io.open(file):read("*a")
  local bad
  for f in src:gmatch('"(GameFont%w+)"') do if not okFonts[f] then bad = f end end
  M.check(bad == nil and not src:find("SetFont%("), file .. ": no font object under 12 pt (" .. tostring(bad) .. ")")
  local badTex
  for path in src:gmatch('"(Interface\\\\[^"]+)"') do if not path:find("^Interface\\\\[%a]+\\\\") then badTex = path end end
  for path in src:gmatch('"Interface\\\\AddOns[^"]*"') do badTex = path end
  M.check(badTex == nil, file .. ": only Blizzard textures (" .. tostring(badTex) .. ")")
end
-- Glyphs the client font has (checked in FRIZQT__.TTF's cmap): ASCII plus these. No arrows or tick marks.
local okGlyph = { ["·"] = true, ["—"] = true, ["–"] = true, ["×"] = true, ["…"] = true }
for _, file in ipairs({ "UI.lua", "UITabs.lua", "Shopping.lua", "Alts.lua", "Seeds.lua", "Nav.lua", "Where.lua", "Vendors.lua",
  "Planner.lua", "Inventory.lua", "DwarfExplorersBible.lua", "DropShare.lua", "ShareData.lua", "Drops.lua", "Prices.lua" }) do
  local bad
  for ch in io.open(file):read("*a"):gmatch("[\194-\244][\128-\191]+") do if not okGlyph[ch] then bad = ch end end
  M.check(bad == nil, file .. ": every character is in FRIZQT (" .. tostring(bad) .. ")")
end
M.done("UI tabs (1.3.0)")
