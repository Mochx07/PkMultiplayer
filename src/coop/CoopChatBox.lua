-- src/coop/CoopChatBox.lua
-- Retro 2D Game Boy chat input modal.
-- Fits strictly within 160x144 (20x18 tiles).
--
-- The upper half is the conversation -- the last few messages and, live, what
-- the partner is typing right now -- and the bottom two rows are yours.
-- Every change you make is reported to CoopManager.sendChatLive, so the
-- partner reads along letter by letter instead of waiting for ENTER.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

-- four input rows: 17 letters after the arrow, then 18 a row, broken at the
-- spaces.  Letters, not bytes: an accented letter is two bytes, and counting
-- bytes both cut the message short and split a letter in two at the end of
-- a row.  A letter is taken only while the message still fits the rows.
local MAX_CHARS = 70
local ROW_FIRST, ROW_NEXT, INPUT_ROWS = 17, 18, 4
local LOG_ROWS = 4

local function letters(t) return select(2, t:gsub("[^\128-\191]", "")) end
-- the first n letters of t, and the rest
local function headLetters(t, n)
  local count = 0
  for pos in t:gmatch("()[^\128-\191]") do
    count = count + 1
    if count > n then return t:sub(1, pos - 1), t:sub(pos) end
  end
  return t, ""
end

