-- THE BATTLE TOWER CHALLENGE IN DUO (nightly.2, src/coop/CoopTower.lua,
-- "tower.multi").  A challenge's first CO-OP DOUBLE carries a run id; once
-- the partner joined, the next battles of the same run go in with the same
-- teams, and a new challenge starts a new run.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local CoopTower = require("src.coop.CoopTower")
local BattleTower = require("src.world.BattleTower")
require("src.coop.CoopLog").enabled = false

CoopManager.connected = true
CoopManager.partner.caps = { [CoopTower.CAP] = true }

local save = { party = {} }
local game = { data = Data, save = save }
local s = BattleTower.state(save)
local battle = { battleTower = true }

-- the challenger
s.beaten = 0
CoopTower.run = nil
local run1 = CoopTower.runFor(game)
T.check(run1 and run1.id and not run1.partnerIn, "the first battle of a challenge opens a run")
T.check(CoopTower.autoTeam(game, battle) == nil, "...and asks as usual (the partner has not joined yet)")
local mons = { { hp = 30, species = "FIXMON_A" }, { hp = 0, species = "FIXMON_C" } }
run1.partnerIn, run1.team = true, mons
s.beaten = 1
T.check(CoopTower.runFor(game) == run1, "battle 2 of the same challenge: the same run")
local team = CoopTower.autoTeam(game, battle)
T.check(team and #team == 1 and team[1] == mons[1], "joined: battle 2 goes in with the same team (the fainted left out)")
CoopManager.partner.caps = {}
T.check(CoopTower.autoTeam(game, battle) == nil, "a partner without tower.multi is asked every battle")
CoopManager.partner.caps = { [CoopTower.CAP] = true }
s.beaten = 0
local run2 = CoopTower.runFor(game)
T.check(run2 ~= run1 and run2.id ~= run1.id, "the beaten count back to 0: a new run, asked again")
T.check(CoopTower.runFor(game) == run2, "...asked twice for the same battle, still the same run")
CoopTower.onLost()
T.check(CoopTower.runFor(game) ~= run2, "a lost battle: the next challenge is a new run")

-- the partner
local mine = { { hp = 40 }, { hp = 40 } }
CoopTower.joined = { id = "RUN-A", team = { mine[2] } }
T.check(CoopTower.autoAccept({ tower = { run = "RUN-A" } }, mine)[1] == mine[2], "the run we joined: straight in with the same team")
T.check(CoopTower.autoAccept({ tower = { run = "RUN-B" } }, mine) == nil, "another run: asked as usual")
T.check(CoopTower.autoAccept({ tower = { run = "RUN-A" } }, { mine[1] }) == nil, "our team no longer able (over the cap, fainted): asked")
T.check(CoopTower.autoAccept({ tower = {} }, mine) == nil, "an older challenger (no run): asked")

T.finish("tower challenge in duo")
