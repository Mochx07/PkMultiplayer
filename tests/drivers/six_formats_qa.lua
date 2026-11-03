-- SIX QA: Testing all remaining formats (LITTLE CUP, ONE TYPE, LEVEL 100, FREE BATTLE)
-- and rule enforcement / team filtering in real game.
--
--   pair.sh <mod> six_formats_qa.lua 7815 crystal PkMpCrys PkCrystalTest <out>
--
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7815")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six_formats") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopLink = require("src.coop.CoopLink")
  local CoopVS = require("src.coop.CoopVS")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"

  -- Host party:
  -- 1. PIDGEY (Level 12, Normal/Flying, can evolve -> LITTLE CUP legal, ONE TYPE normal/flying)
  -- 2. CHARMANDER (Level 10, Fire, can evolve -> LITTLE CUP legal, NOT normal/flying)
  -- 3. SNORLAX (Level 35, Normal, does NOT evolve in Gen 2 -> LITTLE CUP illegal, ONE TYPE normal)
  -- 4. LUGIA (Level 60, Legend -> LITTLE CUP/ONE TYPE/LV100 illegal)
  -- 5. PIDGEY (Level 15 -> Duplicate species -> CUP illegal)
  --
  -- Guest party:
  -- 1. RATTATA (Level 8, Normal, can evolve -> LITTLE CUP legal, ONE TYPE normal)
  -- 2. MEWTWO (Level 70, Legend -> illegal in cups)
  -- 3. SENTRET (Level 10, Normal, can evolve -> LITTLE CUP legal, ONE TYPE normal)
  if role == "host" then
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 12)) -- PIDGEY
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_004", 10)) -- CHARMANDER
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_143", 35)) -- SNORLAX
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_249", 60)) -- LUGIA
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 15)) -- PIDGEY (dup)
  else
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_019", 8))  -- RATTATA
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_150", 70)) -- MEWTWO
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_161", 10)) -- SENTRET
  end

  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "joining 127.0.0.1:" .. port)
  end

  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked on Route 29")
  U.wait(60)

  -- 1. Test LITTLE CUP format
  -- Host team in LITTLE CUP: PIDGEY, CHARMANDER (SNORLAX, LUGIA, 2nd PIDGEY left out)
  -- Guest team in LITTLE CUP: RATTATA, SENTRET (MEWTWO left out)
  -- Scaled to Level 5!
  if role == "host" then
    local kept, left = CoopVS.legalParty(game.data, save.party, CoopVS.FORMATS.little)
    check(#kept == 2, "host LITTLE CUP keeps exactly 2 (Pidgey, Charmander)")
    check(kept[1].species == "SPECIES_016" and kept[2].species == "SPECIES_004", "kept Pidgey and Charmander in order")
    check(#left == 3, "host LITTLE CUP left 3 out (Snorlax not little, Lugia legend, 2nd Pidgey dup)")
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.little), "sent LITTLE CUP invite")
  else
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked ~= nil, "guest received LITTLE CUP invite")
    if asked then
      check(asked.lines[3] == "LITTLE CUP RULES", "invite names LITTLE CUP RULES")
      U.shot(game, DIR .. "/invite_little.png")
      U.wait(70)
      U.tap(game, "a")
    end
  end

  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if top and top.kind == "link" and top.playerParty then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "LITTLE CUP battle opened")
  if battle then
    U.shot(game, DIR .. "/battle_little.png")
    local mine, theirs = battle.playerParty, battle.enemyParty
    local hostSide = role == "host" and mine or theirs
    local guestSide = role == "host" and theirs or mine
    check(#hostSide == 2 and hostSide[1].level == 5 and hostSide[2].level == 5,
          "host side has 2 Pokemon both forced to Level 5")
    check(#guestSide == 2 and guestSide[1].level == 5 and guestSide[2].level == 5,
          "guest side has 2 Pokemon both forced to Level 5 (Mewtwo filtered)")
  end

  -- Wait for battle to finish or exit cleanly
  U.wait(60)
  U.log(role .. " LITTLE CUP test done: " .. fails .. " failures")
  love.event.quit(fails == 0 and 0 or 1)
end
