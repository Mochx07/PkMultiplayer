-- A HELD SCENE WHOSE SCRIPT DIES.  The host talks to WILL with the guest
-- still in the INDIGO PLATEAU center and answers WAIT: the guest's game is
-- told to hold its own copy of WILL's scene.  The host then gives up (B,
-- SOLO), and WILL's script dies before its end -- put down the way the
-- engine puts a stranded script down (OverworldState:watchStuckScript sets
-- runner.co = nil), which is also what an error outside a command leaves.
-- The host walks back out to the center.
--
-- Before the fix CoopStory.finish never ran, the hold was never lifted, and
-- the guest who then walked up to WILL got nothing at all: their copy of the
-- scene was skipped for HOLD_MAX (15 minutes).  Now the hold goes with the
-- script, and WILL talks to the guest.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7815")
  local ROOT = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local DIR = ROOT .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function mark(name)
    os.execute("mkdir -p '" .. ROOT .. "'")
    local f = io.open(ROOT .. "/sync_" .. name, "w")
    if f then f:write("1") f:close() end
  end
  local function waitMark(name, secs)
    for _ = 1, secs * 60 do
      local f = io.open(ROOT .. "/sync_" .. name, "r")
      if f then f:close() return true end
      U.wait(1)
    end
    return false
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
  save.g2Scenes.WILLS_ROOM = 1
  if role == "host" then
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
  local function top() return game.stack:top() end
  local function menuLabels(s)
    if type(s) ~= "table" then return nil end
    for _, v in pairs(s) do
      if type(v) == "table" and type(v[1]) == "table" and v[1].label then
        local t = {}
        for _, it in ipairs(v) do t[#t + 1] = tostring(it.label) end
        return table.concat(t, "/")
      end
    end
  end
  local function running()
    local ow = game.overworld
    return ow and ow.runner and ow.runner:isRunning()
  end

  if role == "host" then
    U.tap(game, "a")
    local asked
    for _ = 1, 8 * 30 do
      asked = menuLabels(top())
      if asked then break end
      U.wait(2)
    end
    check(asked and asked:find("^WAIT "), "guest outside: WAIT / SOLO (" .. tostring(asked) .. ")")
    U.tap(game, "a")   -- WAIT
    U.wait(30)
    check(getmetatable(top()) == CoopStory.WaitHere, "waiting for the guest")
    check(waitMark("guest_held", 20), "the guest's game is holding WILL's scene")
    U.shot(game, DIR .. "/1_host_waiting.png")
    -- the scene dies before its end.  An error inside a command does not
    -- do it (ScriptRunner skips the row and carries on); what does is the
    -- engine putting a parked script down (OverworldState:watchStuckScript:
    -- runner.co = nil) or an error outside a command -- done here the
    -- engine's own way, with WILL's first line on screen
    U.tap(game, "b")   -- B: BATTLE SOLO
    local TextBoxMT = require("src.render.TextBox")
    local inText = false
    for _ = 1, 20 * 30 do
      if getmetatable(top()) == TextBoxMT then inText = true break end
      U.wait(2)
    end
    check(inText, "SOLO: WILL starts talking")
    U.wait(30)
    U.shot(game, DIR .. "/2_host_will_talks.png")
    local r = game.overworld.runner
    r.co, r.waitingFrames, r.waitingCheck = nil, nil, nil
    while top() ~= game.overworld do game.stack:pop() end
    U.wait(30)
    check(not running(), "WILL's script died before its end")
    U.wait(60)
    U.teleport(game, "INDIGO_PLATEAU_POKECENTER1_F", 14, 4, "up")
    U.wait(60)
    mark("host_away")
    check(waitMark("guest_done", 60), "the guest finished")
  else
    local held = false
    for _ = 1, 30 * 30 do
      if CoopStory.held then held = true break end
      U.wait(2)
    end
    check(held, "told to hold WILL's scene")
    mark("guest_held")
    check(waitMark("host_away", 60), "the host's scene died and they walked out")
    U.wait(90)
    while top() ~= game.overworld do U.tap(game, "b") U.wait(20) end
    -- walk in through the door, as a player would, and up to WILL
    U.hold(game, "up", 40)
    for _ = 1, 20 do
      local o = game.overworld
      if o and o.map and o.map.id == "WILLS_ROOM" and o.player and o.player.cellY <= 8 then break end
      U.hold(game, "up", 16)
      U.wait(4)
    end
    U.wait(60)
    local ow = game.overworld
    local p = ow and ow.player
    local front = {}
    for _, n in ipairs((ow and (ow.npcs or (ow.map and ow.map.npcs))) or {}) do
      front[#front + 1] = tostring(n.id) .. "@" .. tostring(n.cellX or n.x) .. "," .. tostring(n.cellY or n.y)
        .. (n.hidden and "(h)" or "")
    end
    U.log("guest in WILL's room at " .. tostring(p and p.cellX) .. "," .. tostring(p and p.cellY) ..
          " facing " .. tostring(p and p.facing) .. " running=" .. tostring(running()) ..
          " npcs " .. table.concat(front, " ") .. " engaging=" .. tostring(CM.isPartnerEngaging and CM.isPartnerEngaging()))
    U.tap(game, "a")
    local seen
    for _ = 1, 10 * 30 do
      local t = top()
      if t ~= game.overworld then
        seen = menuLabels(t) or (getmetatable(t) == require("src.render.TextBox") and "text") or "screen"
        break
      end
      U.wait(2)
    end
    U.shot(game, DIR .. "/2_guest_talks_to_will.png")
    check(seen ~= nil, "WILL's scene plays for the guest (" .. tostring(seen) .. ")")
    check(not CoopStory.heldHere(game.overworld, "OPP_ELITE_FOUR_WILL") and not CoopStory.held,
          "the guest's game no longer holds it")
    if seen then
      -- answer SOLO if asked, and leave it there
      U.wait(30)
      U.shot(game, DIR .. "/3_guest_scene.png")
    end
    mark("guest_done")
  end
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
