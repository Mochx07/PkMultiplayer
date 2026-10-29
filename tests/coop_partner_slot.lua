-- CO-OP DOUBLES: THE PARTNER'S POKEMON FELL ON THEIR SCREEN ONLY.
--
-- Reported from play (log 2026-10-28 00:19-00:24): the partner's BOLA sat
-- in its slot at 0/50 HP, half sunk, for the rest of the battle, while on
-- their screen they were fighting with the QUILAVA they had sent in after
-- it.  The copies had drifted on the turn it fell: this one never ran the
-- faint, so their pick (coop_battle_replace) stayed in replaceQueue, and
-- their own word on their Pokemon (applyPartnerState) later wrote the 0 HP
-- onto the one still standing here.  CoopBattle.alignPartnerSlot puts their
-- queued pick in when the turn opens.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_partner_slot.lua
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
CoopManager.balancedFoes, CoopManager.hardFoes = false, false
require("src.coop.CoopLog").enabled = false
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

CoopManager.connected = true
CoopManager.net = { send = function() end, isLinked = function() return true end, flush = function() end }
CoopManager.isConnected = function() return true end

-- the host's copy, with the partner's FIXMON_C in front and FIXMON_B behind
local function hostCopy(partnerSpecies)
  local hostGame = newGame("HOST", { "FIXMON_A", "FIXMON_B" }, 20)
  local partnerGame = newGame("GUEST", partnerSpecies, 20)
  local wire = {}
  for i, m in ipairs(partnerGame.save.party) do wire[i] = CoopManager.wireMon(m) end
  local battle = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  hostGame.stack:push(battle)
  CoopBattle.initBattle(battle, hostGame.save.party, wire, { name = "GUEST" }, 1234, "SLOT")
  return battle
end

-- their state as it rides with their action: their first one is down
local function theirState(battle, hps)
  local out = {}
  for i, mon in ipairs(battle.ally.party) do
    out[i] = { species = mon.species, level = mon.level, exp = mon.exp, hp = hps[i] or mon.hp,
               status = mon.status, stats = mon.stats, statExp = mon.statExp, moves = {} }
    for j, mv in ipairs(mon.moves or {}) do out[i].moves[j] = { id = mv.id, pp = mv.pp } end
  end
  return out
end

