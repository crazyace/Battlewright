-- Battlewright: the rotation guide window (/bw guide). Your rotation written
-- out from what you have: spec, weapons, known spells and talents. The text
-- comes from the class file (Rogue.Guide, Rogue.GuidePath), so it always
-- matches the icon.
--
-- The look: a flat graphite window with a 1 px edge, a title band, a toolbar
-- of tabs under it, and flat cards with a
-- thin blue accent edge. Larger type and more room between things than the game's
-- small tooltip text, so the guide reads at a glance.
local _, ns = ...

local Guide = {}
ns.Guide = Guide

-- Landscape: wide enough for a whole cycle on one row of icons. INNER is the
-- scroll area's width (window - page insets 2 x 18 - scroll frame insets
-- 14 + 30) less a small margin, so cards never clip.
local WIDTH, HEIGHT = 760, 640
local INNER = WIDTH - 36 - 44 - 8
local TOP_BAR = 108 -- title band + toolbar: the page starts below it
local ROW_ICON, PATH_ICON = 32, 34
local CELL, LABEL_WIDTH = 58, 132 -- path: one icon's slot, the lane label column
local PAD, GAP = 12, 8 -- inside a card, between cards

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local SIZE = { title = 20, header = 15, body = 13, small = 12 }
-- Graphite with one cool accent. Every color is here: change `accent` to
-- re-tint the whole window.
local THEME = {
  window = { 0.075, 0.080, 0.090, 0.97 },
  band = { 0.095, 0.100, 0.112, 1 },
  accent = { 0.36, 0.64, 1.00 },
  page = { 0.060, 0.064, 0.072, 0.98 },
  border = { 0.20, 0.215, 0.24, 1 },
  card = { 0.105, 0.112, 0.125, 1 },
  cardEdge = { 0.17, 0.18, 0.20, 1 },
  title = { 0.96, 0.97, 0.99 },
  text = { 0.88, 0.90, 0.93 },
  muted = { 0.58, 0.61, 0.66 },
  tabOn = { 0.15, 0.17, 0.21, 1 },
  tabOff = { 0.095, 0.100, 0.112, 1 },
  frameEdge = { 0.22, 0.235, 0.26, 1 },
  tree = { 0.085, 0.090, 0.100, 1 },
  nodeEdge = { 0.19, 0.20, 0.22, 1 },
}
local ACCENT = { THEME.accent[1], THEME.accent[2], THEME.accent[3], 1 }

-- The guide's own type sizes (the game's font objects are tooltip-small).
local function font(fs, size, flags)
  if fs.SetFont then fs:SetFont(FONT, size, flags or "") end
  return fs
end

local function backdrop(f, bg, edge, edgeSize, inset)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = bg, edgeFile = edge, tile = true, tileSize = 16, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset } })
end

-- A flat box with a 1-pixel edge.
local function flat(f, color, edge)
  backdrop(f, WHITE, WHITE, 1, 0)
  if f.SetBackdropColor then
    f:SetBackdropColor(unpack(color))
    f:SetBackdropBorderColor(unpack(edge or THEME.cardEdge))
  end
end

local function panel(parent, color, accent)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  flat(p, color or THEME.card)
  if accent then -- an accent edge down the left side
    p.accent = p:CreateTexture(nil, "ARTWORK")
    p.accent:SetTexture(WHITE)
    p.accent:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
    p.accent:SetPoint("TOPLEFT", 1, -1)
    p.accent:SetPoint("BOTTOMLEFT", 1, 1)
    p.accent:SetWidth(2)
  end
  return p
end

-- A tab: flat, accent-edged when it's the one shown.
local function tabButton(parent, label, width)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 26)
  flat(b, THEME.tabOff)
  b.text = font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.small)
  b.text:SetPoint("CENTER")
  b.text:SetText(label)
  if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
  return b
end

local function line(parent, anchor, point, alpha)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(WHITE)
  t:SetPoint(point .. "LEFT", anchor, point .. "LEFT", 0, 0)
  t:SetPoint(point .. "RIGHT", anchor, point .. "RIGHT", 0, 0)
  t:SetHeight(1)
  t:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], alpha)
  return t
end

