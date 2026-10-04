-- Battlewright: the rotation guide window (/bw guide). Your rotation written
-- out from what you have: spec, weapons, known spells and talents. The text
-- comes from the class file (Rogue.Guide, Rogue.GuidePath), so it always
-- matches the icon.
--
-- The look follows ForeverDungeonJournal by Exehn: a stone window in the gold
-- dialog border, a dark title band between thin gold lines, and tooltip-edged
-- cards in its warm "Hall of Thanes" colors over a faint parchment.
local _, ns = ...

local Guide = {}
ns.Guide = Guide

-- Landscape, like ForeverDungeonJournal: wide enough for a whole cycle on one
-- row of icons. INNER is the scroll area's width (window - page insets 2 x 16
-- - scroll frame insets 8 + 28) less a small margin, so cards never clip.
local WIDTH, HEIGHT = 600, 520
local INNER = WIDTH - 32 - 36 - 6
local ROW_ICON, PATH_ICON = 26, 30
local CELL, LABEL_WIDTH = 50, 112 -- path: one icon's slot, the lane label column

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local THEME = {
  window = { 0.045, 0.042, 0.037, 0.99 },
  band = { 0.14, 0.10, 0.055, 0.96 },
  gold = { 0.68, 0.52, 0.20 },
  panel = { 0.24, 0.18, 0.10, 0.90 },
  border = { 0.52, 0.36, 0.16, 1 },
  card = { 0.17, 0.11, 0.06, 0.94 },
  title = { 1.00, 0.80, 0.34 },
  text = { 0.93, 0.84, 0.66 },
  muted = { 0.82, 0.74, 0.60 },
}

local function backdrop(f, bg, edge, edgeSize, inset)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = bg, edgeFile = edge, tile = true, tileSize = 16, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset } })
end

local function panel(parent, color)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  backdrop(p, WHITE, EDGE, 12, 3)
  if p.SetBackdropColor then
    p:SetBackdropColor(unpack(color or THEME.panel))
    p:SetBackdropBorderColor(unpack(THEME.border))
  end
  return p
end

local function parchment(f, alpha)
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -2)
  t:SetPoint("TOPLEFT", 3, -3)
  t:SetPoint("BOTTOMRIGHT", -3, 3)
  t:SetTexture("Interface\\QuestFrame\\QuestBG")
  t:SetVertexColor(1, 0.95, 0.84)
  t:SetAlpha(alpha)
  return t
end

local function line(parent, anchor, point, alpha)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(WHITE)
  t:SetPoint(point .. "LEFT", anchor, point .. "LEFT", 0, 0)
  t:SetPoint(point .. "RIGHT", anchor, point .. "RIGHT", 0, 0)
  t:SetHeight(1)
  t:SetColorTexture(THEME.gold[1], THEME.gold[2], THEME.gold[3], alpha)
  return t
