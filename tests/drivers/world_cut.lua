-- THE PARTNER'S CUT (1.20, src/coop/CoopWorld.lua), two real Gold copies
-- linked over 127.0.0.1.  The guest has no CUT and no badge; the host has a
-- CUT Pokemon and the HIVEBADGE.
--
--   1. host far away on the same map (more than 8 steps): the guest presses
--      A at a CUT tree and only reads "This tree can be CUT!";
--   2. host walks up (within 8 steps): the same A asks "Want to use CUT?",
--      YES uses the host's Pokemon, and the tree is gone; the host is told.
--
--   pair.sh <mod> tests/drivers/world_cut.lua 7832 gold PkReviewUI_A PkReviewUI_B <out>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7832")
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
  local Badges = require("src.inventory.Badges")
  local CoopManager = require("src.coop.CoopManager")
  local CoopWorld = require("src.coop.CoopWorld")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.repelSteps = 500
  local function mon(n, moves, nick)
    local id = ("SPECIES_%03d"):format(n)
    local m = Pokemon.new(game.data, game.data.pokemon[id] and id or next(game.data.pokemon), 90)
    m.moves = {}
    for _, mv in ipairs(moves) do m.moves[#m.moves + 1] = { id = mv, pp = 15 } end
    m.nickname = nick
    return m
  end
  if role == "host" then
    save.party[1] = mon(123, { "CUT", "QUICK_ATTACK" }, "SNIPS") -- SCYTHER
    Badges.set(save, { id = "HIVEBADGE" }, true)
  else
    save.party[1] = mon(160, { "TACKLE" }) -- no CUT, no badge
  end

  -- a CUT tree, the cell to stand on facing it, a cell 3 steps from there
  -- and one more than 8 steps away -- found in the map's own data
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local MAP, tree, stand, face, near, far
  for _, mapId in ipairs({ "AZALEA_TOWN", "ILEX_FOREST", "ROUTE32", "ROUTE36", "ROUTE_32" }) do
    if game.data.maps[mapId] then
      U.teleport(game, mapId, 1, 1, "down")
      local ow = game.overworld
      local function walk(x, y) return ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) end
      local W, H = ow.map.def.width * 2, ow.map.def.height * 2
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if not tree and ow:gen2CutSwap(x, y) then
            for _, d in ipairs({ "up", "down", "left", "right" }) do
              local v = D[d]
              local sx, sy = x - v[1], y - v[2]
              if not tree and walk(sx, sy) and not ow:npcAtCell(sx, sy) then
                tree, stand, face = { x, y }, { sx, sy }, d
              end
            end
          end
        end
      end
      if tree then
        MAP = mapId
        local best
        for y = 0, H - 1 do
          for x = 0, W - 1 do
            local dist = math.abs(x - stand[1]) + math.abs(y - stand[2])
            if walk(x, y) and not ow:npcAtCell(x, y) and not (x == tree[1] and y == tree[2]) then
              if not near and dist >= 2 and dist <= 4 then near = { x, y } end
              if dist >= 12 and (not best or dist < best) then best, far = dist, { x, y } end
            end
          end
        end
        break
      end
    end
  end
  check(MAP ~= nil and near ~= nil and far ~= nil, ("a CUT tree on %s at %s, stand %s facing %s"):format(
    tostring(MAP), tree and (tree[1] .. "," .. tree[2]) or "?", stand and (stand[1] .. "," .. stand[2]) or "?",
    tostring(face)))
  if not (MAP and near and far) then love.event.quit(1) return end
  U.log(("%s: near %d,%d far %d,%d"):format(role, near[1], near[2], far[1], far[2]))

  local ow
  if role == "host" then
    U.teleport(game, MAP, far[1], far[2], "down")
    ow = game.overworld
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.teleport(game, MAP, stand[1], stand[2], face)
    ow = game.overworld
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  check(waitFor(60 * 30, function()
    return CoopManager.isConnected() and CoopManager.partner.map == MAP and CoopWorld.on()
  end), "linked, both on " .. MAP .. " with world.share")
  U.wait(90)

  local ChoiceBox = require("src.ui.ChoiceBox")
  local function treeStands() return game.overworld:gen2CutSwap(tree[1], tree[2]) ~= nil end
  -- A at the tree, then through its texts: was there a YES / NO?  `answer`
  -- is the button pressed on it ("a" = YES, "b" = NO)
  local function talkToTree(answer, shotAt)
    game.overworld.player.facing = face
    U.tap(game, "a") U.wait(30)
    if shotAt then U.shot(game, shotAt) end
    local asked = false
    for _ = 1, 40 do
      local top = game.stack:top()
      if top == game.overworld and not (game.overworld.runner and game.overworld.runner.isRunning
                                        and game.overworld.runner:isRunning()) then break end
      if getmetatable(top) == ChoiceBox then
        asked = true
        U.shot(game, DIR .. "/question.png")
        U.tap(game, answer)
      else
        U.tap(game, "a")
      end
      U.wait(12)
    end
    return asked
  end

  if role == "guest" then
    -- 1. the host is far
    check(waitFor(60 * 10, function() return CoopWorld.partnerHms and CoopWorld.partnerHms.CUT ~= nil end),
          "the host says it can lend CUT")
    local steps = CoopWorld.partnerSteps(ow)
    check(steps ~= nil and steps > CoopWorld.RANGE, "the host is " .. tostring(steps) .. " steps away")
    check(ow:partyKnows("CUT") == nil, "far away: no CUT for us")
    local asked = talkToTree("b", DIR .. "/1_far_can_cut.png")
    check(not asked, "pressing A at the tree: \"can be CUT\", no question")
    check(treeStands(), "the tree is still there")
    CoopManager.sendEmote("exclaim") -- host: come here
    -- 2. the host comes within 8 steps
    check(waitFor(60 * 20, function()
      local st = CoopWorld.partnerSteps(ow)
      return st ~= nil and st <= CoopWorld.RANGE
    end), "the host walked up: " .. tostring(CoopWorld.partnerSteps(ow)) .. " steps")
    U.wait(30)
    asked = talkToTree("a", DIR .. "/2_near_want_cut.png")
    check(asked, "the same A now asks \"Want to use CUT?\"")
    -- the cut plays its animation first: give it up to 5 s, not a fixed 40 frames
    local cut = waitFor(60 * 5, function() return not treeStands() end)
    U.shot(game, DIR .. "/3_after_cut.png")
    check(cut, "YES: the tree is cut with the host's CUT")
  else
    -- wait for the guest's signal, then walk up close
    check(waitFor(60 * 40, function() return CoopManager.partner.emote == "exclaim" end),
          "the guest tried alone and calls us over")
    U.teleport(game, MAP, near[1], near[2], "down")
    ow = game.overworld
    local told = false
    for _ = 1, 60 * 20 do
      local st = CoopManager.statusMessage
      if st and st:find("CUT", 1, true) and st:find("TOBY", 1, true) then told = true break end
      U.wait(1)
    end
    check(told, "the host is told: " .. tostring(CoopManager.statusMessage))
    U.shot(game, DIR .. "/1_lent.png")
    U.wait(60 * 4)
    U.shot(game, DIR .. "/2_after.png")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
