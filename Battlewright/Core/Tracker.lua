-- Battlewright: Slice and Dice and Rupture timers, from your own casts.
-- On Forever, addons can't read auras in combat ("Auras cannot be accessed
-- when secret while tainted", BattlewrightProbe 2026-10-03), so the rotation
-- can't see these. Combo points are readable, though, so when you cast one,
-- its duration is estimated from the combo points you had (Classic's
-- durations; talents that lengthen them aren't counted yet).
local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

-- Seconds of each finisher by combo points spent.
Tracker.DURATION = {
  ["Slice and Dice"] = function(cp) return 6 + 3 * cp end, -- 9 / 12 / 15 / 18 / 21
  ["Rupture"] = function(cp) return 6 + 2 * cp end,        -- 8 / 10 / 12 / 14 / 16
}
local ON_TARGET = { ["Rupture"] = true } -- debuffs: forgotten when the target changes

Tracker.lastCP = 0      -- combo points at the last state read (before a finisher spends them)
Tracker.expires = {}    -- [name] = GetTime() when it runs out
Tracker.names = {}      -- [spellID] = name, filled by State.lua

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

function Tracker.Cast(spellID, now)
  if secret(spellID) then return end
  local name = Tracker.names[spellID]
  local duration = name and Tracker.DURATION[name]
  if duration and Tracker.lastCP > 0 then
    Tracker.expires[name] = now + duration(Tracker.lastCP)
  end
end

-- { [name] = seconds left } for buffs (onTarget false) or target debuffs (true).
function Tracker.Remaining(onTarget, now)
  local out = {}
  for name, t in pairs(Tracker.expires) do
    if (ON_TARGET[name] or false) == onTarget and t > now then out[name] = t - now end
  end
  return out
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit == "player" then Tracker.Cast(spellID, GetTime()) end
end)
ns:On("PLAYER_TARGET_CHANGED", function()
  for name in pairs(ON_TARGET) do Tracker.expires[name] = nil end
end)
