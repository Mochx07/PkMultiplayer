-- tests/test_coop.lua
-- ROM-free tests for the co-op system: transport state machine, handshake,
-- the single message pump, partner smoothing, invites, battle lockstep and
-- host-authoritative sync.  Run: luajit tests/test_coop.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

-- a controllable clock: the stub's timer is frozen at 0
local clock = 100
love.timer.getTime = function() return clock end

local CoopNet = require("src.coop.CoopNet")
local CoopLog = require("src.coop.CoopLog")
local CoopManager = require("src.coop.CoopManager")
local CoopBattleSelect = require("src.coop.CoopBattleSelect")
local CoopBattle = require("src.coop.CoopBattle")
local CoopNewGame = require("src.coop.CoopNewGame")
local CoopWaitModal = require("src.coop.CoopWaitModal")
local CoopBattleInviteModal = require("src.coop.CoopBattleInviteModal")
local Json = require("src.link.Json")
CoopLog.enabled = false

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end

local function section(name) print("\n--- " .. name) end

-- ---------------------------------------------------------------------
-- fixtures
-- ---------------------------------------------------------------------

local function newStack()
  local stack = { states = {} }
  function stack:push(s) table.insert(self.states, s); if s.enter then s:enter() end end
  function stack:pop() local s = table.remove(self.states); if s and s.exit then s:exit() end; return s end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function newInput()
  local input = { pressed = {} }
  function input:wasPressed(k) return self.pressed[k] == true end
  return input
end

-- a stand-in transport that records what is sent and feeds what is queued
local function fakeNet()
  local net = {
    sent = {}, fastSent = {}, queue = {},
    closed = false, paired = true, peer = {}, stalled = false,
    state = CoopNet.STATE.HANDSHAKE, rttMs = 30,
    country = "MX",
    timezone = { offsetSec = -21600, timeStr = "10:00", label = "UTC-6:00" },
  }
  function net:send(msg, opts)
    if opts and opts.fast then table.insert(self.fastSent, msg) else table.insert(self.sent, msg) end
    return true
  end
  function net:update() end
  function net:poll() local q = self.queue; self.queue = {}; return q end
  function net:flush() end
  function net:shutdown() self.closed = true; self.paired = false end
  function net:dropPeer()
    if self.isHostNet then self.paired = false; self.state = CoopNet.STATE.LISTENING
    else self:shutdown() end
  end
  function net:close() self.closed = true; self.paired = false end
  function net:isLinked() return not self.closed and self.paired end
  function net:markSynced() self.state = CoopNet.STATE.SYNCED end
  function net:linkQuality() return 3 end
  function net:lastOf(kind)
    for i = #self.sent, 1, -1 do if self.sent[i].type == kind then return self.sent[i] end end
    return nil
  end
  return net
end

local function freshManager(isHost)
  CoopManager.net = fakeNet()
  CoopManager.isHost = isHost and true or false
  CoopManager.connected = false
  CoopManager.partner = { name = nil, emoteTimer = 0, posN = 0 }
  for k, v in pairs({ map = nil, cx = 0, cy = 0, px = 0, py = 0, facing = "down",
                      healthy = 3, partyCount = 3, lastSeen = 0, hopY = 0 }) do
    CoopManager.partner[k] = v
  end
  CoopManager.render = nil
  CoopManager.partnerNpc = nil
  CoopManager.pendingBattleInvite = nil
  CoopManager.activeInviteModal = nil
  CoopManager.partnerEngagingTrainer = nil
  CoopManager.statusMessage = nil
  CoopManager.statusTimer = 0
  CoopManager.lobby = nil
  CoopManager.timeMode = nil
  CoopManager.timeOffsetSec = 0
  CoopManager.storySync = true
  return CoopManager.net
end

