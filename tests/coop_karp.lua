-- THE MAGIKARP CONTEST (1.20 M3, src/coop/mg/MagikarpContest.lua): it loads
-- with the co-op and registers on the minigame frame, measures with the
-- engine's own Lake of Rage routine, only starts at the lake with a rod, takes
-- the engine's hooked battle (measured, let go, no battle) and plays a full
-- two-copy contest through the frame: both copies agree on the winner, the
-- prize comes once a day.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local MG = require("src.coop.CoopMinigame")
require("src.coop.CoopLog").enabled = false
local Karp = require("src.coop.mg.MagikarpContest")

-- ----------------------------------------------------------- loading
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end end
T.check(has(CoopManager.FEATURES, "src.coop.mg.MagikarpContest"), "the contest is a co-op FEATURE (it loads)")
local mainSrc = io.open((os.getenv("PKM_MOD") or (arg and arg[0] and arg[0]:match("^(.*)/tests/") or ".")) .. "/main.lua")
local mainText = mainSrc and mainSrc:read("*a") or ""
if mainSrc then mainSrc:close() end
T.check(mainText == "" or mainText:find('"src.coop.mg.MagikarpContest"', 1, true), "...and in main.lua's MODULES")
T.check(MG.GAMES.karp == Karp.def and has(MG.ORDER, "karp"), "it registers on the frame as \"karp\"")
T.check(CoopManager.CAPS["minigame.karp"], "...behind its capability")
T.check(Karp.def.duration == 120 and not Karp.def.lowWins, "two minutes, the longest wins")

-- ----------------------------------------------------------- the measure
local fn, text = Karp.engine()
T.check(type(fn) == "function" and type(text) == "function", "the engine's magikarpLength / lengthText are found")
local function mon(a, d, s, p) return { species = "SPECIES_129", dvs = { attack = a, defense = d, speed = s, special = p } } end
-- worked by hand from CalcMagikarpLength: all-zero DVs and ID 0 is the
-- `b == 0, c < 10` row, 190 mm -> 7"; all-15 DVs and ID 0 run off the table:
-- (65535 - 65510) + 1600 = 1625 mm -> 63" = 5'03"
T.check(Karp.measure(mon(0, 0, 0, 0), 0) == 7, "DVs 0 / ID 0 measure 0'07\" (got " .. tostring(Karp.measure(mon(0, 0, 0, 0), 0)) .. ")")
T.check(Karp.measure(mon(15, 15, 15, 15), 0) == 63, "DVs 15 / ID 0 measure 5'03\"")
local feet, inches = fn(mon(8, 3, 11, 6), 12345)
T.check(Karp.measure(mon(8, 3, 11, 6), 12345) == feet * 12 + inches, "the score is the engine's feet * 12 + inches")
T.check(Karp.lengthText(63) == "5'03\"" and Karp.def.scoreText(63) == "5'03\"", "shown the cartridge's way: 5'03\"")
T.check(Karp.def.scoreText(0) == "-", "nothing caught shows -")

-- ----------------------------------------------------------- where it starts
Data.items.OLD_ROD = { id = "OLD_ROD", key = "OLD_ROD", index = 58, name = "OLD ROD", price = 0 }
Data.items.GREAT_BALL = { id = "GREAT_BALL", key = "GREAT_BALL", index = 4, name = "GREAT BALL", price = 600, ball = "GREAT_BALL" }
local GV = require("src.core.GameVersion")
local realGen2 = GV.isGen2
GV.isGen2 = function() return true end
local lake = { map = { id = "LAKE_OF_RAGE" } }
local function gameWith(inv) return { data = Data, save = { inventory = inv, player = { id = 0, name = "MOCHI" } } } end
local ok, why = Karp.canStart(gameWith({ OLD_ROD = 1 }), { map = { id = "ROUTE43" } })
T.check(not ok and why == "Go to the LAKE OF RAGE", "away from the lake: it says where to go")
ok, why = Karp.canStart(gameWith({}), lake)
T.check(not ok and why == "You need a ROD", "no rod: it says so")
T.check(Karp.canStart(gameWith({ OLD_ROD = 1 }), lake), "at the lake with a rod: it can start")
GV.isGen2 = function() return false end
ok, why = Karp.canStart(gameWith({ OLD_ROD = 1 }), lake)
T.check(not ok and why == "Only in Gen 2", "not offered on a Gen 1 game")
GV.isGen2 = function() return true end

