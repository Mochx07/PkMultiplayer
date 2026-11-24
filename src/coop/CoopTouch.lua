-- Touch routing for the mod's Game Boy screens. All rectangles use UI pixels.
local T = {}
local function cm() return require("src.coop.CoopManager") end
local function i18n() return require("src.coop.CoopI18n") end

function T.toGame(game, x, y)
  local r = game and game.renderer
  local p = r and r.uiPresentation or require("src.render.Renderer").uiPresentation
  if not p or not p.scaleX or p.scaleX <= 0 or not p.scaleY or p.scaleY <= 0 then return nil end
  local gx, gy = (x - p.x) / p.scaleX, (y - p.y) / p.scaleY
  if gx < 0 or gy < 0 or gx >= 160 or gy >= 144 then return nil end
  return gx, gy
end

function T.hit(rect, x, y)
  return x ~= nil and y ~= nil and x >= rect.x and x < rect.x + rect.w
    and y >= rect.y and y < rect.y + rect.h
end

-- Run the screen's existing semantic action once, without leaving a held
-- virtual button or a queued press that could reach the next screen.
function T.action(s, button)
  local game, real = s.game, s.game.input
  game.input = setmetatable({ wasPressed = function(_, b) return b == button end,
    isDown = function() return false end }, { __index = real })
  local ok, err = pcall(s.update, s, 0)
  game.input = real
  if not ok then error(err) end
end

local function add(out, id, x, y, w, h, run, label, raw)
  out[#out + 1] = { id = id, x = x, y = y, w = w, h = h, run = run, label = label, raw = raw }
end
local function button(out, s, id, x, y, w, h, key, label)
  add(out, id, x, y, w, h, function() T.action(s, key) end, label)
end
local function back(out, s, y)
  local label = s.touchKind == "lobby" and s.stage == "confirm" and s.quitAsk and "QUIT" or "BACK"
  button(out, s, "back", 104, y or 128, 48, 12, "b", label)
end

-- Draw text literally without Font.localize (which translates single-letter
-- Win/Loss keys "W" -> "V" and "L" -> "D" in Spanish) or CoopI18n.t.
local function drawLiteral(text, x, y)
  local raw = require("src.render.Font")
  if type(text) ~= "string" or text == "" then return 0 end
  if raw.encode and raw.drawCode and raw.advanceOf then
    local pen = x
    for _, code in ipairs(raw.encode(text)) do
      raw.drawCode(code, pen, y)
      pen = pen + raw.advanceOf(code)
    end
    return pen - x
  end
  return raw.draw(text, x, y)
end
T.drawLiteral = drawLiteral

local function literalWidth(text)
  local raw = require("src.render.Font")
  if type(text) ~= "string" or text == "" then return 0 end
  if raw.encode and raw.advanceOf then
    local w = 0
    for _, code in ipairs(raw.encode(text)) do
      w = w + raw.advanceOf(code)
    end
    return w
  end
  return raw.width(text)
end

local function drawCursor(g, x, y)
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x + 1, y + 7, 6, 1)
end

function T.isPhone()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

function T.exitTouch(game)
  if not game or T.isPhone() or os.getenv("POKEPORT_TOUCH") == "1" then return end
  if not game.coopTouchUsed then return end
  game.coopTouchUsed = false
  T.reset(game)
  local cmObj = cm()
  local overlay = cmObj and cmObj.chatOverlay
  if overlay then
    overlay.touchActive = false
    overlay.touchGesture = nil
  end
  local stack = game.stack and game.stack.states
  if type(stack) == "table" then
    for _, st in ipairs(stack) do
      if type(st) == "table" then
        st.touchActive = false
        st.touchGesture = nil
      end
    end
  end
end

function T.keyboard(s)
  if not (s.game.coopTouchUsed or T.isPhone()) then return false end
  return s.touchKind == "chat" or s.stage == "codeEntry"
    or (s.touchKind == "lobby" and s.stage == "name" and s.nameEdit ~= nil)
end

