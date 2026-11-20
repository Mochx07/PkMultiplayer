-- CO-OP THROUGH THE GAME'S LINK LADDER / HUB (nightly.3, B6).  The host
-- hosts with CoopHub (the engine's Connector: LAN, router, hole punch, the
-- Link Hub), writes the game's invite code; the guest joins with it; once
-- the ladder connects, CoopNet adopts the connection and it is an ordinary
-- co-op link: both linked, names known, positions shared.
-- PKM_HUB_ONLY=1: the guest drops the LAN address from the code, so only
-- the hub (or the outside address) can reach the host.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local DIR = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopHub = require("src.coop.CoopHub")
  local MAP = "PALLET_TOWN"
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, Pokemon.new(game.data, role == "host" and "SQUIRTLE" or "BULBASAUR", 10))
  U.teleport(game, MAP, role == "host" and 5 or 8, 8, "down")
  check(CoopHub.available(), "the game has its link ladder")
  local codeFile = DIR .. "/hub_code.txt"
  if role == "host" then
    os.remove(codeFile)
    check(CoopHub.host(game), "hosting through the ladder")
    for _ = 1, 60 * 30 do if CoopHub.code or CoopHub.state == "failed" then break end U.wait(1) end
    check(CoopHub.code ~= nil, "a code to read out (" .. tostring(CoopHub.codeKind) .. "): " .. tostring(CoopHub.code)
          .. " " .. tostring(CoopHub.error or ""))
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
    check(CoopHub.isGameCode(code), "it is the game's own invite code")
    if os.getenv("PKM_HUB_ONLY") == "1" then
      local InviteCode = require("src.online.InviteCode")
      local inv = InviteCode.decode(code)
      U.log("guest: code kind " .. tostring(inv and inv.kind) .. " lan " .. tostring(inv and inv.lan))
    end
    local ok, why = CoopHub.join(game, code)
    check(ok, "joining through the ladder " .. tostring(why or ""))
  end
  local linked = false
  for _ = 1, 60 * 60 do
    if CoopManager.isConnected() and CoopManager.partner.map == MAP then linked = true break end
    if CoopHub.state == "failed" then break end
    U.wait(1)
  end
  U.log(("%s: hub state %s, status %s, error %s"):format(role, tostring(CoopHub.state), tostring(CoopHub.status), tostring(CoopHub.error)))
  check(linked, "linked as a co-op pair, both in " .. MAP)
  check(CoopManager.partner.name == (role == "host" and "TOBY" or "MOCHI"), "partner's name: " .. tostring(CoopManager.partner.name))
  check(CoopManager.net and CoopManager.net.adopted == true, "the co-op link is the adopted connection")
  -- the link carries the co-op traffic: a chat line both ways
  CoopManager.sendChat("HI FROM " .. save.player.name)
  local heard = false
  for _ = 1, 60 * 15 do
    for _, line in ipairs(CoopManager.chatLog or {}) do
      if tostring(line.text):find("^HI FROM ") and line.sender ~= save.player.name then heard = true end
    end
    if heard then break end
    U.wait(1)
  end
  check(heard, "chat crosses the adopted link")
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
