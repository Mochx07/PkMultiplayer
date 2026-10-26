-- A BIG BATTLE WAITS FOR THE PARTNER.
--
-- Reported from play: "en la batalla de la torre quemada el rival aparece de
-- un solo y nos hace que la batalla en duo no funcione".  The BURNED TOWER's
-- rival walks up the moment you step onto the floor (a scene the map runs as
-- it loads), so whoever got there first was never asked CO-OP or SOLO -- the
-- partner was not on the map yet -- and when the partner walked in, their own
-- copy of the scene fired again on their game.
--
--   * the first one in is asked WAIT or SOLO; WAIT tells the partner's game
--     to hold its copy of the scene, and resumes once the partner is on the
--     map -- into the usual CO-OP/SOLO question;
--   * the partner's game, holding, does not play that scene at all;
--   * the hold lifts when the first one's scene is over.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopStory = require("src.coop.CoopStory")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
CoopManager.isConnected = function() return true end
CoopManager.storySync = true
CoopManager.partner = CoopManager.partner or {}
CoopManager.partner.name = "TOBY"
CoopManager.partner.healthy = 3
CoopManager.partner.map = "ECRUTEAK_CITY"
local offered = {}
local realOffer = CoopManager.offerBigBattle
CoopManager.offerBigBattle = function(ctx, class, party) offered[#offered + 1] = class end

-- the Menu is answered by hand
local menus = {}
package.loaded["src.ui.Menu"] = { new = function(game, items, opts)
  local m = { items = items, opts = opts }
  menus[#menus + 1] = m
  return m
end }

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name)
  local save = SaveData.newGame()
  save.player.name = name
  save.coopPartner = "TOBY"
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

-- a runner whose script is a coroutine, the way ScriptRunner drives one
local function newRunner()
  local r = {}
  function r:yield() return coroutine.yield() end
  function r:resume() local ok, err = coroutine.resume(self.co) assert(ok, err) end
  return r
end

local SCRIPT = { { "g2_load_trainer", "OPP_RIVAL1", 9 }, { "start_battle" } }

local function topWait(game)
  local top = game.stack:top()
  return (top and getmetatable(top) == CoopStory.WaitHere) and top or nil
end

-- ---------------------------------------------------------------------
-- the first one in: WAIT, the hold goes out, the partner arrives
-- ---------------------------------------------------------------------
local gameA = newGame("MOCHI")
local owA = { game = gameA, map = { id = "BURNED_TOWER1_F" } }
local runnerA = newRunner()
local ctxA = { game = gameA, save = gameA.save, overworld = owA, runner = runnerA, mapId = "BURNED_TOWER1_F" }
local finished = false
runnerA.co = coroutine.create(function()
  CoopStory.begin(ctxA, SCRIPT)
  finished = true
end)
runnerA:resume()
T.check(#menus == 1, "the first one in is asked before the scene plays (" .. #menus .. " menus)")
local labels = {}
for _, it in ipairs(menus[1] and menus[1].items or {}) do labels[#labels + 1] = it.label end
T.check(table.concat(labels, "|") == "WAIT TOBY|SOLO", "WAIT or SOLO (" .. table.concat(labels, "|") .. ")")
menus[1].items[1].onSelect()
local hold
for _, m in ipairs(sent) do if m.type == "coop_story_hold" then hold = m end end
T.check(hold and hold.map == "BURNED_TOWER1_F" and hold.class == "OPP_RIVAL1", "the partner's game is told to hold the scene")
local w = topWait(gameA)
T.check(w ~= nil, "a wait box is up")
for _ = 1, 60 * 20 do if w then w:update(1 / 60) end end
T.check(not finished, "with the partner still away, the scene keeps waiting")

-- ---------------------------------------------------------------------
-- the partner's game: holding, its own copy of the scene does not play
-- ---------------------------------------------------------------------
CoopStory.onPartnerHold(hold)
local gameB = newGame("TOBY")
local owB = { game = gameB, map = { id = "BURNED_TOWER1_F" } }
local ctxB = { game = gameB, save = gameB.save, overworld = owB, runner = newRunner(), mapId = "BURNED_TOWER1_F" }
local before = #menus
CoopStory.begin(ctxB, SCRIPT)
T.check(ctxB.coopSkipScript == true, "the partner's own copy of the held scene is skipped")
T.check(#menus == before, "...and they are not asked anything by it")
-- another map's scene is not held
local ctxB2 = { game = gameB, save = gameB.save, overworld = { game = gameB, map = { id = "ROUTE_36" } },
                runner = newRunner() }
local nB = #menus
ctxB2.runner.co = coroutine.create(function() CoopStory.begin(ctxB2, SCRIPT) end)
ctxB2.runner:resume()
T.check(not ctxB2.coopSkipScript, "a scene on another map is not held")
if #menus > nB then menus[#menus].items[2].onSelect() end
menus[#menus] = nil

-- the real ScriptRunner does not run a skipped script's rows
do
  local ScriptRunner = require("src.script.ScriptRunner")
  local ran = false
  local Commands = require("src.script.Commands")
  Commands.pkm_test_mark = function() ran = true end
  local owR = { game = gameB, map = { id = "BURNED_TOWER1_F" } }
  local runner = ScriptRunner.new(gameB, owR)
  owR.runner = runner
  pcall(function() runner:run({ { "g2_load_trainer", "OPP_RIVAL1", 9 }, { "pkm_test_mark" } }, { mapId = "BURNED_TOWER1_F" }) end)
  T.check(not ran, "ScriptRunner plays none of a held scene's rows")
  Commands.pkm_test_mark = nil
end

-- ---------------------------------------------------------------------
-- the partner walks in: the scene goes on into CO-OP or SOLO
-- ---------------------------------------------------------------------
CoopManager.partner.map = "BURNED_TOWER1_F"
for _ = 1, 60 * 3 do if topWait(gameA) then topWait(gameA):update(1 / 60) end end
T.check(topWait(gameA) == nil, "the wait box closes once the partner is here")
T.check(offered[1] == "OPP_RIVAL1", "the usual CO-OP / SOLO question follows")
T.check(finished and ctxA.coopStory and ctxA.coopStory.here == true, "the scene goes on with the partner in it")

-- the scene ends: the hold lifts
sent = {}
CoopStory.finish(ctxA)
local release
for _, m in ipairs(sent) do if m.type == "coop_story_release" then release = m end end
T.check(release ~= nil, "the partner's hold is lifted when the scene is over")
CoopStory.onPartnerRelease(release)
T.check(not CoopStory.heldHere(owB, "OPP_RIVAL1"), "...and their game no longer holds it")

-- ---------------------------------------------------------------------
-- SOLO, B, the time running out, or no link: the scene plays alone
-- ---------------------------------------------------------------------
do
  CoopManager.partner.map = "ECRUTEAK_CITY"
  menus = {}
  local game = newGame("MOCHI")
  local ow = { game = game, map = { id = "BURNED_TOWER1_F" } }
  local runner = newRunner()
  local ctx = { game = game, save = game.save, overworld = ow, runner = runner }
  offered = {}
  local done = false
  runner.co = coroutine.create(function() CoopStory.begin(ctx, SCRIPT) done = true end)
  runner:resume()
  menus[1].items[2].onSelect()
  T.check(done and #offered == 0 and not ctx.coopStory.here, "SOLO: the scene plays alone at once")

  menus = {}
  local ctx2 = { game = game, save = game.save, overworld = ow, runner = newRunner() }
  local done2 = false
  ctx2.runner.co = coroutine.create(function() CoopStory.begin(ctx2, SCRIPT) done2 = true end)
  ctx2.runner:resume()
  menus[1].items[1].onSelect()
  local wt = topWait(game)
  for _ = 1, math.ceil(CoopStory.WAIT_MAX + 2) * 60 do if topWait(game) then topWait(game):update(1 / 60) end end
  T.check(done2 and not ctx2.coopStory.here, "nobody came in time: the scene plays alone")

  menus = {}
  local ctx3 = { game = game, save = game.save, overworld = ow, runner = newRunner() }
  local done3 = false
  ctx3.runner.co = coroutine.create(function() CoopStory.begin(ctx3, SCRIPT) done3 = true end)
  ctx3.runner:resume()
  menus[1].items[1].onSelect()
  CoopManager.isConnected = function() return false end
  if topWait(game) then topWait(game):update(1 / 60) end
  T.check(done3 and not ctx3.coopStory.here, "the link drops: the scene plays alone")
  CoopManager.isConnected = function() return true end
end

CoopManager.offerBigBattle = realOffer
T.finish("co-op big battle waits for the partner")
