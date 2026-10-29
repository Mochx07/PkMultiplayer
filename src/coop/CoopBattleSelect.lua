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
  -- EVERY FIELD INSIDE THE BOX.  Reported from play: things ran off the
  -- screen.  The 8x8 font gives 18 letters between the box's borders
  -- (x 8..152), and the row used to ask for more: "[1]" ran into the name,
  -- the level into the HP, the HP ("57/57") past the right edge, and with six
  -- Pokemon the confirm row sat on the box's bottom border.  Now: cursor,
  -- one character for the pick order, eight letters of name, then the level
  -- and the HP in the small font against the right border, rows 10 px apart.
  local MicroFont = require("src.render.MicroFont")
  local okI, I18n = pcall(require, "src.coop.CoopI18n")
  local RIGHT = 152
  local partyCount = math.min(6, #self.party)
  for i = 1, partyCount do
    local mon = self.party[i]
    local y = 32 + (i - 1) * 10
    local order = self:isSelected(i)

    -- Cursor indicator (authentic Game Boy arrow)
    if self.cursor == i then
      love.graphics.setColor(0, 0, 0, 1)
      Font.drawCode(cursorCode, 8, y)
    end

    love.graphics.setColor(0, 0, 0, 1)
    Font.raw.draw(order and tostring(order) or "-", 16, y)

    -- Mon Name
    local name = mon.nickname
    if not name or name == "" then
      local data = self.game and self.game.data
      local def = data and data.pokemon and (data.pokemon[mon.species] or (tonumber(mon.species) and data.pokemon[tonumber(mon.species)]))
      name = (def and def.name) or mon.name or tostring(mon.species or "POKéMON")
    end
    name = require("src.coop.CoopI18n").truncate(tostring(name), 8)
    Font.raw.draw(tostring(name), 26, y)

    -- the level in the small font too: eight letters of name, "L100" and
    -- "278/278" do not fit the 8x8 font side by side
    MicroFont.draw(string.format("L%d", mon.level or 5), 94, y + 2)

    local hpStr
    if (mon.hp or 0) <= 0 then
      love.graphics.setColor(0.6, 0.1, 0.1, 1)
      hpStr = "FNT"
    else
      hpStr = string.format("%d/%d", mon.hp or 0, (mon.stats and mon.stats.hp) or mon.maxHp or 20)
    end
    MicroFont.draw(hpStr, RIGHT - MicroFont.width(hpStr), y + 2)
  end

  -- Confirm button row
  local confirmY = 32 + partyCount * 10 + 2
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
    -- in the player's language first, then wrapped: 18 letters a row, two rows
    local text = okI and I18n.t(self.message) or self.message
    local CM = package.loaded["src.coop.CoopManager"]
    local lines = (CM and CM.wrap) and CM.wrap(text, 18, 2) or { text }
    for k, l in ipairs(lines) do Font.raw.draw(l, 8, 112 + k * 8) end
  else
    local countStr = string.format("SELECTED: %d/3", #self.selected)
    Font.draw(countStr, 8, 120)
    Font.draw("A:PICK  B:BACK", 8, 128)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return CoopBattleSelect
