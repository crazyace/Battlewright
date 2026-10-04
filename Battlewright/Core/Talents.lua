-- Battlewright: your talents, read out of combat and cached (they can't change
-- mid-fight, and reading the tree is ~160 calls). Forever puts all three specs
-- in one Traits tree. Each node is matched to the class file's talent list by
-- node ID, then spell ID (Forever renames talents between builds; the IDs
-- stay), which also gives its spec; nodes not in the list fall back to the
-- per-class group ID map (tabGroups) and the game's name. Ported from
-- Gearwright's reader.
--   Talents.Get() -> { ranks = { [name] = rank }, spellIDs = { [name] = id },
--                      points = { [tab] = n }, list = { { name, rank, max, tab, spellID, posX, posY } },
--                      budget = { total, unspent, spent, bonus, source } or nil }
--   (posX/posY: the node's place in the tree, Traits only; the guide draws the tree from them)
--   budget: your talent points. source "currency" when the game says (the
--   tree's currency), else "level": level - 9 plus the Legacy Talented perk.
local _, ns = ...

local Talents = {}
ns.Talents = Talents

-- Forever's account-wide Legacy tree "Adventure" and its Talented perk (one
-- more talent point per rank), from talentsforever.com's data, 2026-10-03.
Talents.LEGACY_TREE = 1188
Talents.TALENTED = 1225474

local cache
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function clean(v) if not secret(v) then return v end end
-- One game call: nil (not an error) when it fails or the answer is hidden.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, r = pcall(fn, ...)
  if ok then return clean(r) end
end

local function spellName(id)
  if C_Spell then return try(C_Spell.GetSpellName, id) end
end

-- The talent config that holds `treeID`: the active one first, then the
-- tree's own, then any of the game's systems (as TalentsForeverBook does).
local function holds(configID, treeID)
  local info = configID and try(C_Traits.GetConfigInfo, configID)
  for _, t in ipairs(info and info.treeIDs or {}) do if t == treeID then return true end end
  return false
end
function Talents.ConfigFor(treeID)
  local active = C_ClassTalents and try(C_ClassTalents.GetActiveConfigID)
  if not treeID then return active end
  if holds(active, treeID) then return active end
  local own = try(C_Traits.GetConfigIDByTreeID, treeID)
  if holds(own, treeID) then return own end
  if C_Traits.GetConfigIDBySystemID then
    for system = 1, 40 do
      local id = try(C_Traits.GetConfigIDBySystemID, system)
      if holds(id, treeID) then return id end
    end
  end
end

-- A node's definition: its spell ID and name, or nil.
local function definition(configID, info)
  local entryID = info and ((info.activeEntry and info.activeEntry.entryID) or (info.entryIDs and info.entryIDs[1]))
  local entry = entryID and try(C_Traits.GetEntryInfo, configID, entryID)
  return entry and entry.definitionID and try(C_Traits.GetDefinitionInfo, entry.definitionID)
end

-- The Legacy Talented perk's rank (0 when not taken, nil when unreadable).
local function talented()
  local configID = Talents.ConfigFor(Talents.LEGACY_TREE)
  if not configID then return nil end
  for _, nodeID in ipairs(try(C_Traits.GetTreeNodes, Talents.LEGACY_TREE) or {}) do
    local info = try(C_Traits.GetNodeInfo, configID, nodeID)
    local def = definition(configID, info)
    if def and def.spellID == Talents.TALENTED then
      return clean(info.activeRank) or clean(info.ranksPurchased) or 0
    end
  end
  return 0
end

-- The class tree's talent points, from its currency (unspent + spent).
local function currency(configID, treeID)
  local list = treeID and try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
  local c = type(list) == "table" and list[1]
  local unspent, spent = c and clean(c.quantity), c and clean(c.spent)
  if type(unspent) == "number" and type(spent) == "number" then return unspent, spent end
end

local function readTraits(classData)
  -- (Without the class tree's ID, or when no config lists it: the active one, as before.)
  local configID = Talents.ConfigFor(classData.treeID) or Talents.ConfigFor(nil)
  if not configID then return nil end
  local byNode, bySpell = {}, {}
  for _, t in ipairs(classData.TALENTS or {}) do
    if t.node then byNode[t.node] = t end
    if t.spell then bySpell[t.spell] = t end
  end
  local config = try(C_Traits.GetConfigInfo, configID)
  local out = { ranks = {}, spellIDs = {}, points = {}, list = {} }
  for _, treeID in ipairs(config and config.treeIDs or {}) do
    for _, nodeID in ipairs(try(C_Traits.GetTreeNodes, treeID) or {}) do
      local info = try(C_Traits.GetNodeInfo, configID, nodeID)
      local def = info and definition(configID, info)
      local known = byNode[nodeID] or (def and bySpell[def.spellID])
      local tab = known and known.tab
      for _, g in ipairs(not tab and info and info.groupIDs or {}) do tab = tab or classData.tabGroups[g] end
      local name = known and known.name or (tab and def and (clean(def.overrideName) or (def.spellID and spellName(def.spellID))))
      if name then
        local rank = clean(info.activeRank) or clean(info.ranksPurchased) or 0
        out.ranks[name] = math.max(out.ranks[name] or 0, rank)
        out.spellIDs[name] = (def and def.spellID) or (known and known.spell)
        out.points[tab] = (out.points[tab] or 0) + rank
        out.list[#out.list + 1] = { name = name, rank = rank, max = clean(info.maxRanks), tab = tab, spellID = out.spellIDs[name],
          posX = clean(info.posX), posY = clean(info.posY) }
      end
    end
  end
  local unspent, spent = currency(configID, classData.treeID)
  if unspent then out.budget = { total = unspent + spent, unspent = unspent, spent = spent, source = "currency" } end
  out.talented = talented()
  return out
end

local function readClassic()
  local out = { ranks = {}, spellIDs = {}, points = {}, list = {} }
  for tab = 1, GetNumTalentTabs() do
    for i = 1, (GetNumTalents(tab) or 0) do
      local name, _, _, _, rank, max = GetTalentInfo(tab, i)
      if name then
        out.ranks[name] = rank or 0
        out.points[tab] = (out.points[tab] or 0) + (rank or 0)
        out.list[#out.list + 1] = { name = name, rank = rank or 0, max = max, tab = tab }
      end
    end
  end
  return out
end

-- Read now (out of combat only; in combat the last read is kept).
function Talents.Refresh()
  if InCombatLockdown and InCombatLockdown() then return cache end
  local _, class = UnitClass("player")
  local classData = ns.Rotations[class]
  local ok, result
  if C_ClassTalents and C_Traits and classData and classData.tabGroups then
    ok, result = pcall(readTraits, classData)
  elseif GetNumTalentTabs and GetTalentInfo then
    ok, result = pcall(readClassic)
  end
  if ok and result then cache = result end
  if cache then cache.budget = Talents.Budget(cache) end
  return cache
end

-- Your talent points: the game's count when it gives one, else level - 9
-- plus the Legacy Talented perk. nil before level 10 without the game's count.
function Talents.Budget(t)
  if t.budget and t.budget.source == "currency" then
    local b = t.budget
    b.bonus = math.max(0, b.total - math.max(0, (UnitLevel and UnitLevel("player") or 0) - 9))
    return b
  end
  local level = UnitLevel and UnitLevel("player")
  if not level then return nil end
  local spent = 0
  for _, n in pairs(t.points or {}) do spent = spent + n end
  local bonus = t.talented or 0
  local total = math.max(0, level - 9) + (level >= 10 and bonus or 0)
  return { total = total, unspent = math.max(0, total - spent), spent = spent, bonus = bonus, source = "level" }
end

function Talents.Get() return cache or Talents.Refresh() or { ranks = {}, spellIDs = {}, points = {}, list = {} } end
function Talents.Rank(name) return Talents.Get().ranks[name] or 0 end
function Talents.Clear() cache = nil end -- forget the last read (tests, logout)

for _, event in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
  "PLAYER_REGEN_ENABLED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_LEVEL_UP" }) do
  ns:On(event, function() Talents.Refresh() end)
end
