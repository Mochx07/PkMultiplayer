-- A LEVEL 50 VS BATTLE THROUGH THE CABLE CLUB, two Gold copies (1.20).
--
--   pair.sh <mod> vs_level50.lua <port> gold <host> <guest> <out>
--
-- Host: LUGIA 60 (a legend), SNORLAX 40, SNORLAX 35 (same species).
-- Guest: PIDGEY 10, PIDGEY 12 (same species), MEWTWO 70 (a legend).
-- The host invites with LEVEL 50, the guest accepts; the link battle that
-- opens must have, on both screens, one SNORLAX against one PIDGEY, both at
-- level 50, and the host must never see the Cable Club's level menu.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/vs") .. "/" .. role
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
  local team = role == "host" and { { "SPECIES_249", 60 }, { "SPECIES_143", 40 }, { "SPECIES_143", 35 } }
               or { { "SPECIES_016", 10 }, { "SPECIES_016", 12 }, { "SPECIES_150", 70 } }
  for _, t in ipairs(team) do table.insert(save.party, Pokemon.new(game.data, t[1], t[2])) end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both on Route 29")
  U.wait(60)
  check(CoopManager.bothHave("vs.formats"), "both copies have vs.formats")

  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.lv50), "LEVEL 50 invite sent")
  else
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked and asked.lines and asked.lines[3] == "LEVEL 50 RULES", "the invite names LEVEL 50 RULES")
    U.shot(game, DIR .. "/invite.png")
    U.wait(70)
    U.tap(game, "a")
  end

  local sawLevelMenu = false
  local lastWhere
  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if top and top.stage == "battleOptions" then sawLevelMenu = true end
    local where = tostring(top and (top.stage or top.kind or top.phase)) .. "/" .. tostring(top and top.__name or "")
    if where ~= lastWhere then U.log(role .. " top: " .. where) lastWhere = where end
    if top and top.kind == "link" and top.playerParty then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "the link battle opened")
  check(not sawLevelMenu, "the Cable Club's level menu was skipped")
  if battle then
    U.wait(30)
    U.shot(game, DIR .. "/battle.png")
    local mine, theirs = battle.playerParty, battle.enemyParty
    local function desc(p)
      local o = {}
      for _, m in ipairs(p or {}) do o[#o + 1] = tostring(m.species) .. "@" .. tostring(m.level) end
      return table.concat(o, " ")
    end
    U.log(role .. ": mine [" .. desc(mine) .. "] theirs [" .. desc(theirs) .. "]")
    local snorlax = role == "host" and mine or theirs
    local pidgey = role == "host" and theirs or mine
    check(#snorlax == 1 and snorlax[1].species == "SPECIES_143" and snorlax[1].level == 50,
          "the host plays one SNORLAX at 50 (LUGIA banned, second SNORLAX out)")
    check(#pidgey == 1 and pidgey[1].species == "SPECIES_016" and pidgey[1].level == 50,
          "the guest plays one PIDGEY at 50 (second PIDGEY and MEWTWO out)")
  end
  U.log(role .. " done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
