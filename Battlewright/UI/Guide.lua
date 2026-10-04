-- Battlewright: the rotation guide window (/bw guide). Your rotation written
-- out from what you have: spec, weapons, known spells and talents. The text
-- comes from the class file (Rogue.Guide), so it always matches the icon.
local _, ns = ...

local Guide = {}
ns.Guide = Guide

local WIDTH, HEIGHT, ICON = 380, 500, 18
local TEXT_WIDTH = WIDTH - 70
local CONTENT_WIDTH = WIDTH - 50
-- The rotation path: icons in lanes, a label column on the left.
local PATH_ICON, CELL, LABEL_WIDTH, LANE_GAP = 26, 38, 74, 8

-- Sections and the rotation path for the current character, or nil and why not.
function Guide.Build()
  local _, class = UnitClass("player")
  local rotation = ns.Rotations[class]
  if not (rotation and rotation.Guide) then return nil, "no rotation for your class yet" end
  ns.Talents.Refresh()
  local s = ns.State.Read()
  if not s then return nil, "open the guide out of combat" end
  local spec, how = ns.Spec.Detect(class, s.spells)
  local sections = rotation.Guide(s, spec, UnitLevel and UnitLevel("player") or nil)
  local path = rotation.GuidePath and rotation.GuidePath(s, spec) or nil
  return sections, spec, how, path
end

local function create()
  local f = CreateFrame("Frame", "BattlewrightGuide", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  if UISpecialFrames then tinsert(UISpecialFrames, "BattlewrightGuide") end -- Escape closes it
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.title:SetText("Battlewright: your rotation")
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -30)
  sf:SetPoint("BOTTOMRIGHT", -32, 12)
  f.content = CreateFrame("Frame", nil, sf)
  f.content:SetSize(WIDTH - 50, 10)
  sf:SetScrollChild(f.content)
  f.lines = {} -- reused: { icon, text }
  f.cells = {} -- reused path icons: { icon, note, count }
  f.words = {} -- reused path text: arrows, lane labels, "step behind"
  f:Hide()
  return f
end

local function line(f, i)
  local l = f.lines[i]
  if not l then
    l = { icon = f.content:CreateTexture(nil, "ARTWORK"), text = f.content:CreateFontString(nil, "OVERLAY") }
    l.icon:SetSize(ICON, ICON)
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.text:SetJustifyH("LEFT")
    if l.text.SetWordWrap then l.text:SetWordWrap(true) end
    f.lines[i] = l
  end
  return l
end

local function cell(f, i)
  local c = f.cells[i]
  if not c then
    c = { icon = f.content:CreateTexture(nil, "ARTWORK"),
      note = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      count = f.content:CreateFontString(nil, "OVERLAY", "NumberFontNormal") }
    c.icon:SetSize(PATH_ICON, PATH_ICON)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.note:SetWidth(CELL + 12)
    c.note:SetJustifyH("CENTER")
    f.cells[i] = c
  end
  return c
end

local function word(f, i)
  local w = f.words[i]
  if not w then
    w = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w:SetJustifyH("LEFT")
    f.words[i] = w
  end
  return w
end

