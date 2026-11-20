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
M.check(db.schema == 2 and type(db.drops) == "table" and type(db.dropKills) == "table", "1.1.0 save migrated to schema 2 with drop tables")
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
local char = db.chars["TestRealm-Horde-Kenny"]
char.skills.Tailoring = 50
local mine = RM.FilterList(all, s)
local onlyTailoring = #mine > 0
for _, e in ipairs(mine) do if e.r.prof ~= "Tailoring" then onlyTailoring = false end end
M.check(onlyTailoring and #mine < #all, "'My professions' keeps only your professions (" .. #mine .. " of " .. #all .. ")")
M.check(#RM.FilterList(all, { filterKnown = true }) == 0, "'Known' with nothing learned hides everything")
M.check(#RM.FilterList(all, { filterPriced = true }) == 0, "'Has a price' with no prices hides everything")

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
M.check(steps2[1].id == 2840 and steps2[1].sub == "start here" and steps2[2].current, "came from Copper Bar: it starts the chain")
M.check(steps2[2].sub ~= "start here" and steps2[2].sub ~= "", "...and the current step says how it's made from it (" .. tostring(steps2[2].sub) .. ")")
M.check(#steps2 <= RM.LAYOUT.chainSteps, "chain capped at " .. RM.LAYOUT.chainSteps .. " steps")
RM.GoBack()
M.check(st.id == 2840, "Back returns (click mode)")
r2.scripts.OnEnter(r2)
M.check(st.selected ~= st.list[2], "click mode: pointing at a row doesn't move the strip")
RM.LAYOUT.STRIP_MODE = "hover"
M.check(RM.LAYOUT.width == 660 and RM.LAYOUT.height == 632 and RM.LAYOUT.bg[4] == 1, "660x632, opaque background")
local name, counts, price = RM.HeaderText(268418)
M.check(name == "Scarce Herb Seeds" and counts:find("Plant Seeds (1) at a Greenhouse", 1, true) and counts:find("hybridized", 1, true)
  and price:find("no price yet", 1, true), "camp header: plant only, can't be hybridized, no price yet")

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
M.check(ns.Data.lootCasts[8613] == "gather" and ns.Data.lootCasts[2575] == "gather" and ns.Data.lootCasts[2366] == "gather"
  and ns.Data.lootCasts[3365] == "gather" and ns.Data.lootCasts[921] == "pickpocket", "loot casts from DB2: Skinning, Mining, Herb Gathering, Opening, Pick Pocket")
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
M.check(tip:find("from your " .. db.dropKills[299] .. " kills", 1, true) and tip:find("Linen Cloth", 1, true), "mob tooltip: rate, 'from your N kills'")
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
M.check(title == ("Drops from (your %d kills)"):format(db.drops[299][2589].loots)
  and sum:find("Timber Wolf", 1, true) and sum:find("from your " .. db.drops[299][2589].loots .. " kills", 1, true) and #list == 1, "material page 'Drops from'")
-- 'your N kills' counts only the mobs listed: add a second mob under 20 kills that dropped linen.
db.drops[1922][2589] = { loots = 5, seen = 2 }
local title2, sum2, list2 = RM.DropsSummary(2589)
M.check(title2 == title and #list2 == 1 and sum2:find("Timber Wolf", 1, true), "'your N kills' counts only the listed mobs, not the ones under 20")
M.check(RM.DropsSummary(2934) == "Drops from", "no mob listed yet: plain 'Drops from'")
RM.Open(2589)
local Wd = RM.Frame()
M.check(Wd.dropsTitle:GetText() == title, "window shows the Drops from line")
-- The overlay: + opens it, and the same button (now -), Escape and Back each close it.
local histBefore = #st.history
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
M.check(RM.DropsOverlayShown() and Wd.dropsPanel.lines[1]:GetText():find("Timber Wolf", 1, true), "+ opens the drops list")
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
M.check(not RM.DropsOverlayShown(), "- in the same spot closes it")
Wd.dropsToggle.scripts.OnClick(Wd.dropsToggle)
Wd.dropsPanel.scripts.OnKeyDown(Wd.dropsPanel, "ESCAPE")
M.check(not RM.DropsOverlayShown(), "Escape closes it")
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
M.done("UI and drops")
