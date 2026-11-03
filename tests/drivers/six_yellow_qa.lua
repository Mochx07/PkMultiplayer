-- SIX QA: Yellow (Gen 1) adversarial test for M0/M1 features.
--
--   pair.sh <mod> six_yellow_qa.lua 7813 yellow PkReviewUI_Y1 PkReviewUI_Y2 <out>
--
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7813")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six_yellow") .. "/" .. role
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
  local I18n = require("src.coop.CoopI18n")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"

  -- In Yellow, give valid teams
  table.insert(save.party, Pokemon.new(game.data, "PIKACHU", 25))
  table.insert(save.party, Pokemon.new(game.data, "CHARMANDER", 15))
  U.teleport(game, "PALLET_TOWN", role == "host" and 5 or 7, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "joining 127.0.0.1:" .. port)
  end

  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "PALLET_TOWN" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked in Pallet Town")
  U.wait(60)
  check(CoopManager.bothHave("vs.formats"), "both have vs.formats in Yellow")

  -- Test menu navigation and B button in Yellow
  local CoopMenu = require("src.coop.CoopMenu")
  local menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(10)
  check((menu.page or "main") == "main", "menu opens on main page")
  U.shot(game, DIR .. "/menu_main.png")

  -- Navigate to PARTNER
  -- In connectedRows, PARTNER is row 5
  menu.index = 5
  U.wait(5)
  U.tap(game, "a")
  U.wait(10)
  check(menu.page == "partner", "opened PARTNER page")
  U.shot(game, DIR .. "/menu_partner.png")

  -- In PARTNER, BATTLE P1 VS P2 is row 4
  menu.index = 4
  U.wait(5)
  U.tap(game, "a")
  U.wait(10)
  check(menu.page == "vs", "opened VS formats page")
  U.shot(game, DIR .. "/menu_vs.png")

  -- Test B button navigation back
  U.tap(game, "b")
  U.wait(10)
  check(menu.page == "partner", "B button returned to PARTNER page")
  check(menu.index == 4, "cursor restored to BATTLE P1 VS P2 (index 4)")

  U.tap(game, "b")
  U.wait(10)
  check(menu.page == "main", "B button returned to MAIN page")
  check(menu.index == 5, "cursor restored to PARTNER (index 5)")

  U.tap(game, "b")
  U.wait(10)
  check(game.stack:top() ~= menu, "B button closed menu back to overworld")

  -- Now test inviting with LEVEL 50 in Yellow
  U.wait(30)
  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.lv50), "sent LEVEL 50 invite")
  else
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked ~= nil, "guest received battle invite")
    if asked then
      check(asked.lines[3] == "LEVEL 50 RULES", "invite names LEVEL 50 RULES")
      U.shot(game, DIR .. "/invite_yellow.png")
      U.wait(70)
      U.tap(game, "a")
    end
  end

  -- Wait for battle to open
  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if top and top.kind == "link" then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "link battle opened in Yellow")
  if battle then
    U.shot(game, DIR .. "/battle_yellow.png")
    U.log(role .. " yellow battle opened successfully!")
  end

  U.log(role .. " yellow done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
