-- Gen 1 CABLE CLUB WITH THE PARTNER (nightly.3, B6).  The host talks to the
-- Cable Club receptionist (saves, YES), is asked LINK WITH: <partner> /
-- OTHER, picks the partner and TRADE CENTER; the guest is asked on its own
-- screen and says yes: both games open the Cable Club's trade room through
-- the co-op link (no code, no second connection).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7918")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local MAP = "VIRIDIAN_POKECENTER"
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_STARTER, save.flags.EVENT_GOT_POKEDEX = true, true
  table.insert(save.party, Pokemon.new(game.data, role == "host" and "SQUIRTLE" or "BULBASAUR", 10))
  U.teleport(game, MAP, role == "host" and 3 or 4, 4, "up")
  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 40 do
    if CoopManager.isConnected() and CoopManager.partner.map == MAP then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both in " .. MAP)
  U.wait(90)
  local function top() return game.stack:top() end
  local function isLink(t) return t and t.coopTunnel == true end
  if role == "host" then
    game.overworld:cableClubReceptionist()
    -- the welcome and "we have to save": through to the YES/NO, then YES
    local asked = false
    for _ = 1, 60 * 20 do
      local t = top()
      if t and t.header == "LINK WITH" or (t and t.items and t.items[2] and t.items[2].label == "OTHER") then asked = true break end
      U.tap(game, "a") U.wait(20)
    end
    check(asked, "the receptionist asks who to link with")
    U.shot(game, DIR .. "/1_link_with.png")
    local t = top()
    check(t and t.items and t.items[1] and t.items[1].label == "TOBY", "first row is the partner: " .. tostring(t and t.items and t.items[1] and t.items[1].label))
    U.tap(game, "a") U.wait(20)
    U.shot(game, DIR .. "/2_which_room.png")
    U.tap(game, "a")   -- TRADE CENTER
  end
  local link
  for i = 1, 60 * 40 do
    local t = top()
    if isLink(t) then link = t break end
    if role == "guest" and t and t ~= game.overworld and i % 30 == 0 then
      if i == 30 * 4 then U.shot(game, DIR .. "/1_asked.png") end
      U.tap(game, "a")
    end
    U.wait(1)
  end
  check(link ~= nil, "the Cable Club is open through the co-op link")
  if link then
    for _ = 1, 60 * 20 do
      if link.mode == "trade" or link.stage == "trade" or (top() and top() ~= link and top().isTrade) then break end
      U.wait(1)
    end
    U.wait(60)
    U.shot(game, DIR .. "/3_room.png")
    U.log(role .. ": link stage " .. tostring(link.stage) .. " mode " .. tostring(link.mode))
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
