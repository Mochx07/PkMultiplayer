-- CO-OP DOUBLES: SWITCHING, AND FOES THAT THINK.
--
-- The two-copy harness of coop_turn_rules.lua, asking about the switch rule
-- and the foes' doubles AI:
--   * a switch goes before every move, on both copies, and each player can
--     only send in one of their own three;
--   * both players switching in the same turn, and the copies still agree;
--   * a Pokemon held by a foe's WRAP cannot be recalled (Gen 2 / HGSS);
--   * the foes' AI takes the KO it can see, does not waste a status move on
--     a Pokemon that already has one, and two foes do not both pile onto a
--     target the first one is already finishing.
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
local DoublesAI = require("src.battle.DoublesAI")
local Json = require("src.link.Json")
require("src.coop.CoopLog").enabled = false
CoopBattle.AUTO_REPLACE = true

-- moves the fixture set does not carry
Data.moves.FIX_HYPNO = { id = "FIX_HYPNO", index = 90, name = "FIX HYPNO", type = "PSYCHIC",
                         power = 0, accuracy = 60, pp = 20, effect = "SLEEP_EFFECT" }
Data.moves.FIX_SPLASHY = { id = "FIX_SPLASHY", index = 91, name = "FIX SPLASHY", type = "NORMAL",
                           power = 0, accuracy = 100, pp = 40, effect = "SPLASH_EFFECT" }
Data.moves.FIX_SLAM = { id = "FIX_SLAM", index = 92, name = "FIX SLAM", type = "NORMAL",
                        power = 120, accuracy = 100, pp = 10, effect = "NO_ADDITIONAL_EFFECT" }
Data.moves.FIX_SHIELD = { id = "FIX_SHIELD", index = 93, name = "FIX SHIELD", type = "NORMAL",
                          power = 0, accuracy = 100, pp = 10, effect = "PROTECT_EFFECT",
                          target = 0x10 }

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

local function pickMove(b)
  local me = b:battlerAt(P.PLAYER_LEFT)
  if not me then return nil end
  local mv = me.curMoves[1]
  local foe = b:battlerAt(P.OPPONENT_LEFT)
  mv.targetPosition = (foe and foe.mon.hp > 0) and P.OPPONENT_LEFT or P.OPPONENT_RIGHT
  return mv
end

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
  CoopBattle.initBattle(hb, hostGame.save.party, guestWire, { name = "GUEST" }, seed, "SWITCH" .. seed)
  local gb = BattleState.newTrainer(guestGame, "OPP_FIX_YOUNGSTER", 1)
  gb.isCoopGuest = true
  guestGame.stack:push(gb)
  if record then record("guest", gb) end
  CoopBattle.initBattle(gb, guestGame.save.party, hostWire, { name = "HOST" }, seed, "SWITCH" .. seed)
  local function deliver(to)
    local q = bus[to]
    bus[to] = {}
    CoopBattle.currentBattle = (to == "host") and hb or gb
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m) end
    end
  end
  local function turn(hostAction, guestAction)
    sender = "host"; CoopBattle.currentBattle = hb
    local ha = hostAction and hostAction(hb) or pickMove(hb)
    if ha then CoopBattle.onLocalActionSelected(hb, ha) else CoopBattle.onSpectatorTurn(hb) end
    sender = "guest"; CoopBattle.currentBattle = gb
    local ga = guestAction and guestAction(gb) or pickMove(gb)
    if ga then CoopBattle.onLocalActionSelected(gb, ga) else CoopBattle.onSpectatorTurn(gb) end
    deliver("guest"); deliver("host")
    local r1, r2 = drain(hb), drain(gb)
    return r1 == "done" or r2 == "done" or hb.result or gb.result
  end
  drain(hb); drain(gb)
  return hb, gb, turn
end

local function species(b, pos)
  local x = b:battlerAt(pos)
  return x and x.mon and x.mon.species
end

-- the same four Pokemon on both copies, each player's own on their LEFT
local function agree(hb, gb)
  return species(hb, P.PLAYER_LEFT) == species(gb, P.PLAYER_RIGHT)
     and species(hb, P.PLAYER_RIGHT) == species(gb, P.PLAYER_LEFT)
     and species(hb, P.OPPONENT_LEFT) == species(gb, P.OPPONENT_LEFT)
     and species(hb, P.OPPONENT_RIGHT) == species(gb, P.OPPONENT_RIGHT)
