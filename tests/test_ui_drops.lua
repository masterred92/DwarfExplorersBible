-- 1.2.0: the new window (filters remembered, word-start search, chain strip) and trade-goods drops learned from
-- your own kills (secret values skipped, each corpse counted once, a rate only after 20 kills).
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
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[kind] = fn end }
Enum = { TooltipDataType = { Item = 0, Unit = 2 }, ItemClass = { Tradegoods = 7 }, LootSlotType = { Item = 1, Money = 2 } }
hooksecurefunc = function() end

-- Item classes the client knows (GetItemInfoInstant): trade goods are class 7. 99999 is an item the client hides.
local CLASS = { [2589] = 7, [2318] = 7, [2934] = 7, [4865] = 15, [2840] = 7 }
C_Item = { GetItemInfoInstant = function(id) if CLASS[id] then return id, "", "", "", 134400, CLASS[id], 0 end end }

-- An existing 1.1.0 save: schema 1 with one changed setting.
KennyDwarfExplorersBibleDB = { schema = 1, settings = { tooltip = false }, chars = {}, extra = {}, names = {}, cache = {} }

local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
local RM, Dr = ns.RM, ns.Drops
local db = KennyDwarfExplorersBibleDB

-- 1. SavedVariables: migration and filter defaults ----------------------------------------------
M.check(db.schema == 4 and type(db.drops) == "table" and type(db.dropKills) == "table" and type(db.dropShares) == "table" and type(db.dropShareId) == "string", "1.1.0 save migrated to schema 4 with drop tables and share id")
M.check(db.settings.tooltip == false, "existing settings kept")
local s = RM.Settings()
M.check(s.filterMine == true and s.filterKnown == false and s.filterPriced == false, "only 'My professions' ticked at first")
M.check(db.settings.filterMine == nil and db.settings.filterKnown == nil, "defaults aren't written into the save")
RM.SetFilter("filterKnown", true)
M.check(db.settings.filterKnown == true, "ticking Known is remembered in SavedVariables")
RM.SetFilter("filterMine", false)
M.check(db.settings.filterMine == false, "unticking My professions is remembered")
RM.SetFilter("filterKnown", false); RM.SetFilter("filterMine", true)
M.check(db.settings.filterKnown == nil and db.settings.filterMine == nil, "back to the defaults stores nothing")