local function textWidth(fs, text)
  local w = fs.GetStringWidth and tonumber(fs:GetStringWidth())
  return w or (#text * 6)
end

-- Draws the lanes from `y` down; returns the y below them.
local function drawPath(f, lanes, y)
  local nc, nw = 0, 0
  local rowHeight = PATH_ICON + 16
  local function newWord(text, width, x, dy)
    nw = nw + 1
    local w = word(f, nw)
    w:ClearAllPoints()
    w:SetWidth(width)
    w:SetText(text)
    w:SetPoint("TOPLEFT", f.content, "TOPLEFT", x, y - dy)
    w:Show()
    return w
  end
  for _, lane in ipairs(lanes) do
    newWord(lane.label, LABEL_WIDTH - 4, 0, 6)
    local x = LABEL_WIDTH
    for i, st in ipairs(lane.steps) do
      if i > 1 then -- an arrow between steps
        if x + 12 + CELL > CONTENT_WIDTH then x, y = LABEL_WIDTH, y - rowHeight end
        newWord(">", 10, x, 7)
        x = x + 12
      end
      if st.text then
        local width = #st.text * 6 + 4
        if x + width > CONTENT_WIDTH then x, y = LABEL_WIDTH, y - rowHeight end
        local w = newWord(st.text, 0, x, 7)
        x = x + math.max(width, textWidth(w, st.text) + 4)
      else
        if x + CELL > CONTENT_WIDTH then x, y = LABEL_WIDTH, y - rowHeight end
        nc = nc + 1
        local c = cell(f, nc)
        c.icon:SetTexture(ns.Display.Texture(st.spell, st.id))
        c.icon:ClearAllPoints()
        c.icon:SetPoint("TOPLEFT", f.content, "TOPLEFT", x + (CELL - PATH_ICON) / 2, y)
        c.icon:Show()
        c.count:ClearAllPoints()
        c.count:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 2, -1)
        c.count:SetText(st.count and ("x" .. st.count) or "")
        c.count:Show()
        c.note:ClearAllPoints()
        c.note:SetPoint("TOP", c.icon, "BOTTOM", 0, -1)
        c.note:SetText(st.note or "")
        c.note:Show()
        x = x + CELL
      end
    end
    y = y - rowHeight - LANE_GAP
  end
  return y
end

local function height(fs, fallback)
  local h = fs.GetStringHeight and tonumber(fs:GetStringHeight())
  return math.max(h or fallback, fallback)
end

function Guide.Refresh()
  local f = Guide.frame
  if not (f and f:IsShown()) then return end
  local sections, specOrWhy, _, path = Guide.Build()
  Guide.sections, Guide.path = sections, path -- read by tests
  for _, l in ipairs(f.lines) do l.icon:Hide(); l.text:Hide() end
  for _, c in ipairs(f.cells) do c.icon:Hide(); c.note:Hide(); c.count:Hide() end
  for _, w in ipairs(f.words) do w:Hide() end
  local n, y = 0, -4
  local function add(text, spell, id, header)
    n = n + 1
    local l = line(f, n)
    l.text:SetFontObject(header and "GameFontNormal" or "GameFontHighlightSmall")
    l.text:ClearAllPoints()
    if header or not (spell or id) then
      l.icon:Hide()
      l.text:SetPoint("TOPLEFT", f.content, "TOPLEFT", header and 0 or (ICON + 6), y)
    else
      l.icon:SetTexture(ns.Display.Texture(spell, id))
      l.icon:ClearAllPoints()
      l.icon:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
      l.icon:Show()
      l.text:SetPoint("TOPLEFT", f.content, "TOPLEFT", ICON + 6, y - 2)
    end
    l.text:SetWidth(header and CONTENT_WIDTH or TEXT_WIDTH)
    l.text:SetText(text)
    l.text:Show()
    y = y - height(l.text, header and 14 or ICON) - (header and 6 or 4)
  end
  if not sections then
    add(specOrWhy, nil, nil, false)
  else
    if path and #path > 0 then
      add("Your rotation at a glance", nil, nil, true)
      y = drawPath(f, path, y) - 4
    end
    for _, sec in ipairs(sections) do
      if n > 0 then y = y - 6 end
      add(sec.title, nil, nil, true)
      for _, r in ipairs(sec.rows) do add(r.text, r.spell, r.id, false) end
    end
  end
  f.content:SetHeight(-y + 10)
end

function Guide.Toggle()
  Guide.frame = Guide.frame or create()
  if Guide.frame:IsShown() then
    Guide.frame:Hide()
  else
    Guide.frame:Show()
    Guide.Refresh()
  end
end

-- Keep it current while it's open (out of combat: talents read then).
for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
  "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED" }) do
  ns:On(event, function()
    if not (InCombatLockdown and InCombatLockdown()) then Guide.Refresh() end
  end)
end
