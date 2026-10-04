-- Battlewright: the on-screen icon. A big icon for the next ability (dimmed,
-- with a countdown, while you wait for energy), a small one for a cooldown
-- worth using, an energy bar, and a line saying why. Shown in combat (or, if
-- you choose, with an attackable target); /bw unlock to move it.
--
-- Hidden ("secret") values: Forever hides energy and whether the target's cast
-- can be interrupted from addon code in combat. They can still be *shown*: the
-- game's widgets accept them (StatusBar:SetValue, Region:SetAlphaFromBoolean)
-- and draw them without the addon ever reading them. The energy bar and the
-- Kick icon's visibility work that way (the technique EllesmereUI's cast bars use).
local _, ns = ...

local Display = {}
ns.Display = Display

local SIZE, SMALL = 52, 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The spell's icon: by spell ID first (a lookup by name can miss; Kick showed
-- a question mark on the beta, 2026-10-04), then by name.
local icons = {} -- [name] = last icon found
local function texture(name, id)
  if C_Spell and C_Spell.GetSpellTexture then
    for _, key in ipairs({ id or false, name }) do
      if key then
        local ok, tex = pcall(C_Spell.GetSpellTexture, key)
        if ok and tex and not (issecretvalue and issecretvalue(tex)) then
          icons[name] = tex
          return tex
        end
      end
    end
  end
  return icons[name] or QUESTION
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
  -- Energy, drawn by the game even while it's secret to us.
  f.energy = CreateFrame("StatusBar", nil, f)
  f.energy:SetSize(SIZE, 5)
  f.energy:SetPoint("TOP", f, "BOTTOM", 0, -1)
  if f.energy.SetStatusBarTexture then f.energy:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar") end
  if f.energy.SetStatusBarColor then f.energy:SetStatusBarColor(1, 0.9, 0.2) end
  f.why:ClearAllPoints()
  f.why:SetPoint("TOP", f.energy, "BOTTOM", 0, -2)
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
  for _, v in ipairs({ main or false, cd or false }) do
    if v and s.spells[v.spell] then v.id = s.spells[v.spell].id end
  end
  return { main = main, cooldown = cd, spec = spec, state = s }
end

-- Energy bar: max and current go straight to the widget, secret or not.
function Display.UpdateEnergy()
  local bar = Display.frame and Display.frame.energy
  if not bar then return end
  local energyType = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
  local ok = pcall(function()
    bar:SetMinMaxValues(0, UnitPowerMax("player", energyType))
    bar:SetValue(UnitPower("player", energyType))
  end)
  bar:SetShown(ok)
end

-- Kick: shown unless the game says the cast can't be interrupted. That flag is
-- secret in combat, so the game applies it: alpha 0 when true, 1 when false.
-- (Only a secret flag ever gets here, and it's never compared or tested:
-- on Forever that's an error.)
local function kickVisibility(cd, icon)
  local flag = cd.notInterruptible
  if issecretvalue and issecretvalue(flag) and icon.SetAlphaFromBoolean then
    if not pcall(icon.SetAlphaFromBoolean, icon, flag, 0, 1) then icon:SetAlpha(1) end
  else
    icon:SetAlpha(1)
  end
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
  Display.UpdateEnergy()
  local ok, view = pcall(Display.Compute)
  if not ok then view = { message = "error: " .. tostring(view) } end
  Display.view = view -- read by tests
  local m = view.main
  if m then
    f.icon:SetTexture(texture(m.spell, m.id))
    f.icon:SetDesaturated(m.short == true)
    if f.icon.SetVertexColor then
      if m.outOfRange then f.icon:SetVertexColor(1, 0.35, 0.35) else f.icon:SetVertexColor(1, 1, 1) end
    end
    f.wait:SetText(m.wait and m.wait > 0 and ("%.1f"):format(m.wait) or "")
    f.why:SetText(m.outOfRange and (m.spell .. ": out of range") or (m.spell .. ": " .. m.why))
  else
    f.icon:SetTexture(QUESTION)
    f.icon:SetDesaturated(true)
    f.wait:SetText("")
    f.why:SetText(view.message or (not ns.db.locked and "Battlewright (drag me, /bw lock)") or "")
  end
  if view.cooldown then
    f.cd.icon:SetTexture(texture(view.cooldown.spell, view.cooldown.id))
    -- An interrupt is urgent: make it as big as the main icon.
    f.cd:SetSize(view.cooldown.urgent and SIZE or SMALL, view.cooldown.urgent and SIZE or SMALL)
    kickVisibility(view.cooldown, f.cd)
    f.cd:Show()
  else
    f.cd:Hide()
  end
end

ns:On("PLAYER_LOGIN", function() Display.Create() end)
