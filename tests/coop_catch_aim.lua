-- THROWING IN TIME (nightly.3, CoopCatch "catch.aim"): both press A as the
-- ring closes; the worse of the two misses sets the joint throw's bonus.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local CoopCatch = require("src.coop.CoopCatch")
require("src.coop.CoopLog").enabled = false

-- the bonus
local function mul(a, b) return (CoopCatch.aimBonus(a, b)) end
T.check(mul(40, 90) == 3.0, "both within 100 ms: PERFECT (x3)")
T.check(mul(40, 200) == 2.25, "the worse within 250 ms: GREAT")
T.check(mul(300, 10) == 1.75, "within 450 ms: GOOD")
T.check(mul(10, 600) == CoopCatch.JOINT, "one of you late: the plain joint throw (x1.5)")
T.check(mul(nil, 10) == CoopCatch.JOINT, "no press: the plain joint throw")
T.check(mul(90, 240) == mul(240, 90), "the same on both copies (host and guest swap mine/theirs)")

-- the ring, on a fake battle
local sent = {}
CoopManager.connected = true
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m end }
CoopManager.partner.caps = { [CoopCatch.CAP] = true, [CoopCatch.AIM_CAP] = true }
local pressed = false
local states = {}
local game = { stack = { states = states, push = function(self, s) states[#states + 1] = s end },
               input = { wasPressed = function(_, k) return k == "a" and pressed end } }
local ran = 0
package.loaded["src.coop.CoopBattle"] = { executeTurn = function() ran = ran + 1 end }
local battle = { kind = "wild", coopWild = true, game = game, data = {}, coop = { turn = 5 } }
local mine = { coopBall = "POKE_BALL" }
local wire = { ball = "GREAT_BALL" }

T.check(not CoopCatch.holdForAim(battle, 5, mine, { kind = "move" }), "only one ball: no ring")
-- the partner's miss comes first
CoopManager.handlers.coop_catch_aim(nil, { turn = 5, miss = 120 })
T.check(CoopCatch.holdForAim(battle, 5, mine, wire), "both throw: the turn waits for the ring")
local ring = states[#states]
T.check(ring and ring.isCoopAim and ring.aim.theirs == 120, "the ring is up, with the partner's early press")
T.check(CoopCatch.holdForAim(battle, 5, mine, wire), "asked again while it is up: still waiting")
-- press at 1.25 s: 50 ms late
local t = 0
while t < 1.25 - 1e-9 do ring:update(1 / 80) t = t + 1 / 80 end
pressed = true
ring:update(0)
pressed = false
T.check(ring.aim.mine ~= nil and math.abs(ring.aim.mine - 50) <= 15, "my miss measured (" .. tostring(ring.aim.mine) .. " ms)")
T.check(sent[#sent] and sent[#sent].type == "coop_catch_aim" and sent[#sent].turn == 5, "my miss went to the partner")
T.check(ran == 1 and #states == 0, "both in: the ring closes and the turn runs")
T.check(battle.coopAim and battle.coopAim.turn == 5 and battle.coopAim.theirs == 120, "the battle keeps both misses for the throw")
T.check(not CoopCatch.holdForAim(battle, 5, mine, wire), "the turn is not held twice")
local m = CoopCatch.aimBonus(battle.coopAim.mine, battle.coopAim.theirs)
T.check(m == 2.25, "50 and 120 ms: GREAT, x2.25")

-- nobody presses, the partner never answers: the turn still runs
battle.coopAim = nil
CoopCatch.holdForAim(battle, 6, mine, wire)
ring = states[#states]
for _ = 1, 60 * 10 do ring:update(1 / 60) if #states == 0 then break end end
T.check(#states == 0 and ran == 2 and battle.coopAim.mine == CoopCatch.MISS_MS
        and battle.coopAim.theirs == CoopCatch.MISS_MS, "no press, no answer: the turn runs as a plain joint throw")

-- an older partner (no catch.aim): no ring
CoopManager.partner.caps = { [CoopCatch.CAP] = true }
battle.coopAim = nil
T.check(not CoopCatch.holdForAim(battle, 7, mine, wire), "a partner without catch.aim: no ring")
package.loaded["src.coop.CoopBattle"] = nil
T.finish("throwing in time")
