-- Nav.lua: the window's four tabs (Materials | Shopping | Seeds | Alts) and their slash commands. The window code
-- registers a handler with Nav.RegisterTabHandler(fn(tab)); Nav.ShowTab(tab) records the tab, opens the window and
-- calls every handler. Until a handler is registered, the slash commands open the Materials window and print a
-- one-line summary of the tab in chat.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local N = {}
ns.Nav = N
local RM = ns.RM

N.TABS = { "materials", "shopping", "seeds", "alts" }
N.TITLES = { materials = "Materials", shopping = "Shopping", seeds = "Seeds", alts = "Alts" }
N.SLASH = { materials = "materials", shop = "shopping", shopping = "shopping", seeds = "seeds", alts = "alts" }

local current = "materials"
local handlers = {}

function N.IsTab(tab) return N.TITLES[tab] ~= nil end
function N.CurrentTab() return current end

-- fn(tab, arg) is called on every ShowTab, after the window is open. Returns fn so it can be unregistered.
function N.RegisterTabHandler(fn)
  if type(fn) == "function" then handlers[#handlers + 1] = fn end
  return fn
end

function N.UnregisterTabHandler(fn)
  for i = #handlers, 1, -1 do if handlers[i] == fn then table.remove(handlers, i) end end
end

function N.HasHandlers() return #handlers > 0 end

function N.ShowTab(tab, arg)
  if not N.IsTab(tab) then return false end
  current = tab
  if RM.Open then RM.Open() end
  for _, fn in ipairs(handlers) do Core.SafeCall("tab " .. tab, fn, tab, arg) end
  return true
end

-- One line per tab for chat, used until the window shows the tab itself.
function N.Summary(tab)
  if tab == "shopping" then
    local S = ns.Shopping
    if S.Count() == 0 then return "Shopping list is empty. Add a recipe's missing mats from its row, or /deb shop <item> [count]." end
    local s = S.Sections()
    local groups = #s.vendor.groups
    return ("Shopping: %d item(s) · Vendor %s (%d vendor(s)) · Grab from Alt %d · AH %s%s"):format(S.Count(),
      C.Money(s.vendor.subtotal), groups, #s.alt.rows, C.Money(s.ah.subtotal), s.incomplete and " + unpriced" or "")
  elseif tab == "seeds" then
    local sum = ns.Seeds.Summary()
    return sum.empty and ns.Seeds.EMPTY or sum.text
  elseif tab == "alts" then
    return ns.Alts.Status()
  end
  return nil
end

function N.Slash(word, arg)
  local tab = N.SLASH[word]
  arg = arg or ""
  if tab == "shopping" and arg ~= "" then
    local S = ns.Shopping
    local lc = arg:lower()
    if lc == "clear" then Core.Print(("cleared %d item(s) from the shopping list"):format(S.ClearAll())); return true
    elseif lc == "cleardone" or lc == "clear done" then Core.Print(("cleared %d done item(s)"):format(S.ClearDone())); return true end
    local what, n = arg:match("^(.-)%s+(%d+)$")
    local id = RM.ParseItem(what or arg)
    if id then
      local ok = S.AddItem(id, tonumber(n) or 1, "manual")
      Core.Print(ok and ("added %s x%d to the shopping list"):format(RM.Name(id), tonumber(n) or 1) or "shopping list is full (60 items)")
    else
      Core.Print("unknown item '" .. arg .. "'. /deb shop <item> [count] | clear | cleardone")
    end
    return true
  end
  N.ShowTab(tab, arg)
  if not N.HasHandlers() then
    local line = N.Summary(tab)
    if line then Core.Print(line) end
  end
  return true
end
