-- RECONNECTING ON THE MAP, between two real game instances.
--
--   (rig) the guest dials through a UDP relay that can black the link out:
--   PKM_ROLE=host|guest PKM_PORT=<host port | relay port> PKM_NETCTL=<relay
--   control file> SHOT_DIR=... POKEPORT_VERSION=gold love .
--
-- The guest links from a throwaway save and then plays another one, the way
-- the title's CONTINUE CO-OP GAME does (the boot save says hello, the loaded
-- save plays).  The host then cuts the link:
--   A1  7 s   -- shorter than enet's timeout: a stall, no drop
--   A2 25 s   -- a drop: both RECONNECTING, the session resumes
--   A3 25 s   -- the same again: the SECOND reconnect must resume too
--   A4 14 s   -- host->guest only: the guest gives up on the old link while
--               the host still hears it, and dials again
-- and checks after each one that the two are linked again on the same session.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local CTRL = os.getenv("PKM_NETCTL") or "/tmp/pkm-netctl"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function clock() return love.timer.getTime() end
  local function secs(n) local t0 = clock(); while clock() - t0 < n do U.wait(1) end end
  local function waitFor(n, fn)
    local t0 = clock()
    while clock() - t0 < n do
      if fn() then return true, clock() - t0 end
      U.wait(1)
    end
    return false, n
  end
  local function setNet(mode)
    local f = io.open(CTRL, "w"); f:write(mode); f:close()
    U.log(role .. ": net -> '" .. mode .. "'")
  end
  local function netMode()
    local f = io.open(CTRL, "r")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s
  end

  local STATE = rawget(_G, "__PKMULTIPLAYER")
  check(STATE ~= nil, "the mod booted")
  if not STATE then love.event.quit(1) return end
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopNet = require("src.coop.CoopNet")

  local function linked() return CoopManager.isConnected() and CoopManager.net.state == CoopNet.STATE.SYNCED end
  local function stats() local n = CoopManager.net; return n and n.stats or {} end
  local lastState
  CoopManager.onTick("netdrv", function()
    local n = CoopManager.net
    local s = n and n.state
    if s ~= lastState then
      U.log(("%s: [%.1f] state %s -> %s (err=%s)"):format(role, clock(), tostring(lastState), tostring(s), tostring(n and n.error)))
      lastState = s
    end
  end)

  local function playSave(name, team)
    local save = U.freshSave(game)
    save.player.name = name
    for _, sp in ipairs(team) do
      table.insert(save.party, Pokemon.new(game.data, ("SPECIES_%03d"):format(sp), 14))
    end
    U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
    return save
  end

  if role == "host" then
    playSave("MOCHI", { 155, 16 })
    check(CoopManager.host(port), "hosting on " .. port)
  else
    -- the boot save (the title screen's) says hello...
    U.freshSave(game)
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling the relay on " .. port)
  end
  check(waitFor(60, linked), "linked")
  if role == "guest" then
    local bootId = CoopManager.net.identity
    -- ...and CONTINUE loads the real save (Game:loadGame replaces game.save)
    playSave("TOBY", { 158, 161 })
    U.log("guest: boot save id " .. tostring(bootId) .. ", playing save id " .. tostring(CoopManager.coopId()))
  end
  secs(8)

  if role == "host" then
    local function cut(tag, mode, seconds, shotAt)
      local before = stats().reconnects or 0
      setNet(mode)
      local t0 = clock()
      while clock() - t0 < seconds do
        if shotAt and clock() - t0 >= shotAt then
          U.shot(game, DIR .. "/" .. tag .. "_during.png"); shotAt = nil
        end
        U.wait(1)
      end
      setNet("")
      local ok, took = waitFor(45, linked)
      check(ok, ("%s: linked again %.1fs after the link came back (state %s)"):format(tag, took, CoopManager.net.state))
      return (stats().reconnects or 0) - before
    end
    local want = os.getenv("PKM_CUTS") or "A1,A2,A3,A4"
    local function on(tag) return want:find(tag, 1, true) ~= nil end
    if on("A1") then
      local r1 = cut("A1", "both", 7)
      check(r1 == 0, "A1: a 7 s blackout is ridden out without a reconnect (" .. r1 .. ")")
    end
    if on("A2") then
      local r2 = cut("A2", "both", 25, 18)
      check(r2 >= 1, "A2: the first drop reconnects")
      U.shot(game, DIR .. "/A2_after.png")
      secs(5)
    end
    if on("A3") then
      local r3 = cut("A3", "both", 25, 18)
      check(r3 >= 1, "A3: the second drop reconnects too")
      secs(5)
    end
    if on("A4") then
      local r4 = cut("A4", "h2g", 14)
      check(r4 >= 1, "A4: a one-way drop reconnects")
      secs(3)
    end
    secs(tonumber(os.getenv("PKM_TAIL") or "0"))
    setNet("done")
  else
    local seen, t0 = "", nil
    local A = 0
    while true do
      local m = netMode()
      if m == "done" then break end
      if m ~= seen then
        seen = m
        if m == "both" then A = A + 1; t0 = clock() end
      end
      if t0 and m == "both" and clock() - t0 >= 18 then
        U.shot(game, DIR .. ("/cut%d_during.png"):format(A)); t0 = nil
      end
      U.wait(1)
    end
    check(linked(), "still linked at the end")
  end
  U.log(("%s: reconnects=%s resent=%s dupes=%s"):format(role, tostring(stats().reconnects), tostring(stats().resent), tostring(stats().dupes)))
  U.wait(30)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
