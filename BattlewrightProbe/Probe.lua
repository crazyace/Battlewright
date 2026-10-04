-- BattlewrightProbe: answers what Battlewright can't be built without.
--
--   * Can an addon read energy, combo points, auras, cooldowns and spell
--     usability during a fight on Forever, or does the client hide them
--     (issecretvalue)?
--
-- Dev-only. Results are stored in BattlewrightProbeDB and shown in a copyable
-- window (/bwp export). The combat recorder started out in GearwrightProbe.
local P = {}
local PREFIX = "|cffd9a441BattlewrightProbe|r: "
local function say(s, ...) print(PREFIX .. (select("#", ...) > 0 and s:format(...) or s)) end
local function now() return date("%Y-%m-%d %H:%M:%S") end
local function pack(...) return { n = select("#", ...), ... } end

-- Value sanitizing --------------------------------------------------------------
local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function sanitize(v, depth)
  depth = depth or 0
  if isSecret(v) then return "<secret>" end
  local t = type(v)
  if t == "nil" then return "<nil>" end
  if t == "string" or t == "number" or t == "boolean" then return v end
  if t == "table" then
    if depth >= 3 then return "<table>" end
    local out = {}
    for k, val in pairs(v) do
      local key = (type(k) == "string" or type(k) == "number") and k or tostring(k)
      out[key] = sanitize(val, depth + 1)
    end
    return out
  end
  return "<" .. t .. ">"
end

-- Storage ------------------------------------------------------------------------
local function db()
  BattlewrightProbeDB = BattlewrightProbeDB or {}
  local d = BattlewrightProbeDB
  d.version = 1
  d.runs = d.runs or {} -- combat recordings, newest first (5 kept)
  return d
end

-- Combat readability --------------------------------------------------------------
-- Can an addon read what Battlewright needs while you fight? Forever's
-- client has issecretvalue, and retail hides some combat values from addons.
-- /bwp combat arms a recorder for your next fight: twice a second it reads
-- energy, combo points, your buffs, the target's debuffs, cooldowns and
-- whether spells are usable, and notes for each call whether the value came
-- back readable, secret, or missing.
local COMBAT_SPELLS = { "Sinister Strike", "Eviscerate", "Slice and Dice", "Backstab", "Rupture",
  "Garrote", "Mutilate", "Hemorrhage", "Kick", "Gouge", "Evasion", "Sprint", "Blade Flurry", "Adrenaline Rush" }
local combat = { armed = false }

