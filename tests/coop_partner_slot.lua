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

T.finish("co-op double: the partner's Pokemon fell on their screen only")
