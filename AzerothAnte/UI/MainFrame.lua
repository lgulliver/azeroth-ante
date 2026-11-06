local _, ns = ...

local Theme = ns.UI.Theme
local Main = {}

local W, H = Theme.width, Theme.height
local DEFAULT_POINT = "CENTER"

local function saveWindow(frame)
  if not AzerothAnteDB then return end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  AzerothAnteDB.window = {
    point = point, relativePoint = relativePoint, x = x, y = y, width = frame:GetWidth(), height = frame:GetHeight(),
  }
end

local function restoreWindow(frame)
  local saved = AzerothAnteDB and AzerothAnteDB.window
  frame:ClearAllPoints()
  if saved and saved.width and saved.height then
    frame:SetSize(math.max(720, saved.width), math.max(450, saved.height))
    local point = saved.point or DEFAULT_POINT
    frame:SetPoint(point, UIParent, saved.relativePoint or point, saved.x or 0, saved.y or 0)
  else
    frame:SetSize(W, H)
    frame:SetPoint(DEFAULT_POINT)
  end
end

local function region(parent, name, point, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint(point, parent, point, x, y)
  Main[name] = f
  return f
end

local function makeButton(parent, label, x, w, variant)
  local b = Theme.NewButton(parent, label, w, 28, variant)
  b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, Theme.margin)
  return b
end