-- 2. Filters ---------------------------------------------------------------------------------
local all = RM.UsesOf(2589)
M.check(#RM.FilterList(all, s) == #all, "no profession seen yet: 'My professions' lets everything through")
local char = db.alts["TestRealm-Horde-Kenny"]
char.skills.Tailoring = 50
local mine = RM.FilterList(all, s)
local onlyTailoring = #mine > 0
for _, e in ipairs(mine) do if e.r.prof ~= "Tailoring" then onlyTailoring = false end end
M.check(onlyTailoring and #mine < #all, "'My professions' keeps only your professions (" .. #mine .. " of " .. #all .. ")")
M.check(#RM.FilterList(all, { filterKnown = true }) == 0, "'Known' with nothing learned hides everything")
M.check(#RM.FilterList(all, { filterPriced = true }) > 0, "'Has a price' keeps recipes the bundled baseline can fully price")
local savedBaseline = ns.BaselinePrices
ns.BaselinePrices = nil
M.check(#RM.FilterList(RM.UsesOf(2589), { filterPriced = true }) == 0, "'Has a price' with no live prices and no baseline hides everything")
ns.BaselinePrices = savedBaseline

-- 3. Search matches the start of words ------------------------------------------------------
local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end
local copp = RM.Search("copp")
M.check(has(copp, 2840) and has(copp, 4359), "'copp' finds Copper Bar and Handful of Copper Bolts")
M.check(#RM.Search("opper") == 0, "'opper' matches nothing (not the start of a word)")
M.check(has(RM.Search("bolts"), 4359), "'bolts' matches a later word")
M.check(RM.Search("copper bar")[1] == 2840, "an exact name comes first")
M.check(RM.WordStartMatch("handful of copper bolts", "of c") and not RM.WordStartMatch("silverleaf", "leaf"), "word-start matcher")
M.check(not RM.WordStartMatch("dwarf's beard", "s beard"), "an apostrophe doesn't start a word")
local rows, total = RM.SearchPopup("copp")
M.check(#rows == 8 and total > 8 and rows[1].id == copp[1] and rows[1].right:find("used in", 1, true), "popup: 8 rows, total count, 'used in N'")

-- 4. Window, chain strip --------------------------------------------------------------------
-- The "My professions" hint: shown while no profession window has been seen, gone once one has.
local savedSkills = char.skills; char.skills = {}
RM.Open(2840)
M.check(RM.ShownPane() == "materials", "first open straight onto an item shows the Materials pane")
local W = RM.Frame()
M.check(W.hint:IsShown() and W.hint:GetText() == "Open a profession window once to use this filter.", "grey hint under the filters until a profession is seen")
char.skills = savedSkills; RM.Refresh()
M.check(not W.hint:IsShown(), "hint hidden once you have a profession")
RM.SetFilter("filterMine", false)
M.check(RM.FilterHint() == nil, "no hint with 'My professions' off")

-- Hover mode (the default): one click opens a row; the strip follows the row you point at and stays there.
M.check(RM.LAYOUT.STRIP_MODE == "hover", "hover strip is the default")
local st = RM.State()
M.check(st.id == 2840 and #st.list > 1 and st.selected == nil, "hover: no row in the strip before you point at one")
local own = RM.ChainSteps(2840, nil)
M.check(own[1].id == 2840 and own[1].current and own[2] and own[2].id == RM.BestNext(2840).r.product, "before any hover: the page item's own chain")
M.check(W.chainLabel:GetText() == "Crafting chain for the row you point at:", "hover strip label")
M.check(W.chain[1].id == 2840 and W.chain[1].cur:IsShown() and not W.chain[2].cur:IsShown(), "gold outline on the page's own item only")
local r1, r2 = W.rows[1], W.rows[2]
r2.scripts.OnEnter(r2)
M.check(st.selected == st.list[2] and st.id == 2840 and W.chain[2].id == st.list[2].r.product, "pointing at a row puts it in the strip")
r2.scripts.OnLeave(r2)
M.check(st.selected == st.list[2], "the strip stays on that row after the mouse leaves")
r1.scripts.OnEnter(r1)
M.check(st.selected == st.list[1], "...and follows the next row you point at")
local opened = st.list[1].r.product
r1.scripts.OnClick(r1)
M.check(st.id == opened and st.history[#st.history] == 2840 and st.selected == nil, "one click opens the row")
RM.GoBack()
M.check(st.id == 2840, "Back returns")
local stepBtn = W.chain[2]
local stepId = stepBtn.id
stepBtn.scripts.OnClick(stepBtn)
M.check(st.id == stepId and stepId ~= 2840, "clicking a strip step opens that item")
RM.GoBack()

-- The strip comes from recipe data only, never from the breadcrumb (UI Bot, render of 0be3b11).
local function linked(steps)   -- each step is made from the one before it
  for i = 2, #steps do
    local ok = false
    for _, r in ipairs(RM.byReagent[steps[i - 1].id] or {}) do if r.product == steps[i].id then ok = true end end
    if not ok then return false end
  end
  return true
end
local function has2840(steps) for _, x in ipairs(steps) do if x.id == 2840 then return true end end return false end
RM.Navigate(2589, true)    -- Linen Cloth, opened from Copper Bar
local ls = RM.ChainSteps(2589, nil)
M.check(st.history[#st.history] == 2840 and ls[1].id == 2589 and ls[1].sub == "start here" and ls[1].current and #ls >= 2 and linked(ls) and not has2840(ls),
  "Linen Cloth from Copper Bar: 'Linen Cloth (start here) > ...', not the previous page")
M.check(W.chain[1].id == 2589 and W.chain[1].cur:IsShown(), "the window's strip starts on Linen Cloth too")
W.rows[1].scripts.OnEnter(W.rows[1])
local hs = RM.ChainSteps(2589, st.selected)
M.check(hs[1].id == 2589 and hs[2].id == st.selected.r.product and linked(hs) and not has2840(hs) and #hs <= 3, "pointing at a row: Linen Cloth > that row > its best next step")
RM.Navigate(2840, true); RM.Navigate(2996, true)    -- Bolt of Linen Cloth, opened from Copper Bar
W.modeBtn.scripts.OnClick(W.modeBtn)
M.check(st.mode == "made", "Made from mode")
local ms = RM.ChainSteps(2996, nil)
M.check(#ms == 2 and ms[1].id == 2589 and ms[1].sub == "reagent" and ms[2].id == 2996 and ms[2].current and ms[2].sub:find("Tailoring", 1, true) and not has2840(ms),
  "Made from: the recipe's reagent first (Linen Cloth > Bolt of Linen Cloth), not the previous page")
W.rows[1].scripts.OnEnter(W.rows[1])
local mh = RM.ChainSteps(2996, st.selected)
M.check(mh[1].id == st.selected.r.reagents[1].id and mh[#mh].id == 2996 and not has2840(mh), "Made from, pointing at a recipe: its first reagent > this item")
M.check(W.chainLabel:GetText() == "Where the selected recipe's reagent comes in:", "Made from strip label")
RM.Navigate(2840, true)

-- Header: "Not crafted" instead of "Made by 0".
local _, linenCounts = RM.HeaderText(2589)
M.check(linenCounts:find("Not crafted", 1, true) and not linenCounts:find("Made by", 1, true), "nothing makes it: 'Not crafted', never 'Made by 0'")
local _, barCounts = RM.HeaderText(2840)
M.check(barCounts:find("Made by |cffffffff1|r (Mining)", 1, true), "Copper Bar: 'Made by 1 (Mining)'")

-- Scrollbar only when the list doesn't fit.
M.check(#st.list > RM.LAYOUT.rows and W.scroll.shown, "long list: scrollbar shown")
RM.SetFilter("filterKnown", true)
M.check(#st.list <= RM.LAYOUT.rows and not W.scroll.shown, "everything fits: scrollbar hidden")
RM.SetFilter("filterKnown", false)

-- Text size: every font object is 12 pt or larger (GameFontNormal/Highlight/Disable are FRIZQT 12 in Forever's
-- FontStyles.xml; Large/Huge are bigger), including both footer lines.
local ui = io.open("UI.lua"):read("*a")
local okFonts = { GameFontNormal = true, GameFontHighlight = true, GameFontDisable = true, GameFontNormalLarge = true,
  GameFontHighlightLarge = true, GameFontNormalHuge = true }
local badFont
for f in ui:gmatch('"(GameFont%w+)"') do if not okFonts[f] then badFont = f end end
M.check(badFont == nil and not ui:find("SetFont%("), "no font object under 12 pt (" .. tostring(badFont) .. ")")
M.check(ui:find('local key = fontString(win, "GameFontHighlight"', 1, true) and ui:find('win.foot = fontString(win, "GameFontDisable"', 1, true),
  "footer colour key and price note use 12 pt font objects")

-- Recipe name colours: difficulty colour, or white with no skill data (never gold).
local seenWhite, wrong = false, false
for _, row in ipairs(W.rows) do rawset(row.name, "SetTextColor", function(fs, r, g, b) fs.rgb = { r, g, b } end) end
RM.Refresh()
for _, row in ipairs(W.rows) do
  if row.entry then
    local d = RM.Difficulty(row.entry.r)
    local want = d and RM.COLORS.DIFF[d] or RM.COLORS.WHITE
    if not row.name.rgb or row.name.rgb[1] ~= want[1] or row.name.rgb[2] ~= want[2] or row.name.rgb[3] ~= want[3] then wrong = true end
    if not d then seenWhite = true end
  end
end
M.check(seenWhite and not wrong, "rows with no skill data are white (1,1,1), the rest their difficulty colour")

-- Click mode (LAYOUT.STRIP_MODE = "click"): the first click puts a row in the strip, a second opens it.
RM.LAYOUT.STRIP_MODE = "click"
RM.Navigate(2840, false)
M.check(st.id == 2840 and #st.list > 0 and st.selected == st.list[1], "click mode: the most profitable row starts in the chain strip")
M.check(W.chainLabel:GetText() == "Crafting chain for the selected row:", "click strip label")
local steps = RM.ChainSteps(2840, st.selected)
local best = RM.BestNext(st.selected.r.product)
M.check(steps[#steps].id == (best and best.r.product or st.selected.r.product), "chain ends with the selected row's most profitable next step")
M.check(steps[1].current and steps[1].sub == "start here", "no history: this item is where the chain starts")
local second = st.list[2]
RM.ClickRow(second)
M.check(st.selected == second and st.id == 2840, "clicking a row switches the chain strip, no navigation")
RM.ClickRow(second)
M.check(st.id == second.r.product and st.history[#st.history] == 2840, "clicking the selected row opens its item")
local steps2 = RM.ChainSteps(st.id, st.selected)
M.check(steps2[1].id == st.id and steps2[1].sub == "start here" and steps2[1].current and steps2[1].id ~= 2840,
  "came from Copper Bar: the strip still starts on this item, not the previous page")
M.check(#steps2 <= RM.LAYOUT.chainSteps, "chain capped at " .. RM.LAYOUT.chainSteps .. " steps")
RM.GoBack()
M.check(st.id == 2840, "Back returns (click mode)")
r2.scripts.OnEnter(r2)
M.check(st.selected ~= st.list[2], "click mode: pointing at a row doesn't move the strip")
RM.LAYOUT.STRIP_MODE = "hover"
M.check(RM.LAYOUT.width == 660 and RM.LAYOUT.height == 702 and RM.LAYOUT.bg[4] == 1, "660x702 (1.3.0: +30 tab bar, +40 callout card), opaque background")
local name, counts, price, from = RM.HeaderText(268418)
M.check(name == "Scarce Herb Seeds" and counts:find("Plant Seeds (1) at a Greenhouse", 1, true) and counts:find("hybridized", 1, true)
  and price == "309c" and from == "each, from Forever baseline", "camp header: plant only, can't be hybridized, bundled baseline price")

-- 5. Drop learner ---------------------------------------------------------------------------
local WOLF = "Creature-0-4372-0-1-299-0000A1B2C3"
local loot = {}            -- slots: { kind, link, qty, sources = { guid, n, ... } }
local fishing, targetGUID, targetDead = false, nil, false
GetNumLootItems = function() return #loot end
GetLootSlotType = function(i) return loot[i].kind end
GetLootSlotInfo = function(i) return 134400, loot[i].name or "x", loot[i].qty or 1, nil, 1 end
GetLootSlotLink = function(i) return loot[i].link end
GetLootSourceInfo = function(i) return unpack(loot[i].sources) end
IsFishingLoot = function() return fishing end
UnitGUID = function(u) if u == "target" then return targetGUID end; if u == "player" then return "Player-1-0001" end end
UnitIsDead = function(u) return u == "target" and targetDead end
UnitName = function(u) if u == "player" then return "Kenny" end; if u == "target" and targetGUID == WOLF then return "Timber Wolf" end end
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[x]|h|r" end
local function corpse(guid, items)
  loot = { { kind = 2, sources = { guid, 1 } } }   -- coins
  for _, id in ipairs(items) do loot[#loot + 1] = { kind = 1, link = link(id), sources = { guid, 1 } } end
end
local n = 0
local function wolf(items) n = n + 1; local g = ("Creature-0-4372-0-1-299-%010X"):format(n); corpse(g, items); M.fire("LOOT_OPENED", false, false); return g end

for i = 1, 19 do wolf(i % 4 == 0 and { 2589, 4865 } or {}) end     -- Linen Cloth on every 4th corpse, plus junk
M.check(db.dropKills[299] == 19 and db.drops[299][2589].loots == 19 and db.drops[299][2589].seen == 4, "19 wolves counted, linen in 4")
M.check(db.drops[299][4865] == nil, "trade goods only (junk not stored)")
M.check(#Dr.RatesFor(299) == 0, "no rate below 20 kills")
local _, summary = RM.DropsSummary(2589)
M.check(summary:find("after 20", 1, true), "material page: still learning")
local last = wolf({ 2589 })
M.check(db.drops[299][2589].loots == 20 and db.drops[299][2589].seen == 5, "20th kill")
local rates = Dr.RatesFor(299)
M.check(#rates == 1 and rates[1].item == 2589 and Dr.Percent(rates[1]) == 25, "rate shown at 20 kills: 25%")

-- Each corpse once: reopening it (and the /reload-proof list) doesn't count it again.
M.fire("LOOT_OPENED", false, false)
corpse(last, {}); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == 20 and db.drops[299][2589].loots == 20, "a reopened corpse isn't counted twice")

-- A new item: earlier corpses were read in full and didn't have it.
wolf({ 2318 })
M.check(db.drops[299][2318].loots == 21 and db.drops[299][2318].seen == 1 and db.drops[299][2589].loots == 21, "new item starts at the kill count")

-- AoE loot: one window, two corpses; each counted once, the item only on its own corpse.
local a, b = "Creature-0-4372-0-1-299-00000AAAA1", "Creature-0-4372-0-1-1922-00000BBBB2"
loot = { { kind = 1, link = link(2589), sources = { a, 1 } }, { kind = 2, sources = { a, 1, b, 1 } } }
M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == 22 and db.dropKills[1922] == 1 and db.drops[1922][2589] == nil and db.drops[299][2589].seen == 6, "AoE loot split per corpse")

-- Secret or hidden values: the whole window is skipped.
local kills = db.dropKills[299]
local g1 = ("Creature-0-4372-0-1-299-%010X"):format(9001)
corpse(g1, { 2589 }); M.secret[g1] = true; M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "secret mob GUID: corpse skipped")
local secretLink = link(2934)
local g2 = ("Creature-0-4372-0-1-299-%010X"):format(9002)
corpse(g2, { 2589, 2934 }); loot[3].link = secretLink; M.secret[secretLink] = true; M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills and db.drops[299][2934] == nil and db.drops[299][2589].seen == 6, "secret item: whole corpse skipped")
local g3 = ("Creature-0-4372-0-1-299-%010X"):format(9003)
corpse(g3, { 99999 }); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "item the client hides: corpse skipped")
corpse(g1, {}); M.secret[g1] = nil
loot[1].sources = { g1, 1 }; loot[2] = { kind = 1, link = nil, sources = { g1, 1 } }
M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "item slot with no readable link: skipped")
local secretN = {}
GetNumLootItems = function() return secretN end; M.secret[secretN] = true
M.fire("LOOT_OPENED", false, false)
GetNumLootItems = function() return #loot end
M.check(db.dropKills[299] == kills, "secret slot count: skipped")

-- Not a kill's loot: an item you opened, fishing, skinning right after a cast, a chest.
corpse(("Creature-0-4372-0-1-299-%010X"):format(9100), { 2589 }); M.fire("LOOT_OPENED", false, true)
M.check(db.dropKills[299] == kills, "loot from an item is ignored")
fishing = true; M.fire("LOOT_OPENED", false, false); fishing = false
M.check(db.dropKills[299] == kills, "fishing loot is ignored")
local skinned = ("Creature-0-4372-0-1-299-%010X"):format(9200)
corpse(skinned, { 2318 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8613); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "a loot window right after your Skinning cast is ignored")
M.advance(10); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "...and that corpse can't be counted later")
M.check(ns.Data.lootCasts[8613] == "skin" and ns.Data.lootCasts[2575] == "open" and ns.Data.lootCasts[2366] == "open"
  and ns.Data.lootCasts[3365] == "open" and ns.Data.lootCasts[921] == "pickpocket", "loot casts from DB2: Skinning (95), Mining / Herb Gathering / Opening (33), Pick Pocket (71)")
M.check(ns.Data.lootCasts[75] == nil and ns.Data.lootCasts[5019] == nil and ns.Data.lootCasts[133] == nil, "Auto Shot, Shoot, Fireball aren't loot casts")
-- Combat casts (Auto Shot, Shoot, Fireball) right before looting don't skip or retire the corpse.
local shot = ("Creature-0-4372-0-1-299-%010X"):format(9210)
corpse(shot, { 2589 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 75); M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 133)
M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "a kill looted right after Auto Shot / Fireball is counted")
kills = kills + 1
-- Pick Pocket: skipped, but the living mob isn't retired, so its corpse counts after the kill.
local mark = ("Creature-0-4372-0-1-299-%010X"):format(9220)
corpse(mark, { 2589 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 921); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "Pick Pocket loot is ignored")
M.advance(10); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "...and that mob's corpse still counts once it's killed and looted")
kills = kills + 1
-- A hidden window is retired: reopening that corpse (now readable, half looted) doesn't count it.
local half = ("Creature-0-4372-0-1-299-%010X"):format(9230)
corpse(half, { 2589, 2934 }); local hl = link(2934); loot[3].link = hl; M.secret[hl] = true
M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "hidden item: window skipped")
M.secret[hl] = nil; corpse(half, { 2589 }); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "...and the reopened, half-looted corpse isn't counted either")
-- Only creature corpses are retired; with no GetLootSourceInfo, an Opening-type cast (a chest, a node) doesn't retire
-- your dead target, but a skinning-type cast does.
local chest = ("GameObject-0-4372-0-1-1617-%010X"):format(7)
corpse(chest, { 2589 }); M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 3365); M.fire("LOOT_OPENED", false, false)
local chestRetired = false
for _, g in ipairs(db.dropDone) do if g == chest then chestRetired = true end end
M.check(not chestRetired, "a chest's GUID is never put on the done list")
M.advance(10)
GetLootSourceInfo = nil
local deadMob = ("Creature-0-4372-0-1-299-%010X"):format(9250)
targetGUID, targetDead = deadMob, true
corpse(deadMob, { 2589 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", 3365); M.fire("LOOT_OPENED", false, false)   -- opening a chest next to it
M.check(db.dropKills[299] == kills, "Opening cast: that window is skipped...")
M.advance(10); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "...but your dead target's own loot still counts afterwards")
kills = kills + 1
local skinMob = ("Creature-0-4372-0-1-299-%010X"):format(9251)
targetGUID = skinMob; corpse(skinMob, { 2318 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 8613); M.fire("LOOT_OPENED", false, false)
M.advance(10); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills, "Skinning cast: the dead target is retired (its later window isn't counted)")
targetGUID, targetDead = nil, false
GetLootSourceInfo = function(i) return unpack(loot[i].sources) end

-- Casts are registered for the player only, and a hidden spell ID is ignored.
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", 8613); M.advance(0.1)
local sp = {}; M.secret[sp] = true; M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", sp)
local other = ("Creature-0-4372-0-1-299-%010X"):format(9240)
corpse(other, { 2589 }); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "a party member's Skinning or a hidden spell ID doesn't block your kill")
kills = kills + 1
M.advance(10)
corpse(("GameObject-0-4372-0-1-1617-%010X"):format(1), { 2589 }); M.fire("LOOT_OPENED", false, false)
M.check(db.drops[1617] == nil and db.dropKills[299] == kills, "chests (game objects) aren't mobs")

-- Fallback when the client has no GetLootSourceInfo: your dead target.
GetLootSourceInfo = nil
local tg = ("Creature-0-4372-0-1-299-%010X"):format(9300)
targetGUID, targetDead = tg, true
corpse(tg, { 2589 }); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "no GetLootSourceInfo: the dead target is the corpse")
targetDead = false
corpse(("Creature-0-4372-0-1-299-%010X"):format(9301), { 2589 }); M.fire("LOOT_OPENED", false, false)
M.check(db.dropKills[299] == kills + 1, "...and nothing is counted when the target isn't dead")
GetLootSourceInfo = function(i) return unpack(loot[i].sources) end

-- Mob names from your target.
targetGUID, targetDead = WOLF, true
corpse(WOLF, {}); M.fire("LOOT_OPENED", false, false)
M.check(db.mobNames[299] == "Timber Wolf", "mob name learned from your target")
targetGUID, targetDead = nil, false

-- 6. Where it shows ---------------------------------------------------------------------------
db.settings.tooltip = nil
tipLines = {}
postCalls[2](GameTooltip, { guid = WOLF, lines = { { leftText = "Timber Wolf" } } })
local tip = table.concat(tipLines, "\n")
M.check(tip:find("from " .. db.dropKills[299] .. " kills", 1, true) and not tip:find("from your ", 1, true) and tip:find("Linen Cloth", 1, true), "mob tooltip: rate, 'from N kills'")
M.check(tip:find("Light Leather = 4%", 1, true) and tip:find("Linen Cloth = ", 1, true), "every trade good over the threshold, with its rate")
M.check(tip:find("Linen Cloth", 1, true) < tip:find("Light Leather", 1, true), "most likely first")
tipLines = {}
local secretGuid = "Creature-0-1-0-1-299-F1"; M.secret[secretGuid] = true
postCalls[2](GameTooltip, { guid = secretGuid })
M.check(#tipLines == 0, "secret mob GUID on the tooltip: nothing added")
tipLines = {}
postCalls[2](GameTooltip, { guid = "Creature-0-4372-0-1-1922-00000BBBB9" })
M.check(#tipLines == 1 and tipLines[1] == "Learning drops: 1 of 20 kills", "mob under 20 kills: only the grey 'Learning drops' line")
tipLines = {}
postCalls[2](GameTooltip, { guid = WOLF, lines = { { leftText = "Timber Wolf" } } })
M.check(not table.concat(tipLines, "\n"):find("Learning drops", 1, true), "no 'Learning drops' line at 20+ kills")
tipLines = {}
postCalls[2](GameTooltip, { guid = "Creature-0-4372-0-1-3-00000CCCC1" })
M.check(#tipLines == 0, "a mob you've never looted: nothing added")
local title, sum, list = RM.DropsSummary(2589)
M.check(title == ("Drops from (%d kills)"):format(db.drops[299][2589].loots)
  and sum:find("Timber Wolf", 1, true) and sum:find("from " .. db.drops[299][2589].loots .. " kills", 1, true) and not sum:find("from your ", 1, true) and #list == 1, "material page 'Drops from'")
-- 'N kills' counts only the mobs listed: add a second mob under 20 kills that dropped linen.
db.drops[1922][2589] = { loots = 5, seen = 2 }
Dr.InvalidateCombined()
local title2, sum2, list2 = RM.DropsSummary(2589)
M.check(title2 == title and #list2 == 1 and sum2:find("Timber Wolf", 1, true), "'N kills' counts only the listed mobs, not the ones under 20")
M.check(RM.DropsSummary(2934) == "Drops from", "no mob listed yet: plain 'Drops from'")
RM.Open(2589)
local Wd = RM.Frame()
M.check(Wd.dropsTitle:GetText() == title, "window shows the Drops from line")
-- The overlay: + opens it, and the same button (now -), Escape and Back each close it.
local histBefore = #st.history
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
M.check(RM.DropsOverlayShown() and Wd.dropsPanel.lines[1]:GetText():find("Timber Wolf", 1, true), "+ opens the drops list")
M.check(Wd.dropsPanel.title:GetText() == title, "overlay header row: 'Drops from (N kills)'")
M.check(not Wd.scroll.shown, "the recipe list's scrollbar is hidden under the overlay")
Wd.dropsPanel.close.scripts.OnClick(Wd.dropsPanel.close)
M.check(not RM.DropsOverlayShown(), "the (-) in the overlay's header closes it")
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
M.check(not RM.DropsOverlayShown(), "- in the same spot closes it")
-- Escape = Blizzard's CloseSpecialWindows (UIParentPanelManager.lua 1106-1116): pairs over the live UISpecialFrames,
-- Hide() on each shown frame (which runs its OnHide). Then the frame ends, so anything deferred with C_Timer runs.
local function escape()
  for _, n in pairs(UISpecialFrames) do
    local f = _G[n]
    if f and f.shown then f.shown = false; if f.scripts.OnHide then f.scripts.OnHide(f) end end
  end
  M.advance(0)
end
local function special(n) for _, x in pairs(UISpecialFrames) do if x == n then return true end end return false end
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
M.check(special("KennyDwarfExplorersBibleDrops") and not special("KennyDwarfExplorersBibleFrame"), "overlay open: it, not the window, answers Escape")
escape()
M.check(not RM.DropsOverlayShown() and Wd.shown and special("KennyDwarfExplorersBibleFrame") and not special("KennyDwarfExplorersBibleDrops"),
  "Escape closes the overlay only; the window stays and answers the next Escape")
M.check(not Wd.scroll.shown == not (#st.list > RM.LAYOUT.rows), "scrollbar back (if the list needs it) after Escape")
M.combat = true
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle); escape()
M.check(not RM.DropsOverlayShown() and Wd.shown, "in combat too (nothing restricted is called)")
M.combat = false
-- A frame added to UISpecialFrames after the overlay opened (load-on-demand UI does this): one Escape closes the
-- overlay and that frame, not the window; the next Escape closes the window. (Mutating the table during
-- CloseSpecialWindows' pairs loop skipped the other frame and hid the window.)
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
local lod = CreateFrame("Frame", "TestLoadOnDemandFrame"); lod.shown = true
tinsert(UISpecialFrames, "TestLoadOnDemandFrame")
escape()
M.check(not RM.DropsOverlayShown() and not lod.shown and Wd.shown, "one Escape: the overlay and the other frame close, the window stays open")
M.check(special("KennyDwarfExplorersBibleFrame") and not special("KennyDwarfExplorersBibleDrops"), "...and the window is back in UISpecialFrames")
escape()
M.check(not Wd.shown, "a second Escape closes the window")
for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "TestLoadOnDemandFrame" then table.remove(UISpecialFrames, i) end end
RM.Open(2589)
M.check(Wd.shown and st.id == 2589, "window reopened")
local uiSrc = io.open("UI.lua"):read("*a")
M.check(not uiSrc:find("OnKeyDown", 1, true) and not uiSrc:find("EnableKeyboard", 1, true) and not uiSrc:find("SetPropagateKeyboardInput", 1, true),
  "the window never takes the keyboard, so it can't swallow keybinds")
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
Wd.back.scripts.OnClick(Wd.back)
M.check(not RM.DropsOverlayShown() and st.id == 2589 and #st.history == histBefore, "Back closes it and stays on the page")

-- 7. Reads only: no API that loots, casts, targets or moves.
for _, f in ipairs({ "Drops.lua", "UI.lua", "DwarfExplorersBible.lua" }) do
  local src = io.open(f):read("*a")
  for _, bad in ipairs({ "LootSlot%(", "CloseLoot", "CastSpell", "TargetUnit", "InteractUnit", "AssistUnit", "FollowUnit", "MoveForward",
    "SetCVar", "ConfirmLootSlot", "UseContainerItem", "RunMacro" }) do
    M.check(not src:find(bad), f .. " never calls " .. bad)
  end
end
-- Overlay with more mobs than fit: no scrollbar, the last line says how many more.
for cid = 5000, 5019 do db.drops[cid] = { [2934] = { loots = 20, seen = 5 } } end
Dr.InvalidateCombined()
RM.Navigate(2934, true); RM.SetDropsOverlay(true)
local P, fitN = RM.Frame().dropsPanel, RM.DropsLines()
M.check(#P.lines == fitN and fitN < 20 and P.lines[fitN].shown and P.lines[fitN]:GetText():find("+" .. (20 - fitN + 1) .. " more mobs", 1, true),
  "overlay: " .. fitN .. " lines fit, the last says how many more")
RM.SetDropsOverlay(false)
M.done("UI and drops")
