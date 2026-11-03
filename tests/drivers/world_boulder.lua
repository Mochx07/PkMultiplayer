-- STRENGTH BOULDERS ON BOTH SCREENS (1.20, src/coop/CoopWorld.lua), two real
-- Gold copies linked over 127.0.0.1, in MOUNT MORTAR B1F (one boulder, no
-- trainers):
--
--   1. the host (STRENGTH + PLAINBADGE) answers the boulder's own question,
--      uses STRENGTH and pushes it while the guest is still on another map;
--   2. the guest walks onto the map: its boulder is where the host left it;
--   3. the host steps up and pushes it again, the guest watching: it moves
--      on both screens to the same cell;
--   4. the guest, with no STRENGTH of its own and the host a few steps away,
--      answers the boulder's question with the host's STRENGTH and pushes
--      it back: both screens agree again.
--
--   pair.sh <mod> tests/drivers/world_boulder.lua 7830 gold PkReviewUI_A PkReviewUI_B <out>
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
  -- the flat Game Boy view, whatever this identity's display options say
  -- (a 3D world pass turns the camera, and with it which way "down" walks)
  pcall(function()
    local Pipelines = require("src.render.Pipelines")
    for _, e in ipairs(Pipelines.list()) do
      if e.def and e.def.drawWorld then Pipelines.setLevel(e.id, 0) end
    end
    require("src.render.Tilt").setLevel(0)
  end)
  local Pokemon = require("src.pokemon.Pokemon")
  local Badges = require("src.inventory.Badges")
  local CoopManager = require("src.coop.CoopManager")
  local CoopWorld = require("src.coop.CoopWorld")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.repelSteps = 500
  local function mon(n, moves)
    local id = ("SPECIES_%03d"):format(n)
    local m = Pokemon.new(game.data, game.data.pokemon[id] and id or next(game.data.pokemon), 90)
    m.moves = {}
    for _, mv in ipairs(moves) do m.moves[#m.moves + 1] = { id = mv, pp = 15 } end
    return m
  end
  if role == "host" then
    save.party[1] = mon(68, { "STRENGTH", "KARATE_CHOP" }) -- MACHAMP
    Badges.set(save, { id = "PLAINBADGE" }, true)
  else
    save.party[1] = mon(160, { "TACKLE" }) -- no STRENGTH, no badge
  end

  local MAP = "MOUNT_MORTAR_B1_F"
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local BACK = { up = "down", down = "up", left = "right", right = "left" }

  -- where the boulder is and which way it can go twice, from this map's data
  U.teleport(game, MAP, 1, 1, "down")
  local ow = game.overworld
  local function rock() return ow:npcByIndex(3) end
  local b0 = rock()
  check(b0 ~= nil and CoopWorld.isPushable(b0), "MOUNT MORTAR B1F has its STRENGTH boulder")
  if not b0 then love.event.quit(1) return end
  local bx, by = b0.cellX, b0.cellY
  local function walk(x, y) return ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) end
  local dir
  for _, d in ipairs({ "up", "left", "right", "down" }) do
    local v = D[d]
    if walk(bx - v[1], by - v[2]) and walk(bx + v[1], by + v[2]) and walk(bx + 2 * v[1], by + 2 * v[2])
       and walk(bx + 3 * v[1], by + 3 * v[2]) then
      dir = d break
    end
  end
  check(dir ~= nil, "a way to push it twice and back: " .. tostring(dir))
  if not dir then love.event.quit(1) return end
  local v = D[dir]
  local B1 = { bx + v[1], by + v[2] }
  local B2 = { bx + 2 * v[1], by + 2 * v[2] }
  U.log(("%s: boulder at %d,%d, pushed %s to %d,%d then %d,%d"):format(role, bx, by, dir, B1[1], B1[2], B2[1], B2[2]))

  -- answer the boulder's question (AskStrengthScript) until STRENGTH is on
  local function useStrength()
    for _ = 1, 40 do
      if game.stack:top() == ow and ow.strengthActive then return true end
      U.tap(game, "a")
      U.wait(10)
    end
    return ow.strengthActive == true
  end
  local function push(d)
    U.hold(game, d, 6)
    U.wait(40)
  end
  local function at(p) local r = rock() return r and r.cellX == p[1] and r.cellY == p[2] and not r.moving end

  if role == "host" then
    U.teleport(game, MAP, bx - v[1], by - v[2], dir)
    ow = game.overworld
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.teleport(game, "ROUTE29", 10, 8, "down")
    ow = game.overworld
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  check(waitFor(60 * 30, function()
    return CoopManager.isConnected() and CoopManager.partner.map ~= nil and CoopWorld.on()
  end), "linked, both with world.share")
  U.wait(60)

  if role == "host" then
    -- 1. pushed with the guest elsewhere
    local armed = useStrength()
    U.shot(game, DIR .. "/1_strength.png")
    check(armed, "the boulder's question answered: STRENGTH is on")
    push(dir)
    check(at(B1), ("the boulder moved to %d,%d"):format(B1[1], B1[2]))
    U.shot(game, DIR .. "/2_pushed_alone.png")
    -- 2. the guest walks in; 3. once it is here, push again
    check(waitFor(60 * 30, function() return CoopManager.partner.map == MAP end), "the guest walked onto the map")
    U.wait(120)
    U.hold(game, dir, 1) -- face it (we are already)
    U.wait(5)
    -- step onto the boulder's old cell, then push
    U.hold(game, dir, 10)
    U.wait(30)
    if ow.player.cellX ~= bx or ow.player.cellY ~= by then
      U.log(("host: stood at %d,%d after the step"):format(ow.player.cellX, ow.player.cellY))
    end
    push(dir)
    check(at(B2), ("pushed again, now at %d,%d"):format(B2[1], B2[2]))
    U.wait(30)
    U.shot(game, DIR .. "/3_pushed_watched.png")
    -- 4. the guest pushes it back with our STRENGTH
    check(waitFor(60 * 40, function() return at(B1) end),
          ("the guest pushed it back: here too it is at %d,%d"):format(B1[1], B1[2]))
    U.wait(30)
    U.shot(game, DIR .. "/4_guest_pushed.png")
  else
    -- wait for the host's first push to have happened, then walk in
    check(waitFor(60 * 40, function() return CoopWorld.partnerHms and CoopWorld.partnerHms.STRENGTH end),
          "the host says it can lend STRENGTH")
    U.wait(60 * 6)
    -- walk in: two cells to the side of the boulder's line, within sight
    local side = { v[2], v[1] }
    local gx, gy
    for k = 1, 4 do
      for _, s in ipairs({ 1, -1 }) do
        local x, y = B2[1] + side[1] * k * s, B2[2] + side[2] * k * s
        if not gx and walk(x, y) then gx, gy = x, y end
      end
    end
    gx, gy = gx or B2[1] + 2 * v[1], gy or B2[2] + 2 * v[2]
    U.teleport(game, MAP, gx, gy, "down")
    ow = game.overworld
    check(waitFor(60 * 5, function() return at(B1) end),
          ("walking in: the boulder is at %d,%d, where the host left it"):format(B1[1], B1[2]))
    U.shot(game, DIR .. "/2_walked_in.png")
    check(waitFor(60 * 30, function() return at(B2) end),
          ("the host pushed it: here it moved to %d,%d too"):format(B2[1], B2[2]))
    U.wait(40)
    U.shot(game, DIR .. "/3_saw_push.png")
    -- 4. push it back from beyond it, with the host's STRENGTH
    check(ow:partyKnows("STRENGTH") ~= nil, "no STRENGTH here, but the host's is lent (within 8 steps)")
    local Bx = { B2[1] + v[1], B2[2] + v[2] }
    U.teleport(game, MAP, Bx[1], Bx[2], BACK[dir])
    ow = game.overworld
    U.wait(60) -- the map was reloaded: the host's boulders come back
    check(at(B2), "after the reload the boulder is still where the host put it")
    check(CoopWorld.near(ow), "the host is within 8 steps (" .. tostring(CoopWorld.partnerSteps(ow)) .. ")")
    local armed = useStrength()
    U.shot(game, DIR .. "/4_borrowed_strength.png")
    check(armed, "the boulder's question answered with the host's STRENGTH")
    push(BACK[dir])
    check(at(B1), ("pushed back to %d,%d"):format(B1[1], B1[2]))
    U.wait(30)
    U.shot(game, DIR .. "/5_pushed_back.png")
  end
  local r = rock()
  U.log(("%s: BOULDER %s,%s"):format(role, tostring(r and r.cellX), tostring(r and r.cellY)))
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