function Main.Create()
  if Main.frame then return Main.frame end

  local frame = CreateFrame("Frame", "AzerothAnteFrame", UIParent)
  Main.frame = frame
  Theme.Frame(frame) -- leather fill, soft shadow, and a gold border that sits above the content
  frame:SetFrameStrata("HIGH") -- above world nameplates; every child inherits it, and GameTooltip (TOOLTIP) stays above
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(720, 450)
  restoreWindow(frame)

  -- Fixed-size design canvas, scaled and centred inside the outer frame.
  local content = CreateFrame("Frame", nil, frame)
  content:SetSize(W, H)
  content:SetPoint("CENTER")
  content:SetClipsChildren(true) -- discards and slide-aways never draw outside the window
  Main.content = content
  frame:SetScript("OnSizeChanged", function(self, w, h)
    content:SetScale(math.min(w / W, h / H))
    content:ClearAllPoints()
    content:SetPoint("CENTER")
    Theme.RefreshEdges() -- a design unit is a different number of pixels now
  end)
  content:SetScale(math.min(frame:GetWidth() / W, frame:GetHeight() / H))

  -- Title area (drag handle) and close button.
  local title = CreateFrame("Frame", nil, content)
  title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  title:SetPoint("TOPRIGHT", content, "TOPRIGHT", -30, 0)
  title:SetHeight(Theme.titleHeight)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() frame:StartMoving() end)
  title:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    saveWindow(frame)
  end)
  Theme.TitleBar(title, content)
  local titleText = title:CreateFontString(nil, "OVERLAY", Theme.fonts.title)
  titleText:SetPoint("LEFT", title, "LEFT", Theme.margin + 4, 0)
  titleText:SetText("Azeroth Ante")
  Theme.Value(titleText, true)
  Main.title = title

  local close = Theme.NewButton(content, "x", 22, 22)
  close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -5)
  close:SetScript("OnClick", function() frame:Hide() end)
  Main.close = close

  -- Abandon Run in the title bar: shown whenever a run exists (see Main.Render).
  local abandon = Theme.NewButton(content, "Abandon Run", 104, 22, "danger")
  abandon:SetPoint("RIGHT", close, "LEFT", -6, 0)
  ns.UI.Screens.AttachAbandon(abandon, "Abandon Run", "Click to confirm")
  abandon:HookScript("OnEnter", function(self)
    if ns.UI.Screens.Blocked() then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(ns.UI.Screens.BUSY_REASON, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  abandon:HookScript("OnLeave", function() GameTooltip:Hide() end)
  abandon:Hide()
  Main.abandon = abandon
  frame:SetScript("OnHide", function()
    GameTooltip:Hide()
    ns.UI.ConsumableRow.Close()
  end)

  -- Layout A, in design units.
  local m = Theme.margin
  local top = -Theme.titleHeight - m
  local sideW = math.floor(W * Theme.sidebarFraction)
  local rightX = sideW + 2 * m
  local rightW = W - rightX - m
  local bodyH = H - Theme.titleHeight - 2 * m

  local sidebar = region(content, "sidebar", "TOPLEFT", m, top, sideW, bodyH)
  ns.UI.Sidebar.Build(sidebar) -- sets the panel in (Theme.Inset)

  local consumableW = 1
  Main.rowsWidth = rightW
  local trinketRow = region(content, "trinketRow", "TOPLEFT", rightX, top, rightW - consumableW - m, 48)
  ns.UI.TrinketRow.Build(trinketRow)
  local consumableRow = region(content, "consumableRow", "TOPRIGHT", -m, top, consumableW, ns.UI.ConsumableRow.HEIGHT)
  ns.UI.ConsumableRow.Build(consumableRow)

  local handH, btnH = 168, 28
  local playH = bodyH - 48 - handH - btnH - 3 * m
  -- The table the hand is played on: one set-in panel behind the play and hand areas.
  local stage = region(content, "stage", "TOPLEFT", rightX, top - 48 - m, rightW, playH + m + handH)
  Theme.Inset(stage)
  region(content, "playArea", "TOPLEFT", rightX, top - 48 - m, rightW, playH)
  region(content, "handArea", "TOPLEFT", rightX, top - 48 - m - playH - m, rightW, handH)

  local buttons = region(content, "buttons", "BOTTOMLEFT", rightX, m, rightW, btnH)
  buttons.play = makeButton(buttons, "Play", 0, 110, "primary")
  buttons.discard = makeButton(buttons, "Discard", 120, 110)
  buttons.sortRank = makeButton(buttons, "Sort Rank", 240, 110)
  buttons.sortSuit = makeButton(buttons, "Sort Suit", 360, 110)
  for _, b in pairs({ buttons.play, buttons.discard, buttons.sortRank, buttons.sortSuit }) do
    b:ClearAllPoints()
  end
  buttons.play:SetPoint("LEFT", buttons, "LEFT", 0, 0)
  buttons.discard:SetPoint("LEFT", buttons.play, "RIGHT", 10, 0)
  buttons.sortRank:SetPoint("LEFT", buttons.discard, "RIGHT", 10, 0)
  buttons.sortSuit:SetPoint("LEFT", buttons.sortRank, "RIGHT", 10, 0)
  ns.UI.HandView.Build(Main)

  -- Resize grip (outer frame, outside the scaled canvas).
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    saveWindow(frame)
  end)
  Main.grip = grip

  Theme.RefreshEdges()
  tinsert(UISpecialFrames, "AzerothAnteFrame")
  frame:Hide()
  return frame
end

function Main.Show()
  Main.Create()
  if Main.frame:IsShown() then return end -- already open: never re-render mid-hand
  Main.frame:Show()
  Main.Render(Main.run, true)
  ns.UI.HandView.Update(Main.run, true)
  ns.UI.Toast.ShowUnseen() -- achievements earned while the window was closed
end

function Main.Hide()
  if Main.frame then Main.frame:Hide() end
end

function Main.Toggle()
  Main.Create()
  if Main.frame:IsShown() then Main.Hide() else Main.Show() end
end

-- Updates every view from run state; run and run.phase may be nil (empty view).
-- A no-op while a hand is resolving (flight or tally) unless force is set, so
-- stray events cannot jump the sidebar or screens ahead. Only the hand's own
-- completion paths (and window show / run change) force a render.
function Main.Render(run, force)
  if not Main.frame then return end
  if not force then
    local HandView, Tally = ns.UI.HandView, ns.UI.Tally
    if (HandView and HandView.IsBusy()) or (Tally and Tally.IsBusy()) then return end
  end
  ns.UI.Sidebar.Update(run, 0, 0)
  -- The deck-select screen has no items to show.
  local selecting = not (run and (run.phase == "blind" or run.phase == "play" or run.phase == "shop"
    or run.phase == "won" or run.phase == "lost"))
  if Main.abandon then Main.abandon:SetShown(not selecting) end
  Main.trinketRow:SetShown(not selecting)
  Main.consumableRow:SetShown(not selecting)
  ns.UI.ConsumableRow.Update(run) -- first: it sets the width the trinket row may use
  ns.UI.TrinketRow.Update(run)
  local Screens = ns.UI.Screens
  if not Screens then return end
  Screens.Track(run)
  local phase = run and run.phase
  if phase == "blind" or phase == "play" or phase == "shop" or phase == "won" or phase == "lost" then
    Screens.Show(phase, run)
  else
    Screens.Show("newrun", run)
  end
  -- An open pack (also after a reload) overlays the shop; it closes itself when none is open.
  if ns.UI.PackView then ns.UI.PackView.Show(run) end
end

function Main.SetRun(run)
  Main.run = run
  Main.Render(run, true)
  ns.UI.HandView.Update(run, Main.frame ~= nil and Main.frame:IsShown())
end

ns.UI.Main = Main
