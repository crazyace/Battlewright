-- Battlewright: your talents, read out of combat and cached (they can't change
-- mid-fight, and reading the tree is ~160 calls). Forever puts all three specs
-- in one Traits tree; which spec a node belongs to comes from a per-class group
-- ID map (the class file's tabGroups). Ported from Gearwright's reader.
--   Talents.Get() -> { ranks = { [name] = rank }, spellIDs = { [name] = id },
--                      points = { [tab] = n }, list = { { name, rank, max, tab, spellID } } }
local _, ns = ...

local Talents = {}
ns.Talents = Talents

local cache
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function clean(v) if not secret(v) then return v end end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return clean(C_Spell.GetSpellName(id)) end
end

local function readTraits(tabGroups)
  local configID = clean(C_ClassTalents.GetActiveConfigID())
  if not configID then return nil end
  local config = C_Traits.GetConfigInfo(configID)
  local out = { ranks = {}, spellIDs = {}, points = {}, list = {} }
  for _, treeID in ipairs(config and config.treeIDs or {}) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local info = C_Traits.GetNodeInfo(configID, nodeID)
      local tab
      for _, g in ipairs(info and info.groupIDs or {}) do tab = tab or tabGroups[g] end
      local entryID = info and ((info.activeEntry and info.activeEntry.entryID) or (info.entryIDs and info.entryIDs[1]))
      local entry = tab and entryID and C_Traits.GetEntryInfo(configID, entryID)
      local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
      local name = def and (clean(def.overrideName) or (def.spellID and spellName(def.spellID)))
      if name then
        local rank = clean(info.activeRank) or clean(info.ranksPurchased) or 0
        out.ranks[name] = math.max(out.ranks[name] or 0, rank)
        out.spellIDs[name] = def.spellID
        out.points[tab] = (out.points[tab] or 0) + rank
        out.list[#out.list + 1] = { name = name, rank = rank, max = info.maxRanks, tab = tab, spellID = def.spellID }
      end
    end
  end
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
    ok, result = pcall(readTraits, classData.tabGroups)
  elseif GetNumTalentTabs and GetTalentInfo then
    ok, result = pcall(readClassic)
  end
  if ok and result then cache = result end
  return cache
end

function Talents.Get() return cache or Talents.Refresh() or { ranks = {}, spellIDs = {}, points = {}, list = {} } end
function Talents.Rank(name) return Talents.Get().ranks[name] or 0 end
function Talents.Clear() cache = nil end -- forget the last read (tests, logout)

for _, event in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
  "PLAYER_REGEN_ENABLED" }) do
  ns:On(event, function() Talents.Refresh() end)
end
