-- CO-OP DOUBLES STAY IN LOCKSTEP.
--
-- Two real BattleStates -- the host's copy and the guest's -- fight the same
-- fixture trainer, driven through CoopBattle over an in-memory bus exactly
-- the way two machines would be.  After every turn both copies must agree on
-- every Pokemon's HP (mirrored: my LEFT is your RIGHT).
--
-- This is the suite that caught the desyncs the hand-rolled mocks never
-- could: resolveTurn's unused singles speed tie drawing from the RNG for a
-- pairing that differs per copy, and experience split differently on each
-- copy (so the partner's copy levelled late and hit for other numbers).
-- Against the real Gold data it also caught foesOf listing one Pokemon twice
-- and Future Sight landing on its own user; those paths are not reachable
-- with the fixture's movesets, so they are pinned by the code comments.
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
require("src.coop.CoopLog").enabled = false
-- nobody is here to answer a party screen: both copies take the first
-- healthy Pokemon (the interactive pick is covered by tests/test_coop.lua)
CoopBattle.AUTO_REPLACE = true

local P = BattleState.POS

-- WHAT CROSSES THE WIRE IS A COPY.  CoopNet sends JSON, so the receiver never
-- holds the sender's own tables; an in-memory bus that handed them over as
-- they were let a partner's copy share its owner's statExp/stats tables, and
-- one level-up then counted twice.  Round-trip through the same encoder.
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
    save.party[i] = Pokemon.new(Data, sp, level, function(a) return a end)
  end
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local function hpOf(b, pos) local x = b:battlerAt(pos); return x and x.mon and x.mon.hp or -1 end
local function lvOf(b, pos) local x = b:battlerAt(pos); return x and x.mon and x.mon.level end
local function spOf(b, pos) local x = b:battlerAt(pos); return x and x.mon and x.mon.species end

local function drain(b)
  for _ = 1, 20000 do
    if b.coop and b.coop.localReady then return end
    local top = b.game.stack:top()
    if top ~= b and top and top.update then
      top:update(1 / 60)          -- a level-up box; co-op closes it on a timer
    elseif not b:updateQueue() then
      return (b.afterQueue == "finish" or b.result) and "done" or nil
    end
  end
  error("battle queue never drained (phase " .. tostring(b.phase) .. ")")
end

local function pickMove(b, slot)
  local me = b:battlerAt(P.PLAYER_LEFT)
  if not me then return nil end
  local mv = me.curMoves[((slot - 1) % #me.curMoves) + 1]
  local foe = b:battlerAt(P.OPPONENT_LEFT)
  mv.targetPosition = (foe and foe.mon.hp > 0) and P.OPPONENT_LEFT or P.OPPONENT_RIGHT
  return mv
end

-- one full battle; returns turns played and the first turn that disagreed
local function play(seed, level)
  local hostGame = newGame("HOST", { "FIXMON_A", "FIXMON_B" }, level)
  local guestGame = newGame("GUEST", { "FIXMON_C", "FIXMON_B" }, level)

  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m) table.insert(bus[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end

  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end

  local maxBefore = {}
  for i, m in ipairs(hostGame.save.party) do maxBefore[i] = m.stats.hp end

  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "LOCK")
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "LOCK")

  local function pairOk(own, ownPos, copy, copyPos)
    -- strict: experience is split the same way on both copies, so the
    -- partner's copy levels on the same hit its owner's Pokemon does
    return lvOf(own, ownPos) == lvOf(copy, copyPos) and hpOf(own, ownPos) == hpOf(copy, copyPos)
  end
  local function agree()
    return pairOk(hb, P.PLAYER_LEFT, gb, P.PLAYER_RIGHT)
       and pairOk(gb, P.PLAYER_LEFT, hb, P.PLAYER_RIGHT)
       and hpOf(hb, P.OPPONENT_LEFT) == hpOf(gb, P.OPPONENT_LEFT)
       and hpOf(hb, P.OPPONENT_RIGHT) == hpOf(gb, P.OPPONENT_RIGHT)
       and spOf(hb, P.OPPONENT_LEFT) == spOf(gb, P.OPPONENT_LEFT)
       and spOf(hb, P.OPPONENT_RIGHT) == spOf(gb, P.OPPONENT_RIGHT)
  end
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end

  drain(hb); drain(gb)
  if not agree() then return 0, 0 end
  local turns = 0
  for turn = 1, 30 do
    if hb.result or gb.result then break end
    turns = turn
    sender = "host"; CoopBattle.currentBattle = hb
    local hm = pickMove(hb, turn)
    if hm then CoopBattle.onLocalActionSelected(hb, hm) else CoopBattle.onSpectatorTurn(hb) end
    sender = "guest"; CoopBattle.currentBattle = gb
    local gm = pickMove(gb, turn + 1)
    if gm then CoopBattle.onLocalActionSelected(gb, gm) else CoopBattle.onSpectatorTurn(gb) end
    deliver("guest"); deliver("host")
    local r1, r2 = drain(hb), drain(gb)
    if not agree() then return turns, turn end
    if r1 == "done" or r2 == "done" then break end
  end
  T.eq(hb.coop.turn, gb.coop.turn, "seed " .. seed .. " lv " .. level .. ": turn counters agree")
  -- a hit lowers HP, never the maximum (curStats IS mon.stats; writing the
  -- remaining HP into it shrank the bar's denominator for good)
  for i, m in ipairs(hostGame.save.party) do
    if m.level == level then
      T.eq(m.stats.hp, maxBefore[i], "seed " .. seed .. " lv " .. level .. ": max HP of party mon " .. i .. " untouched")
    end
  end
  return turns, nil
end

local played, battles = 0, 0
-- 777 at level 4 is the pairing that exposed the singles speed-tie draw
local SEEDS = { 777, 7919, 15838, 23757, 31676, 39595, 47514, 55433 }
for _, level in ipairs({ 3, 4, 5, 8, 12 }) do
  for _, seed in ipairs(SEEDS) do
    local turns, bad = play(seed, level)
    battles = battles + 1
    played = played + turns
    T.check(bad == nil, string.format("seed %d lv %d: both copies agree every turn%s",
            seed, level, bad and (" (diverged on turn " .. bad .. ")") or ""))
  end
end
T.check(played > battles * 2, "the battles actually ran (" .. played .. " turns over " .. battles .. " battles)")

-- ---------------------------------------------------------------------
-- INTERACTIVE REPLACEMENTS: each player picks their own fallen slot (the
-- LAST healthy one, so it differs from the old automatic rule), the other
-- copy waits for it.  The two copies step interleaved so the pick can cross
-- mid-turn, exactly as it does over the network.
-- ---------------------------------------------------------------------

local function playInteractive(seed, level)
  CoopBattle.AUTO_REPLACE = false
  local hostGame = newGame("HOST", { "FIXMON_A", "FIXMON_B", "FIXMON_C" }, level)
  local guestGame = newGame("GUEST", { "FIXMON_C", "FIXMON_B", "FIXMON_A" }, level)
  local inbox = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m) table.insert(inbox[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "LOCKI")
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "LOCKI")
  local sides = { host = hb, guest = gb }
  local picks = 0

  local function deliver(to)
    local q = inbox[to]
    inbox[to] = {}
    CoopBattle.currentBattle = sides[to]
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m)
      elseif m.type == "coop_battle_replace" then CoopBattle.onPartnerReplace(m) end
    end
  end
  -- one step of one copy; true while it still has work before the menu
  local function step(who)
    local b = sides[who]
    sender = who
    CoopBattle.currentBattle = b
    if b.coop.localReady or b.result then return false end
    local top = b.game.stack:top()
    if top ~= b and top and top.forceSwitch and top.onSwitch then
      local pick
      for i = #b.coopChosenMons, 1, -1 do
        local m = b.coopChosenMons[i]
        local onField = false
        for p = 0, 3 do local x = b:battlerAt(p); if x and x.mon == m then onField = true end end
        if (m.hp or 0) > 0 and not onField then pick = m break end
      end
      b.game.stack:pop()
      top.onSwitch(pick, top)
      picks = picks + 1
      return true
    elseif top ~= b and top and top.update then
      top:update(1 / 60)
      return true
    end
    return b:updateQueue()
  end
  local function settle()
    for _ = 1, 40000 do
      local a = step("host"); deliver("host")
      local g = step("guest"); deliver("guest")
      if not a and not g then return end
    end
    error("copies never settled")
  end
  local function agree()
    for _, pr in ipairs({ { P.PLAYER_LEFT, P.PLAYER_RIGHT }, { P.PLAYER_RIGHT, P.PLAYER_LEFT },
                           { P.OPPONENT_LEFT, P.OPPONENT_LEFT }, { P.OPPONENT_RIGHT, P.OPPONENT_RIGHT } }) do
      if spOf(hb, pr[1]) ~= spOf(gb, pr[2]) or hpOf(hb, pr[1]) ~= hpOf(gb, pr[2]) then return false end
    end
    return true
  end

  settle()
  for turn = 1, 30 do
    if hb.result or gb.result then break end
    sender = "host"; CoopBattle.currentBattle = hb
    local hm = pickMove(hb, turn)
    if hm then CoopBattle.onLocalActionSelected(hb, hm) else CoopBattle.onSpectatorTurn(hb) end
    sender = "guest"; CoopBattle.currentBattle = gb
    local gm = pickMove(gb, turn + 1)
    if gm then CoopBattle.onLocalActionSelected(gb, gm) else CoopBattle.onSpectatorTurn(gb) end
    deliver("guest"); deliver("host")
    settle()
    if not agree() then return turn, picks end
  end
  return nil, picks
end

local totalPicks = 0
for _, level in ipairs({ 3, 4, 5 }) do
  for _, seed in ipairs({ 777, 7919, 15838 }) do
    local bad, picks = playInteractive(seed, level)
    totalPicks = totalPicks + picks
    T.check(bad == nil, string.format("interactive seed %d lv %d: same Pokemon and HP on both screens%s",
            seed, level, bad and (" (diverged on turn " .. bad .. ")") or ""))
  end
end
T.check(totalPicks > 0, "players actually picked replacements (" .. totalPicks .. ")")
CoopBattle.AUTO_REPLACE = true


-- ---------------------------------------------------------------------
-- THE BAG REACHES THE PARTNER'S POKEMON.  The host uses a POTION on the
-- guest's Pokemon; the heal rides with the host's action and both copies
-- write it in as the turn opens -- also when the guest's own action, sent
-- before it heard of the potion, still carries the old HP.
-- ---------------------------------------------------------------------

do
  local hostGame = newGame("HOST", { "FIXMON_A", "FIXMON_B" }, 8)
  local guestGame = newGame("GUEST", { "FIXMON_C", "FIXMON_B" }, 8)
  local hurt = guestGame.save.party[1]
  hurt.hp = 3
  local bus = { host = {}, guest = {} }
  local sender = "host"
  CoopManager.connected = true
  CoopManager.net = { send = function(_, m) table.insert(bus[sender == "host" and "guest" or "host"], onWire(m)) end,
                      isLinked = function() return true end, flush = function() end }
  CoopManager.isConnected = function() return true end
  local hostWire, guestWire = {}, {}
  for i, m in ipairs(hostGame.save.party) do hostWire[i] = CoopManager.wireMon(m) end
  for i, m in ipairs(guestGame.save.party) do guestWire[i] = CoopManager.wireMon(m) end
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, 4242, "BAG")
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, 4242, "BAG")
  drain(hb); drain(gb)

  local seen = {}
  local realApply = CoopBattle.applyItemHeal
  CoopBattle.applyItemHeal = function(battle, heal, mine)
    realApply(battle, heal, mine)
    local list = mine and battle.coopChosenMons or battle.ally.party
    seen[battle == hb and "host" or "guest"] = list[heal.index].hp
  end
  -- the guest chooses first: its state still says 3 HP
  sender = "guest"; CoopBattle.currentBattle = gb
  CoopBattle.onLocalActionSelected(gb, pickMove(gb, 1))
  -- the host's bag: a POTION on the guest's Pokemon (+20)
  sender = "host"; CoopBattle.currentBattle = hb
  local copy = hb.ally.party[1]
  copy.hp = math.min(copy.stats.hp, copy.hp + 20)
  local heal = CoopBattle.itemHeal(hb, copy)
  T.check(heal and heal.side == "ally" and heal.index == 1, "the host's heal names the guest's first Pokemon")
  CoopBattle.onLocalActionSelected(hb, { special = "playerItem", id = "POTION", target = copy,
                                         targetNick = "X", messages = { "Used POTION!" }, heal = heal })
  deliver = function(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  deliver("guest"); deliver("host")
  drain(hb); drain(gb)
  CoopBattle.applyItemHeal = realApply
  T.eq(seen.host, 23, "host's copy: the guest's Pokemon at 23 HP as the turn opens")
  T.eq(seen.guest, 23, "guest's copy: their own Pokemon at 23 HP as the turn opens")
  T.check(hurt.hp > 3, "the guest's real Pokemon (their save) was healed")
  T.eq(hpOf(hb, P.PLAYER_RIGHT), hpOf(gb, P.PLAYER_LEFT), "both copies agree after the turn")
end

T.finish("co-op doubles lockstep")