-- ----------------------------------------------------------- the hooked battle
-- the newWild wrapper marks a rod's battle, and only that one
local BattleState = require("src.battle.BattleState")
local fixA = Data.pokemon.FIXMON_A
local markGame = { data = Data, save = require("src.core.SaveData").newGame(Data.field and Data.field.boot), stack = { push = function() end } }
markGame.save.party = {}
local okH, hooked = pcall(BattleState.newWild, markGame, "FIXMON_A", 5, { hooked = true })
local okW, walked = pcall(BattleState.newWild, markGame, "FIXMON_A", 5, nil)
T.check(okH and hooked and hooked.pkmHooked == true, "a rod's wild battle is marked as hooked (" .. tostring(okH and "" or hooked) .. ")")
T.check(okW and walked and not walked.pkmHooked, "...a wild battle from a step is not")
T.check(fixA ~= nil, "fixture species present")

-- ------------------------------------------------- two copies, one link
local copies, queue = {}, {}
local function stackOf()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
for _, name in ipairs({ "A", "B" }) do
  local game = { data = Data, stack = stackOf(), overworld = lake,
                 save = { inventory = { OLD_ROD = 1 }, player = { name = name == "A" and "MOCHI" or "TOBY", id = name == "A" and 0 or 4660 } } }
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
  MG.game = copies[name].game   -- the frame's "this copy's game" (one per process in a real run)
  CoopManager.getLocalPlayerName = function() return name == "A" and "MOCHI" or "TOBY" end
