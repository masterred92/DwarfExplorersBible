-- Cache.lua: one version stamp for everything derived (shopping rows, Make now lists, skill-ups, seeds, alts).
-- Bags, bank, prices, vendors and alt data call Bump() when they change; Get() rebuilds only after a bump, and
-- in combat it hands back the last result instead of rebuilding (no stutter while you fight).
local _, ns = ...
local C = ns.Compat
local K = { v = 0, memo = {}, n = 0, builds = 0 }
ns.Cache = K

K.MAX_KEYS = 400
K.TTL = 30 -- seconds; prices from other addons (PriceLog, Auctionator...) change without telling us

function K.Bump() K.v = K.v + 1 end
function K.Version() return K.v end

-- value of build(), rebuilt only when the stamp moved, TTL passed, or never built. In combat a stale value is kept.
function K.Get(key, build)
  local e = K.memo[key]
  local now = C.Clock()
  if e and ((e.v == K.v and now - e.at < K.TTL) or C.InCombat()) then return e.val end
  if not e then
    if K.n >= K.MAX_KEYS then K.memo, K.n = {}, 0 end
    K.n = K.n + 1
  end
  local val = build()
  K.builds = K.builds + 1
  K.memo[key] = { v = K.v, val = val, at = now }
  return val
end

function K.Reset() K.memo, K.n = {}, 0; K.Bump() end
