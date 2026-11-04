-- BIKE TRIAL (1.20, src/coop/mg/BikeTrial.lua): registered and loaded,
-- canStart's reasons, the time in tenths, the best time per save, the quiet
-- field, and two copies riding against each other through a fake link: the
-- line-up, the finish gate, a DNF, and both copies naming the same winner.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local MG = require("src.coop.CoopMinigame")
local Bike = require("src.coop.mg.BikeTrial")
require("src.coop.CoopLog").enabled = false

-- --------------------------------------------------------------- loading
local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end end
T.check(has(CoopManager.FEATURES, "src.coop.mg.BikeTrial"), "BikeTrial is a feature module (it loads)")
local modRoot = debug.getinfo(1, "S").source:match("^@(.*)/tests/[^/]*$") or "."
local mf = io.open(modRoot .. "/main.lua")
local mainText = mf and mf:read("*a") or ""
if mf then mf:close() end
T.check(mainText:find('"src.coop.mg.BikeTrial"', 1, true) ~= nil, "...and in main.lua's MODULES")
T.check(MG.GAMES.bike == Bike.def and CoopManager.CAPS["minigame.bike"], "registered as \"bike\" with its capability")
T.check(Bike.def.lowWins and Bike.def.quietField and Bike.def.duration == Bike.DURATION, "lowest time wins, quiet field")
T.check(#Bike.def.name <= 16, "the menu row fits")
for _, l in ipairs(Bike.def.info) do T.check(#l <= 18, "info line fits: " .. l) end

-- ------------------------------------------------------------ the clock
T.check(Bike.timeText(234) == "0:23.4" and Bike.timeText(1234) == "2:03.4" and Bike.timeText(5) == "0:00.5",
        "tenths read as M:SS.T")
T.check(Bike.timeText(Bike.DNF) == "--" and Bike.timeText(nil) == "--" and Bike.timeText(0) == "--",
        "DNF / nothing / not started reads --")
T.check(Bike.tenths(23.44) == 234 and Bike.tenths(23.45) == 235 and Bike.tenths(0) == 1, "seconds -> whole tenths")

-- ---------------------------------------------------------- canStart
local GameVersion = require("src.core.GameVersion")
local realGen2 = GameVersion.isGen2
GameVersion.isGen2 = function() return true end
local roadMaps = { ROUTE16_GATE = {}, ROUTE16 = {}, ROUTE17 = {}, ROUTE17_ROUTE18_GATE = {}, ROUTE18 = {} }
local function g(inv, visited, maps) return { data = { maps = maps or roadMaps }, save = { inventory = inv or {}, visited = visited or {} } } end
local function ow(id) return { map = { id = id } } end
local ok, why = Bike.canStart(g({ BICYCLE = 1 }, {}, { PALLET_TOWN = {} }), ow("PALLET_TOWN"))
T.check(not ok and why == "No CYCLING ROAD here", "no road in the data: " .. tostring(why))
GameVersion.isGen2 = function() return false end
ok, why = Bike.canStart(g({ BICYCLE = 1 }), ow("ROUTE16_GATE"))
T.check(not ok and why == "No CYCLING ROAD here", "Gen 1: not offered (" .. tostring(why) .. ")")
GameVersion.isGen2 = function() return true end
ok, why = Bike.canStart(g({}), ow("ROUTE16_GATE"))
T.check(not ok and why == "You need a BICYCLE", "no bike: says so")
ok, why = Bike.canStart(g({ BICYCLE = 1 }, {}), ow("NEW_BARK_TOWN"))
T.check(not ok and why == "Reach CYCLING ROAD first", "never been to Kanto's road: says so")
ok, why = Bike.canStart(g({ BICYCLE = 1 }, { CELADON_CITY = true }), ow("CELADON_CITY"))
T.check(not ok and why == "Go to the ROUTE 16 gate", "been there, elsewhere now: go to the gate")
T.check(Bike.canStart(g({ BICYCLE = 1 }), ow("ROUTE16_GATE")) == true, "at the start gate with a bike: ok")
T.check(Bike.canStart(g({ BICYCLE = 1 }), ow("ROUTE16")) == true, "...or on ROUTE 16 just outside it")
local ES = require("src.coop.CoopLangES")
for _, k in ipairs({ "BIKE TRIAL", "No CYCLING ROAD here", "You need a BICYCLE", "Reach CYCLING ROAD first",
                     "Go to the ROUTE 16 gate", "New best time!", "TIME", "BEST" }) do
  T.check(type(ES[k]) == "string", "Spanish for " .. k)
end

-- --------------------------------------------------------- best time
local s0 = {}
T.check(Bike.best(s0) == nil and Bike.record(s0, 300) and s0.coopBikeBest == 300, "a first time is the best")
T.check(not Bike.record(s0, 310) and s0.coopBikeBest == 300, "a slower one is not kept")
T.check(Bike.record(s0, 250) and Bike.best(s0) == 250, "a faster one is")
T.check(not Bike.record(s0, Bike.DNF) and Bike.best(s0) == 250, "a DNF never is")

-- progress down the course only grows
local p1, p2, p3 = Bike.progress("ROUTE16", 5, 5), Bike.progress("ROUTE17", 2, 40), Bike.progress("ROUTE17", 2, 80)
T.check(Bike.progress("ROUTE16_GATE", 1, 4) == 0 and p1 < p2 and p2 < p3 and p3 < 1
        and Bike.progress("ROUTE17_ROUTE18_GATE", 0, 4) == 1 and Bike.progress("CELADON_CITY", 1, 1) == nil,
        "progress: gate 0 < route 16 < down the road < finish 1")

-- ------------------------------------------------- two copies, one link
local copies, queue = {}, {}
local function stackOf()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local function newOw()
  local o = { map = { id = "ROUTE16" }, player = { cellX = 6, cellY = 6 }, transitioning = false, warps = 0 }
  function o:startWarpTo(id, x, y)
    self.warps = self.warps + 1
    self.map = { id = id }
    self.player.cellX, self.player.cellY = x, y
  end
  return o
end
for _, name in ipairs({ "A", "B" }) do
  local game = { data = { maps = roadMaps }, save = { player = { name = name }, inventory = { BICYCLE = 1 }, visited = {} },
                 stack = stackOf() }
  game.overworld = newOw()
  game.stack:push(game.overworld)
  game.input = { isDown = function() return false end, wasPressed = function() return false end }
  copies[name] = { game = game, state = {} }
end
local active
local function use(name)
  if active then
    local c = copies[active].state
    c.session, c.pending, c.asked = MG.session, MG.pending, MG.asked
  end
  active = name
  local c = copies[name].state
  MG.session, MG.pending, MG.asked = c.session, c.pending, c.asked
  CoopManager.partner.name = name == "A" and "TOBY" or "MOCHI"
  package.loaded["src.core.Game"] = copies[name].game
  CoopManager.getLocalPlayerName = function() return name == "A" and "MOCHI" or "TOBY" end
end
local statuses = {}
CoopManager.net = { send = function(_, m) queue[#queue + 1] = { from = active, m = m } return true end, flush = function() end }
CoopManager.isConnected = function() return true end
CoopManager.connected = true
CoopManager.overworldIdle = function() return true end
CoopManager.showStatus = function(t) statuses[#statuses + 1] = { who = active, text = t } end
CoopManager.partner.caps = CoopManager.capSet(CoopManager.localCaps())
local function pump()
  for _ = 1, 50 do
    if #queue == 0 then return end
    local e = table.remove(queue, 1)
    use(e.from == "A" and "B" or "A")
    local h = CoopManager.handlers[e.m.type]
    if h then h(nil, e.m) end
  end
end
local plan = {}   -- name -> { [tick] = map id }
local tickN = 0
local function tick(dt)
  tickN = tickN + 1
  for _, n in ipairs({ "A", "B" }) do
    use(n)
    local o = copies[n].game.overworld
    local step = plan[n] and plan[n][tickN]
    if step then o.map = { id = step[1] }; o.player.cellX, o.player.cellY = step[2], step[3] end
    MG.update(dt, copies[n].game, o)
  end
  pump()
end
local function play(planA, planB)
  plan.A, plan.B = planA, planB
  for _, n in ipairs({ "A", "B" }) do      -- both back at the start area
    local o = copies[n].game.overworld
    o.map = { id = "ROUTE16" }; o.player.cellX, o.player.cellY = 6, 6
  end
  use("A")
  T.check(MG.invite(copies.A.game, "bike", copies.A.game.overworld), "A invites to the BIKE TRIAL")
  pump()
  use("B")
  T.check(MG.asked and MG.asked.lines[3] == "BIKE TRIAL", "B is asked")
  MG.asked.onAccept()
  -- the real modal closes itself; this stack is a plain list
  local st = copies.B.game.stack
  while st:top() ~= copies.B.game.overworld do st:pop() end
  pump()
  tickN = 0
end
local function results()
  use("A"); local a = MG.session
  use("B"); local b = MG.session
  return a, b
end

-- race 1: A rides gate -> 16 -> 17 -> finish in ~20 s, B in ~37 s (A waits
-- for B longer than the frame's usual grace: waitForPartner)
-- (ticks of 0.1 s; the countdown is 30 of them)
local function ride(finishTick)
  return { [40] = { "ROUTE16", 9, 6 }, [60] = { "ROUTE17", 4, 2 }, [finishTick - 20] = { "ROUTE17", 16, 82 },
           [finishTick] = { "ROUTE17_ROUTE18_GATE", 0, 4 } }
end
copies.A.game.save.coopBikeBest = 400
play(ride(231), ride(400))
for _ = 1, 33 do tick(0.1) end   -- the countdown, the hop to the line, the line
local a, b = results()
T.check(a.phase == "play" and b.phase == "play", "both riding after the countdown")
use("A"); T.check(MG.fieldQuiet() == true, "the field is quiet while it is on")
T.check(copies.A.game.overworld.map.id == "ROUTE16_GATE" and copies.A.game.overworld.player.cellX == 1
        and copies.A.game.overworld.player.cellY == 4 and copies.A.game.save.onBike == true,
        "A lined up at the start gate's west door, on the bike")
T.check(copies.B.game.overworld.player.cellY == 5, "B on the lane beside")
T.check(a.score == Bike.DNF and a.data.stage == "ride", "the clock runs; no time yet (DNF until the finish)")
for _ = 1, 58 do tick(0.1) end
a, b = results()
T.check(b.partnerScore == Bike.DNF, "the partner's HUD shows no time yet")
for _ = 1, 150 do tick(0.1) end
a, b = results()
T.check(a.phase == "waitResult" and a.final and b.phase == "play", "A is in, B still riding: A waits")
for _ = 1, 170 do tick(0.1) end
a, b = results()
T.check(a.final and b.final and a.final < b.final, ("both finished: A %s, B %s"):format(Bike.timeText(a.final), Bike.timeText(b.final)))
T.check(math.abs(a.final - 200) <= 2 and math.abs(b.final - 369) <= 2, "times measured from the line: " .. a.final .. " / " .. b.final)
T.check(a.result == "win" and b.result == "lose", "the same winner on both: A (" .. tostring(a.result) .. "/" .. tostring(b.result) .. ")")
T.check(a.partnerFinal == b.final and b.partnerFinal == a.final, "each has the other's time")
T.check(copies.A.game.save.coopBikeBest == a.final and copies.B.game.save.coopBikeBest == b.final, "best times kept per save")
local sawBest = false
for _, st in ipairs(statuses) do if st.text == "New best time!" then sawBest = true end end
T.check(sawBest, "a new best is announced")
local bBest = copies.B.game.save.coopBikeBest
for _ = 1, 80 do tick(0.1) end
use("A"); T.check(MG.session == nil and not MG.fieldQuiet(), "over: the field is the engine's again")
use("B"); MG.session = nil

-- race 2: B flies to Fuchsia and walks into the gate from ROUTE 18 -> no
-- finish; A rides; time runs out for B: DNF, A wins on both
play(ride(231), { [40] = { "ROUTE18", 2, 6 }, [60] = { "ROUTE17_ROUTE18_GATE", 9, 4 } })
for _ = 1, 31 + Bike.DURATION * 10 + 20 do tick(0.1) end
a, b = results()
T.check(b.final == Bike.DNF, "into the finish gate not from the road: no time (DNF)")
T.check(a.result == "win" and b.result == "lose", "a finisher beats a DNF on both copies")
T.check(copies.B.game.save.coopBikeBest == bBest, "a DNF leaves the best alone")
for _ = 1, 80 do tick(0.1) end
use("A"); MG.session = nil; use("B"); MG.session = nil

-- race 3: neither finishes: a draw on both
play({}, {})
for _ = 1, 31 + Bike.DURATION * 10 + 20 do tick(0.1) end
a, b = results()
T.check(a.result == "draw" and b.result == "draw", "two DNFs draw")
for _ = 1, 80 do tick(0.1) end
use("A"); MG.session = nil; use("B"); MG.session = nil

-- race 4: B is held up at the start (a transition for 15 s) and rides
-- faster; B crosses the line long after A, yet B's time is the lower one.
-- A must not settle on its own grace: both copies name B.
play(ride(231), { [330] = { "ROUTE17_ROUTE18_GATE", 0, 4 }, [300] = { "ROUTE17", 16, 82 }, [200] = { "ROUTE16", 9, 6 } })
copies.B.game.overworld.transitioning = true
for i = 1, 350 do
  if i == 180 then copies.B.game.overworld.transitioning = false end
  tick(0.1)
end
a, b = results()
T.check(a.final and b.final and b.final < a.final, ("B is slower to the line but faster: A %s, B %s")
        :format(Bike.timeText(a.final), Bike.timeText(b.final)))
T.check(a.result == "lose" and b.result == "win", "...and both copies name B (" .. tostring(a.result) .. "/" .. tostring(b.result) .. ")")
for _ = 1, 80 do tick(0.1) end
use("A"); MG.session = nil; use("B"); MG.session = nil

-- the overworld busy (a transition) delays the line-up instead of failing
play(ride(231), ride(231))
copies.A.game.overworld.transitioning = true
for _ = 1, 35 do tick(0.1) end
a = results()
T.check(a.phase == "play" and a.data.stage == "lineup" and copies.A.game.overworld.warps == 4, "busy: the line-up waits")
copies.A.game.overworld.transitioning = false
tick(0.1) tick(0.1)
a = results()
T.check(a.data.stage == "ride" and copies.A.game.overworld.warps == 5, "...and happens once the field is free")
use("A"); MG.abort(nil, true); pump()
use("B"); T.check(MG.session == nil, "leaving ends it on both")

-- the quiet field reaches the engine through lib/Hooks.lua
local Hooks = rawget(_G, "__PKMULTIPLAYER").hooks
local fake = { rollEncounter = function() return "wild" end, checkTrainerSight = function() return "spotted" end }
pcall(Hooks.modules["src.world.OverworldController"], fake)
use("A")
MG.session = { def = Bike.def, phase = "play" }
T.check(fake.rollEncounter(fake) == nil and fake.checkTrainerSight(fake) == nil, "on: no encounter, no trainer sight")
MG.session = nil
T.check(fake.rollEncounter(fake) == "wild" and fake.checkTrainerSight(fake) == "spotted", "off: the engine's own")
MG.session = { def = { quietField = false }, phase = "play" }
T.check(fake.rollEncounter(fake) == "wild", "a game that did not ask keeps encounters")
MG.session = nil

GameVersion.isGen2 = realGen2
T.finish("co-op bike trial")
