-- CO-OP DOUBLES PLAY BY THE TURN RULES.
--
-- The same two-copy harness as coop_lockstep.lua, asking what each turn
-- DID rather than whether the copies agree:
--   * the foes' moves go to both players' Pokemon, not only to the host's
--     (redirect() answered foesOf()[1] -- the host's -- for every AI move);
--   * an item is used before anybody attacks, on both copies;
--   * moves run fastest first.
-- And the per-foe experience lists: a Pokemon that fought a foe and was
-- then switched out is still paid when that foe falls.
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
-- the trainers here are the scenario: no co-op difficulty on top (coop_balance.lua)
CoopManager.balancedFoes, CoopManager.hardFoes = false, false
local Json = require("src.link.Json")
require("src.coop.CoopLog").enabled = false
CoopBattle.AUTO_REPLACE = true

local P = BattleState.POS

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
    save.party[i] = Pokemon.new(Data, sp, level, function(a) return a end)
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
  error("battle queue never drained")
end

local function pickMove(b, slot)
  local me = b:battlerAt(P.PLAYER_LEFT)
  if not me then return nil end
  local mv = me.curMoves[((slot - 1) % #me.curMoves) + 1]
  local foe = b:battlerAt(P.OPPONENT_LEFT)
  mv.targetPosition = (foe and foe.mon.hp > 0) and P.OPPONENT_LEFT or P.OPPONENT_RIGHT
  return mv
end

-- two copies on an in-memory wire; `record(copy, b)` hooks a copy before
-- the battle starts
local function setup(seed, level, hostSpecies, guestSpecies, record)
  local hostGame = newGame("HOST", hostSpecies, level)
  local guestGame = newGame("GUEST", guestSpecies, level)
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m)
                        table.insert(bus[sender == "host" and "guest" or "host"], Json.decode(Json.encode(m)))
                      end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  if record then record("host", hb) end
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "RULES" .. seed)
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  if record then record("guest", gb) end
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "RULES" .. seed)
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  -- one turn: each side's action (a function of the copy, or nil = move)
  local function turn(n, hostAction, guestAction)
    sender = "host"; CoopBattle.currentBattle = hb
    local ha = hostAction and hostAction(hb) or pickMove(hb, n)
    if ha then CoopBattle.onLocalActionSelected(hb, ha) else CoopBattle.onSpectatorTurn(hb) end
    sender = "guest"; CoopBattle.currentBattle = gb
    local ga = guestAction and guestAction(gb) or pickMove(gb, n + 1)
    if ga then CoopBattle.onLocalActionSelected(gb, ga) else CoopBattle.onSpectatorTurn(gb) end
    deliver("guest"); deliver("host")
    local r1, r2 = drain(hb), drain(gb)
    return r1 == "done" or r2 == "done" or hb.result or gb.result
  end
  drain(hb); drain(gb)
  return hb, gb, turn
end

-- ---------------------------------------------------------------------
-- the foes aim at both of you
-- ---------------------------------------------------------------------

do
  local hits = { host = 0, guest = 0 }
  local function record(who, b)
    if who ~= "host" then return end
    local exec = b.executeAction
    b.executeAction = function(self, user, target, action)
      local l, r = self:battlerAt(P.PLAYER_LEFT), self:battlerAt(P.PLAYER_RIGHT)
      local bothUp = l and r and l.mon.hp > 0 and r.mon.hp > 0
      -- only while both of you are standing: a lone survivor is hit anyway
      if bothUp and user and not user.isPlayer and target and target.isPlayer and action and action.id then
        -- on the host's copy its own Pokemon stands LEFT
        if target.position == P.PLAYER_LEFT then hits.host = hits.host + 1
        elseif target.position == P.PLAYER_RIGHT then hits.guest = hits.guest + 1 end
      end
      return exec(self, user, target, action)
    end
  end
  for _, seed in ipairs({ 777, 7919, 15838, 23757 }) do
    local hb, gb, turn = setup(seed, 5, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_B" }, record)
    for n = 1, 12 do if turn(n) then break end end
  end
  T.check(hits.host > 0, "with both standing, foes attack the host's Pokemon (" .. hits.host .. " times)")
  T.check(hits.guest > 0, "with both standing, foes attack the guest's Pokemon too (" .. hits.guest .. " times)")
end

-- ---------------------------------------------------------------------
-- an item comes before every move, and moves go fastest first
-- ---------------------------------------------------------------------

do
  local log = { host = {}, guest = {} }
  local function record(who, b)
    local exec = b.executeAction
    b.executeAction = function(self, user, target, action)
      if user and action then
        local kind = action.special == "playerItem" and "item" or (action.id and "move") or "other"
        table.insert(log[who], { kind = kind, battler = user,
                                 speed = user.mon and user.mon.stats and user.mon.stats.speed or 0,
                                 priority = action.id and Data.moves[action.id] and Data.moves[action.id].priority or 0 })
      end
      return exec(self, user, target, action)
    end
  end
  local hb, gb, turn = setup(4242, 30, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_B" }, record)
  -- the GUEST uses a potion on turn 1; the host attacks
  local function potion(b)
    local me = b:battlerAt(P.PLAYER_LEFT)
    return { special = "playerItem", id = "FIX_POTION", target = me.mon,
             targetNick = me.mon.nickname or me.mon.species, messages = { "Used FIX POTION!" } }
  end
  turn(1, nil, potion)
  for _, who in ipairs({ "host", "guest" }) do
    local l = log[who]
    T.check(l[1] and l[1].kind == "item", who .. "'s copy: the item is the first thing the turn does")
    local ordered = true
    local last
    for _, e in ipairs(l) do
      if e.kind == "move" then
        if last and (e.priority > last.priority or (e.priority == last.priority and e.speed > last.speed)) then
          ordered = false
        end
        last = e
      end
    end
    T.check(ordered, who .. "'s copy: moves ran fastest first")
  end
end

-- ---------------------------------------------------------------------
-- experience: each foe pays everyone who faced it
-- ---------------------------------------------------------------------

do
  local game = newGame("SOLO", { "FIXMON_A", "FIXMON_B" }, 5)
  local b = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  game.stack:push(b)
  b.double = true
  local a, c = game.save.party[1], game.save.party[2]
  local foe1 = { mon = { hp = 10 } }
  local foe2 = { mon = { hp = 10 } }
  b.sides = { { battlers = { { mon = a }, nil } }, { battlers = { foe1, foe2 } } }
  b:markFoeParticipants()
  -- A goes off, C comes in; foe 1 falls -- then foe 2 must still pay A
  b.sides[1].battlers[1] = { mon = c }
  b:markFoeParticipants()
  T.check(b.foeParticipants[foe1.mon][a] and b.foeParticipants[foe1.mon][c], "foe 1 remembers both Pokemon that faced it")
  b.foeParticipants[foe1.mon] = nil   -- what awardExp spends
  T.check(b.foeParticipants[foe2.mon][a], "the switched-out Pokemon is still owed its share of foe 2")
end

T.finish("co-op doubles turn rules")
