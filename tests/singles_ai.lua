-- SMARTER TRAINERS (src/battle/SinglesAI.lua): a Gen 2 trainer in a single
-- battle picks its move with the doubles foes' scouting, by class; items,
-- switches and locked moves stay the cartridge's.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local GOLD
for _, id in ipairs({ "Gen2Recomp", "PkMultiplayerTest", "PkMultiplayerTest2", "PkMp15A" }) do
  local p = (os.getenv("HOME") or "") .. "/.local/share/love/" .. id .. "/gold/data/generated/moves.lua"
  local f = io.open(p, "rb")
  if f then f:close() GOLD = p break end
end
if not GOLD then print("SKIP smarter trainers: no Gold import") return end
for id, m in pairs(dofile(GOLD)) do if not Data.moves[id] then Data.moves[id] = m end end
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local SinglesAI = require("src.battle.SinglesAI")
SinglesAI.isGen2 = function() return true end

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end
local function battle(oppClass)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20, function(a) return a end) }
  local game = { data = Data, save = save, stack = newStack(),
                 input = { wasPressed = function() return false end, isDown = function() return false end } }
  local b = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  b.oppClass = oppClass
  local foe = b.enemy
  foe.curMoves = { { id = "GROWL", pp = 40 }, { id = "TACKLE", pp = 35 } }
  foe.mon.moves = foe.curMoves
  b.player.mon.hp = 2   -- one TACKLE knocks it out
  return b, foe
end
local function vanilla(pickIndex)
  return function(b, who) return (who or b.enemy).curMoves[pickIndex] end
end

local b, foe = battle("OPP_LEADER_FALKNER")
local got = SinglesAI.enemyAction(vanilla(1), b, foe)
T.check(got and got.id == "TACKLE", "a gym leader takes the knockout instead of GROWL (" .. tostring(got and got.id) .. ")")

local smart, n = 0, 200
for i = 1, n do
  local bb, ff = battle("OPP_YOUNGSTER")
  local s = i * 7919
  bb.rng = function(a, z)
    s = (s * 48271) % 2147483647
    local r = s / 2147483647
    if a and z then return a + math.floor(r * (z - a + 1)) end
    return r
  end
  local mv = SinglesAI.enemyAction(vanilla(1), bb, ff)
  if mv.id == "TACKLE" then smart = smart + 1 end
end
T.check(smart > n * 0.3 and smart < n * 0.7, ("a route trainer plays it smart about half the time (%d/%d)"):format(smart, n))

b, foe = battle("OPP_LEADER_FALKNER")
local item = { special = "enemyItem", id = "POTION" }
T.check(SinglesAI.enemyAction(function() return item end, b, foe) == item, "the class AI's item stays")
b.lockedAction = function() return foe.curMoves[1] end
T.check(SinglesAI.enemyAction(vanilla(1), b, foe).id == "GROWL", "a locked move stays")

b, foe = battle("OPP_LEADER_FALKNER")
b.coopDouble = true
T.check(SinglesAI.enemyAction(vanilla(1), b, foe).id == "GROWL", "a co-op double is the doubles AI's")
b, foe = battle("OPP_LEADER_FALKNER")
b.kind = "link"
T.check(SinglesAI.enemyAction(vanilla(1), b, foe).id == "GROWL", "a link battle is never touched")
SinglesAI.isGen2 = function() return false end
b, foe = battle("OPP_LEADER_FALKNER")
T.check(SinglesAI.enemyAction(vanilla(1), b, foe).id == "GROWL", "Red / Blue / Yellow keep the cartridge's AI")
package.loaded["pkmultiplayer.options"] = { on = function() return false end }
SinglesAI.isGen2 = function() return true end
b, foe = battle("OPP_LEADER_FALKNER")
T.check(SinglesAI.enemyAction(vanilla(1), b, foe).id == "GROWL", "SMARTER TRAINERS off: the cartridge's pick")
package.loaded["pkmultiplayer.options"] = nil

T.finish("smarter trainers")
