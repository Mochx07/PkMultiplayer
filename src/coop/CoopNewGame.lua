-- src/coop/CoopNewGame.lua
-- Dedicated lobby and mutual confirmation screen for "NEW CO-OP GAME".
-- Strictly fits 160x144 (20x18 tiles) in English with authentic Game Boy font and borders.

local Font = require("src.coop.CoopI18n").font()
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local CoopManager = require("src.coop.CoopManager")
local CoopNet = require("src.coop.CoopNet")
local CoopLog = require("src.coop.CoopLog")

local CURSOR = 0xED
local DOWN_ARROW = 0xEE

local function ipDigits(ip)
  local digits = {}
  local a, b, c, d = (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  local octets = {
    tonumber(a) or 10,
    tonumber(b) or 147,
    tonumber(c) or 17,
    tonumber(d) or 1,
  }
  for _, o in ipairs(octets) do
    o = math.min(255, math.max(0, o))
    table.insert(digits, math.floor(o / 100))
    table.insert(digits, math.floor(o / 10) % 10)
    table.insert(digits, o % 10)
  end
  return digits
end

local function clearGB()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
end

local function getLocalPlayerName(game)
  local save = game and game.save
  local pName = save and save.player and save.player.name
  if pName and pName ~= "" and pName ~= "TRAINER" then
    return pName
  end
  return CoopManager.isHost and "HOST" or "GUEST"
end

local CoopNewGame = {}
CoopNewGame.__index = CoopNewGame
CoopNewGame.isOpaque = true

function CoopNewGame.new(game, onStartGame, mode)
  local defaultIP = CoopNet.zeroTierIP() or CoopNet.lanIP()
  local self = setmetatable({
    game = game,
    onStartGame = onStartGame,
    onStartNewGame = onStartGame, -- backward compatibility
    mode = mode or "new",
    stage = "role", -- "role", "ipEntry", "connecting", "confirm"
    roleCursor = 1,
    addr = ipDigits(defaultIP),
    addrPos = 1,
    ip = defaultIP,
    port = CoopNet.DEFAULT_PORT or 7777,
    localReady = false,
    partnerReady = false,
    started = false,
    errorMsg = nil,
    timer = 0,
    timeSyncAsked = false,
    timeSynced = false,
    tzDiff = 0,
    localTimeStr = nil,
    partnerTimeStr = nil,
  }, CoopNewGame)
  -- The lobby never touches the transport itself: CoopManager.update (run
  -- every frame by Game:update) pumps it and offers each message here first.
  CoopManager.lobby = self
  return self
end

-- THE HOST'S INVITE CODE, typed or pasted instead of the twelve digits
-- (CoopNet.inviteCode).  While one is typed, the keyboard is the code's.
function CoopNewGame:onTextInput(text)
  if self.stage ~= "codeEntry" or type(text) ~= "string" then return end
  local clean = text:upper():gsub("[^%w%-]", "")
  if #self.code + #clean <= 12 then self.code = self.code .. clean end
end

function CoopNewGame:onKeyPressed(key)
  if self.stage ~= "codeEntry" then
    require("src.core.Input"):keypressed(key)
    return
  end
  local k = love and love.keyboard
  local ctrl = k and k.isDown and (k.isDown("lctrl") or k.isDown("rctrl") or k.isDown("lgui") or k.isDown("rgui"))
  if key == "backspace" then
    self.code = self.code:sub(1, -2)
  elseif key == "return" or key == "kpenter" then
    self:submitCode()
  elseif key == "escape" then
    self.stage = "ipEntry"
  elseif key == "v" and ctrl then
    local ok, clip = pcall(function() return love.system.getClipboardText() end)
    if ok and type(clip) == "string" then self.code = clip:upper():gsub("[^%w%-]", ""):sub(1, 12) end
  end
end

function CoopNewGame:submitCode()
  local ip, port = CoopNet.parseInviteCode(self.code)
  if not ip then
    self.errorMsg = "THAT CODE IS NOT RIGHT"
    return
  end
  self.ip, self.port, self.errorMsg = ip, port, nil
  if CoopManager.join(ip, port) then
    self.stage = "connecting"
  else
    self.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO CONNECT"
    self.stage = "ipEntry"
  end
end

function CoopNewGame:leave()
  if CoopManager.lobby == self then CoopManager.lobby = nil end
end

function CoopNewGame:exit()
  self:leave()
end

function CoopNewGame:resetToRole(err)
  self.partnerReady = false
  self.localReady = false
  self.timeSyncAsked = false
  self.errorMsg = err
  self.stage = "role"
end

-- Lobby-only messages are consumed; everything else (hello, positions...)
-- still reaches CoopManager's own handlers.
function CoopNewGame:onNetMessage(msg)
  if msg.type == "coop_newgame_ready" then
    self.partnerReady = true
    pcall(Sound.play, self.game.data, "Recovery")
    if self.stage == "confirm" and self.localReady then self:startGame() end
    return true
  elseif msg.type == "coop_newgame_cancel" then
    self.partnerReady = false
    if self.stage == "confirm" then self.errorMsg = "PARTNER NOT READY" end
    return true
  elseif msg.type == "coop_start_game" then
    CoopLog.sync("START_GAME", "Partner launched the game; following")
    if self.stage == "confirm" then self:startGame() end
    return true
  elseif msg.type == "coop_pos" then
    -- the partner is already walking around: drop straight in
    if self.stage == "confirm" and self.mode == "continue" then self:startGame() end
    return false
  elseif msg.type == "net_disconnect" then
    if self.stage ~= "role" and self.stage ~= "ipEntry" then
      local net = CoopManager.net
      self:resetToRole((net and net.error) or "DISCONNECTED")
    end
    return false
  end
  return false
end

function CoopNewGame:enterConfirm()
  self.stage = "confirm"
  -- partnerReady is kept: their READY can arrive in the same frame as the
  -- handshake that brings us here
  self.localReady = false
  self.errorMsg = nil
  pcall(Sound.play, self.game.data, "Menu")

  local localTz = (CoopManager.net and CoopManager.net.timezone) or CoopNet.detectTimezone()
  local partnerTz = CoopManager.partner.timezone
  -- Red / Blue / Yellow have no clock to share
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if okV and GameVersion.isGen1() then partnerTz = nil end
  if partnerTz then
    local diffSec = (partnerTz.offsetSec or 0) - (localTz.offsetSec or 0)
    if math.abs(diffSec) >= 1800 then
      self.tzDiff = diffSec
      self.timeSyncAsked = true
      -- each side reads its own time first: the guest's line used to put
      -- the host's clock under "H" and their own under "P2"
      self.localTimeStr, self.partnerTimeStr = localTz.timeStr or "12:00", partnerTz.timeStr or "12:00"
      -- default: everyone plays on the host's clock
      if CoopManager.isHost then CoopManager.chooseTimeMode("host") end
    end
  end

  if CoopManager.partner.inWorld and self.mode == "continue" then
    self:startGame()
  end
end

function CoopNewGame:update(dt)
  dt = dt or 0.016
  self.timer = self.timer + dt
  CoopManager.lobby = self
  self.timeSynced = CoopManager.timeMode == "host" or CoopManager.timeMode == "guest"

  if self.stage == "connecting" then
    local net = CoopManager.net
    if CoopManager.connected then
      self:enterConfirm()
      if self.started then return end
    elseif not net or net.closed then
      self:resetToRole((net and net.error) or "CONNECTION FAILED")
    end
  elseif self.stage == "confirm" and not CoopManager.isConnected() then
    local st = CoopManager.net and CoopManager.net.state
    if st ~= CoopNet.STATE.RECONNECTING then
      self:resetToRole((CoopManager.net and CoopManager.net.error) or "DISCONNECTED")
    end
  end

  local input = self.game.input
  if not input then return end

  if self.stage == "role" then
    if input:wasPressed("down") or input:wasPressed("up") then
      self.roleCursor = (self.roleCursor == 1) and 2 or 1
      pcall(Sound.play, self.game.data, "Menu")
    elseif input:wasPressed("a") then
      pcall(Sound.play, self.game.data, "Menu")
      self.errorMsg = nil
      if self.roleCursor == 1 then
        if CoopManager.host(self.port) then
          self.stage = "connecting"
        else
          self.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO HOST"
        end
      else
        self.stage = "ipEntry"
      end
    elseif input:wasPressed("b") then
      pcall(Sound.play, self.game.data, "Menu")
      self:leave()
      self.game.stack:pop()
    end

  elseif self.stage == "codeEntry" then
    if input:wasPressed("b") then
      self.stage = "ipEntry"
    elseif input:wasPressed("a") or input:wasPressed("start") then
      self:submitCode()
    end

  elseif self.stage == "ipEntry" then
    if input:wasPressed("b") then
      pcall(Sound.play, self.game.data, "Menu")
      self.stage = "role"
    elseif input:wasPressed("select") then
      pcall(Sound.play, self.game.data, "Menu")
      self.code, self.errorMsg = "", nil
      self.stage = "codeEntry"
    elseif input:wasPressed("up") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] + 1) % 10
      pcall(Sound.play, self.game.data, "Menu")
    elseif input:wasPressed("down") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] - 1 + 10) % 10
      pcall(Sound.play, self.game.data, "Menu")
    elseif input:wasPressed("left") then
      self.addrPos = math.max(1, self.addrPos - 1)
      pcall(Sound.play, self.game.data, "Menu")
    elseif input:wasPressed("right") then
      self.addrPos = math.min(12, self.addrPos + 1)
      pcall(Sound.play, self.game.data, "Menu")
    elseif input:wasPressed("a") or input:wasPressed("start") then
      pcall(Sound.play, self.game.data, "Menu")
      local octets = {}
      for i = 1, 4 do
        local base = (i - 1) * 3
        octets[i] = math.min(255, self.addr[base + 1] * 100
                                  + self.addr[base + 2] * 10
                                  + self.addr[base + 3])
      end
      self.ip = table.concat(octets, ".")
      if CoopManager.join(self.ip, self.port) then
        self.errorMsg = nil
        self.stage = "connecting"
      else
        self.errorMsg = (CoopManager.net and CoopManager.net.error) or "FAILED TO CONNECT"
      end
    end

  elseif self.stage == "connecting" then
    if input:wasPressed("b") then
      pcall(Sound.play, self.game.data, "Menu")
      CoopManager.disconnect()
      self:resetToRole(nil)
    end

  elseif self.stage == "confirm" then
    if input:wasPressed("select") and self.timeSyncAsked then
      pcall(Sound.play, self.game.data, "Menu")
      CoopManager.chooseTimeMode(self.timeSynced and "off" or "host")
    elseif input:wasPressed("a") then
      pcall(Sound.play, self.game.data, "Menu")
      self.localReady = not self.localReady
      if self.localReady then
        CoopManager.net:send({ type = "coop_newgame_ready" })
        if self.partnerReady then
          self:startGame()
        end
      else
        CoopManager.net:send({ type = "coop_newgame_cancel" })
      end
    elseif input:wasPressed("b") then
      pcall(Sound.play, self.game.data, "Menu")
      -- a link is not dropped by one stray B: the second one, within 3 s
      if not (self.quitAsk and self.timer - self.quitAsk <= 3) then
        self.quitAsk = self.timer
        return
      end
      self.quitAsk = nil
      CoopManager.net:send({ type = "coop_newgame_cancel" })
      CoopManager.disconnect()
      self:resetToRole(nil)
    end
    if self.quitAsk and self.timer - self.quitAsk > 3 then self.quitAsk = nil end
  end
