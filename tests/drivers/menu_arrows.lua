-- Screenshots of the title's main menu and the START menu, with the mod on:
-- is the cursor arrow drawn?
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/arrows"
  local menu
  for i = 1, 60 * 40 do
    local top = game.stack:top()
    if top and top.items and (top.choose or top.onSelect or top.index) and top ~= game.overworld then menu = top break end
    U.tap(game, (i % 20 == 0) and "a" or "start")
    U.wait(3)
  end
  U.wait(20)
  local labels = {}
  for _, it in ipairs(menu and menu.items or {}) do labels[#labels + 1] = tostring(it.label) end
  U.log("title menu: " .. table.concat(labels, " | ") .. " index=" .. tostring(menu and menu.index))
  U.shot(game, DIR .. "/1_title_menu.png")
  U.tap(game, "down") U.wait(10)
  U.shot(game, DIR .. "/2_title_menu_down.png")
  -- the START menu on the field
  local save = U.freshSave(game)
  save.player.name = "MOCHI"
  local sp = game.data.pokemon.PIKACHU and "PIKACHU" or next(game.data.pokemon)
  table.insert(save.party, require("src.pokemon.Pokemon").new(game.data, sp, 5))
  local map = game.data.maps.PALLET_TOWN and "PALLET_TOWN" or "NEW_BARK_TOWN"
  U.teleport(game, map, 5, 6, "down")
  U.wait(20)
  U.tap(game, "start") U.wait(20)
  U.shot(game, DIR .. "/3_start_menu.png")
  U.log("done")
  love.event.quit(0)
end