-- "solo" or "group": what you picked, else Group while you're in a party.
function Guide.Mode()
  local picked = ns.db and ns.db.guideMode
  if picked == "solo" or picked == "group" then return picked end
  return (IsInGroup and IsInGroup()) and "group" or "solo"
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
  local mode = Guide.Mode()
  local sections = rotation.Guide(s, spec, UnitLevel and UnitLevel("player") or nil, mode)
  local path = rotation.GuidePath and rotation.GuidePath(s, spec, mode) or nil
  local talents = rotation.TalentGuide
    and rotation.TalentGuide(s, mode, UnitLevel and UnitLevel("player") or nil, ns.db and ns.db.guideBuild or nil) or nil
  if talents then talents.ranks, talents.list = s.talents or {}, ns.Talents.Get().list end
  return sections, spec, how, path, talents
end

-- "rotation" or "talents": the page the window shows.
function Guide.Page()
  local page = ns.db and ns.db.guidePage
  return page == "talents" and "talents" or "rotation"
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
  flat(f, THEME.window, THEME.frameEdge)
  -- A second, darker line just inside the outer one: a framed edge without the
  -- game's heavy stone border.
  local inner = CreateFrame("Frame", nil, f, "BackdropTemplate")
  inner:SetPoint("TOPLEFT", 3, -3)
  inner:SetPoint("BOTTOMRIGHT", -3, 3)
  backdrop(inner, nil, WHITE, 1, 0)
  if inner.SetBackdropBorderColor then inner:SetBackdropBorderColor(unpack(THEME.cardEdge)) end
  if UISpecialFrames then tinsert(UISpecialFrames, "BattlewrightGuide") end -- Escape closes it

  -- Title band: the name, and your spec and level under it.
  local band = f:CreateTexture(nil, "BACKGROUND")
  band:SetTexture(WHITE)
  band:SetColorTexture(unpack(THEME.band))
  band:SetPoint("TOPLEFT", 4, -4)
  band:SetPoint("TOPRIGHT", -4, -4)
  band:SetHeight(58)
  line(f, band, "BOTTOM", 0.5)
  f.title = font(f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), SIZE.title)
  f.title:SetPoint("TOP", 0, -14)
  f.title:SetText("Battlewright")
  f.title:SetTextColor(unpack(THEME.title))
  f.subtitle = font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.small)
  f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
  f.subtitle:SetTextColor(unpack(THEME.muted))
  -- Close: a flat square that matches the tabs (Escape closes it too).
  local close = CreateFrame("Button", nil, f, "BackdropTemplate")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -12, -12)
  flat(close, THEME.tabOff, THEME.border)
  close.text = font(close:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.body)
  close.text:SetPoint("CENTER", 0, 0)
  close.text:SetText("x")
  close.text:SetTextColor(unpack(THEME.muted))
  close:SetScript("OnEnter", function() close.text:SetTextColor(unpack(THEME.accent)) end)
  close:SetScript("OnLeave", function() close.text:SetTextColor(unpack(THEME.muted)) end)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close

  -- Toolbar under the band: the pages on the left, Solo / Group on the right.
  f.pages = {}
  for i, key in ipairs({ "rotation", "talents" }) do
    local b = tabButton(f, key == "rotation" and "Rotation" or "Talents", 104)
    b:SetPoint("TOPLEFT", 18 + (i - 1) * 108, -74)
    b:SetScript("OnClick", function() Guide.SetPage(key) end)
    f.pages[key] = b
  end
  f.modes = {}
  for i, mode in ipairs({ "solo", "group" }) do
    local b = tabButton(f, mode == "solo" and "Solo" or "Group", 84)
    b:SetPoint("TOPRIGHT", -18 - (2 - i) * 88, -74)
    b:SetScript("OnClick", function() Guide.SetMode(mode) end)
    b.mode = mode
    f.modes[mode] = b
  end

  -- The page: a dark panel holding the scrolling content.
  local page = panel(f, THEME.page)
  if page.SetBackdropBorderColor then page:SetBackdropBorderColor(unpack(THEME.border)) end
  page:SetPoint("TOPLEFT", 18, -TOP_BAR)
  page:SetPoint("BOTTOMRIGHT", -18, 18)
  -- Scrolling: the mouse wheel, and a slim bar on the right (no arrow buttons).
  local sf = CreateFrame("ScrollFrame", nil, page)
  sf:SetPoint("TOPLEFT", 14, -14)
  sf:SetPoint("BOTTOMRIGHT", -30, 14)
  f.content = CreateFrame("Frame", nil, sf)
  f.content:SetSize(INNER, 10)
  sf:SetScrollChild(f.content)
  local bar = CreateFrame("Slider", nil, page)
  bar:SetPoint("TOPRIGHT", -10, -14)
  bar:SetPoint("BOTTOMRIGHT", -10, 14)
  bar:SetWidth(6)
  if bar.SetOrientation then bar:SetOrientation("VERTICAL") end
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(bar)
  track:SetColorTexture(1, 1, 1, 0.05)
  if bar.SetThumbTexture then
    bar:SetThumbTexture(WHITE)
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
      thumb:SetSize(6, 48)
      thumb:SetColorTexture(THEME.muted[1], THEME.muted[2], THEME.muted[3], 0.5)
    end
  end
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)
  bar:Hide() -- until there's something to scroll
  if bar.SetValueStep then bar:SetValueStep(1) end
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf:SetScript("OnScrollRangeChanged", function(_, _, range)
    range = math.max(0, tonumber(range) or 0)
    bar:SetMinMaxValues(0, range)
    if (tonumber(bar:GetValue()) or 0) > range then bar:SetValue(range) end
    if range > 0 then bar:Show() else bar:Hide() end
  end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local _, range = bar:GetMinMaxValues()
    local v = (tonumber(bar:GetValue()) or 0) - delta * 60
    bar:SetValue(math.max(0, math.min(tonumber(range) or 0, v)))
  end)
  f.scroll, f.bar = sf, bar
  -- Path icons and words sit on a layer above the lane cards (a child frame
  -- draws over its parent's own textures).
  f.layer = CreateFrame("Frame", nil, f.content)
  f.layer:SetAllPoints(f.content)
  if f.layer.SetFrameLevel and f.content.GetFrameLevel then
    f.layer:SetFrameLevel((tonumber(f.content:GetFrameLevel()) or 1) + 5)
  end

  f.headers = {} -- section titles: { text, rule }
  f.builds = {}  -- talents page: build buttons
  f.nodes = {}   -- talents page: tree nodes
  f.trees = {}   -- talents page: a heading per tree
  f.treeBoxes = {} -- talents page: a box behind each tree
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
    local h = { text = font(f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal"), SIZE.header) }
    h.text:SetJustifyH("LEFT")
    h.text:SetTextColor(unpack(THEME.title))
    h.rule = f.content:CreateTexture(nil, "ARTWORK")
    h.rule:SetTexture(WHITE)
    h.rule:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    h.rule:SetHeight(1)
    return h
  end)
end

local function card(f, i)
  return pooled(f.lines, i, function()
    local c = { card = panel(f.content, THEME.card, true) }
    c.icon = c.card:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(ROW_ICON, ROW_ICON)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.text = font(c.card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.body)
    if c.text.SetSpacing then c.text:SetSpacing(3) end
    c.text:SetJustifyH("LEFT")
    c.text:SetTextColor(unpack(THEME.text))
    if c.text.SetWordWrap then c.text:SetWordWrap(true) end
    return c
  end)
end

local function lane(f, i)
  return pooled(f.lanes, i, function() return panel(f.content, THEME.card, true) end)
end

local function cell(f, i)
  return pooled(f.cells, i, function()
    local c = { icon = f.layer:CreateTexture(nil, "OVERLAY"),
      note = font(f.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.small - 1),
      count = font(f.layer:CreateFontString(nil, "OVERLAY", "NumberFontNormal"), SIZE.body, "OUTLINE") }
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
    local w = font(f.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.body)
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
  for _, b in ipairs(f.builds) do b:Hide() end
  for _, n in ipairs(f.nodes) do n:Hide() end
  for _, h in ipairs(f.trees) do h:Hide() end
  for _, b in ipairs(f.treeBoxes) do b:Hide() end
end

local function paintTabs(tabs, current)
  for key, b in pairs(tabs) do
    local on = key == current
    if b.SetBackdropColor then
      b:SetBackdropColor(unpack(on and THEME.tabOn or THEME.tabOff))
      b:SetBackdropBorderColor(unpack(on and ACCENT or THEME.border))
    end
    b.text:SetTextColor(unpack(on and THEME.title or THEME.muted))
  end
end

function Guide.SetMode(mode)
  ns.db.guideMode = mode
  ns.db.guideBuild = nil -- the best fit changes with the mode
  Guide.Refresh()
end

function Guide.SetPage(page)
  ns.db.guidePage = page
  if Guide.frame and Guide.frame.bar then Guide.frame.bar:SetValue(0) end -- a new page starts at the top
  Guide.Refresh()
end

function Guide.SetBuild(key)
  ns.db.guideBuild = key
  Guide.Refresh()
end

function Guide.Refresh()
  local f = Guide.frame
  if not (f and f:IsShown()) then return end
  Guide.mode, Guide.page = Guide.Mode(), Guide.Page() -- read by tests
  paintTabs(f.modes, Guide.mode)
  paintTabs(f.pages, Guide.page)
  local sections, specOrWhy, _, path, talents = Guide.Build()
  Guide.sections, Guide.path, Guide.talents = sections, path, talents -- read by tests
  hideAll(f)
  local level = UnitLevel and UnitLevel("player")
  local specName = sections and (specOrWhy:gsub("^%l", string.upper)) or nil
  -- (Short: the tabs on both sides of the band say which page this is.)
  f.subtitle:SetText(specName and ("%s%s"):format(specName, level and ("  -  level " .. level) or "") or "")

  local y, nh, nl, nlane, nc, nw = 0, 0, 0, 0, 0, 0

  local function addHeader(text)
    nh = nh + 1
    local h = header(f, nh)
    y = y - (nh > 1 and 20 or 4)
    h.text:ClearAllPoints()
    h.text:SetPoint("TOPLEFT", f.content, "TOPLEFT", 2, y)
    h.text:SetText(text)
    h.text:Show()
    y = y - 22
    h.rule:ClearAllPoints()
    h.rule:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    h.rule:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, y)
    h.rule:Show()
    y = y - 10
  end

  local function addCard(text, spell, id)
    nl = nl + 1
    local c = card(f, nl)
    local hasIcon = spell or id
    c.text:ClearAllPoints()
    local left = 4 + PAD -- past the accent edge
    c.text:SetPoint("TOPLEFT", c.card, "TOPLEFT", hasIcon and (left + ROW_ICON + PAD) or left, -PAD)
    c.text:SetWidth(INNER - (hasIcon and (left + ROW_ICON + 2 * PAD) or (left + PAD)))
    c.text:SetText(text)
    if hasIcon then
      c.icon:SetTexture(ns.Display.Texture(spell, id))
      c.icon:ClearAllPoints()
      c.icon:SetPoint("TOPLEFT", c.card, "TOPLEFT", left, -(PAD - 2))
      c.icon:Show()
    else
      c.icon:Hide()
    end
    local height = math.max(stringHeight(c.text, SIZE.body) + 2 * PAD, hasIcon and (ROW_ICON + 2 * PAD - 4) or 0)
    c.card:ClearAllPoints()
    c.card:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
    c.card:SetSize(INNER, height)
    c.card:Show()
    y = y - height - GAP
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
    local rowHeight = PATH_ICON + 24
    local top = y
    local x, rowTop = LABEL_WIDTH, y - PAD
    addWord(l.label, LABEL_WIDTH - 16, 4 + PAD, rowTop - 9, THEME.title)
    for i, st in ipairs(l.steps) do
      if i > 1 then
        if x + 16 + CELL > INNER - 6 then x, rowTop = LABEL_WIDTH, rowTop - rowHeight end
        addWord(">", 12, x + 3, rowTop - 9, THEME.muted)
        x = x + 16
      end
      if st.text then
        local width = #st.text * 7 + 8
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
    y = top - height - GAP
  end

  if not sections then
    addCard(specOrWhy)
  elseif Guide.page == "talents" then
    -- One running position: the page's own drawing and these helpers share it.
    y = Guide.DrawTalents(f, talents, y, function(text, at) y = at; addHeader(text); return y end,
      function(text, at, spell, id) y = at; addCard(text, spell, id); return y end)
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

-- Talents page ----------------------------------------------------------------------
-- The build picker, your tree with the build laid over it, then the plan.
local NODE, NODE_GAP, TREE_HEAD = 36, 50, 30
local BUILD_BUTTON = 48
local TREE_NAMES = { "Assassination", "Combat", "Subtlety" }
local STATUS = { -- edge color: the build's talents, and the rest
  build = ACCENT,
  none = THEME.nodeEdge,
}

local function buildButton(f, i)
  return pooled(f.builds, i, function()
    local b = CreateFrame("Button", nil, f.content, "BackdropTemplate")
    flat(b, THEME.card)
    b.name = font(b:CreateFontString(nil, "OVERLAY", "GameFontNormal"), SIZE.body)
    b.name:SetPoint("TOP", 0, -9)
    b.tag = font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.small - 1)
    b.tag:SetPoint("TOP", b.name, "BOTTOM", 0, -4)
    b.tag:SetTextColor(unpack(THEME.muted))
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    return b
  end)
end

local function node(f, i)
  return pooled(f.nodes, i, function()
    local n = CreateFrame("Button", nil, f.content, "BackdropTemplate")
    if n.SetFrameLevel and f.content.GetFrameLevel then n:SetFrameLevel((tonumber(f.content:GetFrameLevel()) or 1) + 2) end
    n:SetSize(NODE + 2, NODE + 2)
    backdrop(n, WHITE, WHITE, 1, 0)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(NODE, NODE)
    n.icon:SetPoint("CENTER")
    n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- A faint accent glow around the build's talents.
    n.glow = n:CreateTexture(nil, "OVERLAY")
    n.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if n.glow.SetBlendMode then n.glow:SetBlendMode("ADD") end
    n.glow:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.35)
    n.glow:SetPoint("CENTER")
    n.glow:SetSize(NODE * 1.75, NODE * 1.75)
    -- The rank in a small dark badge on the corner, like the game's talent window.
    n.badge = CreateFrame("Frame", nil, n, "BackdropTemplate")
    n.badge:SetSize(28, 15)
    n.badge:SetPoint("CENTER", n, "BOTTOMRIGHT", -3, 1)
    flat(n.badge, { 0.03, 0.025, 0.02, 0.95 }, THEME.nodeEdge)
    if n.badge.SetFrameLevel and n.GetFrameLevel then n.badge:SetFrameLevel((tonumber(n:GetFrameLevel()) or 1) + 2) end
    n.rank = font(n.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), SIZE.small - 1)
    n.rank:SetPoint("CENTER", 0, 0)
    n:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) else GameTooltip:SetText(self.name or "") end
      if self.line then GameTooltip:AddLine(self.line, THEME.accent[1], THEME.accent[2], THEME.accent[3], true) end
      GameTooltip:Show()
    end)
    n:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return n
  end)
