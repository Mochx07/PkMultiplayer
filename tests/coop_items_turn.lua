-- CO-OP DOUBLES: ITEMS WITH NO POKEMON TO PICK, LATE PICKS, REVIVES, EXP.
--
-- Reported from play:
--   * "attempt to index local 'target' (a nil value)" (BagMenu useOn): an
--     X item in a co-op double has no Pokemon to pick, and the co-op path
--     read target.species.  Behind the crash, the boost only ever reached
--     the user's own copy -- every hit after it landed for different damage
--     on the two screens;
--   * "when one takes long, the wrong Pokemon is sent out": a fallen
--     partner slot gave up after 30 s and sent in the first healthy one,
--     then the partner chose another;
--   * "reviving the other does nothing": a player whose whole team was down
--     got a Pokemon back and it never came in;
--   * "if the battle desyncs the player loses their exp": the host's win
--     closed the guest's copy with a foe still standing there, unpaid.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local BagMenu = require("src.ui.BagMenu")
local CoopBattle = require("src.coop.CoopBattle")
local CoopManager = require("src.coop.CoopManager")
-- the trainers here are the scenario: no co-op difficulty on top (coop_balance.lua)
CoopManager.balancedFoes, CoopManager.hardFoes = false, false
require("src.coop.CoopLog").enabled = false
local P = BattleState.POS
local Json = require("src.link.Json")
local function onWire(m) return Json.decode(Json.encode(m)) end

Data.items.X_ATTACK = Data.items.X_ATTACK or { id = "X_ATTACK", key = "X_ATTACK", name = "X ATTACK", price = 500 }
Data.items.POKE_DOLL = Data.items.POKE_DOLL or { id = "POKE_DOLL", key = "POKE_DOLL", name = "POKé DOLL", price = 1000 }

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
  save.inventory = save.inventory or {}
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function drain(b)
  for _ = 1, 20000 do
    if b.coop and b.coop.localReady then return end
    local top = b.game.stack:top()
    if top ~= b and top and top.update then top:update(1 / 60)
    elseif not b:updateQueue() then
      if b.afterQueue == "finish" or b.result then return "done" end
      if b.phase ~= "messages" then return nil end
      b:update(1 / 60)
    end
  end
  error("queue never drained (phase " .. tostring(b.phase) .. ")")
end

-- a host copy and a guest copy of one co-op double, messages carried by hand
local function pair(seed)
  local hostGame = newGame("HOST", { "FIXMON_A", "FIXMON_B" }, 20)
  local guestGame = newGame("GUEST", { "FIXMON_C", "FIXMON_B" }, 20)
  local bus = { host = {}, guest = {} }
  local env = { sender = "host" }
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m) table.insert(bus[env.sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "ITEMS")
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "ITEMS")
  function env.deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m)
      elseif m.type == "coop_battle_sync" then CoopBattle.onPartnerBattleSync(m) end
    end
  end
  env.hb, env.gb, env.hostGame, env.guestGame = hb, gb, hostGame, guestGame
  drain(hb); drain(gb)
  return env
end

-- a harmless move: the first one the battler knows, aimed at the left foe
local function plainMove(b)
  local me = b:battlerAt(P.PLAYER_LEFT)
  if not me then return nil end
  local mv = me.curMoves[1]
  mv.targetPosition = P.OPPONENT_LEFT
  return mv
end

