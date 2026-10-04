-- Battlewright: the on-screen icon. A big icon for the next ability (dimmed,
-- with a countdown, while you wait for energy), a small one for a cooldown
-- worth using, and a line saying why. Shown in combat (or, if you choose, with
-- an attackable target); /bw unlock to move it.
local _, ns = ...

local Display = {}
ns.Display = Display

local SIZE, SMALL = 52, 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function texture(name)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, name)
    if ok and tex then return tex end
  end
  return QUESTION
end

function Display.Create()
  if Display.frame then return Display.frame end
  local f = CreateFrame("Frame", "BattlewrightFrame", UIParent)
  f:SetSize(SIZE, SIZE)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.point = { point, rel, x, y }
  end)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.wait = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.wait:SetPoint("CENTER")
  f.why = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.why:SetPoint("TOP", f, "BOTTOM", 0, -3)
  f.cd = CreateFrame("Frame", nil, f)
  f.cd:SetSize(SMALL, SMALL)
  f.cd:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 4, 0)
  f.cd.icon = f.cd:CreateTexture(nil, "ARTWORK")
  f.cd.icon:SetAllPoints()
  f.cd.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  Display.frame = f
  Display.Place()
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 0.1 then elapsed = 0; Display.Update() end
  end)
  return f
end

function Display.Place()
  local f, p = Display.frame, ns.db.point
  f:ClearAllPoints()
  f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  f:SetScale(ns.db.scale or 1)
end

-- What to show: { main, cooldown, message } from the game's state.
function Display.Compute()
  local _, class = UnitClass("player")
  local rotation = ns.Rotations[class]
  if not rotation then return { message = "no rotation for your class yet" } end
  local s, reason = ns.State.Read()
  if not s then
    return { message = reason == "secret" and "the game hides combat data from addons" or "can't read your state" }
  end
  local spec = ns.Spec.Detect(class, s.spells)
  local main, cd = rotation.Next(s, spec)
  return { main = main, cooldown = cd, spec = spec, state = s }
end

function Display.Update()
  local f = Display.frame
  if not f then return end
  local show = ns.db.enabled and (not ns.db.locked or (UnitAffectingCombat and UnitAffectingCombat("player"))
    or (ns.db.showOutOfCombat and UnitExists("target") and UnitCanAttack("player", "target")))
  if not show then
    f:SetAlpha(0)
    return
  end
  f:SetAlpha(1)
  local ok, view = pcall(Display.Compute)
  if not ok then view = { message = "error: " .. tostring(view) } end
  Display.view = view -- read by tests
  local m = view.main
  if m then
    f.icon:SetTexture(texture(m.spell))
    f.icon:SetDesaturated(m.wait > 0)
    f.wait:SetText(m.wait > 0 and ("%.1f"):format(m.wait) or "")
    f.why:SetText(m.spell .. ": " .. m.why)
  else
    f.icon:SetTexture(QUESTION)
    f.icon:SetDesaturated(true)
    f.wait:SetText("")
    f.why:SetText(view.message or (not ns.db.locked and "Battlewright (drag me, /bw lock)") or "")
  end
  if view.cooldown then
    f.cd.icon:SetTexture(texture(view.cooldown.spell))
    f.cd:Show()
  else
    f.cd:Hide()
  end
end

ns:On("PLAYER_LOGIN", function() Display.Create() end)