end

-- A tree's box: a slightly darker panel behind its heading and talents.
local function treeBox(f, i)
  return pooled(f.treeBoxes, i, function()
    local b = panel(f.content, THEME.tree)
    -- Under the talents, whichever was made first.
    if b.SetFrameLevel and f.content.GetFrameLevel then b:SetFrameLevel(tonumber(f.content:GetFrameLevel()) or 1) end
    return b
  end)
end

local function treeHead(f, i)
  return pooled(f.trees, i, function()
    local h = font(f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal"), SIZE.body)
    h:SetJustifyH("CENTER")
    h:SetTextColor(unpack(THEME.title))
    return h
  end)
end

-- Draws the talents page from `y` down; returns the y below it. addHeader and
-- addCard draw at the y they're given and return the y below what they drew.
function Guide.DrawTalents(f, tg, y, addHeader, addCard)
  if not tg then return addCard("No talent builds for your class yet.", y) end
  local rotation = ns.Rotations[select(2, UnitClass("player"))]

  -- Build picker: the three builds, the best fit marked, the shown one lit.
  y = addHeader("Pick a build", y)
  -- The builds that fit the Solo/Group tab and your weapons, best fit first.
  local width = (INNER - GAP * (#tg.picks - 1)) / #tg.picks
  for i, pick in ipairs(tg.picks) do
    local key = pick[1]
    local b = buildButton(f, i)
    local build = rotation.BUILDS[key]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", (i - 1) * (width + GAP), y)
    b:SetSize(width, BUILD_BUTTON)
    b.name:SetText(build.name)
    b.tag:SetText(key == tg.picks[1][1] and "best fit for you" or "")
    local on = key == tg.key
    if b.SetBackdropColor then
      b:SetBackdropColor(unpack(on and THEME.tabOn or THEME.card))
      b:SetBackdropBorderColor(unpack(on and ACCENT or THEME.cardEdge))
    end
    b.name:SetTextColor(unpack(on and THEME.title or THEME.text))
    b:SetScript("OnClick", function() Guide.SetBuild(key) end)
    b:Show()
  end
  y = y - BUILD_BUTTON - GAP

  -- The tree, from the game's own layout (Traits positions). Without
  -- positions (no Traits tree) only the plan below is shown.
  local list = tg.list or {}
  local minX, maxX, minY = {}, {}, nil
  for _, e in ipairs(list) do
    if e.posX and e.posY and e.tab then
      minX[e.tab] = math.min(minX[e.tab] or e.posX, e.posX)
      maxX[e.tab] = math.max(maxX[e.tab] or e.posX, e.posX)
      minY = math.min(minY or e.posY, e.posY)
    end
  end
  if minY then
    -- The whole build, drawn as if its points were spent: its talents lit with
    -- the build's ranks, the rest greyed at 0. Your own points are in the plan below.
    y = addHeader(tg.build.name .. ": the talent tree", y)
    local target = rotation.BuildRanks(tg.build, #tg.build.order)
    local colWidth = (INNER - 2 * GAP) / 3
    local function colOf(e) return math.floor((e.posX - minX[e.tab]) / 600 + 0.5) end
    local want = {}
    for _, e in ipairs(list) do want[e.tab] = (want[e.tab] or 0) + (target[e.name] or 0) end
    for tab = 1, 3 do
      local h = treeHead(f, tab)
      h:ClearAllPoints()
      h:SetPoint("TOP", f.content, "TOPLEFT", (tab - 1) * (colWidth + GAP) + colWidth / 2, y - PAD)
      h:SetText(("%s  %d"):format(TREE_NAMES[tab], want[tab] or 0))
      h:SetTextColor(unpack((want[tab] or 0) > 0 and THEME.title or THEME.muted))
      h:Show()
    end
    local top, rows, n = y - PAD - TREE_HEAD, 0, 0
    for _, e in ipairs(list) do
      if e.posX and e.posY and e.tab then
        local col = colOf(e)
        local row = math.floor((e.posY - minY) / 600 + 0.5)
        rows = math.max(rows, row + 1)
        n = n + 1
        local nd = node(f, n)
        local goal, max = target[e.name] or 0, e.max or target[e.name] or 0
        local lit = goal > 0
        local status = lit and "build" or "none"
        nd.status, nd.name, nd.spellID = status, e.name, e.spellID
        nd.line = lit and ("In this build: %d of %d ranks"):format(goal, max) or "Not in this build"
        nd.icon:SetTexture(ns.Display.Texture(e.name, e.spellID))
        nd.icon:SetDesaturated(not lit)
        nd.icon:SetAlpha(lit and 1 or 0.45)
        if nd.SetBackdropBorderColor then
          nd:SetBackdropColor(0.02, 0.02, 0.02, 1)
          nd:SetBackdropBorderColor(unpack(STATUS[status]))
        end
        if lit then nd.glow:Show() else nd.glow:Hide() end
        -- The build's ranks / the talent's max, like the game's talent window.
        nd.rank:SetText(max > 0 and ("%d/%d"):format(goal, max) or "")
        nd.rank:SetTextColor(unpack(lit and THEME.title or THEME.muted))
        if nd.badge.SetBackdropBorderColor then nd.badge:SetBackdropBorderColor(unpack(STATUS[status])) end
        nd.lit = lit
        -- Each tree centered in its box.
        local span = math.floor((maxX[e.tab] - minX[e.tab]) / 600 + 0.5) * NODE_GAP + NODE + 2
        local x0 = (e.tab - 1) * (colWidth + GAP) + (colWidth - span) / 2
        nd:ClearAllPoints()
        nd:SetPoint("TOPLEFT", f.content, "TOPLEFT", x0 + col * NODE_GAP, top - row * NODE_GAP)
        nd:Show()
      end
    end
    local bottom = top - rows * NODE_GAP + (NODE_GAP - NODE) - PAD
    for tab = 1, 3 do
      local box = treeBox(f, tab)
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", f.content, "TOPLEFT", (tab - 1) * (colWidth + GAP), y)
      box:SetSize(colWidth, y - bottom)
      box:Show()
    end
    y = bottom - GAP
    y = addCard("The tree as this build fills it by level 30: its talents lit with their ranks, the rest "
      .. "greyed. Your own points and what to take next are in the plan below. Hover a talent for its text.", y)
  end

  y = addHeader("The plan", y)
  for _, r in ipairs(tg.rows) do y = addCard(r.text, y, r.spell, r.id) end
  return y
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
  "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
  ns:On(event, function()
    if not (InCombatLockdown and InCombatLockdown()) then Guide.Refresh() end
  end)
end
