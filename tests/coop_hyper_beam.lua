-- HYPER BEAM'S RECHARGE TURN, IN GEN 1 AND GEN 2 (lib/Hooks.lua).
--
-- The engine's HYPER_BEAM_EFFECT sets mustRecharge and skips it when the
-- target fainted or its substitute broke -- Generation One's rule, which the
-- gen1_faithful ruleset turns on.  Gold, Silver and Crystal fight under that
-- same ruleset, so in Gen 2 a Hyper Beam that knocked its target out needed
-- no recharge, which the cartridge never allows: from Gen 2 on only a miss
-- spares the turn.
--
-- Two real copies of a co-op double (host's and guest's, over an in-memory
-- bus, as coop_lockstep.lua) and a single battle; every case checks who must
-- recharge and that the two copies agree on every Pokemon's HP.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
Data.moves.FIX_BEAM = { id = "FIX_BEAM", index = 63, name = "FIX BEAM", type = "NORMAL", power = 150,
                        accuracy = 100, pp = 5, effect = "HYPER_BEAM_EFFECT" }
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local CoopBattle = require("src.coop.CoopBattle")
local CoopManager = require("src.coop.CoopManager")
local GameVersion = require("src.core.GameVersion")
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
    m.moves = { { id = "FIX_BEAM", pp = 5 } }
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

for _, version in ipairs({ "gold", "red" }) do
  -- 1) a Hyper Beam that lands and leaves the target standing: the next turn
  -- is a recharge, on both copies, in both generations
  local log = coopDouble(version, nil, 3)
  T.check(log[1].hostMust and log[1].guestCopyMust, version .. ": a landed Hyper Beam asks for a recharge, on both copies")
  T.check(log[2].locked.host == "recharge" and log[2].locked.guest == "recharge",
          version .. ": turn 2 is the recharge turn for both players")
  T.check(not log[2].hostMust and log[3].hostMust, version .. ": ...then it fires again on turn 3")
  local allAgree = true
  for _, r in ipairs(log) do allAgree = allAgree and r.agree end
  T.check(allAgree, version .. ": both copies agree on every HP through the beam and the recharge")

  -- 2) a miss spares the recharge, in both generations
  log = coopDouble(version, function(hb, gb)
    for _, b in ipairs({ hb, gb }) do
      for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
        local x = b:battlerAt(pos)
        if x then x.invulnerable = true end
      end
    end
  end, 1)
  T.check(not log[1].hostMust and not log[1].guestCopyMust and log[1].agree, version .. ": a Hyper Beam that misses needs no recharge")
end

-- 3) a Hyper Beam that knocks its target out: Gen 2 recharges anyway, Gen 1
-- does not (the cartridges' rules)
local function koFirstFoe(hb, gb)
  for _, b in ipairs({ hb, gb }) do
    local x = b:battlerAt(P.OPPONENT_LEFT)
    x.mon.hp = 1
  end
end
local log = coopDouble("gold", koFirstFoe, 2)
T.check(log[1].hostMust and log[1].guestCopyMust, "GOLD: a Hyper Beam that knocks out its target still asks for a recharge, on both copies")
T.check(log[2].locked.host == "recharge" and log[1].agree and log[2].agree, "GOLD: ...the next turn is the recharge and both copies agree")
log = coopDouble("red", koFirstFoe, 2)
T.check(not log[1].hostMust and not log[1].guestCopyMust and log[1].agree,
        "RED: a Hyper Beam that knocks out its target needs no recharge (Gen 1)")

-- 4) a broken substitute: Gen 2 recharges, Gen 1 does not
local function subFirstFoe(hb, gb)
  for _, b in ipairs({ hb, gb }) do b:battlerAt(P.OPPONENT_LEFT).substituteHP = 1 end
end
log = coopDouble("gold", subFirstFoe, 1)
T.check(log[1].hostMust and log[1].guestCopyMust, "GOLD: breaking a substitute still asks for a recharge")
log = coopDouble("red", subFirstFoe, 1)
T.check(not log[1].hostMust and not log[1].guestCopyMust, "RED: breaking a substitute needs no recharge (Gen 1)")

-- 5) a single battle, Gen 2: the knockout is followed by a recharge turn
do
  GameVersion.set("gold")
  CoopManager.connected = false
  local game = newGame("SOLO", { "FIXMON_A" }, 30)
  local b = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  game.stack:push(b)
  drain(b)
  b.enemy.mon.hp = 1
  local mv = b.player.curMoves[1]
  b:resolveTurn(mv)
  -- far enough for the move to land (the trainer's next Pokemon then waits
  -- on a prompt nobody answers here)
  for _ = 1, 2000 do
    if not b:updateQueue() then break end
  end
  T.check(b.enemy == nil or b.enemy.mon.hp <= 0 or b.enemyParty, "the single: the beam landed")
  T.check(b.player.mustRecharge == true, "GOLD single: the knockout Hyper Beam still asks for a recharge")
end

GameVersion.set("red")
T.finish("Hyper Beam's recharge turn")