end

function CoopNewGame:startGame()
  if self.started then return end
  self.started = true
  self:leave()

  local tag = (self.mode == "continue") and "CONTINUE_GAME" or "NEW_GAME"
  local desc = (self.mode == "continue") and "Continue Co-op Game" or "New Co-op Game"
  CoopLog.sync(tag, "Starting synchronized " .. desc)
  CoopManager.isLinkedSession = true

  if CoopManager.net and not CoopManager.net.closed then
    CoopManager.net:send({ type = "coop_start_game", mode = self.mode })
    CoopManager.net:flush()
  end

  local top = self.game.stack:top()
  if top == self then
    self.game.stack:pop()
  else
    CoopManager.removeState(self.game, self)
  end
  local startCb = self.onStartGame or self.onStartNewGame
  if startCb then
    startCb()
  end
  if self.game and self.game.save then
    self.game.save.coopLinked = true
    self.game.save.coopPartner = CoopManager.partner.name or "PARTNER"
    CoopManager.syncTrainerName(self.game)
  end
end

-- Every line here fits the 18 text columns inside a full-width box
-- (x 8..152); the old layout ran past the border and over the footer.
local function fit(text, n)
  -- translated, then cut to n letters (not bytes: an accent is two)
  return require("src.coop.CoopI18n").fit(text, n)
