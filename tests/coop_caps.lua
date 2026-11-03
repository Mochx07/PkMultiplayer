-- CAPABILITIES IN THE HELLO (1.20): a copy says what it can do beyond
-- protocol 16; a feature runs only when both copies have it, and a copy from
-- before 1.20 (no caps at all) still links, with every new feature off.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end,
                    update = function() end, poll = function() return {} end,
                    markSynced = function() end, dropPeer = function() end,
                    notePeerIdentity = function() end, timezone = { offsetSec = 0 } }
CoopManager.isHost = true
CoopManager.connected = false

local function sentOf(kind)
  for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end
end
local function hello(extra)
  local m = { type = "coop_hello", proto = CoopManager.PROTOCOL, ver = "1.20.0", name = "TOBY",
              gen = require("src.core.GameVersion").generation(), timezone = { offsetSec = 0 } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local saved = CoopManager.CAPS
CoopManager.CAPS = {}

-- ours: registered names, sorted, in the hello
CoopManager.registerCap("vs.rules")
CoopManager.registerCap("caps.probe")
local list = CoopManager.localCaps()
T.check(#list == 2 and list[1] == "caps.probe" and list[2] == "vs.rules", "our caps come out sorted")
T.check(not pcall(CoopManager.registerCap, "has space"), "a name with a space is refused")
T.check(not pcall(CoopManager.registerCap, nil), "no name is refused")

-- a 1.20 partner with some of ours
sent = {}
CoopManager.dispatch(nil, hello({ caps = { "vs.rules", "minigame.karp" } }))
T.check(CoopManager.connected, "a partner with caps links")
local welcome = sentOf("coop_welcome")
T.check(welcome and type(welcome.caps) == "table" and #welcome.caps == 2, "our welcome carries our caps")
T.check(CoopManager.partnerHas("vs.rules") and CoopManager.partnerHas("minigame.karp"), "the partner's caps are kept")
T.check(CoopManager.bothHave("vs.rules"), "a cap on both copies is on")
T.check(not CoopManager.bothHave("minigame.karp"), "a cap only the partner has stays off")
T.check(not CoopManager.bothHave("caps.probe"), "a cap only we have stays off")

-- a partner from before 1.20: no caps field, same protocol -> links, nothing new
CoopManager.connected = false
CoopManager.dispatch(nil, hello({ ver = "1.6.17" }))
T.check(CoopManager.connected, "a 1.6.17 partner (no caps) still links")
T.check(not CoopManager.partnerHas("vs.rules") and not CoopManager.bothHave("vs.rules"),
        "...and every new feature is off with it")

-- junk in the list is dropped, not trusted
local set = CoopManager.capSet({ "ok_name", 42, ("x"):rep(40), "bad name", { "t" }, "vs.rules" })
T.check(set.ok_name and set["vs.rules"] and not set[42] and not set["bad name"], "only short names are kept")
T.check(next(CoopManager.capSet("vs.rules")) == nil and next(CoopManager.capSet(nil)) == nil,
        "a caps field that is not a list counts as none")
local many = {}
for i = 1, 200 do many[i] = "c" .. i end
local n = 0
for _ in pairs(CoopManager.capSet(many)) do n = n + 1 end
T.check(n == 64, "at most 64 caps are read")

CoopManager.CAPS = saved
T.finish("co-op capabilities")
