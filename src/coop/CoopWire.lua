-- src/coop/CoopWire.lua
-- The overworld position snapshot (coop_pos) in a few bytes (1.20, cap
-- "net.binpos").  It goes out up to 15 times a second on the unreliable
-- channel, and as JSON each one was ~250 bytes saying mostly what the last
-- one said.  Here a snapshot is either
--
--   a key frame   every field, tagged values;               ~45 bytes
--   a difference  only the fields that changed since a key
--                 frame THE PARTNER SAID IT HAS;            ~15 bytes walking
--
-- The channel loses packets, so a difference never builds on the packet
-- before it: it names its key frame, and every packet carries the newest
-- key frame its sender has received.  A sender that has seen no such word
-- for a key frame it still remembers sends key frames; a receiver handed a
-- difference on a key frame it does not have drops it and says so (ack 0),
-- and the next packet it gets is whole again.  Nothing here can stall.
--
-- A packet starts with MAGIC, which no JSON text does, so both forms share
-- the channel and a copy without the cap keeps getting JSON.
--
-- A snapshot with a field this file does not know is not encoded (nil): the
-- caller sends it as JSON, as before.

local CoopWire = {}

CoopWire.CAP = "net.binpos"
CoopWire.MAGIC = 0xB1
CoopWire.KEEP = 8          -- key frames remembered on each side
CoopWire.REKEY = 9         -- a difference this wide becomes the new key frame
CoopWire.RETRY = 6         -- differences before an unconfirmed key frame is offered again

-- wire order; never reorder or remove, only append (the cap covers this list)
local FIELDS = { "map", "cx", "cy", "tx", "ty", "px", "py", "hy", "facing", "moving",
                 "sprite", "inBattle", "inDialogue", "busy", "healthy", "surf",
                 "fol", "fol.s", "fol.px", "fol.py", "fol.f", "fol.m", "fol.sh" }
local INDEX = {}
for i, name in ipairs(FIELDS) do INDEX[name] = i end
local FOL = { s = "fol.s", px = "fol.px", py = "fol.py", f = "fol.f", m = "fol.m", sh = "fol.sh" }
-- a change in one of these is worth a new key frame (they are long)
local LONG = { map = true, sprite = true, ["fol.s"] = true }

local char, byte, floor = string.char, string.byte, math.floor

-- ------------------------------------------------------------- numbers

