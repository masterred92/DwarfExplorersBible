-- A 1.2.1 save (schema 3) moves to 1.3.0 (schema 4) without losing anything.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.installLDB()
GameTooltip = M.frameObj("GameTooltip")
UISpecialFrames, tinsert = {}, table.insert
TooltipDataProcessor = { AddTooltipPostCall = function() end }
hooksecurefunc = function() end
KennyDwarfExplorersBibleDB = { schema = 3, settings = { tooltip = false, sources = "auctionator,pricelog,tsm,auctioneer,scan" },
  chars = { ["TestRealm-Horde-Kenny"] = { learned = { [2996] = true }, skills = { Tailoring = 50 } },
    ["TestRealm-Horde-Bankalt"] = { learned = {}, skills = { Mining = 120 } } },
  extra = {}, names = {}, cache = {}, drops = { [706] = { [2589] = { seen = 5, loots = 20 } } }, dropKills = { [706] = 20 },
  dropDone = {}, dropShares = {}, dropShareId = "abcdef123456", mobNames = { [706] = "Frostmane Troll Whelp" } }
local ns = M.loadAddon(".", "DwarfExplorersBible")
M.fire("PLAYER_LOGIN")
local db = KennyDwarfExplorersBibleDB
M.check(db.schema == 4 and db.chars == nil, "schema 3 -> 4")
M.check(db.alts["TestRealm-Horde-Kenny"].learned[2996] and db.alts["TestRealm-Horde-Kenny"].skills.Tailoring == 50, "learned recipes and skills kept")
M.check(db.alts["TestRealm-Horde-Bankalt"].skills.Mining == 120 and db.alts["TestRealm-Horde-Bankalt"].name == "Bankalt", "alts kept, named from their key")
M.check(db.settings.tooltip == false and ns.Prices.Order(db.settings.sources)[1] == "auctionator" and ns.Prices.Order(db.settings.sources)[6] == "baseline",
  "settings kept; baseline added last")
M.check(db.dropKills[706] == 20 and db.dropShareId == "abcdef123456" and ns.Drops.Kills(706) == 20, "drop data and share id kept")
M.check(type(db.vendors.list) == "table" and type(db.shopping.order) == "table" and type(db.gather) == "table" and type(db.sightShares) == "table" and type(db.mobZones) == "table",
  "new tables created")
M.done("migration to 1.3.0")
