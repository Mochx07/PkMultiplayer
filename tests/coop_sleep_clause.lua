-- THE SLEEP CLAUSE (1.20, src/coop/CoopSleepClause.lua): which battles play
-- under it, what counts and what does not, and that both copies of a link
-- battle and the replay's spectator fail the same move.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Input = T.link.prepare(Data)
local CoopManager = require("src.coop.CoopManager")
local CoopLink = require("src.coop.CoopLink")
local CoopVS = require("src.coop.CoopVS")
local CoopReplay = require("src.coop.CoopReplay")
local CoopSleepClause = require("src.coop.CoopSleepClause")
local I18n = require("src.coop.CoopI18n")
local Pokemon = require("src.pokemon.Pokemon")
local Protocol = require("src.link.Protocol")
local Net = require("src.link.Net")
local LinkBattle = require("src.link.LinkBattle")
local BattleState = require("src.battle.BattleState")
local SaveData = require("src.core.SaveData")
require("src.coop.CoopLog").enabled = false
CoopManager.showStatus = function() end

-- the fixture dataset has no sleep move and no REST
Data.moves.HYPNOSIS = { id = "HYPNOSIS", index = 95, name = "HYPNOSIS", type = "PSYCHIC",
                        power = 0, accuracy = 100, pp = 20, effect = "SLEEP_EFFECT" }
Data.moves.REST = { id = "REST", index = 156, name = "REST", type = "PSYCHIC",
                    power = 0, accuracy = 100, pp = 10, effect = "HEAL_EFFECT" }

local function mon(species, level, moves)
  local m = Pokemon.new(Data, species, level)
  if moves then
    m.moves = {}
    for _, id in ipairs(moves) do m.moves[#m.moves + 1] = { id = id, pp = Data.moves[id].pp } end
  end
  return m
end

-- ----------------------------------------------------- which battles
local F = CoopVS.FORMATS
T.check(CoopManager.CAPS[CoopSleepClause.CAP], "the clause is announced as a capability")
T.check(not F.free.rules, "FREE BATTLE has no rules, so no clause")
for _, id in ipairs({ "lv50", "lv100", "little", "mono" }) do
  T.check(F[id].rules and F[id].rules.sleep, id .. " plays under the sleep clause")
end
CoopManager.partner = { name = "TOBY", caps = {} }
T.check(not CoopSleepClause.agreed(F.lv50), "a partner without the clause: it stays off")
CoopManager.partner.caps = { [CoopSleepClause.CAP] = true }
T.check(CoopSleepClause.agreed(F.lv50), "both copies have it: LEVEL 50 is under the clause")
T.check(not CoopSleepClause.agreed(F.free) and not CoopSleepClause.agreed(nil), "never in a free battle")

-- the tunnel of a format battle carries it, and so does its recording
local function newGame(party)
  local save = SaveData.newGame()
  save.party = party
  return { data = Data, save = save, stack = { push = function() end } }
end
local g = newGame({ mon("FIXMON_A", 20) })
local t = CoopLink.newTunnel("L-sleep")
CoopReplay.start(t, { asker = true, myName = "MOCHI", theirName = "TOBY", format = "lv50" })
CoopVS.attach(t, g, F.lv50)
T.check(t.sleepClause and t.rec.sleepClause, "a LEVEL 50 tunnel and its recording are under the clause")
t.closed = true
CoopLink.adapter = nil
local tf = CoopLink.newTunnel("L-free")
CoopVS.attach(tf, g, F.free)
T.check(not tf.sleepClause, "a FREE BATTLE tunnel is not")
tf.closed = true
CoopManager.partner.caps = {}
local to = CoopLink.newTunnel("L-old")
CoopVS.attach(to, g, F.lv50)
T.check(to.vs and not to.sleepClause, "a LEVEL 50 battle with a partner that lacks it plays without it")
to.closed = true
CoopLink.adapter = nil
CoopManager.partner.caps = { [CoopSleepClause.CAP] = true }

local r = CoopReplay.build({ asker = true, myName = "A", theirName = "B", format = "lv50", myParty = {},
                             theirParty = {}, seed = 9, sleepClause = true,
                             log = { { me = true, m = { type = "action", kind = "move", slot = 1 } } } })
T.check(r and r.sleepClause == true, "the replay keeps that the clause was on")
T.check(CoopReplay.newFeed(r).sleepClause == true, "...and the replay's feed hands it to the spectator")
r.sleepClause = nil
T.check(CoopReplay.newFeed(r).sleepClause == false, "a replay without it (an older one) is watched without it")

-- the line, in both languages, fits the battle's text box
local function fits(s)
  for line in (s .. "\n"):gmatch("(.-)\n") do
    if #line:gsub("[\128-\191]", "") > 18 then return false end
  end
  return true
end
T.check(fits(CoopSleepClause.TEXT), "the English line fits the box")
local forced = I18n.forced
I18n.forced = "es"
local es = CoopSleepClause.message()
I18n.forced = forced
T.check(es ~= CoopSleepClause.TEXT and es:find("CL") and fits(es), "...and it has a Spanish line that fits: " .. es)

-- ------------------------------------------- one battle, move by move
-- RED (the host) has HYPNOSIS and REST; BLUE three Pokemon
local function oneBattle(armed)
  local game = T.link.fakeGame(Data, {}, { name = "RED" })
  local nA = Net.loopbackPair()
  nA.sleepClause = armed
  local mine = { mon("FIXMON_A", 30, { "HYPNOSIS", "REST", "FIX_TACKLE" }),
                 mon("FIXMON_C", 30, { "HYPNOSIS", "FIX_TACKLE" }) }
  local theirs = { mon("FIXMON_B", 30, { "HYPNOSIS", "REST", "FIX_SCRATCH" }),
                   mon("FIXMON_C", 30, { "REST", "FIX_TACKLE" }), mon("FIXMON_A", 30) }
  local b = LinkBattle.newHost(game, nA, { myParty = Protocol.packParty(mine),
                                           theirParty = Protocol.packParty(theirs),
                                           theirName = "BLUE", seed = 1234 })
  b.accuracyRoll = function() return true end -- no 1-in-256 misses in these cases
  b.said = {}
  local say = b.sayNext
  b.sayNext = function(s, m, ...) b.said[#b.said + 1] = m return say(s, m, ...) end
  return b
end
local function use(b, user, target, id)
  b.said = {}
  b:performMove(user, target, { id = id, pp = 10 })
  return table.concat(b.said, " / ")
end
local function bring(b, side, i)
  local party = side == "enemy" and b.enemyParty or b.playerParty
  b[side] = BattleState.makeBattler(Data, party[i], side == "player")
  b[side].name = b[side].name or party[i].species
end

do
  local b = oneBattle(true)
  T.check(b.coopSleepClause ~= nil, "a link battle whose net carries the clause is armed")
  local foes = b.enemyParty
  local said = use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[1].status == "SLP", "the first foe put to sleep falls asleep: " .. said)
  bring(b, "enemy", 2)
  said = use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[2].status == nil, "a second foe does not, while the first sleeps")
  T.check(said:find("SLEEP CLAUSE", 1, true) and not said:find("fell asleep", 1, true),
          "...and the move fails with the clause's own line: " .. said)
  T.check(b.coopSleepClause.blocked == 1, "one sleep stopped")
  -- the foe's own REST is theirs: never stopped, never counted
  foes[2].hp = foes[2].hp - 5
  said = use(b, b.enemy, b.player, "REST")
  T.check(foes[2].status == "SLP", "the team's own REST still puts it to sleep (clause or not)")
  -- the player's team: one of the foe's sleep moves is allowed (theirs to spend)
  bring(b, "enemy", 1)
  foes[1].status = nil
  said = use(b, b.enemy, b.player, "HYPNOSIS")
  T.check(b.playerParty[1].status == "SLP", "the clause holds per team: the other side may still put one to sleep")
end

do
  -- woke up / fainted / RESTed: no longer counts
  local b = oneBattle(true)
  local foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  foes[1].status = nil -- woke up
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[2].status == "SLP", "the first one woke up: the second sleep lands")

  b = oneBattle(true)
  foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  foes[1].hp = 0 -- fainted asleep
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[2].status == "SLP", "the first one fainted: the second sleep lands")

  b = oneBattle(true)
  foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  foes[1].hp = foes[1].hp - 7
  use(b, b.enemy, b.player, "REST") -- asleep, then RESTs (SLEEP TALK's way)
  T.check(foes[1].status == "SLP" and foes[1].hp == foes[1].stats.hp, "the sleeper RESTs")
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[2].status == "SLP", "...and its sleep is its own now: the next foe's sleep lands")

  b = oneBattle(true)
  foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  use(b, b.enemy, b.player, "REST") -- at full HP: REST fails, the foe's sleep stays
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[1].status == "SLP" and foes[2].status == nil, "a REST that failed changes nothing: still stopped")

  b = oneBattle(true)
  foes = b.enemyParty
  foes[1].hp = foes[1].hp - 3
  use(b, b.enemy, b.player, "REST") -- its own sleep first
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[2].status == "SLP", "a team resting on its own does not stop the foe's first sleep")

  b = oneBattle(true)
  foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  bring(b, "enemy", 1) -- the sleeper back in: still asleep, the target already is
  local said = use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(not said:find("SLEEP CLAUSE", 1, true), "a target already asleep fails the engine's own way")
end

do
  local b = oneBattle(false)
  T.check(b.coopSleepClause == nil, "a link battle without it (FREE BATTLE, a real cable) is not armed")
  local foes = b.enemyParty
  use(b, b.player, b.enemy, "HYPNOSIS")
  bring(b, "enemy", 2)
  use(b, b.player, b.enemy, "HYPNOSIS")
  T.check(foes[1].status == "SLP" and foes[2].status == "SLP", "...and two foes can sleep there, as before")
end

