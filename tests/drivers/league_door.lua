-- ELITE FOUR DOOR TOGETHER: both in the INDIGO PLATEAU POKECENTER under the
-- door to WILL's room.  The host walks in first; the guest must not get a
-- CO-OP/SOLO invite nor a read-along of the host's walk-in, and when the
-- guest follows it must not end up standing in/through the closed door.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7791")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CM = require("src.coop.CoopManager")
  local CoopStory = require("src.coop.CoopStory")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  for _, n in ipairs(role == "host" and { 157, 18, 65 } or { 160, 181, 130 }) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 50)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  U.teleport(game, "INDIGO_PLATEAU_POKECENTER1_F", 14, 4, "up")
  if role == "host" then check(CM.host(port), "hosting")
  else U.wait(60) check(CM.join("127.0.0.1", port), "joined") end
  local linked = false
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "INDIGO_PLATEAU_POKECENTER1_F" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked in the plateau center")
  U.wait(90)
  local function stackDesc()
    local out = {}
    for i, s in ipairs(game.stack.states or {}) do
      local tag = s == game.overworld and "OW" or nil
      if not tag then
        for k, v in pairs(s) do
          if type(k) == "string" and k:match("^is") and v == true then tag = k break end
        end
      end
      if not tag and s.items and s.header then tag = "menu:" .. tostring(s.header) end
      if not tag and getmetatable(s) == CoopStory.WaitHere then tag = "WaitHere" end
      out[#out + 1] = tag or (s.text and ("text:" .. tostring(s.text):sub(1, 20)) or "?")
    end
    return table.concat(out, ",")
  end
  local function pos()
    local ow = game.overworld
    local p = ow and ow.player
    return string.format("%s (%s,%s)", tostring(ow and ow.map and ow.map.id), tostring(p and p.cellX), tostring(p and p.cellY))
  end
  local seenInvite, seenFeed, seenMenu = false, false, false
  local function watch(secs, tag)
    local t0 = love.timer.getTime()
    local last
    while love.timer.getTime() - t0 < secs do
      local d = stackDesc() .. " @ " .. pos() .. " feed=" .. #(CoopStory.feed or {})
      if d ~= last then U.log(role .. " " .. tag .. ": " .. d) last = d end
      if CM.activeInviteModal then seenInvite = true end
      if #(CoopStory.feed or {}) > 0 then seenFeed = true end
      if d:find("menu:") then seenMenu = true end
      U.wait(2)
    end
  end
  if role == "host" then
    U.hold(game, "up", 24)
    watch(4, "walk-in")
    U.shot(game, DIR .. "/1_in_room.png")
    -- whatever the room asks, the first answer
    for _ = 1, 10 do
      local top = game.stack:top()
      if top == game.overworld then break end
      U.tap(game, "a") U.wait(20)
    end
    watch(10, "after")
    U.shot(game, DIR .. "/3_host_end.png")
    check(seenMenu == false, "no CO-OP/SOLO / WAIT menu walking in")
  else
    watch(4, "host-walks")
    U.shot(game, DIR .. "/1_guest_while_host_enters.png")
    watch(3, "host-walks2")
    check(not seenInvite, "no CO-OP invite on the guest for a walk-in")
    check(not seenFeed, "no read-along of the host's walk-in")
    while game.stack:top() ~= game.overworld do U.tap(game, "b") U.wait(20) end
    -- (14,5) is not floor: stand where the host stood
    U.shot(game, DIR .. "/1b_before_left.png")
    for _ = 1, 60 do
      if game.overworld.player.cellX == 14 then break end
      U.hold(game, "left", 1)
    end
    U.wait(20)
    U.shot(game, DIR .. "/1c_after_left.png")
    U.log("guest before door: " .. pos())
    local before = save.g2Scenes and save.g2Scenes.WILLS_ROOM
    U.log("guest: WILL's room scene before walking in: " .. tostring(before))
    for _ = 1, 120 do
      if game.overworld.map.id == "WILLS_ROOM" then break end
      U.hold(game, "up", 1)
    end
    U.wait(20)
    U.shot(game, DIR .. "/2a_guest_arrives.png")
    watch(4, "guest-enters")
    U.shot(game, DIR .. "/2_guest_in_room.png")
    local p = game.overworld.player
    U.log("guest in room at " .. pos() .. " scene=" .. tostring(save.g2Scenes and save.g2Scenes.WILLS_ROOM))
    check(before == nil or before == 0, "the host's walk-in did not advance the guest's door scene")
    check(game.overworld.map.id == "WILLS_ROOM" and p.cellY and p.cellY <= 14,
          "the guest's own walk-in ran (off the door, no input)")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
