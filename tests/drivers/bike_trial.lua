-- BIKE TRIAL (1.20, src/coop/mg/BikeTrial.lua), two real Gold copies linked
-- over 127.0.0.1.  Both stand in ROUTE 16 GATE with a BICYCLE; the host
-- invites from the frame, the guest presses A on the invite; after the
-- countdown each copy rides its own player out the west door, down ROUTE 17
-- and into the ROUTE 17 / 18 GATE, steering by a path search on the map
-- (the downhill road pulls on its own).  Each copy logs its time, the
-- partner's and the result; the shell compares the two copies' lines.
--
-- The guest plays in Spanish.
--
--   pair.sh <mod> tests/drivers/bike_trial.lua 7830 gold PkReviewUI_A PkReviewUI_B <out>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7830")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function waitFor(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  U.wait(5)
  pcall(function()
    local Pipelines = require("src.render.Pipelines")
    for _, e in ipairs(Pipelines.list()) do
      if e.def and e.def.drawWorld then Pipelines.setLevel(e.id, 0) end
    end
    require("src.render.Tilt").setLevel(0)
  end)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local MG = require("src.coop.CoopMinigame")
  local Bike = require("src.coop.mg.BikeTrial")
  -- the guest plays in Spanish, so the shots show both languages
  if role == "guest" then require("src.coop.CoopI18n").forced = "es" end
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local m = Pokemon.new(game.data, game.data.pokemon.SPECIES_160 and "SPECIES_160" or next(game.data.pokemon), 40)
  save.party[1] = m
  save.visited = save.visited or {}

  -- canStart before the bike, and away from the gate
  U.teleport(game, "CELADON_CITY", 10, 10, "down")
  local ok0, why0 = Bike.canStart(game, game.overworld)
  check(not ok0 and why0 == "You need a BICYCLE", "no bike: " .. tostring(why0))
  save.inventory.BICYCLE = 1
  local ok1, why1 = Bike.canStart(game, game.overworld)
  check(not ok1, "with a bike in Celadon: " .. tostring(why1))

  local lane = role == "host" and { 3, 4 } or { 3, 5 }
  U.teleport(game, Bike.START, lane[1], lane[2], "left")
  local ow = game.overworld
  check(ow.map.id == Bike.START and Bike.canStart(game, ow) == true, "in " .. Bike.START .. " with a bike: canStart ok")
  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  check(waitFor(60 * 30, function()
    return CoopManager.isConnected() and CoopManager.partner.map == Bike.START
  end), "linked, both in " .. Bike.START)
  U.wait(90)
  check(#MG.available() >= 1 and MG.GAMES.bike ~= nil, "the BIKE TRIAL is offered (both have minigame.bike)")

  if role == "host" then
    check(MG.invite(game, "bike", game.overworld), "host invites to the BIKE TRIAL")
  else
    check(waitFor(60 * 15, function() return MG.asked ~= nil end), "guest is asked")
    U.wait(70)
    U.shot(game, DIR .. "/invite.png")
    U.tap(game, "a")
  end
  check(waitFor(60 * 15, function() return MG.session ~= nil end), "the session is on")
  U.wait(60)
  U.shot(game, DIR .. "/countdown.png")
  check(waitFor(60 * 10, function() return MG.session and MG.session.phase == "play" end), "countdown over: play")

  -- ---------------------------------------------------------------- ride
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local ORDER = { "down", "left", "right", "up" }
  local function goalOf(o)
    local id, W, H = o.map.id, o.map.def.width * 2, o.map.def.height * 2
    if id == Bike.START then return function(x, y) return x == 0 and (y == 4 or y == 5) end, "left" end
    if id == "ROUTE16" then return function(x, y) return y == H - 1 end, "down" end
    if id == Bike.ROAD then return function(x, y) return x == 17 and (y == 82 or y == 83) end, "right" end
    return nil
  end
  -- breadth-first over walkable, unoccupied cells: the first step toward a goal
  local function nextDir(o)
    local goal, push = goalOf(o)
    if not goal then return nil end
    local px, py = o.player.cellX, o.player.cellY
    if goal(px, py) then return push end
    local W, H = o.map.def.width * 2, o.map.def.height * 2
    local seen, q, head = { [py * W + px] = "start" }, { { px, py } }, 1
    while q[head] do
      local c = q[head]; head = head + 1
      for _, d in ipairs(ORDER) do
        local nx, ny = c[1] + D[d][1], c[2] + D[d][2]
        local k = ny * W + nx
        if nx >= 0 and ny >= 0 and nx < W and ny < H and not seen[k]
           and (goal(nx, ny) or (o.map:isWalkableCell(nx, ny) and not o:npcAtCell(nx, ny))) then
          seen[k] = (c[1] == px and c[2] == py) and d or seen[c[2] * W + c[1]]
          if goal(nx, ny) then return seen[k] end
          q[#q + 1] = { nx, ny }
        end
      end
    end
    return push
  end
  local shotRoad, shotWait = false, false
  local lastKey, still = nil, 0
  local maps = {}
  for _ = 1, 60 * 100 do
    local s = MG.session
    if not s or s.phase ~= "play" then break end
    local o = game.overworld
    if o and o.map and s.data.stage == "ride" and game.stack:top() == o and not o.transitioning then
      maps[o.map.id] = true
      if o.map.id == Bike.ROAD and not shotRoad and o.player.cellY >= 30 then
        shotRoad = true
        U.shot(game, DIR .. "/road.png")
      end
      if not o.player.moving then
        local d = nextDir(o)
        if d then U.hold(game, d, 4) else U.wait(1) end
      else
        U.wait(1)
      end
      local key = o.map.id .. ":" .. o.player.cellX .. "," .. o.player.cellY
      if key == lastKey then still = still + 1 else still, lastKey = 0, key end
      if still > 600 then check(false, "stuck at " .. key) break end
    else
      if game.stack:top() ~= o and game.stack:top() and game.stack:top().update then
        -- a text box on the way (the gate officer): read on
        U.tap(game, "a")
      end
      U.wait(1)
    end
  end
  local s = MG.session
  check(s ~= nil and s.final ~= nil and s.final < Bike.DNF, "crossed the finish: " .. (s and Bike.timeText(s.final) or "?"))
  check(maps[Bike.ROAD] == true, "rode down " .. Bike.ROAD)
  if s and s.phase == "waitResult" then
    U.shot(game, DIR .. "/waiting.png")
    shotWait = true
  end
  check(waitFor(60 * 130, function() return MG.session and MG.session.phase == "result" end), "the result is in")
  s = MG.session
  U.wait(20)
  U.shot(game, DIR .. "/result.png")
  if s then
    U.log(("RESULT %s result=%s mine=%s theirs=%s"):format(role, tostring(s.result), tostring(s.final), tostring(s.partnerFinal)))
    check(s.partnerFinal ~= nil, "the partner's time arrived: " .. Bike.timeText(s.partnerFinal))
    check(Bike.best(save) == s.final, "best time kept in the save: " .. Bike.timeText(Bike.best(save)))
  end
  check(waitFor(60 * 10, function() return MG.session == nil end), "the result goes away")
  U.log(("%s done, %d failure(s)%s"):format(role, fails, shotWait and "" or " (no wait shot)"))
  U.wait(120)
  love.event.quit(fails == 0 and 0 or 1)
end
