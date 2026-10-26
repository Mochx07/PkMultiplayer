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
local old = newHost(nil)
local busy = old:connect("127.0.0.1:7777")
run(0.1)
local refused = false
for _, e in ipairs(old.events) do if e.type == "disconnect" and e.data == 3 then refused = true end end
check(refused and host.peer and guest2:isLinked(), "a third machine is told the host is busy")
old.events = {}
local _ = busy
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

print(string.format("%d/%d checks passed%s  (co-op session layer)", total - fails, total,
                    fails > 0 and (", " .. fails .. " FAILURES") or ""))
if fails > 0 then os.exit(1) end
