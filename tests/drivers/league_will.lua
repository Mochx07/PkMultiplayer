-- WILL WITH THE PARTNER STILL OUTSIDE.  Host in WILL's room under WILL, guest
-- in the INDIGO PLATEAU center.  1.6.15: the host is asked WAIT <partner> /
-- SOLO and waits for the guest to walk in; the guest gets no invite from the
-- center.  Then the guest walks in through the door, and CO-OP starts with
-- both in the room, the guest where it walked (not warped onto the host).
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
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 70)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  save.g2Scenes = save.g2Scenes or {}
  if role == "host" then
    save.g2Scenes.WILLS_ROOM = 1
    U.teleport(game, "WILLS_ROOM", 5, 8, "up")
    check(CM.host(port), "hosting")
  else
    U.teleport(game, "INDIGO_PLATEAU_POKECENTER1_F", 14, 4, "up")
    U.wait(60)
    check(CM.join("127.0.0.1", port), "joined")
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map then linked = true break end
    U.wait(1)
  end
  check(linked, "linked")
  U.wait(90)
  local function labels(s)
    for _, v in pairs(s) do
      if type(v) == "table" and type(v[1]) == "table" and v[1].label then
        local t = {}
        for _, it in ipairs(v) do t[#t + 1] = tostring(it.label) end
        return table.concat(t, "/")
      end
    end
  end
  local function stackDesc()
    local out = {}
    for _, s in ipairs(game.stack.states or {}) do
      local tag = s == game.overworld and "OW" or labels(s) and ("menu[" .. labels(s) .. "]")
      if not tag and getmetatable(s) == CoopStory.WaitHere then tag = "WaitHere" end
      if not tag and s.lines and type(s.lines[1]) == "string" then tag = "box[" .. table.concat(s.lines, "|") .. "]" end
      if not tag then
        for k, v in pairs(s) do
          if type(k) == "string" and k:match("^is") and v == true then tag = k break end
        end
      end
      out[#out + 1] = tag or "?"
    end
    return table.concat(out, ",")
  end
  local function pos()
    local ow = game.overworld
    local p = ow and ow.player
    return string.format("%s (%s,%s)", tostring(ow and ow.map and ow.map.id), tostring(p and p.cellX), tostring(p and p.cellY))
  end
  local seen = {}
  local function watch(secs, tag, stop)
    local t0 = love.timer.getTime()
    local last
    while love.timer.getTime() - t0 < secs do
      local d = stackDesc() .. " @ " .. pos() .. " feed=" .. #(CoopStory.feed or {})
      if d ~= last then U.log(role .. " " .. tag .. ": " .. d) last = d end
      if CM.activeInviteModal then seen.invite = true end
      if #(CoopStory.feed or {}) > 0 then seen.feed = true end
      if d:find("READ ALONG") then seen.readAlong = true end
      if d:find("CO%-OP/SOLO") then seen.coopSolo = true end
      if d:find("WAIT ") then seen.wait = true end
      if stop and stop(d) then return d end
      U.wait(2)
    end
  end
  local function inBattle()
    local top = game.stack:top()
    return top and top.coopDouble
  end
  if role == "host" then
    U.tap(game, "a")
    local d = watch(8, "talk", function(d) return d:find("menu%[") end)
    U.shot(game, DIR .. "/1_host_asked.png")
    check(seen.wait and not seen.coopSolo, "guest outside: WAIT/SOLO, not CO-OP/SOLO")
    U.tap(game, "a") -- first row: WAIT (1.6.15) / CO-OP (1.6.16)
    watch(40, "waiting", function(d)
      if inBattle() then return true end
      local top = game.stack:top()
      if top and top.isCoopBattleSelect then U.tap(game, "start") U.wait(20)
      elseif d:find("isTextBox") or d:find("text") or d:find("menu%[CO%-OP") then U.tap(game, "a") U.wait(10) end
    end)
    U.shot(game, DIR .. "/3_host_end.png")
    check(inBattle(), "a co-op double vs WILL started")
  else
    watch(8, "outside")
    U.shot(game, DIR .. "/1_guest_outside.png")
    check(not seen.invite, "no invite while still in the center")
    check(not seen.readAlong and not seen.feed, "no read-along from the center")
    -- 1.6.16: accept to show what happens (read along, then the warp)
    if seen.invite then
      for _ = 1, 3 do U.tap(game, "a") U.wait(40) end
      U.tap(game, "start") U.wait(30)
      watch(20, "accepted", function() return inBattle() end)
      U.log("guest after the go: " .. pos())
      U.shot(game, DIR .. "/2_guest_after_go.png")
    else
      while game.stack:top() ~= game.overworld do U.tap(game, "b") U.wait(20) end
      U.hold(game, "up", 40)
      watch(25, "walked-in", function() return CM.activeInviteModal end)
      U.log("guest walked in: " .. pos())
      U.shot(game, DIR .. "/2_guest_walked_in.png")
      check(CM.activeInviteModal ~= nil, "invite arrives once in the room")
      for _ = 1, 3 do U.tap(game, "a") U.wait(40) end
      U.tap(game, "start") U.wait(30)
      watch(25, "accepted", function() return inBattle() end)
      check(inBattle(), "co-op double vs WILL on the guest too")
    end
  end
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
