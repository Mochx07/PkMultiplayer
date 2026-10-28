-- EACH GAME'S coop.log REACHES THE PARTNER ON ITS OWN (src/coop/CoopLogShare.lua).
--
-- Every co-op bug so far needed both logs, and the partner's had to be found
-- and sent by hand.  Lines go over the link in batches, the network traffic
-- stays home, lines written during a drop wait for the link, and the
-- receiver appends them to coop-partner.log.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_logshare.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")
local CoopLogShare = require("src.coop.CoopLogShare")

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end, closed = false,
                    flush = function() end, isLinked = function() return true end }
local function line(level, tag, msg)
  CoopLog.onLine({ level = level, tag = tag, message = msg },
                 string.format("[t] [%s] [%s] %s\n", level, tag, msg))
end

CoopLogShare.pending, CoopLogShare.dropped = {}, 0
line("INFO", "BATTLE:TURN", "resolve turn 1")
line("NET", "NET", "-> SEND coop_battle_action")
line("WARN", "BATTLE", "the copies differ")
T.check(#CoopLogShare.pending == 2, "the network traffic stays home, the rest is kept for the partner")

-- not linked: nothing goes, nothing is lost
CoopManager.connected = false
T.check(CoopLogShare.flush() == false and #CoopLogShare.pending == 2, "while the link is down the lines wait")

CoopManager.connected = true
sent = {}
T.check(CoopLogShare.flush() == true, "linked, the waiting lines go")
local msg = sent[1]
T.check(msg and msg.type == "coop_log" and #msg.lines == 2 and msg.lines[2]:find("copies differ"),
        "...as one coop_log batch, in order, without the trailing newline")
T.check(#CoopLogShare.pending == 0, "...and are not sent twice")

-- a long drop: only the newest lines are kept, and the partner is told
CoopLogShare.pending, CoopLogShare.dropped = {}, 0
for i = 1, CoopLogShare.MAX_PENDING + 25 do line("INFO", "BATTLE:TURN", "resolve turn " .. i) end
T.check(#CoopLogShare.pending == CoopLogShare.MAX_PENDING and CoopLogShare.dropped == 25,
        "a long drop keeps the newest lines and counts the rest")
sent = {}
CoopLogShare.flush()
T.check(#sent[1].lines == CoopLogShare.MAX_BATCH and sent[1].dropped == 25, "batches are capped; the count rides along")

-- switched off in the MODS panel: nothing is sent
package.loaded["pkmultiplayer.options"] = { on = function(k) return k ~= "shareLog" end }
CoopLogShare.pending, CoopLogShare.dropped = {}, 0
line("INFO", "X", "private")
sent = {}
T.check(CoopLogShare.flush() == false and #sent == 0, "SHARE CO-OP LOG off: nothing goes to the partner")
package.loaded["pkmultiplayer.options"] = nil

-- receiving: appended to coop-partner.log, with whose it is
local tmp = os.tmpname()
os.remove(tmp)
CoopLogShare.FILE = tmp
CoopManager.partner = CoopManager.partner or {}
CoopManager.partner.name = "TOBY"
CoopLogShare.lastWriter = nil
CoopManager.handlers.coop_log(nil, { type = "coop_log", lines = { "[a] [INFO] [X] one", "[b] [WARN] [Y] two" }, dropped = 3 })
local f = io.open(tmp, "r")
local text = f and f:read("*a") or ""
if f then f:close() end
os.remove(tmp)
T.check(text:find("TOBY's coop.log") and text:find("one\n") and text:find("two\n"), "the partner's lines land in coop-partner.log, under their name")
T.check(text:find("3 older lines"), "...with a note when some did not fit")

T.finish("co-op log shared with the partner")
