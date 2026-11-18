-- No partner: the co-op menu's EMOTE row opens the picker and the bubble
-- shows over your own player (it used to close the menu and do nothing).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/emote_solo"
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
  end
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = "MOCHI"
  local sp = game.data.pokemon.PIKACHU and "PIKACHU" or game.data.pokemon.SPECIES_025 and "SPECIES_025" or next(game.data.pokemon)
  table.insert(save.party, require("src.pokemon.Pokemon").new(game.data, sp, 5))
  U.teleport(game, game.data.maps.PALLET_TOWN and "PALLET_TOWN" or "NEW_BARK_TOWN", 5, 6, "down")
  check(not CoopManager.isConnected(), "no partner")
  local CoopMenu = require("src.coop.CoopMenu")
  local menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(10)
  local rows = menu:offlineRows()
  local at
  for i, r in ipairs(rows) do if r.label == "EMOTE" then at = i end end
  check(at ~= nil, "the offline menu has EMOTE")
  U.shot(game, DIR .. "/0_menu.png")
  if at then
    menu.index = at
    U.wait(5)
    U.tap(game, "a")
    U.wait(15)
    local top = game.stack:top()
    check(top and top.isEmotePicker, "EMOTE opens the picker")
    U.shot(game, DIR .. "/1_picker.png")
    U.tap(game, "a")
    U.wait(10)
    check(CoopManager.localEmote ~= nil, "the bubble is up over the player (" .. tostring(CoopManager.localEmote) .. ")")
    check(game.stack:top() == game.overworld, "back on the field")
    U.shot(game, DIR .. "/2_bubble.png")
  end
  U.log(("done: %d failures"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