end

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
  local f = CreateFrame("Frame", "BattlewrightGuide", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", 0, 10)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  backdrop(f, "Interface\\FrameGeneral\\UI-Background-Rock", "Interface\\DialogFrame\\UI-DialogBox-Border", 24, 6)
  if f.SetBackdropColor then f:SetBackdropColor(unpack(THEME.window)) end
  if UISpecialFrames then tinsert(UISpecialFrames, "BattlewrightGuide") end -- Escape closes it

  -- Title band.
  local band = f:CreateTexture(nil, "BACKGROUND")
  band:SetTexture(WHITE)
  band:SetColorTexture(unpack(THEME.band))
  band:SetPoint("TOPLEFT", 12, -10)
  band:SetPoint("TOPRIGHT", -12, -10)
  band:SetHeight(44)
  line(f, band, "TOP", 0.65)
  line(f, band, "BOTTOM", 0.45)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", 0, -16)
  f.title:SetText("Battlewright")
  f.title:SetTextColor(0.96, 0.79, 0.25)
  f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -3)
  f.subtitle:SetTextColor(unpack(THEME.muted))
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)

  -- The page: a parchment panel holding the scrolling content.
  local page = panel(f)
  page:SetPoint("TOPLEFT", 16, -60)
  page:SetPoint("BOTTOMRIGHT", -16, 16)
  parchment(page, 0.18)
  local sf = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -28, 8)
  f.content = CreateFrame("Frame", nil, sf)
  f.content:SetSize(INNER, 10)
  sf:SetScrollChild(f.content)
  -- Path icons and words sit on a layer above the lane cards (a child frame
  -- draws over its parent's own textures).
  f.layer = CreateFrame("Frame", nil, f.content)
  f.layer:SetAllPoints(f.content)
  if f.layer.SetFrameLevel and f.content.GetFrameLevel then
    f.layer:SetFrameLevel((tonumber(f.content:GetFrameLevel()) or 1) + 5)
  end

  f.headers = {} -- section titles: { text, rule }
  f.lines = {}   -- cards: { card, icon, text }
  f.lanes = {}   -- path lanes: a card each
  f.cells = {}   -- path icons: { icon, note, count }
  f.words = {}   -- path text: lane labels, arrows, "step behind"
  f:Hide()
  return f
end

-- Pools: widgets are made once and reused on every refresh.
local function pooled(list, i, make)
  if not list[i] then list[i] = make() end
  return list[i]
end

local function header(f, i)
  return pooled(f.headers, i, function()
    local h = { text = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal") }
    h.text:SetJustifyH("LEFT")
    h.text:SetTextColor(unpack(THEME.title))
    h.rule = f.content:CreateTexture(nil, "ARTWORK")
    h.rule:SetTexture(WHITE)
    h.rule:SetColorTexture(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.55)
    h.rule:SetHeight(1)
    return h
  end)
end

local function card(f, i)
  return pooled(f.lines, i, function()
    local c = { card = panel(f.content, THEME.card) }
    c.icon = c.card:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(ROW_ICON, ROW_ICON)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.text = c.card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetJustifyH("LEFT")
    c.text:SetTextColor(unpack(THEME.text))
    if c.text.SetWordWrap then c.text:SetWordWrap(true) end
    return c
  end)
end

local function lane(f, i)
  return pooled(f.lanes, i, function() return panel(f.content, THEME.card) end)
end

local function cell(f, i)
  return pooled(f.cells, i, function()
    local c = { icon = f.layer:CreateTexture(nil, "OVERLAY"),
      note = f.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      count = f.layer:CreateFontString(nil, "OVERLAY", "NumberFontNormal") }
    c.icon:SetSize(PATH_ICON, PATH_ICON)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.note:SetWidth(CELL + 16)
    c.note:SetJustifyH("CENTER")
    c.note:SetTextColor(unpack(THEME.muted))
    return c
  end)
end

local function word(f, i)
  return pooled(f.words, i, function()
    local w = f.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w:SetJustifyH("LEFT")
    return w
  end)
end

local function stringHeight(fs, fallback)
  local h = fs.GetStringHeight and tonumber(fs:GetStringHeight())
  return math.max(h or fallback, fallback)
end

local function stringWidth(fs, text)
  return (fs.GetStringWidth and tonumber(fs:GetStringWidth())) or (#text * 6)
end

local function hideAll(f)
  for _, h in ipairs(f.headers) do h.text:Hide(); h.rule:Hide() end
  for _, c in ipairs(f.lines) do c.card:Hide() end
  for _, l in ipairs(f.lanes) do l:Hide() end
  for _, c in ipairs(f.cells) do c.icon:Hide(); c.note:Hide(); c.count:Hide() end
  for _, w in ipairs(f.words) do w:Hide() end
end

function Guide.Refresh()
  local f = Guide.frame
  if not (f and f:IsShown()) then return end
  local sections, specOrWhy, _, path = Guide.Build()
  Guide.sections, Guide.path = sections, path -- read by tests
  hideAll(f)
  local level = UnitLevel and UnitLevel("player")
  local specName = sections and (specOrWhy:gsub("^%l", string.upper)) or nil
  f.subtitle:SetText(specName and ("Your rotation  -  %s%s"):format(specName, level and ("  -  level " .. level) or "") or "")

  local y, nh, nl, nlane, nc, nw = 0, 0, 0, 0, 0, 0

  local function addHeader(text)
    nh = nh + 1
    local h = header(f, nh)
    y = y - (nh > 1 and 10 or 2)
    h.text:ClearAllPoints()
    h.text:SetPoint("TOPLEFT", f.content, "TOPLEFT", 2, y)
    h.text:SetText(text)
    h.text:Show()
    y = y - 16
    h.rule:ClearAllPoints()
    h.rule:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    h.rule:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, y)
    h.rule:Show()
    y = y - 6
  end

  local function addCard(text, spell, id)
    nl = nl + 1
    local c = card(f, nl)
    local hasIcon = spell or id
    c.text:ClearAllPoints()
    c.text:SetPoint("TOPLEFT", c.card, "TOPLEFT", hasIcon and (ROW_ICON + 16) or 10, -8)
    c.text:SetWidth(INNER - (hasIcon and (ROW_ICON + 26) or 20))
    c.text:SetText(text)
    if hasIcon then
      c.icon:SetTexture(ns.Display.Texture(spell, id))
      c.icon:ClearAllPoints()
      c.icon:SetPoint("TOPLEFT", c.card, "TOPLEFT", 7, -6)
      c.icon:Show()
    else
      c.icon:Hide()
    end
    local height = math.max(stringHeight(c.text, 12) + 16, hasIcon and (ROW_ICON + 12) or 0)
    c.card:ClearAllPoints()
    c.card:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    c.card:SetSize(INNER, height)
    c.card:Show()
    y = y - height - 4
  end

  local function addWord(text, width, x, top, color)
    nw = nw + 1
    local w = word(f, nw)
    w:ClearAllPoints()
    w:SetWidth(width)
    w:SetText(text)
    w:SetTextColor(unpack(color or THEME.text))
    w:SetPoint("TOPLEFT", f.content, "TOPLEFT", x, top)
    w:Show()
    return w
  end

  -- One lane: a card with its label on the left and the steps as icons,
  -- wrapping onto a second row when they don't fit.
  local function addLane(l)
    local rowHeight = PATH_ICON + 18
    local top = y
    local x, rowTop = LABEL_WIDTH, y - 8
    addWord(l.label, LABEL_WIDTH - 12, 10, rowTop - 8, THEME.title)
    for i, st in ipairs(l.steps) do
      if i > 1 then
        if x + 14 + CELL > INNER - 6 then x, rowTop = LABEL_WIDTH, rowTop - rowHeight end
        addWord(">", 12, x + 2, rowTop - 9, THEME.muted)
        x = x + 14
      end
      if st.text then
        local width = #st.text * 6 + 6
        if x + width > INNER - 6 then x, rowTop = LABEL_WIDTH, rowTop - rowHeight end
        local w = addWord(st.text, 0, x, rowTop - 9, THEME.muted)
        x = x + math.max(width, stringWidth(w, st.text) + 6)
      else
        if x + CELL > INNER - 6 then x, rowTop = LABEL_WIDTH, rowTop - rowHeight end
        nc = nc + 1
        local c = cell(f, nc)
        c.icon:SetTexture(ns.Display.Texture(st.spell, st.id))
        c.icon:ClearAllPoints()
        c.icon:SetPoint("TOPLEFT", f.content, "TOPLEFT", x + (CELL - PATH_ICON) / 2, rowTop)
        c.icon:Show()
        c.count:ClearAllPoints()
        c.count:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 2, -1)
        c.count:SetText(st.count and ("x" .. st.count) or "")
        c.count:Show()
        c.note:ClearAllPoints()
        c.note:SetPoint("TOP", c.icon, "BOTTOM", 0, -2)
        c.note:SetText(st.note or "")
        c.note:Show()
        x = x + CELL
      end
    end
    local height = (top - rowTop) + rowHeight
    nlane = nlane + 1
    local box = lane(f, nlane)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, top)
    box:SetSize(INNER, height)
    box:Show()
    y = top - height - 4
  end

  if not sections then
    addCard(specOrWhy)
  else
    if path and #path > 0 then
      addHeader("At a glance")
      for _, l in ipairs(path) do addLane(l) end
    end
    for _, sec in ipairs(sections) do
      addHeader(sec.title)
      for _, r in ipairs(sec.rows) do addCard(r.text, r.spell, r.id) end
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