local KEYS = { "1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM.,?" }
T.KEYS = KEYS
local function keyboard(out, s)
  for row, chars in ipairs(KEYS) do
    for col = 1, #chars do
      local ch = chars:sub(col, col)
      add(out, "key:" .. ch, 5 + (col - 1) * 15, 62 + (row - 1) * 13, 15, 13, function()
        s.swallowOpenKey = false
        s:onTextInput(ch)
      end, ch, true)
    end
  end
  add(out, "erase", 5, 114, 45, 13, function()
    if s.touchKind == "chat" then s:onKeyPressed("backspace")
    elseif s.stage == "name" then s:nameKey("erase")
    else s.code = (s.code or ""):sub(1, -2) end
  end, "DEL")
  add(out, "space", 50, 114, 55, 13, function() s:onTextInput(" ") end, "SPACE")
  add(out, "ok", 105, 114, 50, 13, function()
    if s.touchKind == "chat" then s:onKeyPressed("return")
    elseif s.stage == "name" then s:confirmName()
    else s:submitCode() end
  end, s.touchKind == "chat" and "SEND" or "OK")
  add(out, "back", 104, 128, 48, 12, function() T.cancel(s) end, "BACK")
end

function T.cancel(s)
  if s.touchKind == "chat" then return s:cancel() end
  if s.touchKind == "lobby" and s.stage == "name" and s.nameEdit then
    s.nameEdit = nil
    if s.name == "" then s:leave() s.game.stack:pop() end
    return
  end
  -- A keeper decision cannot be abandoned: cancelling means a fair coin.
  if s.coopKeepMenu then
    s.index = 3
    return T.action(s, "a")
  end
  return T.action(s, "b")
end

local function menuRows(s)
  return cm().isConnected() and s:connectedRows(s.game.overworld) or s:offlineRows()
end

