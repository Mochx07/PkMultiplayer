-- LEVEL-UPS IN THE CORNER (nightly.2, CoopBattle.noteLevelUp / drawLevelUps).
--
-- In a co-op double neither copy writes "X grew to level N!" or opens the
-- stats window any more: every level-up -- yours and the partner's, on both
-- copies -- is noted for the corner card.  Two real copies over an in-memory
-- bus (as coop_hyper_beam.lua); the foes are left at 1 HP and both leads are
-- one point short of their next level, so the first turn levels both.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local CoopBattle = require("src.coop.CoopBattle")
local CoopManager = require("src.coop.CoopManager")
local GameVersion = require("src.core.GameVersion")
local Growth = require("src.pokemon.Growth")
CoopManager.balancedFoes, CoopManager.hardFoes = false, false
require("src.coop.CoopLog").enabled = false
CoopBattle.AUTO_REPLACE = true
local P = BattleState.POS
local Json = require("src.link.Json")
local function onWire(m) return Json.decode(Json.encode(m)) end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name, species, level)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = {}
  for i, sp in ipairs(species) do
    local m = Pokemon.new(Data, sp, level, function(a) return a end)
    m.moves = { { id = "FIX_TACKLE", pp = 35 } }
    save.party[i] = m
  end
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function drain(b)
  for _ = 1, 20000 do
    if b.coop and b.coop.localReady then return end
    local top = b.game.stack:top()
    if top ~= b and top and top.update then
      top:update(1 / 60)
    elseif not b:updateQueue() then
      return (b.afterQueue == "finish" or b.result) and "done" or nil
    end
  end
  error("battle queue never drained (phase " .. tostring(b.phase) .. ")")
end

local function hpOf(b, pos) local x = b:battlerAt(pos); return x and x.mon and x.mon.hp or -1 end

-- a co-op double on `version`; `setup(hb, gb)` runs before turn 1.  Returns
-- the per-turn log: who was locked into a recharge, and whether HP agreed.
local function coopDouble(version, setup, turns)
  GameVersion.set(version)
  local hostGame = newGame("HOST", { "FIXMON_A" }, 30)
  local guestGame = newGame("GUEST", { "FIXMON_C" }, 30)
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m) table.insert(bus[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hw, gw = {}, {}
  for i, m in ipairs(hostGame.save.party) do hw[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do gw[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, gw, { name = "GUEST" }, 777, "HB")
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hw, { name = "HOST" }, 777, "HB")
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  local function agree()
    return hpOf(hb, P.PLAYER_LEFT) == hpOf(gb, P.PLAYER_RIGHT) and hpOf(hb, P.PLAYER_RIGHT) == hpOf(gb, P.PLAYER_LEFT)
       and hpOf(hb, P.OPPONENT_LEFT) == hpOf(gb, P.OPPONENT_LEFT)
       and hpOf(hb, P.OPPONENT_RIGHT) == hpOf(gb, P.OPPONENT_RIGHT)
  end
  drain(hb); drain(gb)
  for _, b in ipairs({ hb, gb }) do
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local x = b:battlerAt(pos)
      if x then x.mon.stats.hp = 999; x.mon.hp = 999 end
    end
  end
  if setup then setup(hb, gb) end
  local log = {}
  for turn = 1, turns do
    local row = { locked = {} }
    for _, side in ipairs({ { "host", hb }, { "guest", gb } }) do
      sender = side[1]
      local b = side[2]
      CoopBattle.currentBattle = b
      local me = b:battlerAt(P.PLAYER_LEFT)
      local locked = me and b:menuLockedAction(me)
      if locked then
        row.locked[side[1]] = locked.special or true
        b:submitTurnAction(locked, true)
      elseif me then
        local mv = me.curMoves[1]
        mv.targetPosition = P.OPPONENT_LEFT
        CoopBattle.onLocalActionSelected(b, mv)
      else
        CoopBattle.onSpectatorTurn(b)
      end
    end
    deliver("guest"); deliver("host")
    drain(hb); drain(gb)
    row.agree = agree()
    row.hostMust = hb:battlerAt(P.PLAYER_LEFT) and hb:battlerAt(P.PLAYER_LEFT).mustRecharge or false
    row.guestCopyMust = gb:battlerAt(P.PLAYER_RIGHT) and gb:battlerAt(P.PLAYER_RIGHT).mustRecharge or false
    log[turn] = row
  end
  return log, hb, gb
end

local function almostLevelled(mon)
  local rate = Data.pokemon[mon.species].growthRate
  mon.exp = Growth.expForLevel(rate, mon.level + 1) - 1
end

for _, version in ipairs({ "gold", "red" }) do
  local said = {}
  local real = BattleState.sayNext
  BattleState.sayNext = function(self, text, ...)
    said[#said + 1] = tostring(text)
    return real(self, text, ...)
  end
  local log, hb, gb = coopDouble(version, function(h, g)
    for _, b in ipairs({ h, g }) do
      for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
        local x = b:battlerAt(pos)
        if x then x.mon.hp = 1 end
      end
      for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT }) do
        local x = b:battlerAt(pos)
        if x then almostLevelled(x.mon) end
      end
    end
  end, 1)
  BattleState.sayNext = real
  local grew = 0
  for _, line in ipairs(said) do if line:find("grew") then grew = grew + 1 end end
  T.check(grew == 0, version .. ": no \"grew to level\" box in a co-op double (" .. grew .. ")")
  T.check(log[1].agree, version .. ": the two copies agree on HP")
  for _, side in ipairs({ { "host", hb }, { "guest", gb } }) do
    local b = side[2]
    local owners = {}
    for _, e in ipairs(b.coopLevelUps or {}) do owners[e.owner] = (owners[e.owner] or 0) + 1 end
    T.check(owners.you == 1, version .. " " .. side[1] .. ": its own level-up is noted for the corner")
    T.check(owners.partner == 1, version .. " " .. side[1] .. ": ...and so is the partner's")
    local cards = CoopBattle.levelUpCards(b, 100)
    T.check(#cards == 2 and cards[1].level and cards[1].level == cards[1].mon.level,
            version .. " " .. side[1] .. ": two cards, each with the new level")
    T.check(#CoopBattle.levelUpCards(b, 100 + CoopBattle.LEVELUP_SHOW + 0.1) == 0,
            version .. " " .. side[1] .. ": ...gone after " .. CoopBattle.LEVELUP_SHOW .. " s")
  end
end

-- the card itself
do
  GameVersion.set("gold")
  local e = CoopBattle.noteLevelUp({ data = Data }, { species = "FIXMON_A", level = 9 }, 9, "you")
  T.check(e and e.name ~= "" and e.level == 9, "noteLevelUp keeps name and level")
end

T.finish("level-ups in the corner")