local function note(out, key, fn, ...)
  combat.lastCheck = key
  local rec = out[key] or { calls = 0, readable = 0, secret = 0, missing = 0, errors = 0 }
  out[key] = rec
  rec.calls = rec.calls + 1
  if not fn then rec.missing = rec.missing + 1; return nil end
  local res = pack(pcall(fn, ...))
  if not res[1] then rec.errors = rec.errors + 1; rec.error = tostring(res[2]); return nil end
  local anySecret = false
  for i = 2, res.n do if isSecret(res[i]) then anySecret = true end end
  if anySecret then rec.secret = rec.secret + 1 else rec.readable = rec.readable + 1 end
  if rec.example == nil and not anySecret then rec.example = sanitize({ unpack(res, 2, math.min(res.n, 6)) }) end
  -- Readable but nothing found (nil) is different from found: count both, keep
  -- the first real answer (e.g. the Slice and Dice aura while it's up).
  if not anySecret and res[2] ~= nil then
    rec.found = (rec.found or 0) + 1
    if rec.foundExample == nil then rec.foundExample = sanitize({ unpack(res, 2, math.min(res.n, 6)) }) end
  end
  return not anySecret and res[2] or nil, res
end

local function auraNames(out, unit, filter)
  local names = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 40 do
    local data = note(out, "aura:" .. unit .. ":" .. filter, get, unit, i, filter)
    if type(data) ~= "table" then break end
    local name = data.name
    if isSecret(name) then names[#names + 1] = "<secret>" else names[#names + 1] = tostring(name) end
    local okD, dur = pcall(function() return data.expirationTime end)
    local rec = out["aura expirationTime"] or { calls = 0, readable = 0, secret = 0, missing = 0, errors = 0 }
    out["aura expirationTime"] = rec
    rec.calls = rec.calls + 1
    if okD and isSecret(dur) then rec.secret = rec.secret + 1 else rec.readable = rec.readable + 1 end
  end
  return names
end

local function combatSample(out)
  local energyType = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
  local cpType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  note(out, "UnitPower(energy)", UnitPower, "player", energyType)
  note(out, "UnitPowerMax(energy)", UnitPowerMax, "player", energyType)
  note(out, "UnitPower(combo points)", UnitPower, "player", cpType)
  note(out, "GetComboPoints", GetComboPoints, "player", "target")
  note(out, "UnitHealth(target)", UnitHealth, "target")
  note(out, "UnitHealthMax(target)", UnitHealthMax, "target")
  note(out, "UnitCanAttack(target)", UnitCanAttack, "player", "target")
  note(out, "IsStealthed", IsStealthed)
  note(out, "GetTime", GetTime)
  out.buffs = auraNames(out, "player", "HELPFUL")
  out.debuffs = auraNames(out, "target", "HARMFUL|PLAYER")
  for _, name in ipairs(COMBAT_SPELLS) do
    local info = C_Spell and C_Spell.GetSpellInfo and select(2, pcall(C_Spell.GetSpellInfo, name))
    local id = type(info) == "table" and not isSecret(info.spellID) and info.spellID or nil
    if id then
      note(out, "C_Spell.GetSpellCooldown", C_Spell.GetSpellCooldown, id)
      note(out, "C_Spell.IsSpellUsable", C_Spell.IsSpellUsable, id)
      note(out, "C_Spell.GetSpellPowerCost", C_Spell.GetSpellPowerCost, id)
      out.known = out.known or {}
      out.known[name] = id
    end
  end
  -- Round 2 (2026-10-04): energy, target health and auras by index came back
  -- hidden or blocked in combat, so try the other ways to get them.
  local snd = out.known and out.known["Slice and Dice"]
  local ua = C_UnitAuras or {}
  if snd then note(out, "C_UnitAuras.GetPlayerAuraBySpellID(Slice and Dice)", ua.GetPlayerAuraBySpellID, snd) end
  note(out, "C_UnitAuras.GetAuraDataBySpellName(player, Slice and Dice)", ua.GetAuraDataBySpellName,
    "player", "Slice and Dice", "HELPFUL")
  local auraUtil = rawget(_G, "AuraUtil")
  note(out, "AuraUtil.FindAuraByName(Slice and Dice)", auraUtil and auraUtil.FindAuraByName, "Slice and Dice", "player", "HELPFUL")
  note(out, "UnitHealthPercent(target)", rawget(_G, "UnitHealthPercent"), "target")
  note(out, "UnitPowerPercent(energy)", rawget(_G, "UnitPowerPercent"), "player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
  note(out, "GetPowerRegen", rawget(_G, "GetPowerRegen"))
  note(out, "UnitGUID(target)", rawget(_G, "UnitGUID"), "target")
  note(out, "UnitCastingInfo(target)", rawget(_G, "UnitCastingInfo"), "target")
  note(out, "UnitChannelInfo(target)", rawget(_G, "UnitChannelInfo"), "target")
  local ss = out.known and out.known["Sinister Strike"]
  if ss and C_Spell then note(out, "C_Spell.IsSpellInRange(Sinister Strike)", C_Spell.IsSpellInRange, ss, "target") end
  -- Blizzard's own rotation suggestion (retail's Assisted Combat), if Forever has it.
  local ac = rawget(_G, "C_AssistedCombat") or {}
  note(out, "C_AssistedCombat.IsAvailable", ac.IsAvailable)
  local nextSpell = note(out, "C_AssistedCombat.GetNextCastSpell", ac.GetNextCastSpell)
  if nextSpell then
    out.assistedSuggestions = out.assistedSuggestions or {}
    local name = C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, nextSpell))
    local key = tostring(isSecret(name) and nextSpell or name or nextSpell)
    out.assistedSuggestions[key] = (out.assistedSuggestions[key] or 0) + 1
  end
  note(out, "C_AssistedCombat.GetRotationSpells", ac.GetRotationSpells)
end

