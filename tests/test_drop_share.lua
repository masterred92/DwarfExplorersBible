-- Drop sharing: export/import strings, merge/dedup, wording, and party/guild sync.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.installLDB()
GameTooltip = M.frameObj("GameTooltip")
rawset(GameTooltip, "AddLine", function() end)
rawset(GameTooltip, "AddDoubleLine", function() end)
UISpecialFrames, tinsert = {}, table.insert
GetMoneyString = function(c) return c .. "c" end
TooltipDataProcessor = { AddTooltipPostCall = function() end }
Enum = { TooltipDataType = { Item = 0, Unit = 2 }, ItemClass = { Tradegoods = 7 }, LootSlotType = { Item = 1 } }
hooksecurefunc = function() end
C_Item = { GetItemInfoInstant = function() end }

KennyDwarfExplorersBibleDB = { schema = 1, settings = {}, chars = {}, extra = {}, names = {}, cache = {} }
local ns = M.loadAddon(".", "DwarfExplorersBible")
local RM, Dr, Sh = ns.RM, ns.Drops, ns.DropShare
local db = KennyDwarfExplorersBibleDB
db.dropShareId = "alicehost01"

local function fillPersonal()
  db.drops[299] = { [2589] = { loots = 20, seen = 5 }, [2318] = { loots = 20, seen = 1 } }
  db.dropKills[299] = 20
  db.mobNames[299] = "Timber Wolf"
  db.dropDone = { "Creature-0-4372-0-1-299-0000000001" }
end
fillPersonal()

local function snapOf(sid, kills, drops, names)
  return Sh.Encode(sid, { kills = kills, drops = drops, names = names or {} })
end

-- 1. Serialization is stable and does not include dropDone or imported shares --------------
local text = Sh.EncodePersonal()
M.check(type(text) == "string" and text:find("^DEB1:alicehost01:%x%x%x%x%x%x%x%x:", 1), "export starts with DEB1:id:checksum:")
M.check(text:find("299,20,Timber Wolf,2318:1:20,2589:5:20", 1, true) or text:find("299,20,Timber Wolf,2589:5:20,2318:1:20", 1, true), "export has wolf counts and name")
M.check(not text:find("Creature-", 1, true) and not text:find("dropDone", 1, true), "export never includes corpse GUIDs")
M.check(Sh.EncodePersonal() == text, "export is deterministic")
db.dropShares["otherplayer1"] = { hash = "ffffffff", kills = { [1922] = 40 }, drops = { [1922] = { [2589] = { loots = 40, seen = 8 } } }, names = { [1922] = "Gray Wolf" } }
M.check(not Sh.EncodePersonal():find("1922", 1, true), "export is personal only: imported mobs are left out")
db.dropShares = {}

-- 2. Names with reserved characters escape and come back ----------------------------------
local odd = Sh.Encode("bobhostaaaa", { kills = { [7] = 20 }, drops = { [7] = { [1] = { loots = 20, seen = 3 } } },
  names = { [7] = [[A/B:C,D%E]] } })
local dec, sid = Sh.Decode(odd)
M.check(sid == "bobhostaaaa" and dec.names[7] == "A/B:C,D%E", "name with / : , % round-trips")

-- 3. Newlines around a string are tolerated; malformed input never throws ------------------
local wrapped = "\n  " .. text .. "\n"
local d2, sid2, err2
M.check(pcall(function() d2, sid2, _, err2 = Sh.Decode(wrapped) end) and d2 and sid2 == "alicehost01" and not err2, "newlines around an export still parse")
local badCases = { "", "   ", "hello", "DEB1:short:deadbeef:", "DEB1:abcdefgh:zzzzzzzz:", "DEB1:abcdefgh:00000000:299,20,Wolf", "DEB1" }
for _, s in ipairs(badCases) do
  local ok, snap, _, _, err = pcall(Sh.Decode, s)
  M.check(ok and snap == nil and err ~= nil, "malformed rejected without error: " .. tostring(s))
