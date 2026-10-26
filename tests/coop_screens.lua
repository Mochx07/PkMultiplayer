-- ONE SCREEN FOR THE SIDE (lib/Hooks.lua, Hooks.sharedScreens): in a co-op
-- double a REFLECT raised by one Pokemon cuts the damage its partner takes
-- too, as in HeartGold/SoulSilver; outside co-op nothing changes.
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
local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 30, function(a) return a end) }
local game = { data = Data, save = save, stack = newStack(),
               input = { wasPressed = function() return false end, isDown = function() return false end } }
local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
game.stack:push(battle)
CoopManager.net = { send = function() end, flush = function() end, isLinked = function() return true end }
local partner = { CoopManager.wireMon(Pokemon.new(Data, "FIXMON_B", 30, function(a) return a end)) }
CoopBattle.initBattle(battle, save.party, partner, { name = "TOBY" }, 77, "SCR")

local foe = battle:battlerAt(P.OPPONENT_LEFT)
local mine, theirs = battle:battlerAt(P.PLAYER_LEFT), battle:battlerAt(P.PLAYER_RIGHT)
local move
for id, m in pairs(Data.moves) do
  if (tonumber(m.power) or 0) >= 40 and not require("src.battle.Damage").isSpecial(m.type) then move = m break end
end
assert(move and foe and mine and theirs, "fixture battle")
local function hit(target)
  local d = battle:computeDamage(foe, target, move, { noCrit = true, crit = false, roll = 255 })
  return type(d) == "table" and (d.damage or d[1]) or d
end
local base = hit(theirs)
mine.reflect = true
local covered = hit(theirs)
T.check(type(base) == "number" and type(covered) == "number" and covered < base,
        ("a partner's REFLECT cuts the hit (%s -> %s)"):format(tostring(base), tostring(covered)))
mine.reflect = nil
theirs.reflect = true
local own = hit(theirs)
T.check(own == covered, "...by as much as its own REFLECT would")
theirs.reflect = nil
T.check(hit(theirs) == base, "no screen up: the hit as it was")

-- not a co-op battle: the cartridge's rule (only the Pokemon that raised it)
local was = CoopBattle.currentBattle
CoopBattle.currentBattle = nil
mine.reflect = true
T.check(hit(theirs) == base, "outside co-op a screen covers only its own Pokemon")
mine.reflect = nil
CoopBattle.currentBattle = was

-- a spread move's animation plays on each foe it hits, in a co-op double
local Hooks = rawget(_G, "__PKMULTIPLAYER").hooks
local V = require("src.core.GameVersion")
local realGen2, realGen1 = V.isGen2, V.isGen1
V.isGen2, V.isGen1 = function() return true end, function() return false end
T.check(Hooks.animateEachTarget({ coopDouble = true }, true) == false,
        "Gold/Silver/Crystal: a spread move animates on the second foe too")
T.check(Hooks.animateEachTarget({}, true) == true, "...only in a co-op double")
V.isGen2 = function() return false end
T.check(Hooks.animateEachTarget({ coopDouble = true }, true) == true,
        "later generations keep their one field-wide animation")
V.isGen2, V.isGen1 = realGen2, realGen1

-- Gen 1 animations: an object at a single-battle pic's centre lands on the
-- centre of the Pokemon actually there (OAM = screen + 8, + 16)
local so = {
  player = { to = { 36 - 24 - 30, 68 - 24 + 4 }, size = 48, k = 1 },   -- the partner's slot, 30 px left
  enemy = { to = { 124 - 28 + 20, 28 - 28 + 10 }, size = 56, k = 1 },  -- the right-hand foe
}
local dx, dy = Hooks.gen1Offset(so, 124 + 8, 28 + 16)
T.check(dx == 20 and dy == 10, ("a hit on the foe's pic lands on the foe really hit (%d,%d)"):format(dx, dy))
dx, dy = Hooks.gen1Offset(so, 36 + 8, 68 + 16)
T.check(dx == -30 and dy == 4, ("an attack leaves from the Pokemon really attacking (%d,%d)"):format(dx, dy))

T.finish("co-op shared screens")