-- Events during a recorded fight: are their arguments readable?
local function noteEvent(out, event, ...)
  local rec = out["event:" .. event] or { calls = 0, readable = 0, secret = 0, missing = 0, errors = 0 }
  out["event:" .. event] = rec
  rec.calls = rec.calls + 1
  local args = pack(...)
  local anySecret = false
  for i = 1, args.n do if isSecret(args[i]) then anySecret = true end end
  if anySecret then rec.secret = rec.secret + 1 else rec.readable = rec.readable + 1 end
  if rec.example == nil and not anySecret then rec.example = sanitize({ unpack(args, 1, math.min(args.n, 5)) }) end
  -- Which spells you cast (by name), so a run shows e.g. that Slice and Dice was up.
  if event == "UNIT_SPELLCAST_SUCCEEDED" and args[1] == "player" and not isSecret(args[3]) then
    local id = args[3]
    local name = C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, id))
    local key = (type(name) == "string" and not isSecret(name)) and name or tostring(id)
    out.casts = out.casts or {}
    out.casts[key] = (out.casts[key] or 0) + 1
  end
end

local function combatStart()
  if not combat.armed or combat.ticker then return end
  local out = { at = now(), samples = 0 }
  combat.out = out
  local function tick()
    if not combat.ticker then return end
    out.samples = out.samples + 1
    local ok, err = pcall(combatSample, out)
    if not ok then out.error = tostring(err) end
    if out.samples < 60 then C_Timer.After(0.5, tick) end -- at most 30 s
  end
  combat.ticker = true
  tick()
end

