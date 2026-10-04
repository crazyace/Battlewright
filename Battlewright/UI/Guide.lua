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

  -- Solo / Group: two small tabs at the left of the title band.
  f.modes = {}
  for i, mode in ipairs({ "solo", "group" }) do
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(64, 22)
    b:SetPoint("TOPLEFT", 22 + (i - 1) * 70, -21)
    backdrop(b, WHITE, EDGE, 10, 3)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(mode == "solo" and "Solo" or "Group")
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    b:SetScript("OnClick", function() Guide.SetMode(mode) end)
    b.mode = mode
    f.modes[mode] = b
  end

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

  -- Rotation / Talents: page tabs at the right of the title band.
  f.pages = {}
  for i, key in ipairs({ "rotation", "talents" }) do
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(76, 22)
    b:SetPoint("TOPRIGHT", -40 - (2 - i) * 82, -21)
    backdrop(b, WHITE, EDGE, 10, 3)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(key == "rotation" and "Rotation" or "Talents")
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    b:SetScript("OnClick", function() Guide.SetPage(key) end)
    f.pages[key] = b
  end

  f.headers = {} -- section titles: { text, rule }
  f.builds = {}  -- talents page: build buttons
  f.nodes = {}   -- talents page: tree nodes
  f.trees = {}   -- talents page: a heading per tree
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
  for _, b in ipairs(f.builds) do b:Hide() end
  for _, n in ipairs(f.nodes) do n:Hide() end
  for _, h in ipairs(f.trees) do h:Hide() end
end

local function paintTabs(tabs, current)
  for key, b in pairs(tabs) do
    local on = key == current
    if b.SetBackdropColor then
      if on then
        b:SetBackdropColor(0.30, 0.22, 0.10, 0.98)
        b:SetBackdropBorderColor(THEME.title[1], THEME.title[2], THEME.title[3], 1)
      else
        b:SetBackdropColor(0.12, 0.115, 0.105, 0.98)
        b:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
      end
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
  f.subtitle:SetText(specName and ("%s  -  %s%s"):format(Guide.page == "talents" and "Your talents" or "Your rotation",
    specName, level and ("  -  level " .. level) or "") or "")

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
local BUILD_ORDER = { "mutilate", "backstab", "combat" }
local NODE, NODE_GAP, TREE_HEAD = 30, 42, 20
local TREE_NAMES = { "Assassination", "Combat", "Subtlety" }
local STATUS = { -- border color and tooltip line
  done = { { 0.25, 0.85, 0.30 }, "In this build: done" },
  todo = { { 1.00, 0.80, 0.34 }, "In this build: still to take" },
  next = { { 1.00, 1.00, 0.55 }, "Your next point" },
  off = { { 0.85, 0.25, 0.20 }, "Not in this build" },
  none = { { 0.35, 0.32, 0.28 }, nil },
}

local function buildButton(f, i)
  return pooled(f.builds, i, function()
    local b = CreateFrame("Button", nil, f.content, "BackdropTemplate")
    backdrop(b, WHITE, EDGE, 10, 3)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetPoint("TOP", 0, -6)
    b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.tag:SetPoint("TOP", b.name, "BOTTOM", 0, -2)
    b.tag:SetTextColor(unpack(THEME.muted))
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    return b
  end)
end

local function node(f, i)
  return pooled(f.nodes, i, function()
    local n = CreateFrame("Button", nil, f.content, "BackdropTemplate")
    n:SetSize(NODE + 6, NODE + 6)
    backdrop(n, WHITE, EDGE, 10, 2)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(NODE, NODE)
    n.icon:SetPoint("CENTER")
    n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    n.rank = n:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    n.rank:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", 3, -3)
    n:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) else GameTooltip:SetText(self.name or "") end
      if self.line then GameTooltip:AddLine(self.line, 1, 0.82, 0.3, true) end
      GameTooltip:Show()
    end)
    n:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return n
  end)
end

