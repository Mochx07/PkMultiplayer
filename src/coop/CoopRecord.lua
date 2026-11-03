-- src/coop/CoopRecord.lua
-- THE VS RECORD (1.20): wins, losses and a local ELO against each partner,
-- per VS format, written when a P1-vs-P2 match ends (src/coop/CoopMatch.lua).
--
-- Where it lives: modstorage/PkMultiplayer/vs_record.json, not the save.
--   * Both copies must agree on the record.  A match result is written to
--     modstorage the moment the match ends, on both copies; in the save it
--     would only last if each player saved afterwards, and one who did not
--     would come back with a record the partner's copy no longer matches.
--   * The replays of the same matches already live in modstorage.
--   * The save stays the engine's (and a 1.6 copy's) format: nothing new in it.
-- The file is keyed by OUR save's coop id first (two saves on one game are
-- two trainers), then by the partner's coop id (their name is kept too, for
-- the menu; a partner renaming themselves is still the same partner).
--
-- ELO: both start at 1000, K = 32, whole numbers.  Each copy keeps both
-- ratings of the pair and computes the change the same way: from the side
-- with the smaller coop id, rounded once, added to one side and taken from
-- the other -- so the two copies hold mirrored numbers, never ones a
-- rounding or a float last bit apart.
local CoopRecord = {}

CoopRecord.FILE = "modstorage/PkMultiplayer/vs_record.json"
CoopRecord.VERSION = 1
CoopRecord.START = 1000
CoopRecord.K = 32

local function json() return require("src.link.Json") end
local function fs() return love and love.filesystem end

local cache = nil
function CoopRecord.forget() cache = nil end

local function empty() return { v = CoopRecord.VERSION, saves = {} } end

function CoopRecord.load()
  if cache then return cache end
  local f = fs()
  local t
  if f then
    local ok, text = pcall(f.read, CoopRecord.FILE)
    if ok and type(text) == "string" then
      local ok2, r = pcall(json().decode, text)
      if ok2 and type(r) == "table" and r.v == CoopRecord.VERSION and type(r.saves) == "table" then t = r end
    end
  end
  cache = t or empty()
  return cache
end

function CoopRecord.store(t)
  local f = fs()
  if not (f and t) then return false end
  local ok = pcall(function()
    f.createDirectory(CoopRecord.FILE:match("^(.*)/[^/]+$"))
    f.write(CoopRecord.FILE, json().encode(t))
  end)
  cache = t
  return ok
end

-- (ra, rb, a won?) -> the two new ratings
function CoopRecord.elo(ra, rb, aWon)
  local expect = 1 / (1 + 10 ^ ((rb - ra) / 400))
  local d = math.floor(CoopRecord.K * ((aWon and 1 or 0) - expect) + 0.5)
  return ra + d, rb - d
end

local function blank()
  return { w = 0, l = 0, gw = 0, gl = 0, elo = CoopRecord.START, theirElo = CoopRecord.START }
end

-- our record against `partnerId` (nil when there is none yet)
function CoopRecord.against(myId, partnerId)
  if type(myId) ~= "string" or type(partnerId) ~= "string" then return nil end
  local mine = CoopRecord.load().saves[myId]
  return mine and mine[partnerId] or nil
end

-- a finished match:
--   { myId, partnerId, partnerName, format, won = bool, gamesWon, gamesLost }
-- -> the format's record after it, or nil when it can not be kept (no ids,
-- or the two ids are the same save)
function CoopRecord.add(r)
  if type(r) ~= "table" or type(r.myId) ~= "string" or type(r.partnerId) ~= "string"
     or r.myId == r.partnerId then
    return nil
  end
  local t = CoopRecord.load()
  t.saves[r.myId] = t.saves[r.myId] or {}
  local e = t.saves[r.myId][r.partnerId] or { formats = {} }
  t.saves[r.myId][r.partnerId] = e
  if type(r.partnerName) == "string" and r.partnerName ~= "" then e.name = r.partnerName end
  e.formats = type(e.formats) == "table" and e.formats or {}
  local fmt = type(r.format) == "string" and r.format or "free"
  local f = e.formats[fmt] or blank()
  e.formats[fmt] = f
  if r.won then f.w = f.w + 1 else f.l = f.l + 1 end
  f.gw = f.gw + (tonumber(r.gamesWon) or 0)
  f.gl = f.gl + (tonumber(r.gamesLost) or 0)
  -- the change is worked out from the smaller id's side on both copies
  if r.myId < r.partnerId then
    f.elo, f.theirElo = CoopRecord.elo(f.elo, f.theirElo, r.won)
  else
    f.theirElo, f.elo = CoopRecord.elo(f.theirElo, f.elo, not r.won)
  end
  CoopRecord.store(t)
  return f
end

-- the record as the VS menu lists it: one row per format played, in the
-- order of CoopVS.FORMATS -> { { format = fmt, rec = f }, ... }
function CoopRecord.rows(myId, partnerId)
  local e = CoopRecord.against(myId, partnerId)
  local out = {}
  if not (e and type(e.formats) == "table") then return out end
  for _, fmt in ipairs(require("src.coop.CoopVS").FORMATS) do
    local f = e.formats[fmt.id]
    if type(f) == "table" then out[#out + 1] = { format = fmt, rec = f } end
  end
  return out
end

-- a format's box in the menu: three lines of at most 18 letters
function CoopRecord.describe(f)
  return {
    string.format("WON %d  LOST %d", f.w or 0, f.l or 0),
    string.format("GAMES %d-%d", f.gw or 0, f.gl or 0),
    string.format("ELO %d VS %d", f.elo or CoopRecord.START, f.theirElo or CoopRecord.START),
  }
end

return CoopRecord