local function combatEnd()
  if not combat.ticker then return end
  combat.ticker = nil
  local out = combat.out
  table.insert(db().runs, 1, out)
  while #db().runs > 5 do table.remove(db().runs) end
  combat.armed = false
  local secret, readable = {}, 0
  for key, rec in pairs(out) do
    if type(rec) == "table" and rec.calls then
      if rec.secret > 0 then secret[#secret + 1] = key else readable = readable + 1 end
    end
  end
  table.sort(secret)
  say("combat: %d samples; %d calls readable%s", out.samples, readable,
    #secret > 0 and (", SECRET: " .. table.concat(secret, ", ")) or ", nothing secret")
  say("combat: /reload, then /bwp export (or send the SavedVariables file)")
end

function P.combat()
  combat.armed = true
  say("combat: armed - start a fight (hit a target dummy or a mob); recording stops when combat ends")
end

-- Export -------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jsonString(s)
  s = s:gsub('[%c"\\]', function(c) return ESC[c] or ("\\u%04x"):format(c:byte()) end)
  return '"' .. s:gsub("|", "\\u007c") .. '"' -- "|" breaks WoW edit boxes
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end

local function toJSON(v, buf)
  local t = type(v)
  if t == "table" then
    local arr, n = isArray(v)
    if arr then
      buf[#buf + 1] = "["
      for i = 1, n do
        if i > 1 then buf[#buf + 1] = "," end
        toJSON(v[i], buf)
      end
      buf[#buf + 1] = "]"
    else
      buf[#buf + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        if not first then buf[#buf + 1] = "," end
        first = false
        buf[#buf + 1] = jsonString(tostring(k))
        buf[#buf + 1] = ":"
        toJSON(val, buf)
      end
      buf[#buf + 1] = "}"
    end
  elseif t == "string" then
    buf[#buf + 1] = jsonString(v)
  elseif t == "number" then
    buf[#buf + 1] = (v ~= v or v == math.huge or v == -math.huge) and "null" or tostring(v)
  elseif t == "boolean" then
    buf[#buf + 1] = tostring(v)
  else
    buf[#buf + 1] = "null"
  end
end

function P.export()
  local buf = {}
  toJSON(db(), buf)
  local text = table.concat(buf)
  if not P.exportFrame then
    local f = CreateFrame("Frame", "BattlewrightProbeExport", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(640, 440)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BattlewrightProbeExport")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("BattlewrightProbe export  -  Ctrl+A, Ctrl+C, paste into a .json file")
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30)
    sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(580)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.edit = eb
    P.exportFrame = f
  end
  P.exportFrame.edit:SetText(text)
  P.exportFrame:Show()
  P.exportFrame.edit:SetFocus()
  P.exportFrame.edit:HighlightText()
  say("export: %d characters", #text)
end


-- Spell book -----------------------------------------------------------------------
-- What every talent and ability actually says on Forever, for theorycrafting:
-- /bwp book saves each talent's text at every rank (with its row, spec,
-- prerequisites and point requirement), every spell in your spell book (cost,
-- cast time, range, cooldown, rank, text), and, if a trainer window is open,
-- every service it lists with its text. Out of combat only. Spell text loads
-- on demand, so a second pass a moment later fills what came back empty.
local function call(fn, ...)
  if not fn then return nil end
  local res = pack(pcall(fn, ...))
  if not res[1] then return nil end
  return sanitize(res[2]), res
end

local function describe(spellID)
  local desc = spellID and C_Spell and call(C_Spell.GetSpellDescription, spellID)
  return type(desc) == "string" and desc ~= "" and desc or nil
end

local function bookTalents(out)
  local configID = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
  local config = configID and C_Traits and call(C_Traits.GetConfigInfo, configID)
  if type(config) ~= "table" or type(config.treeIDs) ~= "table" then out.error = "no talent tree"; return end
  out.conditions = {}
  for _, treeID in ipairs(config.treeIDs) do
    for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, treeID) or {}) do
      local node = call(C_Traits.GetNodeInfo, configID, nodeID)
      if type(node) == "table" then
        local rec = { nodeID = nodeID, maxRanks = node.maxRanks, rank = node.activeRank or node.currentRank,
          posX = node.posX, posY = node.posY, groupIDs = node.groupIDs, conditionIDs = node.conditionIDs,
          edges = {}, entries = {} }
        for _, e in ipairs(type(node.visibleEdges) == "table" and node.visibleEdges or {}) do
          rec.edges[#rec.edges + 1] = e.targetNode
        end
        for _, entryID in ipairs(type(node.entryIDs) == "table" and node.entryIDs or {}) do
          local entry = call(C_Traits.GetEntryInfo, configID, entryID)
          local def = type(entry) == "table" and entry.definitionID and call(C_Traits.GetDefinitionInfo, entry.definitionID)
          local spellID = type(def) == "table" and def.spellID or nil
          local e = { entryID = entryID, spellID = spellID, name = spellID and C_Spell and call(C_Spell.GetSpellName, spellID),
            ranks = {} }
          for r = 1, math.max(1, tonumber(node.maxRanks) or 1) do
            local text = C_Traits.GetTraitDescription and call(C_Traits.GetTraitDescription, entryID, r)
            e.ranks[r] = type(text) == "string" and text ~= "" and text or nil
          end
          e.spellText = describe(spellID)
          rec.entries[#rec.entries + 1] = e
        end
        for _, condID in ipairs(type(node.conditionIDs) == "table" and node.conditionIDs or {}) do
          if out.conditions[condID] == nil then
            out.conditions[condID] = call(C_Traits.GetConditionInfo, configID, condID) or false
          end
        end
        out.nodes[#out.nodes + 1] = rec
      end
    end
  end
end

-- Spell book: the modern C_SpellBook API, else the older per-tab one.
local function bookSpells(out)
  local list = {}
  local SB = C_SpellBook
  if SB and SB.GetNumSpellBookSkillLines then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, call(SB.GetNumSpellBookSkillLines) or 0 do
      local info = call(SB.GetSpellBookSkillLineInfo, line)
      if type(info) == "table" then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = call(SB.GetSpellBookItemInfo, i, bank)
          if type(item) == "table" and item.spellID then
            list[#list + 1] = { tab = info.name, id = item.spellID, passive = item.isPassive }
          end
        end
      end
    end
  elseif GetNumSpellTabs then
    for tab = 1, GetNumSpellTabs() do
      local name, _, offset, count = GetSpellTabInfo(tab)
      for i = offset + 1, offset + count do
        local _, id = GetSpellBookItemInfo(i, "spell")
        if id then list[#list + 1] = { tab = name, id = id } end
      end
    end
  end
  for _, s in ipairs(list) do
    local info = C_Spell and call(C_Spell.GetSpellInfo, s.id)
    if type(info) == "table" then
      s.name, s.castTime, s.minRange, s.maxRange = info.name, info.castTime, info.minRange, info.maxRange
    end
    s.rank = C_Spell and call(C_Spell.GetSpellSubtext, s.id)
    s.cost = C_Spell and call(C_Spell.GetSpellPowerCost, s.id)
    s.cooldownMs = GetSpellBaseCooldown and call(GetSpellBaseCooldown, s.id)
    s.text = describe(s.id)
    out.spells[#out.spells + 1] = s
  end
end

local function bookTrainer(out)
  local n = GetNumTrainerServices and call(GetNumTrainerServices) or 0
  if type(n) ~= "number" or n == 0 then return end
  out.trainer = { name = UnitName and call(UnitName, "npc"), services = {} }
  for i = 1, n do
    local _, res = call(GetTrainerServiceInfo, i)
    out.trainer.services[i] = {
      info = res and sanitize({ unpack(res, 2, res.n) }), -- name, rank/subtext, category...
      level = GetTrainerServiceLevelReq and call(GetTrainerServiceLevelReq, i),
      text = GetTrainerServiceDescription and call(GetTrainerServiceDescription, i) or nil,
    }
  end
end

local function bookPass(out)
  out.nodes, out.spells = {}, {}
  bookTalents(out)
  bookSpells(out)
  bookTrainer(out)
  local missing = 0
  for _, s in ipairs(out.spells) do if not s.text then missing = missing + 1 end end
  for _, n in ipairs(out.nodes) do
    for _, e in ipairs(n.entries) do if not (e.ranks[1] or e.spellText) then missing = missing + 1 end end
  end
  return missing
end

function P.book()
  if InCombatLockdown and InCombatLockdown() then return say("not in combat: try again after the fight") end
  local d = db()
  local out = { at = now(), character = UnitName and UnitName("player"), level = UnitLevel and UnitLevel("player") }
  d.book = out
  bookPass(out) -- asks for every spell's text; some arrive a moment later
  local function second()
    local missing = bookPass(out)
    say("book: %d talents, %d spells%s%s, %d without text. Now /bwp export",
      #out.nodes, #out.spells, out.trainer and ", " or "",
      out.trainer and (#out.trainer.services .. " trainer services") or "", missing)
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, second) else second() end
  say("reading talents and spells...")
end

-- Wiring ----------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
  pcall(events.RegisterEvent, events, e)
end

-- When the game blocks this addon ("...has been blocked from an action only
-- available to the Blizzard UI"), it names the function: keep it, so we know
-- which call to avoid.
local function blocked(event, addon, func)
  if addon ~= "BattlewrightProbe" then return end
  local d = db()
  d.blocked = d.blocked or {}
  local key = tostring(func)
  local rec = d.blocked[key] or { count = 0, event = event, first = now(), during = combat.lastCheck }
  rec.count = rec.count + 1
  d.blocked[key] = rec
  say("the game blocked %s (during: %s)", key, tostring(combat.lastCheck))
end
-- Events whose arguments a helper could use instead of polling.
-- (Not the combat log: reading it triggered "BattlewrightProbe has been blocked
-- from an action only available to the Blizzard UI" on the beta, 2026-10-04.)
local WATCHED = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_FREQUENT", "UNIT_AURA", "PLAYER_TARGET_CHANGED" }
local watchable = {}
for _, e in ipairs(WATCHED) do watchable[e] = pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    blocked(event, ...)
  elseif event == "PLAYER_REGEN_DISABLED" then
    combatStart()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if combat.out then combat.out.eventsRegistered = watchable end
    combatEnd()
  elseif combat.ticker and combat.out then
    local unit = ...
    if event:find("^UNIT_") and unit ~= "player" and unit ~= "target" then return end
    pcall(noteEvent, combat.out, event, ...)
  end
end)

local COMMANDS = {
  combat = P.combat,
  book = P.book,
  export = P.export,
  clear = function() BattlewrightProbeDB = nil; say("cleared") end,
}

SLASH_BATTLEWRIGHTPROBE1 = "/bwp"
SlashCmdList.BATTLEWRIGHTPROBE = function(msg)
  local cmd = (msg or ""):lower():match("^(%S*)")
  local fn = COMMANDS[cmd]
  if fn then
    local ok, err = pcall(fn)
    if not ok then say("|cffff5050error:|r %s", tostring(err)) end
  else
    say("usage: /bwp combat (record your next fight) | book (all talent and spell text) | export | clear")
  end
end