-- their pick is queued: it goes in as the turn opens
do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  local front = battle:battlerAt(P.PLAYER_RIGHT)
  T.check(front and front.mon == battle.ally.party[1], "the partner's first Pokemon starts in their slot")
  CoopBattle.onPartnerReplace({ inviteId = "SLOT", index = 2, species = "FIXMON_B" })
  CoopBattle.applyPartnerState(battle, theirState(battle, { 0 }))
  CoopBattle.alignPartnerSlot(battle)
  local now = battle:battlerAt(P.PLAYER_RIGHT)
  T.check(now and now.mon == battle.ally.party[2], "their queued pick is in the slot")
  T.check(now and now.ally, "...on the partner's side")
  T.check(#battle.coop.replaceQueue == 0, "...and taken off the queue")
  T.check(battle:battlerAt(P.PLAYER_LEFT) ~= nil, "our own Pokemon is untouched")
end

-- no pick yet, but they have one to make: the slot empties and waits
do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  CoopBattle.applyPartnerState(battle, theirState(battle, { 0 }))
  CoopBattle.alignPartnerSlot(battle)
  T.check(battle:battlerAt(P.PLAYER_RIGHT) == nil, "with no pick yet, the fallen one leaves the slot")
  local queued = false
  for _, pos in ipairs(battle.pendingReplacements or {}) do queued = queued or pos == P.PLAYER_RIGHT end
  T.check(queued, "...and the end of the turn waits for their pick")
end

-- nobody left: the slot just empties
do
  local battle = hostCopy({ "FIXMON_C" })
  CoopBattle.applyPartnerState(battle, theirState(battle, { 0 }))
  CoopBattle.alignPartnerSlot(battle)
  T.check(battle:battlerAt(P.PLAYER_RIGHT) == nil, "a partner with nobody left leaves an empty slot")
  T.check(not battle.pendingReplacements or #battle.pendingReplacements == 0, "...with nothing to wait for")
end

-- the normal case changes nothing
do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  CoopBattle.onPartnerReplace({ inviteId = "SLOT", index = 2, species = "FIXMON_B" })
  local before = battle:battlerAt(P.PLAYER_RIGHT)
  CoopBattle.applyPartnerState(battle, theirState(battle, {}))
  CoopBattle.alignPartnerSlot(battle)
  T.check(battle:battlerAt(P.PLAYER_RIGHT) == before, "a partner Pokemon still standing stays")
  T.check(#battle.coop.replaceQueue == 1, "...and a pick for a later faint stays queued")
end

-- NOBODY STANDING ON OUR SIDE as a turn starts (logs 2026-10-28 22:29: the
-- battle played hundreds of empty turns a second after the AI took over)
local function emptyOurSide(battle)
  for _, pos in ipairs({ P.PLAYER_LEFT, P.PLAYER_RIGHT }) do
    local b = battle:battlerAt(pos)
    if b then b.mon.hp = 0 battle:placeBattler(pos, nil) end
  end
  battle:syncSides()
end

do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  emptyOurSide(battle)
  for _, m in ipairs(battle.coopChosenMons) do m.hp = 0 end
  local partnerSecond = battle.ally.party[2]
  T.check((partnerSecond.hp or 0) > 0, "the partner still has one healthy on the bench")
  T.check(CoopBattle.guardEmptySide(battle) == false and battle:battlerAt(P.PLAYER_RIGHT) == nil,
          "one empty turn is left to the engine (its replacements may still be coming)")
  T.check(CoopBattle.guardEmptySide(battle) == false, "with somebody on a bench the turn goes on")
  local now = battle:battlerAt(P.PLAYER_RIGHT)
  T.check(now and now.mon == partnerSecond and now.ally, "...and that Pokemon is sent in to the partner's slot")
  T.check(battle:battlerAt(P.PLAYER_LEFT) == nil, "our own slot stays empty: we have nobody left")
end

do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  emptyOurSide(battle)
  for _, m in ipairs(battle.coopChosenMons) do m.hp = 0 end
  for _, m in ipairs(battle.ally.party) do m.hp = 0 end
  CoopBattle.guardEmptySide(battle)
  T.check(CoopBattle.guardEmptySide(battle) == true, "with nobody left anywhere the turn does not run")
  T.check(battle.result == "lose" or (battle.coop.forceResult == "lose"), "...and the battle is lost")
end

do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  local left, right = battle:battlerAt(P.PLAYER_LEFT), battle:battlerAt(P.PLAYER_RIGHT)
  CoopBattle.guardEmptySide(battle)
  T.check(CoopBattle.guardEmptySide(battle) == false, "a side with Pokemon standing is left alone")
  T.check(battle:battlerAt(P.PLAYER_LEFT) == left and battle:battlerAt(P.PLAYER_RIGHT) == right, "...untouched")
end

-- THE OTHER WAY ROUND: their Pokemon fell on THIS screen only.  Reported
-- from play (2026-10-28 23:07): each screen waited on the other -- one for
-- the partner's pick after a faint, the other for this player's move.  Their
-- next move arriving instead of a pick puts their Pokemon back.
do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  local c = battle.coop
  local theirs = battle.ally.party[1]
  local placed
  local wait = CoopBattle.newReplaceWait(battle, P.PLAYER_RIGHT, function(mon) placed = mon end)
  theirs.hp = 0
  battle:placeBattler(P.PLAYER_RIGHT, nil) -- the faint took it off, on this copy
  wait:update(0.1)
  T.check(placed == nil, "waiting for their pick, with nothing from them yet")
  c.partnerActions[c.turn] = { kind = "move", slot = 1 }
  c.partnerStates[c.turn] = theirState(battle, { 30 })
  c.partnerActives = { [c.turn] = 1 }
  wait:update(0.1)
  T.check(placed == theirs and theirs.hp == 30, "their move instead of a pick: the one they say is in their slot goes back in")
end

-- THE DIFFICULTY THE INVITE CARRIES.  Reported from play (2026-10-28 23:07):
-- one copy padded a trainer to four Pokemon and a level up, the other kept
-- its three -- each used its own BALANCED FOES.  Both copies now use the
-- rules the invite carries.
do
  local CoopBalance = require("src.coop.CoopBalance")
  local foes = { { hp = 30, level = 20 } }
  local mine = { { hp = 40, level = 25 }, { hp = 40, level = 25 }, { hp = 40, level = 25 } }
  local theirs = { { hp = 40, level = 25 }, { hp = 40, level = 25 }, { hp = 40, level = 25 } }
  CoopManager.balancedFoes, CoopManager.hardFoes = false, false
  local plan = CoopBalance.plan(foes, mine, theirs, { balancedFoes = true, hardFoes = false })
  T.check(plan and plan.foes == 4, "the invite's BALANCED FOES pads the trainer even where this game has it off")
  CoopManager.balancedFoes = true
  T.check(CoopBalance.plan(foes, mine, theirs, { balancedFoes = false, hardFoes = false }) == nil,
          "...and an invite with it off keeps the cartridge's team even where this game has it on")
  CoopManager.balancedFoes = false
  T.check(CoopBalance.currentRules().balancedFoes == false, "the inviter sends its own rules")
end

-- WHAT THE PARTNER IS GOING TO DO (requested from play: "you should know
-- which attack the other player is going to use", "and items")
do
  local battle = hostCopy({ "FIXMON_C", "FIXMON_B" })
  local c = battle.coop
  CoopManager.partner = CoopManager.partner or {}
  CoopManager.partner.name = "Toby"
  local plan = CoopBattle.partnerPlan(battle)
  T.check(plan and plan[1] == "TOBY" and plan[2] and plan[2]:find("CHOOSING"), "before they choose: their name, still choosing")
  local ally = battle:battlerAt(P.PLAYER_RIGHT)
  local mv = ally.curMoves[1]
  c.partnerActions[c.turn] = { kind = "move", id = mv.id, slot = 1, target = P.OPPONENT_LEFT }
  plan = CoopBattle.partnerPlan(battle)
  local foe = battle:battlerAt(P.OPPONENT_LEFT)
  T.check(plan[2] and plan[2] ~= "" and plan[3] and plan[3]:find(foe.name, 1, true), "a move: its name and the foe it is aimed at")
  c.partnerActions[c.turn] = { kind = "item", id = "POTION", targetNick = "FIXMON_C" }
  plan = CoopBattle.partnerPlan(battle)
  T.check(plan[2] and plan[3] and plan[3]:find("FIXMON_C", 1, true), "an item: which one and who it is for")
  c.partnerActions[c.turn] = { kind = "switch", index = 2, species = "FIXMON_B" }
  plan = CoopBattle.partnerPlan(battle)
  T.check(plan[3] and plan[3]:find(">", 1, true), "a switch: who comes in")
  c.partnerLost = true
  T.check(CoopBattle.partnerPlan(battle) == nil, "with the AI playing for them there is nothing to say")
end

-- PLAYER MON FAINTED WITH FULL SAVE PARTY BUT WIPED CO-OP SQUAD:
-- Reported from play (log 2026-10-28 01:29): player brought 3 Pokemon, all
-- fainted, while party slots 4-6 still had full HP in save.party.
-- playerMonFainted must check coopChosenMons and sideCanContinue rather than
-- save.party, so it does not ignore the defeat and spin in a spectator loop.
do
  local battle = hostCopy({ "FIXMON_C" })
  local extraMon = Pokemon.new(Data, "FIXMON_B", 20, function(a) return a end)
  table.insert(battle.game.save.party, extraMon)
  battle.coopChosenMons = { battle.game.save.party[1] }
  T.check(#battle.game.save.party > #battle.coopChosenMons, "player has unchosen healthy Pokemon in save party")

  -- When player's chosen mons are fainted but partner is still alive: spectator mode
  for _, m in ipairs(battle.coopChosenMons) do m.hp = 0 end
  battle:playerMonFainted()
  T.check(battle.result == nil, "with ally still fighting, playerMonFainted does not trigger blackout")

  -- When partner is ALSO fainted: entire side cannot continue, so it must blackout and lose
  for _, m in ipairs(battle.ally.party) do m.hp = 0 end
  emptyOurSide(battle)
  battle:playerMonFainted()
  T.check(battle.result == "lose", "when whole side is down, playerMonFainted loses despite unchosen mons in save party")
  T.check(battle.afterQueue == "finish", "...and queues battle finish")
end

-- SPECTATOR TURN WITH PARTNER LOST DOES NOT LOOP WHEN SIDE CANNOT CONTINUE
do
  local battle = hostCopy({ "FIXMON_C" })
  local c = battle.coop
  c.partnerLost = true
  emptyOurSide(battle)
  for _, m in ipairs(battle.coopChosenMons) do m.hp = 0 end
  for _, m in ipairs(battle.ally.party) do m.hp = 0 end
  CoopBattle.onSpectatorTurn(battle)
  T.check(battle.result == "lose" or c.finished, "onSpectatorTurn immediately finishes when side cannot continue")
end

T.finish("co-op double: the partner's Pokemon fell on their screen only")
