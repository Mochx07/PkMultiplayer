-- src/coop/CoopWaitModal.lua
-- Retro 2D Game Boy modal displayed while waiting for partner to respond to a Co-op battle invite.
-- Fits strictly within 160x144 (20x18 tiles), 100% English.
--
-- It never pumps the network itself (CoopManager.update does, every frame)
-- and never pops itself: the answer, B, or the timeout all go through
-- onCancel/CoopManager, which removes it from wherever it sits.

local Font = require("src.coop.CoopI18n").font()
local Sound = require("src.core.Sound")

local CoopWaitModal = {}
CoopWaitModal.__index = CoopWaitModal
CoopWaitModal.isOpaque = false
CoopWaitModal.isCoopWaitModal = true

-- opts.lines: the two lines to show instead of "WAITING FOR / NAME...";
-- opts.compact: a short box along the top, so the shared dialogue the
-- partner is reading stays visible in the box at the bottom.
function CoopWaitModal.new(game, partnerName, onCancel, timeout, opts)
  local self = setmetatable({
    game = game,
    partnerName = string.upper(partnerName or "PARTNER"),
    onCancel = onCancel,
    timeout = timeout or 22,
    timer = 0,
    done = false,
    lines = opts and opts.lines,
    compact = opts and opts.compact,
    cancelLabel = (opts and opts.cancelLabel) or "B: BATTLE SOLO",
  }, CoopWaitModal)
  return self
end

function CoopWaitModal:finish(reason)
  if self.done then return end
  self.done = true
  if self.onCancel then self.onCancel(reason) end
  -- in case nobody removed us (no pending invite left), do it here
  local stack = self.game and self.game.stack
  if stack and stack.states then
    for i = #stack.states, 1, -1 do
      if stack.states[i] == self then
        if i == #stack.states then stack:pop() else table.remove(stack.states, i) end
        break
      end
    end
  end
end

function CoopWaitModal:update(dt)
  self.timer = self.timer + (dt or 0.016)
  if self.timer >= self.timeout then
    self:finish("timeout")
    return
  end
  local input = self.game and self.game.input
  if input and input:wasPressed("b") and self.timer >= 0.5 then
    pcall(Sound.play, self.game and self.game.data, "Menu")
    self:finish("user")
  end
end

function CoopWaitModal:draw()
  if self.compact then
    -- what B does is always on show, under the lines
    local left = math.max(0, math.ceil(self.timeout - self.timer))
    local l1 = (self.lines and self.lines[1]) or ("WAITING " .. self.partnerName)
    local l2 = self.lines and self.lines[2]
    local fit = require("src.coop.CoopI18n").fit
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, 20, l2 and 5 or 4)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(fit(l1, 15), 8, 8)
    Font.draw(string.format("%3d", left), 128, 8)
    if l2 then Font.draw(fit(l2, 18), 8, 16) end
    Font.draw(fit(self.cancelLabel, 18), 8, l2 and 24 or 16)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  local tx, ty = 1, 5
  Font.drawBox(tx, ty, 18, 7)

  love.graphics.setColor(0, 0, 0, 1)
  local name = require("src.coop.CoopI18n").truncate(self.partnerName, 12)
  local fit = require("src.coop.CoopI18n").fit
  Font.draw(fit((self.lines and self.lines[1]) or "WAITING FOR", 16), (tx + 1) * 8, (ty + 1) * 8)
  Font.draw(fit((self.lines and self.lines[2]) or (name .. "..."), 16), (tx + 1) * 8, (ty + 2) * 8)

  local dots = string.rep(".", math.floor(self.timer * 2) % 4)
  local left = math.max(0, math.ceil(self.timeout - self.timer))
  Font.draw(string.format("TIME %2d%s", left, dots), (tx + 1) * 8, (ty + 3) * 8)
  Font.draw(fit(self.cancelLabel, 16), (tx + 1) * 8, (ty + 5) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopWaitModal
