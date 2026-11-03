-- P1-VS-P2 MATCHES AND THE VS RECORD (1.20, src/coop/CoopMatch.lua,
-- src/coop/CoopRecord.lua): the score both copies agree on, the tunnel
-- numbered by game, a whole best of 3 between two real Cable Clubs (one per
-- player, in one process, joined through the co-op messages they send), a
-- player leaving, the invite that carries the length, the record and its
-- ELO, and the VS menu that shows them.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopLink = require("src.coop.CoopLink")
local CoopVS = require("src.coop.CoopVS")
local CoopMatch = require("src.coop.CoopMatch")
local CoopRecord = require("src.coop.CoopRecord")
local CoopReplay = require("src.coop.CoopReplay")
local I18n = require("src.coop.CoopI18n")
require("src.coop.CoopLog").enabled = false
CoopManager.isConnected = function() return true end

-- --------------------------------------------------------- the score
T.check(CoopManager.CAPS["vs.match"] == true, "the hello announces vs.match")
local m = CoopMatch.new({ best = 3, asker = true })
T.check(m.best == 3 and m.need == 2 and m.game == 1, "best of 3: two wins take it")
T.check(CoopMatch.new({ best = 7 }).best == 1 and CoopMatch.new({}).need == 1, "anything but 3 is one game")
T.check(CoopMatch.winnerOf(m, "win") == "asker" and CoopMatch.winnerOf(m, "lose") == "asked"
        and CoopMatch.winnerOf(m, "draw") == "none" and CoopMatch.winnerOf(m, nil) == "none",
        "a battle's result, as the side that won it")
local asked = CoopMatch.new({ best = 3, asker = false })
T.check(CoopMatch.winnerOf(asked, "win") == "asked", "...on the asked copy too")
T.check(CoopMatch.agree("asker", "asker") == "asker" and CoopMatch.agree("asked", "asked") == "asked",
        "both copies name the same winner: that one")
T.check(CoopMatch.agree("asker", "asked") == "none" and CoopMatch.agree("asker", nil) == "none"
        and CoopMatch.agree("none", "none") == "none", "they differ, or nobody won: no winner")
T.eq(CoopMatch.apply(m, "asker"), "next", "1-0: on to game 2")
m.game = 2
T.eq(CoopMatch.apply(m, "asked"), "next", "1-1: on to game 3")
m.game = 3
T.eq(CoopMatch.apply(m, "asker"), "won", "2-1: the match is over")
T.check(m.over and m.winner == "asker" and CoopMatch.myWins(m) == 2 and CoopMatch.theirWins(m) == 1,
        "...won by the asker, 2-1")
local v = CoopMatch.new({ best = 3, asker = true })
T.eq(CoopMatch.apply(v, "none"), "void", "a game without a winner ends the match")
T.check(v.over and v.void and not v.winner, "...with no result")
local one = CoopMatch.new({ best = 1, asker = false })
T.eq(CoopMatch.apply(one, "asker"), "won", "one game: its winner takes the match")

-- -------------------------------------------- the tunnel, game by game
local t = CoopLink.newTunnel("L-route")
t.match = CoopMatch.new({ best = 3, asker = true })
CoopMatch.route(t, { link = "L-route", game = 1, payload = { type = "hash" } })
CoopMatch.route(t, { link = "L-route", game = 2, payload = { type = "party", seed = 2 } })
CoopMatch.route(t, { link = "L-route", game = 3, payload = { type = "party", seed = 3 } })
T.check(#t.inbox == 1 and t.inbox[1].type == "hash", "this game's message comes in")
T.check(#t.match.held == 2, "the next games' wait")
CoopMatch.nextGame(t)
T.check(t.match.game == 2 and #t.inbox == 1 and t.inbox[1].seed == 2,
        "next game: the last one's leftovers go, what waited for this one comes in")
CoopMatch.route(t, { link = "L-route", game = 1, payload = { type = "bye" } })
T.check(#t.inbox == 1, "a late message from an earlier game is dropped")
local sent = {}
CoopManager.net = { send = function(_, msg) sent[#sent + 1] = msg return true end, flush = function() end }
t:send({ type = "action", kind = "move", slot = 1 })
T.check(sent[1].type == "coop_link" and sent[1].game == 2, "what goes out says its game")
-- the sleep clause (CoopVS.attach, src/coop/CoopSleepClause.lua) is armed on
-- the tunnel for game 1: every later game's recording keeps it
t.sleepClause = true
t.recInfo = { asker = true, myName = "A", theirName = "B", format = "lv50", best = 3 }
CoopMatch.nextGame(t)
T.check(t.rec and t.rec.game == 3 and t.rec.sleepClause == true, "the next game's recording keeps the sleep clause")
t.rec.myParty, t.rec.theirParty, t.rec.seed = {}, {}, 1
t.rec.log = { { me = true, m = { type = "action", kind = "move", slot = 1 } } }
local sc = CoopReplay.build(t.rec, "2026-11-02 22:00")
T.check(sc and sc.sleepClause == true and sc.game == 3 and sc.best == 3, "...and so does its replay")
t.rec, t.sleepClause = nil, nil
t.match = nil
t:close()
sent = {}
local plain = CoopLink.newTunnel("L-plain")
plain:send({ type = "hello" })
T.check(sent[1].game == nil, "outside a match nothing new goes on the wire")
plain:close()

-- ----------------------------------------- two real Cable Clubs, one match
local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) if x.enter then x:enter() end end
  function s:pop() local x = table.remove(self.states) if x and x.exit then x:exit() end return x end
  function s:top() return self.states[#self.states] end
  return s
end
local function newGame(name, id)
  local save = SaveData.newGame()
  save.player.name = name
  save.coopId = id
  save.party = { Pokemon.new(Data, "FIXMON_A", 20), Pokemon.new(Data, "FIXMON_B", 20) }
  local g = { data = Data, save = save, stack = newStack(),
              input = { pressed = {}, wasPressed = function(self, k) return self.pressed[k] end,
                        isDown = function() return false end } }
  g.stack:push({ isOverworld = true })
  return g
end

-- one process plays both copies: what one sends, the other receives
local queues, side = { A = {}, B = {} }, "A"
CoopManager.net = { send = function(_, msg) table.insert(queues[side == "A" and "B" or "A"], msg) return true end,
                    flush = function() end }
local function deliver(to, tunnel)
  local q = queues[to]
  queues[to] = {}
  for _, msg in ipairs(q) do
    if msg.type == "coop_link" and not tunnel.closed then
      if tunnel.match then CoopMatch.route(tunnel, msg) else table.insert(tunnel.inbox, msg.payload) end
    elseif msg.type == "coop_match" then
      CoopMatch.onMessage(msg, tunnel)
    end
  end
end

-- A asks (the Cable Club's host), B is asked
local function openMatch(A, B, best, fmt)
  queues = { A = {}, B = {} }
  CoopManager.partner.name, CoopManager.partner.id = "MOCHI", A.save.coopId
  side = "B"
  local lsB = CoopLink.openLinkState(B, "battle", false, "L-match", fmt, best)
  local tB = lsB.net
  CoopLink.adapter = nil
  CoopManager.partner.name, CoopManager.partner.id = "TOBY", B.save.coopId
  side = "A"
  local lsA = CoopLink.openLinkState(A, "battle", true, "L-match", fmt, best)
  return lsA, lsB, lsA.net, tB
end

local frames = 0
local function frame(A, B, lsA, lsB, tA, tB, keysA, keysB)
  frames = frames + 1
  side = "A"
  -- a free battle's asker picks the level rule (any) once, with A
  A.input.pressed = keysA or (lsA.stage == "battleOptions" and { a = true }) or {}
  if A.stack:top() == lsA then lsA:update(1 / 60) end
  side = "B"
  B.input.pressed = keysB or {}
  if B.stack:top() == lsB then lsB:update(1 / 60) end
  deliver("A", tA)
  deliver("B", tB)
end
local function runUntil(A, B, lsA, lsB, tA, tB, cond, limit)
  for _ = 1, limit or 2000 do
    if cond() then return true end
    frame(A, B, lsA, lsB, tA, tB)
  end
  return cond()
end
-- the battle on each screen ends as `resA` / `resB` say
local function endBattles(A, B, resA, resB)
  local bA, bB = A.stack:top(), B.stack:top()
  -- a turn each (what a replay needs to be kept), then the end
  side = "A"; bA.net:send({ type = "action", kind = "move", slot = 1 })
  side = "B"; bB.net:send({ type = "action", kind = "move", slot = 1 })
  bA.result, bB.result = resA, resB
  side = "A"; bA:finish()
  side = "B"; bB:finish()
  -- the fade back from the battle screen (BattleState:finish) plays out
  for _, g in ipairs({ A, B }) do
    local top = g.stack:top()
    if top and top.coopMatch == nil and not top.isOverworld and top ~= bA and top ~= bB then g.stack:pop() end
  end
end

for _, n in ipairs(CoopReplay.list()) do love.filesystem.remove(CoopReplay.DIR .. "/" .. n) end
CoopReplay.forget()
love.filesystem.remove(CoopRecord.FILE)
CoopRecord.forget()

local A, B = newGame("MOCHI", "id-aaa"), newGame("TOBY", "id-bbb")
local lsA, lsB, tA, tB = openMatch(A, B, 3, CoopVS.FORMATS.lv50)
local mA, mB = lsA.coopMatch, lsB.coopMatch
T.check(mA and mB and mA.best == 3 and mB.best == 3 and mA.asker and not mB.asker, "both copies play a best of 3")
T.check(mA.myId == "id-aaa" and mA.partnerId == "id-bbb" and mB.partnerId == "id-aaa", "...each knowing the other's coop id")
local both = function(stage) return function() return lsA.stage == stage and lsB.stage == stage end end
local seeds = {}
local plan = { { "win", "lose" }, { "lose", "win" }, { "win", "lose" } }
local scores = {}
for g = 1, 3 do
  T.check(runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning")), "game " .. g .. ": both battles start")
  seeds[g] = tA.rec and tA.rec.seed
  T.check(tA.rec and tA.rec.game == g and tB.rec and tB.rec.game == g, "game " .. g .. ": both record it as game " .. g)
  T.check(tB.rec and tB.rec.seed == seeds[g], "game " .. g .. ": one seed, from the host, on both")
  endBattles(A, B, plan[g][1], plan[g][2])
  local after = g < 3 and "matchNext" or "matchOver"

  T.check(runUntil(A, B, lsA, lsB, tA, tB, both(after), 200), "game " .. g .. ": both copies settle it (" .. after .. ")")
  scores[g] = CoopMatch.myWins(mA) .. "-" .. CoopMatch.theirWins(mA) .. "/" .. CoopMatch.myWins(mB) .. "-" .. CoopMatch.theirWins(mB)
  T.check(A.stack:top() == lsA and B.stack:top() == lsB and not tA.closed and not tB.closed,
          "game " .. g .. ": the Cable Club stays open on both, the tunnel too")
end
T.eq(table.concat(scores, " "), "1-0/0-1 1-1/1-1 2-1/1-2", "the score after each game, mirrored on the two copies")
T.check(seeds[1] and seeds[2] and seeds[3] and not (seeds[1] == seeds[2] and seeds[2] == seeds[3]),
        "a new seed for each game: " .. table.concat({ tostring(seeds[1]), tostring(seeds[2]), tostring(seeds[3]) }, " "))
T.check(mA.over and mB.over and mA.winner == "asker" and mB.winner == "asker", "both say the asker won the match")

-- the record, written on both copies at the end
local recA = CoopRecord.against("id-aaa", "id-bbb")
local recB = CoopRecord.against("id-bbb", "id-aaa")
local fA, fB = recA and recA.formats.lv50, recB and recB.formats.lv50
T.check(fA and fA.w == 1 and fA.l == 0 and fA.gw == 2 and fA.gl == 1, "MOCHI's record: a LEVEL 50 win, games 2-1")
T.check(fB and fB.w == 0 and fB.l == 1 and fB.gw == 1 and fB.gl == 2, "TOBY's record: a LEVEL 50 loss, games 1-2")
T.check(recA.name == "TOBY" and recB.name == "MOCHI", "each keeps the partner's name")
T.check(fA.elo == 1016 and fA.theirElo == 984 and fB.elo == 984 and fB.theirElo == 1016,
        "ELO 1000 each -> 1016 / 984, mirrored on both copies")

-- three replays on each copy, one per game
local names = CoopReplay.list()
T.eq(#names, 6, "three replays per copy (both copies write to the one test disk)")
local games = {}
for _, n in ipairs(names) do
  local r = CoopReplay.load(n)
  if r then games[#games + 1] = r.me .. r.game .. "/" .. tostring(r.best) end
end
table.sort(games)
T.eq(table.concat(games, " "), "guest1/3 guest2/3 guest3/3 host1/3 host2/3 host3/3",
     "each game left its own replay, numbered, on both sides")
local first = CoopReplay.load(names[1])
local _, info = CoopReplay.describe(first, names[1])
T.check(info[1]:match("^LEVEL 50 %d/3$") ~= nil, "the replay list names the game: " .. tostring(info[1]))

-- the end: A on either side leaves; nobody is told anything (it is over)
for _ = 1, 70 do frame(A, B, lsA, lsB, tA, tB) end
frame(A, B, lsA, lsB, tA, tB, { a = true }, { a = true })
T.check(A.stack:top().isOverworld and B.stack:top().isOverworld, "the match over, both back in the overworld")
T.check(tA.closed and tB.closed and #queues.A == 0 and #queues.B == 0, "...the tunnels shut, no leave sent")

-- --------------------------------------------- someone leaves between games
CoopRecord.forget()
local before = CoopRecord.against("id-aaa", "id-bbb").formats.lv50.w
lsA, lsB, tA, tB = openMatch(A, B, 3, CoopVS.FORMATS.lv50)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
endBattles(A, B, "lose", "win")
runUntil(A, B, lsA, lsB, tA, tB, both("matchNext"), 200)
for _ = 1, 70 do frame(A, B, lsA, lsB, tA, tB) end
frame(A, B, lsA, lsB, tA, tB, {}, { b = true })
T.check(B.stack:top().isOverworld, "B between games: the asked player leaves")
for _ = 1, 3 do frame(A, B, lsA, lsB, tA, tB) end
local top = A.stack:top()
T.check(top ~= lsA and not top.isOverworld and A.stack.states[#A.stack.states - 1].isOverworld,
        "...and the asker's Cable Club closes too, with a box saying so")
T.check(lsA.coopMatch.partnerLeft and lsA.coopMatch.over and not lsA.coopMatch.winner, "...the match over with no result")
A.stack:pop()
CoopRecord.forget()
T.eq(CoopRecord.against("id-aaa", "id-bbb").formats.lv50.w, before, "a match left unfinished is not in the record")

-- ---------------------------------- the asker leaves before game 2 begins
lsA, lsB, tA, tB = openMatch(A, B, 3, nil)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
endBattles(A, B, "win", "lose")
runUntil(A, B, lsA, lsB, tA, tB, both("matchNext"), 200)
-- A goes on to game 2 first and waits in the Cable Club; then B in it (B)
for _ = 1, 70 do frame(A, B, lsA, lsB, tA, tB) end
frame(A, B, lsA, lsB, tA, tB, { a = true }, {})
T.eq(lsA.stage, "battleWait", "A goes on to game 2 at once (A)")
frame(A, B, lsA, lsB, tA, tB, { b = true }, {})
T.check(A.stack:top().isOverworld, "A leaves the Cable Club while waiting (B)")
for _ = 1, 3 do frame(A, B, lsA, lsB, tA, tB) end
T.check(not B.stack:top().isOverworld and B.stack:top() ~= lsB, "B is told: a box, the Cable Club gone")
B.stack:pop()
T.check(B.stack:top().isOverworld and lsB.coopMatch.over, "...back to the overworld")

-- -------------------------------- a game the copies disagree on: no result
lsA, lsB, tA, tB = openMatch(A, B, 3, nil)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
endBattles(A, B, "win", "win")
T.check(runUntil(A, B, lsA, lsB, tA, tB, both("matchOver"), 200), "both copies say they won: the match ends")
T.check(lsA.coopMatch.void and lsB.coopMatch.void, "...as no result on both")
for _ = 1, 70 do frame(A, B, lsA, lsB, tA, tB) end
frame(A, B, lsA, lsB, tA, tB, { a = true }, { a = true })

-- ------------------------- RUN (a draw on both screens) ends it, no result
lsA, lsB, tA, tB = openMatch(A, B, 3, nil)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
endBattles(A, B, "draw", "draw")
T.check(runUntil(A, B, lsA, lsB, tA, tB, both("matchOver"), 200) and lsA.coopMatch.void and lsB.coopMatch.void,
        "a drawn game (RUN, a desync) ends the match with no result on both")
-- a leave arriving once the match is settled changes nothing
CoopMatch.onMessage({ type = "coop_match", link = tA.id, kind = "leave", game = 1 }, tA)
T.check(not tA.closed and not lsA.coopMatch.partnerLeft, "a late leave after the end is ignored")
for _ = 1, 70 do frame(A, B, lsA, lsB, tA, tB) end
frame(A, B, lsA, lsB, tA, tB, { a = true }, { a = true })
T.check(A.stack:top().isOverworld and B.stack:top().isOverworld, "...and both close the end screen")

-- ------------------- the partner leaves during a battle: it ends, so does the match
lsA, lsB, tA, tB = openMatch(A, B, 3, nil)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
local battleA = A.stack:top()
CoopMatch.onMessage({ type = "coop_match", link = tA.id, kind = "leave", game = 1 }, tA)
T.check(tA.closed and lsA.coopMatch.partnerLeft, "a leave in the middle of a battle closes the tunnel")
side = "A"; battleA:update(1 / 60)
T.check(battleA.result == "draw", "...which the battle reads as the cable coming out (a draw)")
battleA:finish()
if A.stack:top() ~= lsA then A.stack:pop() end
side = "A"; lsA:update(1 / 60)
T.check(A.stack:top() ~= lsA and A.stack.states[#A.stack.states - 1].isOverworld, "...and the Cable Club closes with a box")
A.stack:pop()
B.stack:pop(); B.stack:pop()
T.check(B.stack:top().isOverworld, "(the other copy, gone in this test, is cleared)")
CoopLink.adapter = nil

-- ----------------------------------------------- one game, a free battle
CoopRecord.forget()
lsA, lsB, tA, tB = openMatch(A, B, 1, nil)
runUntil(A, B, lsA, lsB, tA, tB, both("battleRunning"))
endBattles(A, B, "lose", "win")
T.check(runUntil(A, B, lsA, lsB, tA, tB, both("matchOver"), 200), "one game: over after the first battle")
local free = CoopRecord.against("id-bbb", "id-aaa").formats.free
T.check(free and free.w == 1 and free.l == 0, "a free battle has its own record (TOBY 1-0)")
T.check(free.elo == 1016 and CoopRecord.against("id-aaa", "id-bbb").formats.free.elo == 984,
        "...and its own ELO, mirrored")
for _ = 1, 400 do frame(A, B, lsA, lsB, tA, tB) end
T.check(A.stack:top().isOverworld and B.stack:top().isOverworld, "the end screen closes by itself")

-- ---------------------------------------------------------- the invite
CoopManager.partner.caps = {}
local function newStackG() return newGame("ME", "id-me") end
local g = newStackG()
local out = {}
CoopManager.net = { send = function(_, msg) out[#out + 1] = msg return true end, flush = function() end }
local function lastSent(kind) for i = #out, 1, -1 do if out[i].type == kind then return out[i] end end end
CoopLink.pending, CoopLink.adapter = nil, nil
CoopLink.invite(g, "battle", CoopVS.FORMATS.lv50, 3)
T.check(lastSent("coop_link_invite").best == nil, "a partner without vs.match is asked for one battle, as ever")
CoopLink.pending = nil
CoopManager.partner.caps = { ["vs.formats"] = true, ["vs.match"] = true }
CoopLink.invite(g, "battle", CoopVS.FORMATS.lv50, 3)
T.check(lastSent("coop_link_invite").best == 3 and CoopLink.pending.best == 3, "with it, the invite says best of 3")
CoopLink.pending = nil
CoopLink.invite(g, "battle", CoopVS.FORMATS.free, 7)
T.check(lastSent("coop_link_invite").best == 1, "anything else asks for one game")
CoopLink.pending = nil
CoopLink.invite(g, "trade", nil, 3)
T.check(lastSent("coop_link_invite").best == nil, "a trade is not a match")
CoopLink.pending = nil

local idle = CoopManager.overworldIdle
CoopManager.overworldIdle = function() return true end
out = {}
CoopLink.asked = nil
CoopLink.onInvite(g, { id = "L5", mode = "battle", format = "lv50", best = 2, name = "TOBY" })
T.check(lastSent("coop_link_decline") and lastSent("coop_link_decline").reason == "rules",
        "a length this copy does not know is declined")
out = {}
CoopLink.asked = nil
CoopLink.onInvite(g, { id = "L6", mode = "battle", format = "lv50", best = 3, name = "TOBY" })
local modal = CoopLink.asked
T.check(modal and modal.lines[3] == "LEVEL 50 RULES" and modal.lines[4] == "BEST OF 3 GAMES",
        "the asked player sees the rules and BEST OF 3 GAMES")
g.stack:pop()
CoopLink.asked = nil
CoopLink.onInvite(g, { id = "L7", mode = "battle", best = 1, name = "TOBY" })
T.check(CoopLink.asked and CoopLink.asked.lines[4] == nil, "one game: no extra line")
g.stack:pop()
CoopLink.asked = nil
CoopManager.overworldIdle = idle

-- --------------------------------------------------------- the record
CoopRecord.forget()
local a1, b1 = CoopRecord.elo(1000, 1000, true)
T.check(a1 == 1016 and b1 == 984, "even ratings: the winner takes 16")
local a2, b2 = CoopRecord.elo(1200, 1000, true)
local a3, b3 = CoopRecord.elo(1200, 1000, false)
T.check(a2 - 1200 < 16 and 1200 - a3 > 16 and a2 + b2 == 2200 and a3 + b3 == 2200,
        "the favourite wins less and loses more; nothing is made or lost")
-- the same matches written on two copies give mirrored numbers, even
-- where rounding could tip one copy's way
love.filesystem.remove(CoopRecord.FILE)
CoopRecord.forget()
local results = { true, true, false, true, false, false, true, true, true, false, true }
for _, won in ipairs(results) do
  CoopRecord.add({ myId = "x1", partnerId = "y2", partnerName = "Y", format = "lv100", won = won, gamesWon = 1, gamesLost = 0 })
  CoopRecord.add({ myId = "y2", partnerId = "x1", partnerName = "X", format = "lv100", won = not won, gamesWon = 0, gamesLost = 1 })
end
local fx, fy = CoopRecord.against("x1", "y2").formats.lv100, CoopRecord.against("y2", "x1").formats.lv100
T.check(fx.elo == fy.theirElo and fx.theirElo == fy.elo and fx.elo + fx.theirElo == 2000,
        "eleven matches later both copies hold the same pair: " .. fx.elo .. " / " .. fx.theirElo)
T.check(fx.w == 7 and fx.l == 4 and fy.w == 4 and fy.l == 7, "wins and losses mirrored too")
CoopRecord.forget()
T.check(CoopRecord.against("x1", "y2").formats.lv100.elo == fx.elo, "it is on disk: read back the same")
T.check(CoopRecord.add({ myId = "x1", partnerId = "x1", won = true }) == nil
        and CoopRecord.add({ myId = "x1", won = true }) == nil, "no partner id, or our own: nothing kept")
CoopRecord.add({ myId = "x9", partnerId = "y2", partnerName = "Y", format = "mono", won = true })
T.check(CoopRecord.against("x1", "y2").formats.mono == nil, "another save of ours keeps its own record")
love.filesystem.write(CoopRecord.FILE, "{broken")
CoopRecord.forget()
T.check(next(CoopRecord.load().saves) == nil, "a broken file reads as an empty record")
love.filesystem.remove(CoopRecord.FILE)
CoopRecord.forget()
CoopRecord.add({ myId = "x1", partnerId = "y2", partnerName = "Y", format = "little", won = false, gamesWon = 1, gamesLost = 2 })
CoopRecord.add({ myId = "x1", partnerId = "y2", partnerName = "Y", format = "lv50", won = true, gamesWon = 2, gamesLost = 0 })
local rows = CoopRecord.rows("x1", "y2")
T.check(#rows == 2 and rows[1].format.id == "lv50" and rows[2].format.id == "little", "the record's rows, in format order")
local box = CoopRecord.describe(rows[2].rec)
T.eq(table.concat(box, "|"), "WON 0  LOST 1|GAMES 1-2|ELO 984 VS 1016", "a format's box")

-- --------------------------------------------------------- the menu
local CoopMenu = require("src.coop.CoopMenu")
local mg = newGame("X", "x1")
local menu = CoopMenu.new(mg)
CoopManager.partner.id, CoopManager.partner.name = "y2", "Y"
CoopManager.partner.caps = { ["vs.formats"] = true, ["vs.match"] = true }
CoopMatch.wantBest = 1
local vs = menu:connectedRows(nil, "vs")
T.check(vs[1].label == "MATCH: 1 GAME" and vs[#vs - 1].label == "RECORD" and vs[#vs].label == "REPLAYS",
        "the VS page: the match length first, the formats, RECORD, REPLAYS")
vs[1].run()
T.check(CoopMatch.wantBest == 3 and menu:connectedRows(nil, "vs")[1].label == "MATCH: BEST OF 3",
        "A on it switches to the best of 3")
vs[1].run()
T.eq(CoopMatch.wantBest, 1, "...and back")
local rec = menu:connectedRows(nil, "record")
T.check(#rec == 2 and rec[1].label == "LEVEL 50" and rec[1].info[1] == "WON 1  LOST 0", "RECORD lists this partner's formats")
CoopManager.partner.id = "someone-new"
rec = menu:connectedRows(nil, "record")
T.check(#rec == 1 and rec[1].label == "NO MATCHES YET", "a partner never played: nothing yet")
CoopManager.partner.caps = { ["vs.formats"] = true }
vs = menu:connectedRows(nil, "vs")
T.check(vs[1].label == "FREE BATTLE" and #vs == 6, "a partner without vs.match: the formats and REPLAYS, as before")

-- ------------------------------------------------- the words, both languages
local texts = { "MATCH: 1 GAME", "MATCH: BEST OF 3", "RECORD", "NO MATCHES YET" }
-- (a name is cut to 6 letters in the status line, CoopMatch.statusLine)
local lines = { "BEST OF 3 GAMES", "GAME 3 OF 3", "WAITING FOR YELLOW", "NEXT: GAME 3", "NO RESULT",
                "YOU WIN!", "YELLOW WINS!", "A: NEXT  B: LEAVE", "B: LEAVE", "A: OK", "ELO 1016",
                "WON 12  LOST 30", "GAMES 24-61", "ELO 1016 VS 984" }
local boxes = { { "A: ONE GAME OR THE", "BEST OF 3. YOUR", "PARTNER SEES IT." },
                { "WINS, LOSSES AND", "ELO AGAINST YOUR", "PARTNER." },
                { "WHAT YOU WIN OR", "LOSE AGAINST YOUR", "PARTNER SHOWS HERE" } }
local function len(s) return select(2, s:gsub("[^\128-\191]", "")) end
for _, lang in ipairs({ "en", "es" }) do
  I18n.forced = lang
  local ok, bad = true, {}
  for _, s in ipairs(texts) do
    local tr = I18n.t(s)
    if len(tr) > 16 or (lang == "es" and tr == s) then ok = false bad[#bad + 1] = tr end
  end
  for _, s in ipairs(lines) do
    local tr = I18n.t(s)
    if len(tr) > 18 or (lang == "es" and tr == s and not s:match("^ELO")) then ok = false bad[#bad + 1] = tr end
  end
  for _, b in ipairs(boxes) do
    for _, l in ipairs(I18n.lines(b)) do if len(l) > 18 then ok = false bad[#bad + 1] = l end end
    if lang == "es" and I18n.lines(b)[1] == b[1] then ok = false bad[#bad + 1] = b[1] end
  end
  T.check(ok, lang .. ": every new line translated and fits: " .. table.concat(bad, " / "))
end
I18n.forced = "es"
T.eq(I18n.t("TOBY left\nthe match."), I18n.fitGlyphs("TOBY dejó\nla partida."), "es: the partner left")
T.eq(I18n.t("YELLOW WINS!"), I18n.fitGlyphs("¡GANA YELLOW!"), "es: the partner won")
local wait = CoopMatch.statusLine({ stage = "matchWait" }, CoopMatch.new({ theirName = "YELLOWSTONE" }))
T.check(len(I18n.t(wait)) <= 18, "es: the longest status line fits: " .. I18n.t(wait))
I18n.forced = nil

T.finish("co-op best of 3 and VS record")
