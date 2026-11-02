-- THE SESSION OUTLIVES THE CONNECTION (src/coop/CoopNet.lua).
--
-- Two (or three) CoopNet transports over a fake enet that can cut a link
-- the way a real one dies: silently first -- packets vanish for a while
-- before either side notices -- and then with a disconnect.  Every message
-- must reach the partner exactly once and in order, across drops,
-- reconnects and lost acknowledgements; a partner that restarted its game
-- gets nothing meant for the old one; and nobody else can take the
-- partner's place while the host waits for it.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_session.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local clock = 1000
love.timer.getTime = function() return clock end

-- ------------------------------------------------------------- fake enet
local hosts = {}          -- address -> host
local links = {}

local Host = {}
Host.__index = Host

local function newHost(address)
  local h = setmetatable({ events = {}, address = address }, Host)
  if address then hosts[address] = h end
  return h
end

function Host:service()
  return table.remove(self.events, 1)
end
function Host:flush() end
function Host:destroy()
  if self.address then hosts[self.address] = nil end
  self.destroyed = true
end

local Peer = {}
Peer.__index = Peer

function Peer:send(text)
  local link = self.link
  if not link.up or link.silent then return end
  table.insert(self.other.host.events, { type = "receive", peer = self.other, data = text })
end
function Peer:timeout() end
function Peer:ping_interval() end
local function drop(self, code, tell)
  local link = self.link
  if not link.up then return end
  link.up = false
  if tell then
    table.insert(self.other.host.events, { type = "disconnect", peer = self.other, data = code or 0 })
  end
end
function Peer:reset() drop(self, 0, false) end
function Peer:disconnect_now(code) drop(self, code, true) end
function Peer:disconnect_later(code) drop(self, code, true) end

function Host:connect(address)
  local server = hosts[address:gsub("^%*", "127.0.0.1")] or hosts[address]
  local link = { up = true }
  local mine = setmetatable({ host = self, link = link }, Peer)
  links[#links + 1] = link
  if not server or server.destroyed then
    link.up = false
    return mine
  end
  local theirs = setmetatable({ host = server, link = link }, Peer)
  mine.other, theirs.other = theirs, mine
  link.a, link.b = mine, theirs
  table.insert(self.events, { type = "connect", peer = mine })
  table.insert(server.events, { type = "connect", peer = theirs })
  return mine
end

package.loaded.enet = {
  host_create = function(address, peers)
    if address then
      local port = address:match(":(%d+)$")
      local key = "127.0.0.1:" .. port
      if hosts[key] then return nil, "in use" end
      return newHost(key)
    end
    return newHost(nil)
  end,
}
package.loaded["src.coop.CoopNet"] = nil
local CoopNet = require("src.coop.CoopNet")
require("src.coop.CoopLog").enabled = false
CoopNet.lanIP = function() return "127.0.0.1" end

-- the link as it dies: packets vanish first...
local function goSilent(link) link.silent = true end
-- ...then both sides notice
local function notice(link)
  if not link.up then return end
  link.up = false
  table.insert(link.a.host.events, { type = "disconnect", peer = link.a, data = 0 })
  table.insert(link.b.host.events, { type = "disconnect", peer = link.b, data = 0 })
end
local function currentLink(net) return net.peer and net.peer.link end

-- --------------------------------------------------------------- harness
local fails, total = 0, 0
local function check(cond, what)
  total = total + 1
  if cond then print("ok   " .. what) else fails = fails + 1; print("FAIL " .. what) end
end

local nets = {}
local got = {}
local function track(net, name)
  nets[#nets + 1] = net
  got[net] = { name = name, msgs = {}, events = {} }
  return net
end

local function step(dt)
  dt = dt or 0.05
  clock = clock + dt
  for _, net in ipairs(nets) do
    net:update(dt)
    for _, m in ipairs(net:poll()) do
      if m.type:sub(1, 4) == "net_" then
        local list = got[net].events
        list[#list + 1] = m
        -- what CoopManager does: a link that is up and resumed is a handshake
        if m.type == "net_connect" then net:markSynced() end
      else
        local list = got[net].msgs
        list[#list + 1] = m
      end
    end
  end
end
local function run(seconds) for _ = 1, math.floor(seconds / 0.05 + 0.5) do step(0.05) end end

local function bodies(net, kind)
  local out = {}
  for _, m in ipairs(got[net].msgs) do
    if m.type == (kind or "coop_chat") then out[#out + 1] = m.text end
  end
  return table.concat(out, ",")
end
local function lastEvent(net, kind)
  local list = got[net].events
  for i = #list, 1, -1 do if list[i].type == kind then return list[i] end end
end
local function clear(net) got[net].msgs, got[net].events = {}, {} end

local function chat(net, text) return net:send({ type = "coop_chat", text = text }) end

-- --------------------------------------------------- a link, and its acks
local host = track(CoopNet.new(), "host")
host.identity = "SAVE-HOST"
assert(host:host(7777))
local guest = track(CoopNet.new(), "guest")
guest.identity = "SAVE-GUEST"
assert(guest:join("127.0.0.1", 7777))
run(0.5)
check(host:isLinked() and guest:isLinked(), "both ends are linked after the resume exchange")
check(lastEvent(host, "net_connect") and lastEvent(guest, "net_connect"), "each end reports the link to the game")
check(host.peerId == "SAVE-GUEST" and guest.peerId == "SAVE-HOST", "each end knows the other's save")

local mine = { type = "coop_chat", text = "A" }
chat(guest, "A"); guest:send(mine); chat(guest, "B")
check(mine.seq == nil, "send() leaves the caller's table as it was")
run(0.5)
check(bodies(host) == "A,A,B", "messages arrive once each, in order")
check(#guest.outbox == 0, "acknowledged messages leave the outbox")

-- ------------------------------------- the silent seconds before a drop
clear(host); clear(guest)
local link = currentLink(guest)
goSilent(link)
chat(guest, "C"); chat(guest, "D"); chat(host, "x")
run(1)
check(bodies(host) == "", "nothing gets through a dead link")
check(#guest.outbox == 2 and #host.outbox == 1, "unacknowledged messages are kept")
notice(link)
run(0.2)
check(lastEvent(host, "net_disconnect").reason == "lost" and lastEvent(guest, "net_disconnect").reason == "lost",
      "both ends notice the link is lost (not left)")
chat(guest, "E")
run(4)
check(host:isLinked() and guest:isLinked(), "the guest dials again and the session resumes")
check(lastEvent(host, "net_connect").resumed == true, "...as the same session")
check(bodies(host) == "C,D,E", "what was lost in the silence, and what was sent while down, arrives once")
check(bodies(guest) == "x", "...both ways")
check(#guest.outbox == 0 and #host.outbox == 0, "and the outboxes empty again")

-- ------------------------------------- an acknowledgement that got lost
clear(host); clear(guest)
local acks = 0
local realSend = Peer.send
Peer.send = function(self, text)
  -- the host's acks (and pings) never leave: the guest believes F and G are lost
  if self.host == host.enetHost and (text:find('"coop_ack"') or text:find('"coop_ping"')) then
    acks = acks + 1
    return
  end
  return realSend(self, text)
end
chat(guest, "F"); chat(guest, "G")
run(1)
Peer.send = realSend
check(bodies(host) == "F,G" and #guest.outbox == 2 and acks > 0, "F and G arrived; their ack did not")
link = currentLink(guest)
goSilent(link); notice(link)
run(5)
check(guest:isLinked(), "linked again")
check(bodies(host) == "F,G", "the resent copies are dropped: each arrives once")

-- ------------------------- a partner who restarted gets nothing of the old
clear(host); clear(guest)
link = currentLink(guest)
goSilent(link)
chat(host, "for-the-old-game")
notice(link)
run(0.2)
guest:close()
local guest2 = track(CoopNet.new(), "guest2")
guest2.identity = "SAVE-GUEST"
assert(guest2:join("127.0.0.1", 7777))
run(1)
check(host:isLinked() and guest2:isLinked(), "the same save, restarted, links again")
check(lastEvent(host, "net_connect").resumed == false, "...as a new session")
check(bodies(guest2) == "", "nothing meant for the old game is replayed into the new one")
chat(guest2, "H")
run(0.5)
check(bodies(host) == "H", "and the new session works")

-- -------------------------- nobody else takes the partner's place meanwhile
clear(host); clear(guest2)
link = currentLink(guest2)
local partnerAddress = guest2.address
guest2.address = "127.0.0.1:1"      -- the partner cannot get through for now
goSilent(link); notice(link)
run(0.1)
local stranger = track(CoopNet.new(), "stranger")
stranger.identity = "SAVE-STRANGER"
assert(stranger:join("127.0.0.1", 7777))
run(1)
check(not stranger:isLinked() and stranger.closed and stranger.error == "HOST IS BUSY",
      "another save is turned away while the host waits for its partner")
check(host.state == CoopNet.STATE.RECONNECTING, "...and the host keeps waiting (" .. host.state .. ")")
chat(host, "still-yours")
guest2.address = partnerAddress
run(10)
check(host:isLinked() and guest2:isLinked() and bodies(guest2) == "still-yours",
      "the partner comes back into its place, session intact")

-- a connection that goes quiet without a disconnect: the partner's new
-- connection takes over only once it has said who it is
clear(host); clear(guest2)
goSilent(currentLink(guest2))
run(5)
local quietPeer = host.peer
guest2.peer:reset()
guest2.paired, guest2.resumed = false, false
guest2:setState(CoopNet.STATE.RECONNECTING, "test")
guest2.reconnectRetryTimer = 99
run(1)
check(host.peer ~= quietPeer and host:isLinked() and guest2:isLinked(),
      "a partner on a new connection replaces the quiet one")

-- ---------------------------------------------------------- odd packets
clear(host)
guest2.peer:send('{"type":"net_disconnect","reason":"left"}')
run(0.2)
check(host:isLinked() and lastEvent(host, "net_disconnect") == nil, "a packet named like a local event is dropped")

-- a partner from before the session layer: its hello reaches the game, so
-- the player can be told which version it has
-- a third machine while the partner is linked: it waits as a candidate
-- (it could be the partner, calling again over a link that died one way)
-- and is turned away once it says who it is -- or dropped if it never does
local third = track(CoopNet.new(), "third")
third.identity = "SAVE-THIRD"
assert(third:join("127.0.0.1", 7777))
run(1)
check(third.closed and third.error == "HOST IS BUSY" and guest2:isLinked() and host:isLinked(),
      "a third machine is told the host is busy, and the partner stays linked")
local old = newHost(nil)
local busy = old:connect("127.0.0.1:7777")
run(CoopNet.RESUME_TIMEOUT + 1)
check(not busy.link.up and guest2:isLinked(), "a connection that never says who it is is dropped")
old.events = {}
guest2:shutdown()
run(0.5)
clear(host)
local oldPeer = old:connect("127.0.0.1:7777")
run(0.1)
oldPeer:send('{"type":"coop_hello","proto":13,"ver":"1.4.1-alpha.6"}')
run(0.1)
local hello
for _, m in ipairs(got[host].msgs) do if m.type == "coop_hello" then hello = m end end
check(hello and hello.proto == 13, "an old partner's hello is passed on to the handshake")
host:send({ type = "coop_reject", reason = "PARTNER HAS V1.5.0" })
local told = false
for _, e in ipairs(old.events) do
  if e.type == "receive" and e.data:find("coop_reject") then told = true end
end
check(told, "...and the refusal reaches it")

-- ------------------------------------------- reconnects from real play
-- Each pair below gets its own port.
local function pair(port, hostId, guestId)
  local h = track(CoopNet.new(), "host" .. port); h.identity = hostId
  assert(h:host(port))
  local g = track(CoopNet.new(), "guest" .. port); g.identity = guestId
  assert(g:join("127.0.0.1", port))
  run(0.5)
  return h, g
end
local function dropBoth(net) local l = currentLink(net); if not l then return end goSilent(l); notice(l) end

-- THE SECOND RECONNECT (log 2026-10-28 22:07 resumed, 22:09:31 "Turned
-- away a connection that is not the partner"; same in a two-instance
-- repro).  The guest linked from the title screen: it resumed with the boot
-- save's id, CONTINUE loaded its own save, and the hello after the first
-- reconnect stamped that save's id on the transport.
do
  local h, g = pair(7781, "SAVE-H", "BOOT-SAVE")
  check(h:isLinked() and g:isLinked() and h.peerId == "BOOT-SAVE", "linked from the title screen (boot save id)")
  dropBoth(g)
  run(4)
  check(h:isLinked() and g:isLinked(), "the first reconnect resumes")
  g.identity = "REAL-SAVE"          -- what the reconnect's hello stamps (CoopManager.sendHello)
  clear(h); clear(g)
  chat(h, "turn-4")
  dropBoth(g)
  run(6)
  check(g.error == nil and not g.closed, "the second reconnect is not turned away (" .. tostring(g.error) .. ")")
  check(h:isLinked() and g:isLinked() and lastEvent(h, "net_connect")
        and lastEvent(h, "net_connect").resumed == true, "...it resumes the same session")
  check(bodies(g) == "turn-4", "...and what was sent meanwhile arrives")

  -- the host learns the save the partner plays from its hello / name update:
  -- a partner whose game restarted with that save takes its place back
  -- while the host is still waiting (a new session)
  ;(h.notePeerIdentity or function() end)(h, "REAL-SAVE")
  dropBoth(g)
  run(0.2)
  g:close()
  local g2 = track(CoopNet.new(), "guest7781b"); g2.identity = "REAL-SAVE"
  assert(g2:join("127.0.0.1", 7781))
  run(1)
  check(h:isLinked() and g2:isLinked() and lastEvent(h, "net_connect").resumed == false,
        "the partner's own save, restarted, is let back in while the host waits")
  g2:close()
  run(0.2)
end

-- A LINK THAT DIES ONE WAY.  The host still hears the guest (its pings get
-- through) but the guest hears nothing: enet gives up on the guest's side
-- only, the guest dials again at once, and the host -- whose partner looks
-- alive -- used to turn the call away with the busy code, which ends the
-- guest's session for good ("Rejected extra connection: a partner is
-- already linked" -> "HOST IS BUSY").
do
  local h, g = pair(7782, "SAVE-H2", "SAVE-G2")
  run(2)
  clear(h); clear(g)
  chat(h, "lost-one-way")
  local l = currentLink(g)
  local hostPeer = h.peer
  -- the host's packets stop reaching the guest; the guest's still arrive
  local realSend = Peer.send
  Peer.send = function(self, text)
    if self == hostPeer then return end
    return realSend(self, text)
  end
  run(0.5)
  table.insert(g.enetHost.events, { type = "disconnect", peer = g.peer, data = 0 })
  l.silent = true                    -- and the old connection is dead from here
  Peer.send = realSend
  run(0.3)
  check(h.peer == hostPeer or h:isLinked(), "(the host still had its partner when the call came)")
  run(5)
  check(g.error == nil and not g.closed, "the guest's new call is not refused as a stranger (" .. tostring(g.error) .. ")")
  check(h:isLinked() and g:isLinked() and h.peer ~= hostPeer, "it takes the old link's place")
  check(lastEvent(g, "net_connect") and lastEvent(g, "net_connect").resumed == true, "...as the same session")
  check(bodies(g) == "lost-one-way", "...and what the host sent into the dead link arrives once")
  -- and a stranger calling while the partner is alive is still turned away
  local s3 = track(CoopNet.new(), "stranger7782"); s3.identity = "SAVE-OTHER"
  assert(s3:join("127.0.0.1", 7782))
  run(1)
  check(s3.closed and s3.error == "HOST IS BUSY" and h:isLinked() and g:isLinked(),
        "a stranger calling over a live partner is still turned away")
  g:close(); h:close()
  run(0.2)
end

-- A CO-OP DOUBLE WAITING FOR THE PARTNER (log 2026-10-28 21:40:35 link
-- lost, 21:41:35 "Reconnect window expired", 21:43:35 the AI): the battle
-- waits LINK_GRACE with RECONNECTING... on both screens, so the session
-- must stay open (and the guest keep dialing) that long, not RECONNECT_MAX.
do
  local h, g = pair(7783, "SAVE-H3", "SAVE-G3")
  local battleWaits = true
  h.holdSession = function() return battleWaits end
  g.holdSession = function() return battleWaits end
  clear(h); clear(g)
  chat(h, "after-a-long-drop")
  local addr = g.address
  g.address = "127.0.0.1:1"          -- the guest cannot get through for now
  dropBoth(g)
  run(CoopNet.RECONNECT_MAX + 15)
  check(h.state == CoopNet.STATE.RECONNECTING and g.state == CoopNet.STATE.RECONNECTING and not g.closed,
        "while the battle waits, both keep the session past RECONNECT_MAX (" .. h.state .. "/" .. g.state .. ")")
  g.address = addr
  run(10)
  check(h:isLinked() and g:isLinked() and lastEvent(g, "net_connect").resumed == true,
        "the partner comes back into the same session")
  check(bodies(g) == "after-a-long-drop", "...with what was sent meanwhile")
  -- the battle gave up (or ended): the usual window applies again
  battleWaits = false
  g.address = "127.0.0.1:1"
  dropBoth(g)
  run(CoopNet.RECONNECT_MAX + 1)
  check(h.state == CoopNet.STATE.LISTENING and g.closed, "without a waiting battle the window closes at RECONNECT_MAX")
end

print(string.format("%d/%d checks passed%s  (co-op session layer)", total - fails, total,
                    fails > 0 and (", " .. fails .. " FAILURES") or ""))
if fails > 0 then os.exit(1) end
