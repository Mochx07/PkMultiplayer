-- CO-OP DIFFICULTY (src/coop/CoopBalance.lua): the trainer of a co-op double
-- is made a match for the two of you, the same way on both copies.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Pokemon = require("src.pokemon.Pokemon")
local CoopManager = require("src.coop.CoopManager")
local CoopBalance = require("src.coop.CoopBalance")
require("src.coop.CoopLog").enabled = false

local function team(n, level)
  local out = {}
  for i = 1, n do out[i] = Pokemon.new(Data, i % 2 == 0 and "FIXMON_B" or "FIXMON_A", level, function(a) return a end) end
  return out
end
local function battle(n, level) return { data = Data, enemyParty = team(n, level) } end

T.check(CoopManager.balancedFoes == true and CoopManager.hardFoes == false,
        "BALANCED FOES is on and HARD FOES off by default")

-- three of yours, three of theirs, against a gym leader's two
local b = battle(2, 12)
local changed = CoopBalance.apply(b, team(3, 14), team(3, 14))
T.check(changed and #b.enemyParty == 4, "six against two: the trainer brings four (" .. #b.enemyParty .. ")")
T.check(b.enemyParty[3].species == b.enemyParty[1].species and b.enemyParty[4].species == b.enemyParty[2].species,
        "the extra ones are its own team again, in order")
T.check(b.enemyParty[1].level == 13, "a team a little behind yours goes up a level (" .. b.enemyParty[1].level .. ")")
local def = Data.pokemon[b.enemyParty[1].species]
local Stats = require("src.pokemon.Stats")
T.check(b.enemyParty[1].stats.hp == Stats.calc(def, 13, b.enemyParty[1].dvs, b.enemyParty[1].statExp).hp
        and b.enemyParty[1].hp == b.enemyParty[1].stats.hp, "its stats are worked out for the new level")

-- far ahead: two levels
local far = battle(2, 10)
CoopBalance.apply(far, team(2, 20), team(2, 20))
T.check(far.enemyParty[1].level == 12, "a team far behind goes up two")

-- the same on both copies (the lists arrive the other way round on the guest)
local hostCopy, guestCopy = battle(3, 15), battle(3, 15)
local mine, theirs = team(3, 18), team(2, 25)
CoopBalance.apply(hostCopy, mine, theirs)
CoopBalance.apply(guestCopy, theirs, mine)
local same = #hostCopy.enemyParty == #guestCopy.enemyParty
for i, m in ipairs(hostCopy.enemyParty) do
  local g = guestCopy.enemyParty[i]
  same = same and g and g.species == m.species and g.level == m.level and g.hp == m.hp
end
T.check(same, "both copies build the very same team")

-- a trainer already strong enough is left alone
local strong = battle(6, 40)
T.check(not CoopBalance.apply(strong, team(3, 20), team(3, 20)) and #strong.enemyParty == 6,
        "a full team of higher levels is not touched")

-- HARD FOES: one for each, three levels up
CoopManager.hardFoes = true
local hard = battle(2, 12)
CoopBalance.apply(hard, team(3, 12), team(3, 12))
T.check(#hard.enemyParty == 6 and hard.enemyParty[1].level == 15, "HARD FOES: one foe each, three levels up")
CoopManager.hardFoes = false

-- off, and the battles it never touches
CoopManager.balancedFoes = false
local plain = battle(2, 12)
T.check(not CoopBalance.apply(plain, team(3, 20), team(3, 20)) and #plain.enemyParty == 2,
        "both rules off: the cartridge's team")
CoopManager.balancedFoes = true
for _, flag in ipairs({ "coopWild", "battleTower", "isLinkBattle" }) do
  local x = battle(1, 5)
  x[flag] = true
  T.check(not CoopBalance.apply(x, team(3, 30), team(3, 30)) and #x.enemyParty == 1, flag .. " is never balanced")
end

T.finish("co-op difficulty")
