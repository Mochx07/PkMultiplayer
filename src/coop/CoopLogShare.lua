-- src/coop/CoopLogShare.lua
-- THE PARTNER'S SIDE OF THE STORY, WITHOUT ASKING FOR IT.  Every bug report
-- from a co-op session needed both coop.log files, and the partner's had to
-- be found and sent by hand.  Each game now sends its own log lines to the
-- other while linked, a batch every SEND_EVERY seconds, and writes what it
-- receives to coop-partner.log next to its coop.log (their clock, their
-- order).  The [NET] traffic lines stay home: they are most of the file and
-- the receiver has its own side of them.  Lines written while the link is
-- down wait (up to MAX_PENDING) and go when it is back, so what happened
-- during a drop arrives too.  Switched off in MODS -> PkMultiplayer ->
-- OPTIONS -> SHARE CO-OP LOG (receiving never is: it is the partner's choice).

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopLogShare = {}

CoopLogShare.SEND_EVERY = 3.0
CoopLogShare.MAX_BATCH = 80
CoopLogShare.MAX_PENDING = 400
CoopLogShare.MAX_FILE_BYTES = 1024 * 1024
CoopLogShare.FILE = "coop-partner.log"

CoopLogShare.pending = {}
CoopLogShare.dropped = 0
CoopLogShare.timer = 0

CoopLogShare.enabled = function()
  local opts = package.loaded["pkmultiplayer.options"]
  return not (opts and opts.on) or opts.on("shareLog")
end

-- every line this game writes, but the network traffic
CoopLog.onLine = function(entry, line)
  if entry.level == "NET" or entry.tag == "LOGSHARE" then return end
  local pending = CoopLogShare.pending
  pending[#pending + 1] = (line:gsub("\n$", ""))
  if #pending > CoopLogShare.MAX_PENDING then
    table.remove(pending, 1)
    CoopLogShare.dropped = CoopLogShare.dropped + 1
  end
end

function CoopLogShare.flush(force)
  local net = CoopManager.net
  if not (net and CoopManager.connected) then return false end
  local pending = CoopLogShare.pending
  if #pending == 0 and CoopLogShare.dropped == 0 then return false end
  if not CoopLogShare.enabled() then
    CoopLogShare.pending, CoopLogShare.dropped = {}, 0
    return false
  end
  local batch = {}
  local n = math.min(#pending, CoopLogShare.MAX_BATCH)
  for i = 1, n do batch[i] = pending[i] end
  local msg = { type = "coop_log", lines = batch, dropped = CoopLogShare.dropped }
  if net:send(msg) == false then return false end
  for _ = 1, n do table.remove(pending, 1) end
  CoopLogShare.dropped = 0
  return true
end

local function filePath()
  if CoopLogShare.FILE:sub(1, 1) == "/" then return CoopLogShare.FILE end
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    return love.filesystem.getSaveDirectory() .. "/" .. CoopLogShare.FILE
  end
  return CoopLogShare.FILE
end

-- what the partner sent, appended to coop-partner.log
function CoopLogShare.receive(msg)
  if type(msg) ~= "table" or type(msg.lines) ~= "table" then return end
  local path = filePath()
  local okS, f = pcall(io.open, path, "r")
  if okS and f then
    local size = f:seek("end") or 0
    f:close()
    if size > CoopLogShare.MAX_FILE_BYTES then pcall(os.rename, path, path .. ".old") end
  end
  local ok, out = pcall(io.open, path, "a")
  if not (ok and out) then return end
  local who = tostring((CoopManager.partner and CoopManager.partner.name) or "PARTNER")
  if CoopLogShare.lastWriter ~= who then
    CoopLogShare.lastWriter = who
    out:write(string.format("\n=== %s's coop.log (their clock), received %s ===\n", who,
                            os.date("%Y-%m-%d %H:%M:%S")))
  end
  local dropped = tonumber(msg.dropped) or 0
  if dropped > 0 then
    out:write(string.format("... %d older lines of theirs did not fit while the link was down ...\n", dropped))
  end
  for _, l in ipairs(msg.lines) do
    if type(l) == "string" then out:write(l, "\n") end
  end
  out:close()
end

CoopManager.handlers.coop_log = function(ow, msg) CoopLogShare.receive(msg) end

CoopManager.onTick("logshare", function(dt)
  CoopLogShare.timer = CoopLogShare.timer - dt
  if CoopLogShare.timer > 0 then return end
  CoopLogShare.timer = CoopLogShare.SEND_EVERY
  CoopLogShare.flush()
end)

return CoopLogShare
