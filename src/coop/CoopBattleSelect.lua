-- src/coop/CoopBattleSelect.lua
-- Authentic Game Boy 3-Pokémon Selection Menu for Co-op Double Battles.
-- Fits strictly within 160x144 (20x18 tiles), 100% English.

local Font = require("src.coop.CoopI18n").font()
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local CoopBattleSelect = {}
CoopBattleSelect.__index = CoopBattleSelect
CoopBattleSelect.isOpaque = true
CoopBattleSelect.isCoopBattleSelect = true

function CoopBattleSelect.new(game, party, onComplete, onCancel)
  local self = setmetatable({
    game = game,
    party = party or {},
    onComplete = onComplete,
    onCancel = onCancel,
    cursor = 1,
    selected = {}, -- Array of indices into party [1..3]
    message = nil,
    messageTimer = 0,
  }, CoopBattleSelect)

  -- Auto-preselect up to 3 healthy Pokémon
  for i, mon in ipairs(self.party) do
    if mon and (mon.hp or 0) > 0 and not mon.isEgg then
      table.insert(self.selected, i)
      if #self.selected >= 3 then break end
    end
  end

  return self
end

function CoopBattleSelect:isSelected(idx)
  for order, pIdx in ipairs(self.selected) do
    if pIdx == idx then return order end
  end
  return nil
end

function CoopBattleSelect:toggleSelect(idx)
  local mon = self.party[idx]
  if not mon then return end
  if (mon.hp or 0) <= 0 then
    self.message = "POKéMON HAS NO HP!"
    self.messageTimer = 1.5
    pcall(Sound.play, self.game.data, "Collision")
    return
  end
  if mon.isEgg then
    self.message = "AN EGG CAN'T BATTLE!"
    self.messageTimer = 1.5
    pcall(Sound.play, self.game.data, "Collision")
    return
  end

  local existingOrder = self:isSelected(idx)
  if existingOrder then
    table.remove(self.selected, existingOrder)
    pcall(Sound.play, self.game.data, "Menu")
  else
    if #self.selected >= 3 then
      self.message = "CAN ONLY PICK 3!"
      self.messageTimer = 1.5
      pcall(Sound.play, self.game.data, "Collision")
      return
    end
    table.insert(self.selected, idx)
    pcall(Sound.play, self.game.data, "Menu")
  end
end

function CoopBattleSelect:confirm()
  if #self.selected == 0 then
    -- Fallback: auto-pick first healthy
    for i, mon in ipairs(self.party) do
      if mon and (mon.hp or 0) > 0 and not mon.isEgg then
        table.insert(self.selected, i)
        break
      end
    end
  end

  if #self.selected == 0 then
    self.message = "NO HEALTHY POKéMON!"
    self.messageTimer = 1.5
    pcall(Sound.play, self.game.data, "Collision")
    return
  end

  pcall(Sound.play, self.game.data, "Press_AB")
  local chosenMons = {}
  for _, idx in ipairs(self.selected) do
    table.insert(chosenMons, self.party[idx])
  end

  self.game.stack:pop()
  if self.onComplete then
    self.onComplete(chosenMons)
  end
end

function CoopBattleSelect:update(dt)
  dt = dt or 0.016
  if self.messageTimer > 0 then
    self.messageTimer = self.messageTimer - dt
    if self.messageTimer <= 0 then self.message = nil end
  end

  local input = self.game.input
  if not input then return end

  local partyCount = math.min(6, #self.party)
  local maxCursor = partyCount + 1 -- Extra row for [CONFIRM]

  if input:wasPressed("down") then
    self.cursor = self.cursor + 1
    if self.cursor > maxCursor then self.cursor = 1 end
    pcall(Sound.play, self.game.data, "Menu")
  elseif input:wasPressed("up") then
    self.cursor = self.cursor - 1
    if self.cursor < 1 then self.cursor = maxCursor end
    pcall(Sound.play, self.game.data, "Menu")
  elseif input:wasPressed("a") then
    if self.cursor == maxCursor then
      self:confirm()
    else
      self:toggleSelect(self.cursor)
    end
  elseif input:wasPressed("start") then
    self:confirm()
  elseif input:wasPressed("b") then
    pcall(Sound.play, self.game.data, "Menu")
    self.game.stack:pop()
    if self.onCancel then
      self.onCancel()
    end
  end
end

function CoopBattleSelect:draw()
  love.graphics.setColor(1, 1, 1, 1)

  -- Top Header Box (20 tiles wide, 3 tiles high)
  Font.drawBox(0, 0, 20, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("CHOOSE 3 POKéMON", 16, 8)

  -- Party List Box (20 tiles wide, 11 tiles high)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 3, 20, 11)

  local Theme = require("src.ui.Theme")
  local cursorCode = (Theme and Theme.cursor) or 0xED
  local partyCount = math.min(6, #self.party)
  for i = 1, partyCount do
    local mon = self.party[i]
    local y = 32 + (i - 1) * 12
    local isSelectedOrder = self:isSelected(i)
    local orderTag = isSelectedOrder and string.format("[%d]", isSelectedOrder) or "[ ]"

    -- Cursor indicator (authentic Game Boy ▶ arrow)
    if self.cursor == i then
      love.graphics.setColor(0, 0, 0, 1)
      Font.drawCode(cursorCode, 8, y)
    end

    -- Order slot tag
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(orderTag, 16, y)

    -- Mon Name
    local name = mon.nickname
    if not name or name == "" then
      local data = self.game and self.game.data
      local def = data and data.pokemon and (data.pokemon[mon.species] or (tonumber(mon.species) and data.pokemon[tonumber(mon.species)]))
      name = (def and def.name) or mon.name or tostring(mon.species or "POKéMON")
    end
    name = tostring(name):sub(1, 8)
    Font.draw(name, 36, y)

    -- Level & HP
    local lvl = string.format("L:%d", mon.level or 5)
    Font.draw(lvl, 102, y)

    local hpStr = string.format("%d/%d", mon.hp or 0, (mon.stats and mon.stats.hp) or mon.maxHp or 20)
    if (mon.hp or 0) <= 0 then
      love.graphics.setColor(0.6, 0.1, 0.1, 1)
      Font.draw("FNT", 126, y)
    else
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(hpStr, 126, y)
    end
  end

  -- Confirm button row
  local confirmY = 32 + partyCount * 12
  if self.cursor == (partyCount + 1) then
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(cursorCode, 8, confirmY)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("[CONFIRM TEAM]", 16, confirmY)

  -- Bottom Instruction / Status Box (20 tiles wide, 4 tiles high)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 14, 20, 4)
  love.graphics.setColor(0, 0, 0, 1)

  if self.message and self.messageTimer > 0 then
    Font.draw(self.message, 12, 122)
  else
    local countStr = string.format("SELECTED: %d/3", #self.selected)
    Font.draw(countStr, 10, 118)
    Font.draw("A:PICK  B:BACK", 10, 128)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return CoopBattleSelect