-- the message laid out on the input rows, broken at spaces (a word longer
-- than a row is split); nil when it needs more rows than there are
local function layout(text)
  local rows, row = {}, ""
  local function width() return (#rows == 0) and ROW_FIRST or ROW_NEXT end
  local function push() rows[#rows + 1] = row row = "" end
  local pos = 1
  while pos <= #text do
    local word, spaces = text:match("^(%S*)(%s*)", pos)
    pos = pos + #word + #spaces
    while letters(word) > width() do
      if row ~= "" then push() end
      local head, rest = headLetters(word, width())
      row = head
      push()
      word = rest
    end
    if word ~= "" or spaces ~= "" then
      local candidate = row .. word
      if letters(candidate) > width() then
        push()
        candidate = word
      end
      row = candidate
      -- the spaces stay on the row while they fit (a space typed at the end
      -- of a row starts the next one)
      for _ = 1, #spaces do
        if letters(row) < width() then row = row .. " " else push() end
      end
    end
    if #rows > INPUT_ROWS then return nil end
  end
  rows[#rows + 1] = row
  if #rows > INPUT_ROWS then return nil end
  return rows
end

local CoopChatBox = {}
CoopChatBox.__index = CoopChatBox
CoopChatBox.isChatBox = true
CoopChatBox.isOpaque = false
CoopChatBox.layout = layout

-- A phone types on the on-screen keyboard, which only shows while text
-- input is armed; a desktop has text input on all the time, and other tools
-- rely on it staying on, so only a phone has it lowered again.
local function isPhone()
  local name = love and love.system and love.system.getOS and love.system.getOS()
  return name == "iOS" or name == "Android"
end
CoopChatBox.isPhone = isPhone

local function setKeyboard(on)
  pcall(function()
    if love.keyboard and love.keyboard.setTextInput then
      love.keyboard.setTextInput(on)
    end
  end)
end

local function manager()
  local ok, CoopManager = pcall(require, "src.coop.CoopManager")
  return ok and CoopManager or nil
end

local function popUtf8Char(str)
  local len = #str
  if len == 0 then return "" end
  local b = str:byte(len)
  local drop = 1
  while len - drop > 0 and (b >= 0x80 and b <= 0xBF) do
    drop = drop + 1
    b = str:byte(len - drop + 1)
  end
  return str:sub(1, len - drop)
end

-- opts.overlay: drawn inside a co-op double instead of pushed on top of it
-- (CoopManager.openChat).  THE BATTLE GOES ON UNDER THE CHAT: reported from
-- play, opening the chat in a battle froze it until the chat was closed --
-- the state stack updates only its top.  As an overlay the battle stays the
-- top state and keeps running, reading a mute pad (lib/Hooks.lua), while the
-- keys and the typed text come here.
function CoopChatBox.new(game, opts)
  local self = setmetatable({
    game = game,
    overlay = opts and opts.overlay or nil,
    text = "",
    cursorTimer = 0,
    tx = 0,
    ty = 7,
    tw = 20,
    th = 11,
    -- the T that opened the box also arrives as text input right after;
    -- it must not become the first letter of the message
    swallowOpenKey = true,
  }, CoopChatBox)

  -- raises the on-screen keyboard on a phone
  setKeyboard(true)

  return self
end

-- the box going away without a message: the partner's typing line goes too
function CoopChatBox:cancel()
  local CM = manager()
  if CM and CM.sendChatLive then CM.sendChatLive(nil, true) end
  self:close()
end

function CoopChatBox:changed()
  local CM = manager()
  if CM and CM.sendChatLive then CM.sendChatLive(self.text) end
end

function CoopChatBox:close()
  if isPhone() then setKeyboard(false) end
  if self.overlay then
    local CM = manager()
    if CM and CM.chatOverlay == self then CM.chatOverlay = nil end
    return
  end
  if self.game and self.game.stack then
    local top = type(self.game.stack.top) == "function" and self.game.stack:top() or self.game.stack.top
    if top == self then self.game.stack:pop() end
  end
end

function CoopChatBox:onTextInput(text)
  if not text or text == "" then return end
  if self.swallowOpenKey then
    self.swallowOpenKey = false
    if (text == "t" or text == "T") and self.text == "" then return end
  end
  -- Filter control characters
  local clean = text:gsub("[%c]", "")
  if clean == "" then return end

  -- letter by letter, while the message still fits the rows
  local added = false
  for ch in clean:gmatch("[^\128-\191][\128-\191]*") do
    local candidate = self.text .. ch
    if letters(candidate) > MAX_CHARS or not layout(candidate) then break end
    self.text = candidate
    added = true
  end
  if added then self:changed() end
end

function CoopChatBox:onKeyPressed(key)
  if key == "escape" then
    pcall(Sound.play, self.game.data, "Menu")
    self:cancel()
  elseif key == "backspace" then
    if #self.text > 0 then
      self.text = popUtf8Char(self.text)
      self:changed()
    end
  elseif key == "return" or key == "kpenter" then
    local trimmed = self.text:match("^%s*(.-)%s*$") or ""
    local CM = manager()
    if #trimmed > 0 and CM and CM.sendChat then
      CM.sendChat(trimmed)
      -- the box stays open for the reply: a conversation, not one line
      self.text = ""
      self:changed()
      pcall(Sound.play, self.game.data, "Press_AB")
    else
      self:cancel()
    end
  end
end

-- A mute pad: what a battle under the open chat reads (lib/Hooks.lua), so
-- the letters you type are not taken as A, B or a direction.
function CoopChatBox.mutedInput(real)
  return setmetatable({}, { __index = function(_, k)
    local v = real[k]
    if type(v) == "function" and type(k) == "string"
       and (k:find("^was") or k:find("^is") or k:find("Pressed$") or k:find("Held") or k:find("Down$")) then
      return function() return false end
    end
    return v
  end })
end

function CoopChatBox:update(dt)
  self.cursorTimer = self.cursorTimer + (dt or 0.016)
  -- one frame is enough for the opening key's text event to have come and gone
  if self.cursorTimer > 0.1 then self.swallowOpenKey = false end

  -- Fallback check for input if not delivered via keypressed
  local input = self.game and self.game.input
  if input then
    if input:wasPressed("b") and #self.text == 0 then
      self:cancel()
    elseif input:wasPressed("a") then
      -- a phone keyboard swiped away comes back on A
      setKeyboard(true)
    end
  end
end

function CoopChatBox:draw()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(self.tx, self.ty, self.tw, self.th)

  love.graphics.setColor(0, 0, 0, 1)
  local top = (self.ty + 1) * 8
  Font.draw(isPhone() and "CHAT  A:KEYBOARD" or "CHAT ENTER/ESC", 8, top)

  -- the conversation, newest at the bottom
  local CM = manager()
  local lines = (CM and CM.chatLines) and CM.chatLines(18, LOG_ROWS) or {}
  for i, l in ipairs(lines) do
    Font.draw(l, 8, top + i * 8)
  end

  -- your line
  local cursor = (math.floor(self.cursorTimer * 3) % 2 == 0) and "_" or " "
  local text = self.text
  local y = top + (LOG_ROWS + 1) * 8
  -- the cartridge's own arrow; the Gen 2 font has no ">"
  Font.drawCode(0xED, 8, y)
  local rows = layout(text) or { text }
  for i, part in ipairs(rows) do
    local x = (i == 1) and 16 or 8
    local width = (i == 1) and ROW_FIRST or ROW_NEXT
    if i == #rows then
      if letters(part) < width then
        part = part .. cursor
      elseif i < INPUT_ROWS then
        -- a full row: the cursor waits at the start of the next one
        Font.draw(cursor, 8, y + i * 8)
      end
    end
    Font.draw(part, x, y + (i - 1) * 8)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return CoopChatBox