end
-- Valid header and checksum, but one item has seen > loots: that item is skipped, the mob stays.
local rec = "299,20,Wolf,2589:99:20,2318:1:20"
local h = Sh.Hash("charlieaaaa:" .. rec)
local mixed, msid = Sh.Decode("DEB1:charlieaaaa:" .. h .. ":" .. rec)
M.check(msid == "charlieaaaa" and mixed.kills[299] == 20 and mixed.drops[299][2318] and not mixed.drops[299][2589],
  "item with seen > loots is skipped; the rest of the mob is kept")

-- 4. Merge: same source replaces; different sources add; own export is ignored -------------
local doneBefore = #db.dropDone
local friend = snapOf("bobhostaaaa", { [299] = 10, [1922] = 20 }, {
  [299] = { [2589] = { loots = 10, seen = 4 } },
  [1922] = { [2589] = { loots = 20, seen = 5 } },
}, { [299] = "Timber Wolf", [1922] = "Gray Wolf" })
local ok, kind = Sh.Import(friend, true)
M.check(ok and kind == "added", "first import from bob is added")
M.check(Dr.Kills(299) == 30 and Dr.Kills(1922) == 20, "combined kills sum personal + bob")
local rates = Dr.RatesFor(299)
local linen
for _, e in ipairs(rates) do if e.item == 2589 then linen = e end end
M.check(linen and linen.loots == 30 and linen.seen == 9, "linen is 5/20 yours + 4/10 from bob")
-- Gray Wolf has 20 loots from bob only: a rate shows (MIN_LOOTS).
local src = Dr.SourcesOf(2589)
local gray
for _, e in ipairs(src.rows) do if e.cid == 1922 then gray = e end end
M.check(gray and gray.loots == 20, "a mob only bob has farmed is listed once it reaches 20 combined kills")
ok, kind = Sh.Import(friend, true)
M.check(ok and kind == "same" and Dr.Kills(299) == 30, "pasting the same string twice does not double the numbers")
-- Bob farms more and exports again: replace, don't add on top of his old snapshot.
local friend2 = snapOf("bobhostaaaa", { [299] = 15, [1922] = 20 }, {
  [299] = { [2589] = { loots = 15, seen = 6 } },
  [1922] = { [2589] = { loots = 20, seen = 5 } },
}, { [1922] = "Gray Wolf" })
ok, kind = Sh.Import(friend2, true)
M.check(ok and kind == "replaced" and Dr.Kills(299) == 35 and linen, "a later export from bob replaces his earlier snapshot")
linen = nil
for _, e in ipairs(Dr.RatesFor(299)) do if e.item == 2589 then linen = e end end
M.check(linen and linen.loots == 35 and linen.seen == 11, "linen is now 5/20 yours + 6/15 from bob, not 4+6")
-- A third person adds on top.
local cara = snapOf("carahostaaa", { [299] = 5 }, { [299] = { [2589] = { loots = 5, seen = 1 } } }, {})
Sh.Import(cara, true)
M.check(Dr.Kills(299) == 40, "a different account is added to the combined total")
ok, kind = Sh.Import(text, true)
M.check((not ok) and kind == "own" and Dr.Kills(299) == 40, "importing your own export is ignored")
M.check(#db.dropDone == doneBefore and db.dropDone[1] == "Creature-0-4372-0-1-299-0000000001", "import never writes dropDone")

-- 5. 10 of yours + 10 shared reaches the 20-kill threshold --------------------------------
db.drops, db.dropKills, db.mobNames, db.dropShares = {}, {}, {}, {}
db.drops[700] = { [2589] = { loots = 10, seen = 2 } }
db.dropKills[700] = 10
db.mobNames[700] = "Prowler"
M.check(#Dr.RatesFor(700) == 0, "10 personal kills: still learning")
Sh.Import(snapOf("bobhostaaaa", { [700] = 10 }, { [700] = { [2589] = { loots = 10, seen = 3 } } }, { [700] = "Prowler" }), true)
local r700 = Dr.RatesFor(700)
M.check(#r700 == 1 and r700[1].loots == 20 and r700[1].seen == 5 and Dr.Kills(700) == 20, "10 + 10 combined kills shows a rate")
M.check(Dr.Label(20) == "from 20 kills" and not Dr.Label(20):find("your", 1, true), "label is 'from N kills'")
local title, sum = RM.DropsSummary(2589)
M.check(title == "Drops from (20 kills)" and sum:find("from 20 kills", 1, true) and not (title .. sum):find("your", 1, true),
  "material page uses combined 'from N kills' wording")

-- 6. Export / Import windows: SetMaxLetters(0), buttons, slash -----------------------------
Sh.OpenExport()
local ew = _G["KennyDwarfExplorersBibleDropExportWindow"]
M.check(ew and ew.shown and ew.edit and ew.edit.maxLetters == 0, "export window EditBox has SetMaxLetters(0)")
M.check(ew.edit:GetText():find("^DEB1:", 1) and ew.edit.highlighted, "export window shows the string selected")
M.check(ew.action and ew.action.shown, "export window has a Copy button")
ew.action.scripts.OnClick(ew.action)
M.check(type(M.clipboard) == "string" and M.clipboard:find("^DEB1:", 1), "Copy writes the drop string to the clipboard")
ew:Hide()
Sh.OpenImport()
local iw = _G["KennyDwarfExplorersBibleDropImportWindow"]
M.check(iw and iw.shown and iw.edit and iw.edit.maxLetters == 0 and iw.action and iw.action.shown, "import window: SetMaxLetters(0) and Import button")
iw.edit:SetText(snapOf("davehostaaa", { [800] = 20 }, { [800] = { [2589] = { loots = 20, seen = 4 } } }, { [800] = "Bear" }))
iw.action.scripts.OnClick(iw.action)
M.check(Dr.Kills(800) == 20 and not iw.shown, "Import button applies the string and closes the window")
M.prints = {}
M.slash("/deb", "export")
M.check(_G["KennyDwarfExplorersBibleDropExportWindow"].shown, "/deb export opens the export window")
M.slash("/deb", "import")
M.check(_G["KennyDwarfExplorersBibleDropImportWindow"].shown, "/deb import opens the import window")

-- 7. Combat / lockdown gating, chunking, reassembly, secrets, no ping-pong -----------------
-- Restore a known personal set and clear shares so the payload is small or large as needed.
db.drops, db.dropKills, db.mobNames, db.dropShares = { [299] = { [2589] = { loots = 20, seen = 5 } } }, { [299] = 20 }, { [299] = "Timber Wolf" }, {}
-- A large snapshot so the payload is split into several chunks.
for cid = 10000, 10080 do
  db.dropKills[cid] = 20
  db.drops[cid] = { [2589] = { loots = 20, seen = 3 } }
  db.mobNames[cid] = "Mob" .. cid
end
Sh.ResetComms()
M.addonMessages, M.combat, M.lockdown = {}, true, false
M.group.inGroup, M.group.guild = true, false
M.check(select(1, Sh.CanSend()) == false and select(2, Sh.CanSend()) == "combat", "CanSend is false in combat")
Sh.Flush()
M.check(#M.addonMessages == 0 and Sh.Pending() and Sh.QueueSize() == 0, "Flush in combat sends nothing and stays pending")
M.combat, M.lockdown = false, true
M.check(select(2, Sh.CanSend()) == "lockdown", "CanSend is false in chat-messaging lockdown")
Sh.Flush()
M.check(#M.addonMessages == 0, "Flush in lockdown sends nothing")
M.lockdown = false
Sh.ResetComms(); M.addonMessages = {}
Sh.SetPending(true)
M.fire("PLAYER_REGEN_ENABLED")
M.check(#M.addonMessages > 0, "leaving combat flushes a pending send")
local payload = Sh.EncodePersonal()
local chunks = Sh.BuildChunks(payload)
M.check(#chunks > 1, "a large export is split into several chunks")
for i, c in ipairs(chunks) do
  M.check(#c <= Sh.MAX_CHUNK, "chunk " .. i .. " is at most 240 bytes (" .. #c .. ")")
end
M.advance(Sh.SEND_GAP * (#chunks + 5))
-- Outbound messages: one announce plus the data chunks, all with a clean prefix and PARTY.
local announces, dataMsgs, bad = 0, 0, false
for _, m in ipairs(M.addonMessages) do
  if m.prefix ~= Sh.PREFIX or M.secret[m.prefix] or M.secret[m.message] or M.secret[m.chatType] then bad = true end
  if m.chatType ~= "PARTY" then bad = true end
  if type(m.message) == "string" and m.message:sub(1, 2) == "A:" then announces = announces + 1
  elseif type(m.message) == "string" and m.message:sub(1, 2) == "D:" then dataMsgs = dataMsgs + 1 end
end
M.check(not bad and announces >= 1 and dataMsgs == #chunks, "outbound messages are non-secret, on PARTY, with announce + all chunks")

-- Reassembly out of order, from a named peer, applies once.
db.dropShares = {}
Sh.ResetComms()
local peerSnap = { kills = {}, drops = {}, names = {} }
for cid = 20000, 20070 do
  peerSnap.kills[cid] = 20
  peerSnap.drops[cid] = { [2589] = { loots = 20, seen = 2 } }
  peerSnap.names[cid] = "Peer" .. cid
end
local peerText = Sh.Encode("evehostaaaa", peerSnap)
local peerChunks = Sh.BuildChunks(peerText)
M.check(#peerChunks > 1, "peer payload is also chunked")
-- Deliver last chunk first, then the rest; incomplete until the last missing one arrives.
Sh.OnAddonMessage(Sh.PREFIX, peerChunks[#peerChunks], "PARTY", "Eve")
M.check(db.dropShares["evehostaaaa"] == nil, "no import until every chunk has arrived")
for i = 1, #peerChunks - 1 do Sh.OnAddonMessage(Sh.PREFIX, peerChunks[i], "PARTY", "Eve") end
M.check(db.dropShares["evehostaaaa"] and db.dropShares["evehostaaaa"].kills[20000] == 20, "out-of-order chunks reassemble and import")
local killsBefore = Dr.Kills(20000)
-- Deliver the same chunks again: same hash, no double count.
for i = 1, #peerChunks do Sh.OnAddonMessage(Sh.PREFIX, peerChunks[i], "PARTY", "Eve") end
M.check(Dr.Kills(20000) == killsBefore, "receiving the same snapshot again does not double counts")

-- Secret fields on CHAT_MSG_ADDON are ignored (the whole message is skipped).
db.dropShares = {}
local secretSender, secretText = "SecretEve", peerChunks[1]
M.secret[secretSender] = true
Sh.OnAddonMessage(Sh.PREFIX, secretText, "PARTY", secretSender)
M.check(db.dropShares["evehostaaaa"] == nil, "secret sender: message ignored")
M.secret[secretSender] = nil
M.secret[secretText] = true
Sh.OnAddonMessage(Sh.PREFIX, secretText, "PARTY", "Eve")
M.check(db.dropShares["evehostaaaa"] == nil, "secret message body: ignored")
M.secret[secretText] = nil
local secretPrefix = Sh.PREFIX
-- Use a distinct secret value equal to the prefix string: mark the same string.
-- issecretvalue keys off the value; mark a unique token instead and pass it as prefix.
local secretPref = "DEBDROPS" -- same string as prefix; marking it would also mark the constant.
-- Pass a different secret prefix token.
local hiddenPrefix = "HIDDENPFX"; M.secret[hiddenPrefix] = true
Sh.OnAddonMessage(hiddenPrefix, peerText, "PARTY", "Eve")
M.check(db.dropShares["evehostaaaa"] == nil, "secret prefix: ignored")
M.secret[hiddenPrefix] = nil

-- Receiving a share does not start a broadcast of our data (no ping-pong).
Sh.ResetComms(); M.addonMessages = {}
Sh.OnAddonMessage(Sh.PREFIX, peerChunks[1], "PARTY", "Eve")
M.check(Sh.QueueSize() == 0 and #M.addonMessages == 0, "receiving data chunks does not enqueue a send of our own data")

-- Announce from a new peer requests their data once; a second announce is rate-limited.
Sh.ResetComms(); M.addonMessages = {}
local peerHash = peerText:match("^DEB1:[%w]+:(%x+):")
Sh.OnAddonMessage(Sh.PREFIX, "A:evehostaaaa:" .. peerHash, "PARTY", "Eve")
-- Pump any query: CanSend is true, startPump ran inside maybeQuery.
M.advance(1)
local q = 0
for _, m in ipairs(M.addonMessages) do
  if type(m.message) == "string" and m.message:sub(1, 2) == "Q:" then q = q + 1 end
end
M.check(q == 1, "an announce for a hash we don't have sends one query")
Sh.OnAddonMessage(Sh.PREFIX, "A:evehostaaaa:" .. peerHash, "PARTY", "Eve")
M.advance(1)
local q2 = 0
for _, m in ipairs(M.addonMessages) do
  if type(m.message) == "string" and m.message:sub(1, 2) == "Q:" then q2 = q2 + 1 end
end
M.check(q2 == 1, "a second announce for the same hash is not queried again immediately")

-- Answering a query: only if they asked for our current hash, and only once per DATA_GAP.
Sh.ResetComms(); M.addonMessages = {}
local ours = Sh.EncodePersonal()
local ourHash = ours:match("^DEB1:[%w]+:(%x+):")
Sh.OnAddonMessage(Sh.PREFIX, "Q:alicehost01:" .. ourHash, "PARTY", "Eve")
M.advance(Sh.SEND_GAP * (#Sh.BuildChunks(ours) + 5))
local dcount = 0
for _, m in ipairs(M.addonMessages) do
  if type(m.message) == "string" and m.message:sub(1, 2) == "D:" then dcount = dcount + 1 end
end
M.check(dcount == #Sh.BuildChunks(ours), "a query for our current hash is answered with the data chunks")
local after = #M.addonMessages
Sh.OnAddonMessage(Sh.PREFIX, "Q:alicehost01:" .. ourHash, "PARTY", "Eve")
M.advance(Sh.SEND_GAP * 5)
M.check(#M.addonMessages == after, "a second query for the same hash within the data gap is not answered again")

-- Guild and raid channels are chosen correctly; throttle is retried.
Sh.ResetComms(); M.addonMessages = {}; M.group.inGroup, M.group.inRaid, M.group.guild = false, true, true
Sh.SetPending(true); Sh.Flush(); M.advance(Sh.SEND_GAP * 400)
local sawRaid, sawGuild, sawParty = false, false, false
for _, m in ipairs(M.addonMessages) do
  if m.chatType == "RAID" then sawRaid = true end
  if m.chatType == "GUILD" then sawGuild = true end
  if m.chatType == "PARTY" then sawParty = true end
end
M.check(sawRaid and sawGuild and not sawParty, "in a raid and a guild, messages go to RAID and GUILD, not PARTY")

Sh.ResetComms(); M.addonMessages = {}; M.group.inRaid, M.group.guild, M.group.inGroup = false, false, true
M.sendResult = 3
Sh.Flush()
M.check(#M.addonMessages == 0 and Sh.QueueSize() > 0, "a throttled send leaves the message in the queue")
M.sendResult = 0
M.advance(2)
M.check(#M.addonMessages > 0, "the queued message is sent after the throttle clears")

-- The prefix was registered.
M.check(M.addonPrefixes[Sh.PREFIX] == true, "DEBDROPS prefix is registered")

-- Window buttons exist on the guide.
RM.Open(2589)
local W = RM.Frame()
M.check(W.exportBtn and W.importBtn and W.exportBtn:GetText() == "Export Drops" and W.importBtn:GetText() == "Import Drops",
  "Export Drops and Import Drops buttons are on the window")

M.done("drop sharing")

