-- THE MINIGAME FRAME (1.20, src/coop/CoopMinigame.lua): register, the
-- capability gate, invite/accept/go, the countdown, scores both ways, the
-- shared result, leaving and the link dropping.  Two copies of the frame are
-- played against each other through a fake link (one module instance, its
-- state swapped between "A" and "B").
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local MG = require("src.coop.CoopMinigame")
require("src.coop.CoopLog").enabled = false
-- the real games (src/coop/mg) set aside: this suite plays its own two
local realGames, realOrder = MG.GAMES, MG.ORDER
MG.GAMES, MG.ORDER = {}, {}

-- a test game: score = how many times update ran with A held
local started, finished = {}, {}
MG.register({ id = "tap", name = "TAP RACE", info = { "TAP A!", "", "" }, duration = 2,
  start = function(s) started[#started + 1] = s.asker end,
  update = function(s, dt, game) if game.input:isDown("a") then s:setScore(s.score + 1) end end,
  finish = function(s, _, result) finished[#finished + 1] = result end })
MG.register({ id = "time", name = "TIME TRIAL", duration = 5, lowWins = true, start = function() end })

T.check(MG.GAMES.tap and MG.ORDER[1] == "tap", "a game registers")
T.check(CoopManager.CAPS["minigame.tap"], "...and announces its capability")
T.check(not pcall(MG.register, { id = "bad id", name = "X", start = function() end }), "an id with a space is refused")

-- outcome: the same from both sides
T.check(MG.outcome(MG.GAMES.tap, 5, 3) == "win" and MG.outcome(MG.GAMES.tap, 3, 5) == "lose", "higher wins")
T.check(MG.outcome(MG.GAMES.time, 30, 40) == "win" and MG.outcome(MG.GAMES.time, 40, 30) == "lose", "lowWins: lower wins")
T.check(MG.outcome(MG.GAMES.tap, 4, 4) == "draw", "a tie is a draw")
T.check(MG.outcome(MG.GAMES.tap, 4, nil) == "win" and MG.outcome(MG.GAMES.tap, nil, 4) == "lose"
        and MG.outcome(MG.GAMES.tap, nil, nil) == "none", "a missing score loses")

-- ------------------------------------------------- two copies, one link
local copies, queue = {}, {}
local function stackOf()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local held = {}
for _, name in ipairs({ "A", "B" }) do
  local game = { data = Data, save = { player = { name = name == "A" and "MOCHI" or "TOBY" } }, stack = stackOf(),
                 overworld = {} }
  game.input = { isDown = function(_, b) return held[name] == b end, wasPressed = function() return false end }
  copies[name] = { game = game, state = { session = nil, pending = nil, asked = nil } }
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
CoopManager.net = { send = function(_, m) queue[#queue + 1] = { from = active, m = m } return true end, flush = function() end }
CoopManager.isConnected = function() return true end
CoopManager.connected = true
CoopManager.overworldIdle = function() return true end
CoopManager.showStatus = function() end
local allCaps = CoopManager.capSet(CoopManager.localCaps())
CoopManager.partner.caps = allCaps
local function pump()
  for _ = 1, 50 do
    if #queue == 0 then return end
    local e = table.remove(queue, 1)
    local to = e.from == "A" and "B" or "A"
    use(to)
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

-- gate
CoopManager.partner.caps = {}
use("A")
T.check(#MG.available() == 0, "a partner without the capabilities: no games offered")
T.check(not MG.invite(copies.A.game, "tap"), "...and an invite is refused")
CoopManager.partner.caps = allCaps
T.check(#MG.available() == 2, "with them: both games offered")

-- invite -> accept -> go
use("A")
T.check(MG.invite(copies.A.game, "tap"), "A invites to TAP RACE")
pump()
use("B")
local modal = MG.asked
T.check(modal and modal.lines[2] == "WANTS TO PLAY!" and modal.lines[3] == "TAP RACE", "B is asked, the box names the game")
modal.onAccept()
pump()
use("A"); local sa = MG.session
use("B"); local sb = MG.session
T.check(sa and sb and sa.mid == sb.mid and sa.seed == sb.seed and sa.asker and not sb.asker,
        "both have the session: same id and seed, A is the asker")
local same, inRange = true, true
for _ = 1, 50 do
  local x, y = sa:random(1, 6), sb:random(1, 6)
  if x ~= y then same = false end
  if x < 1 or x > 6 then inRange = false end
end
T.check(same and inRange, "the seeded random gives the same numbers on both, in range")
T.check(sa.phase == "countdown" and sb.phase == "countdown", "both count down first")

-- countdown -> play; A holds A for 1 s, B for 0.5 s
for _ = 1, 31 do tick(0.1) end
T.check(#started == 2, "the game starts on both after the countdown")
held.A = "a"
for _ = 1, 10 do tick(0.1) end
held.A = nil; held.B = "a"
for _ = 1, 5 do tick(0.1) end
held.B = nil
use("A"); local scoreA = MG.session.score; local seenB = MG.session.partnerScore
use("B"); local scoreB = MG.session.score
T.check(scoreA == 10 and scoreB == 5, "each copy counts its own player: " .. scoreA .. " / " .. scoreB)
T.check(seenB ~= nil, "the partner's score reaches the other HUD")
for _ = 1, 10 do tick(0.1) end
use("A"); local ra = MG.session and MG.session.result
use("B"); local rb = MG.session and MG.session.result
T.check(ra == "win" and rb == "lose", "time up: A wins on A, loses... B loses on B (" .. tostring(ra) .. "/" .. tostring(rb) .. ")")
T.check(#finished == 2 and finished[1] ~= finished[2], "the game's finish runs on both with their own result")
for _ = 1, 70 do tick(0.1) end
use("A"); T.check(MG.session == nil, "the result goes away on its own")

-- leaving: B held on A's copy for 1 s ends it on both
use("A"); MG.invite(copies.A.game, "tap"); pump()
use("B"); MG.asked.onAccept(); pump()
for _ = 1, 31 do tick(0.1) end
held.A = "b"
for _ = 1, 11 do tick(0.1) end
held.A = nil
use("A"); local goneA = MG.session == nil
use("B"); local goneB = MG.session == nil
T.check(goneA and goneB, "holding B leaves the game on both copies")
T.check(finished[#finished] == "quit", "...and the game hears it was a quit")

-- the link dropping ends it
use("A"); MG.invite(copies.A.game, "tap"); pump()
use("B"); MG.asked.onAccept(); pump()
CoopManager.isConnected = function() return false end
use("A"); MG.update(0.1, copies.A.game, copies.A.game.overworld)
T.check(MG.session == nil, "the link gone: the game is over")
CoopManager.isConnected = function() return true end
use("B"); MG.session = nil

-- a declined invite and a busy partner
use("A"); MG.invite(copies.A.game, "tap"); pump()
use("B"); MG.asked.onDecline(); pump()
use("A"); T.check(MG.pending == nil and MG.session == nil, "a no clears the invite")
use("B"); MG.session = { mid = "x" }
use("A"); MG.invite(copies.A.game, "tap"); pump()
use("A"); T.check(MG.pending == nil, "a partner already playing answers busy")
use("B"); MG.session = nil

-- the menu shows MINIGAMES under PARTNER only when there is a game to play
local Menu = require("src.coop.CoopMenu")
local m = setmetatable({ game = copies.A.game }, { __index = Menu })
local function has(rows, label) for _, r in ipairs(rows) do if r.label == label then return r end end end
local partnerRows = m:connectedRows(nil, "partner")
T.check(has(partnerRows, "MINIGAMES") and has(partnerRows, "MYSTERY GIFT"), "PARTNER lists MINIGAMES, and the rows after it stay")
local list = m:connectedRows(nil, "minigames")
T.check(#list == 2 and list[1].label == "TAP RACE", "MINIGAMES lists the games")
CoopManager.partner.caps = {}
local without = m:connectedRows(nil, "partner")
T.check(not has(without, "MINIGAMES") and has(without, "MYSTERY GIFT"), "without a common game the row is not there")
CoopManager.partner.caps = allCaps

-- leave no test games behind for other suites
MG.GAMES, MG.ORDER = realGames, realOrder
CoopManager.CAPS["minigame.tap"], CoopManager.CAPS["minigame.time"] = nil, nil
T.finish("co-op minigame frame")
