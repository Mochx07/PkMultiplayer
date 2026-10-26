-- src/coop/CoopBattleInviteModal.lua
-- Retro 2D Game Boy modal displayed when receiving a Co-op battle invitation.
-- Fits strictly within 160x144 (20x18 tiles), 100% English.

local Font = require("src.coop.CoopI18n").font()
local Sound = require("src.core.Sound")
local Theme = require("src.ui.Theme")

local CoopBattleInviteModal = {}
CoopBattleInviteModal.__index = CoopBattleInviteModal
CoopBattleInviteModal.isOpaque = false

function CoopBattleInviteModal.new(game, partnerName, trainerName, onAccept, onDecline)
  local self = setmetatable({
    game = game,
    partnerName = string.upper(partnerName or "PARTNER"),
    trainerName = string.upper(trainerName or "TRAINER"),
    onAccept = onAccept,
    onDecline = onDecline,
    index = 1, -- 1: JOIN CO-OP, 2: DECLINE
    tx = 1,
    ty = 4,
    tw = 18,
    th = 9,
    timer = 0,
  }, CoopBattleInviteModal)

  -- Play noticeable Game Boy alert sound so Player 2 knows an invite arrived
  pcall(function()
    Sound.play(game and game.data, "Get_Key_Item")
  end)

  return self
end

CoopBattleInviteModal.isCoopInvite = true

function CoopBattleInviteModal:close()
  if self.game and self.game.stack then
    local top = type(self.game.stack.top) == "function" and self.game.stack:top() or self.game.stack.top
    if top == self then self.game.stack:pop() end
  end
end

function CoopBattleInviteModal:update(dt)
  self.timer = self.timer + (dt or 0.016)
  -- unanswered invites decline themselves just before the inviter gives up
  if self.timeout and self.timer >= self.timeout then
    self:close()
    if self.onDecline then self.onDecline() end
    return
  end
  if self.timer < 0.3 then return end

  local input = self.game and self.game.input
  if not input then return end

  if input:wasPressed("up") then
    self.index = self.index == 1 and 2 or 1
    pcall(Sound.play, self.game.data, "Press_AB")
  elseif input:wasPressed("down") then
    self.index = self.index == 2 and 1 or 2
    pcall(Sound.play, self.game.data, "Press_AB")
  elseif input:wasPressed("a") then
    pcall(Sound.play, self.game.data, "Press_AB")
    if self.game and self.game.stack then
      local top = type(self.game.stack.top) == "function" and self.game.stack:top() or self.game.stack.top
      if top == self then self.game.stack:pop() end
    end
    if self.index == 1 then
      if self.onAccept then self.onAccept() end
    else
      if self.onDecline then self.onDecline() end
    end
  elseif input:wasPressed("b") then
    pcall(Sound.play, self.game.data, "Press_AB")
    if self.game and self.game.stack then
      local top = type(self.game.stack.top) == "function" and self.game.stack:top() or self.game.stack.top
      if top == self then self.game.stack:pop() end
    end
    if self.onDecline then self.onDecline() end
  end
end

-- 16 text columns inside the 18-tile box (x 16..144)
function CoopBattleInviteModal:draw()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(self.tx, self.ty, self.tw, self.th)

  love.graphics.setColor(0, 0, 0, 1)
  local x = (self.tx + 1) * 8
  local y = (self.ty + 1) * 8
  local pLabel = self.partnerName
  if #pLabel > 16 then pLabel = pLabel:sub(1, 16) end
  local tLabel = self.trainerName
  if #tLabel > 13 then tLabel = tLabel:sub(1, 13) end
  local lines = self.lines or { pLabel, "WANTS TO TEAM UP", "VS " .. tLabel }
  for i = 1, 3 do
    Font.draw(require("src.coop.CoopI18n").fit(lines[i] or "", 16), x, y + (i - 1) * 8)
  end

  local row1Y, row2Y = y + 32, y + 40
  Font.drawCode(Theme.cursor or 0xEC, x, self.index == 1 and row1Y or row2Y)
  Font.draw("JOIN", x + 8, row1Y)
  Font.draw("DECLINE", x + 8, row2Y)
  if self.timeout then
    local left = math.max(0, math.ceil(self.timeout - self.timer))
    Font.draw(string.format("%2d", left), x + 112, row1Y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopBattleInviteModal
