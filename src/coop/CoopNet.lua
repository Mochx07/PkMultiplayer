-- src/coop/CoopNet.lua
-- Network transport for Gen2Recomped Co-op Mode (lua-enet, bundled with LÖVE).
--
-- Two channels:
--   0  reliable + ordered: everything that must arrive (handshake, battle
--      turns, story flags, chat...).
--   1  unreliable + sequenced: overworld position snapshots.  A late or lost
--      snapshot is simply superseded by the next one, so it never stalls the
--      reliable stream behind it (head-of-line blocking was what made the
--      partner freeze and then teleport).
--
-- States:
--   DISCONNECTED  nothing open
--   LISTENING     host socket open, no partner yet (host goes back here when
--                 a partner leaves or a reconnect window expires)
--   CONNECTING    guest dialing the host
--   HANDSHAKE     enet link up, waiting for the coop_hello exchange
--   SYNCED        handshake done (set by CoopManager via markSynced)
--   RECONNECTING  link dropped mid-session; guest re-dials, host waits
--
-- THE SESSION OUTLIVES THE CONNECTION.  enet is reliable inside one
-- connection, but a link that dies takes with it everything sent in the
-- seconds before enet noticed, and a new connection starts from nothing.
-- So every reliable message carries a session sequence number and stays in
-- the outbox until the partner acknowledges it (`coop_ack`, also carried by
-- the ping).  A new connection opens with `coop_resume`: each side says who
-- it is and the last message it received; when both remember the same
-- session, only what the other never got is sent again, and anything that
-- arrives twice is dropped by its number.  A partner who restarted the game
-- is a new session: nothing old is replayed into it.  While the host is
-- waiting for its partner to come back, only the same save may take the
-- slot (`identity`, the save's co-op id).

local Json = require("src.link.Json")
local CoopLog = require("src.coop.CoopLog")

local hasEnet, enet = pcall(require, "enet")
if not hasEnet then enet = nil end

local CoopNet = {}
CoopNet.__index = CoopNet

CoopNet.DEFAULT_PORT = 7777
-- 3: foes roll their target from the shared RNG and story scenes send the
-- whole state diff -- a v2 copy would resolve the same turn differently
-- 7: story events count for the partner on any map and wait out a dropped
-- link -- a v6 copy would drop every event from another map
-- 10: the doubles AI plans the foes' turn together and a hit follows the
-- slot after a switch -- a v9 copy would resolve the same turn differently
-- 11: an egg crosses the cable as an egg and stays out of a link battle -- a
-- v10 copy would send the egg out on its side only
-- 12: a Wrap holds the foe it hit and the guest sweeps the field in the
-- host's order -- a v11 copy would resolve the same turn differently
-- 13: X items and the flute ride with the turn, a fallen partner's slot waits
-- for their own pick, and a revive brings a player back -- a v12 copy would
-- resolve those turns differently
-- 14: the session layer (sequence numbers, acks, coop_resume) -- a v13 copy
-- sends none of it
CoopNet.PROTOCOL = 14
CoopNet.CHANNELS = 2
CoopNet.CH_RELIABLE = 0
CoopNet.CH_FAST = 1

CoopNet.STATE = {
  DISCONNECTED = "DISCONNECTED",
  LISTENING    = "LISTENING",
  CONNECTING   = "CONNECTING",
  HANDSHAKE    = "HANDSHAKE",
  SYNCED       = "SYNCED",
  RECONNECTING = "RECONNECTING",
}

CoopNet.PING_INTERVAL   = 1.0   -- keepalive / RTT probe
CoopNet.STALL_TIMEOUT   = 4.0   -- no packet for this long: link flagged weak
CoopNet.CONNECT_TIMEOUT = 12.0  -- guest gives up dialing a host that never answers
CoopNet.RECONNECT_RETRY = 2.0   -- first guest re-dial while RECONNECTING...
CoopNet.RECONNECT_RETRY_MAX = 8.0 -- ...then slower, so a slow link can finish connecting
CoopNet.RECONNECT_MAX   = 60.0  -- reconnect window before the session is dropped
CoopNet.OUTBOX_MAX      = 2048  -- reliable messages kept until the partner has them
CoopNet.ACK_INTERVAL    = 0.1   -- how soon a received message is acknowledged
CoopNet.RESUME_TIMEOUT  = 6.0   -- a connection that never says coop_resume is dropped

-- never sequenced or acknowledged: they describe the connection itself
local CONTROL = { coop_ping = true, coop_pong = true, coop_ack = true,
                  coop_resume = true, coop_busy = true }
-- what a peer from before the session layer may send first: passed on so
-- the handshake can tell the player which version the partner has
local LEGACY_FIRST = { coop_hello = true, coop_welcome = true, coop_reject = true }

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

function CoopNet.available()
  return enet ~= nil
end

-- ---------------------------------------------------------------------
-- Address discovery.  These shell out (`ip`, `ipconfig`) or open sockets,
-- so they are cached: the lobby and menu draw them every frame, and a
-- popen per frame froze the game for tens of milliseconds at a time.
-- ---------------------------------------------------------------------

local IP_CACHE_TTL = 15.0
local ipCache = {}

local function cached(key, fn)
  local entry = ipCache[key]
  local t = now()
  if entry and (t - entry.at) < IP_CACHE_TTL then return entry.value end
  local value = fn()
  ipCache[key] = { value = value, at = t }
  return value
end

function CoopNet.clearAddressCache()
  ipCache = {}
end

local function detectLanIP()
  local ok, ip = pcall(function()
    local socket = require("socket")
    local udp = socket.udp()
    udp:setpeername("192.0.2.1", 9)
    local addr = udp:getsockname()
    udp:close()
    return addr
  end)
  if ok and ip and ip ~= "0.0.0.0" then return ip end
  return "127.0.0.1"
end

function CoopNet.lanIP()
  return cached("lan", detectLanIP)
end

-- The address this machine would send from to reach `target`: a UDP socket
-- "connected" to it sends nothing, but the OS picks the route and the source
-- address.  Works the same on phones, where there is no shell to ask.
local function sourceAddressFor(target)
  local ok, addr = pcall(function()
    local socket = require("socket")
    local udp = socket.udp()
    udp:setpeername(target, 9)
    local a = udp:getsockname()
    udp:close()
    return a
  end)
  if ok and type(addr) == "string" and addr ~= "0.0.0.0" then return addr end
  return nil
end
CoopNet.sourceAddressFor = sourceAddressFor

-- The pools ZeroTier Central hands addresses out of ("Auto-Assign from
-- Range"), as dotted prefixes.  A network on one of these routes it through
-- the ZeroTier interface (or, on iOS and Android, the ZeroTier VPN), so the
-- address the OS picks to reach a host inside one is our ZeroTier address.
CoopNet.ZEROTIER_POOLS = {
  "10.147.17.", "10.147.18.", "10.147.19.", "10.147.20.",
  "10.144.", "10.241.", "10.242.", "10.243.", "10.244.",
  "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
  "172.27.", "172.28.", "172.29.", "172.30.",
  "192.168.191.", "192.168.192.", "192.168.193.",
  "192.168.194.", "192.168.195.", "192.168.196.",
}

-- `lanIP` is where the default route leaves from; a pool address that comes
-- out the same is just a home network that happens to use that range.
function CoopNet.probeZeroTierIP(probe, lanIP)
  probe = probe or sourceAddressFor
  lanIP = lanIP or probe("192.0.2.1")
  for _, pool in ipairs(CoopNet.ZEROTIER_POOLS) do
    local target = pool .. (select(2, pool:gsub("%.", "")) == 2 and "0.1" or "1")
    local addr = probe(target)
    if addr and addr ~= lanIP and addr:sub(1, #pool) == pool then return addr end
  end
  return nil
end

local function detectZeroTierIP()
  -- 0. Any platform, phones included: which pool gets its own route
  local probed = CoopNet.probeZeroTierIP()
  if probed then return probed end

  -- the shell lookups below find a network on a custom range too, but a
  -- phone has no shell (io.popen is missing or fails there)
  if not io.popen then return nil end

  -- 1. Linux: ZeroTier interfaces are named zt*
  local ok, ip = pcall(function()
    local handle = io.popen("ip -4 -o addr show 2>/dev/null")
    if not handle then return nil end
    for line in handle:lines() do
      local iface, addr = line:match("%d+:%s+([%w_%.%-]+)%s+inet%s+(%d+%.%d+%.%d+%.%d+)")
      if iface and (iface:find("^zt") or iface:lower():find("zerotier")) then
        handle:close()
        return addr
      end
    end
    handle:close()
    return nil
  end)
  if ok and ip and #ip > 6 then return ip end

  -- 2. Windows: the adapter section is titled "... ZeroTier One [xxxx]"
  if package.config:sub(1, 1) == "\\" then
    local ok2, ip2 = pcall(function()
      local handle = io.popen("ipconfig 2>nul")
      if not handle then return nil end
      local inZT = false
      for line in handle:lines() do
        local low = line:lower()
        if not line:match("^%s") and line:match("%S") then
          -- a new adapter header (unindented line)
          inZT = low:find("zerotier") ~= nil
        elseif inZT and (low:find("ipv4") or low:find("direcci")) then
          local addr = line:match("(%d+%.%d+%.%d+%.%d+)")
          if addr and not addr:find("^127%.") and not addr:find("^169%.254%.") then
            handle:close()
            return addr
          end
        end
      end
      handle:close()
      return nil
    end)
    if ok2 and ip2 and #ip2 > 6 then return ip2 end
  end
  return nil
end

function CoopNet.zeroTierIP()
  return cached("zt", detectZeroTierIP) or nil
end

-- Best IP address to display or prefill (ZeroTier prioritized if present)
function CoopNet.bestIP()
  local zt = CoopNet.zeroTierIP()
  if zt then return zt, true end
  return CoopNet.lanIP(), false
end

-- Detect system country code or locale
function CoopNet.detectCountry()
  local ok, country = pcall(function()
    for _, var in ipairs({ "LC_ALL", "LC_MESSAGES", "LANG", "LC_TIME" }) do
      local val = os.getenv(var)
      if val and #val > 0 then
        local c = val:match("^[a-zA-Z]+_([A-Z][A-Z])")
        if c then return c end
      end
    end
    return "US"
  end)
  if ok and country then return country end
  return "US"
end

-- Detect system timezone offset and current formatted time
function CoopNet.detectTimezone()
  local ok, tzInfo = pcall(function()
    local t = os.time()
    local localDate = os.date("*t", t)
    local utcDate = os.date("!*t", t)
    -- os.time() reads a table as LOCAL time, so DST must be carried over or
    -- the difference is an hour off half the year
    utcDate.isdst = localDate.isdst
    local diff = os.difftime(os.time(localDate), os.time(utcDate))
    local sign = (diff >= 0) and "+" or "-"
    local abs = math.abs(diff)
    local hours = math.floor(abs / 3600)
    local mins = math.floor((abs % 3600) / 60)
    return {
      offsetSec = diff,
      label = string.format("UTC%s%d:%02d", sign, hours, mins),
      timeStr = os.date("%H:%M", t),
      hours = (diff >= 0) and hours or -hours,
      mins = mins,
    }
  end)
  if ok and tzInfo then return tzInfo end
  return { offsetSec = 0, label = "UTC+0:00", timeStr = "12:00", hours = 0, mins = 0 }
end

-- ---------------------------------------------------------------------
-- Wire encoding.  Messages carry game tables (moves, Pokemon) that may
-- hold functions, userdata or back-references; Json.encode raises on the
-- first of those, and an error inside send() used to vanish into the
-- caller's pcall with the message never sent.  wire() makes a plain,
-- acyclic copy that always encodes.
-- ---------------------------------------------------------------------

local function wireCopy(v, depth, seen)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return 0 end
    return v
  end
  if t == "string" or t == "boolean" then return v end
  if t ~= "table" then return nil end
  if depth > 10 or seen[v] then return nil end
  seen[v] = true
  local out = {}
  local n = #v
  if n > 0 then
    for i = 1, n do out[i] = wireCopy(v[i], depth + 1, seen) end
    -- keep arrays dense; nil holes would turn them into objects
    for i = 1, n do if out[i] == nil then out[i] = false end end
  else
    for k, val in pairs(v) do
      local kt = type(k)
      if kt == "string" or kt == "number" then
        local c = wireCopy(val, depth + 1, seen)
        if c ~= nil then out[tostring(k)] = c end
      end
    end
  end
  seen[v] = nil
  return out
end

function CoopNet.wire(v)
  return wireCopy(v, 0, {})
end

function CoopNet.encode(msg)
  local ok, text = pcall(Json.encode, wireCopy(msg, 0, {}))
  if ok then return text end
  CoopLog.error("NET", "encode failed for " .. tostring(msg and msg.type) .. ": " .. tostring(text))
  return nil
end

-- ---------------------------------------------------------------------

local idCounter = 0
local function newId()
  idCounter = idCounter + 1
  local r = (love and love.math and love.math.random) or math.random
  return string.format("%x%06x%04x", os.time() % 0x10000000, r(0, 0xFFFFFF), idCounter % 0x10000)
end
CoopNet.newId = newId

function CoopNet.new()
  local self = setmetatable({
    enetHost = nil,
    peer = nil,
    candidate = nil,        -- host: a connection waiting to prove it is the partner
    state = CoopNet.STATE.DISCONNECTED,
    isHost = false,
    address = nil,
    port = CoopNet.DEFAULT_PORT,
    inbox = {},
    outbox = {},            -- { seq, text, type }: sent or not, until acknowledged
    error = nil,
    closed = true,
    paired = false,
    resumed = false,        -- this connection's coop_resume exchange is done
    sessionActive = false,  -- a handshake has completed at least once

    identity = nil,         -- the save's co-op id (CoopManager sets it)
    localSession = newId(),
    peerSession = nil,
    peerId = nil,
    sendSeq = 0,
    recvSeq = 0,
    ackDirty = false,
    ackTimer = 0,
    resumeTimer = 0,
    stats = { resent = 0, dupes = 0, reconnects = 0 },

    pingTimer = 0,
    rttMs = 0,
    lastHeartbeat = 0,
    stalled = false,
    reconnectTimer = 0,
    reconnectRetryTimer = 0,
    reconnectAttempts = 0,
    connectTimer = 0,

    country = CoopNet.detectCountry(),
    timezone = CoopNet.detectTimezone(),
  }, CoopNet)
  return self
end

function CoopNet:setState(newState, reason)
  if self.state ~= newState then
    CoopLog.sync("STATE_CHANGE", string.format("%s -> %s (%s)", self.state, newState, reason or "normal"))
    self.state = newState
    table.insert(self.inbox, { type = "net_state_change", state = newState, reason = reason })
  end
end

-- CoopManager calls this once both hellos have crossed
function CoopNet:markSynced()
  self.sessionActive = true
  self.reconnectTimer = 0
  self:setState(CoopNet.STATE.SYNCED, "Handshake completed")
end

function CoopNet:isLinked()
  return not self.closed and self.paired and self.resumed and self.peer ~= nil
end

-- a new session: nothing of the last partner's is kept or replayed
function CoopNet:resetSession()
  self.localSession = newId()
  self.peerSession = nil
  self.peerId = nil
  self.sendSeq = 0
  self.recvSeq = 0
  self.outbox = {}
  self.ackDirty = false
end

local function configurePeer(peer)
  if peer and peer.timeout then
    -- limit, minimum, maximum (ms): give up on a silent peer within ~12s so
    -- the reconnect loop can take over instead of waiting a full minute (a
    -- long frame -- a save, a map load -- must not count as a drop)
    pcall(peer.timeout, peer, 32, 3000, 12000)
  end
  if peer and peer.ping_interval then pcall(peer.ping_interval, peer, 500) end
end

local function openHost(self, address, peers)
  local ok, h, err = pcall(enet.host_create, address, peers, CoopNet.CHANNELS)
  if not ok or not h then return nil, err or h end
  return h
end

function CoopNet:host(port)
  port = port or CoopNet.DEFAULT_PORT
  if not enet then
    self.error = "Co-op needs lua-enet (bundled with LÖVE)"
    CoopLog.error("NET", self.error)
    return false
  end
  self:close()
  self.inbox = {}

  local h, err = openHost(self, ("*:%d"):format(port), 4)
  if not h then
    self.error = "PORT " .. port .. " IN USE"
    CoopLog.error("NET", tostring(err or ("Failed to bind port " .. port)))
    return false
  end

  self.enetHost = h
  self.isHost = true
  self.closed = false
  self.paired = false
  self.sessionActive = false
  self.error = nil
  self.port = port
  self:resetSession()
  self.address = ("%s:%d"):format(CoopNet.lanIP(), port)

  self:setState(CoopNet.STATE.LISTENING, "Server started on " .. self.address)
  CoopLog.info("NET", "Hosting on " .. self.address)
  return true
end

function CoopNet:dial()
  if not self.enetHost or not self.address then return false end
  local ok, peer = pcall(self.enetHost.connect, self.enetHost, self.address, CoopNet.CHANNELS)
  if ok and peer then
    self.peer = peer
    self.resumed = false
    configurePeer(peer)
    return true
  end
  return false
end

function CoopNet:join(host, port)
  port = port or CoopNet.DEFAULT_PORT
  if not enet then
    self.error = "Co-op needs lua-enet (bundled with LÖVE)"
    CoopLog.error("NET", self.error)
    return false
  end
  self:close()
  self.inbox = {}

  local h, err = openHost(self, nil, 1)
  if not h then
    self.error = "NETWORK UNAVAILABLE"
    CoopLog.error("NET", tostring(err or "Failed to create client socket"))
    return false
  end

  self.enetHost = h
  self.isHost = false
  self.closed = false
  self.paired = false
  self.sessionActive = false
  self.error = nil
  self.port = port
  self:resetSession()
  self.connectTimer = 0

  self.address = host:find(":") and host or ("%s:%d"):format(host, port)

  if not self:dial() then
    self:close()
    self.error = "BAD ADDRESS"
    CoopLog.error("NET", "Failed to initiate connect to " .. tostring(self.address))
    return false
  end

  self:setState(CoopNet.STATE.CONNECTING, "Connecting to " .. self.address)
  CoopLog.info("NET", "Connecting to " .. self.address)
  return true
end

local QUIET_TYPES = { coop_pos = true }

local function rawSend(peer, text, channel, flag)
  if not peer then return false end
  local ok = pcall(peer.send, peer, text, channel, flag)
  return ok
end

local function sendControl(peer, msg)
  local ok, text = pcall(Json.encode, msg)
  if ok then rawSend(peer, text, CoopNet.CH_RELIABLE, "reliable") end
end

-- send(msg)                -> reliable: numbered, kept until acknowledged
-- send(msg, { fast = true }) -> unreliable sequenced, dropped while down
-- The caller's table is never changed.
function CoopNet:send(msg, opts)
  if not msg or self.closed then return false end
  local fast = opts and opts.fast

  local out = wireCopy(msg, 0, {})
  if type(out) ~= "table" then return false end
  local linked = self:isLinked()
                 and (self.state == CoopNet.STATE.SYNCED or self.state == CoopNet.STATE.HANDSHAKE)

  if msg.type == "coop_reject" and self.peer and self.paired and not self.resumed then
    -- a partner from before the session layer never resumes: tell it now
    local ok, text = pcall(Json.encode, out)
    if ok then rawSend(self.peer, text, CoopNet.CH_RELIABLE, "reliable") end
    return ok
  end

  if fast then
    if not linked then return false end
    local ok, text = pcall(Json.encode, out)
    if not ok then return false end
    rawSend(self.peer, text, CoopNet.CH_FAST, "unreliable")
    return true
  end

  self.sendSeq = self.sendSeq + 1
  out.seq = self.sendSeq
  local ok, text = pcall(Json.encode, out)
  if not ok then
    CoopLog.error("NET", "encode failed for " .. tostring(msg.type) .. ": " .. tostring(text))
    return false
  end
  if #self.outbox >= CoopNet.OUTBOX_MAX then
    local lost = table.remove(self.outbox, 1)
    CoopLog.error("NET", "outbox full: dropped unacknowledged " .. tostring(lost and lost.type))
  end
  table.insert(self.outbox, { seq = out.seq, text = text, type = msg.type })

  if linked then
    rawSend(self.peer, text, CoopNet.CH_RELIABLE, "reliable")
    if not QUIET_TYPES[msg.type] then CoopLog.net("-> SEND", msg.type, msg) end
  else
    CoopLog.net(".. QUEUE", msg.type, msg)
  end
  return true
end

-- everything the partner has confirmed can go
function CoopNet:acknowledged(upTo)
  upTo = tonumber(upTo)
  if not upTo then return end
  local keep, n = {}, 0
  for _, e in ipairs(self.outbox) do
    if e.seq > upTo then n = n + 1; keep[n] = e end
  end
  self.outbox = keep
end

function CoopNet:sendPing()
  if not self.peer or not self.resumed then return end
  local text = Json.encode({ type = "coop_ping", t = now(), a = self.recvSeq })
  rawSend(self.peer, text, CoopNet.CH_RELIABLE, "unsequenced")
  self.ackDirty = false
end

function CoopNet:sendPong(t)
  if not self.peer then return end
  local text = Json.encode({ type = "coop_pong", t = t })
  rawSend(self.peer, text, CoopNet.CH_RELIABLE, "unsequenced")
end

-- 0..3 signal bars for the HUD
function CoopNet:linkQuality()
  if not self:isLinked() then return 0 end
  if self.stalled then return 1 end
  local rtt = self.rttMs or 0
  if rtt <= 90 then return 3 end
  if rtt <= 220 then return 2 end
  return 1
end

function CoopNet:sendResume(peer)
  sendControl(peer, {
    type = "coop_resume", proto = CoopNet.PROTOCOL,
    session = self.localSession, peer = self.peerSession,
    ack = self.recvSeq, id = self.identity,
  })
end

function CoopNet:onPeerConnected(peer, t)
  -- A HOST ONLY EVER HAS ONE PARTNER.  A second machine dialing in while the
  -- partner is alive is turned away.  One dialing in after the partner went
  -- silent may be the partner coming back on a new connection: it waits as
  -- the candidate until its coop_resume says who it is, and the live
  -- connection is only given up for it then.
  if self.isHost and self.peer and self.peer ~= peer then
    if self.paired and (t - self.lastHeartbeat) < CoopNet.STALL_TIMEOUT then
      CoopLog.warn("NET", "Rejected extra connection: a partner is already linked")
      pcall(peer.disconnect_now, peer, 3)
      return
    end
    if self.candidate and self.candidate ~= peer then pcall(self.candidate.reset, self.candidate) end
    self.candidate = peer
    self.candidateTimer = 0
    configurePeer(peer)
    self:sendResume(peer)
    return
  end

  self.peer = peer
  configurePeer(peer)
  self.paired = true
  self.resumed = false
  self.resumeTimer = 0
  self.stalled = false
  self.lastHeartbeat = t
  self.connectTimer = 0
  self.error = nil
  CoopLog.info("NET", "Link established with peer; resuming the session")
  self:sendResume(peer)
end

-- the coop_resume of `peer` (the live connection or the host's candidate)
function CoopNet:onResume(peer, msg, t)
  -- while waiting for its partner, the host keeps the place for that save
  local waiting = self.isHost and self.sessionActive and self.peerId ~= nil
  if waiting and msg.id ~= self.peerId then
    CoopLog.warn("NET", "Turned away a connection that is not the partner (" .. tostring(msg.id) .. ")")
    sendControl(peer, { type = "coop_busy" })
    pcall(peer.disconnect_later, peer, 3)
    if peer == self.candidate then
      self.candidate = nil
    else
      self.peer, self.paired, self.resumed = nil, false, false
    end
    return
  end

  if peer == self.candidate then
    if self.peer then pcall(self.peer.reset, self.peer) end
    self.candidate = nil
    self.peer = peer
    self.paired = true
    self.lastHeartbeat = t
    self.connectTimer = 0
    self.error = nil
  end

  local continuation = self.peerSession ~= nil and msg.session == self.peerSession
                       and msg.peer == self.localSession
  if continuation then
    self:acknowledged(msg.ack)
  else
    if self.peerSession ~= nil then
      -- they are a new game (or a new partner): what was meant for the last
      -- one is not theirs
      CoopLog.info("NET", string.format("Partner is a new session; dropping %d old messages", #self.outbox))
      self.outbox = {}
    end
    self.recvSeq = 0
  end
  self.peerSession = msg.session
  self.peerId = msg.id
  self.resumed = true
  self.ackDirty = false
  self.reconnectTimer = 0
  self.reconnectAttempts = 0
  if self.sessionActive then self.stats.reconnects = self.stats.reconnects + 1 end

  for _, e in ipairs(self.outbox) do
    rawSend(peer, e.text, CoopNet.CH_RELIABLE, "reliable")
  end
  if continuation and #self.outbox > 0 then
    self.stats.resent = self.stats.resent + #self.outbox
    CoopLog.info("NET", string.format("Resumed the session: %d messages sent again", #self.outbox))
  end

  self:setState(CoopNet.STATE.HANDSHAKE, continuation and "Session resumed" or "Peer connected; starting handshake")
  table.insert(self.inbox, { type = "net_connect", reconnect = self.sessionActive, resumed = continuation })
end

function CoopNet:onPeerDisconnected(peer, data)
  if peer == self.candidate then
    self.candidate = nil
    return
  end
  if peer ~= self.peer then
    -- a late disconnect for a connection that was already replaced (the old
    -- link of a partner who has since reconnected) must not drop the new one
    CoopLog.info("NET", "Ignoring disconnect of a stale peer")
    return
  end
  local code = tonumber(data) or 0
  self.paired = false
  self.resumed = false
  self.peer = nil
  self.stalled = false
  local intentional = code == 2 or self.byeReceived

  if code == 4 and not self.isHost then
    -- the host refused us; its coop_reject (just before) said why
    self.error = self.rejectReason or "PARTNER REFUSED THE LINK"
    self:close()
    table.insert(self.inbox, { type = "net_disconnect", reason = "refused" })
    return
  end
  if code == 3 and not self.isHost then
    -- the host is keeping its place for another save
    self.error = "HOST IS BUSY"
    CoopLog.warn("NET", "The host is waiting for its own partner")
    self:close()
    table.insert(self.inbox, { type = "net_disconnect", reason = "busy" })
    return
  end

  if self.state == CoopNet.STATE.CONNECTING and not self.sessionActive then
    self.error = "HOST NOT FOUND"
    CoopLog.warn("NET", "Could not reach host " .. tostring(self.address))
    self:close()
    table.insert(self.inbox, { type = "net_disconnect", reason = "unreachable" })
    return
  end

  if intentional then
    CoopLog.info("NET", "Partner left the session")
    self.sessionActive = false
    self.byeReceived = false
    if self.isHost then
      self:resetSession()
      self:setState(CoopNet.STATE.LISTENING, "Partner left; waiting for a new partner")
    else
      self:close()
    end
    table.insert(self.inbox, { type = "net_disconnect", reason = "left" })
    return
  end

  CoopLog.warn("NET", "Link lost; entering reconnect window")
  self.reconnectTimer = 0
  self.reconnectAttempts = 0
  self.reconnectRetryTimer = CoopNet.RECONNECT_RETRY -- guest re-dials at once
  self:setState(CoopNet.STATE.RECONNECTING, "Link lost")
  table.insert(self.inbox, { type = "net_disconnect", reason = "lost" })
end

function CoopNet:onReceive(peer, data, t)
  local okJson, msg = pcall(Json.decode, data)
  if not (okJson and type(msg) == "table" and type(msg.type) == "string") then
    CoopLog.warn("NET", "Dropped undecodable packet")
    return
  end
  if peer == self.candidate then
    if msg.type == "coop_resume" then self:onResume(peer, msg, t) end
    return
  end
  if peer ~= self.peer then return end
  self.lastHeartbeat = t
  self.stalled = false

  local kind = msg.type
  if kind == "coop_resume" then
    self:onResume(peer, msg, t)
  elseif kind == "coop_ping" then
    self:sendPong(msg.t)
    self:acknowledged(msg.a)
  elseif kind == "coop_pong" then
    if tonumber(msg.t) then
      self.rttMs = math.max(0, math.floor((t - msg.t) * 1000 + 0.5))
    end
  elseif kind == "coop_ack" then
    self:acknowledged(msg.a)
  elseif kind == "coop_busy" then
    self.byeReceived = false
  elseif kind:sub(1, 4) == "net_" then
    -- the transport's own events never come over the wire
    CoopLog.warn("NET", "Dropped a packet posing as a local event: " .. kind)
  elseif not self.resumed then
    -- a partner from before the session layer: let the handshake see its
    -- hello, so the player is told which version the partner has
    if LEGACY_FIRST[kind] then
      if kind == "coop_reject" then self.rejectReason = tostring(msg.reason or "") end
      table.insert(self.inbox, msg)
    end
  else
    local seq = tonumber(msg.seq)
    if seq then
      if seq <= self.recvSeq then
        self.stats.dupes = self.stats.dupes + 1
        CoopLog.info("NET", "Dropped a message received twice: " .. kind .. " #" .. seq)
        self.ackDirty = true
        return
      end
      self.recvSeq = seq
      self.ackDirty = true
    end
    if kind == "coop_bye" then self.byeReceived = true end
    if kind == "coop_reject" then self.rejectReason = tostring(msg.reason or "") end
    if not QUIET_TYPES[kind] then CoopLog.net("<- RECV", kind, msg) end
    table.insert(self.inbox, msg)
  end
end

function CoopNet:update(dt)
  if not self.enetHost or self.closed then return end
  dt = dt or 0.016
  local t = now()

  -- 1. enet events
  for _ = 1, 256 do
    local ok, event = pcall(self.enetHost.service, self.enetHost, 0)
    if not ok or not event then break end

    if event.type == "connect" then
      self:onPeerConnected(event.peer, t)

    elseif event.type == "disconnect" then
      self:onPeerDisconnected(event.peer, event.data)
      if self.closed then return end

    elseif event.type == "receive" then
      self:onReceive(event.peer, event.data, t)
      if self.closed then return end
    end
  end

  -- 2. acknowledgements, keepalive + stall detection on a live link
  if self.paired and self.peer then
    if not self.resumed then
      self.resumeTimer = self.resumeTimer + dt
      if self.resumeTimer >= CoopNet.RESUME_TIMEOUT then
        CoopLog.warn("NET", "The partner never resumed the session; dropping the connection")
        self.resumeTimer = 0
        pcall(self.peer.reset, self.peer)
        self:onPeerDisconnected(self.peer, 0)
        if self.closed then return end
      end
    end
  end
  if self.paired and self.peer and self.resumed then
    self.ackTimer = self.ackTimer + dt
    if self.ackDirty and self.ackTimer >= CoopNet.ACK_INTERVAL then
      self.ackTimer = 0
      self.ackDirty = false
      local text = Json.encode({ type = "coop_ack", a = self.recvSeq })
      rawSend(self.peer, text, CoopNet.CH_RELIABLE, "unsequenced")
    end
    self.pingTimer = self.pingTimer + dt
    if self.pingTimer >= CoopNet.PING_INTERVAL then
      self.pingTimer = 0
      self:sendPing()
    end
    local quiet = t - self.lastHeartbeat
    if quiet > CoopNet.STALL_TIMEOUT and not self.stalled then
      self.stalled = true
      CoopLog.warn("NET", string.format("Link stalled (%.1fs without packets)", quiet))
      table.insert(self.inbox, { type = "net_stalled" })
    end
  end
  if self.candidate then
    self.candidateTimer = (self.candidateTimer or 0) + dt
    if self.candidateTimer >= CoopNet.RESUME_TIMEOUT then
      pcall(self.candidate.reset, self.candidate)
      self.candidate = nil
    end
  end

  -- 3. guest dialing a host that never answers
  if self.state == CoopNet.STATE.CONNECTING and not self.resumed then
    self.connectTimer = self.connectTimer + dt
    if self.connectTimer >= CoopNet.CONNECT_TIMEOUT then
      self.error = "HOST NOT FOUND"
      CoopLog.warn("NET", "Connect timed out for " .. tostring(self.address))
      self:close()
      table.insert(self.inbox, { type = "net_disconnect", reason = "unreachable" })
      return
    end
  end

  -- 4. reconnect window
  if self.state == CoopNet.STATE.RECONNECTING then
    if not self.isHost and not self.paired then
      -- each try waits longer than the last, so a slow link (ZeroTier
      -- relaying) has time to finish a connect before it is cut off
      local wait = math.min(CoopNet.RECONNECT_RETRY_MAX, CoopNet.RECONNECT_RETRY * (self.reconnectAttempts + 1))
      if self.reconnectAttempts == 0 then wait = CoopNet.RECONNECT_RETRY end
      self.reconnectRetryTimer = self.reconnectRetryTimer + dt
      if self.reconnectRetryTimer >= wait then
        self.reconnectRetryTimer = 0
        self.reconnectAttempts = self.reconnectAttempts + 1
        if self.peer then pcall(self.peer.reset, self.peer) end
        self.peer = nil
        self:dial()
      end
    end
    self.reconnectTimer = self.reconnectTimer + dt
    if self.reconnectTimer >= CoopNet.RECONNECT_MAX then
      CoopLog.error("NET", "Reconnect window expired; dropping the session")
      self.sessionActive = false
      if self.isHost then
        if self.peer then pcall(self.peer.reset, self.peer) end
        self.peer = nil
        self.paired, self.resumed = false, false
        self:resetSession()
        self:setState(CoopNet.STATE.LISTENING, "Reconnect window expired; waiting for a partner")
        table.insert(self.inbox, { type = "net_disconnect", reason = "timeout" })
      else
        self.error = "LINK LOST"
        self:close()
        table.insert(self.inbox, { type = "net_disconnect", reason = "timeout" })
      end
    end
  end
end

function CoopNet:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

function CoopNet:flush()
  if self.enetHost then
    pcall(self.enetHost.flush, self.enetHost)
  end
end

-- The host turns one partner away (another version, another game) and
-- keeps listening for the right one; a guest just closes.
function CoopNet:dropPeer()
  if not self.isHost then return self:shutdown() end
  if self.peer then
    pcall(self.peer.disconnect_later, self.peer, 4)
    pcall(self.enetHost.flush, self.enetHost)
  end
  self.peer, self.paired, self.resumed = nil, false, false
  self.sessionActive = false
  self:resetSession()
  self:setState(CoopNet.STATE.LISTENING, "Turned a partner away; still listening")
end

-- Leave politely: the disconnect (with code 2 = "left on purpose") is given
-- a moment to reach the partner, so they see "partner left" at once instead
-- of sitting in a reconnect window until their timeout fires.
function CoopNet:shutdown()
  if self.peer and self.enetHost then
    pcall(self.peer.disconnect_later, self.peer, 2)
    for _ = 1, 10 do
      local ok, event = pcall(self.enetHost.service, self.enetHost, 15)
      if not ok then break end
      if event and event.type == "disconnect" then break end
    end
  end
  self:close()
end

function CoopNet:close()
  if self.peer then
    pcall(self.peer.disconnect_now, self.peer, 2)
    self.peer = nil
  end
  if self.candidate then
    pcall(self.candidate.disconnect_now, self.candidate, 1)
    self.candidate = nil
  end
  if self.enetHost then
    pcall(self.enetHost.flush, self.enetHost)
    pcall(self.enetHost.destroy, self.enetHost)
    self.enetHost = nil
  end
  self.paired = false
  self.resumed = false
  self.closed = true
  self.stalled = false
  self.sessionActive = false
  self.byeReceived = false
  self:resetSession()
  self:setState(CoopNet.STATE.DISCONNECTED, "Transport closed")
end

return CoopNet
