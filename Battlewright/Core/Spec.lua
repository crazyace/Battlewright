-- Battlewright: which spec to play. From the talents' signature spells (a
-- talent that teaches a spell is in the spellbook), or the /bw spec override.
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

-- spec, how ("override" | "talents" | "default"), from a state's known spells.
function Spec.Detect(class, spells)
  if ns.db and ns.db.specOverride then return ns.db.specOverride, "override" end
  for _, sign in ipairs(Spec.SIGNS[class] or {}) do
    if spells[sign[1]] then return sign[2], "talents" end
  end
  return Spec.DEFAULT[class], "default"
end
