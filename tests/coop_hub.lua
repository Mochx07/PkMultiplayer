-- CO-OP THROUGH THE GAME'S LINK LADDER (src/coop/CoopHub.lua).
--
-- The hand-over: the ladder's socket goes to CoopNet; the guest drops every
-- connection the ladder raced (and redials), the host keeps listening; the
-- job lets go of the socket so closing it later does not close CoopNet's.
--
--   luajit <mod>/tests/run.lua <mod>/tests/coop_hub.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local fails, total = 0, 0
local function check(ok, msg)
  total = total + 1
  print((ok and "ok   " or "FAIL ") .. msg)
  if not ok then fails = fails + 1 end
end
require("src.coop.CoopLog").enabled = false
local CoopHub = require("src.coop.CoopHub")

local function fakeJob()
  local dropped = {}
  local function handle(name)
    return { disconnect_now = function() dropped[#dropped + 1] = name end }
  end
  local host = { flush = function() end }
  local t = { driver = { host = host }, peers = {
    [1] = { handle = handle("lan"), address = "192.168.1.8:40000" },
    [2] = { handle = handle("public"), address = "45.0.0.1:40000" },
  } }
  local ch = { transport = t, peerId = 1, owns = true, target = "x" }
  return { channel = ch }, host, t, dropped
end

local job, host, t, dropped = fakeJob()
local h, address = CoopHub.takeOver(job, true)
check(h == host, "the guest gets the ladder's socket")
check(address == "192.168.1.8:40000", "and the endpoint that worked")
check(#dropped == 2, "the guest drops every connection the ladder raced")
check(t.driver.host == nil and job.channel == nil, "the job lets go of the socket")

job, host, t, dropped = fakeJob()
h = CoopHub.takeOver(job, false)
check(h == host and #dropped == 0, "the host keeps its peers and listens")

check(CoopHub.takeOver({}, true) == nil, "nothing to take from an unfinished job")

-- the game's codes and the mod's are told apart
package.loaded["src.online.InviteCode"] = { decode = function(code)
  if code == "3ZVS-N3PZ-CHQ9-3HEG-Y" then return { kind = "hub" } end
  return nil, "bad code"
end }
package.loaded["src.online.net.Connector"] = {}
check(CoopHub.isGameCode("3ZVS-N3PZ-CHQ9-3HEG-Y") == true, "a game invite code goes through the hub")
check(CoopHub.isGameCode("30AG-0B4") == false, "the mod's own code does not")
check(CoopHub.isGameCode(nil) == false, "no code: no")

CoopHub.cancel()
check(CoopHub.state == nil and CoopHub.job == nil, "cancel leaves nothing behind")

print(("%d/%d checks passed  (co-op through the link hub)"):format(total - fails, total))
if fails > 0 then os.exit(1) end
