-- src/coop/CoopWatch.lua
-- WATCHING THE PARTNER'S BATTLE.  START -> CO-OP -> PARTNER -> WATCH <name> opens a
-- small battle screen of the partner's fight as it happens: their foe and
-- their Pokemon (pics, levels, HP bars, status) and the line on their text
-- box.  It only shows -- the battle is theirs; to fight beside them, WILD
-- TOGETHER or a trainer's CO-OP DOUBLE.
--
-- Wire: coop_watch { on } (start/stop), and while watched the battling side
-- sends coop_watch_frame { foe, mine, text } every FRAME_EVERY seconds, or
-- { idle = true } once a second when it is not in a battle.

local CoopManager = require("src.coop.CoopManager")
local Font = require("src.coop.CoopI18n").font()

local CoopWatch = {}

CoopWatch.FRAME_EVERY = 0.2
CoopWatch.IDLE_EVERY = 1.0
CoopWatch.watchedBy = false -- the partner is watching us
CoopWatch.frame = nil       -- what we last saw of the partner's battle
CoopWatch.timer = 0

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

-- the battle on our stack, if any
function CoopWatch.currentBattle(game)
  local states = game and game.stack and game.stack.states
  for i = #(states or {}), 1, -1 do
    local st = states[i]
    if type(st) == "table" and (st.kind == "wild" or st.kind == "trainer") and st.enemy then
      return st
    end
  end
  return nil
end

local function pack(b)
  if not (b and b.mon) then return nil end
  local m = b.mon
  local maxHp = (m.stats and m.stats.hp) or m.maxHp or m.hp or 1
  local shiny = false
  pcall(function() shiny = require("src.pokemon.Pokemon").isShiny(m) end)
  return { species = m.species, level = m.level, hp = m.hp or 0, max = maxHp,
           status = m.status, name = b.name or m.nickname, shiny = shiny or nil }
end

local function lineOf(battle)
  local cur = battle.current
  local text = cur and cur.text
  if type(text) ~= "string" then return nil end
  return (text:gsub("[\n\v\f]", " "):sub(1, 60))
end

function CoopWatch.snapshot(battle)
  return { kind = battle.kind, foe = pack(battle.enemy), mine = pack(battle.player),
           text = lineOf(battle), double = battle.coopDouble or nil }
end

local H = CoopManager.handlers

H.coop_watch = function(ow, msg)
  CoopWatch.watchedBy = msg.on == true
  CoopWatch.timer = 0
end

H.coop_watch_frame = function(ow, msg)
  CoopWatch.frame = msg
  CoopWatch.frameAt = love and love.timer and love.timer.getTime() or os.time()
end

-- the watched side: frames while someone looks
CoopManager.onTick("watch", function(dt, game)
  if CoopWatch.serial ~= CoopManager.linkSerial then
    CoopWatch.serial = CoopManager.linkSerial
    CoopWatch.watchedBy = false
  end
  if not CoopWatch.watchedBy then return end
  CoopWatch.timer = CoopWatch.timer - dt
  if CoopWatch.timer > 0 then return end
  local battle = CoopWatch.currentBattle(game)
  if battle then
    CoopWatch.timer = CoopWatch.FRAME_EVERY
    local snap = CoopWatch.snapshot(battle)
    snap.type = "coop_watch_frame"
    CoopManager.net:send(snap, { fast = true })
  else
    CoopWatch.timer = CoopWatch.IDLE_EVERY
    send({ type = "coop_watch_frame", idle = true })
  end
end)

-- ---------------------------------------------------------------------
-- the screen
-- ---------------------------------------------------------------------

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

function CoopWatch.open(game)
  CoopWatch.frame = nil
  send({ type = "coop_watch", on = true })
  local self = setmetatable({ game = game, pics = {} }, Screen)
  game.stack:push(self)
  return self
end

function Screen:close()
  send({ type = "coop_watch", on = false })
  self.game.stack:pop()
end

function Screen:update()
  local input = self.game.input
  if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
    self:close()
    return
  end
  if not CoopManager.isConnected() then self:close() end
end