-- ---------------------------------- both copies and the replay, lockstep
-- RED (host, slower) uses HYPNOSIS on turns 1 and 2; BLUE attacks on turn
-- 1 and switches to its second Pokemon on turn 2, so the second HYPNOSIS
-- meets a new foe while the first sleeps.  Turn 3: both attack.
local function lockstep(armA, armB, seed)
  local gA = T.link.fakeGame(Data, {}, { name = "RED" })
  local gB = T.link.fakeGame(Data, {}, { name = "BLUE" })
  gA.save.party = { mon("FIXMON_A", 20, { "HYPNOSIS", "FIX_TACKLE" }) }
  gB.save.party = { mon("FIXMON_B", 30), mon("FIXMON_C", 30) }
  local nA, nB = Net.loopbackPair()
  nA.sleepClause, nB.sleepClause = armA, armB
  local log = {}
  for _, side in ipairs({ { n = nA, s = "host" }, { n = nB, s = "guest" } }) do
    local send = side.n.send
    side.n.send = function(self, m)
      if m.type == "action" then log[#log + 1] = { side = side.s, msg = m } end
      return send(self, m)
    end
  end
  local pA, pB = Protocol.packParty(gA.save.party), Protocol.packParty(gB.save.party)
  local bA = LinkBattle.newHost(gA, nA, { myParty = pA, theirParty = pB, theirName = "BLUE", seed = seed })
  local bB = LinkBattle.newGuest(gB, nB, { myParty = pB, theirParty = pA, theirName = "RED", seed = seed })
  gA.stack:push(bA)
  gB.stack:push(bB)
  local plan = {
    A = function(turn) return turn <= 2 and 1 or 2 end,
    B = function(turn) return turn == 2 and "switch" or 1 end,
  }
  local sides = { { b = bA, g = gA, plan = plan.A }, { b = bB, g = gB, plan = plan.B } }
  local function done(b) return (b.turnCount or 0) >= 3 and b.phase == "menu" or b.result ~= nil end
  for _ = 1, 20000 do
    if done(bA) and done(bB) then break end
    for _, s in ipairs(sides) do
      local b = s.b
      local want = s.plan((b.turnCount or 0) + 1)
      if not done(b) then
        -- a turn that switches holds A in the menu until the switch is in
        Input.pressed = { a = true }
        if b.phase == "menu" then
          s.menu = (s.menu or 0) + 1
          b.menuIndex = 1
          if want == "switch" and s.switched ~= b.turnCount then
            Input.pressed = {}
            if s.menu >= 2 then
              s.switched = b.turnCount
              b:resolveSwitch(b.playerParty[2])
            end
          end
        else
          s.menu = 0
          if b.phase == "moveSelect" then b.moveIndex = type(want) == "number" and want or 1; b.menuIndex = 1 end
        end
        s.g.stack:update(1 / 60)
      end
    end
  end
  return bA, bB, { hostParty = pA, guestParty = pB, hostName = "RED", guestName = "BLUE", seed = seed,
                   sleepClause = armA or nil, log = log }
end
local function view(party)
  local o = {}
  for _, m in ipairs(party) do o[#o + 1] = m.hp .. ":" .. tostring(m.status) end
  return table.concat(o, " ")
end

do
  local bA, bB, replay = lockstep(true, true, 4242)
  T.check(bA.turnCount == 3 and bB.turnCount == 3 and not bA.result and not bB.result,
          "three turns on both copies, no desync: " .. tostring(bA.result) .. "/" .. tostring(bB.result))
  local guestOnA, guestOnB = view(bA.enemyParty), view(bB.playerParty)
  T.check(bA.enemyParty[1].status == "SLP" and bA.enemyParty[2].status == nil,
          "host copy: the first foe sleeps, the second HYPNOSIS failed (" .. guestOnA .. ")")
  T.eq(guestOnB, guestOnA, "guest copy: the same HP and status, Pokemon by Pokemon")
  T.eq(view(bB.enemyParty), view(bA.playerParty), "...and the host's side the same on both")
  T.check(bA.coopSleepClause.blocked == 1 and bB.coopSleepClause.blocked == 1, "one sleep stopped on each copy")

  -- the replay, through the engine's spectator
  local gS = T.link.fakeGame(Data, {}, { name = "RED" })
  local spec = CoopReplay.newBattle(gS, replay)
  T.check(spec and spec.coopSleepClause ~= nil, "the replay's spectator is armed")
  gS.stack:push(spec)
  for _ = 1, 20000 do
    if spec.result or spec.linkEnded or (spec.turnCount == 3 and spec.phase == "waitBoth" and spec.net.closed) then break end
    Input.pressed = { a = true }
    gS.stack:update(1 / 60)
  end
  T.eq(spec.turnCount, 3, "the replay plays the three turns")
  T.eq(view(spec.enemyParty), guestOnA, "the replay ends with the guest's team exactly as the battle did")
  T.eq(view(spec.playerParty), view(bA.playerParty), "...and the host's")
  T.check(spec.coopSleepClause.blocked == 1, "the replay stops the same sleep")

  -- the same replay watched without the clause plays a different battle:
  -- what the replay notes is what makes it faithful
  replay.sleepClause = nil
  local gN = T.link.fakeGame(Data, {}, { name = "RED" })
  local plain = CoopReplay.newBattle(gN, replay)
  gN.stack:push(plain)
  for _ = 1, 20000 do
    if plain.result or plain.linkEnded or (plain.turnCount == 3 and plain.phase == "waitBoth" and plain.net.closed) then break end
    Input.pressed = { a = true }
    gN.stack:update(1 / 60)
  end
  T.check(plain.coopSleepClause == nil and plain.enemyParty[2].status == "SLP",
          "(watched without the clause the second foe would sleep: " .. view(plain.enemyParty) .. ")")
end

do
  local bA, bB = lockstep(false, false, 4242)
  T.check(not bA.result and not bB.result and bA.enemyParty[2].status == "SLP" and bB.playerParty[2].status == "SLP",
          "without the clause on either copy both foes sleep, still in step")
end

do
  -- one copy with the clause and one without split on the second HYPNOSIS:
  -- why it only plays when both have it (bothHave)
  local bA, bB = lockstep(true, false, 4242)
  T.check(bA.result == "draw" or bB.result == "draw", "a copy without the clause desyncs: the battle ends as a draw")
end

T.finish("co-op sleep clause")
