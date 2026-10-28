-- JOINING, THE MENUS AND THE EXTRAS (1.5.2 / 1.6.0).
--
--   * invite codes: the host's address, read out, typed back
--   * the error says why, and what to do about it
--   * an invite takes a NEW press of A; one that runs out says so
--   * the rules are kept in the save
--   * the link in numbers (VERSION -> diagnostics), the ping loss
--   * READY / NOT READY, cleared when a co-op battle starts
--   * the co-op result: who knocked out what, the experience each took
--   * the arrow to a partner on another map
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
require("src.render.Font").load(T.fixtures.fresh())
local CoopNet = require("src.coop.CoopNet")
local CoopManager = require("src.coop.CoopManager")
local CoopMenu = require("src.coop.CoopMenu")
local CoopSummary = require("src.coop.CoopSummary")
require("src.coop.CoopLog").enabled = false

-- ---------------------------------------------------------------------
-- invite codes
-- ---------------------------------------------------------------------
for _, c in ipairs({ { "192.168.1.100", 7777 }, { "10.147.17.5", 7777 }, { "255.255.255.255", 65535 },
                     { "172.22.4.9", 7790 }, { "0.0.0.0", 7777 } }) do
  local code = CoopNet.inviteCode(c[1], c[2])
  local ip, port = CoopNet.parseInviteCode(code)
  T.check(ip == c[1] and port == c[2], ("%s:%d -> %s -> back"):format(c[1], c[2], tostring(code)))
