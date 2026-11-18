-- The partner's head on the TOWN MAP (CoopTownMap), Red host + Yellow guest.
-- Host in Pallet Town, guest in Viridian City; each opens the TOWN MAP and
-- screenshots it.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7808")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, require("src.pokemon.Pokemon").new(game.data, "PIKACHU", 10))
  local MY = role == "host" and "PALLET_TOWN" or "VIRIDIAN_CITY"
  local THEIRS = role == "host" and "VIRIDIAN_CITY" or "PALLET_TOWN"
  U.teleport(game, MY, 8, 8, "down")
  if role == "host" then check(CoopManager.host(port), "hosting")
  else U.wait(60) check(CoopManager.join("127.0.0.1", port), "dialling") end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == THEIRS then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, the partner in " .. THEIRS)
  U.wait(30)
  local TownMap = require("src.ui.TownMap")
  local tm = TownMap.new(game)
  game.stack:push(tm)
  U.wait(10)
  local CoopTownMap = require("src.coop.CoopTownMap")
  local x, y = CoopTownMap.point(tm)
  U.log(("%s: map mode %s, partner at %s,%s"):format(role, tostring(tm.mode), tostring(x), tostring(y)))
  check(x ~= nil, "the partner has a place on the map")
  U.shot(game, DIR .. "/townmap.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