-- the pic for a side, built once per species (front for the foe, back for
-- the partner's own), through the engine's own battler so it wears its palette
function Screen:pic(side, info)
  if not (info and info.species) then return nil end
  local key = side .. ":" .. info.species .. (info.shiny and "*" or "")
  local hit = self.pics[key]
  if hit ~= nil then return hit or nil end
  local img = false
  pcall(function()
    local game = self.game
    local Pokemon = require("src.pokemon.Pokemon")
    local BattleState = require("src.battle.BattleState")
    local mon = Pokemon.new(game.data, info.species, tonumber(info.level) or 5)
    if info.shiny and Pokemon.forceShiny then Pokemon.forceShiny(game.data, mon) end
    local b = BattleState.makeBattler(game.data, mon, side == "mine", game.save)
    if b and b.sprite and b.sprite.getWidth then img = b.sprite end
  end)
  self.pics[key] = img
  return img or nil
end

local function hpBar(x, y, w, hp, max)
  local f = math.max(0, math.min(1, (tonumber(hp) or 0) / math.max(1, tonumber(max) or 1)))
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x, y, w + 2, 4)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x + 1, y + 1, w, 2)
  if f > 0.5 then g.setColor(0.1, 0.75, 0.2, 1)
  elseif f > 0.2 then g.setColor(0.95, 0.75, 0.1, 1)
  else g.setColor(0.9, 0.15, 0.1, 1) end
  g.rectangle("fill", x + 1, y + 1, math.floor(w * f + 0.5), 2)
  g.setColor(0, 0, 0, 1)
end

local function label(info)
  local name = tostring(info.name or info.species or "?"):sub(1, 10)
  return name, ("L%d"):format(tonumber(info.level) or 0) .. (info.status and (" " .. tostring(info.status):sub(1, 3)) or "")
end

function Screen:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", 0, 0, 160, 144)
  g.setColor(0, 0, 0, 1)
  local who = tostring(CoopManager.partner.name or "PARTNER"):upper():sub(1, 7)
  local f = CoopWatch.frame
  if not f then
    Font.drawBox(0, 12, 20, 6)
    Font.draw("WATCHING " .. who, 8, 104)
    Font.draw("WAITING...", 8, 120)
    return
  end
  if f.idle then
    Font.drawBox(0, 12, 20, 6)
    Font.draw(who .. " IS NOT", 8, 104)
    Font.draw("IN A BATTLE.", 8, 120)
    return
  end
  -- the foe, top right; its HUD top left
  local foe, mine = f.foe, f.mine
  if foe then
    local img = self:pic("foe", foe)
    if img then
      local w, h = img:getWidth(), img:getHeight()
      local tw = math.max(1, math.min(7, math.floor(w / 8)))
      local th = math.max(1, math.min(7, math.floor(h / 8)))
      g.setColor(1, 1, 1, 1)
      g.draw(img, 96 + 8 * math.floor((8 - tw) / 2), 8 * (7 - th))
      g.setColor(0, 0, 0, 1)
    end
    local n, l = label(foe)
    Font.draw(n, 8, 0)
    Font.draw(l, 32, 8)
    hpBar(16, 18, 64, foe.hp, foe.max)
  end
  if mine then
    local img = self:pic("mine", mine)
    if img then
      local w, h = img:getWidth(), img:getHeight()
      local s = 1
      pcall(function()
        s = require("src.battle.BattleState").resolveBattleScale(self.game.data, "back", nil, mine.species) or 1
      end)
      g.setColor(1, 1, 1, 1)
      g.draw(img, 8, 96 - h * s, 0, s, s)
      g.setColor(0, 0, 0, 1)
    end
    local n, l = label(mine)
    Font.draw(n, 80, 56)
    Font.draw(l, 104, 64)
    hpBar(88, 74, 64, mine.hp, mine.max)
    Font.draw(("%3d/%3d"):format(tonumber(mine.hp) or 0, tonumber(mine.max) or 0), 96, 80)
  end
  Font.drawBox(0, 12, 20, 6)
  for i, line in ipairs(CoopManager.wrap(f.text or "", 18, 2)) do
    Font.draw(line, 8, 96 + i * 16)
  end
  -- whose battle this is, under their HP numbers
  Font.draw(who, 80, 88)
end

CoopWatch.Screen = Screen

return CoopWatch
