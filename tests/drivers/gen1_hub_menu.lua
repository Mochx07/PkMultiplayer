-- HOST ONLINE / JOIN by the game's code, through the co-op menu
-- (nightly.3, B6).  The host opens CO-OP, picks HOST ONLINE and waits for
-- the code on screen; the guest opens CO-OP, JOIN, TYPE A CODE, types it
-- with the keyboard and presses ENTER: both end linked.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm")
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopMenu = require("src.coop.CoopMenu")
  local CoopHub = require("src.coop.CoopHub")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, Pokemon.new(game.data, role == "host" and "SQUIRTLE" or "BULBASAUR", 10))
  U.teleport(game, "PALLET_TOWN", role == "host" and 5 or 8, 8, "down")
  local menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(20)
  local function rowIndex(label)
    for i, r in ipairs(menu:offlineRows()) do
      if r.label == label then return i end
    end
  end
  local codeFile = DIR .. "/hub_menu_code.txt"
  if role == "host" then
    os.remove(codeFile)
    local i = rowIndex("HOST ONLINE")
    check(i ~= nil, "the co-op menu has HOST ONLINE")
    if not i then love.event.quit(1) return end
    menu.index = i
    U.tap(game, "a")
    for _ = 1, 60 * 30 do if CoopHub.code then break end U.wait(1) end
    U.wait(20)
    U.shot(game, DIR .. "/host/1_host_online.png")
    check(menu.stage == "hubHost" and CoopHub.code ~= nil, "the code is on screen: " .. tostring(CoopHub.code))
    local f = io.open(codeFile, "w") if f then f:write(CoopHub.code or "") f:close() end
  else
    local code
    for _ = 1, 60 * 60 do
      local f = io.open(codeFile, "r")
      if f then code = f:read("*a") f:close() end
      if code and code ~= "" then break end
      U.wait(1)
    end
    check(code and code ~= "", "read the host's code")
    menu.index = rowIndex("JOIN") or 1
    U.tap(game, "a") U.wait(10)
    local rows = menu:joinRows()
    for j, r in ipairs(rows) do if r.label == "TYPE A CODE" then menu.pickIndex = j end end
    U.tap(game, "a") U.wait(10)
    check(menu.stage == "codeEntry", "typing a code")
    menu:onTextInput(code)
    U.wait(10)
    U.shot(game, DIR .. "/guest/1_code_typed.png")
    menu:onKeyPressed("return")
    U.wait(5)
    check(menu.stage == "hubJoin" or CoopManager.isConnected(), "joining online (" .. tostring(menu.stage) .. ")")
    U.shot(game, DIR .. "/guest/2_joining.png")
  end
  local linked = false
  for _ = 1, 60 * 60 do
    if CoopManager.isConnected() and CoopManager.partner.name then linked = true break end
    U.wait(1)
  end
  check(linked, "linked with " .. tostring(CoopManager.partner.name))
  U.wait(30)
  U.shot(game, DIR .. "/" .. role .. "/3_linked.png")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
