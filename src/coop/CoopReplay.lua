-- src/coop/CoopReplay.lua
-- REPLAYS of P1-vs-P2 battles (1.20).
--
-- A link battle is lockstep: given both parties, the shared seed and each
-- side's choices in order, the engine plays the same battle again, move for
-- move.  The co-op tunnel (CoopLink) already carries every message the
-- Cable Club sends and receives, so recording is noting them down as they
-- pass; and the engine has its own way of playing a battle from someone
-- else's traffic -- LinkBattle.newSpectator, the tournament spectator --
-- so watching is handing it the notes, one message at a time, whenever it
-- waits for the next turn.
--
-- Nothing extra goes over the link and nothing is asked of the partner:
-- each copy records its own replay.  A replay is a small JSON file in
-- modstorage/PkMultiplayer/replays/ (the newest MAX are kept).
local CoopReplay = {}

CoopReplay.DIR = "modstorage/PkMultiplayer/replays"
CoopReplay.MAX = 20
CoopReplay.VERSION = 1

local function json() return require("src.link.Json") end

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

-- ---------------------------------------------------------------------
-- recording (on CoopLink's tunnel)
-- ---------------------------------------------------------------------

-- info: { asker = bool (the Cable Club's host), myName, theirName, format }
function CoopReplay.start(tunnel, info)
  if not tunnel then return nil end
  tunnel.rec = { asker = info.asker and true or false, myName = info.myName, theirName = info.theirName,
                 format = info.format, log = {} }
  return tunnel.rec
end

-- every message through the tunnel: dir "out" (ours) or "in" (theirs)
function CoopReplay.note(tunnel, dir, msg)
  local r = tunnel and tunnel.rec
  if not r or type(msg) ~= "table" then return end
  local mine = dir == "out"
  if msg.type == "party" then
    if mine then r.myParty = copy(msg.mons) else r.theirParty = copy(msg.mons) end
    if msg.seed then r.seed = msg.seed end
    if msg.forceLevel then r.forceLevel = msg.forceLevel end
  elseif msg.type == "action" or msg.type == "forfeit" or msg.type == "bye" then
    r.log[#r.log + 1] = { me = mine, m = copy(msg) }
  end
end

-- the recording as a replay (host/guest as the Cable Club had them), or nil
-- when there is no battle in it (a trade, a battle that never started)
function CoopReplay.build(rec, when)
  if not (rec and rec.myParty and rec.theirParty and rec.seed) then return nil end
  local actions = 0
  for _, e in ipairs(rec.log) do if e.m.type == "action" then actions = actions + 1 end end
  if actions == 0 then return nil end
  local host = rec.asker
  local log = {}
  for _, e in ipairs(rec.log) do
    log[#log + 1] = { side = (e.me == host) and "host" or "guest", msg = e.m }
  end
  return {
    v = CoopReplay.VERSION,
    date = when or os.date("%Y-%m-%d %H:%M"),
    format = rec.format,
    me = host and "host" or "guest",
    hostName = host and rec.myName or rec.theirName,
    guestName = host and rec.theirName or rec.myName,
    hostParty = host and rec.myParty or rec.theirParty,
    guestParty = host and rec.theirParty or rec.myParty,
    seed = rec.seed,
    forceLevel = rec.forceLevel,
    sleepClause = rec.sleepClause or nil,
    log = log,
  }
end

-- ---------------------------------------------------------------------
-- files
-- ---------------------------------------------------------------------

local function fs() return love and love.filesystem end

-- the menu asks every frame: the list and the files read are kept until a
-- replay is written or removed (a replay file never changes)
local listCache, loaded = nil, {}
function CoopReplay.forget() listCache, loaded = nil, {} end

function CoopReplay.save(replay)
  local f = fs()
  if not (f and replay) then return nil end
  local ok, name = pcall(function()
    f.createDirectory(CoopReplay.DIR)
    local base = os.date("%Y%m%d-%H%M%S")
    local name = base .. ".json"
    local n = 1
    while f.getInfo(CoopReplay.DIR .. "/" .. name) do
      n = n + 1
      name = base .. "-" .. n .. ".json"
    end
    f.write(CoopReplay.DIR .. "/" .. name, json().encode(replay))
    return name
  end)
  CoopReplay.forget()
  if not ok then return nil end
  CoopReplay.prune()
  return name
end

-- file names, newest first
function CoopReplay.list()
  if listCache then return listCache end
  local f = fs()
  if not f then return {} end
  local ok, items = pcall(f.getDirectoryItems, CoopReplay.DIR)
  if not ok or type(items) ~= "table" then return {} end
  local out = {}
  for _, n in ipairs(items) do if n:match("%.json$") then out[#out + 1] = n end end
  table.sort(out, function(a, b) return a > b end)
  listCache = out
  return out
end

function CoopReplay.prune()
  local f = fs()
  local names = CoopReplay.list()
  if #names <= CoopReplay.MAX then return end
  for i = CoopReplay.MAX + 1, #names do pcall(f.remove, CoopReplay.DIR .. "/" .. names[i]) end
  CoopReplay.forget()
end

function CoopReplay.load(name)
  if loaded[name] ~= nil then return loaded[name] or nil end
  local r = CoopReplay.read(name)
  loaded[name] = r or false
  return r
end

function CoopReplay.read(name)
  local f = fs()
  if not (f and type(name) == "string" and not name:find("[/\\]")) then return nil end
  local ok, text = pcall(f.read, CoopReplay.DIR .. "/" .. name)
  if not ok or type(text) ~= "string" then return nil end
  local ok2, r = pcall(json().decode, text)
  if not ok2 or type(r) ~= "table" or r.v ~= CoopReplay.VERSION or type(r.log) ~= "table"
     or type(r.hostParty) ~= "table" or type(r.guestParty) ~= "table" then
    return nil
  end
  return r
end

-- the tunnel closed: keep what it saw, if it was a battle
function CoopReplay.finish(tunnel)
  local rec = tunnel and tunnel.rec
  if not rec then return nil end
  tunnel.rec = nil
  local replay = CoopReplay.build(rec)
  if replay then return CoopReplay.save(replay) end
  return nil
end

-- ---------------------------------------------------------------------
-- watching
-- ---------------------------------------------------------------------

-- The spectator's "net": it hands over the next recorded message only while
-- the battle waits for a turn (one side's action is kept until the other's
-- arrives, so two of one side in a row would overwrite each other), and
-- closes when they run out -- the spectator then ends the match.
local Feed = {}
Feed.__index = Feed

function CoopReplay.newFeed(replay)
  local q = {}
  for _, e in ipairs(replay.log or {}) do
    q[#q + 1] = { type = "spectate", side = e.side, msg = e.msg }
  end
  -- a battle played under the sleep clause is watched under it too (the
  -- spectator is armed by its net, lib/Hooks.lua)
  return setmetatable({ queue = q, pos = 1, inbox = {}, closed = false, paired = true,
                        sleepClause = replay.sleepClause == true }, Feed)
end

function Feed:idle()
  local b = self.battle
  return b and (b.phase == "waitBoth" or b.phase == "menu") or false
end

function Feed:update()
  if self.closed or not self:idle() then return end
  local nextMsg = self.queue[self.pos]
  if nextMsg then
    self.inbox[#self.inbox + 1] = nextMsg
    self.pos = self.pos + 1
  else
    self.closed = true
  end
end

function Feed:poll()
  local q = self.inbox
  self.inbox = {}
  return q
end

function Feed:send() end
function Feed:close() self.closed = true end

-- a replay -> the battle that plays it (not pushed), or nil, why
function CoopReplay.newBattle(game, replay)
  local LinkBattle = require("src.link.LinkBattle")
  local Handshake = require("src.link.Handshake")
  local feed = CoopReplay.newFeed(replay)
  local battle, why = LinkBattle.newSpectator(game, feed, {
    hostParty = replay.hostParty, guestParty = replay.guestParty,
    hostName = replay.hostName, guestName = replay.guestName,
    seed = replay.seed, verdict = "full", strict = Handshake.strict("full"),
    forceLevel = replay.forceLevel,
  })
  if not battle then return nil, why end
  feed.battle = battle
  battle.coopReplay = true
  return battle
end

function CoopReplay.play(game, name)
  local replay = CoopReplay.load(name)
  if not replay then return false, "Replay can't be read" end
  local battle, why = CoopReplay.newBattle(game, replay)
  if not battle then return false, why or "Replay can't be played" end
  game.stack:push(battle)
  return true
end

-- how a replay reads in the list: "VS TOBY 11-02", and its box
function CoopReplay.describe(replay, name)
  local other = replay.me == "host" and replay.guestName or replay.hostName
  local I18n = require("src.coop.CoopI18n")
  local day = (replay.date or ""):match("%d+%-(%d+%-%d+)") or ""
  local label = "VS " .. I18n.truncate(tostring(other or "?"):upper(), 7) .. " " .. day
  local fmt = replay.format and require("src.coop.CoopVS").format(replay.format)
  return label, { fmt and fmt.name or "FREE BATTLE", (replay.date or name or ""):sub(1, 18), "A: WATCH" }
end

return CoopReplay
