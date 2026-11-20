-- THE CABLE CLUB WITH THE PARTNER (src/coop/CoopCableClub.lua).
--
-- Only the Gen 1 receptionist's link door (room "any", no phase, no role)
-- with a partner on the line is taken over; Gen 2/3 room scripts (phase
-- "connect") and any game without a partner keep the engine's door.
--
--   luajit <mod>/tests/run.lua <mod>/tests/coop_cableclub.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local fails, total = 0, 0
local function check(ok, msg)
  total = total + 1
  print((ok and "ok   " or "FAIL ") .. msg)
  if not ok then fails = fails + 1 end
end

local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false
local GV = require("src.core.GameVersion")
local CC = require("src.coop.CoopCableClub")

local gen1 = true
local realIsGen1 = GV.isGen1
GV.isGen1 = function() return gen1 end
local connected = true
local realConnected = CoopManager.isConnected
CoopManager.isConnected = function() return connected end

check(CC.applies("any", {}) == true, "Gen 1 receptionist with a partner: asks who to link with")
check(CC.applies("any", nil) == true, "no opts at all is the receptionist too")
check(CC.applies("any", { phase = "connect" }) == false, "a room script's connect phase is left alone")
check(CC.applies("any", { role = "host" }) == false, "a door that already knows HOST/JOIN is left alone")
check(CC.applies("trade", {}) == false, "a named room is left alone")
connected = false
check(CC.applies("any", {}) == false, "no partner: the engine's door")
connected = true
gen1 = false
check(CC.applies("any", {}) == false, "Gen 2/3: the engine's door")
gen1 = true

local rows = CC.rows("toby")
check(rows[1] == "TOBY" and rows[2] == "OTHER", "rows: the partner's name first, then OTHER")
check(#CC.rows("AVERYLONGNAMEINDEED")[1] <= 10, "a long name fits the menu row")
check(CC.rows(nil)[1] == "PARTNER", "no name: PARTNER")

-- OTHER hands the call on to the engine's door untouched
local pushed = {}
local game = { stack = { push = function(_, s) pushed[#pushed + 1] = s end } }
package.loaded["src.ui.Menu"] = { new = function(_, items, opts) return { items = items, opts = opts } end }
local seen
CC.open(game, function(g, room, opts, onDone) seen = { g, room, opts, onDone } end, "any", { x = 1 }, "cb")
local menu = pushed[1]
check(menu and menu.opts.header == "LINK WITH", "the question is LINK WITH")
menu.items[2].onSelect()
check(seen and seen[2] == "any" and seen[3].x == 1 and seen[4] == "cb", "OTHER opens the engine's door with the same arguments")
-- B is the receptionist's "Please come again!"
local result
CC.open(game, function() end, "any", {}, function(r) result = r end)
pushed[#pushed].opts.onCancel()
check(result == "noconnect", "B answers noconnect (her 'Please come again!')")

GV.isGen1 = realIsGen1
CoopManager.isConnected = realConnected
print(("%d/%d checks passed  (Cable Club with the partner)"):format(total - fails, total))
if fails > 0 then os.exit(1) end