local function treeHead(f, i)
  return pooled(f.trees, i, function()
    local h = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
  local width = (INNER - 8) / #BUILD_ORDER
  for i, key in ipairs(BUILD_ORDER) do
    local b = buildButton(f, i)
    local build = rotation.BUILDS[key]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", (i - 1) * (width + 4), y)
    b:SetSize(width, 38)
    b.name:SetText(build.name)
    b.tag:SetText(key == tg.picks[1][1] and "best fit for you" or "")
    local on = key == tg.key
    if b.SetBackdropColor then
      b:SetBackdropColor(unpack(on and { 0.30, 0.22, 0.10, 0.98 } or THEME.card))
      b:SetBackdropBorderColor(unpack(on and { THEME.title[1], THEME.title[2], THEME.title[3], 1 } or THEME.border))
    end
    b.name:SetTextColor(unpack(on and THEME.title or THEME.text))
    b:SetScript("OnClick", function() Guide.SetBuild(key) end)
    b:Show()
  end
  y = y - 38 - 4

  -- The tree, from the game's own layout (Traits positions). Without
  -- positions (no Traits tree) only the plan below is shown.
  local list = tg.list or {}
  local minX, minY = {}, nil
  for _, e in ipairs(list) do
    if e.posX and e.posY and e.tab then
      minX[e.tab] = math.min(minX[e.tab] or e.posX, e.posX)
      minY = math.min(minY or e.posY, e.posY)
    end
  end
  if minY then
    y = addHeader(tg.build.name .. " on your tree", y)
    local target = rotation.BuildRanks(tg.build, 21)
    local nextName = tg.plan and tg.plan.next and tg.plan.next.name
    local colWidth = INNER / 3
    local have, want = {}, {}
    for _, e in ipairs(list) do
      have[e.tab] = (have[e.tab] or 0) + (e.rank or 0)
      want[e.tab] = (want[e.tab] or 0) + (target[e.name] or 0)
    end
    for tab = 1, 3 do
      local h = treeHead(f, tab)
      h:ClearAllPoints()
      h:SetPoint("TOP", f.content, "TOPLEFT", (tab - 0.5) * colWidth, y)
      h:SetText((want[tab] or 0) > 0 and ("%s  %d / %d"):format(TREE_NAMES[tab], have[tab] or 0, want[tab])
        or ("%s  %d"):format(TREE_NAMES[tab], have[tab] or 0))
      h:Show()
    end
    local top, rows, n = y - TREE_HEAD, 0, 0
    for _, e in ipairs(list) do
      if e.posX and e.posY and e.tab then
        local col = math.floor((e.posX - minX[e.tab]) / 600 + 0.5)
        local row = math.floor((e.posY - minY) / 600 + 0.5)
        rows = math.max(rows, row + 1)
        n = n + 1
        local nd = node(f, n)
        local rank, goal = e.rank or 0, target[e.name] or 0
        local status = (e.name == nextName and "next") or (goal > 0 and (rank >= goal and "done" or "todo"))
          or (rank > 0 and "off") or "none"
        nd.status, nd.name, nd.spellID, nd.line = status, e.name, e.spellID, STATUS[status][2]
        nd.icon:SetTexture(ns.Display.Texture(e.name, e.spellID))
        nd.icon:SetDesaturated(status == "none")
        nd.icon:SetAlpha(status == "none" and 0.45 or 1)
        if nd.SetBackdropBorderColor then
          local c = STATUS[status][1]
          nd:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
          nd:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        nd.rank:SetText(goal > 0 and ("%d/%d"):format(rank, goal) or (rank > 0 and tostring(rank) or ""))
        local x0 = (e.tab - 1) * colWidth + (colWidth - 4 * NODE_GAP) / 2
        nd:ClearAllPoints()
        nd:SetPoint("TOPLEFT", f.content, "TOPLEFT", x0 + col * NODE_GAP, top - row * NODE_GAP)
        nd:Show()
      end
    end
    y = top - rows * NODE_GAP - 2
    y = addCard("Green: done.  Gold: still to take.  Bright: your next point.  Red: not in this build.  "
      .. "Numbers: your rank / the build's. Hover a talent for its text.", y)
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