end

local function switchTo(i)
  return function(b) return { special = "playerSwitch", mon = b.coopChosenMons[i] } end
end

-- ---------------------------------------------------------------------
-- switching
-- ---------------------------------------------------------------------

do
  local log = { host = {}, guest = {} }
  local function record(who, b)
    local exec = b.executeAction
    b.executeAction = function(self, user, target, action)
      if user and action then
        log[who][#log[who] + 1] = action.special == "playerSwitch" and "switch" or (action.id and "move") or "other"
      end
      return exec(self, user, target, action)
    end
  end
  local hb, gb, turn = setup(5151, 20, { "FIXMON_A", "FIXMON_B", "FIXMON_C" },
                             { "FIXMON_C", "FIXMON_A", "FIXMON_B" }, record)
  T.check(agree(hb, gb), "both copies open with the same four Pokemon")

  -- turn 1: the host switches to its second, the guest attacks
  turn(switchTo(2))
  T.check(species(hb, P.PLAYER_LEFT) == "FIXMON_B", "the host's own switch lands on the host's copy")
  T.check(species(gb, P.PLAYER_RIGHT) == "FIXMON_B", "...and on the guest's copy, in the partner slot")
  T.check(agree(hb, gb), "the copies agree after the host's switch")
  for _, who in ipairs({ "host", "guest" }) do
    T.check(log[who][1] == "switch", who .. "'s copy: the switch runs before every move")
  end

  -- turn 2: both switch at once
  log.host, log.guest = {}, {}
  turn(switchTo(3), switchTo(3))
  T.check(species(hb, P.PLAYER_LEFT) == "FIXMON_C" and species(hb, P.PLAYER_RIGHT) == "FIXMON_B",
          "both switching in one turn: each brings in their own third Pokemon")
  T.check(agree(hb, gb), "the copies agree after a double switch")
  for _, who in ipairs({ "host", "guest" }) do
    T.check(log[who][1] == "switch" and log[who][2] == "switch",
            who .. "'s copy: both switches come before the foes' moves")
  end

  -- the party a player picks from is their own three, never the partner's
  local own = {}
  for _, m in ipairs(hb.coopChosenMons) do own[m] = true end
  local leaked = false
  for _, m in ipairs(hb.ally.party or {}) do if own[m] then leaked = true end end
  T.check(not leaked, "the partner's Pokemon are not in the host's switch list")

  -- a fainted Pokemon cannot be sent in: the wire answer for it is refused
  local fainted = gb.ally.party[1]
  local savedHp = fainted.hp
  fainted.hp = 0
  local decoded = CoopBattle.decodeAction(gb, { kind = "switch", index = 1, species = fainted.species })
  T.check(decoded and decoded.mon == fainted,
          "a switch to a fainted Pokemon stays a no-op, the same one the partner's copy runs")
  local out = gb:battlerAt(P.PLAYER_RIGHT)
  local again = CoopBattle.decodeAction(gb, { kind = "switch", index = 99, species = out.mon.species })
  T.check(again == nil or again.mon ~= out.mon, "the species fallback never picks the Pokemon already out")
  fainted.hp = savedHp
end

-- a switch hides and poofs only its own slot, not the partner's too
do
  local hb = setup(3131, 20, { "FIXMON_A", "FIXMON_B", "FIXMON_C" }, { "FIXMON_C", "FIXMON_A", "FIXMON_B" })
  local function poofAt()
    for _, e in ipairs(hb.queue) do if e.anim == "POOF_ANIM" then return e.targetPosition end end
  end
  for _, case in ipairs({ { P.PLAYER_LEFT, hb.coopChosenMons[2], "the host's" },
                          { P.PLAYER_RIGHT, hb.ally.party[2], "the partner's" } }) do
    local pos, mon, who = case[1], case[2], case[3]
    hb.queue, hb.nextInsert = {}, 0
    local other = hb:battlerAt(pos == P.PLAYER_LEFT and P.PLAYER_RIGHT or P.PLAYER_LEFT)
    local incoming = hb:switchPlayerInto(pos, mon)
    T.check(incoming and hb:slotSendingOut(incoming), who .. " switch: the incoming Pokemon waits for its poof")
    T.check(not hb:slotSendingOut(other), who .. " switch: the other player's Pokemon stays on screen")
    T.check(not hb:sideArriving(true, 0) or hb:growInScale(hb.player) ~= nil,
            who .. " switch: the side is not 'arriving' as a whole")
    T.check(poofAt() == pos, who .. " switch: the poof lands on that slot (" .. tostring(poofAt()) .. ")")
    hb.sendingOut, hb.sendingOutSlot = false, nil
  end
end

-- ---------------------------------------------------------------------
-- WRAP holds you: "can't be recalled!"
-- ---------------------------------------------------------------------

do
  local hb, gb = setup(6262, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local me = hb:battlerAt(P.PLAYER_LEFT)
  T.check(hb:canRecall(me), "a free Pokemon can be recalled")
  local foe = hb:battlerAt(P.OPPONENT_LEFT)
  foe.trappingTurns = 2
  T.check(not hb:canRecall(me), "a Pokemon held by a foe's WRAP cannot be recalled")
  foe.trappingTurns = nil
end

-- ---------------------------------------------------------------------
-- MEAN LOOK holds you while its user stays out
-- ---------------------------------------------------------------------

do
  local MoveEffects = require("src.battle.MoveEffects")
  local hb = setup(6363, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local me = hb:battlerAt(P.PLAYER_LEFT)
  local foe = hb:battlerAt(P.OPPONENT_LEFT)
  local msgs = MoveEffects.primary.MEAN_LOOK_EFFECT(hb, foe, me)
  T.check(msgs and tostring(msgs[1]):find("run away"), "MEAN LOOK pins the Pokemon in")
  T.check(not hb:canRecall(me), "a Pokemon under MEAN LOOK cannot be recalled")
  msgs = MoveEffects.primary.MEAN_LOOK_EFFECT(hb, foe, me)
  T.check(tostring(msgs[1]):find("failed"), "a second MEAN LOOK on a held Pokemon fails")
  -- the holder leaves the field: a new battler stands in its slot
  local stand = {}
  for k, v in pairs(foe) do stand[k] = v end
  stand.trapped, stand.meanLookBy = nil, nil
  hb:placeBattler(P.OPPONENT_LEFT, stand)
  T.check(hb:canRecall(me), "the hold ends once the Pokemon that used MEAN LOOK has left")
  hb:placeBattler(P.OPPONENT_LEFT, foe)
  T.check(not hb:canRecall(me), "...and holds again while it is back out")
  foe.mon.hp = 0
  T.check(hb:canRecall(me), "a fainted holder lets go")
  foe.mon.hp = 10

  -- the foe's AI does not switch out of a hold either
  local TrainerAI = require("src.battle.TrainerAI")
  local mine = hb:battlerAt(P.PLAYER_LEFT)
  MoveEffects.primary.MEAN_LOOK_EFFECT(hb, mine, hb.enemy)
  T.check(TrainerAI.switchAction(hb) == nil, "a trainer cannot switch a held Pokemon out")
end

-- and from a wild battle there is no running
do
  local game = newGame("SOLO", { "FIXMON_A" }, 20)
  local b = BattleState.newWild(game, "FIXMON_B", 5)
  game.stack:push(b)
  drain(b)
  b.rng = function(a) return a end   -- every run roll would succeed
  local MoveEffects = require("src.battle.MoveEffects")
  MoveEffects.primary.MEAN_LOOK_EFFECT(b, b.enemy, b.player)
  b:tryRun()
  T.check(b.result ~= "run", "MEAN LOOK: a held Pokemon cannot run from a wild battle")
end

-- ---------------------------------------------------------------------
-- the foes think
-- ---------------------------------------------------------------------

local function foeMoves(b, pos, ids)
  local f = b:battlerAt(pos)
  f.curMoves = {}
  for i, id in ipairs(ids) do f.curMoves[i] = { id = id, pp = 10 } end
  return f
end

-- takes the KO it can see
do
  local hb = setup(7373, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local foe = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_TACKLE", "FIX_SPLASHY" })
  foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_SPLASHY" })  -- so the KO is this foe's to take
  local weak = hb:battlerAt(P.PLAYER_RIGHT)
  weak.mon.hp = 2
  local move, target = DoublesAI.choose(hb, foe, foe.curMoves)
  T.check(move and move.id == "FIX_TACKLE", "the foe attacks instead of splashing")
  T.check(target == weak, "the foe goes for the Pokemon it can knock out")
end

-- no sleep move on a Pokemon that is already asleep
do
  local hb = setup(8484, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local foe = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_HYPNO" , "FIX_TACKLE" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  l.mon.status, r.mon.status = "SLP", "SLP"
  local move = DoublesAI.choose(hb, foe, foe.curMoves)
  T.check(move and move.id == "FIX_TACKLE", "a sleep move is not wasted on two sleeping Pokemon")
  l.mon.status, r.mon.status = nil, nil
  local _, target = DoublesAI.choose(hb, foe, { foe.curMoves[1] })
  T.check(target ~= nil, "a status move still gets a target")
end

-- the second foe does not overkill what the first is finishing
do
  local hb = setup(9595, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_SLAM" })
  local f2 = foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_SLAM" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  l.mon.hp = 3
  DoublesAI.beginTurn(hb)
  local _, t1 = DoublesAI.choose(hb, f1, f1.curMoves)
  local _, t2 = DoublesAI.choose(hb, f2, f2.curMoves)
  T.check(t1 == l, "the first foe takes the KO on the weakened Pokemon")
  T.check(t2 == r, "the second foe aims at the other Pokemon instead of piling on")
end

-- they gang up on a Pokemon neither could knock out alone
do
  local hb = setup(4141, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_TACKLE" })
  local f2 = foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_TACKLE" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  local tackle = Data.moves.FIX_TACKLE
  local d1 = DoublesAI.estimate(hb, f1, r, tackle, false)
  local d2 = DoublesAI.estimate(hb, f2, r, tackle, false)
  r.mon.hp = math.max(d1, d2) + 1            -- one TACKLE is not enough...
  T.check(d1 + d2 >= r.mon.hp, "fixture: two TACKLEs finish it")
  r.curStats.hp = 999                         -- ...and a sliver of its bar, so a lone hit
                                              -- looks better spent on l
  local dl = DoublesAI.estimate(hb, f1, l, tackle, false) + DoublesAI.estimate(hb, f2, l, tackle, false)
  T.check(dl < l.mon.hp, "fixture: l survives both")
  DoublesAI.beginTurn(hb)
  local _, t1 = DoublesAI.choose(hb, f1, f1.curMoves)
  local _, t2 = DoublesAI.choose(hb, f2, f2.curMoves)
  T.check(t1 == r and t2 == r, "both foes hit the Pokemon only the two of them can finish")
end

-- the dangerous Pokemon goes first, not just the frail one
do
  local hb = setup(5252, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_TACKLE" })
  foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_SPLASHY" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  foeMoves(hb, P.PLAYER_LEFT, { "FIX_SLAM" })     -- hits hard
  foeMoves(hb, P.PLAYER_RIGHT, { "FIX_SPLASHY" }) -- harmless
  l.mon.hp, r.mon.hp = 1, 2                   -- the harmless one even has more to take
  DoublesAI.beginTurn(hb)
  local _, t1 = DoublesAI.choose(hb, f1, f1.curMoves)
  T.check(t1 == l, "the foe knocks out the threat over the harmless one")
end

-- PROTECT when it is about to be knocked out first, and its partner is there
do
  local hb = setup(6363, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_SHIELD", "FIX_TACKLE" })
  foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_TACKLE" })
  local l, r = hb:battlerAt(P.PLAYER_LEFT), hb:battlerAt(P.PLAYER_RIGHT)
  foeMoves(hb, P.PLAYER_LEFT, { "FIX_SLAM" })
  foeMoves(hb, P.PLAYER_RIGHT, { "FIX_SPLASHY" })
  l.curStats.speed, f1.curStats.speed = 999, 1
  l.curStats.attack = 999
  local cap = f1.curStats.hp
  f1.mon.hp = math.floor(cap / 2)              -- healthy enough that the old AI never shielded
  T.check(DoublesAI.estimate(hb, l, f1, Data.moves.FIX_SLAM, false) >= f1.mon.hp,
          "fixture: the faster SLAM knocks it out")
  DoublesAI.beginTurn(hb)
  local move = DoublesAI.choose(hb, f1, f1.curMoves)
  T.check(move and move.id == "FIX_SHIELD", "a doomed foe shields instead of trading blows")
end

-- two foes do not both put the same Pokemon to sleep
do
  local hb = setup(7474, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local f1 = foeMoves(hb, P.OPPONENT_LEFT, { "FIX_HYPNO" })
  local f2 = foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_HYPNO" })
  DoublesAI.beginTurn(hb)
  local _, t1 = DoublesAI.choose(hb, f1, f1.curMoves)
  local _, t2 = DoublesAI.choose(hb, f2, f2.curMoves)
  T.check(t1 and t2 and t1 ~= t2, "the two sleep moves go to different Pokemon")
end

-- the same plan on both copies of one battle
do
  local hb, gb = setup(8585, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local picks = {}
  for _, b in ipairs({ hb, gb }) do
    DoublesAI.beginTurn(b)
    local out = {}
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local f = b:battlerAt(pos)
      local mv, t = DoublesAI.choose(b, f, f.curMoves)
      out[#out + 1] = (mv and mv.id or "-") .. "@" .. (t and t.mon.species or "-")
    end
    picks[#picks + 1] = table.concat(out, ",")
  end
  T.check(picks[1] == picks[2], "host and guest plan the very same turn (" .. picks[1] .. ")")
end

-- a hit aimed at a Pokemon that switched out lands on the one that came in
do
  local hb, gb, turn = setup(6161, 20, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  foeMoves(hb, P.OPPONENT_LEFT, { "FIX_SLAM" }); foeMoves(hb, P.OPPONENT_RIGHT, { "FIX_SLAM" })
  foeMoves(gb, P.OPPONENT_LEFT, { "FIX_SLAM" }); foeMoves(gb, P.OPPONENT_RIGHT, { "FIX_SLAM" })
  -- the guest's Pokemon shrugs everything off, so both foes aim at the host's lead
  hb:battlerAt(P.PLAYER_RIGHT).curStats.defense = 999
  gb:battlerAt(P.PLAYER_LEFT).curStats.defense = 999
  local leaving = hb:battlerAt(P.PLAYER_LEFT).mon
  local before = leaving.hp
  turn(switchTo(2))
  local incoming = hb:battlerAt(P.PLAYER_LEFT)
  T.check(incoming.mon ~= leaving, "fixture: the host's second Pokemon came in")
  T.check(leaving.hp == before, "the Pokemon that switched out takes nothing on the bench")
  T.check(incoming.mon.hp < incoming.curStats.hp, "the Pokemon that came in takes the hit")
  T.check(gb:battlerAt(P.PLAYER_RIGHT).mon.hp == incoming.mon.hp, "...the same on the guest's copy")

  -- and the lookup on its own: a stale choice resolves to the slot's battler
  local Targeting = require("src.battle.Targeting")
  local foe = hb:battlerAt(P.OPPONENT_LEFT)
  local stale = { mon = leaving, position = P.PLAYER_LEFT }
  local got = Targeting.resolve(hb, foe, Data.moves.FIX_SLAM, stale)
  T.check(got[1] == incoming, "Targeting.resolve aims at whoever stands in the chosen spot")
end

-- and both copies of a whole battle still agree with the AI choosing
do
  local hb, gb, turn = setup(1212, 12, { "FIXMON_A", "FIXMON_B" }, { "FIXMON_C", "FIXMON_A" })
  local same = true
  for _ = 1, 15 do
    if turn() then break end
    if not agree(hb, gb) then same = false end
    for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
      local a, c = hb:battlerAt(pos), gb:battlerAt(pos)
      if (a and a.mon.hp) ~= (c and c.mon.hp) then same = false end
    end
    local hl, gr = hb:battlerAt(P.PLAYER_LEFT), gb:battlerAt(P.PLAYER_RIGHT)
    if (hl and hl.mon.hp) ~= (gr and gr.mon.hp) then same = false end
  end
  T.check(same, "with the doubles AI choosing, both copies stay in lockstep")
end

T.finish("co-op doubles switching and foe AI")
