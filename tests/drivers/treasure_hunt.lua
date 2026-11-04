-- TREASURE HUNT (1.20, src/coop/mg/Treasure.lua), two real copies linked over
-- 127.0.0.1, on a route with grass and ledges (Gold: Route 29; Yellow: Route 1).
--
--   round 1: the host asks, the guest joins.  Both log the hidden cell and the
--            guest checks the host's cell is its own.  The guest stands far,
--            mid and near and reads COLD / WARM / HOT, presses A on a wrong
--            cell (nothing); then the host steps onto the cell and presses A:
--            the host wins on both, the guest stops.
--   round 2: the guest asks and finds it: the guest wins on both.
--
--   pair.sh <mod> tests/drivers/treasure_hunt.lua 7810 gold PkMp15B PkMpBigB <out>
--   pair.sh <mod> tests/drivers/treasure_hunt.lua 7811 yellow PkReviewUI_Y1 PkReviewUI_Y2 <out>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7810")
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
  local CoopManager = require("src.coop.CoopManager")
  local MG = require("src.coop.CoopMinigame")
  local Treasure = require("src.coop.mg.Treasure")
  local Collision = require("src.world.Collision")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.repelSteps = 0

  local MAP
  for _, id in ipairs({ "ROUTE29", "ROUTE_29", "ROUTE_1", "ROUTE1", "NEW_BARK_TOWN", "PALLET_TOWN" }) do
    if game.data.maps[id] then MAP = id break end
  end
  check(MAP ~= nil, "a map to hunt on: " .. tostring(MAP))
  if not MAP then love.event.quit(1) return end
  U.teleport(game, MAP, 1, 1, "down")
  -- both copies work out the same list: the host starts a quarter of the way
  -- along it, the guest three quarters
  local cells = Treasure.candidates(game.overworld.map, 1, 1, game.data.field)
  check(#cells >= Treasure.MIN_CELLS, MAP .. ": " .. #cells .. " cells to hide in")
  local spot = cells[math.max(1, math.floor(#cells * (role == "host" and 0.25 or 0.75)))]
  U.teleport(game, MAP, spot[1], spot[2], "down")
  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  check(waitFor(60 * 30, function()
    return CoopManager.isConnected() and CoopManager.partner.map == MAP
  end), "linked, both on " .. MAP)
  U.wait(90)

  local function sess() return MG.session end
  local function dist(x, y, s) return math.abs(x - s.data.cx) + math.abs(y - s.data.cy) end
  local function free(x, y)
    local ow = game.overworld
    local p = CoopManager.partner
    return ow.map:isWalkableCell(x, y) and not ow.map:warpAtCell(x, y) and not ow:npcAtCell(x, y)
           and not (p.cx == x and p.cy == y)
  end
  -- a cell `lo..hi` steps from the treasure
  local function cellAt(s, lo, hi)
    for _, c in ipairs(cells) do
      local d = dist(c[1], c[2], s)
      if d >= lo and d <= hi and free(c[1], c[2]) then return c end
    end
  end
  -- the A that digs also talks to whatever is in front: read it away
  local function closeTexts()
    for _ = 1, 30 do
      local ow = game.overworld
      if game.stack:top() == ow and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then return end
      U.tap(game, "b")
      U.wait(8)
    end
  end
  local function goTo(c)
    U.teleport(game, MAP, c[1], c[2], "down")
    U.wait(20)
  end
  -- stand next to the treasure and walk onto it, then press A
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local function walkOnAndDig(s, tag)
    local stepped = false
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local v = D[dir]
      local fx, fy = s.data.cx - v[1], s.data.cy - v[2]
      if not stepped and free(fx, fy) then
        goTo({ fx, fy })
        local p = game.overworld.player
        if Collision.canMove(game.overworld.map, game.overworld.entities or {}, p, dir) then
          for _ = 1, 4 do
            if p.cellX == s.data.cx and p.cellY == s.data.cy then break end
            U.hold(game, dir, 18)
            U.wait(12)
            p = game.overworld.player
          end
          stepped = p.cellX == s.data.cx and p.cellY == s.data.cy
        end
      end
    end
    check(stepped, tag .. ": walked onto the treasure's cell " .. s.data.cx .. "," .. s.data.cy)
    U.wait(20)
    check(s.data.hint == "hot" and s.data.dist == 0, tag .. ": on it the hint says HOT")
    U.shot(game, DIR .. "/" .. tag .. "_on_cell.png")
    U.tap(game, "a")
    U.wait(5)
    local found = s.data.found == true
    U.wait(20)
    closeTexts()
    return found
  end

  local function hunt(round, asker)
    -- the invite
    if asker then
      check(waitFor(60 * 10, function() return CoopManager.overworldIdle(game, game.overworld) end), "idle to ask")
      check(MG.invite(game, "treasure", game.overworld), round .. ": asked for TREASURE HUNT")
    else
      check(waitFor(60 * 20, function() return MG.asked ~= nil end), round .. ": asked to play")
      U.wait(70)
      U.shot(game, DIR .. "/" .. round .. "_invite.png")
      U.tap(game, "a")
    end
    check(waitFor(60 * 15, function() return sess() and sess().phase == "play" end), round .. ": hunting after the countdown")
    local s = sess()
    if not s then return end
    U.log(("%s CELL %s %s,%s of %s"):format(round, tostring(s.data.map), tostring(s.data.cx), tostring(s.data.cy),
                                            tostring(s.data.cells)))
    check(game.overworld.rollEncounter == Treasure.noEncounter, round .. ": no wild Pokemon while hunting")
    if not asker then
      check(waitFor(60 * 5, function() return s.data.matched ~= nil end) and s.data.matched == true,
            round .. ": the asker's cell is ours (" .. tostring(s.data.matched) .. ")")
    end
    U.wait(30)
    U.shot(game, DIR .. "/" .. round .. "_hunting.png")
    return s
  end

  local function result(round, s, want)
    check(waitFor(60 * 15, function() return s.phase == "result" end), round .. ": the result is in")
    U.log(("%s FINAL mine=%s theirs=%s result=%s"):format(round, tostring(s.final), tostring(s.partnerFinal), tostring(s.result)))
    check(s.result == want, round .. ": " .. want .. " (" .. tostring(s.result) .. ")")
    U.wait(30)
    U.shot(game, DIR .. "/" .. round .. "_result.png")
    check(waitFor(60 * 10, function() return MG.session == nil end), round .. ": the result goes away")
    check(game.overworld.rollEncounter ~= Treasure.noEncounter and type(game.overworld.rollEncounter) == "function",
          round .. ": wild Pokemon are back")
  end

  -- ------------------------------------------------------------ round 1
  local s = hunt("r1", role == "host")
  if s then
    if role == "guest" then
      for _, h in ipairs({ { "cold", 9, 99 }, { "warm", 4, 8 }, { "hot", 1, 3 } }) do
        local c = cellAt(s, h[2], h[3])
        if c then
          goTo(c)
          check(s.data.hint == h[1], ("r1: %d steps away: %s (%s)"):format(dist(c[1], c[2], s), h[1], tostring(s.data.hint)))
          U.shot(game, DIR .. "/r1_hint_" .. h[1] .. ".png")
        else
          U.log("r1: no free cell " .. h[2] .. "-" .. h[3] .. " steps away for " .. h[1])
        end
      end
      -- dig where it is not
      U.tap(game, "a")
      U.wait(10)
      local st = tostring(CoopManager.statusMessage)
      closeTexts()
      check(s.phase == "play" and (st:find("nada", 1, true) or st:find("Nothing", 1, true)) ~= nil,
            "r1: A on a wrong cell, the hunt goes on: " .. st)
      CoopManager.sendEmote("exclaim") -- host: your turn
      result("r1", s, "lose")
      check(s.final == Treasure.NOT_FOUND and s.partnerFinal and s.partnerFinal < Treasure.NOT_FOUND,
            "r1: we did not find it, the host did in " .. tostring(s.partnerFinal))
    else
      check(waitFor(60 * 40, function() return CoopManager.partner.emote == "exclaim" end), "r1: the guest is done with the hints")
      check(walkOnAndDig(s, "r1"), "r1: A on the cell: found")
      result("r1", s, "win")
    end
  end
  U.wait(120)

  -- ------------------------------------------------------------ round 2
  s = hunt("r2", role == "guest")
  if s then
    if role == "guest" then
      check(walkOnAndDig(s, "r2"), "r2: A on the cell: found")
      result("r2", s, "win")
    else
      result("r2", s, "lose")
    end
  end

  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
