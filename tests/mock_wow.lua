-- Minimal mock of the WoW: Forever client for offline tests. Not Blizzard code; just enough surface.
-- Host addons (DBM, BigWigs, Details, Questie, LibStub...) are mocked in each test file.
local M = {}
M.now, M.clock, M.combat, M.encounter, M.lockdown = 1790000000, 1000, false, false, false
M.timers, M.frames, M.prints, M.sounds, M.chat = {}, {}, {}, {}, {}
M.secret = {}
M.group = { inGroup = false, inRaid = false, leader = false, assist = false }

local function frameObj(name)
  local fr = { events = {}, scripts = {}, shown = true, name = name, points = {}, kids = {} }
  local mt = {}
  mt.__index = function(t, k)
    if k == "RegisterEvent" then return function(_, e) t.events[e] = true end end
    if k == "UnregisterEvent" then return function(_, e) t.events[e] = nil end end
    if k == "SetScript" then return function(_, s, fn) t.scripts[s] = fn end end
    if k == "GetScript" then return function(_, s) return t.scripts[s] end end
    if k == "IsShown" then return function() return t.shown end end
    if k == "Show" then return function() t.shown = true end end
    if k == "Hide" then return function() t.shown = false end end
    if k == "SetShown" then return function(_, v) t.shown = v and true or false end end
    if k == "SetText" then return function(_, v) t.text_ = v end end
    if k == "GetText" then return function() return t.text_ end end
    if k == "SetChecked" then return function(_, v) t.checked = v and true or false end end
    if k == "GetChecked" then return function() return t.checked end end
    if k == "GetName" then return function() return t.name end end
    if k == "SetPoint" then return function(_, ...) t.points[#t.points + 1] = { ... } end end
    if k == "CreateFontString" or k == "CreateTexture" then
      return function() local c = frameObj(); t.kids[#t.kids + 1] = c; return c end end
    if k == "Text" then local c = frameObj(); rawset(t, "Text", c); return c end
    return function() end -- every other widget method is a no-op
  end
  return setmetatable(fr, mt)
end
M.frameObj = frameObj

function M.install(env)
  env = env or _G
  env.issecretvalue = function(v) return v ~= nil and M.secret[v] == true end
  env.time = function() return M.now end
  env.date = os.date
  env.GetTime = function() return M.clock end
  env.GetBuildInfo = function() return "1.60.1", "70374", "Oct 13 2026", 16001 end
  env.GetLocale = function() return "enUS" end
  env.GetRealmName = function() return "TestRealm" end
  env.UnitName = function(u) if u == "player" then return "Kenny" end end
  env.UnitGUID = function(u) if u == "player" then return "Player-1-0001" end end
  env.UnitFactionGroup = function() return M.faction or "Horde" end
  env.UnitAffectingCombat = function() return M.combat end
  env.InCombatLockdown = function() return M.combat end
  env.IsInGroup = function() return M.group.inGroup end
  env.IsInRaid = function() return M.group.inRaid end
  env.UnitIsGroupLeader = function() return M.group.leader end
  env.UnitIsGroupAssistant = function() return M.group.assist end
  env.C_InstanceEncounter = { IsEncounterInProgress = function() return M.encounter end }
  env.C_ChatInfo = { InChatMessagingLockdown = function() return M.lockdown end,
    SendChatMessage = function(msg, chatType) M.chat[#M.chat + 1] = { msg, chatType } end }
  env.C_FriendList = { IsFriend = function(guid) return M.friends and M.friends[guid] end,
    GetFriendInfo = function(name) return M.friends and M.friends[name] and { name = name } or nil end,
    IsOnIgnoredList = function(name) return M.ignored and M.ignored[name] or false end }
  env.C_GuildInfo = { MemberExistsByName = function(name) return M.guild and M.guild[name] or false end }
  env.C_PartyInfo = { DoCountdown = function(s) M.countdowns = (M.countdowns or 0) + 1; M.lastCountdown = s; return true, false end }
  env.PlaySoundFile = function(id, channel)
    if M.soundFails then return false end
    M.sounds[#M.sounds + 1] = { id, channel }; return true, #M.sounds end
  env.C_Timer = {
    After = function(d, fn) M.timers[#M.timers + 1] = { at = M.clock + (d or 0), fn = fn } end,
    NewTimer = function(d, fn) local h = { at = M.clock + (d or 0), fn = fn }
      h.Cancel = function(s) s.cancelled = true end; M.timers[#M.timers + 1] = h; return h end,
    NewTicker = function() return { Cancel = function() end } end }
  env.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end,
    IsAddOnLoaded = function(n) return M.loaded and M.loaded[n] end }
  env.Settings = { RegisterCanvasLayoutCategory = function(_, n) return { name = n, GetID = function() return n end } end,
    RegisterAddOnCategory = function(c) M.settingsCategory = c end, OpenToCategory = function() end }
  env.UIParent = frameObj("UIParent")
  env.SlashCmdList = env.SlashCmdList or {}
  env.CreateFrame = function(_, name) local f = frameObj(name); M.frames[#M.frames + 1] = f
    if name then env[name] = f end; return f end
  env.print = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    M.prints[#M.prints + 1] = table.concat(t, " ") end
  env.unpack = env.unpack or table.unpack
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
end

-- A tiny LibStub + LibDataBroker so LDB objects can be tested.
function M.installLDB(env)
  env = env or _G
  local libs = {}
  M.ldbObjects = {}
  libs["LibDataBroker-1.1"] = { NewDataObject = function(_, name, obj) M.ldbObjects[name] = obj; return obj end,
    GetDataObjectByName = function(_, name) return M.ldbObjects[name] end }
  env.LibStub = setmetatable({ libs = libs }, { __call = function(_, name, silent)
    if libs[name] then return libs[name] end
    if not silent then error("Cannot find a library instance of " .. tostring(name)) end end })
  return libs
end

-- Load an addon the way the client does: each TOC file gets (addonName, privateTable).
function M.loadAddon(dir, name)
  local ns = {}
  for line in io.lines(dir .. "/" .. name .. ".toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then assert(loadfile(dir .. "/" .. line))(name, ns) end
  end
  M.fire("ADDON_LOADED", name)
  return ns
end

function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- Advance the clock and run due timers in order.
function M.advance(sec)
  local target = M.clock + (sec or 0)
  for _ = 1, 10000 do
    table.sort(M.timers, function(a, b) return a.at < b.at end)
    local t = M.timers[1]
    if not t or t.at > target then break end
    table.remove(M.timers, 1)
    M.clock = math.max(M.clock, t.at)
    if not t.cancelled then t.fn() end
  end
  M.clock = target
end

function M.slash(cmd, msg)
  for k, fn in pairs(SlashCmdList) do
    for i = 1, 5 do if _G["SLASH_" .. k .. i] == cmd then return fn(msg or "") end end
  end
  error("no slash command " .. cmd)
end

function M.lastPrint() return M.prints[#M.prints] or "" end
function M.printed(s) for _, p in ipairs(M.prints) do if p:find(s, 1, true) then return true end end return false end

M.fails, M.passes = 0, 0
function M.check(cond, label)
  if cond then M.passes = M.passes + 1 else M.fails = M.fails + 1; io.write("FAIL: ", label, "\n") end
end
function M.done(name)
  io.write(("%s: %d passed, %d failed\n"):format(name, M.passes, M.fails))
  os.exit(M.fails == 0 and 0 or 1)
end
return M