local function hello(extra)
  local m = { type = "coop_hello", proto = CoopNet.PROTOCOL, name = "MOCHI", country = "MX",
              gen = require("src.core.GameVersion").generation(),
              timezone = { offsetSec = -21600, timeStr = "10:00" } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- ---------------------------------------------------------------------
section("CoopNet transport")
-- ---------------------------------------------------------------------

do
  local net = CoopNet.new()
  check(net.state == CoopNet.STATE.DISCONNECTED, "initial state is DISCONNECTED")
  net:setState(CoopNet.STATE.HANDSHAKE, "test")
  net:markSynced()
  check(net.state == CoopNet.STATE.SYNCED and net.sessionActive, "markSynced -> SYNCED and session active")
  net:close()
  check(net.state == CoopNet.STATE.DISCONNECTED and net.closed, "close -> DISCONNECTED")

  -- wire(): functions, userdata and cycles never reach Json.encode
  local cyc = { id = "TACKLE", pp = 35 }
  cyc.self = cyc
  cyc.fn = function() end
  local w = CoopNet.wire({ type = "x", move = cyc, list = { 1, 2, 3 } })
  check(w.move.id == "TACKLE" and w.move.fn == nil and w.move.self == nil, "wire() strips functions and cycles")
  check(#w.list == 3, "wire() keeps arrays")
  local text = CoopNet.encode({ type = "coop_battle_action", action = cyc })
  check(type(text) == "string" and Json.decode(text).action.id == "TACKLE", "encode() never raises on engine tables")

  -- a late disconnect for a replaced peer must not drop the live one
  local live, stale = { name = "live" }, { name = "stale" }
  net = CoopNet.new()
  net.closed = false
  net.peer = live
  net.paired = true
  net.state = CoopNet.STATE.SYNCED
  net.sessionActive = true
  net:onPeerDisconnected(stale, 0)
  check(net.peer == live and net.paired, "stale peer disconnect is ignored")

  -- an unexpected drop opens the reconnect window
  net:onPeerDisconnected(live, 0)
  check(net.state == CoopNet.STATE.RECONNECTING and not net.paired, "link loss -> RECONNECTING")

  -- the host keeps listening after a partner leaves on purpose
  net = CoopNet.new()
  net.closed = false
  net.isHost = true
  net.peer = live
  net.paired = true
  net.sessionActive = true
  net.state = CoopNet.STATE.SYNCED
  net:onPeerDisconnected(live, 2)
  check(net.state == CoopNet.STATE.LISTENING and not net.closed, "host returns to LISTENING when partner leaves")

  -- ...and after the reconnect window runs out
  net = CoopNet.new()
  net.closed = false
  net.isHost = true
  net.enetHost = { service = function() return nil end, flush = function() end }
  net.state = CoopNet.STATE.RECONNECTING
  net.reconnectTimer = CoopNet.RECONNECT_MAX - 0.01
  net:update(0.05)
  check(net.state == CoopNet.STATE.LISTENING and not net.closed, "host reconnect timeout -> LISTENING (socket kept)")

  -- a guest that never reaches a host gives up with a readable error
  net = CoopNet.new()
  net.closed = false
  net.enetHost = { service = function() return nil end, flush = function() end, destroy = function() end }
  net.state = CoopNet.STATE.CONNECTING
  net.connectTimer = CoopNet.CONNECT_TIMEOUT - 0.01
  net:update(0.05)
  check(net.closed and net.error == "HOST NOT FOUND", "guest connect timeout reports HOST NOT FOUND")

  -- reliable messages queue while down, fast ones are dropped
  net = CoopNet.new()
  net.closed = false
  net:send({ type = "coop_chat", text = "hi" })
  net:send({ type = "coop_pos" }, { fast = true })
  check(#net.outbox == 1, "reliable queued while link is down; fast snapshot dropped")

  local tz = CoopNet.detectTimezone()
  check(type(tz.label) == "string" and tz.label:find("^UTC[%+%-]%d+:%d%d$"), "timezone label well formed: " .. tz.label)
  check(CoopNet.lanIP() == CoopNet.lanIP(), "address lookups are cached")
end

-- ---------------------------------------------------------------------
section("handshake + single pump")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  table.insert(net.queue, { type = "net_connect" })
  CoopManager.update(nil, 0.016)
  check(net:lastOf("coop_hello") ~= nil, "hello sent when the link comes up")
  check(net:lastOf("coop_hello").proto == CoopNet.PROTOCOL, "hello carries the protocol version")
  check(net:lastOf("coop_hello").ver == CoopManager.modVersion(), "hello carries the mod's version")

  table.insert(net.queue, hello({ ver = "9.9.9-test" }))
  CoopManager.update(nil, 0.016)
  check(CoopManager.connected, "partner hello completes the handshake")
  check(net.state == CoopNet.STATE.SYNCED, "transport marked SYNCED")
  check(net:lastOf("coop_welcome") ~= nil, "hello answered with welcome")
  check(CoopManager.partner.name == "MOCHI", "partner name recorded")
  check(CoopManager.partner.version == "9.9.9-test", "partner's mod version recorded")

  -- incompatible partner is refused
  net = freshManager(false)
  table.insert(net.queue, hello({ proto = 1, ver = "1.3.1" }))
  CoopManager.update(nil, 0.016)
  check(not CoopManager.connected, "old protocol partner is not linked")
  check(net.closed, "link to incompatible partner is closed")

  -- ...and a host refusing one keeps listening for the right partner
  net = freshManager(true)
  net.isHostNet = true
  table.insert(net.queue, hello({ proto = 1, ver = "1.3.1" }))
  CoopManager.update(nil, 0.016)
  check(not CoopManager.connected and not net.closed and net.state == CoopNet.STATE.LISTENING,
        "a host that refuses a partner keeps its door open")
  check(net:lastOf("coop_reject") ~= nil, "...after telling them why")
  check(CoopManager.statusMessage == "PARTNER HAS V1.3.1", "the refusal names the partner's version ("
        .. tostring(CoopManager.statusMessage) .. ")")
  local reject = net:lastOf("coop_reject")
  check(reject and reject.reason == "PARTNER HAS V" .. CoopManager.modVersion():upper(),
        "...and tells the partner this one's")
  -- a partner from before versions were sent still gets the old line
  net = freshManager(false)
  table.insert(net.queue, hello({ proto = 1 }))
  CoopManager.update(nil, 0.016)
  check(CoopManager.statusMessage == "PARTNER HAS OTHER VERSION", "no version sent: the old refusal")
end

-- ---------------------------------------------------------------------
section("lobby (CoopNewGame)")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  local game = { input = newInput(), stack = newStack(), data = {}, save = {} }
  local started = 0
  local lobby = CoopNewGame.new(game, function() started = started + 1 end)
  game.stack:push(lobby)
  check(CoopManager.lobby == lobby, "lobby registers with CoopManager")

  lobby.stage = "connecting"
  -- the partner's READY arrives in the SAME frame as the handshake
  table.insert(net.queue, hello())
  table.insert(net.queue, { type = "coop_newgame_ready" })
  CoopManager.update(nil, 0.016)
  lobby:update(0.016)
  check(lobby.stage == "confirm", "handshake moves the lobby to confirm")
  check(lobby.partnerReady == true, "partner READY received in the handshake frame is kept")

  game.input.pressed = { a = true }
  lobby:update(0.016)
  game.input.pressed = {}
  check(started == 1, "both ready -> game starts once")
  check(net:lastOf("coop_start_game") ~= nil, "start broadcast to partner")
  check(CoopManager.lobby == nil, "lobby unregisters on start")
  check(game.save.coopLinked == true, "save marked as co-op linked")

  -- coop_start_game from the partner launches too
  net = freshManager(false)
  CoopManager.connected = true
  local started2 = false
  local lobby2 = CoopNewGame.new(game, function() started2 = true end)
  game.stack:push(lobby2)
  lobby2.stage = "confirm"
  table.insert(net.queue, { type = "coop_start_game" })
  CoopManager.update(nil, 0.016)
  check(started2, "partner's start message launches the game")

  -- a host lobby whose partner is in a different time zone shares the host clock
  net = freshManager(true)
  CoopManager.connected = true
  CoopManager.partner.timezone = { offsetSec = 3600, timeStr = "17:00" }
  -- a Gen 2 game: Red / Blue / Yellow have no clock to share
  local GV = require("src.core.GameVersion")
  local wasGame = GV.get()
  GV.set("gold")
  local lobby3 = CoopNewGame.new(game, function() end)
  game.stack:push(lobby3)
  lobby3:enterConfirm()
  check(lobby3.timeSyncAsked and CoopManager.timeMode == "host", "host clock shared by default when zones differ")
  check(net:lastOf("coop_time_sync") and net:lastOf("coop_time_sync").mode == "host", "clock choice sent to partner")
  GV.set("yellow")
  CoopManager.chooseTimeMode("off")
  local lobbyY = CoopNewGame.new(game, function() end)
  lobbyY:enterConfirm()
  check(not lobbyY.timeSyncAsked and CoopManager.timeMode ~= "host", "Red/Blue/Yellow ask about no clock")
  lobbyY:leave()
  GV.set(wasGame)
  lobby3:leave()
end

-- ---------------------------------------------------------------------
section("time of day")
-- ---------------------------------------------------------------------

do
  freshManager(false)
  -- local is UTC-6; the host is UTC+1 and asks everyone to use its clock
  CoopManager.applyTimeMode("host", 3600, -21600)
  check(CoopManager.timeOffsetSec == 3600 - (-21600), "guest shifts to host clock")
  CoopManager.applyTimeMode("guest", 3600, -21600)
  check(CoopManager.timeOffsetSec == 0, "guest clock mode: guest keeps its own time")
  CoopManager.applyTimeMode("off", 3600, -21600)
  check(CoopManager.timeOffsetSec == 0, "off: own clocks")
end

-- ---------------------------------------------------------------------
section("partner position + rendering")
-- ---------------------------------------------------------------------

local function fakeOw(mapId)
  local ow = {
    map = { id = mapId, npcs = {} },
    npcs = {}, entities = {},
    neighbors = {},
    camera = { x = 0, y = 0 },
    player = { cellX = 5, cellY = 5, px = 80, py = 80, facing = "down", walkId = "SPRITE_CHRIS" },
  }
  local game = { stack = newStack(), data = { sprites = { SPRITE_CHRIS = {}, SPRITE_KRIS = {} } },
                 save = { party = { { hp = 10 } } }, overworld = ow }
  game.stack:push(ow)
  ow.game = game
  return ow, game
end

do
  local net = freshManager(true)
  CoopManager.connected = true
  local ow = fakeOw("NEW_BARK_TOWN")

  -- NPC construction needs the real sprite pipeline; stub it for the test
  local NPC = require("src.world.NPC")
  local realNew = NPC.new
  NPC.new = function(data, mapId, def)
    return { def = def, mapId = mapId, id = mapId .. "_obj", refreshSprite = function(self) self.refreshed = true end }
  end

  CoopManager.dispatch(ow, { type = "coop_pos", n = 5, map = "NEW_BARK_TOWN", cx = 4, cy = 4, px = 64, py = 64,
                             facing = "left", moving = false, sprite = "SPRITE_KRIS" })
  CoopManager.dispatch(ow, { type = "coop_pos", n = 4, map = "ROUTE_29", cx = 9, cy = 9, px = 144, py = 144 })
  check(CoopManager.partner.map == "NEW_BARK_TOWN", "older position snapshot is dropped")

  CoopManager.updatePartnerRender(ow, 0.016)
  local npc = CoopManager.partnerNpc
  check(npc and npc.px == 64 and npc.py == 64, "partner appears at its snapshot")
  check(npc and npc.passable and npc.coopPartner, "partner entity is passable")
  check(npc and npc.spriteName == "SPRITE_KRIS", "partner uses the sprite it reports")

  -- one step to the right: drawn position glides instead of jumping
  CoopManager.dispatch(ow, { type = "coop_pos", n = 6, map = "NEW_BARK_TOWN", cx = 4, cy = 4, tx = 5, ty = 4,
                             px = 72, py = 64, facing = "right", moving = true, sprite = "SPRITE_KRIS" })
  CoopManager.updatePartnerRender(ow, 1 / 60)
  check(npc.px > 64 and npc.px < 72, "partner glides toward the new snapshot (px=" .. tostring(npc.px) .. ")")
  check(npc.moving == true, "partner walks while gliding")
  for _ = 1, 30 do CoopManager.updatePartnerRender(ow, 1 / 60) end
  check(npc.px == 72, "partner reaches the snapshot")

  -- a warp-sized jump snaps
  CoopManager.dispatch(ow, { type = "coop_pos", n = 7, map = "NEW_BARK_TOWN", cx = 15, cy = 2, px = 240, py = 32 })
  CoopManager.updatePartnerRender(ow, 1 / 60)
  check(npc.px == 240 and npc.py == 32, "large jumps snap instead of sliding through walls")

  -- bike: the partner's sheet changes with it
  CoopManager.dispatch(ow, { type = "coop_pos", n = 8, map = "NEW_BARK_TOWN", px = 240, py = 32, sprite = "SPRITE_CHRIS" })
  CoopManager.updatePartnerRender(ow, 1 / 60)
  check(npc.refreshed and npc.spriteName == "SPRITE_CHRIS", "sprite refreshes when the partner changes sheet")

  -- partner on a connected map we are drawing: placed through the seam
  ow.neighbors = { { map = { id = "ROUTE_29" }, ox = -320, oy = 0 } }
  CoopManager.dispatch(ow, { type = "coop_pos", n = 9, map = "ROUTE_29", px = 300, py = 32 })
  CoopManager.updatePartnerRender(ow, 1 / 60)
  check(CoopManager.partnerNpc and CoopManager.partnerNpc.px == -20, "partner on a neighbouring map is drawn across the seam")

  -- partner somewhere we cannot see: no entity
  CoopManager.dispatch(ow, { type = "coop_pos", n = 10, map = "VIOLET_CITY", px = 0, py = 0 })
  CoopManager.updatePartnerRender(ow, 1 / 60)
  check(CoopManager.partnerNpc == nil and #ow.npcs == 0, "partner on an unseen map is removed")

  -- our own broadcast: fast channel, change-driven
  net.fastSent = {}
  CoopManager.lastSentPos = nil
  CoopManager.update(ow, 0.016)
  check(#net.fastSent == 1 and net.fastSent[1].type == "coop_pos", "own position sent on the fast channel")
  CoopManager.update(ow, 0.016)
  check(#net.fastSent == 1, "unchanged idle position is not re-sent every frame")
  ow.player.facing = "up"
  CoopManager.update(ow, 0.016)
  check(#net.fastSent == 2, "turning sends a snapshot at once")

  NPC.new = realNew
end

-- ---------------------------------------------------------------------
section("story gates")
-- ---------------------------------------------------------------------

do
  freshManager(true)
  CoopManager.connected = true
  local ow = { map = { id = "NEW_BARK_TOWN" }, game = { data = {}, save = {} } }
  CoopManager.partner.map = "NEW_BARK_TOWN"
  check(CoopManager.checkStoryWarp(ow, "VIOLET_GYM") == true, "partner beside you: gym allowed")
  CoopManager.partner.map = "ROUTE_31"
  check(CoopManager.checkStoryWarp(ow, "VIOLET_GYM") == false, "partner elsewhere: gym blocked")
  ow.map.id = "VIOLET_CITY"
  CoopManager.partner.map = "VIOLET_POKECENTER_1F"
  check(CoopManager.checkStoryWarp(ow, "VIOLET_GYM") == true, "both in Violet: gym allowed")
  ow.map.id = "SEAFOAM_ISLANDS_B1F"
  CoopManager.partner.map = "ROUTE_20"
  check(CoopManager.checkStoryWarp(ow, "SEAFOAM_GYM") == false, "Blaine's real map id is gated")
  -- the Elite Four corridor never deadlocks
  ow.map.id = "WILLS_ROOM"
  CoopManager.partner.map = "INDIGO_PLATEAU_POKECENTER1_F"
  check(CoopManager.checkStoryWarp(ow, "KOGAS_ROOM") == true, "league rooms count as together")
  CoopManager.storySync = false
  CoopManager.partner.map = "ROUTE_29"
  check(CoopManager.checkStoryWarp(ow, "VIOLET_GYM") == true, "story sync off: never gated")
end

-- ---------------------------------------------------------------------
section("battle invites")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  CoopManager.connected = true
  local ow, game = fakeOw("ROUTE_30")
  local pushed = {}
  ow.pushBattle = function(self, b) table.insert(pushed, b) end
  CoopManager.partner.map = "ROUTE_30"
  CoopManager.partner.lastSeen = clock

  check(CoopManager.promptCoopBattle(ow, { kind = "wild" }, {}) == false, "wild battles are always solo")
  local tb = { kind = "trainer", oppClass = "YOUNGSTER", partyIndex = 1 }
  check(CoopManager.promptCoopBattle(ow, tb, {}) == true, "trainer battle with an idle partner offers co-op")
  game.stack:pop()

  CoopManager.partner.map = "VIOLET_CITY"
  local far = { kind = "trainer" }
  check(CoopManager.promptCoopBattle(ow, far, {}) == false and far.coopHandled, "partner on another map: straight to solo")

  CoopManager.partner.map = "ROUTE_30"
  CoopManager.partner.busy = true
  local busy = { kind = "trainer" }
  check(CoopManager.promptCoopBattle(ow, busy, {}) == false, "busy partner: solo")
  check(CoopManager.statusMessage and CoopManager.statusMessage:find("busy"), "busy partner explained to player")
  CoopManager.partner.busy = false

  -- receiving an invite while in a menu: polite decline, nothing torn down
  local menu = { isMenu = true }
  game.stack:push(menu)
  CoopManager.onBattleInviteReceived(ow, { inviteId = "A1", mapId = "ROUTE_30", trainerName = "JOEY" })
  local d = net:lastOf("coop_battle_decline")
  check(d and d.reason == "busy" and d.inviteId == "A1", "invite while busy is declined with reason")
  check(game.stack:top() == menu, "busy player's menu is left alone")
  game.stack:pop()

  -- idle: the modal appears
  CoopManager.onBattleInviteReceived(ow, { inviteId = "A2", mapId = "ROUTE_30", trainerName = "JOEY" })
  check(game.stack:top() and game.stack:top().isCoopInvite, "idle player gets the invite modal")
  check(game.stack:top().inviteId == "A2", "modal remembers its invite")
  -- the inviter gives up: the modal goes wherever it is
  CoopManager.onBattleCancelled(ow, { inviteId = "A2" })
  check(game.stack:top() == ow, "cancelled invite removes the modal")

  -- an accept that arrives after we already went solo is answered with abort
  CoopManager.pendingBattleInvite = nil
  CoopManager.onBattleAccepted(ow, { inviteId = "LATE" })
  check(net:lastOf("coop_battle_abort") and net:lastOf("coop_battle_abort").inviteId == "LATE", "late accept -> abort")

  -- decline for an old invite does not cancel the current one
  local cur = { kind = "trainer" }
  CoopManager.pendingBattleInvite = { battle = cur, inviteId = "NEW", ow = ow }
  CoopManager.onBattleDeclined(ow, { inviteId = "OLD" })
  check(CoopManager.pendingBattleInvite ~= nil, "decline for a different invite is ignored")
  CoopManager.onBattleDeclined(ow, { inviteId = "NEW", reason = "far" })
  check(CoopManager.pendingBattleInvite == nil and pushed[#pushed] == cur, "matching decline battles solo")

  -- wait modal times out into a solo battle
  local reason
  local wm = CoopWaitModal.new(game, "MOCHI", function(r) reason = r end, 1.0)
  game.stack:push(wm)
  wm:update(1.1)
  check(reason == "timeout" and game.stack:top() ~= wm, "wait modal times out and leaves")

  -- invite modal declines itself before the inviter gives up
  local declined = false
  local im = CoopBattleInviteModal.new(game, "MOCHI", "JOEY", function() end, function() declined = true end)
  im.timeout = 1.0
  game.stack:push(im)
  im:update(1.1)
  check(declined and game.stack:top() ~= im, "invite modal auto-declines on timeout")
end

-- ---------------------------------------------------------------------
section("battle lockstep")
-- ---------------------------------------------------------------------

-- a minimal battle with the surface CoopBattle uses
local function mockBattle(isGuest, game)
  local b = {
    isCoopGuest = isGuest,
    game = game or { stack = newStack(), save = { party = {} } },
    battlers = {},
    resolved = {},
    phase = "menu",
  }
  function b:battlerAt(pos) return self.battlers[pos] end
  function b:setAlly(ally) self.ally = ally end
  function b:sendOutSecondPair() end
  function b:resolveTurn(action)
    table.insert(self.resolved, { action = action, partner = self.coopPartnerAction,
                                  roll = self.rng(1, 1000000) })
    self.phase = "messages"
  end
  return b
end

do
  -- the two copies talk through a little bus
  local hostBattle, guestBattle
  local busTo = { host = {}, guest = {} }
  local sender = "host"
  local net = freshManager(true)
  CoopManager.connected = true
  function net:send(msg) table.insert(busTo[sender == "host" and "guest" or "host"], msg) end

  local function deliver(to)
    local q = busTo[to]
    busTo[to] = {}
    CoopBattle.currentBattle = (to == "host") and hostBattle or guestBattle
    for _, m in ipairs(q) do
      if m.type == "coop_battle_action" then CoopBattle.onPartnerAction(m)
      elseif m.type == "coop_battle_leave" then CoopBattle.onPartnerLeft(m) end
    end
  end

  local tackleH = { id = "TACKLE", pp = 35 }
  local emberH = { id = "EMBER", pp = 25 }
  local tackleG = { id = "TACKLE", pp = 35 }
  local emberG = { id = "EMBER", pp = 25 }
  local hostMon = { species = "CYNDAQUIL", hp = 20 }
  local guestMon = { species = "TOTODILE", hp = 22 }
  local guestMon2 = { species = "PIDGEY", hp = 15 }

  hostBattle = mockBattle(false)
  CoopBattle.initBattle(hostBattle, { hostMon }, { CoopManager.wireMon(guestMon), CoopManager.wireMon(guestMon2) },
                        { name = "GUEST" }, 4242, "INV1")
  local hostCoop = hostBattle.coop
  guestBattle = mockBattle(true)
  CoopBattle.initBattle(guestBattle, { guestMon, guestMon2 }, { CoopManager.wireMon(hostMon) },
                        { name = "HOST" }, 4242, "INV1")
  hostBattle.coop = hostCoop

  -- field: each side's own Pokemon on the left, the partner's on the right
  hostBattle.battlers = { [0] = { mon = hostMon, curMoves = { tackleH, emberH } },
                          [2] = { mon = hostBattle.ally.party[1], ally = true, curMoves = { tackleG, emberG } } }
  guestBattle.battlers = { [0] = { mon = guestMon, curMoves = { tackleG, emberG } },
                           [2] = { mon = guestBattle.ally.party[1], ally = true, curMoves = { tackleH, emberH } } }

  -- host picks EMBER at the right-hand foe; nothing resolves yet
  sender = "host"
  CoopBattle.currentBattle = hostBattle
  emberH.targetPosition = 3
  CoopBattle.onLocalActionSelected(hostBattle, emberH)
  check(#hostBattle.resolved == 0 and hostBattle.phase == "waitPartner", "host waits for the guest's turn")
  local wire = busTo.guest[1]
  check(wire and wire.action.kind == "move" and wire.action.slot == 2 and wire.action.target == 3,
        "move sent as slot + target, not as the engine table")

  -- guest picks TACKLE on ITS partner's... no: on the left foe
  deliver("guest")
  sender = "guest"
  CoopBattle.currentBattle = guestBattle
  tackleG.targetPosition = 1
  CoopBattle.onLocalActionSelected(guestBattle, tackleG)
  check(#guestBattle.resolved == 1, "guest resolves as soon as both turns are in")
  deliver("host")
  check(#hostBattle.resolved == 1, "host resolves when the guest's turn arrives")

  local hr, gr = hostBattle.resolved[1], guestBattle.resolved[1]
  check(hr.roll == gr.roll, "both copies roll the same dice for the turn")
  check(hr.partner == tackleG, "host's ally acts with the guest's REAL move instance")
  check(gr.partner == emberH and emberH.targetPosition == 3, "guest's ally acts with host's move at the same foe")

  -- turn 2: a target on the player side is mirrored (my left is your right)
  sender = "guest"
  CoopBattle.currentBattle = guestBattle
  guestBattle.phase = "menu"
  tackleG.targetPosition = 2 -- the guest aims at its partner (host's mon)
  CoopBattle.onLocalActionSelected(guestBattle, tackleG)
  deliver("host")
  sender = "host"
  CoopBattle.currentBattle = hostBattle
  hostBattle.phase = "menu"
  CoopBattle.onLocalActionSelected(hostBattle, tackleH)
  check(hostBattle.resolved[2].partner.targetPosition == 0, "guest's 'my partner' becomes host's own slot")
  deliver("guest")
  check(hostBattle.resolved[2].roll == guestBattle.resolved[2].roll, "turn 2 dice agree")

  -- a stale action for an old turn is ignored
  CoopBattle.currentBattle = hostBattle
  CoopBattle.onPartnerAction({ type = "coop_battle_action", inviteId = "INV1", turn = 1, action = { kind = "spectator" } })
  check(hostBattle.coop.partnerActions[1] == nil, "stale turn ignored")

  -- switches travel as an index into the chosen three
  local enc = CoopBattle.encodeAction(guestBattle, { special = "playerSwitch", mon = guestMon2 })
  check(enc.kind == "switch" and enc.index == 2, "switch encoded as chosen-party index")
  local dec = CoopBattle.decodeAction(hostBattle, enc)
  check(dec and dec.special == "playerSwitch" and dec.mon == hostBattle.ally.party[2],
        "switch decoded to the host's copy of that Pokemon")

  -- a locked turn hands the decision to the engine (lockedAction/AI)
  check(CoopBattle.decodeAction(hostBattle, CoopBattle.encodeAction(hostBattle, {}, { locked = true })) == nil,
        "locked turn decodes to engine choice")

  -- partner leaves while we wait: the turn goes ahead with the AI
  sender = "host"
  CoopBattle.currentBattle = hostBattle
  hostBattle.phase = "menu"
  local before = #hostBattle.resolved
  CoopBattle.onLocalActionSelected(hostBattle, tackleH)
  check(#hostBattle.resolved == before, "waiting for turn 3")
  CoopBattle.onPartnerLeft({ type = "coop_battle_leave", inviteId = "INV1" })
  check(#hostBattle.resolved == before + 1 and hostBattle.resolved[#hostBattle.resolved].partner == nil,
        "partner leaving releases the turn to the ally AI")
  hostBattle.phase = "menu"
  CoopBattle.onLocalActionSelected(hostBattle, tackleH)
  check(#hostBattle.resolved == before + 2, "later turns no longer wait")

  -- a turn lost with a dropped link is sent again once it is back
  local c2 = mockBattle(false)
  CoopBattle.initBattle(c2, { hostMon }, {}, { name = "G" }, 9, "RS")
  c2.battlers = { [0] = { mon = hostMon, curMoves = { tackleH } } }
  busTo.guest = {}
  sender = "host"
  CoopBattle.currentBattle = c2
  CoopBattle.onLocalActionSelected(c2, tackleH)
  busTo.guest = {} -- lost in flight
  CoopBattle.onLinkRestored()
  local resent, here = {}, nil
  for _, m in ipairs(busTo.guest) do
    if m.type == "coop_battle_action" then resent[#resent + 1] = m end
    if m.type == "coop_battle_here" then here = m end
  end
  check(#resent == 1 and resent[1].turn == 1, "pending turn re-sent after reconnect")
  check(here and here.inviteId == "RS" and here.turn == 1, "...and the partner told which battle and turn we are on")

  -- actions that beat the battle into existence are kept
  CoopBattle.currentBattle = nil
  CoopBattle.onPartnerAction({ type = "coop_battle_action", inviteId = "INV2", turn = 1, action = { kind = "spectator" } })
  local late = mockBattle(false)
  CoopBattle.initBattle(late, { hostMon }, {}, { name = "G" }, 7, "INV2")
  check(late.coop.partnerActions[1] ~= nil, "early partner action buffered until the battle starts")
end

do
  -- the owner's word on its own Pokemon rides along with every action
  local host = mockBattle(false)
  local guestMon = { species = "TOTODILE", level = 10, hp = 30, stats = { hp = 30, attack = 12 },
                     moves = { { id = "TACKLE", pp = 30 } } }
  local copy = CoopManager.wireMon(guestMon)
  CoopBattle.initBattle(host, { { species = "CYNDAQUIL", hp = 20, moves = {} } }, { copy }, { name = "G" }, 3, "ST")
  local oldStats = copy.stats
  CoopBattle.applyPartnerState(host, { { species = "TOTODILE", level = 11, hp = 34,
    stats = { hp = 34, attack = 13 }, moves = { { id = "TACKLE", pp = 29 }, { id = "WATER_GUN", pp = 25 } } } })
  check(copy.level == 11 and copy.hp == 34, "partner's level-up reaches our copy")
  check(copy.stats ~= oldStats and copy.stats.attack == 13, "stats replaced the way a level-up replaces them")
  check(#copy.moves == 2 and copy.moves[1].pp == 29 and copy.moves[2].id == "WATER_GUN", "moves and PP follow the owner")
  local packed = CoopBattle.packOwnState({ coopChosenMons = { guestMon } })
  check(packed[1].level == 10 and packed[1].moves[1].id == "TACKLE", "own state packed for the wire")
end

do
  -- foesOf on the guest with the host's slot empty must not list the
  -- guest's Pokemon twice (a spread move hit it twice on one copy only)
  local BattleState = require("src.battle.BattleState")
  if BattleState.foesOf then
    local mine = { isPlayer = true, mon = { hp = 20 } }
    local foe = { isPlayer = false, mon = { hp = 20 } }
    local guestCopy = {
      coopDouble = true, isCoopGuest = true,
      sides = { { battlers = { mine, nil } }, { battlers = { foe } } },
    }
    local foes = BattleState.foesOf(guestCopy, foe)
    check(#foes == 1 and foes[1] == mine, "guest foesOf with the host's slot empty lists each Pokemon once")
    guestCopy.sides[1].battlers = { mine, { isPlayer = true, name = "HOST", mon = { hp = 9 } } }
    foes = BattleState.foesOf(guestCopy, foe)
    check(#foes == 2 and foes[1].name == "HOST", "guest foesOf lists the host's Pokemon first")
  end
end

-- ---------------------------------------------------------------------
section("host-authoritative sync")
-- ---------------------------------------------------------------------

do
  freshManager(false)
  CoopManager.connected = true
  local game = { stack = newStack(), save = { party = {} } }
  local guest = mockBattle(true, game)
  local own = { species = "TOTODILE", nickname = "TOTO", hp = 25 }
  CoopBattle.initBattle(guest, { own }, { { species = "CYNDAQUIL", hp = 20 } }, { name = "HOST" }, 1, "S1")
  guest.coopDouble = true
  guest.battlers = {
    [0] = { mon = own, curStats = { hp = 25 } },
    [2] = { mon = guest.ally.party[1] },
    [1] = { mon = { species = "BELLSPROUT", hp = 15 } },
    [3] = { mon = { species = "BELLSPROUT", hp = 15 } },
  }
  game.stack:push(guest)
  CoopBattle.currentBattle = guest
  guest.phase = "messages"
  guest.coop.turn = 2 -- turn 1 has been played

  CoopBattle.onPartnerBattleSync({ inviteId = "S1", turn = 1,
    guest = { species = "TOTODILE", hp = 15 }, host = { species = "CYNDAQUIL", hp = 18 },
    enemy1 = { species = "BELLSPROUT", hp = 0 }, enemy2 = { species = "BELLSPROUT", hp = 3 } })
  CoopBattle.tick(0.016)
  check(own.hp == 25, "no correction while the turn is still animating")
  guest.phase = "menu"
  CoopBattle.tick(0.016)
  check(guest.battlers[2].mon.hp == 18 and guest.battlers[3].mon.hp == 3,
        "host's Pokemon and the foes corrected between turns")

  -- the next turn already ran here: turn 1's HP must not land over it
  guest.coop.turn = 3
  guest.battlers[3].mon.hp = 2
  CoopBattle.onPartnerBattleSync({ inviteId = "S1", turn = 1,
    host = { species = "CYNDAQUIL", hp = 18 }, enemy2 = { species = "BELLSPROUT", hp = 3 } })
  CoopBattle.tick(0.016)
  check(guest.battlers[3].mon.hp == 2, "a sync for an older turn is dropped")
  check(own.hp == 25, "the guest's OWN Pokemon is never overwritten by the host (it may be a level-up ahead)")
  check(guest.battlers[1].mon.hp == 15, "a faint the guest has not seen is not forced (engine must run it)")

  -- final result from the host: "lose" is the engine's word, not "loss"
  local finishedWith
  guest.finish = function(self) finishedWith = self.result; self.game.stack:pop() end
  CoopBattle.onPartnerBattleSync({ inviteId = "S1", result = "lose", final = true })
  CoopBattle.tick(1.1)
  check(finishedWith == "lose", "host's loss ends the guest battle through finish()")
end

-- ---------------------------------------------------------------------
section("misc")
-- ---------------------------------------------------------------------

do
  local lines = CoopManager.wrap("Please wait for partner to arrive at the gym!", 18, 2)
  check(#lines == 2 and #lines[1] <= 18 and #lines[2] <= 18, "status text wraps to the box")

  -- CoopBattleSelect
  local party = {
    { species = "CYNDAQUIL", hp = 20 }, { species = "PIDGEY", hp = 15 },
    { species = "GEODUDE", hp = 18 }, { species = "RATTATA", hp = 0 },
  }
  local sel = CoopBattleSelect.new({ input = newInput(), data = {}, stack = newStack() }, party, function() end)
  check(#sel.selected == 3 and sel:isSelected(4) == nil, "battle select preselects 3 healthy")
  sel:toggleSelect(4)
  check(#sel.selected == 3, "fainted mon cannot be picked")

  -- deterministic RNG is machine independent
  local a = CoopBattle.newRng(99)
  local b = CoopBattle.newRng(99)
  local same = true
  for _ = 1, 50 do if a(1, 255) ~= b(1, 255) then same = false end end
  check(same, "co-op RNG is deterministic")

  check(CoopManager.leaderBadgeFor("OPP_LEADER") == "ZEPHYRBADGE", "Gold's OPP_LEADER is Falkner")
  check(CoopManager.leaderBadgeFor("OPP_LEADER_LT_SURGE") == "THUNDERBADGE", "OPP_LEADER_* maps to its badge")
  check(CoopManager.leaderBadgeFor("BUGSY") == "HIVEBADGE", "Crystal spelling still maps")
  check(CoopManager.leaderBadgeFor("OPP_YOUNGSTER") == nil, "non-leaders give no badge")

  -- isPartnerEngaging is scoped to the map
  freshManager(true)
  CoopManager.connected = true
  CoopManager.partnerEngagingTrainer = { mapId = "ROUTE_30" }
  CoopManager.partnerEngagingTrainerTime = clock
  check(CoopManager.isPartnerEngaging("ROUTE_30") == true, "partner engaging on our map holds sight")
  check(CoopManager.isPartnerEngaging("ROUTE_31") == false, "partner engaging elsewhere does not")
  clock = clock + 20
  check(CoopManager.isPartnerEngaging("ROUTE_30") == false, "engage hold expires")

  -- chat goes out and shows locally
  local net = freshManager(true)
  CoopManager.connected = true
  CoopManager.sendChat("  Hello partner!  ")
  check(net:lastOf("coop_chat") and net:lastOf("coop_chat").text == "Hello partner!", "chat trimmed and sent")
  check(CoopManager.activeChatMessage and CoopManager.activeChatMessage.text == "Hello partner!", "chat shown locally")
  check(pcall(CoopManager.drawUI, nil), "drawUI renders without an overworld")
end

-- ---------------------------------------------------------------------
section("bug-catching contest together")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  CoopManager.connected = true
  CoopManager.partner.name = "MOCHX"
  local BugContest = require("src.world.BugContest")
  local game = { data = { field = { gen2BugContest = { parkBalls = 20, minutes = 20, contestants = {
    { id = 2, picks = { { species = "CATERPIE", score = 100 } } } } } }, pokemon = {} },
    save = { flags = {}, party = { { hp = 10 } } } }
  -- the partner entered a minute ago and has 19 minutes left
  CoopManager.dispatch(nil, { type = "coop_contest", kind = "start", secondsLeft = 19 * 60 })
  check(CoopManager.statusMessage and CoopManager.statusMessage:find("joined the contest"), "partner entering is announced")
  BugContest.start(game)
  local left = game.save.g2BugContest.endsAt - os.time()
  check(left <= 19 * 60 and left >= 19 * 60 - 2, "joining a partner's contest shares their clock")
  check(net:lastOf("coop_contest") and net:lastOf("coop_contest").kind == "start", "our entry is sent")
  BugContest.setCaught(game.save, { species = "PINSIR", level = 12, hp = 30, stats = { hp = 30, attack = 40 } })
  check(net:lastOf("coop_contest").kind == "catch", "our catch is sent")
  -- the partner caught something huge: they outscore us on our own board
  CoopManager.dispatch(nil, { type = "coop_contest", kind = "catch", species = "SCYTHER", score = 9999 })
  local placing, board = BugContest.judge(game)
  local partnerRow
  for _, row in ipairs(board) do if row.partner then partnerRow = row end end
  check(partnerRow and partnerRow.score == 9999, "partner's catch is on the judging board")
  check(placing == 2, "we place behind the partner (placing " .. tostring(placing) .. ")")
end

-- ---------------------------------------------------------------------
section("story lived together")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  CoopManager.connected = true
  CoopManager.partner.name = "MOCHX"
  CoopManager.partner.map = "ELMS_LAB"
  local CoopStory = require("src.coop.CoopStory")
  local ow = { map = { id = "ELMS_LAB" } }
  local game = { data = { tokens = nil }, save = { player = { name = "TOBY" }, flags = {} } }
  local ctx = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctx)
  check(ctx.coopStory ~= nil, "a script with the partner on the map is shared")
  check(CoopStory.duoName() == "TOBY & MOCHX", "the player is addressed as both of them")
  local TextBox = require("src.render.TextBox")
  check(TextBox.substitute(game, "Hello {PLAYER}!") == "Hello TOBY & MOCHX!", "text boxes use both names")
  CoopStory.onText(ctx, "Here, {PLAYER}!")
  check(net:lastOf("coop_story_text") and net:lastOf("coop_story_text").text == "Here, TOBY & MOCHX!", "the line is sent expanded")
  ctx.lastCheck = true
  CoopStory.observe(ctx, "give_item", { "give_item", "POTION", 1 })
  -- the rows' own effects on the save, which is what is shared
  game.save.flags.EVENT_GOT_POTION = true
  CoopStory.finish(ctx)
  local r = net:lastOf("coop_story_rewards")
  check(r and #r.rewards == 2 and r.rewards[1].id == "POTION"
        and r.rewards[2].kind == "set_flag" and r.rewards[2].id == "EVENT_GOT_POTION",
        "rewards sent when the script ends")
  check(CoopStory.duoName() == nil, "names go back to normal afterwards")

  -- EVERYTHING the scene wrote is shared, not just the rows on a list:
  -- Falkner's `specialphonecall` (Elm's egg call), an object `disappear`
  -- (its flag set with no setevent), a cleared flag and a map scene
  net.sent = {}
  game.save.flags.EVENT_G2_1792 = true
  local ctxF = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctxF)
  game.save.flags.EVENT_G2_1213 = true
  game.save.flags.ZEPHYRBADGE = true
  game.save.flags.EVENT_G2_1792 = false
  game.save.g2Scenes = { ELMS_LAB = 2 }
  game.save.g2SpecialCall = 3
  CoopStory.finish(ctxF)
  local rf = net:lastOf("coop_story_rewards")
  local got = {}
  for _, x in ipairs(rf and rf.rewards or {}) do got[x.kind .. ":" .. tostring(x.id or x.map)] = x end
  check(got["set_flag:EVENT_G2_1213"] and got["set_flag:ZEPHYRBADGE"], "the badge and the beaten leader are shared")
  check(got["clear_flag:EVENT_G2_1792"], "a cleared flag is shared")
  check(got["scene_key:ELMS_LAB"] and got["scene_key:ELMS_LAB"].scene == 2, "a map scene is shared")
  check(got["special_call:3"], "the armed POKeGEAR call is shared")
  game.save.g2Scenes, game.save.g2SpecialCall = nil, nil

  -- a script that hands over a Pokemon is personal: texts yes, rewards no
  net.sent = {}
  local ctx2 = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctx2)
  CoopStory.observe(ctx2, "set_flag", { "set_flag", "EVENT_STARTER" })
  CoopStory.observe(ctx2, "g2_give_poke", { "g2_give_poke", 155, 5 })
  check(CoopStory.duoName() == nil, "after a gift Pokemon the text is the player's own again")
  CoopStory.finish(ctx2)
  check(net:lastOf("coop_story_rewards") == nil, "a personal script shares no flags")

  -- partner elsewhere: not lived together (no names, no lines, no warp),
  -- but what it changed still counts for them
  CoopManager.partner.map = "NEW_BARK_TOWN"
  net.sent = {}
  local ctx3 = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctx3)
  check(ctx3.coopStory ~= nil and not ctx3.coopStory.here, "partner on another map: the event is recorded")
  check(CoopStory.duoName() == nil, "partner on another map: the player keeps their own name")
  CoopStory.onText(ctx3, "Hi!")
  check(net:lastOf("coop_story_text") == nil, "partner on another map: no lines are sent")
  ctx3.lastCheck = true
  CoopStory.observe(ctx3, "g2_giveitem", { "g2_giveitem", "TM_31", 1 })
  CoopStory.observe(ctx3, "g2_warp", { "g2_warp", "HALL_OF_FAME", 4, 13 })
  game.save.flags.EVENT_FAR = true
  CoopStory.finish(ctx3)
  local r3 = net:lastOf("coop_story_rewards")
  local kinds3 = {}
  for _, x in ipairs(r3 and r3.rewards or {}) do kinds3[x.kind] = true end
  check(kinds3.item and kinds3.set_flag and not kinds3.warp,
        "partner on another map gets the item and the flag, not the warp")
  CoopManager.partner.map = "ELMS_LAB"

  -- what a scene takes, the rival's name, the story sprites, the beasts
  net.sent = {}
  game.save.inventory = { MYSTERY_EGG = 1 }
  local ctxT = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctxT)
  ctxT.lastCheck = true
  CoopStory.observe(ctxT, "take_item", { "take_item", "MYSTERY_EGG", 1 })
  game.save.player.rival = "SILVER"
  game.save.gen2VarSprites = { [3] = "SPRITE_ROCKET" }
  game.save.g2Wram = { [0xD73D] = 2 }
  game.save.g2RoamReleased = true
  CoopStory.finish(ctxT)
  local rT = net:lastOf("coop_story_rewards")
  local gotT = {}
  for _, x in ipairs(rT and rT.rewards or {}) do gotT[x.kind] = x end
  check(gotT.take_item and gotT.take_item.id == "MYSTERY_EGG", "an item the scene takes is shared")
  check(gotT.rival_name and gotT.rival_name.name == "SILVER", "the rival's name is shared")
  check(gotT.var_sprite and gotT.var_sprite.slot == 3 and gotT.var_sprite.sprite == "SPRITE_ROCKET",
        "a story sprite change is shared")
  check(gotT.wram and gotT.wram.addr == 0xD73D and gotT.wram.value == 2, "a script memory byte is shared")
  check(gotT.roam_release ~= nil, "the beasts' release is shared")
  game.save.gen2VarSprites, game.save.g2Wram, game.save.g2RoamReleased = nil, nil, nil

  -- a map callback and a map-reload bit are not story
  net.sent = {}
  local ctxC = { game = game, overworld = ow, save = game.save, mapCallback = true }
  CoopStory.begin(ctxC)
  check(ctxC.coopStory == nil, "a map callback is not shared")
  local ctxR = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctxR)
  game.save.flags.EVENT_G2_0002 = true
  CoopStory.finish(ctxR)
  check(net:lastOf("coop_story_rewards") == nil, "a map-reload bit is not shared")
  game.save.flags.EVENT_G2_0002 = nil

  -- a purchase and a scripted wild Pokemon are the player's own
  for _, rows in ipairs({ { { "give_money", -500 } }, { { "g2_give_coins", -50 } },
                          { { "g2_load_wild", "SPECIES_185", 20 } },
                          { { "start_battle", "wild", "SPECIES_130", 30 } },
                          { { "g2_select_apricorn" } } }) do
    net.sent = {}
    local c = { game = game, overworld = ow, save = game.save }
    CoopStory.begin(c)
    c.lastCheck = true
    CoopStory.observe(c, "g2_giveitem", { "g2_giveitem", "FRESH_WATER", 1 })
    for _, row in ipairs(rows) do CoopStory.observe(c, row[1], row) end
    game.save.flags.EVENT_PERSONAL = true
    CoopStory.finish(c)
    check(net:lastOf("coop_story_rewards") == nil, "personal: " .. rows[1][1] .. " shares nothing")
    game.save.flags.EVENT_PERSONAL = nil
  end

  -- link down: the event waits in the save for the partner
  net.sent = {}
  CoopManager.connected = false
  game.save.coopPartner = "MOCHX"
  game.save.coopStoryOutbox = nil
  local ctxO = { game = game, overworld = ow, save = game.save }
  CoopStory.begin(ctxO)
  check(ctxO.coopStory ~= nil, "offline with a known partner: the event is recorded")
  game.save.flags.EVENT_OFFLINE = true
  CoopStory.finish(ctxO)
  check(net:lastOf("coop_story_rewards") == nil and game.save.coopStoryOutbox
        and #game.save.coopStoryOutbox == 1, "offline: the event is kept in the save")
  CoopManager.syncTrainerDefeated("ROUTE30_obj_3", "EVENT_BEAT_YOUNGSTER", 3, "ROUTE_30")
  check(#game.save.coopStoryOutbox == 1, "no game to save into: a trainer is not kept")
  local Game = package.loaded["src.core.Game"]
  package.loaded["src.core.Game"] = game
  CoopManager.syncTrainerDefeated("ROUTE30_obj_3", "EVENT_BEAT_YOUNGSTER", 3, "ROUTE_30")
  package.loaded["src.core.Game"] = Game
  check(#game.save.coopStoryOutbox == 2 and game.save.coopStoryOutbox[2][1].kind == "trainer",
        "offline: a beaten trainer is kept too")
  -- a save that never played with anyone keeps nothing
  local loner = { player = { name = "SOLO" }, flags = {} }
  local ctxL = { game = { data = {}, save = loner }, overworld = ow, save = loner }
  CoopStory.begin(ctxL)
  check(ctxL.coopStory == nil, "a save with no partner records nothing")

  -- linked again: the kept events go out once both are in the world
  CoopManager.connected = true
  CoopManager.partner.name = "MOCHX"
  CoopManager.bindStoryPartner(game, ow)
  local backlog = 0
  for _, m in ipairs(net.sent) do if m.type == "coop_story_rewards" and m.backlog then backlog = backlog + 1 end end
  check(backlog == 2 and game.save.coopStoryOutbox == nil, "reconnected: the kept events are sent")
  -- a different partner does not get what was kept for the old one
  game.save.coopStoryOutbox = { { { kind = "set_flag", id = "EVENT_X" } } }
  net.sent = {}
  CoopManager.partner.name = "OTHER"
  CoopManager.bindStoryPartner(game, ow)
  check(net:lastOf("coop_story_rewards") == nil and game.save.coopStoryOutbox == nil
        and game.save.coopPartner == "OTHER", "a new partner: the old partner's events are dropped")
  CoopManager.partner.name = "MOCHX"
  game.save.coopPartner = nil

  -- receiving side: same map gets the item and the flag
  CoopManager.partner.map = "ELMS_LAB"
  local recvGame = { data = { items = { POTION = { name = "POTION" } } },
                     save = { inventory = {}, flags = {}, player = { name = "MOCHX" } },
                     overworld = { map = { id = "ELMS_LAB" } } }
  local Bag = require("src.inventory.Bag")
  local realAdd = Bag.add
  Bag.add = function(save, id, n) save.inventory[id] = (save.inventory[id] or 0) + n return true end
  CoopStory.onPartnerRewards(recvGame, { map = "ELMS_LAB", rewards = {
    { kind = "item", id = "POTION", count = 1 }, { kind = "set_flag", id = "EVENT_GOT_POTION" } } })
  Bag.add = realAdd
  check(recvGame.save.inventory.POTION == 1, "partner receives the same item")
  check(recvGame.save.flags.EVENT_GOT_POTION, "partner's event flag is set")
  CoopStory.onPartnerRewards(recvGame, { map = "ELMS_LAB", rewards = {
    { kind = "scene_key", map = "ROUTE32", scene = 1 }, { kind = "special_call", id = 3 } } })
  check(recvGame.save.g2Scenes and recvGame.save.g2Scenes.ROUTE32 == 1, "partner's map scene is written")
  check(recvGame.save.g2SpecialCall == 3, "partner's POKeGEAR call is armed")

  -- the same event a second time (both talked to the NPC, or it came in a
  -- backlog after being played here): no second item
  Bag.add = function(save, id, n) save.inventory[id] = (save.inventory[id] or 0) + n return true end
  CoopStory.onPartnerRewards(recvGame, { map = "ELMS_LAB", rewards = {
    { kind = "item", id = "POTION", count = 1 }, { kind = "set_flag", id = "EVENT_GOT_POTION" } } })
  check(recvGame.save.inventory.POTION == 1, "an event already lived here gives no second item")
  -- from another map: the outcome, never the warp
  CoopStory.pendingWarp = nil
  CoopStory.onPartnerRewards(recvGame, { map = "GOLDENROD_CITY", rewards = {
    { kind = "item", id = "POTION", count = 1 }, { kind = "set_flag", id = "EVENT_GOLDENROD" },
    { kind = "warp", map = "HALL_OF_FAME", x = 4, y = 13 } } })
  check(recvGame.save.inventory.POTION == 2 and recvGame.save.flags.EVENT_GOLDENROD,
        "an event on another map counts here too")
  check(CoopStory.pendingWarp == nil, "an event on another map does not warp this player")
  Bag.add = realAdd
  recvGame.save.inventory.MYSTERY_EGG = 1
  CoopStory.onPartnerRewards(recvGame, { map = "ELMS_LAB", rewards = {
    { kind = "take_item", id = "MYSTERY_EGG", count = 1 }, { kind = "set_flag", id = "EVENT_GAVE_EGG" },
    { kind = "take_item", id = "SECRETPOTION", count = 1 },
    { kind = "rival_name", name = "SILVER" }, { kind = "wram", addr = 0xD73D, value = 2 },
    { kind = "trainer", npcId = "ROUTE30_obj_3", headerEvent = "EVENT_BEAT_YOUNGSTER", mapId = "ROUTE_30" } } })
  check(recvGame.save.inventory.MYSTERY_EGG == nil, "the item the scene took leaves this bag")
  check(recvGame.save.player.rival == "SILVER", "the rival gets the same name here")
  check(recvGame.save.g2Wram and recvGame.save.g2Wram[0xD73D] == 2, "the script memory byte is written")
  check(recvGame.save.flags.EVENT_BEAT_YOUNGSTER and recvGame.save.defeatedTrainers["ROUTE30_obj_3"],
        "a trainer beaten while apart is beaten here")
  -- arrives before this save is up: applied once it is
  local early = { data = recvGame.data, save = nil }
  CoopStory.inbox = {}
  CoopStory.onPartnerRewards(early, { backlog = true, rewards = { { kind = "set_flag", id = "EVENT_EARLY" } } })
  check(#CoopStory.inbox == 1, "an event that arrives on the title screen waits")
  CoopStory.tick(0, recvGame)
  check(#CoopStory.inbox == 0 and recvGame.save.flags.EVENT_EARLY, "and is applied once the save is up")

  -- a save caught by the old sharing (badge, no egg, aide never showed up)
  -- gets Elm's call back on load
  local V = require("src.core.GameVersion")
  local wasVersion = V.get()
  V.set("gold")
  local stuck = { flags = { EVENT_G2_1213 = true, ZEPHYRBADGE = true, EVENT_G2_1792 = true } }
  check(CoopStory.repairSave(stuck) and stuck.g2SpecialCall == 3, "a stuck save gets Elm's egg call re-armed")
  local fine = { flags = { EVENT_G2_1213 = true, EVENT_G2_0045 = true, EVENT_G2_1792 = true } }
  check(not CoopStory.repairSave(fine) and fine.g2SpecialCall == nil, "a save that has the egg is left alone")
  local early = { flags = { EVENT_G2_1792 = true } }
  check(not CoopStory.repairSave(early), "a save before Falkner is left alone")
  V.set(wasVersion)
  CoopStory.feed = {}
  CoopStory.onPartnerText(recvGame, { map = "ELMS_LAB", text = "Here, TOBY & MOCHX!" })
  check(#CoopStory.feed >= 1, "partner's lines are queued to read")
  CoopStory.onPartnerText(recvGame, { map = "ROUTE_29", text = "far away" })
  check(#CoopStory.feed == 1, "lines from another map are ignored")
  CoopStory.feed = {}
end

-- ---------------------------------------------------------------------
section("one clock, one weekday")
-- ---------------------------------------------------------------------

do
  freshManager(false)
  CoopManager.connected = true
  local before = os.time()
  CoopManager.applyTimeMode("host", 3600, -21600, 3, 0)
  local shifted = os.time()
  check(math.abs((shifted - before) - (3600 + 21600)) <= 2, "the game's clock moves to the shared one")
  check(os.date("%Y-%m-%d %H:%M", shifted) == os.date("%Y-%m-%d %H:%M"), "os.date with no time reads the shared clock")
  check(CoopManager.dayOffset({ g2DayOffset = 5 }) == 3, "the host's picked weekday is shared")
  CoopManager.applyTimeMode("off")
  check(math.abs(os.time() - before) <= 2, "own clock comes back")
  check(CoopManager.dayOffset({ g2DayOffset = 5 }) == 5, "own weekday comes back")
end

-- ---------------------------------------------------------------------
section("saving together")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  CoopManager.connected = true
  CoopManager.partner.name = "MOCHX"
  CoopManager.onLocalSaved(true)
  check(net:lastOf("coop_save") ~= nil, "a save asks the partner to save")
  local saves = 0
  local ow, game = fakeOw("NEW_BARK_TOWN")
  game.writeSave = function() saves = saves + 1 return true end
  CoopManager.dispatch(ow, { type = "coop_save", name = "MOCHX" })
  local realGame = package.loaded["src.core.Game"]
  package.loaded["src.core.Game"] = game
  CoopManager.update(ow, 0.016)
  package.loaded["src.core.Game"] = realGame
  check(saves == 1, "the partner's request saves this game once it is idle")
  check(net:lastOf("coop_save_done") and net:lastOf("coop_save") and #net.sent >= 2, "and answers")
  local before = #net.sent
  CoopManager.savingForPartner = true
  CoopManager.onLocalSaved(true)
  CoopManager.savingForPartner = false
  check(#net.sent == before, "a save made for the partner is not echoed back")
end

-- ---------------------------------------------------------------------
section("big battles: decided before the dialogue")
-- ---------------------------------------------------------------------

do
  local net = freshManager(true)
  CoopManager.connected = true
  CoopManager.partner.name = "MOCHX"
  CoopManager.partner.map = "VIOLET_GYM"
  CoopManager.partner.lastSeen = clock
  local save = { flags = {}, inventory = {}, party = { { hp = 20, species = "A" } }, player = { name = "TOBY" } }
  check(CoopManager.isBigBattleClass("OPP_LEADER", save), "Falkner is a big battle")
  check(CoopManager.isBigBattleClass("OPP_RIVAL1", save), "the rival is a big battle")
  check(not CoopManager.isBigBattleClass("OPP_YOUNGSTER", save), "a youngster is not")
  save.flags.ZEPHYRBADGE = true
  check(not CoopManager.isBigBattleClass("OPP_LEADER", save), "a leader whose badge you hold is not asked again")
  save.flags.ZEPHYRBADGE = nil
  local CoopStory = require("src.coop.CoopStory")
  local script = { { "show_text", "X" }, { "g2_winloss", "W", "L" }, { "g2_load_trainer", "OPP_LEADER", 1 }, { "g2_start_battle" } }
  check(CoopStory.findBigBattle(script, save) == "OPP_LEADER", "the gym script's trainer is found before it talks")

  -- host talks to Falkner: the choice comes first, the partner is invited
  local ow, game = fakeOw("VIOLET_GYM")
  game.save = save
  game.data.trainers = { OPP_LEADER = { partyNames = { "FALKNER" } } }
  local realGame = package.loaded["src.core.Game"]
  package.loaded["src.core.Game"] = game
  local runner = {}
  function runner:resume() end
  function runner:yield()
    local menu = game.stack:top()
    game.stack:pop()
    menu.items[1].onSelect() -- CO-OP
  end
  CoopManager.offerBigBattle({ game = game, runner = runner, overworld = ow, save = save }, "OPP_LEADER", 1)
  local inv = net:lastOf("coop_bigbattle_invite")
  check(inv and inv.trainerName == "FALKNER", "the partner is invited before Falkner says a word")
  check(CoopManager.bigBattle and CoopManager.bigBattle.inviteId == inv.inviteId, "host remembers the plan")

  -- the partner picks while Falkner talks and is ready first
  CoopManager.dispatch(ow, { type = "coop_bigbattle_ready", inviteId = inv.inviteId, chosenMons = { { species = "B", hp = 20 } } })
  check(CoopManager.bigBattle.partnerMons ~= nil, "partner's team waits for the host")
  -- the script reaches startbattle: host picks three, and it starts at once
  local pushed
  ow.pushBattle = function(self, b) pushed = b end
  local CoopBattle = require("src.coop.CoopBattle")
  local realInit = CoopBattle.initBattle
  local initWith
  CoopBattle.initBattle = function(b, mine, theirs) initWith = theirs end
  local battle = { kind = "trainer", oppClass = "OPP_LEADER", partyIndex = 1 }
  check(CoopManager.promptCoopBattle(ow, battle, {}) == true, "the big battle takes the co-op path")
  local select = game.stack:top()
  check(select and select.isCoopBattleSelect, "no BATTLE MODE menu again: straight to the team")
  select:confirm()
  check(net:lastOf("coop_bigbattle_go") ~= nil, "both ready -> the go goes out")
  check(pushed == battle and initWith and initWith[1].species == "B", "battle starts with the partner's three")
  CoopBattle.initBattle = realInit

  -- partner declined while the leader talked: solo, no menu
  freshManager(true)
  CoopManager.connected = true
  CoopManager.bigBattle = { inviteId = "Z", oppClass = "OPP_LEADER" }
  CoopManager.dispatch(ow, { type = "coop_battle_decline", inviteId = "Z", reason = "declined" })
  local b2 = { kind = "trainer", oppClass = "OPP_LEADER" }
  check(CoopManager.promptCoopBattle(ow, b2, {}) == false, "declined in advance -> solo battle, nothing asked")

  -- the guest side: invite -> ready -> go
  local net2 = freshManager(false)
  CoopManager.connected = true
  CoopManager.partner.name = "TOBY"
  local gow, ggame = fakeOw("VIOLET_GYM")
  package.loaded["src.core.Game"] = ggame
  CoopManager.dispatch(gow, { type = "coop_bigbattle_invite", inviteId = "Q", oppClass = "OPP_LEADER",
                              trainerName = "FALKNER", mapId = "VIOLET_GYM" })
  local modal = ggame.stack:top()
  check(modal and modal.isCoopInvite and modal.lines[2]:find("FALKNER"), "guest is told who the partner faces")
  ggame.stack:pop(); modal.onAccept()
  ggame.stack:top():confirm()
  check(net2:lastOf("coop_bigbattle_ready") ~= nil, "guest's team is sent")
  check(ggame.stack:top() and ggame.stack:top().compact, "guest reads along under a small waiting box")
  local started
  local realStart = CoopManager.startGuestBattle
  CoopManager.startGuestBattle = function(g, o, msg, mons) started = mons end
  CoopManager.dispatch(gow, { type = "coop_bigbattle_go", inviteId = "Q", seed = 5, localMons = {} })
  CoopManager.startGuestBattle = realStart
  check(started and #started >= 1, "the go starts the guest's battle with the team picked earlier")
  check(not (ggame.stack:top() and ggame.stack:top().compact), "the waiting box is gone")
  package.loaded["src.core.Game"] = realGame
end

-- ---------------------------------------------------------------------
section("after a won co-op battle")
-- ---------------------------------------------------------------------

do
  freshManager(true)
  CoopManager.connected = true
  local CoopBattle = require("src.coop.CoopBattle")
  local a = { species = "A", hp = 0, stats = { hp = 20 } }
  local b = { species = "B", hp = 5, status = "PSN", stats = { hp = 20 } }
  local c = { species = "C", hp = 0, stats = { hp = 20 } }
  local battle = { game = { save = { party = { a, b, c } } }, coopChosenMons = { a, b, c }, data = {} }
  check(CoopBattle.afterWinRules(battle) == nil, "with someone still standing nothing changes")
  check(a.hp == 0 and b.status == "PSN", "fainted stay fainted, statuses stay (Gen 2 rule)")
  b.hp = 0
  local note = CoopBattle.afterWinRules(battle)
  check(note and a.hp == 1 and c.hp == 0, "a win with nobody standing gets ONE Pokemon up at 1 HP, not all")
  CoopManager.partnerHeals = true
  CoopManager.partner.name = "MOCHX"
  local Pokemon = require("src.pokemon.Pokemon")
  local realHeal = Pokemon.heal
  Pokemon.heal = function(m) m.hp = m.stats.hp; m.status = nil end
  note = CoopBattle.afterWinRules(battle)
  Pokemon.heal = realHeal
  CoopManager.partnerHeals = false
  check(note and c.hp == 20 and b.hp == 20, "PARTNER HEALS: Sinnoh's partner rule heals the team")

  -- lost together in a battle the story lets you lose: the host's scene heals
  -- the host; the guest, who runs no script, is healed here
  local BattleState = require("src.battle.BattleState")
  local CB = require("src.coop.CoopBattle")
  local realNew, realInit = BattleState.newTrainer, CB.initBattle
  BattleState.newTrainer = function() return {} end
  CB.initBattle = function() end
  Pokemon.heal = function(m) m.hp = m.stats.hp; m.status = nil end
  local function lostTo(msg)
    local mon = { species = "A", hp = 0, stats = { hp = 20 } }
    local pushed
    local ow = { pushBattle = function(_, bt) pushed = bt end, afterBattle = function() end }
    local g = { save = { party = { mon } }, overworld = ow, stack = { push = function() end } }
    CoopManager.startGuestBattle(g, ow, msg, { mon })
    pushed.onFinish("lose")
    return mon.hp
  end
  check(lostTo({ oppClass = "OPP_RIVAL1", mapId = "CHERRYGROVE_CITY", canLose = true }) == 20,
        "a can-lose battle lost together heals the guest's team")
  check(lostTo({ oppClass = "OPP_RIVAL1", mapId = "OAKS_LAB" }) == 20,
        "Oak's Lab rival lost together heals the guest's team (the host's script heals the host)")
  check(lostTo({ oppClass = "OPP_FALKNER", mapId = "VIOLET_GYM" }) == 0,
        "an ordinary loss is left to the blackout")
  BattleState.newTrainer, CB.initBattle, Pokemon.heal = realNew, realInit, realHeal
end

if failures == 0 then
  print("\nALL CO-OP TESTS PASSED")
  os.exit(0)
else
  print(string.format("\n%d FAILURE(S)", failures))
  os.exit(1)
end
