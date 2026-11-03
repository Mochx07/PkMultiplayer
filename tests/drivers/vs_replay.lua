-- A P1-VS-P2 BATTLE AND ITS REPLAY, two Gold copies (1.20).
--
--   pair.sh <mod> vs_replay.lua <port> gold <host> <guest> <out>
--
-- A LEVEL 50 battle (SNORLAX + RATTATA against PIDGEY + SENTRET) is played
-- to the end by pressing A on both copies.  Each copy notes how it ended --
-- every Pokemon's HP, host side and guest side, and who won -- then plays
-- the replay it recorded (CoopReplay) and notes the same at the replay's
-- end.  The replay must end exactly like the battle did.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/vsr") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopLink = require("src.coop.CoopLink")
  local CoopVS = require("src.coop.CoopVS")
  local CoopReplay = require("src.coop.CoopReplay")
  local save = U.freshSave(game)
  save.options = save.options or {}
  save.options.animations = false
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local team = role == "host" and { { "SPECIES_143", 40 }, { "SPECIES_019", 20 } }
               or { { "SPECIES_016", 10 }, { "SPECIES_161", 12 } }
  for _, t in ipairs(team) do table.insert(save.party, Pokemon.new(game.data, t[1], t[2])) end
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
  local replaysBefore = #CoopReplay.list()

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
  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.lv50), "LEVEL 50 invite sent")
  else
    for _ = 1, 60 * 20 do if CoopLink.asked then break end U.wait(1) end
    U.wait(70)
    U.tap(game, "a")
  end

  -- host-side and guest-side HP, the same order on both copies
  local function ending(b)
    local host = role == "host" and b.playerParty or b.enemyParty
    local guest = role == "host" and b.enemyParty or b.playerParty
    if b.spectating then host, guest = b.playerParty, b.enemyParty end
    local o = {}
    for _, m in ipairs(host or {}) do o[#o + 1] = tostring(m.hp) end
    o[#o + 1] = "|"
    for _, m in ipairs(guest or {}) do o[#o + 1] = tostring(m.hp) end
    return table.concat(o, " ")
  end
  local function playOut(match, frames)
    local b
    for _ = 1, 60 * 40 do
      local top = game.stack:top()
      if top and match(top) then b = top break end
      U.wait(1)
    end
    if not b then return nil end
    local last
    for _ = 1, frames do
      local top = game.stack:top()
      if top == b then last = ending(b) end
      if top == game.overworld then break end
      if top == b and b.phase == "moveSelect" then U.tap(game, "a") U.wait(4)
      elseif top == b or (top and top ~= game.overworld) then U.tap(game, "a") U.wait(6)
      else U.wait(1) end
    end
    return b, last
  end

  local live, liveEnd = playOut(function(t) return t.kind == "link" and not t.spectating end, 60 * 120)
  check(live ~= nil, "the link battle opened")
  if live then
    U.log(role .. ": battle ended '" .. tostring(liveEnd) .. "' result " .. tostring(live.result))
    check(game.stack:top() == game.overworld, "back in the overworld after the battle")
  end
  U.wait(60)
  local names = CoopReplay.list()
  check(#names == replaysBefore + 1, "the battle left a replay (" .. #names .. " now)")
  local replay = names[1] and CoopReplay.load(names[1])
  check(replay and replay.format == "lv50" and #replay.log > 0, "the replay reads back, LEVEL 50, with turns")
  if replay then U.log(role .. ": replay " .. names[1] .. " " .. #replay.log .. " messages, me=" .. tostring(replay.me)) end

  if replay then
    check(CoopReplay.play(game, names[1]), "the replay starts")
    local spec, specEnd = playOut(function(t) return t.spectating end, 60 * 120)
    check(spec ~= nil, "the replay plays as a spectated battle")
    U.log(role .. ": replay ended '" .. tostring(specEnd) .. "'")
    check(specEnd == liveEnd, "the replay ends exactly like the battle did")
    check(game.stack:top() == game.overworld, "back in the overworld after the replay")
  end
  U.log(role .. " done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
