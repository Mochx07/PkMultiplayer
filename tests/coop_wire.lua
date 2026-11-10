-- POSITION SNAPSHOTS IN A FEW BYTES (1.20, src/coop/CoopWire.lua, cap net.binpos).
--
-- coop_pos goes out up to 15 times a second on a channel that loses packets.
-- Each one is a key frame or a difference on a key frame the partner said it
-- has; what comes out on the other side is the table the JSON form gave, and
-- a lost packet never leaves the partner frozen or somewhere it never was.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_wire.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
require("src.coop.CoopLog").enabled = false
local CoopWire = require("src.coop.CoopWire")
local CoopNet = require("src.coop.CoopNet")
local Json = require("src.link.Json")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function pos(n, x, extra)
  local m = { type = "coop_pos", n = n, map = "NEW_BARK_TOWN", cx = x, cy = 7, tx = x + 1, ty = 7,
              px = x * 16 + 0.5, py = 112, hy = 0, facing = "right", moving = true,
              sprite = "SPRITE_CHRIS", inBattle = false, inDialogue = false, busy = false, healthy = 3,
              fol = { s = "SPRITE_MON_155", px = x * 16 - 16, py = 112, f = "right", m = true } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- a key frame first, the same table back
local a, b = CoopWire.newState(), CoopWire.newState()
local first = CoopWire.encodePos(a, pos(1, 4))
T.check(CoopWire.isPacket(first) and first:byte(2) == 1, "the first snapshot is a key frame")
T.check(not CoopWire.isPacket(Json.encode(pos(1, 4))), "JSON never looks like one")
local back = CoopWire.decodePos(b, first)
T.check(same(back, pos(1, 4)), "it decodes to the table that was sent")
T.check(#first < #Json.encode(pos(1, 4)) / 2, "a key frame is under half the JSON (" .. #first .. " vs " .. #Json.encode(pos(1, 4)) .. ")")

-- no word from the partner yet: key frames go on
local second = CoopWire.encodePos(a, pos(2, 5))
T.check(second:byte(2) == 1, "until the partner says it has one, every snapshot is whole")
T.check(same(CoopWire.decodePos(b, second), pos(2, 5)), "...and decodes")

-- the partner's own packet carries what it has; differences start
local reply = CoopWire.encodePos(b, pos(1, 9))
T.check(reply:byte(4) == second:byte(3), "the partner's packet names the newest key frame it received")
CoopWire.decodePos(a, reply)
local third = CoopWire.encodePos(a, pos(3, 6))
T.check(third:byte(2) == 0 and third:byte(3) == second:byte(3), "then a difference on that key frame")
T.check(same(CoopWire.decodePos(b, third), pos(3, 6)), "a difference decodes to the whole table")
T.check(#third <= 24, "a step is a couple dozen bytes at most (" .. #third .. ")")

-- values of every kind survive: fractions, negatives, nil, no follower
local odd = pos(4, -3, { px = -47.25, py = 1 / 3, hy = -10, surf = true, tx = false })
odd.fol, odd.ty = nil, nil
T.check(same(CoopWire.decodePos(b, CoopWire.encodePos(a, odd)), odd), "fractions, negatives and missing fields come back as sent")
local bare = { type = "coop_pos", n = 5, map = "ROUTE_29", cx = 1, cy = 1, fol = {} }
T.check(same(CoopWire.decodePos(b, CoopWire.encodePos(a, bare)), bare), "an empty follower table stays a table")

-- what we cannot say goes as JSON
T.check(CoopWire.encodePos(a, pos(6, 1, { future = 1 })) == nil, "a field from a later version is left to JSON")
T.check(CoopWire.encodePos(a, pos(6, 1, { fol = { s = "X", extra = 1 } })) == nil, "...also inside the follower")
T.check(CoopWire.encodePos(a, { type = "coop_chat_live", n = 1 }) == nil, "only coop_pos is encoded")
T.check(CoopWire.decodePos(b, "\177\0\0") == nil and CoopWire.decodePos(b, first:sub(1, 12)) == nil,
        "a packet cut short is dropped")

-- a receiver that lost its key frames says so and is sent a whole one
a, b = CoopWire.newState(), CoopWire.newState()
CoopWire.decodePos(b, CoopWire.encodePos(a, pos(1, 1)))
CoopWire.decodePos(a, CoopWire.encodePos(b, pos(1, 1)))
local fresh = CoopWire.newState() -- b restarted its side
T.check(CoopWire.decodePos(fresh, CoopWire.encodePos(a, pos(2, 2))) == nil, "a difference on an unknown key frame is dropped")
CoopWire.decodePos(a, CoopWire.encodePos(fresh, pos(2, 1)))
local healed = CoopWire.encodePos(a, pos(3, 3))
T.check(healed:byte(2) == 1 and same(CoopWire.decodePos(fresh, healed), pos(3, 3)), "the next snapshot is whole again")

-- a walk across maps over a link that loses a third of its packets, each way
do
  local seed = 7
  local function lost() seed = (seed * 1103515245 + 12345) % 2147483648 return seed % 3 == 0 end
  local sa, sb = CoopWire.newState(), CoopWire.newState()
  local wrong, arrived, lastN, bytes, json = 0, 0, 0, 0, 0
  for n = 1, 600 do
    local m = pos(n, n % 40, { map = (n > 300) and "ROUTE_29" or "NEW_BARK_TOWN",
                               moving = n % 7 ~= 0, facing = (n % 50 < 25) and "right" or "up" })
    if n > 450 then m.fol = nil end
    local text = CoopWire.encodePos(sa, m)
    bytes, json = bytes + #text, json + #Json.encode(m)
    if not lost() then
      local got = CoopWire.decodePos(sb, text)
      if got then
        arrived = arrived + 1
        lastN = got.n
        if not same(got, m) then wrong = wrong + 1 end
      end
    end
    -- the partner's snapshots come back at a third of the rate
    if n % 3 == 0 then
      local r = CoopWire.encodePos(sb, pos(n, 2))
      if not lost() then CoopWire.decodePos(sa, r) end
    end
  end
  T.check(wrong == 0, "over a lossy link every snapshot that arrives is the one that was sent")
  T.check(arrived >= 330, "what the link delivers is used: " .. arrived .. " of 600 sent")
  T.check(lastN >= 598, "the walk is followed to its end (#" .. lastN .. ")")
  T.check(bytes * 5 < json, ("it weighs under a fifth of the JSON: %d vs %d bytes"):format(bytes, json))
  T.check(sa.stats.keys < 60, "key frames are the exception (" .. sa.stats.keys .. " of 600)")
end

-- the key frame number wraps without confusing anybody
do
  local sa, sb = CoopWire.newState(), CoopWire.newState()
  local wrong = 0
  for n = 1, 900 do
    local m = pos(n, n % 9, { map = "MAP_" .. n }) -- a new key frame every time
    local got = CoopWire.decodePos(sb, CoopWire.encodePos(sa, m))
    if not same(got, m) then wrong = wrong + 1 end
    CoopWire.decodePos(sa, CoopWire.encodePos(sb, pos(n, 1)))
  end
  T.check(wrong == 0 and sa.stats.keys > 255, "more than 255 key frames in one link, all read right")
end

-- through the transport: short form only when asked, JSON otherwise, both read
do
  local function link()
    local x, y = CoopNet.new(), CoopNet.new()
    for _, n in ipairs({ x, y }) do
      n.closed, n.paired, n.resumed, n.state = false, true, true, CoopNet.STATE.SYNCED
    end
    x.peer = { send = function(_, text) y:onReceive(y.peer, text, 0) end }
    y.peer = { send = function(_, text) x:onReceive(x.peer, text, 0) end }
    return x, y
  end
  local x, y = link()
  x:send(pos(1, 3), { fast = true, bin = true })
  T.check(#y.inbox == 1 and same(y.inbox[1], pos(1, 3)), "CoopNet: a short snapshot reaches the partner's inbox as coop_pos")
  local shortBytes = x.stats.fastBytes
  x:send(pos(2, 4), { fast = true })
  T.check(#y.inbox == 2 and same(y.inbox[2], pos(2, 4)), "CoopNet: without the cap it goes as JSON, as before")
  T.check(x.stats.fastBytes - shortBytes > shortBytes * 2, "CoopNet: the JSON one is the heavy one")
  x:send({ type = "coop_chat_live", n = 1, text = "hi" }, { fast = true, bin = true })
  T.check(#y.inbox == 3 and y.inbox[3].type == "coop_chat_live", "CoopNet: other fast messages are untouched")
  x:send(pos(3, 4, { future = true }), { fast = true, bin = true })
  T.check(#y.inbox == 4 and y.inbox[4].future == true, "CoopNet: a snapshot the short form cannot hold falls back to JSON")
  -- a stranger's packet is not read
  local before = #y.inbox
  y:onReceive({}, CoopWire.encodePos(CoopWire.newState(), pos(9, 9)), 0)
  T.check(#y.inbox == before, "CoopNet: a short packet from anyone but the partner is ignored")
  -- a new connection starts from nothing
  y:send(pos(1, 1), { fast = true, bin = true })
  x:send(pos(4, 5), { fast = true, bin = true })
  local old = x.wire
  x:onPeerConnected(x.peer, 0)
  T.check(x.wire ~= old and x.wire.partnerAck == 0, "CoopNet: a new connection forgets the old key frames")
end

T.finish("co-op position snapshots in a few bytes")
