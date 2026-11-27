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
Dr.InvalidateCombined()
M.check(not Sh.EncodePersonal():find("1922", 1, true), "export is personal only: imported mobs are left out")
db.dropShares = {}
Dr.InvalidateCombined()

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
Dr.InvalidateCombined()
M.check(#Dr.RatesFor(700) == 0, "10 personal kills: still learning")
Sh.Import(snapOf("bobhostaaaa", { [700] = 10 }, { [700] = { [2589] = { loots = 10, seen = 3 } } }, { [700] = "Prowler" }), true)
local r700 = Dr.RatesFor(700)
M.check(#r700 == 1 and r700[1].loots == 20 and r700[1].seen == 5 and Dr.Kills(700) == 20, "10 + 10 combined kills shows a rate")
M.check(Dr.Label(20) == "from 20 kills" and not Dr.Label(20):find("your", 1, true), "label is 'from N kills'")
local title, sum = RM.DropsSummary(2589)
M.check(title == "Drops from (20 kills)" and sum:find("from 20 kills", 1, true) and not (title .. sum):find("your", 1, true),
  "material page uses combined 'from N kills' wording")
-- Mob tooltip must use combined kills too (10 personal + 10 shared = 20).
local tipLines = {}
local tip = M.frameObj("ShareTip")
rawset(tip, "AddLine", function(_, s) tipLines[#tipLines + 1] = s end)
rawset(tip, "AddDoubleLine", function(_, a, b) tipLines[#tipLines + 1] = a .. " = " .. b end)
Dr.AddUnitLines(tip, "Creature-0-4372-0-1-700-00000AAAA1", "Prowler")
local tipText = table.concat(tipLines, "\n")
M.check(not tipText:find("Learning drops", 1, true) and tipText:find("from 20 kills", 1, true),
  "mob tooltip shows combined rates when personal kills are under 20")


-- 6. Export / Import windows: SetMaxLetters(0), buttons, slash -----------------------------
Sh.OpenExport()
local ew = _G["KennyDwarfExplorersBibleDropExportWindow"]
M.check(ew and ew.shown and ew.edit and ew.edit.maxLetters == 0, "export window EditBox has SetMaxLetters(0)")
M.check(ew.edit:GetText():find("^DEB1:", 1) and ew.edit.highlighted, "export window shows the string selected")
M.check(ew.title and ew.title:GetText():find("Ctrl+C", 1, true), "export window tells you to press Ctrl+C")
M.check(not (ew.action and ew.action.shown), "export window has no Copy button")
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
Dr.InvalidateCombined()
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

-- 8. Review fixes: every blocker and nit ---------------------------------------------------
-- Combined cache: same table until ApplyShare invalidates it.
local cached = Dr.Combined()
M.check(Dr.Combined() == cached, "Combined() returns the cached table on a second call")
Sh.Import(snapOf("cachehostaa", { [900] = 20 }, { [900] = { [2589] = { loots = 20, seen = 1 } } }, {}), true)
M.check(Dr.Combined() ~= cached, "ApplyShare invalidates the Combined cache")

-- Colour codes and pipes are stripped from imported names.
local colour = Sh.Encode("namepipeaaaa", { kills = { [1] = 20 }, drops = { [1] = { [2] = { loots = 20, seen = 1 } } },
  names = { [1] = "|cff00ff00Timber|r |cffffffffWolf|r" } })
local decName = select(1, Sh.Decode(colour))
M.check(decName and decName.names[1] == "Timber Wolf", "imported mob names have colour codes and pipes stripped")

-- Duplicate mob ids in one string: first copy wins, loots never exceed kills.
local rec = "299,20,Wolf,2589:5:20/299,30,Wolf,2589:20:30"
local h = Sh.Hash("dupesourceaa:" .. rec)
local decDup = select(1, Sh.Decode("DEB1:dupesourceaa:" .. h .. ":" .. rec))
M.check(decDup.kills[299] == 20 and decDup.drops[299][2589].loots == 20 and decDup.drops[299][2589].seen == 5,
  "duplicate mob in one string keeps the first copy (loots stay <= kills)")

-- Synced source is bound to the first sender; another sender cannot overwrite it.
local bindSnap = { kills = { [1100] = 20 }, drops = { [1100] = { [2589] = { loots = 20, seen = 2 } } }, names = {} }
local ok, kind = Dr.ApplyShare("bindhostaaaa", bindSnap, "aaaaaaa1", "Bob-TestRealm")
M.check(ok and kind == "added" and db.dropShares["bindhostaaaa"].sender == "bob-testrealm", "first addon-comms sender is stored normalised (name-realm, lower case)")
ok, kind = Dr.ApplyShare("bindhostaaaa", { kills = { [1100] = 40 }, drops = { [1100] = { [2589] = { loots = 40, seen = 8 } } }, names = {} }, "aaaaaaa2", "Eve-TestRealm")
M.check((not ok) and kind == "sender" and db.dropShares["bindhostaaaa"].kills[1100] == 20, "a different sender cannot overwrite that snapshot")
ok, kind = Dr.ApplyShare("bindhostaaaa", { kills = { [1100] = 30 }, drops = { [1100] = { [2589] = { loots = 30, seen = 3 } } }, names = {} }, "aaaaaaa4", "bob-OtherRealm")
M.check((not ok) and kind == "sender" and db.dropShares["bindhostaaaa"].kills[1100] == 20, "a Bob on another realm is a different player (cross-realm)")
ok, kind = Dr.ApplyShare("bindhostaaaa", { kills = { [1100] = 25 }, drops = { [1100] = { [2589] = { loots = 25, seen = 3 } } }, names = {} }, "aaaaaaa3", "BOB-Test Realm")
M.check(ok and kind == "replaced" and db.dropShares["bindhostaaaa"].kills[1100] == 25, "the same player can update the snapshot (realm spaces and case ignored)")

-- Cap: the oldest of 51 sources is evicted.
db.dropShares = {}
Dr.InvalidateCombined()
for i = 1, 51 do
  M.now = 1790000000 + i
  local sid = ("cap%08dxx"):format(i)
  Dr.ApplyShare(sid, { kills = { [1200 + i] = 20 }, drops = { [1200 + i] = { [2589] = { loots = 20, seen = 1 } } }, names = {} }, ("h%07d"):format(i))
end
local nShares = 0
for _ in pairs(db.dropShares) do nShares = nShares + 1 end
M.check(nShares == Dr.MAX_SHARES and not db.dropShares["cap00000001xx"] and db.dropShares["cap00000051xx"],
  "dropShares is capped at 50 and the oldest source is evicted")

-- Self-echo: CHAT_MSG_ADDON sender is Name-Realm, UnitName is Name.
Sh.ResetComms(); M.addonMessages = {}
local selfText = Sh.Encode("evehostaaaa", { kills = { [1300] = 20 }, drops = { [1300] = { [2589] = { loots = 20, seen = 1 } } }, names = {} })
local selfHash = selfText:match("^DEB1:[%w]+:(%x+):")
Sh.OnAddonMessage(Sh.PREFIX, "A:evehostaaaa:" .. selfHash, "PARTY", "Kenny-TestRealm")
M.advance(1)
local qSelf = 0
for _, m in ipairs(M.addonMessages) do
  if type(m.message) == "string" and m.message:sub(1, 2) == "Q:" then qSelf = qSelf + 1 end
end
M.check(qSelf == 0, "a Name-Realm self-echo is ignored")

-- Incoming channels: PARTY/RAID/GUILD/INSTANCE_CHAT only.
local chanText = Sh.Encode("chanhostaaaa", { kills = { [1400] = 20 }, drops = { [1400] = { [2589] = { loots = 20, seen = 1 } } }, names = {} })
local chanChunks = Sh.BuildChunks(chanText)
for _, bad in ipairs({ "WHISPER", "SAY", "CHANNEL", "YELL", "EMOTE" }) do
  for i = 1, #chanChunks do Sh.OnAddonMessage(Sh.PREFIX, chanChunks[i], bad, "Eve") end
end
M.check(db.dropShares["chanhostaaaa"] == nil, "WHISPER/SAY/CHANNEL/YELL/EMOTE are ignored")
for i = 1, #chanChunks do Sh.OnAddonMessage(Sh.PREFIX, chanChunks[i], "INSTANCE_CHAT", "Eve") end
M.check(db.dropShares["chanhostaaaa"] and db.dropShares["chanhostaaaa"].kills[1400] == 20, "INSTANCE_CHAT is accepted")
local raidText = Sh.Encode("raidhostaaaa", { kills = { [1401] = 20 }, drops = { [1401] = { [2589] = { loots = 20, seen = 1 } } }, names = {} })
for i, c in ipairs(Sh.BuildChunks(raidText)) do Sh.OnAddonMessage(Sh.PREFIX, c, "RAID", "Eve") end
M.check(db.dropShares["raidhostaaaa"], "RAID is accepted")
local gText = Sh.Encode("guildhostaa1", { kills = { [1402] = 20 }, drops = { [1402] = { [2589] = { loots = 20, seen = 1 } } }, names = {} })
for i, c in ipairs(Sh.BuildChunks(gText)) do Sh.OnAddonMessage(Sh.PREFIX, c, "GUILD", "Eve") end
M.check(db.dropShares["guildhostaa1"], "GUILD is accepted")

-- Reassembly TTL refreshes on every chunk, so a long gap after chunk 1 does not drop the rest.
local slowSnap = { kills = {}, drops = {}, names = {} }
for cid = 16000, 16080 do
  slowSnap.kills[cid] = 20
  slowSnap.drops[cid] = { [2589] = { loots = 20, seen = 2 } }
  slowSnap.names[cid] = "Slow" .. cid
end
local slowPayload = Sh.Encode("slowhostaaaa", slowSnap)
local slowChunks = Sh.BuildChunks(slowPayload)
M.check(#slowChunks > 2, "TTL test payload is chunked")
Sh.OnAddonMessage(Sh.PREFIX, slowChunks[1], "PARTY", "SlowEve")
M.advance(25)
Sh.OnAddonMessage(Sh.PREFIX, slowChunks[2], "PARTY", "SlowEve")
M.advance(25)
for i = 3, #slowChunks do Sh.OnAddonMessage(Sh.PREFIX, slowChunks[i], "PARTY", "SlowEve") end
M.check(db.dropShares["slowhostaaaa"] and db.dropShares["slowhostaaaa"].kills[16000] == 20,
  "reassembly still completes when gaps between chunks exceed the old 30s TTL")

-- Hash change while a send is in flight does not stack a second payload.
Sh.ResetComms(); M.addonMessages = {}; M.group.inGroup, M.group.inRaid, M.group.guild = true, false, false
M.combat, M.lockdown, M.sendResult = false, false, 0
db.drops, db.dropKills, db.mobNames = { [299] = { [2589] = { loots = 20, seen = 5 } } }, { [299] = 20 }, { [299] = "Timber Wolf" }
for cid = 17000, 17080 do
  db.dropKills[cid] = 20
  db.drops[cid] = { [2589] = { loots = 20, seen = 3 } }
  db.mobNames[cid] = "QMob" .. cid
end
Dr.InvalidateCombined()
Sh.Flush()
local firstQueued = Sh.QueueSize()
M.check(firstQueued > 10, "first flush queued a large payload")
db.dropKills[299] = 21
db.drops[299][2589].loots = 21
Dr.InvalidateCombined()
Sh.Flush()
local secondQueued = Sh.QueueSize()
M.check(secondQueued <= firstQueued + 2, "a newer hash while data is in flight does not append a second full payload (queued " .. secondQueued .. " after " .. firstQueued .. ")")
M.check(Sh.Pending(), "the newer hash stays pending until the in-flight send finishes")

-- lastQueryAt is pruned of stale keys.
Sh.ResetComms(); M.addonMessages = {}
for i = 1, 8 do
  Sh.OnAddonMessage(Sh.PREFIX, "A:" .. ("qsrc%08d"):format(i) .. ":aaaaaaaa", "PARTY", "Eve")
end
M.advance(1)
M.check(Sh.QueryMapSize() >= 8, "each new announce is remembered")
M.advance(Sh.QUERY_GAP + 1)
Sh.OnAddonMessage(Sh.PREFIX, "A:qsrc00000009:aaaaaaaa", "PARTY", "Eve")
M.check(Sh.QueryMapSize() == 1, "stale lastQueryAt entries are pruned (size " .. Sh.QueryMapSize() .. ")")

-- Pump returns cleanly when the addon-message API is missing, and leaves the queue in place.
Sh.ResetComms()
Sh.Enqueue("PARTY", "A:alicehost01:deadbeef")
local saved = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = nil
local okPump = pcall(Sh.Pump)
C_ChatInfo.SendAddonMessage = saved
M.check(okPump and Sh.QueueSize() == 1, "pump returns cleanly when SendAddonMessage is missing and keeps the queue")


M.done("drop sharing")

