-- CO-OP DOUBLES KEEP EVERY STATUS IN LOCKSTEP.
--
-- Reported from play: one screen showed a Pokemon confused and the other
-- did not.  HP was being corrected by the host after every turn, which hid
-- that the two copies had drifted apart; confusion, sleep counters, Wrap and
-- the rest were not.  Two causes, both found by this suite:
--   * a Wrap held a foe on one copy only (fightLockedAction asked "the
--     player", which is each copy's own Pokemon), so that foe chose a move --
--     drawing from the RNG -- on one screen and not on the other;
--   * the end-of-turn sweep walked the field in position order, the two
--     players' Pokemon the other way round on each copy (Leech Seed healing
--     a foe that poison then hurt).
-- Movesets come from the player's imported Gold data (status-heavy pool);
-- every scalar a battler carries is compared, mirrored, after every turn.
-- Skipped when no Gold import is found (PKM_GOLD_MOVES=<moves.lua>).
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local GOLD = os.getenv("PKM_GOLD_MOVES")
if not GOLD then
  for _, id in ipairs({ "Gen2Recomp", "PkMultiplayerTest", "PkMultiplayerTest2" }) do
    local p = (os.getenv("HOME") or "") .. "/.local/share/love/" .. id .. "/gold/data/generated/moves.lua"
    local f = io.open(p, "rb")
    if f then f:close() GOLD = p break end
  end
end
if not GOLD then
  print("SKIP co-op status lockstep: no Gold import (set PKM_GOLD_MOVES)")
  return
end
local real = dofile(GOLD)
for id, m in pairs(real) do if not Data.moves[id] then Data.moves[id] = m end end
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
CoopBattle.AUTO_REPLACE = true
local P = BattleState.POS
local Json = require("src.link.Json")
local function onWire(m) return Json.decode(Json.encode(m)) end

local POOL = os.getenv("POOL") and {} or { "CONFUSE_RAY", "SUPERSONIC", "CONFUSION", "PSYBEAM", "DYNAMICPUNCH", "SWAGGER",
  "THUNDER_WAVE", "POISONPOWDER", "SLEEP_POWDER", "TOXIC", "LEECH_SEED", "GROWL", "TACKLE", "EMBER",
  "BITE", "HEADBUTT", "SAND_ATTACK", "DOUBLE_TEAM", "PROTECT", "THRASH", "ATTRACT", "MEAN_LOOK",
  "WRAP", "FOCUS_ENERGY", "SUBSTITUTE", "REST", "SAFEGUARD", "LIGHT_SCREEN", "DISABLE", "ENCORE",
  "SING", "HYPNOSIS", "SWEET_KISS", "ROLLOUT", "FURY_CUTTER", "CURSE", "NIGHTMARE", "PERISH_SONG",
  "FLAME_WHEEL", "THUNDERSHOCK", "ICE_PUNCH", "FURY_ATTACK", "DOUBLESLAP", "SKULL_BASH", "FLY" }
