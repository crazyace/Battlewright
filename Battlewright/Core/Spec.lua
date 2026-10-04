-- Battlewright: which spec to play: the /bw spec override, else the talent
-- tab with the most points, else a talent-taught signature spell, else the
-- class's default (before level 10 nobody has talents).
local _, ns = ...

local Spec = {}
ns.Spec = Spec

-- Spells only a spec's talents teach, strongest sign first.
Spec.SIGNS = {
  ROGUE = {
    { "Mutilate", "assassination" }, { "Cold Blood", "assassination" },
    { "Hemorrhage", "subtlety" }, { "Premeditation", "subtlety" }, { "Preparation", "subtlety" },
    { "Ghostly Strike", "subtlety" },
    { "Adrenaline Rush", "combat" }, { "Blade Flurry", "combat" }, { "Riposte", "combat" },
  },
}
Spec.DEFAULT = { ROGUE = "combat" }

-- spec, how ("override" | "talents" | "spells" | "default").
function Spec.Detect(class, spells)
  if ns.db and ns.db.specOverride then return ns.db.specOverride, "override" end
  local classData = ns.Rotations[class]
  local points = ns.Talents.Get().points
  local best, most = nil, 0
  for tab, n in pairs(points) do
    if n > most then best, most = tab, n end
  end
  if best and classData and classData.tabToSpec and classData.tabToSpec[best] then
    return classData.tabToSpec[best], "talents"
  end
  for _, sign in ipairs(Spec.SIGNS[class] or {}) do
    if spells[sign[1]] then return sign[2], "spells" end
  end
  return Spec.DEFAULT[class], "default"
end