end
CoopManager.net = { send = function(_, m) queue[#queue + 1] = { from = active, m = m } return true end, flush = function() end }
CoopManager.isConnected = function() return true end
CoopManager.connected = true
CoopManager.overworldIdle = function() return true end
local statuses = {}
CoopManager.showStatus = function(s) statuses[#statuses + 1] = s end
CoopManager.realDate = function(f) return os.date(f, 86400 * 400) end
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
local function tick(dt)
  for _, n in ipairs({ "A", "B" }) do
    use(n); MG.update(dt, copies[n].game, copies[n].game.overworld)
  end
  pump()
end
-- what the engine's castLine hands pushBattle after "Oh! It's a bite!"
local function bite(name, species, dvs)
  use(name)
  local g = copies[name].game
  local battle = { game = g, pkmHooked = true, enemy = { name = species == "SPECIES_129" and "MAGIKARP" or "GYARADOS",
                   mon = { species = species, dvs = dvs } } }
  local before = #g.stack.states
  local took = Karp.onHooked(g.overworld, battle)
  return took, g.stack.states[before + 1]
end

T.check(not Karp.onHooked(lake, { pkmHooked = true, enemy = { mon = mon(15, 15, 15, 15) } }),
        "no contest on: a bite is the engine's battle as always")

use("A")
T.check(MG.invite(copies.A.game, "karp"), "A asks B to the MAGIKARP CONTEST")
pump()
use("B")
T.check(MG.asked and MG.asked.lines[3] == "MAGIKARP CONTEST", "B is asked, the box names the contest")
MG.asked.onAccept()
pump()
-- a bite in the countdown is let go, uncounted
local took, box = bite("A", "SPECIES_129", { attack = 15, defense = 15, speed = 15, special = 15 })
T.check(took and box and MG.session.score == 0, "a bite in the countdown is let go, not counted")
for _ = 1, 31 do tick(0.1) end
use("A"); T.check(MG.session and MG.session.phase == "play", "after the countdown the contest is on")

-- A: a small one, then a big one, then a GYARADOS; B: a middling one
took, box = bite("A", "SPECIES_129", { attack = 0, defense = 0, speed = 0, special = 0 })
T.check(took and box and MG.session.score == 7 and MG.session.data.catches == 1, "A's first MAGIKARP: 0'07\", no battle, a box says so")
took = bite("A", "SPECIES_129", { attack = 15, defense = 15, speed = 15, special = 15 })
T.check(took and MG.session.score == 63 and MG.session.data.catches == 2, "A's second: 5'03\" is the new best")
took = bite("A", "SPECIES_130", { attack = 15, defense = 15, speed = 15, special = 15 })
T.check(took and MG.session.score == 63 and MG.session.data.catches == 2, "a GYARADOS gets away and does not count")
local bLen = Karp.measure(mon(2, 5, 7, 1), 4660)
took = bite("B", "SPECIES_129", { attack = 2, defense = 5, speed = 7, special = 1 })
use("B"); T.check(took and MG.session.score == bLen, "B's MAGIKARP is measured with B's trainer ID: " .. Karp.lengthText(bLen))
-- through the engine's own OverworldState:pushBattle, as castLine calls it
local okOW, OW = pcall(require, "src.world.OverworldController")
use("B")
local nB = MG.session.data.catches
local pushed = false
local fakeOw = setmetatable({ map = { id = "LAKE_OF_RAGE" } }, { __index = function(_, k)
  if k == "pkmPushed" then return nil end
  return function() pushed = true end
end })
local okP, errP = pcall(okOW and OW.pushBattle, fakeOw, { game = copies.B.game, pkmHooked = true,
  enemy = { name = "MAGIKARP", mon = mon(2, 5, 7, 1) } })
T.check(okOW and okP and not pushed and MG.session.data.catches == nB + 1,
        "OverworldState:pushBattle hands a hooked fish to the contest, no battle (" .. tostring(errP) .. ")")
T.check(copies.A.game.save.party == nil and copies.B.game.save.party == nil, "no MAGIKARP went into a party")

-- time up: both copies settle the same result
for _ = 1, 1205 do tick(0.1) end
use("A"); local ra, fa, pa = MG.session and MG.session.result, MG.session and MG.session.final, MG.session and MG.session.partnerFinal
use("B"); local rb, fb, pb = MG.session and MG.session.result, MG.session and MG.session.final, MG.session and MG.session.partnerFinal
T.check(fa == 63 and pb == 63 and fb == bLen and pa == bLen, "both copies hold the same two lengths")
local winnerA = (ra == "win") and "A" or (ra == "lose") and "B" or "draw"
local winnerB = (rb == "win") and "B" or (rb == "lose") and "A" or "draw"
T.check(bLen < 63 and ra == "win" and rb == "lose" and winnerA == winnerB,
        "both copies name the same winner (" .. tostring(ra) .. " / " .. tostring(rb) .. ")")
local inv = copies.A.game.save.inventory
T.check(inv.GREAT_BALL == 1 and copies.A.game.save.coopKarpPrizeDay, "the winner gets one GREAT BALL")
T.check(not copies.B.game.save.inventory.GREAT_BALL, "the other gets nothing")
-- a bite after the whistle is let go too
took, box = bite("A", "SPECIES_129", { attack = 15, defense = 15, speed = 15, special = 15 })
T.check(took and MG.session.final == 63, "a bite after the whistle is let go, the result stands")
for _ = 1, 80 do tick(0.1) end
use("A"); T.check(MG.session == nil, "the result goes away on its own")

-- the prize is once a day
T.check(Karp.givePrize(copies.A.game) == "already" and inv.GREAT_BALL == 1, "a second win the same day gives no second prize")
CoopManager.realDate = function(f) return os.date(f, 86400 * 401) end
T.check(Karp.givePrize(copies.A.game) == "given" and inv.GREAT_BALL == 2, "...the next day it does")

-- a contest nobody fished: no winner, no prize
CoopManager.realDate = function(f) return os.date(f, 86400 * 402) end
use("A"); MG.invite(copies.A.game, "karp"); pump()
use("B"); MG.asked.onAccept(); pump()
for _ = 1, 1300 do tick(0.1) end
T.check(inv.GREAT_BALL == 2, "a draw at 0 gives no prize")

-- leaving mid-contest: the hook lets the next bite be a battle again
use("A"); MG.invite(copies.A.game, "karp"); pump()
use("B"); MG.asked.onAccept(); pump()
for _ = 1, 31 do tick(0.1) end
MG.abort("You left the game", true); pump()
use("A")
T.check(MG.session == nil and not Karp.onHooked(lake, { pkmHooked = true, enemy = { mon = mon(1, 1, 1, 1) } }),
        "after leaving, a bite is a battle again")

GV.isGen2 = realGen2
T.finish("magikarp contest")