local function putVarint(out, n)
  while n >= 128 do
    out[#out + 1] = char(n % 128 + 128)
    n = floor(n / 128)
  end
  out[#out + 1] = char(n)
end

local function getVarint(data, pos)
  local n, mul = 0, 1
  for _ = 1, 8 do
    local b = byte(data, pos)
    if not b then return nil end
    pos = pos + 1
    n = n + (b % 128) * mul
    if b < 128 then return n, pos end
    mul = mul * 128
  end
  return nil
end

local function zig(n) return n >= 0 and n * 2 or -n * 2 - 1 end
local function zag(n) return n % 2 == 0 and n / 2 or -(n + 1) / 2 end

local LIMIT = 2 ^ 40

-- ------------------------------------------------------------- values
-- tag: 0 nil, 1 false, 2 true, 3 integer, 4 number in 1/256ths,
--      5 string, 6 any other number (as text)

local function putValue(out, v)
  local t = type(v)
  if v == nil then out[#out + 1] = "\0"
  elseif v == false then out[#out + 1] = "\1"
  elseif v == true then out[#out + 1] = "\2"
  elseif t == "number" then
    if v == floor(v) and v > -LIMIT and v < LIMIT then
      out[#out + 1] = "\3"
      putVarint(out, zig(v))
    elseif v * 256 == floor(v * 256) and v > -LIMIT / 256 and v < LIMIT / 256 then
      out[#out + 1] = "\4"
      putVarint(out, zig(v * 256))
    elseif v ~= v or v == math.huge or v == -math.huge then
      return false
    else
      local text = ("%.17g"):format(v)
      out[#out + 1] = "\6"
      putVarint(out, #text)
      out[#out + 1] = text
    end
  elseif t == "string" then
    if #v > 255 then return false end
    out[#out + 1] = "\5"
    putVarint(out, #v)
    out[#out + 1] = v
  else
    return false
  end
  return true
end

local function getValue(data, pos)
  local tag = byte(data, pos)
  if not tag then return nil, nil end
  pos = pos + 1
  if tag == 0 then return nil, pos
  elseif tag == 1 then return false, pos
  elseif tag == 2 then return true, pos
  elseif tag == 3 or tag == 4 then
    local n, at = getVarint(data, pos)
    if not n then return nil, nil end
    n = zag(n)
    return tag == 4 and n / 256 or n, at
  elseif tag == 5 or tag == 6 then
    local len, at = getVarint(data, pos)
    if not len or at + len - 1 > #data then return nil, nil end
    local text = data:sub(at, at + len - 1)
    if tag == 6 then
      text = tonumber(text)
      if not text then return nil, nil end
    end
    return text, at + len
  end
  return nil, nil
end

-- ------------------------------------------------------------- snapshot

-- msg -> { [field index] = value }, or nil when it holds what we cannot say
local function flatten(msg)
  local flat = {}
  for k, v in pairs(msg) do
    if k == "fol" then
      if type(v) ~= "table" then return nil end
      flat[INDEX.fol] = true
      for fk, fv in pairs(v) do
        local name = FOL[fk]
        if not name or type(fv) == "table" then return nil end
        flat[INDEX[name]] = fv
      end
    elseif k ~= "type" and k ~= "n" then
      local i = INDEX[k]
      if not i or k:sub(1, 4) == "fol." or type(v) == "table" then return nil end
      flat[i] = v
    end
  end
  return flat
end

local function unflatten(flat, n)
  local msg = { type = "coop_pos", n = n }
  local fol
  for i, name in ipairs(FIELDS) do
    local v = flat[i]
    if v ~= nil then
      if name == "fol" then fol = fol or {}
      elseif name:sub(1, 4) == "fol." then
        fol = fol or {}
        fol[name:sub(5)] = v
      else
        msg[name] = v
      end
    end
  end
  if flat[INDEX.fol] then msg.fol = fol or {} end
  return msg
end

-- ------------------------------------------------------------- state

-- one per link, each way: forget it when the link is new
function CoopWire.newState()
  return {
    nextKey = 1,
    sinceKey = 0,     -- differences sent since our last key frame
    sent = {},        -- key frames we sent: { id, flat }, oldest first
    got = {},         -- key frames we received, oldest first
    ack = 0,          -- the newest key frame we received (0: none, or lost track)
    partnerAck = 0,   -- the newest key frame the partner says it has
    stats = { keys = 0, diffs = 0, bytes = 0, dropped = 0 },
  }
end

local function find(list, id)
  for i = #list, 1, -1 do
    if list[i].id == id then return list[i] end
  end
end

local function remember(list, id, flat)
  list[#list + 1] = { id = id, flat = flat }
  while #list > CoopWire.KEEP do table.remove(list, 1) end
end

local function header(out, flags, key, ack)
  out[1] = char(CoopWire.MAGIC, flags, key, ack)
end

-- A coop_pos table -> packet text, or nil (send it as JSON).
function CoopWire.encodePos(state, msg)
  if type(msg) ~= "table" or msg.type ~= "coop_pos" then return nil end
  local n = tonumber(msg.n) or 0
  if n < 0 or n ~= floor(n) or n >= LIMIT then return nil end
  local flat = flatten(msg)
  if not flat then return nil end

  local out = {}
  local base = state.partnerAck > 0 and find(state.sent, state.partnerAck) or nil
  if base then
    local mask, count, long = 0, 0, false
    for i = 1, #FIELDS do
      if flat[i] ~= base.flat[i] then
        mask = mask + 2 ^ (i - 1)
        count = count + 1
        long = long or LONG[FIELDS[i]] == true
      end
    end
    -- a wide difference: offer a new key frame instead.  The partner must
    -- say it has it before we build on it, so until then the differences go
    -- on from the old one; a key frame that got lost is offered again.
    local newest = state.sent[#state.sent]
    if (long or count >= CoopWire.REKEY)
       and (newest.id == base.id or state.sinceKey >= CoopWire.RETRY) then
      base = nil
    end
    if base then
      header(out, 0, base.id, state.ack)
      putVarint(out, n)
      putVarint(out, mask)
      for i = 1, #FIELDS do
        if flat[i] ~= base.flat[i] and not putValue(out, flat[i]) then return nil end
      end
      local text = table.concat(out)
      state.sinceKey = state.sinceKey + 1
      state.stats.diffs = state.stats.diffs + 1
      state.stats.bytes = state.stats.bytes + #text
      return text
    end
  end

  local id = state.nextKey
  header(out, 1, id, state.ack)
  putVarint(out, n)
  for i = 1, #FIELDS do
    if not putValue(out, flat[i]) then return nil end
  end
  state.nextKey = id % 255 + 1
  remember(state.sent, id, flat)
  state.sinceKey = 0
  local text = table.concat(out)
  state.stats.keys = state.stats.keys + 1
  state.stats.bytes = state.stats.bytes + #text
  return text
end

function CoopWire.isPacket(data)
  return type(data) == "string" and byte(data, 1) == CoopWire.MAGIC
end

-- Packet text -> a coop_pos table like the JSON one, or nil (dropped: not
-- ours, cut short, or a difference on a key frame we do not have).
function CoopWire.decodePos(state, data)
  if not CoopWire.isPacket(data) or #data < 5 then return nil end
  local flags, key, ack = byte(data, 2, 4)
  if flags > 1 or key == 0 then return nil end
  local n, pos = getVarint(data, 5)
  if not n then return nil end

  local flat = {}
  if flags == 1 then
    for i = 1, #FIELDS do
      local v, at = getValue(data, pos)
      if not at then return nil end
      flat[i], pos = v, at
    end
    if pos ~= #data + 1 then return nil end
    if not find(state.got, key) then remember(state.got, key, flat) end
    state.ack = key
  else
    local base = find(state.got, key)
    if not base then
      state.ack = 0 -- tell the sender we lost track: it answers with a key frame
      state.stats.dropped = state.stats.dropped + 1
      state.partnerAck = ack
      return nil
    end
    local mask, at = getVarint(data, pos)
    if not mask or mask >= 2 ^ #FIELDS then return nil end
    pos = at
    for i = 1, #FIELDS do
      local bit = mask % 2
      mask = (mask - bit) / 2
      if bit == 1 then
        local v, nextPos = getValue(data, pos)
        if not nextPos then return nil end
        flat[i], pos = v, nextPos
      else
        flat[i] = base.flat[i]
      end
    end
    if pos ~= #data + 1 then return nil end
  end
  state.partnerAck = ack
  return unflatten(flat, n)
end

return CoopWire