function T.targets(s)
  local out, kind = {}, s.touchKind
  if T.keyboard(s) then keyboard(out, s) return out end
  if kind == "menu" then
    local stage = s.stage
    if stage == "main" or stage == "joinPick" then
      local join = stage == "joinPick"
      local rows = join and s:joinRows() or menuRows(s)
      local field = join and "pickIndex" or "index"
      local visible = join and 6 or 9
      local pitch = join and 10 or (#rows > 8 and 9 or (#rows > 6 and 10 or 12))
      local first = join and (s.pickScroll or 1) or (s.scroll or 1)
      local selected = s[field] or 1
      first = math.max(1, math.min(first, selected))
      if selected > first + visible - 1 then first = selected - visible + 1 end
      if join then s.pickScroll = first else s.scroll = first end
      for n = first, math.min(#rows, first + visible - 1) do
        local y = (join and 66 or 48) + (n - first) * pitch
        add(out, "row:" .. n, 8, y,
          144, math.min(pitch, 128 - y), function() s[field] = n T.action(s, "a") end)
      end
      back(out, s)
    elseif stage == "hosting" then
      button(out, s, "addresses", 8, 24, 144, 24, "select")
      button(out, s, "more", 8, 110, 144, 12, "select", "NEXT IP")
      back(out, s)
    elseif stage == "addrEntry" or stage == "portEntry" then
      local port = stage == "portEntry"
      local count, pos = port and 5 or 12, port and "portPos" or "addrPos"
      for n = 1, count do
        local x = port and (48 + (n - 1) * 12) or (16 + (n - 1) * 9 + math.floor((n - 1) / 3) * 6)
        add(out, "digit:" .. n, x, 48, port and 12 or 9, 20, function() s[pos] = n end)
      end
      button(out, s, "up", 8, 72, 64, 16, "up", "UP")
      button(out, s, "down", 88, 72, 64, 16, "down", "DOWN")
      button(out, s, "ok", 8, 128, 64, 12, "a", "OK")
      back(out, s)
    else back(out, s) end
  elseif kind == "lobby" then
    local stage = s.stage
    if stage == "name" then
      add(out, "edit", 8, 40, 144, 64, function() s:editName() end)
      button(out, s, "ok", 8, 116, 64, 12, "a", "OK")
    elseif stage == "role" then
      for n = 1, 2 do
        add(out, "role:" .. n, 8, 44 + (n - 1) * 16, 144, 16,
          function() s.roleCursor = n T.action(s, "a") end)
      end
    elseif stage == "ipEntry" then
      for n = 1, 12 do
        add(out, "digit:" .. n, 16 + (n - 1) * 9 + math.floor((n - 1) / 3) * 6,
          44, 9, 20, function() s.addrPos = n end)
      end
      button(out, s, "up", 8, 70, 64, 16, "up", "UP")
      button(out, s, "down", 88, 70, 64, 16, "down", "DOWN")
      button(out, s, "code", 8, 90, 144, 16, "select", "TYPE A CODE")
      button(out, s, "ok", 8, 116, 64, 12, "a", "OK")
    elseif stage == "connecting" then
      if cm().isHost then button(out, s, "addresses", 8, 44, 144, 40, "select") end
    elseif stage == "confirm" then
      button(out, s, "ready", 8, 76, 144, 16, "a")
      if s.timeSyncAsked then button(out, s, "clock", 8, 56, 144, 16, "select") end
      button(out, s, "ok", 8, 116, 80, 12, "a", "READY!")
    end
    back(out, s, 128)
  elseif kind == "team" then
    local n = math.min(6, #s.party)
    for index = 1, n do
      add(out, "mon:" .. index, 8, 32 + (index - 1) * 10, 144, 10,
        function() s.cursor = index s:toggleSelect(index) end)
    end
    add(out, "confirm", 8, 34 + n * 10, 144, 12, function() s:confirm() end)
    back(out, s)
  elseif kind == "invite" then
    local x, y = (s.tx + 1) * 8, (s.ty + 1) * 8
    for n = 1, 2 do
      add(out, "answer:" .. n, x, y + 32 + (n - 1) * 16, 128, 14, function()
        s.index = n
        if n == 2 then T.cancel(s) elseif s.armed then T.action(s, "a") end
      end)
    end
    local backY = math.min(132, (s.ty + (s.th or 11)) * 8 + 4)
    back(out, s, backY)
  elseif kind == "emotes" then
    local list = require("src.coop.CoopEmotes").LIST
    local x0 = math.floor((160 - (#list - 1) * 20) / 2)
    for n = 1, #list do
      add(out, "emote:" .. n, x0 + (n - 1) * 20 - 10, 6, 20, 24, function()
        s.index = n T.action(s, "a")
      end)
    end
    back(out, s, 56)
  elseif kind == "list" then
    local visible = math.min(s.maxVisible or #s.items, #s.items)
    local innerTop = (s.ty + 1) * 8
    local innerBot = math.min(144, (s.ty + s.th - 1) * 8)
    for row = 1, visible do
      local n = (s.scroll or 0) + row
      local textY = (s.ty + s.th - 2 - (visible - row) * s.rowStep) * 8
      local pad = s.rowStep > 1 and 2 or 0
      local top = math.max(innerTop, textY - pad)
      local bot = math.min(innerBot, top + (s.rowStep > 1 and 12 or 8))
      if row < visible then
        local nextY = (s.ty + s.th - 2 - (visible - (row + 1)) * s.rowStep) * 8
        bot = math.min(bot, nextY - pad)
      end
      add(out, "row:" .. n, (s.tx + 1) * 8, top,
        (s.tw - 2) * 8, math.max(1, bot - top),
        function() s.index = n T.action(s, "a") end)
    end
    -- The BACK strip is outside the menu and never covers its last row.
    if (s.ty + s.th) * 8 <= 128 then back(out, s) end
  elseif kind == "text" then
    button(out, s, "ok", 8, 104, 88, 32, "a")
    back(out, s)
  elseif kind == "aim" then
    button(out, s, "throw", 8, 100, 144, 32, "a")
  elseif kind == "roulette" then
    return out
  elseif kind == "wait" then
    if s.compact then
      back(out, s, (s.lines and s.lines[2]) and 42 or 34)
    else
      back(out, s)
    end
  elseif kind == "link" then
    if s.stage == "battleOptions" then
      button(out, s, "down", 8, 56, 64, 16, "down", "DOWN")
      button(out, s, "up", 88, 56, 64, 16, "up", "UP")
    elseif s.stage == "modeSelect" then
      for n = 1, 2 do
        add(out, "mode:" .. n, 8, 48 + (n - 1) * 16, 144, 16,
          function() s.index = n T.action(s, "a") end)
      end
    end
    button(out, s, "ok", 8, 116, 80, 12, "a", "OK")
    back(out, s)
  elseif kind == "match" then
    button(out, s, "ok", 8, 116, 80, 12, "a", "OK")
    back(out, s)
  elseif kind == "dex" then
    button(out, s, "swap", 8, 36, 144, 12, "select")
    local lists = s:lists()
    for row = 0, 8 do
      local n = (s.top or 1) + row
      if lists and lists[s.tab][n] then
        add(out, "row:" .. n, 8, 52 + row * 8, 144, 8, function() s.cursor = n end)
      end
    end
    back(out, s)
  else back(out, s) end
  return out
end

function T.scroll(s, delta)
  local kind = s.touchKind
  if kind == "menu" and (s.stage == "main" or s.stage == "joinPick") then
    local join = s.stage == "joinPick"
    local rows = join and s:joinRows() or menuRows(s)
    local field = join and "pickIndex" or "index"
    s[field] = math.max(1, math.min(#rows, (s[field] or 1) + delta))
  elseif kind == "list" then
    s.index = math.max(1, math.min(#s.items, s.index + delta)) s:clampScroll()
  elseif kind == "dex" or kind == "souls" then
    for _ = 1, math.abs(delta) do T.action(s, delta > 0 and "down" or "up") end
  end
end

function T.pressed(s, id, px, py)
  local desktop = not T.isPhone() and os.getenv("POKEPORT_TOUCH") ~= "1"
  local x, y = T.toGame(s.game, px, py)
  local target
  for _, r in ipairs(T.targets(s)) do if T.hit(r, x, y) then target = r break end end
  -- On desktop while touch mode is inactive, ignore mouse clicks on empty
  -- background or letterbox so focusing the window neither turns on touch UI
  -- nor cancels the active screen.
  if desktop and id == "mouse" and not s.game.coopTouchUsed and not target then
    return false
  end
  s.game.coopTouchUsed = true
  s.touchActive = true
  if T.keyboard(s) and T.isPhone() and love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(false) end
  if s.touchGesture then return true end -- one owner; other fingers cannot confirm
  s.touchGesture = { id = id, x = px, y = py, lastY = py, target = target, dragged = false,
    stage = s.stage, page = s.page }
  return true
end
function T.moved(s, id, px, py)
  local g = s.touchGesture
  if not g or g.id ~= id then return true end
  local r = s.game.renderer or require("src.render.Renderer")
  local scale = r.uiPresentation and r.uiPresentation.scaleY or 1
  local scaleX = r.uiPresentation and r.uiPresentation.scaleX or 1
  if math.abs(py - g.y) > 6 * scale or math.abs(px - g.x) > 6 * scaleX then g.dragged = true end
  local steps = (g.lastY - py) / (10 * scale)
  local n = steps > 0 and math.floor(steps) or math.ceil(steps)
  if g.dragged and n ~= 0 then T.scroll(s, n) g.lastY = g.lastY - n * 10 * scale end
  return true
end
function T.released(s, id, px, py)
  local g = s.touchGesture
  if not g or g.id ~= id then return true end
  s.touchGesture = nil
  local top = cm().chatOverlay or s.game.stack:top()
  if top ~= s or g.stage ~= s.stage or g.page ~= s.page then return true end
  local r = s.game.renderer or require("src.render.Renderer")
  local p = r.uiPresentation or { scaleX = 1, scaleY = 1 }
  if g.dragged or math.abs(px - g.x) > 6 * p.scaleX or math.abs(py - g.y) > 6 * p.scaleY then return true end
  local x, y = T.toGame(s.game, px, py)
  if g.target then
    if T.hit(g.target, x, y) then g.target.run() end
  elseif s.touchKind ~= "roulette" then
    T.cancel(s)
  end
  return true
end

local function drawKeyboard(s)
  local F, g = i18n().font(), love.graphics
  g.setColor(1, 1, 1, 1) g.rectangle("fill", 0, 0, 160, 144)
  g.setColor(0, 0, 0, 1)
  F.draw(s.touchKind == "chat" and "CHAT" or (s.stage == "name" and "YOUR NAME:" or "HOST'S CODE:"), 8, 4)
  if s.touchKind == "chat" then
    local lines = cm().chatLines(18, 2)
    for n, line in ipairs(lines) do drawLiteral(i18n().fitGlyphs(i18n().truncate(line, 18)), 8, 8 + n * 8) end
    local rows = require("src.coop.CoopChatBox").layout(s.text) or {}
    drawLiteral(i18n().fitGlyphs(rows[#rows - 1] or ""), 8, 36)
    local last = i18n().fitGlyphs(rows[#rows] or "")
    local w = drawLiteral(last, 8, 46)
    if #last < 18 and 8 + w <= 148 then drawCursor(g, 8 + w, 46) end
  else
    local text = i18n().fitGlyphs(s.stage == "name" and s.nameEdit.buf or (s.code or ""))
    if #text <= 17 then
      local w = drawLiteral(text, 8, 24)
      drawCursor(g, 8 + w, 24)
    else
      local cut = 0
      for i = 1, math.min(18, #text) do if text:sub(i, i) == "-" then cut = i end end
      if cut == 0 then cut = 18 end
      drawLiteral(text:sub(1, cut), 8, 20)
      local w2 = drawLiteral(text:sub(cut + 1, cut + 18), 8, 30)
      if 8 + w2 <= 148 then drawCursor(g, 8 + w2, 30) end
    end
    if s.errorMsg then F.draw(s.errorMsg, 8, 44) end
  end
end

function T.draw(s)
  if not (s.game.coopTouchUsed or T.isPhone()) then return end
  if T.keyboard(s) then drawKeyboard(s) end
  local g, F = love.graphics, i18n().font()
  local function clear(x, y, w, h)
    g.setColor(1, 1, 1, 1) g.rectangle("fill", x, y, w, h)
  end
  if s.touchKind == "menu" then
    clear(8, 128, 144, 12)
    if s.stage == "portEntry" or s.stage == "addrEntry" then
      clear(8, 72, 144, 52)
      g.setColor(0, 0, 0, 1) F.draw("TAP A DIGIT", 8, 98)
      if s.errorMsg then F.draw(s.errorMsg, 8, 110) end
    end
  elseif s.touchKind == "lobby" and not T.keyboard(s) then
    clear(8, 116, 144, 24)
    if s.stage == "ipEntry" then clear(8, 68, 144, 40) end
  elseif s.touchKind == "team" or s.touchKind == "dex" then clear(8, 128, 144, 12)
  end
  local lh = (F.raw and F.raw.glyphHeight and F.raw.glyphHeight()) or 8
  for _, r in ipairs(T.targets(s)) do
    -- Black one-pixel outlines remain readable on both Game Boy palettes.
    g.setColor(0, 0, 0, 0.35)
    g.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    if r.label then
      g.setColor(1, 1, 1, 1) g.rectangle("fill", r.x + 1, r.y + 1, r.w - 2, r.h - 2)
      g.setColor(0, 0, 0, 1)
      local lw = r.raw and literalWidth(r.label) or F.width(r.label)
      local tx = r.x + math.max(2, math.floor((r.w - lw) / 2))
      local ty = r.y + math.max(1, math.floor((r.h - lh) / 2))
      if r.raw then drawLiteral(r.label, tx, ty) else F.draw(r.label, tx, ty) end
    end
  end
  g.setColor(1, 1, 1, 1)
end

function T.bind(class, kind)
  class.touchKind = kind
  class.holdsUIAnchors = true
  class.touchpressed, class.touchmoved, class.touchreleased = T.pressed, T.moved, T.released
  local draw = class.draw
  class.draw = function(s, ...)
    if not T.keyboard(s) then draw(s, ...) end
    T.draw(s)
  end
end
function T.attach(s, kind)
  -- Instance methods for engine menus; engine code stays in its own checkout.
  if not s.touchKind then T.bind(s, kind) end
  return s
end

function T.route(game, method, id, x, y)
  game.coopTouchOwners = game.coopTouchOwners or {}
  local owners = game.coopTouchOwners
  local s = owners[id]
  if method == "touchpressed" then
    s = cm().chatOverlay or game.stack:top()
    if not (s and s.touchKind) then return false end
    if s:touchpressed(id, x, y) == false then return false end
    owners[id] = s
    return true
  elseif s == false then
    if method == "touchreleased" then owners[id] = nil end
    return true
  end
  if not s then return false end
  s[method](s, id, x, y)
  if method == "touchreleased" then owners[id] = nil end
  return true
end

-- Android can cancel contacts while the app is suspended without releases.
function T.reset(game)
  for _, s in pairs(game.coopTouchOwners or {}) do
    if s then s.touchGesture = nil end
  end
  game.coopTouchOwners = nil
end

function T.drawOpener() end
return T
