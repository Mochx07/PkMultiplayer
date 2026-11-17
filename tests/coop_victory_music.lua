-- THE WILD JINGLE WAITS FOR THE LAST FOE (lib/Hooks.lua, playVictoryMusic).
--
-- The engine starts the victory theme as each wild mon's faint slide lands;
-- in a double (a co-op wild pair, Gen 1 and Gen 2) that played while the
-- twin was still standing.  The wrapper lets it through only when the far
-- side is out, and a single battle is untouched.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local BattleState = require("src.battle.BattleState")
local Music = require("src.core.Music")
local GameVersion = require("src.core.GameVersion")

local played = {}
Music.playVictory = function(_, kind) played[#played + 1] = kind end

local function fake(double, foesStanding)
  local b = setmetatable({ data = Data, musicKind = "wild" }, { __index = BattleState })
  b.isDouble = function() return double end
  b.sideCanContinue = function(_, isPlayer)
    if isPlayer then return true end
    return foesStanding > 0
  end
  return b
end

for _, ver in ipairs({ "gold", "red" }) do
  GameVersion.set(ver)
  played = {}
  local b = fake(true, 1)
  b:playVictoryMusic()
  T.check(#played == 0 and not b.victoryMusicPlayed,
          ver .. ": one wild foe of two down, the twin standing: no jingle yet")
  T.check(not b.lowHealthAlarmDisabled, ver .. ": ...and the low-health alarm is left alone")
  b.sideCanContinue = function(_, isPlayer) return isPlayer and true or false end
  b:playVictoryMusic()
  T.check(#played == 1 and b.victoryMusicPlayed, ver .. ": the last foe down: the jingle plays")
  b:playVictoryMusic()
  T.check(#played == 1, ver .. ": ...once")

  played = {}
  local s = fake(false, 1)
  s:playVictoryMusic()
  T.check(#played == 1, ver .. ": a single battle plays it as the engine does")
end

T.finish("victory jingle in doubles")