local function stagesOf(b)
  local out = {}
  for k, v in pairs((b and b.stages) or {}) do if v ~= 0 then out[#out + 1] = k .. "=" .. v end end
  table.sort(out)
  return table.concat(out, ",")
end

-- ---------------------------------------------------------------------
-- X ATTACK from the guest's bag: no crash, and the stage on BOTH copies
-- ---------------------------------------------------------------------
do
  local env = pair(4242)
  local hb, gb = env.hb, env.gb
  env.guestGame.save.inventory.X_ATTACK = 1
  env.sender = "host"; CoopBattle.currentBattle = hb
  CoopBattle.onLocalActionSelected(hb, plainMove(hb))
  env.sender = "guest"; CoopBattle.currentBattle = gb
  local ok, err = pcall(BagMenu.useItem, env.guestGame, gb, "X_ATTACK", { close = function() end })
  T.check(ok, "an X ATTACK in a co-op double does not crash (" .. tostring(err) .. ")")
  -- the bag's messages first, then the action goes out
  for _ = 1, 600 do
    local top = env.guestGame.stack:top()
    if top == gb or not top or not top.update then break end
    top:update(1 / 60)
  end
  T.check(gb.coop.localReady == true, "the X ATTACK is this turn's action")
  local mine = gb:battlerAt(P.PLAYER_LEFT)
  T.check((mine.stages.attack or 0) == 1, "the guest's own copy has the ATTACK stage (" .. stagesOf(mine) .. ")")
  env.deliver("guest"); env.deliver("host")
  drain(hb); drain(gb)
  local onHost = hb:battlerAt(P.PLAYER_RIGHT)
  T.check(onHost and (onHost.stages.attack or 0) == 1,
          "the host's copy of the guest's Pokemon has it too (" .. stagesOf(onHost) .. ")")
  T.check(stagesOf(onHost) == stagesOf(gb:battlerAt(P.PLAYER_LEFT)), "both copies hold the same stages")
end

-- ---------------------------------------------------------------------
-- the POKé FLUTE wakes the whole field on both copies
-- ---------------------------------------------------------------------
do
  local env = pair(777)
  local hb, gb = env.hb, env.gb
  for _, b in ipairs({ hb, gb }) do
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local f = b:battlerAt(pos)
      if f then f.mon.status = "SLP" f.status = "SLP" f.sleepTurns = 7 end
    end
  end
  env.sender = "host"; CoopBattle.currentBattle = hb
  CoopBattle.onLocalActionSelected(hb, plainMove(hb))
  env.sender = "guest"; CoopBattle.currentBattle = gb
  CoopBattle.onLocalActionSelected(gb, { special = "playerItem", id = "POKE_FLUTE",
                                         messages = { "FLUTE" }, boost = { flute = true } })
  env.deliver("guest"); env.deliver("host")
  drain(hb); drain(gb)
  local asleep = 0
  for _, b in ipairs({ hb, gb }) do
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local f = b:battlerAt(pos)
      if f and f.mon.status == "SLP" then asleep = asleep + 1 end
    end
  end
  T.check(asleep == 0, "the flute woke every foe on both copies (" .. asleep .. " still asleep)")
end

-- ---------------------------------------------------------------------
-- the POKé DOLL is refused in a co-op double (it would end one copy only)
-- ---------------------------------------------------------------------
do
  local env = pair(99)
  local ItemEffects = require("src.inventory.ItemEffects")
  env.gb.kind = "wild" -- a trainer battle refuses the doll anyway
  local kind = ItemEffects.use(Data, env.guestGame.save, "POKE_DOLL", nil, env.gb)
  T.check(kind == "failed", "a POKé DOLL is refused while battling together (" .. tostring(kind) .. ")")
end

-- ---------------------------------------------------------------------
-- a POKé BALL is refused in a co-op double (trainer: blocked / thief; wild: together)
-- ---------------------------------------------------------------------
do
  local env = pair(100)
  local ItemEffects = require("src.inventory.ItemEffects")
  Data.items.POKE_BALL = Data.items.POKE_BALL or { id = "POKE_BALL", key = "POKE_BALL", name = "POKé BALL", price = 200 }
  env.guestGame.save.inventory.POKE_BALL = 3

  -- In a co-op trainer double, throwing a ball is blocked by the trainer
  local kind, msgs = ItemEffects.use(Data, env.guestGame.save, "POKE_BALL", nil, env.gb)
  T.check(kind == "failed", "a POKé BALL is refused in a co-op trainer battle (" .. tostring(kind) .. ")")
  local textJoined = table.concat(msgs or {}, " ")
  T.check(textJoined:find("blocked") or textJoined:find("thief"),
          "refusal message mentions trainer block / thief: " .. tostring(textJoined))
  T.check(env.guestGame.save.inventory.POKE_BALL == 3, "the ball is not consumed")

  -- Using a POKé BALL via BagMenu: does not close the bag, does not consume the ball
  local closed = false
  local okUse, errUse = pcall(BagMenu.useItem, env.guestGame, env.gb, "POKE_BALL", { close = function() closed = true end })
  T.check(okUse, "using a POKé BALL via BagMenu in a co-op double does not crash (" .. tostring(errUse) .. ")")
  T.check(not closed, "the bag menu is NOT closed when a ball is blocked")
  T.check(env.guestGame.save.inventory.POKE_BALL == 3, "the ball is still in inventory")

  -- Direct throwBall in co-op does not advance turns or execute actions
  local rec = { actions = 0, endTurns = 0 }
  local realAct, realEnd = env.gb.executeAction, env.gb.endOfTurn
  env.gb.executeAction = function(...) rec.actions = rec.actions + 1 return realAct(...) end
  env.gb.endOfTurn = function(...) rec.endTurns = rec.endTurns + 1 return realEnd(...) end
  local turnBefore = env.gb.turn or 1
  env.gb:throwBall("POKE_BALL")
  T.check(rec.actions == 0 and rec.endTurns == 0, "throwBall does not execute enemy actions or endOfTurn")
  T.check((env.gb.turn or 1) == turnBefore, "turn count did not advance")
  T.check(env.gb.phase == "menu", "phase returned to menu")
  env.gb.executeAction, env.gb.endOfTurn = realAct, realEnd

  -- In a co-op wild double, balls cannot be aimed
  env.gb.kind = "wild"
  env.gb.coopWild = true
  local wKind, wMsgs = ItemEffects.use(Data, env.guestGame.save, "POKE_BALL", nil, env.gb)
  T.check(wKind == "failed", "a POKé BALL is refused in a co-op wild battle (" .. tostring(wKind) .. ")")
  T.check(wMsgs and wMsgs[1]:find("together"), "refusal message explains cannot catch together")
end

-- ---------------------------------------------------------------------
-- a partner still choosing is waited for, however long it takes
-- ---------------------------------------------------------------------
do
  local env = pair(5)
  local gb = env.gb
  local placed
  local w = CoopBattle.newReplaceWait(gb, P.PLAYER_RIGHT, function(m) placed = m or false end)
  env.guestGame.stack:push(w)
  for _ = 1, 60 * 90 do w:update(1 / 60) end
  T.check(placed == nil, "90 s on, the partner's slot is still waiting for their own pick")
  table.insert(gb.coop.replaceQueue, { index = 2, species = gb.ally.party[2].species })
  w:update(1 / 60)
  T.check(placed == gb.ally.party[2], "their pick, when it comes, is the one sent in")

  local placed2
  local w2 = CoopBattle.newReplaceWait(gb, P.PLAYER_RIGHT, function(m) placed2 = m or false end)
  env.guestGame.stack:push(w2)
  CoopManager.isConnected = function() return false end
  for _ = 1, 60 * 31 do w2:update(1 / 60) end
  T.check(placed2 ~= nil, "with the link gone, the wait gives up and the next healthy one goes in")
  CoopManager.isConnected = function() return true end
end

-- ---------------------------------------------------------------------
-- a revived Pokemon on an empty side is asked for at the end of the turn
-- ---------------------------------------------------------------------
do
  local env = pair(31)
  local hb, gb = env.hb, env.gb
  -- the guest's whole team is down: their slot is empty on both copies
  for _, b in ipairs({ hb, gb }) do
    local pos = (b == hb) and P.PLAYER_RIGHT or P.PLAYER_LEFT
    local list = (b == hb) and b.ally.party or b.coopChosenMons
    for _, m in ipairs(list) do m.hp = 0 end
    b:placeBattler(pos, nil)
    b:syncSides()
  end
  T.check(gb:battlerAt(P.PLAYER_LEFT) == nil and hb:battlerAt(P.PLAYER_RIGHT) == nil, "the guest's slot is empty")
  -- the host revives the guest's second Pokemon from the host's bag
  local target = hb.ally.party[2]
  target.hp = math.floor((target.stats and target.stats.hp or 40) / 2)
  local heal = CoopBattle.itemHeal(hb, target)
  T.check(heal and heal.side == "ally", "the revive rides with the host's action")
  env.sender = "host"; CoopBattle.currentBattle = hb
  CoopBattle.onLocalActionSelected(hb, { special = "playerItem", id = "REVIVE", messages = { "REVIVE" }, heal = heal })
  env.sender = "guest"; CoopBattle.currentBattle = gb
  CoopBattle.onSpectatorTurn(gb)
  env.deliver("guest"); env.deliver("host")
  -- the guest's copy: their own party screen opens for the empty slot
  pcall(drain, gb)
  local top = env.guestGame.stack:top()
  local asked = false
  for _, st in ipairs(env.guestGame.stack.states) do
    if st ~= gb and type(st) == "table" and (st.forceSwitch or (st.opts and st.opts.forceSwitch) or st.onSwitch) then asked = true end
  end
  T.check(asked or (gb:battlerAt(P.PLAYER_LEFT) ~= nil),
          "the guest is asked who goes in (or it is in) after the revive (" .. tostring(top and top.__name or top) .. ")")
  -- the host's copy waits for that pick instead of leaving the slot empty
  pcall(drain, hb)
  local waiting = false
  for _, st in ipairs(env.hostGame.stack.states) do
    if getmetatable(st) and st.place and st.pos == P.PLAYER_RIGHT then waiting = true end
  end
  T.check(waiting or hb:battlerAt(P.PLAYER_RIGHT) ~= nil, "the host's copy waits for the guest's pick")
end

-- ---------------------------------------------------------------------
-- the host's win pays the guest for a foe its copy never saw fall
-- ---------------------------------------------------------------------
do
  local env = pair(2024)
  local gb = env.gb
  local paid = {}
  local real = gb.awardExp
  gb.awardExp = function(self, foe) paid[#paid + 1] = foe and foe.mon return real(self, foe) end
  local foe = gb:battlerAt(P.OPPONENT_LEFT)
  local expBefore = gb.coopChosenMons[1].exp
  gb.foeParticipants = gb.foeParticipants or {}
  gb.foeParticipants[foe.mon] = { [gb.coopChosenMons[1]] = true }
  CoopBattle.forceFinishBattle(gb, "win")
  T.check(#paid >= 1 and paid[1] == foe.mon, "the foe still standing on the guest's copy is paid for")
  T.check(gb.coopChosenMons[1].exp > expBefore,
          ("the guest's Pokemon gained its experience (%s -> %s)"):format(tostring(expBefore), tostring(gb.coopChosenMons[1].exp)))

  local env2 = pair(2025)
  local gb2 = env2.gb
  local paid2 = 0
  local real2 = gb2.awardExp
  gb2.awardExp = function(self, f) paid2 = paid2 + 1 return real2(self, f) end
  for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
    local f = gb2:battlerAt(pos)
    if f then gb2.expPaidFor = gb2.expPaidFor or {} gb2.expPaidFor[f.mon] = true end
  end
  CoopBattle.forceFinishBattle(gb2, "win")
  T.check(paid2 == 0, "a foe already paid for is not paid twice")
end

-- ---------------------------------------------------------------------
-- a foe's AI switch never picks the Pokemon already out in the other slot
-- ---------------------------------------------------------------------
do
  local TrainerAI = require("src.battle.TrainerAI")
  local env = pair(8)
  local hb = env.hb
  local function onField()
    local out = {}
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local b = hb:battlerAt(pos)
      if b then out[b.mon] = true end
    end
    return out
  end
  -- only the two on the field are left: nobody to switch to
  for i, mon in ipairs(hb.enemyParty) do if not onField()[mon] then mon.hp = 0 end end
  local act = TrainerAI.switchAction(hb)
  T.check(act == nil, "with only the two on the field, the foe does not switch (" ..
          tostring(act and act.index) .. ")")
  -- a third one on the bench: that is the one it goes to
  local extra = Pokemon.new(Data, "FIXMON_B", 20, function(a) return a end)
  hb.enemyParty[#hb.enemyParty + 1] = extra
  local act2 = TrainerAI.switchAction(hb)
  T.check(act2 and hb.enemyParty[act2.index] == extra, "the switch goes to the one on the bench")
end

T.finish("co-op items, late picks, revives and exp")
