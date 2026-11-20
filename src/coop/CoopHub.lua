-- src/coop/CoopHub.lua
-- CO-OP THROUGH THE GAME'S LINK HUB (nightly.3, B6).
--
-- Until now two players reached each other only by an address: the same
-- network, a VPN (ZeroTier, Tailscale, Radmin, Hamachi) or a forwarded port.
-- Gen2Recomped has its own way to reach a friend for its LINK screen
-- (src/online/net/Connector.lua, "the reachability ladder"): the LAN, the
-- router opening the port by itself (UPnP / NAT-PMP / PCP), a forwarded
-- port, a hole punch, and a Link Hub -- the project's official server or the
-- player's own -- that introduces the two and lets them punch through.  Its
-- code is the game's own invite code (src/online/InviteCode.lua), the one
-- the LINK screen shows.
--
-- This uses that ladder for co-op: HOST ONLINE shows the game's code, JOIN
-- takes it, and once the ladder has a connection CoopNet ADOPTS it (its ENet
-- host and the partner's peer) -- from there it is the ordinary co-op link,
-- with its session, resends and reconnects.  Nothing new goes over the wire
-- between the two games: the hub only introduces them.
--
--   CoopHub.host(game)          start hosting through the ladder
--   CoopHub.join(game, code)    join a host's code (true) or say why not
--   CoopHub.update(dt)          once a frame (CoopManager.update calls it)
--   CoopHub.cancel()            give up (and give the router its port back)
--   CoopHub.state               nil | "hosting" | "joining" | "linked" | "failed"
--   CoopHub.code                the code to read out, once there is one
--   CoopHub.status, CoopHub.error   short lines for the screens
local CoopHub = {}

CoopHub.HUB_WAIT = 6     -- seconds HOST waits for the hub's ticket before showing a direct code

local function log(level, msg)
  pcall(function() require("src.coop.CoopLog")[level]("HUB", msg) end)
end

local function manager()
  return package.loaded["src.coop.CoopManager"] or require("src.coop.CoopManager")
end

function CoopHub.settings(game)
  local okL, LinkState = pcall(require, "src.link.LinkState")
  if not (okL and LinkState.settings) then return nil end
  local ok, s = pcall(LinkState.settings, game)
  return ok and s or nil
end

-- is the engine's ladder there at all (an older Gen2Recomped has none)?
function CoopHub.available()
  local ok1 = pcall(require, "src.online.net.Connector")
  local ok2 = pcall(require, "src.online.InviteCode")
  return ok1 and ok2
end

local function closeJob(job)
  if not job then return end
  if job.close then pcall(job.close, job) elseif job.cancel then pcall(job.cancel, job) end
end

function CoopHub.cancel()
  closeJob(CoopHub.job)
  CoopHub.job, CoopHub.state, CoopHub.code, CoopHub.status = nil, nil, nil, nil
  CoopHub.waited, CoopHub.peerReady, CoopHub.readyWait, CoopHub.sentReadyAt = 0, nil, nil, nil
end

-- the ENet host (the socket) and the endpoint that worked, out of a
-- finished ladder job.  Every connection the ladder made is dropped (it
-- raced several, and the two sides may have kept different ones); the job
-- lets go of the socket, which CoopNet now owns.
function CoopHub.takeOver(job, dropPeers)
  local ch = job and job.channel
  local t = ch and ch.transport
  local rec = t and t.peers and t.peers[ch.peerId]
  local driver = t and t.driver
  local h = driver and driver.host
  if not (h and rec) then return nil end
  local address = rec.address or ch.target
  if dropPeers then
    for _, r in pairs(t.peers or {}) do
      if r.handle then pcall(function() r.handle:disconnect_now() end) end
    end
  end
  pcall(h.flush, h)
  driver.host = nil         -- the transport no longer services or destroys it
  ch.owns = false
  job.channel = nil
  return h, address
end

function CoopHub.host(game)
  if not CoopHub.available() then CoopHub.error = "NO LINK HUB IN THIS GAME" return false end
  CoopHub.cancel()
  local LinkState = require("src.link.LinkState")
  local Connector = require("src.online.net.Connector")
  local s = CoopHub.settings(game) or {}
  local opts = LinkState.hostOptions(s)
  opts.maxPeers = 1
  opts.lanBeacon = false
  local CoopNet = require("src.coop.CoopNet")
  opts.port = CoopNet.DEFAULT_PORT
  local ok, job = pcall(Connector.host, opts)
  if not ok or not job then
    CoopHub.error = "CAN'T HOST: " .. tostring(job)
    log("error", CoopHub.error)
    return false
  end
  CoopHub.job, CoopHub.state, CoopHub.game, CoopHub.settingsUsed = job, "hosting", game, s
  CoopHub.isHost, CoopHub.waited, CoopHub.error = true, 0, nil
  CoopHub.status = "GETTING A CODE"
  log("info", "hosting through the ladder (hub " .. tostring(s.hubAddress) .. ")")
  return true
end

-- the code for the shown screen, the LINK screen's way: a HUB code when the
-- hub gave a ticket (it carries the hub and the ticket, never our address),
-- the direct code otherwise
local function buildCode(job, s)
  local LinkState = require("src.link.LinkState")
  local InviteCode = require("src.online.InviteCode")
  local display
  local hubIp, hubPort, hubLan, hubPublicPort = LinkState.hubEndpoint(s.hubAddress)
  if job.info and job.info.hubTicket and hubIp then
    display = InviteCode.encode({ kind = "hub", lan = hubLan,
                                  hub = { ip = hubIp, port = hubPort, publicPort = hubPublicPort },
                                  ticket = job.info.hubTicket })
    if display then return display, "hub" end
  end
  local fields = job:inviteFields()
  fields.room = nil
  display = InviteCode.encode(fields)
  return display, "direct"
end

function CoopHub.join(game, code)
  if not CoopHub.available() then return false, "NO LINK HUB IN THIS GAME" end
  local InviteCode = require("src.online.InviteCode")
  local Util = require("src.online.net.Util")
  local okD, invite, why = pcall(InviteCode.decode, code, Util.lanIP and Util.lanIP() or nil)
  if not okD or not invite then return false, tostring(why or invite or "BAD CODE") end
  CoopHub.cancel()
  local LinkState = require("src.link.LinkState")
  local Connector = require("src.online.net.Connector")
  local s = CoopHub.settings(game) or {}
  local opts = LinkState.joinOptions(s, invite)
  opts.maxPeers = 1
  local ok, job = pcall(Connector.join, invite, opts)
  if not ok or not job then return false, tostring(job) end
  CoopHub.job, CoopHub.state, CoopHub.game = job, "joining", game
  CoopHub.isHost, CoopHub.error = false, nil
  CoopHub.status = "REACHING THE HOST"
  log("info", "joining a link code through the ladder")
  return true
end

-- is `code` the game's own invite code (and not one of the mod's)?
function CoopHub.isGameCode(code)
  if type(code) ~= "string" or not CoopHub.available() then return false end
  local InviteCode = require("src.online.InviteCode")
  local ok, invite = pcall(InviteCode.decode, code)
  return ok and type(invite) == "table"
