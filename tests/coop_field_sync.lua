-- THE FIELD IN THE HOST'S SYNC (nightly.2, CoopBattle.packField / fieldSig /
-- applyField).  Weather and each side's screens and hazards are part of the
-- sync now: a guest whose REFLECT or SANDSTORM counted differently takes the
-- host's, and the drift is counted.  And the host's word on the last turn is
-- applied as the next turn starts, not dropped when both land together.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopBattle = require("src.coop.CoopBattle")
require("src.coop.CoopLog").enabled = false

local function battle(weather, turns, reflect, spikes)
  local sides = { { screens = { reflect = reflect }, hazards = {} }, { screens = {}, hazards = { spikes = spikes } } }
  return { field = { weather = weather, weatherTurns = turns, sides = sides }, sides = sides,
           battlerAt = function() return nil end, enemyParty = {}, coop = { turn = 3 } }
end

local host = battle("SANDSTORM", 3, 4, 1)
local guest = battle("SANDSTORM", 2, nil, 1)
local hs = CoopBattle.fieldSig(CoopBattle.packField(host))
local gs = CoopBattle.fieldSig(CoopBattle.packField(guest))
T.check(hs ~= gs, "a weather turn and a REFLECT apart: the field signatures differ")
T.check(CoopBattle.fieldSig(CoopBattle.packField(battle("SANDSTORM", 3, 4, 1))) == hs, "the same field: the same signature")

local before = CoopBattle.desyncs or 0
CoopBattle.applySync(guest, { turn = 2, field = CoopBattle.packField(host), fieldSig = hs })
T.check(CoopBattle.fieldSig(CoopBattle.packField(guest)) == hs, "the guest takes the host's field")
T.check(guest.field.weatherTurns == 3 and guest.sides[1].screens.reflect == 4, "...weather turns and REFLECT")
T.check((CoopBattle.desyncs or 0) == before + 1, "...and the drift is counted")
CoopBattle.applySync(guest, { turn = 2, field = CoopBattle.packField(host), fieldSig = hs })
T.check((CoopBattle.desyncs or 0) == before + 1, "agreeing again: nothing counted")

-- an older host (no field in the sync): nothing changes
local old = battle("RAIN", 1, nil, nil)
CoopBattle.applySync(old, { turn = 2 })
T.check(old.field.weather == "RAIN", "an older host's sync leaves the field alone")

T.finish("the field in the sync")
