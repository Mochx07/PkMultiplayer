-- Red/Blue <-> Yellow through the version matrix (src/coop/CoopEditions.lua),
-- two real copies.  The host runs a story script with one shared flag and one
-- its own edition only has; the guest must get the shared one, not the other.
--   host Yellow: EVENT_BEAT_MT_MOON_3_JESSIE_JAMES (Yellow's scripts)
--   host Red:    EVENT_BEAT_MT_MOON_3_SUPER_NERD   (Red's trainer data)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7802")
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local GV = require("src.core.GameVersion")
  local me = GV.get()
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, require("src.pokemon.Pokemon").new(game.data, "PIKACHU", 10))
  U.teleport(game, "PALLET_TOWN", role == "host" and 5 or 8, 8, "down")
  if role == "host" then check(CoopManager.host(port), "hosting")
  else U.wait(60) check(CoopManager.join("127.0.0.1", port), "dialling") end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "PALLET_TOWN" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked (" .. me .. " with " .. tostring(CoopManager.partner.game) .. ")")
  check(CoopManager.storyCompatible(), "one story across the editions")
  U.wait(60)
  local SHARED = "EVENT_GOT_POKEDEX"
  local OWN = me == "yellow" and "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES" or "EVENT_BEAT_MT_MOON_3_SUPER_NERD"
  local THEIR_OWN = me == "yellow" and "EVENT_BEAT_MT_MOON_3_SUPER_NERD" or "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES"
  if role == "host" then
    local ow = game.overworld
    ow.runner:run({ { "set_flag", SHARED }, { "set_flag", OWN } }, { mapId = "PALLET_TOWN" })
    for _ = 1, 120 do if not ow.runner:isRunning() then break end U.wait(1) end
    check(save.flags[SHARED] and save.flags[OWN], "the host lived it: " .. SHARED .. " + " .. OWN)
    U.wait(240)
  else
    for _ = 1, 60 * 15 do
      if save.flags[SHARED] then break end
      U.wait(1)
    end
    U.wait(60)
    check(save.flags[SHARED] == true, "the shared event arrived: " .. SHARED)
    check(not save.flags[THEIR_OWN], "the other edition's own event did not: " .. THEIR_OWN)
  end
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
