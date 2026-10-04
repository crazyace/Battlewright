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


-- Wiring ----------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    combatStart()
  elseif event == "PLAYER_REGEN_ENABLED" then
    combatEnd()
  end
end)

local COMMANDS = {
  combat = P.combat,
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
    say("usage: /bwp combat (record your next fight) | export | clear")
  end
end