if os.getenv("POOL") then for m in os.getenv("POOL"):gmatch("[%w_]+") do POOL[#POOL + 1] = m end end
for _, id in ipairs(POOL) do assert(Data.moves[id], id) end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local rnd
local function moveset()
  local out, seen = {}, {}
  while #out < 4 do
    local id = POOL[rnd(#POOL)]
    if not seen[id] then seen[id] = true out[#out + 1] = { id = id, pp = Data.moves[id].pp } end
  end
  return out
end
local function newGame(name, species, level)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = {}
  for i, sp in ipairs(species) do
    local m = Pokemon.new(Data, sp, level, function(a) return a end)
    m.moves = moveset()
    save.party[i] = m
  end
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

local SKIP = { position = true, isPlayer = true, ally = true, shownHP = true, x = true, y = true,
  picX = true, picY = true, name = true, drainFloor = true, drainHold = true }
local function scalarFields(b)
  local out = {}
  if not b then return out end
  for k, v in pairs(b) do
    local t = type(v)
    if (t == "number" or t == "string" or t == "boolean") and not SKIP[k] and not tostring(k):find("^shown")
       and not tostring(k):find("anim") and not tostring(k):find("draw") then
      out[k] = v
    elseif t == "table" and (k == "stages" or k == "statStages" or k == "statMods") then
      for kk, vv in pairs(v) do out[k .. "." .. kk] = vv end
    end
  end
  if b.mon then out["mon.hp"] = b.mon.hp out["mon.status"] = b.mon.status or "none" out["mon.species"] = b.mon.species end
  return out
end
local function diff(a, b)
  local fa, fb = scalarFields(a), scalarFields(b)
  local d = {}
  local keys = {}
  for k in pairs(fa) do keys[k] = true end
  for k in pairs(fb) do keys[k] = true end
  for k in pairs(keys) do
    if fa[k] ~= fb[k] then d[#d + 1] = ("%s: %s vs %s"):format(k, tostring(fa[k]), tostring(fb[k])) end
  end
  table.sort(d)
  return d
end

local function play(seed, level, tamper)
  local s = seed
  rnd = function(n) s = (s * 48271) % 2147483647 return 1 + (s % n) end
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
  local hb = BattleState.newTrainer(hostGame, "OPP_FIX_YOUNGSTER", 1)
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  -- same enemy movesets on both copies
  local em = {}
  for i, m in ipairs(hb.enemyParty) do em[i] = moveset() m.moves = em[i] end
  for i, m in ipairs(gb.enemyParty) do
    m.moves = {}
    for j, mv in ipairs(em[i]) do m.moves[j] = { id = mv.id, pp = mv.pp } end
  end
  hostGame.stack:push(hb)
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "LOCK")
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "LOCK")
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m)
      elseif m.type == "coop_battle_sync" then CoopBattle.onPartnerBattleSync(m) end
    end
  end
  local function pick(b, turn)
    local me = b:battlerAt(P.PLAYER_LEFT)
    if not me then return nil end
    local mv = me.curMoves[rnd(#me.curMoves)]
    local tgt = rnd(3)
    if tgt == 3 then mv.targetPosition = P.PLAYER_RIGHT
    else
      local foe = b:battlerAt(tgt == 1 and P.OPPONENT_LEFT or P.OPPONENT_RIGHT)
      mv.targetPosition = (foe and foe.mon.hp > 0) and foe.position or nil
    end
    return mv
  end
  local function compare(turn)
    local bad = {}
    for _, pr in ipairs({ { P.PLAYER_LEFT, P.PLAYER_RIGHT, "hostMon" }, { P.PLAYER_RIGHT, P.PLAYER_LEFT, "guestMon" },
                          { P.OPPONENT_LEFT, P.OPPONENT_LEFT, "foeL" }, { P.OPPONENT_RIGHT, P.OPPONENT_RIGHT, "foeR" } }) do
      for _, d in ipairs(diff(hb:battlerAt(pr[1]), gb:battlerAt(pr[2]))) do bad[#bad + 1] = pr[3] .. " " .. d end
    end
    return bad
  end
  drain(hb); drain(gb)
  for turn = 1, 25 do
    if hb.result or gb.result then break end
    sender = "host"; CoopBattle.currentBattle = hb
    local function choose(b)
      local me = b:battlerAt(P.PLAYER_LEFT)
      if not me then return CoopBattle.onSpectatorTurn(b) end
      local locked = b:lockedAction(me)
      if locked then return b:submitTurnAction(locked, true) end
      return CoopBattle.onLocalActionSelected(b, pick(b, turn))
    end
    choose(hb)
    sender = "guest"; CoopBattle.currentBattle = gb
    choose(gb)
    deliver("guest"); deliver("host")
    -- whatever a copy sends while it plays the turn goes from that copy
    sender = "host"; CoopBattle.currentBattle = hb
    local ok1, r1 = pcall(drain, hb)
    sender = "guest"; CoopBattle.currentBattle = gb
    local ok2, r2 = pcall(drain, gb)
    sender = "host"
    if not ok1 or not ok2 then return turn, { "drain error: " .. tostring(r1) .. " / " .. tostring(r2) } end
    if tamper and turn == tamper then
      -- the guest's copy drifts: a foe's HP and a stat stage are off
      local foe = gb:battlerAt(P.OPPONENT_LEFT)
      if foe and foe.mon.hp > 1 then
        foe.mon.hp = foe.mon.hp - 1
        foe.stages = foe.stages or {}
        foe.stages.attack = (foe.stages.attack or 0) + 1
      end
    end
    deliver("guest")
    -- the guest applies host syncs between turns
    CoopBattle.currentBattle = gb
    CoopBattle.tick(0.016)
    local bad = compare(turn)
    if #bad > 0 then return turn, bad end
    if r1 == "done" or r2 == "done" then break end
  end
end

local N = tonumber(os.getenv("N") or "120")
local turnsPlayed = 0
CoopBattle.desyncs = 0
for i = 1, N do
  local seed = 1000 + i * 7919
  local level = 10 + (i % 4) * 5
  local bad, what = play(seed, level)
  T.check(bad == nil, ("seed %d lv %d: both copies agree on every battler%s"):format(seed, level,
          bad and (" (turn " .. bad .. ": " .. table.concat(what, "; ") .. ")") or ""))
end
-- true lockstep: the host's word never had to put the guest right
T.check(CoopBattle.desyncs == 0, ("no turn needed correcting (%d did)"):format(CoopBattle.desyncs))

-- ...and when a copy does drift, the turn's signatures catch it and the
-- host's state puts it right before the next turn
CoopBattle.desyncs = 0
local caught = 0
for i = 1, 6 do
  local before = CoopBattle.desyncs
  local bad, what = play(5000 + i * 104729, 20, 2)
  T.check(bad == nil, ("tampered seed %d: the copies agree again after the correction%s"):format(i,
          bad and (" (turn " .. bad .. ": " .. table.concat(what, "; ") .. ")") or ""))
  if CoopBattle.desyncs > before then caught = caught + 1 end
end
T.check(caught >= 5, ("a drifted copy is detected (%d of 6 games)"):format(caught))
T.finish("co-op status lockstep")