end
T.check(#CoopNet.inviteCode("192.168.1.100", 7777) == 8, "the usual port makes a 7-letter code (and a dash)")
T.check(#CoopNet.inviteCode("192.168.1.100", 7779) == 11, "another port makes a 10-letter one")
local code = CoopNet.inviteCode("10.147.17.5", 7777)
T.check(CoopNet.parseInviteCode(code:lower():gsub("%-", " ")) == "10.147.17.5", "case and spaces do not matter")
T.check(CoopNet.parseInviteCode(code:gsub("0", "O")) == "10.147.17.5", "an O is read as a zero")
T.check(CoopNet.parseInviteCode("HELLO") == nil, "a word is no code")
T.check(CoopNet.parseInviteCode("ZZZZ-ZZZ") == nil, "a code past the last address is refused")
T.check(CoopNet.parseInviteCode("") == nil and CoopNet.parseInviteCode(nil) == nil, "nothing is no code")

-- the hosts joined lately, newest first, at most three, no repeats
local files = {}
love.filesystem = love.filesystem or {}
local realFs = {}
for _, k in ipairs({ "getInfo", "read", "write", "createDirectory" }) do realFs[k] = love.filesystem[k] end
love.filesystem.getInfo = function(path) return files[path] and { type = "file" } or nil end
love.filesystem.read = function(path) return files[path] end
love.filesystem.write = function(path, text) files[path] = text return true end
love.filesystem.createDirectory = function() return true end
CoopNet.rememberHost("10.0.0.1", 7777)
CoopNet.rememberHost("10.0.0.2", 7777)
CoopNet.rememberHost("10.0.0.1", 7777)
CoopNet.rememberHost("10.0.0.3", 7790)
CoopNet.rememberHost("10.0.0.4", 7777)
local recent = CoopNet.recentHosts()
T.check(#recent == 3 and recent[1].ip == "10.0.0.4" and recent[2].ip == "10.0.0.3" and recent[2].port == 7790
        and recent[3].ip == "10.0.0.1", "the last three hosts, newest first, each once")
CoopNet.rememberHost("not an ip", 7777)
T.check(#CoopNet.recentHosts() == 3 and CoopNet.recentHosts()[1].ip == "10.0.0.4", "a bad address is not kept")
for k, f in pairs(realFs) do love.filesystem[k] = f end

-- ---------------------------------------------------------------------
-- the error, whole, with advice
-- ---------------------------------------------------------------------
local lines = CoopMenu.errorLines("HOST NOT FOUND", 7777)
T.check(lines[1] == "HOST NOT FOUND" and #lines >= 2 and table.concat(lines, " "):find("UDP 7777", 1, true),
        "HOST NOT FOUND says to check the firewall's UDP port")
lines = CoopMenu.errorLines("PARTNER PLAYS OTHER GAME", 7777)
T.check(lines[1] == "PARTNER PLAYS" and lines[2] == "OTHER GAME", "a long reason wraps instead of being cut")
for _, l in ipairs(CoopMenu.errorLines("PARTNER HAS V1.6.0", 7777, 3)) do
  T.check(#l <= 18, "each line fits the box: " .. l)
end
T.check(#CoopMenu.errorLines("SOMETHING ODD", 7777) == 1, "an unknown reason has no made-up advice")
-- every reason and its tip fit the three lines of the box, in Spanish too
local I18n = require("src.coop.CoopI18n")
for _, lang in ipairs({ "en", "es" }) do
  I18n.forced = lang
  for _, why in ipairs({ "HOST NOT FOUND", "PORT 7777 IN USE", "HOST IS BUSY", "PARTNER HAS V1.6.0",
                         "PARTNER PLAYS OTHER GAME", "LINK LOST", "NETWORK UNAVAILABLE", "BAD ADDRESS",
                         "WRONG CODE" }) do
    local all = CoopMenu.errorLines(why, 7777, 9)
    local tipLines = #all - #CoopMenu.wrap(why, 18)
    T.check(tipLines >= 1 and #all <= 3, ("%s: %s and its tip in %d line(s)"):format(lang, why, #all))
  end
end
I18n.forced = nil

-- ---------------------------------------------------------------------
-- an invite takes a new press of A
-- ---------------------------------------------------------------------
local Invite = require("src.coop.CoopBattleInviteModal")
local held, pressedA = true, false
local game = { data = {}, stack = { states = {} } }
function game.stack:push(x) table.insert(self.states, x) end
function game.stack:pop() return table.remove(self.states) end
function game.stack:top() return self.states[#self.states] end
game.input = { isDown = function(_, b) return b == "a" and held end,
               wasPressed = function(_, b) return b == "a" and pressedA end }
local accepted, declined = 0, 0
local modal = Invite.new(game, "TOBY", "FALKNER", function() accepted = accepted + 1 end,
                         function() declined = declined + 1 end)
game.stack:push(modal)
pressedA = true
for _ = 1, 30 do modal:update(0.05) end   -- 1.5 s, A held the whole time
T.check(accepted == 0, "an A held from the last text box joins nothing")
held = false
pressedA = false
modal:update(0.05)
pressedA = true
modal:update(0.05)
T.check(accepted == 1, "a new press after letting go joins")
local m2 = Invite.new(game, "TOBY", "FALKNER", function() end, function() declined = declined + 1 end)
m2.timeout = 1
game.stack:push(m2)
CoopManager.statusMessage = nil
for _ = 1, 30 do m2:update(0.05) end
T.check(declined == 1 and CoopManager.statusMessage == "The invite ran out", "an invite that runs out says so")

-- ---------------------------------------------------------------------
-- the rules are kept in the save
-- ---------------------------------------------------------------------
local G = require("src.core.Game")
local wasSave = G.save
G.save = { }
CoopManager.connected = false
CoopManager.setRule("storySync", false)
T.check(G.save.coopRules and G.save.coopRules.storySync == false, "a rule set is written to the save")
CoopManager.storySync = true
CoopManager.loadRules(G.save)
T.check(CoopManager.storySync == false, "and read back when the save loads")
CoopManager.connected, CoopManager.isHost = true, false
CoopManager.storySync = true
CoopManager.loadRules(G.save)
T.check(CoopManager.storySync == true, "a linked guest keeps the host's rules")
CoopManager.connected = false
CoopManager.storySync = true
G.save = wasSave

-- ---------------------------------------------------------------------
-- the link in numbers
-- ---------------------------------------------------------------------
local net = CoopNet.new()
net.peer, net.resumed = {}, true
local sentRaw = 0
local t0 = 1000
local clockNow = t0
local realTimer = love.timer
love.timer = { getTime = function() return clockNow end }
package.loaded["enet"] = package.loaded["enet"] or {}
net.pingLog = {}
for i = 1, 10 do
  net.pingLog[i] = { t = t0 - 10 + i * 0.5, back = (i % 5 ~= 0) }
end
clockNow = t0 + 5
T.check(net:lossPercent() == 20, "2 pings of 10 unanswered is 20% loss (got " .. net:lossPercent() .. ")")
net.pingLog[#net.pingLog + 1] = { t = clockNow - 0.5 }
T.check(net:lossPercent() == 20, "a ping still on its way is not counted lost")
love.timer = realTimer
CoopManager.net = net
net.stats = { resent = 4, dupes = 1, reconnects = 2 }
net.rttMs = 63
local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
if okCB then CoopBattle.desyncs = 1 end
CoopManager.isConnected = function() return true end
CoopManager.partner.version = "1.6.0"
local diag = {}
for _, row in ipairs(CoopMenu.diagnostics()) do diag[row[1]] = row[2] end
T.check(diag.PING == "63 MS" and diag.RESENT == "4" and diag.RECONNECTS == "2" and diag["DESYNCS FIXED"] == "1"
        and diag["P2 MOD"] == "V1.6.0", "the diagnostics read the link's counters")

-- ---------------------------------------------------------------------
-- READY / NOT READY
-- ---------------------------------------------------------------------
local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end, flush = function() end }
CoopManager.connected = true
CoopManager.setReady(true)
T.check(CoopManager.localReady and sent[#sent].type == "coop_ready" and sent[#sent].ready == true,
        "READY goes to the partner")
CoopManager.onPartnerReady({ ready = false })
T.check(CoopManager.partner.ready == false, "the partner's NOT READY is known")
CoopManager.statusMessage = nil
CoopManager.warnNotReady()
T.check(CoopManager.statusMessage and CoopManager.statusMessage:find("not ready", 1, true),
        "a leader's question says the partner is not ready")
CoopManager.onPartnerReady({ ready = true })
local battle = { }
pcall(require("src.coop.CoopBattle").initBattle, battle, {}, {}, CoopManager.partner, 1, "x")
T.check(CoopManager.localReady == false and CoopManager.partner.ready == nil, "a co-op battle clears both")

-- ---------------------------------------------------------------------
-- the co-op result
-- ---------------------------------------------------------------------
local mine, theirs = { species = "CYNDAQUIL", nickname = "QUILL" }, { species = "TOTODILE" }
local b = { ally = { party = { theirs } }, data = { pokemon = { TOTODILE = { name = "TOTODILE" } } } }
CoopSummary.begin(b)
local killer
function b:killerOf() return killer end
local foe1, foe2, foe3 = { isPlayer = false }, { isPlayer = false }, { isPlayer = false }
killer = { isPlayer = true, mon = mine }
CoopSummary.onFainted({ battle = b, battler = foe1 })
CoopSummary.onFainted({ battle = b, battler = foe2 })
killer = { isPlayer = true, mon = theirs }
CoopSummary.onFainted({ battle = b, battler = foe3 })
CoopSummary.onFainted({ battle = b, battler = { isPlayer = true, mon = mine } })
CoopSummary.onExpGained({ battle = b, mon = mine, gained = 120 })
CoopSummary.onExpGained({ battle = b, mon = theirs, gained = 95 })
CoopSummary.onExpGained({ battle = b, mon = mine, gained = 30 })
local out = CoopSummary.lines(b, "win", "MOCHX", "TOBY")
T.check(out[1] == "CO-OP WIN!", "the result says it was won")
T.check(out[2] == "MOCHX 2KO 150XP", "our knockouts and experience: " .. tostring(out[2]))
T.check(out[3] == "TOBY 1KO 95XP", "the partner's: " .. tostring(out[3]))
T.check(out[4] == "MVP: QUILL", "the Pokemon that did the most")
for _, l in ipairs(out) do T.check(#l <= 18, "fits the box: " .. l) end
CoopSummary.finish(b, "win")
T.check(b.coopTally == nil and CoopSummary.current(50) ~= nil, "it waits, and shows")
T.check(CoopSummary.current(50 + CoopSummary.SHOW + 1) == nil, "for a few seconds")
CoopSummary.finish({ }, "win")
T.check(CoopSummary.pending == nil, "a battle that was not co-op shows nothing")
local ran = { ally = { party = {} } }
CoopSummary.begin(ran)
CoopSummary.finish(ran, "run")
T.check(CoopSummary.pending == nil, "nor one the two ran from before anything happened")

-- ---------------------------------------------------------------------
-- where a partner on another map is
-- ---------------------------------------------------------------------
local g2 = { data = { maps = { NEW_BARK_TOWN = { landmark = 1 }, PALLET_TOWN = { landmark = 0x2F } },
                      field = { townMap = { johto = "x", landmarks = { [1] = { x = 148, y = 116 },
                                                                       [0x2F] = { x = 60, y = 124 } } } } } }
local nx = CoopManager.mapPoint(g2, "NEW_BARK_TOWN")
local px = CoopManager.mapPoint(g2, "PALLET_TOWN")
T.check(nx == 148 and px and px > nx, "Kanto lies east of Johto on the town map")
local g1 = { data = { maps = {}, field = { townMap = { locations = { PALLET_TOWN = { x = 2, y = 11 } } } } } }
T.check(select(2, CoopManager.mapPoint(g1, "PALLET_TOWN")) == 11, "Red/Blue/Yellow's town map squares")
T.check(CoopManager.mapPoint(g1, "OAKS_LAB") == nil, "a map with no square has no arrow")

-- A LINK ATTEMPT THAT FAILS BACK TO THE JOIN LIST it never went through
-- (RECONNECT, an automatic rejoin).  Reported from play after a dropped
-- link: "CoopMenu.lua:778: attempt to perform arithmetic on field
-- 'pickIndex' (a nil value)" -- the list had no cursor and drawing it crashed.
do
  local pressed = {}
  local game = { input = { wasPressed = function(_, b) return pressed[b] == true end,
                           isDown = function() return false end },
                 stack = { states = {}, top = function(st) return st.states[#st.states] end,
                           push = function(st, x) st.states[#st.states + 1] = x end,
                           pop = function(st) return table.remove(st.states) end } }
  local realNet, realConnected = CoopManager.net, CoopManager.isConnected
  CoopManager.net = nil
  CoopManager.isConnected = function() return false end
  local menu = CoopMenu.new(game)
  menu.stage, menu.pickIndex = "joining", nil
  menu:update(0.016)
  T.check(menu.stage == "joinPick", "a failed link attempt falls back to the join list")
  local okDraw, err = pcall(menu.draw, menu)
  T.check(okDraw, "the join list draws with no cursor set yet (" .. tostring(err) .. ")")
  pressed.down = true
  local okUpd, err2 = pcall(menu.update, menu, 0.016)
  T.check(okUpd and type(menu.pickIndex) == "number", "...and its cursor moves (" .. tostring(err2) .. ")")
  CoopManager.net, CoopManager.isConnected = realNet, realConnected
end

-- THE RULES ARE THE SAME ON BOTH GAMES.  Reported from play: NEW CO-OP /
-- CONTINUE CO-OP link first and load the save after; the host sent its rules
-- at the link (its defaults) and not the ones its save then loaded, so the
-- two games played by different rules (BALANCED FOES on one, off the other).
do
  require("src.coop.CoopBalance")
  local sentRules = {}
  local realNet, realConnected, realHost = CoopManager.net, CoopManager.connected, CoopManager.isHost
  CoopManager.net = { send = function(_, m) if m.type == "coop_rules" then sentRules[m.name] = m.value end return true end,
                      flush = function() end }
  CoopManager.connected, CoopManager.isHost = true, true
  CoopManager.balancedFoes = true
  CoopManager.loadRules({ coopRules = { balancedFoes = false } })
  T.check(CoopManager.balancedFoes == false, "the host's save brings its own rules")
  T.check(sentRules.balancedFoes == false, "...and they go to the partner again, not the defaults sent at the link")
  -- a linked guest keeps the host's rules over the ones in its own save
  sentRules = {}
  CoopManager.isHost = false
  CoopManager.balancedFoes = false
  CoopManager.loadRules({ coopRules = { balancedFoes = true } })
  T.check(CoopManager.balancedFoes == false and next(sentRules) == nil, "a linked guest plays by the host's rules, whatever its save says")
  -- the partner's message sets the rule
  CoopManager.handlers.coop_rules(nil, { type = "coop_rules", name = "balancedFoes", value = true })
  T.check(CoopManager.balancedFoes == true, "the host's rule message is taken by the guest")
  CoopManager.net, CoopManager.connected, CoopManager.isHost = realNet, realConnected, realHost
end

T.finish("co-op joining, menus and extras")
