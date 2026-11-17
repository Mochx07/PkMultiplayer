-- WHAT THE PARTNER JUST DID (nightly.2, src/coop/CoopFeed.lua, "events.feed").
--
-- Our catches, evolutions and hatched eggs go to a partner with the
-- capability (and not to one without it, nor a catch made together); theirs
-- become cards in the corner and a burst over their avatar.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local CoopFeed = require("src.coop.CoopFeed")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.connected = true
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m end, isLinked = function() return true end,
                    flush = function() end }
CoopManager.partner.name = "TOBY"

local function withCaps(on)
  CoopManager.partner.caps = on and { [CoopFeed.CAP] = true } or {}
end

-- sending
withCaps(false)
sent = {}
CoopFeed.onCaught({ species = "FIXMON_A", mon = { species = "FIXMON_A" } })
T.check(#sent == 0, "a partner without events.feed is sent nothing")
withCaps(true)
CoopFeed.onCaught({ species = "FIXMON_A", mon = { species = "FIXMON_A" } })
T.check(#sent == 1 and sent[1].kind == "caught" and sent[1].species == "FIXMON_A", "a catch goes to the partner")
CoopFeed.onCaught({ species = "FIXMON_A", mon = { species = "FIXMON_A" }, battle = { coopWild = true } })
T.check(#sent == 1, "a catch made together is not repeated")
CoopFeed.onEvolved({ fromSpecies = "FIXMON_A", toSpecies = "FIXMON_C", mon = {} })
T.check(sent[2] and sent[2].kind == "evolved" and sent[2].from == "FIXMON_A" and sent[2].species == "FIXMON_C",
        "an evolution goes, from and to")
CoopFeed.onHatched({ mon = { species = "FIXMON_C" } })
T.check(sent[3] and sent[3].kind == "hatched", "a hatched egg goes")

-- receiving
CoopFeed.queue = {}
local game = { data = Data }
CoopManager.handlers.coop_event({ game = game }, { type = "coop_event", kind = "caught", species = "FIXMON_A" })
CoopManager.handlers.coop_event({ game = game }, { type = "coop_event", kind = "bogus" })
T.check(#CoopFeed.queue == 1, "their catch is queued (an unknown kind is not)")
T.check(CoopManager.partner.emote == "exclaim" and CoopManager.partner.emoteTimer > 0, "...with a burst over their avatar")
local line = CoopFeed.line(game, CoopFeed.queue[1], "TOBY")
T.check(line and line:find("TOBY") and line:find("CAUGHT"), "the card says who and what (" .. tostring(line) .. ")")
for i = 1, 3 do
  CoopManager.handlers.coop_event({ game = game }, { type = "coop_event", kind = "evolved", from = "FIXMON_A", species = "FIXMON_C" })
end
local cards = CoopFeed.cards(50)
T.check(#cards == CoopFeed.ROWS, "at most " .. CoopFeed.ROWS .. " cards at once")
local later = CoopFeed.cards(50 + CoopFeed.SHOW + 0.1)
T.check(#later == CoopFeed.ROWS and later[1] ~= cards[1], "the shown ones go after " .. CoopFeed.SHOW .. " s and the next come in")

-- the partner's contest, live
CoopManager.partner.contest = { active = true, secondsLeft = 200, at = (love and love.timer and love.timer.getTime()) or os.clock() }
local now0 = CoopManager.partnerContestSecondsLeft
CoopManager.partnerContestSecondsLeft = function() return 125 end
local l1 = CoopFeed.contestLine(game)
T.check(l1 and l1:find("02:05") and l1:find("TOBY"), "the partner's contest: their time left (" .. tostring(l1) .. ")")
CoopManager.partner.contest.species, CoopManager.partner.contest.score = "FIXMON_A", 312
local l2 = CoopFeed.contestLine(game)
T.check(l2 and l2:find("312"), "...and their best catch's score (" .. tostring(l2) .. ")")
CoopManager.partner.contest.active = false
T.check(CoopFeed.contestLine(game) == nil, "their run over: no card")
CoopManager.partnerContestSecondsLeft = now0

T.finish("the partner's feed")
