-- SIX QA: Compatibility test with peer without 1.20 (vs.formats disabled on guest).
--
--   pair.sh <mod> six_compat_qa.lua 7814 gold PkMp15B PkMpBigB <out>
--
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7814")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six_compat") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopMenu = require("src.coop.CoopMenu")
  local CoopLink = require("src.coop.CoopLink")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"

  table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 20))
  table.insert(save.party, Pokemon.new(game.data, "SPECIES_019", 20))
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  -- Guest simulates being a 1.6.x peer without vs.formats
  if role == "guest" then
    CoopManager.CAPS["vs.formats"] = nil
    U.log("guest: simulated non-1.20 peer by removing vs.formats from CAPS")
  end

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

  -- Verify capability check
  check(not CoopManager.bothHave("vs.formats"), "bothHave(vs.formats) is false as expected")
  if role == "host" then
    check(CoopManager.CAPS["vs.formats"] == true, "host has vs.formats locally")
    check(not CoopManager.partnerHas("vs.formats"), "host knows partner does not have vs.formats")
  else
    check(CoopManager.CAPS["vs.formats"] == nil, "guest has no vs.formats locally")
    check(CoopManager.partnerHas("vs.formats"), "guest sees host has vs.formats")
  end

  -- Host checks menu: PARTNER -> BATTLE P1 VS P2
  if role == "host" then
    local menu = CoopMenu.new(game)
    game.stack:push(menu)
    U.wait(10)
    -- PARTNER page
    menu.index = 5
    U.tap(game, "a")
    U.wait(10)
    check(menu.page == "partner", "host opened PARTNER page")

    local rows = menu:connectedRows(game.overworld, "partner")
    local battleRow = rows[4]
    check(battleRow and battleRow.label == "BATTLE P1 VS P2", "row 4 is BATTLE P1 VS P2")
    check(battleRow and battleRow.sub == nil, "BATTLE P1 VS P2 has NO subpage (fallback to direct invite)")
    U.shot(game, DIR .. "/host_compat_partner_menu.png")

    -- Trigger the battle invite via menu row
    battleRow.run()
    U.wait(10)
    check(CoopLink.pending ~= nil, "host sent direct classic battle invite")
  else
    -- Guest waits for classic battle invite
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked ~= nil, "guest received classic battle invite")
    if asked then
      check(asked.lines[3] == "P1 VS P2 BATTLE?", "invite says P1 VS P2 BATTLE? (no format rules)")
      U.shot(game, DIR .. "/guest_compat_invite.png")
      U.wait(70)
      U.tap(game, "a")
    end
  end

  -- Verify link battle opens (in classic battle without format, host confirms level menu)
  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if role == "host" and top and top.stage == "battleOptions" then
      U.log("host is on Cable Club level menu (battleOptions): pressing A to proceed")
      U.tap(game, "a")
    end
    if top and top.kind == "link" then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "classic link battle opened between 1.20 and non-1.20 peer")
  if battle then
    U.shot(game, DIR .. "/compat_battle.png")
    U.log(role .. " classic link battle opened successfully!")
  end

  U.log(role .. " compat done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
