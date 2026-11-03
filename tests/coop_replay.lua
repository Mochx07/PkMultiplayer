-- REPLAYS (1.20, src/coop/CoopReplay.lua): what the tunnel notes down, the
-- replay built from it on either side, the files kept, and the feed that
-- hands the engine's spectator one recorded message at a time.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
local CoopLink = require("src.coop.CoopLink")
local CoopReplay = require("src.coop.CoopReplay")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end, flush = function() end }

-- --------------------------------------------- a battle through a tunnel
local function battleThrough(asker)
  local t = CoopLink.newTunnel(asker and "L-ask" or "L-asked")
  CoopReplay.start(t, { asker = asker, myName = "MOCHI", theirName = "TOBY", format = "lv50" })
  local myParty, theirParty = { { species = "SNORLAX", level = 40 } }, { { species = "PIDGEY", level = 10 } }
  t:send({ type = "hello", name = "MOCHI" })
  t:send({ type = "party", mons = myParty, seed = asker and 4242 or nil, forceLevel = asker and 50 or nil })
  table.insert(t.inbox, { type = "party", mons = theirParty, seed = (not asker) and 4242 or nil,
                          forceLevel = (not asker) and 50 or nil })
  t:poll()
  t:send({ type = "action", kind = "move", slot = 1 })
  table.insert(t.inbox, { type = "action", kind = "move", slot = 2 })
  table.insert(t.inbox, { type = "hash", turn = 1, value = "x" })
  t:poll()
  t:send({ type = "action", kind = "switch", index = 2 })
  table.insert(t.inbox, { type = "action", kind = "run" })
  t:poll()
  myParty[1].level = 99 -- the party changing later does not change the record
  return t
end

local t = battleThrough(true)
local r = CoopReplay.build(t.rec, "2026-11-02 21:30")
T.check(r and r.v == 1 and r.date == "2026-11-02 21:30" and r.format == "lv50", "a battle builds a replay")
T.check(r.me == "host" and r.hostName == "MOCHI" and r.guestName == "TOBY", "the asker is the host")
T.check(r.hostParty[1].species == "SNORLAX" and r.guestParty[1].species == "PIDGEY", "both parties, on their sides")
T.check(r.hostParty[1].level == 40, "the parties are copies, taken when they were sent")
T.check(r.seed == 4242 and r.forceLevel == 50, "the host's seed and level rule")
T.check(#r.log == 4, "the actions only (hello, party and hash left out): " .. #r.log)
T.check(r.log[1].side == "host" and r.log[1].msg.slot == 1 and r.log[2].side == "guest" and r.log[2].msg.slot == 2,
        "each action is tagged with its side, in order")

local t2 = battleThrough(false)
local r2 = CoopReplay.build(t2.rec, "2026-11-02 21:31")
T.check(r2.me == "guest" and r2.hostName == "TOBY" and r2.guestName == "MOCHI", "on the asked copy the partner is the host")
T.check(r2.hostParty[1].species == "PIDGEY" and r2.guestParty[1].species == "SNORLAX" and r2.seed == 4242,
        "...with the partner's party and seed on the host side")
T.check(r2.log[1].side == "guest" and r2.log[2].side == "host", "...and our actions on the guest side")

-- no battle, no replay
local t3 = CoopLink.newTunnel("L-trade")
CoopReplay.start(t3, { asker = true, myName = "A", theirName = "B" })
t3:send({ type = "party", mons = {}, seed = 1 })
T.check(CoopReplay.build(t3.rec) == nil, "a Cable Club visit with no action leaves no replay")
local t4 = CoopLink.newTunnel("L-none")
t4:send({ type = "action", kind = "move", slot = 1 })
T.check(t4.rec == nil, "a tunnel nobody records (a trade) notes nothing")
t4:close()

-- ------------------------------------------------------------- files
CoopReplay.forget()
for _, n in ipairs(CoopReplay.list()) do love.filesystem.remove(CoopReplay.DIR .. "/" .. n) end
CoopReplay.forget()
local before = #CoopReplay.list()
t:close()
local names = CoopReplay.list()
T.check(#names == before + 1, "closing the tunnel writes the replay")
local back = CoopReplay.load(names[1])
T.check(back and back.hostName == "MOCHI" and #back.log == 4 and back.seed == 4242, "...and it reads back the same")
T.check(t.rec == nil, "the recording is dropped once written")
local label, info = CoopReplay.describe(back, names[1])
T.check(label:match("^VS TOBY %d%d%-%d%d$") and info[1] == "LEVEL 50" and info[3] == "A: WATCH",
        "the list says who it was against, the day and the rules: " .. label)
T.check(#label <= 16, "the label fits a menu row")
T.check(CoopReplay.load("../../secrets.json") == nil and CoopReplay.load("nope.json") == nil,
        "a name with a path, or a missing file, reads as nothing")
love.filesystem.write(CoopReplay.DIR .. "/bad.json", "{not json")
CoopReplay.forget()
T.check(CoopReplay.load("bad.json") == nil, "a broken file reads as nothing")
love.filesystem.remove(CoopReplay.DIR .. "/bad.json")
CoopReplay.forget()

-- the newest MAX are kept
local max = CoopReplay.MAX
CoopReplay.MAX = 3
for i = 1, 5 do
  love.filesystem.write(("%s/2020010%d-000000.json"):format(CoopReplay.DIR, i), "{}")
end
CoopReplay.forget()
CoopReplay.prune()
local kept = CoopReplay.list()
T.check(#kept == 3 and kept[1] == names[1], "older replays are removed past the limit, the newest stay")
CoopReplay.MAX = max

-- ------------------------------------------------------------- the feed
local feed = CoopReplay.newFeed(back)
local battle = { phase = "messages" }
feed.battle = battle
feed:update()
T.check(#feed:poll() == 0, "nothing is handed over while the battle is busy")
battle.phase = "waitBoth"
feed:update()
local got = feed:poll()
T.check(#got == 1 and got[1].type == "spectate" and got[1].side == "host" and got[1].msg.slot == 1,
        "while it waits for a turn, the next message, as the spectator reads it")
feed:update(); feed:update(); feed:update()
local rest = feed:poll()
T.check(#rest == 3 and rest[1].side == "guest", "one message per update, in order")
T.check(not feed.closed, "still open after the last message...")
feed:update()
T.check(feed.closed, "...and closed on the next idle update: the spectator ends the match")

T.finish("co-op replays")