end

local function adopt(job)
  -- the guest drops the ladder's connections and dials anew from the same
  -- socket; the host keeps listening (its old peers just go quiet)
  local h, address = CoopHub.takeOver(job, not CoopHub.isHost)
  if not h then
    CoopHub.state, CoopHub.error = "failed", "LINK LOST"
    return
  end
  local path = job.path
  local CM = manager()
  if CM.adopt(h, CoopHub.isHost, address) then
    CoopHub.state = "linked"
    local okC, Connector = pcall(require, "src.online.net.Connector")
    CoopHub.status = okC and string.upper(Connector.describe(path)) or "LINKED"
    log("info", "linked (" .. tostring(path) .. ") with " .. tostring(address))
  else
    CoopHub.state, CoopHub.error = "failed", "COULD NOT ADOPT THE LINK"
  end
end

function CoopHub.update(dt)
  local job = CoopHub.job
  if not job or CoopHub.state == "linked" or CoopHub.state == "failed" then return end
  local ok, err = pcall(job.update, job)
  if not ok then
    CoopHub.state, CoopHub.error = "failed", tostring(err)
    log("error", "ladder: " .. tostring(err))
    return
  end
  if CoopHub.state == "hosting" then
    if job.state == "failed" then
      CoopHub.state, CoopHub.error = "failed", tostring(job.reason or "CAN'T HOST")
      return
    end
    if not CoopHub.code and job.state ~= "starting" and not job.pending then
      CoopHub.waited = (CoopHub.waited or 0) + (dt or 0)
      local s = CoopHub.settingsUsed or {}
      if (job.info and job.info.hubTicket) or not s.hubAddress or CoopHub.waited >= CoopHub.HUB_WAIT then
        local code, kind = buildCode(job, s)
        CoopHub.code, CoopHub.codeKind = code, kind
        CoopHub.status = kind == "hub" and "VIA THE LINK HUB" or "DIRECT CODE"
        log("info", "code ready (" .. tostring(kind) .. ")")
      end
    end
    -- THE HAND-OVER IS AGREED ON THE LADDER'S OWN CHANNEL.  The host takes
    -- the socket only when the guest says its side is through
    -- (pkm_hub_ready): taking it earlier stopped the ladder answering a
    -- guest still finishing its handshake, and the guest's ladder failed.
    -- The host answers pkm_hub_go, and only then does the guest redial.
    if job.state == "connected" and job.channel then
      local ch = job.channel
      pcall(ch.update, ch)
      local okP, msgs = pcall(ch.poll, ch)
      for _, m in ipairs(okP and msgs or {}) do
        if type(m) == "table" and m.type == "pkm_hub_ready" then CoopHub.peerReady = true end
      end
      if CoopHub.peerReady then
        pcall(ch.send, ch, { type = "pkm_hub_go" })
        pcall(job.update, job)
        adopt(job)
      end
    end
  elseif CoopHub.state == "joining" then
    if job.state == "failed" then
      CoopHub.state, CoopHub.error = "failed", tostring(job.reason or "COULD NOT REACH THE HOST")
      log("warn", "join failed: " .. tostring(job.reason))
      return
    end
    if job.progress then CoopHub.status = string.upper(tostring(job.progress)) end
    if job.state == "connected" and job.channel then
      local ch = job.channel
      CoopHub.readyWait = (CoopHub.readyWait or 0) + (dt or 0)
      if not CoopHub.sentReadyAt or CoopHub.readyWait - CoopHub.sentReadyAt >= 1 then
        pcall(ch.send, ch, { type = "pkm_hub_ready" })
        CoopHub.sentReadyAt = CoopHub.readyWait
      end
      pcall(ch.update, ch)
      local okP, msgs = pcall(ch.poll, ch)
      for _, m in ipairs(okP and msgs or {}) do
        if type(m) == "table" and m.type == "pkm_hub_go" then adopt(job) return end
      end
      if CoopHub.readyWait > 15 then
        CoopHub.state, CoopHub.error = "failed", "THE HOST DID NOT ANSWER"
      end
    end
  end
end

return CoopHub