end

function CoopNewGame:draw()
  clearGB()

  Font.drawBox(0, 0, 20, 3)
  local title = (self.mode == "continue") and "CONTINUE CO-OP" or "NEW CO-OP GAME"
  local tW = Font.width and Font.width(title) or (#title * 8)
  Font.draw(title, math.max(8, math.floor((160 - tW) / 2)), 8)

  Font.drawBox(0, 3, 20, 11)
  Font.drawBox(0, 14, 20, 4)
  local footer

  if self.stage == "role" then
    Font.draw("SELECT ROLE:", 8, 32)
    Font.draw("HOST GAME", 24, 48)
    Font.draw("JOIN GAME", 24, 64)
    Font.drawCode(CURSOR, 12, (self.roleCursor == 1) and 48 or 64)
    Font.draw("HOST: SHARE IP", 8, 80)
    Font.draw("GUEST: IP OR CODE", 8, 96)
    footer = "A:SELECT  B:BACK"

  elseif self.stage == "ipEntry" then
    Font.draw(CoopNet.zeroTierIP() and "HOST ZEROTIER IP:" or "HOST IP:", 8, 32)
    for i = 1, 12 do
      local octet = math.floor((i - 1) / 3)
      local x = 16 + (i - 1) * 9 + octet * 6
      Font.draw(tostring(self.addr[i]), x, 48)
      if i == self.addrPos then
        Font.drawCode(DOWN_ARROW, x, 56)
      end
    end
    for octet = 1, 3 do
      Font.draw(".", 16 + octet * 33 - 6, 48)
    end
    Font.draw("PORT: " .. self.port, 8, 72)
    Font.draw("UP/DOWN: DIGIT", 8, 88)
    Font.draw("SELECT: A CODE", 8, 96)
    footer = "A:JOIN  B:BACK"

  elseif self.stage == "codeEntry" then
    local blink = math.floor(self.timer * 2) % 2 == 0
    Font.draw("HOST'S CODE:", 8, 32)
    Font.draw((self.code or "") .. (blink and "_" or ""), 16, 48)
    Font.draw("TYPE THE CODE,", 8, 72)
    Font.draw("CTRL+V PASTES IT.", 8, 80)
    footer = "ENTER:OK  ESC:BACK"

  elseif self.stage == "connecting" then
    local dots = string.rep(".", math.floor(self.timer * 2) % 4)
    if CoopManager.isHost then
      local zt = CoopNet.zeroTierIP()
      Font.draw("WAITING GUEST" .. dots, 8, 32)
      if zt then
        Font.draw("ZEROTIER IP:", 8, 48)
        Font.draw(fit(zt, 18), 8, 56)
        Font.draw("LAN IP:", 8, 72)
        Font.draw(fit(CoopNet.lanIP(), 18), 8, 80)
      else
        Font.draw("TELL YOUR GUEST:", 8, 48)
        Font.draw(fit(CoopNet.lanIP(), 18), 8, 64)
      end
      Font.draw("CODE: " .. tostring(CoopNet.inviteCode(zt or CoopNet.lanIP(), self.port) or "?"), 8, 96)
      Font.draw("PORT: " .. self.port, 8, 104)
    else
      Font.draw("CONNECTING" .. dots, 8, 32)
      Font.draw("TO:", 8, 48)
      Font.draw(fit(self.ip, 18), 8, 56)
      Font.draw("PORT: " .. self.port, 8, 72)
      Font.draw("PLEASE WAIT", 8, 96)
    end
    footer = "B:CANCEL"

  elseif self.stage == "confirm" then
    local pName = fit(CoopManager.partner.name or "PARTNER", 7)
    local myName = fit(getLocalPlayerName(self.game), 7)
    Font.draw("LINKED:", 8, 32)
    Font.draw(myName .. " & " .. pName, 8, 40)
    if self.timeSyncAsked then
      Font.draw(fit(string.format("YOU %s P2 %s", self.localTimeStr or "12:00", self.partnerTimeStr or "12:00"), 18), 8, 56)
      Font.draw(fit("SELECT: CLOCK " .. (self.timeSynced and "ONE" or "OWN"), 18), 8, 64)
    else
      Font.draw("SAVE LINKED TO", 8, 56)
      Font.draw("THIS PARTNER", 8, 64)
    end
    Font.draw("YOU: " .. (self.localReady and "READY!" or "PRESS A"), 8, 80)
    Font.draw("P2:  " .. (self.partnerReady and "READY!" or "WAITING"), 8, 96)
    footer = self.quitAsk and "B AGAIN: QUIT" or "A:READY  B:QUIT"
  end

  if footer then Font.draw(footer, 8, 120) end
  if self.errorMsg then
    -- the reason in full, and what to do about it
    require("src.coop.CoopMenu").drawError(self.errorMsg, self.port, 8, 128, 2)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopNewGame
