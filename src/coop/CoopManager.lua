-- src/coop/CoopManager.lua
-- Core Manager for Gen2Recomped Co-op mode.
--
-- One pump: Game:update calls CoopManager.update once per rendered frame,
-- and that is the only place the transport is serviced and its inbox read.
-- (The overworld, the co-op menu, the wait modal and the lobby used to pump
-- it too; whichever ran first ate the messages, which is how the lobby's
-- READY and half the battle replies went missing.)  Screens that need raw
-- messages register as CoopManager.lobby and are offered each one first.
--
-- Responsibilities: handshake + version check, overworld partner sync
-- (smoothed, sprite-accurate, seam-aware), story gates, partner items, emotes,
-- chat, co-op double battle invites, time-of-day agreement and the HUD.

local CoopNet = require("src.coop.CoopNet")
local CoopLog = require("src.coop.CoopLog")
local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local NPC = require("src.world.NPC")
local Pokemon = require("src.pokemon.Pokemon")
local Strings = require("src.core.Strings")
local Tilt = require("src.render.Tilt")

local CoopManager = {}

-- the real clock, captured before any shared-clock shim (see applyTimeMode)
local realTime, realDate = os.time, os.date
CoopManager.realTime, CoopManager.realDate = realTime, realDate

CoopManager.PROTOCOL = CoopNet.PROTOCOL

CoopManager.net = nil
CoopManager.connected = false
CoopManager.isHost = false
CoopManager.storySync = true       -- Story progress barrier (can be toggled)
CoopManager.partnerHeals = false   -- Sinnoh partner rule: heal after every won co-op battle

-- shared rules: changed by either player, applied on both
local SHARED_RULES = { storySync = true, partnerHeals = true }
local RULE_LABELS = { storySync = "STORY SYNC", partnerHeals = "PARTNER HEALS" }
-- rule name -> function(value, fromPartner) run after it changes
local ruleChanged = {}
function CoopManager.setRule(name, value, fromPartner)
  if not SHARED_RULES[name] then return end
  CoopManager[name] = value and true or false
  if not fromPartner and CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_rules", name = name, value = CoopManager[name] })
  end
  if ruleChanged[name] then pcall(ruleChanged[name], CoopManager[name], fromPartner) end
end

-- A feature module's own shared rule: same wire message, same "host's rules
-- are the session's rules" on linking, shown under `label`.
function CoopManager.addRule(name, label, default, onChange)
  SHARED_RULES[name] = true
  RULE_LABELS[name] = label
  ruleChanged[name] = onChange
  if CoopManager[name] == nil then CoopManager[name] = default and true or false end
end

function CoopManager.ruleLabel(name)
  return RULE_LABELS[name] or name
end

-- Per-frame work of the feature modules, run while linked:
-- fn(dt, game, ow).  Each runs under pcall; a failure is logged once.
CoopManager.tickers = {}
function CoopManager.onTick(name, fn)
  CoopManager.tickers[name] = fn
end
-- ...and the work that runs linked or not (picking a link back up)
CoopManager.idleTickers = {}
function CoopManager.onIdleTick(name, fn)
  CoopManager.idleTickers[name] = fn
end

local function freshPartner()
  return {
    name = nil,
    country = "US",
    timezone = nil,
    map = nil,
    cx = 0, cy = 0,
    tx = nil, ty = nil,
    px = 0, py = 0,
    hopY = 0,
    facing = "down",
    moving = false,
    sprite = nil,
    leadMon = nil,
    partyCount = 0,
    healthy = 0,
    badges = 0,
    emote = nil,
    emoteTimer = 0,
    inBattle = false,
    inDialogue = false,
    busy = false,
    lastSeen = 0,
    posN = 0,
  }
end

CoopManager.partner = freshPartner()

CoopManager.timeOffsetSec = 0
CoopManager.timeMode = nil
CoopManager.localInBattle = false
CoopManager.localInDialogue = false
CoopManager.localEmote = nil
CoopManager.localEmoteTimer = 0
CoopManager.syncTimer = 0
CoopManager.posN = 0
CoopManager.partnerNpc = nil
CoopManager.statusMessage = nil
CoopManager.statusTimer = 0
CoopManager.pendingBattleInvite = nil
CoopManager.activeInviteModal = nil
CoopManager.lobby = nil
-- feature modules loaded at the end of this file (they register into it)
CoopManager.FEATURES = {
  "src.coop.CoopDex",
  "src.coop.CoopRejoin",
  "src.coop.CoopGift",
  "src.coop.CoopSoulLink",
  "src.coop.CoopGear",
  "src.coop.CoopWild",
  "src.coop.CoopCompat",
  "src.coop.CoopWatch",
  "src.coop.CoopVisit",
  "src.coop.CoopDayCare",
  "src.coop.CoopTower",
}
CoopManager.render = nil

local PARTNER_NPC_INDEX = 988
local POS_INTERVAL_MOVING = 1 / 15
local POS_INTERVAL_IDLE = 0.5
local ENGAGE_WINDOW = 8.0
local INVITE_TIMEOUT = 20.0
CoopManager.INVITE_TIMEOUT = INVITE_TIMEOUT
local PARTNER_FRESH = 3.0     -- a partner position older than this is stale

local EMOTE_SYMBOLS = {
  exclaim = "!",
  heart = "<3",
  question = "?",
  music = "#",
  star = "*",
}

local LEADER_BADGES = {
  FALKNER = "ZEPHYRBADGE", BUGSY = "HIVEBADGE", WHITNEY = "PLAINBADGE", MORTY = "FOGBADGE",
  CHUCK = "STORMBADGE", JASMINE = "MINERALBADGE", PRYCE = "GLACIERBADGE", CLAIR = "RISINGBADGE",
  BROCK = "BOULDERBADGE", MISTY = "CASCADEBADGE", LT_SURGE = "THUNDERBADGE", ERIKA = "RAINBOWBADGE",
  JANINE = "SOULBADGE", SABRINA = "MARSHBADGE", BLAINE = "VOLCANOBADGE", BLUE = "EARTHBADGE",
}

-- Gym / League maps that wait for the partner (ids as the Gen 2 data spells them)
local STORY_GATE_MAPS = {
  VIOLET_GYM = true, AZALEA_GYM = true, GOLDENROD_GYM = true, ECRUTEAK_GYM = true,
  CIANWOOD_GYM = true, OLIVINE_GYM = true, MAHOGANY_GYM = true, BLACKTHORN_GYM = true,
  PEWTER_GYM = true, CERULEAN_GYM = true, VERMILION_GYM = true, CELADON_GYM = true,
  FUCHSIA_GYM = true, SAFFRON_GYM = true, SEAFOAM_GYM = true, CINNABAR_GYM = true,
  VIRIDIAN_GYM = true,
  WILLS_ROOM = true, KOGAS_ROOM = true, BRUNOS_ROOM = true, KARENS_ROOM = true,
  LANCES_ROOM = true, HALL_OF_FAME = true,
  -- Red / Blue / Yellow's Elite Four
  LORELEIS_ROOM = true, AGATHAS_ROOM = true, CHAMPIONS_ROOM = true,
}

-- The Elite Four is one corridor: anyone inside it counts as "with you"
local LEAGUE_MAPS = {
  INDIGO_PLATEAU_POKECENTER1_F = true, INDIGO_PLATEAU_POKECENTER_1F = true,
  WILLS_ROOM = true, KOGAS_ROOM = true, BRUNOS_ROOM = true, KARENS_ROOM = true,
  LANCES_ROOM = true, HALL_OF_FAME = true,
  -- Red / Blue / Yellow's Elite Four
  INDIGO_PLATEAU_LOBBY = true, LORELEIS_ROOM = true, AGATHAS_ROOM = true,
  CHAMPIONS_ROOM = true,
}

-- where a partner who entered the HALL OF FAME with you is standing
local HOF_PARTNER_MAPS = { LANCES_ROOM = true, HALL_OF_FAME = true, CHAMPIONS_ROOM = true }

local P2_BLUE_PALETTE = {
  { 255, 255, 255 },
  { 255, 206, 156 },
  { 40, 112, 248 },
  { 0, 0, 0 },
}

-- THE PARTNER WEARS THEIR CARTRIDGE'S COLOUR: the version they picked at
-- the launcher (their hello's `game`) -- RED in red, BLUE in blue, YELLOW in
-- yellow; GOLD in gold, SILVER in silver, CRYSTAL in crystal.  A version
-- not listed keeps the blue above.
local VERSION_OUTFIT = {
  red = { 232, 40, 24 },
  blue = { 40, 112, 248 },
  yellow = { 240, 192, 0 },
  green = { 56, 168, 64 },
  gold = { 224, 160, 16 },
  silver = { 144, 152, 176 },
  crystal = { 56, 192, 232 },
}

-- `game`: whose version to dress (a VISIT avatar names its own); default
-- the partner's
local function partnerPalette(game)
  game = game or (CoopManager.partner and CoopManager.partner.game)
  local outfit = type(game) == "string" and VERSION_OUTFIT[game:lower()]
  if not outfit then return P2_BLUE_PALETTE, "p2_gold_blue" end
  return { P2_BLUE_PALETTE[1], P2_BLUE_PALETTE[2], outfit, P2_BLUE_PALETTE[4] }, "p2_" .. game:lower()
end

-- ---------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function getGame(ow)
  if ow and ow.game then return ow.game end
  local ok, G = pcall(require, "src.core.Game")
  if ok and type(G) == "table" then return G end
  return _G.Game
end
CoopManager.getGame = getGame

local function stackTop(game)
  local stack = game and game.stack
  if not stack then return nil end
  if type(stack.top) == "function" then return stack:top() end
  return stack.states and stack.states[#stack.states]
end

-- Remove one state from anywhere in the stack (an invite or wait modal
-- that is no longer on top must still go when its answer arrives).
local function removeState(game, state)
  local states = game and game.stack and game.stack.states
  if not (states and state) then return false end
  for i = #states, 1, -1 do
    if states[i] == state then
      if i == #states and game.stack.pop then
        game.stack:pop()
      else
        table.remove(states, i)
        if state.exit then pcall(state.exit, state) end
      end
      return true
    end
  end
  return false
end
CoopManager.removeState = removeState

local function playSound(game, name)
  pcall(function()
    require("src.core.Sound").play(game and game.data, name)
  end)
end

local function normMap(m)
  if not m then return nil end
  return (tostring(m):upper():gsub("%s+", ""))
end

local function mapsMatch(m1, m2)
  if not m1 or not m2 then return false end
  return normMap(m1) == normMap(m2)
end
CoopManager.mapsMatch = mapsMatch

-- "NEW_BARK_TOWN" -> "NEW BARK TOWN"
function CoopManager.mapLabel(mapId)
  if not mapId then return "???" end
  local s = tostring(mapId):upper():gsub("_", " "):gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function healthyCount(save)
  local n = 0
  for _, mon in ipairs((save and save.party) or {}) do
    if type(mon) == "table" and (mon.hp or 0) > 0 and not mon.isEgg then n = n + 1 end
  end
  return n
end

local function getLeadMonSummary(save)
  if not save or not save.party or #save.party == 0 then return nil end
  local lead = save.party[1]
  if type(lead) ~= "table" then return nil end
  return {
    species = tostring(lead.species or "POKéMON"),
    level = tonumber(lead.level) or 5,
    hp = tonumber(lead.hp) or 20,
    maxHp = tonumber(lead.maxHp) or (lead.stats and lead.stats.hp) or 20,
  }
end

-- The sheet the local player is actually showing: walking, on the bike or
-- surfing.  The partner sees the same one instead of a walker sliding over
-- the water.
local function localSpriteId(p)
  if not p then return nil end
  if p.surfing and p.surfId then return p.surfId end
  if p.onBike and p.bikeId then return p.bikeId end
  return p.walkId or p.spriteId
end
CoopManager.localSpriteId = localSpriteId

local function localHopY(p)
  if p and p.hopFrames and p.hopFrames > 0 then
    local total = p.hopTotal or 32
    local t = 1 - p.hopFrames / total
    return -math.floor(10 * math.sin(t * math.pi) + 0.5)
  end
  return 0
end

-- Free to answer an invite: the overworld is the screen, and no script,
-- warp or approach is running on it.
local function overworldIdle(game, ow)
  ow = ow or (game and game.overworld)
  if not (game and ow) then return false end
  if stackTop(game) ~= ow then return false end
  if ow.transitioning or ow.engaging or ow.inBattle then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return false end
  return true
end
CoopManager.overworldIdle = overworldIdle

function CoopManager.init()
  if not CoopManager.net then
    CoopManager.net = CoopNet.new()
    CoopLog.info("MANAGER", "CoopManager initialized")
  end
end

local function resetSession()
  -- a session that ends hands everyone their own clock back
  if CoopManager.timeOffsetSec ~= 0 or CoopManager.dayOffsetOverride ~= nil then
    CoopManager.timeOffsetSec = 0
    CoopManager.dayOffsetOverride = nil
    os.time, os.date = realTime, realDate
  end
  CoopManager.timeMode = nil
  CoopManager.connected = false
  CoopManager.partner = freshPartner()
  CoopManager.render = nil
  CoopManager.pendingBattleInvite = nil
  CoopManager.activeInviteModal = nil
  CoopManager.bigBattle = nil
  CoopManager.guestBig = nil
  CoopManager.guestSelect = nil
  CoopManager.partnerEngagingTrainer = nil
  CoopManager.timePrompted = false
  CoopManager.pendingTimePrompt = false
  CoopManager.lastSyncedName = nil
  CoopManager.lastSentPos = nil
end

-- THIS SAVE'S CO-OP NAME.  Trainer names collide (two GOLDs), so the save
-- gets an id of its own the first time it links: the partner is told it in
-- the hello, the transport keeps the host's place for it while the link is
-- down (only the same save may come back into it), and the story remembers
-- which save its events are owed to.
function CoopManager.coopId(save)
  if type(save) ~= "table" then
    local game = getGame()
    save = game and game.save
  end
  if type(save) ~= "table" then return nil end
  if type(save.coopId) ~= "string" or save.coopId == "" then
    save.coopId = CoopNet.newId()
  end
  return save.coopId
end

local function stampIdentity()
  if CoopManager.net then CoopManager.net.identity = CoopManager.coopId() or CoopManager.net.identity end
end

function CoopManager.host(port)
  CoopManager.init()
  resetSession()
  stampIdentity()
  local ok = CoopManager.net:host(port)
  if ok then
    CoopManager.isHost = true
    CoopLog.info("MANAGER", "Hosted on port " .. tostring(port))
  end
  return ok
end

function CoopManager.join(ip, port)
  CoopManager.init()
  resetSession()
  stampIdentity()
  local ok = CoopManager.net:join(ip, port)
  if ok then
    CoopManager.isHost = false
    CoopLog.info("MANAGER", "Joining " .. tostring(ip) .. ":" .. tostring(port))
  end
  return ok
end

function CoopManager.disconnect()
  local game = getGame()
  if CoopManager.net and not CoopManager.net.closed then
    CoopManager.net:send({ type = "coop_bye" })
    CoopManager.net:flush()
    CoopManager.net:shutdown()
  end
  local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
  if okCB and CoopBattle and CoopBattle.onLinkLost then pcall(CoopBattle.onLinkLost, "left") end
  CoopManager.removePartnerNpc(game and game.overworld)
  resetSession()
  CoopLog.info("MANAGER", "Disconnected cleanly")
end

function CoopManager.isConnected()
  return CoopManager.connected == true
     and CoopManager.net ~= nil
     and CoopManager.net:isLinked()
end

function CoopManager.linkState()
  local net = CoopManager.net
  if not net or net.closed then return "off" end
  if net.state == CoopNet.STATE.RECONNECTING then return "reconnecting" end
  if CoopManager.connected and net.stalled then return "weak" end
  if CoopManager.connected then return "ok" end
  return net.state:lower()
end

function CoopManager.getLocalPlayerName(game)
  game = game or getGame()
  local save = game and game.save
  local function good(n) return type(n) == "string" and n ~= "" and n ~= "TRAINER" and n ~= "HOST" and n ~= "GUEST" end
  if save then
    if save.player and good(save.player.name) then return save.player.name end
    if good(save.playerName) then return save.playerName end
    if save.party and save.party[1] and good(save.party[1].ot) then return save.party[1].ot end
  end
  return CoopManager.isHost and "HOST" or "GUEST"
end

-- Game:writeSave calls this after every save
function CoopManager.onLocalSaved(ok)
  if CoopManager.savingForPartner or ok == false then return end
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_save", name = CoopManager.getLocalPlayerName() })
  end
end

function CoopManager.syncTrainerName(game)
  game = game or getGame()
  local playerName = CoopManager.getLocalPlayerName(game)
  if playerName ~= "HOST" and playerName ~= "GUEST" and CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_name_update", name = playerName })
  end
end

function CoopManager.syncTrainerDefeated(npcId, headerEvent, trainerIndex, mapId, oppClass, partyIndex)
  if not CoopManager.storySync then return end
  if not CoopManager.isConnected() then
    -- the partner is owed it all the same: kept for the next link-up
    local game = getGame()
    if game and game.save and type(game.save.coopPartner) == "string" then
      require("src.coop.CoopStory").queue(game.save, { {
        kind = "trainer", npcId = npcId, headerEvent = headerEvent,
        trainerIndex = trainerIndex, mapId = mapId } })
    end
    return
  end
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({
      type = "coop_trainer_defeated",
      npcId = npcId,
      headerEvent = headerEvent,
      trainerIndex = trainerIndex,
      mapId = mapId,
      oppClass = oppClass,
      partyIndex = partyIndex,
    })
  end
end

function CoopManager.syncTrainerEngaging(npcId, trainerIndex, mapId, oppClass, partyIndex)
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({
      type = "coop_trainer_engaging",
      npcId = npcId,
      trainerIndex = trainerIndex,
      mapId = mapId,
      oppClass = oppClass,
      partyIndex = partyIndex,
    })
  end
end

-- ---------------------------------------------------------------------
-- handshake
-- ---------------------------------------------------------------------

local function buildHello(ow, kind)
  local game = getGame(ow)
  local save = game and game.save
  local badgesCount = 0
  if game and game.data and save then
    pcall(function()
      badgesCount = require("src.inventory.Badges").count(game.data, save)
    end)
  end
  local p = ow and ow.player
  return {
    type = kind or "coop_hello",
    proto = CoopManager.PROTOCOL,
    id = CoopManager.coopId(save),
    ver = CoopManager.modVersion(),
    game = GameVersion.get(),
    gen = GameVersion.generation(),
    name = CoopManager.getLocalPlayerName(game),
    sprite = localSpriteId(p),
    -- who they are under the bike or the surf: Kris or the boy
    walk = p and p.walkId or nil,
    country = CoopManager.net.country or "US",
    timezone = CoopManager.net.timezone,
    timeMode = CoopManager.timeMode,
    dayOffset = save and tonumber(save.g2DayOffset) or 0,
    inWorld = (ow ~= nil and ow.map ~= nil),
    map = (ow and ow.map and ow.map.id) or nil,
    cx = p and p.cellX or 0,
    cy = p and p.cellY or 0,
    px = p and p.px or 0,
    py = p and p.py or 0,
    facing = p and p.facing or "down",
    leadMon = getLeadMonSummary(save),
    partyCount = save and save.party and #save.party or 0,
    healthy = healthyCount(save),
    badges = badgesCount,
  }
end

local function sendHello(ow, kind)
  stampIdentity()
  CoopManager.net:send(buildHello(ow, kind))
end
CoopManager.sendHello = sendHello

local function applyPartnerInfo(msg)
  local partner = CoopManager.partner
  -- their live-chat counter restarts with their game
  CoopManager.partnerLiveN = 0
  CoopManager.partnerTyping = nil
  partner.name = msg.name or partner.name or "PARTNER"
  partner.id = type(msg.id) == "string" and msg.id or nil
  partner.version = msg.ver or nil
  partner.sprite = msg.sprite or partner.sprite
  partner.walk = type(msg.walk) == "string" and msg.walk or nil
  partner.country = msg.country or partner.country or "US"
  partner.timezone = msg.timezone or partner.timezone
  partner.game = msg.game
  -- their colour follows the version they play (a rejoin may bring another)
  if CoopManager.partnerNpc and CoopManager.applyPartnerPalette then
    CoopManager.applyPartnerPalette(CoopManager.partnerNpc)
  end
  partner.inWorld = msg.inWorld == true
  if msg.map then
    partner.map = msg.map
    partner.cx, partner.cy = msg.cx or 0, msg.cy or 0
    partner.tx, partner.ty = nil, nil
    partner.px = msg.px or (partner.cx * 16)
    partner.py = msg.py or (partner.cy * 16)
    partner.facing = msg.facing or "down"
    partner.moving = false
    partner.lastSeen = now()
  end
  partner.leadMon = msg.leadMon
  partner.dayOffset = tonumber(msg.dayOffset) or partner.dayOffset or 0
  partner.partyCount = msg.partyCount or 0
  partner.healthy = msg.healthy or partner.partyCount
  partner.badges = msg.badges or 0
end

-- This mod's version, as the manifest says it (main.lua hands it over
-- through package.loaded, which needs none of the co-op modules loaded).
function CoopManager.modVersion()
  local o = package.loaded["pkmultiplayer.options"]
  return tostring(o and o.version or "?")
end

-- Why `msg`'s sender cannot be linked with, or nil: what to show here, and
-- what to tell them (each side names the OTHER one's version, so both see
-- which one has to update; a partner from before 1.4.1-alpha.1 sends none).
local function incompatible(msg)
  if (tonumber(msg.proto) or 1) ~= CoopManager.PROTOCOL then
    local theirs = msg.ver and ("PARTNER HAS V" .. tostring(msg.ver):upper()) or "PARTNER HAS OTHER VERSION"
    return theirs, "PARTNER HAS V" .. CoopManager.modVersion():upper()
  end
  if msg.gen and tonumber(msg.gen) ~= GameVersion.generation() then
    return "PARTNER PLAYS OTHER GAME"
  end
  return nil
end

local function completeHandshake(ow)
  local wasConnected = CoopManager.connected
  CoopManager.connected = true
  if not wasConnected then
    -- each fresh link counts up: a feature that sent its state "once per
    -- link" sends it again
    CoopManager.linkSerial = (CoopManager.linkSerial or 0) + 1
    local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
    if okCB and CoopBattle and CoopBattle.onLinkRestored then pcall(CoopBattle.onLinkRestored) end
  end
  CoopManager.partner.posN = 0
  CoopManager.lastSentPos = nil
  CoopManager.syncTimer = POS_INTERVAL_IDLE -- send our position right away
  CoopManager.net:markSynced()
  if not wasConnected then
    CoopManager.showStatus(string.format("Linked with %s!", CoopManager.partner.name or "PARTNER"), 3)
    playSound(getGame(ow), "Menu")
  end
  CoopManager.lastSyncedName = CoopManager.getLocalPlayerName(getGame(ow))
  -- medicine handed over whose answer never came
  pcall(CoopManager.askHeldItems, getGame(ow))
  -- the host's rules are the session's rules
  if CoopManager.isHost and not wasConnected then
    for name in pairs(SHARED_RULES) do
      CoopManager.net:send({ type = "coop_rules", name = name, value = CoopManager[name] })
    end
  end

  -- Host proposes the clock once per session when the two disagree
  local partnerTz = CoopManager.partner.timezone
  local localTz = CoopManager.net.timezone
  if CoopManager.isHost and not CoopManager.timeMode and partnerTz and localTz
     and math.abs((partnerTz.offsetSec or 0) - (localTz.offsetSec or 0)) >= 1800
     and not CoopManager.timePrompted then
    CoopManager.pendingTimePrompt = true
  end
end

-- ---------------------------------------------------------------------
-- time of day: both players can agree to share one clock.  mode is
-- "host", "guest" or "off" (each keeps their own); every side computes its
-- own offset from the offsets in the message, so the result is identical
-- whichever end decided.
-- ---------------------------------------------------------------------

-- ONE CLOCK FOR THE WHOLE GAME.  Day and night, the night music, the
-- evolutions that need it, the weekly events and the daily ones all read the
-- wall clock in different places (os.date/os.time).  While the two players
-- share a clock, the game's view of "now" is shifted to the agreed one --
-- every reader at once, rather than a handful patched and the rest left on
-- the local time.  A date TABLE passed to os.time, or a time passed to
-- os.date, is converted as given: only "what time is it" moves.
local function installClockShim()
  if (CoopManager.timeOffsetSec or 0) == 0 then
    os.time, os.date = realTime, realDate
    return
  end
  os.time = function(t)
    if t ~= nil then return realTime(t) end
    return realTime() + (CoopManager.timeOffsetSec or 0)
  end
  os.date = function(fmt, t)
    if t == nil then t = os.time() end
    return realDate(fmt or "%c", t)
  end
end
CoopManager.realTime = realTime

-- the weekday Mom's clock picked (Gen 2 save.g2DayOffset), shared too, or
-- the two would disagree about Bug Contest days and the weekday siblings
function CoopManager.dayOffset(save)
  if CoopManager.dayOffsetOverride ~= nil then return CoopManager.dayOffsetOverride end
  return (save and tonumber(save.g2DayOffset)) or 0
end

function CoopManager.applyTimeMode(mode, hostOffsetSec, guestOffsetSec, hostDay, guestDay)
  local localTz = (CoopManager.net and CoopManager.net.timezone) or CoopNet.detectTimezone()
  local localOff = localTz.offsetSec or 0
  local target, day
  if mode == "host" then target, day = tonumber(hostOffsetSec), tonumber(hostDay)
  elseif mode == "guest" then target, day = tonumber(guestOffsetSec), tonumber(guestDay) end
  CoopManager.timeMode = mode
  CoopManager.timeOffsetSec = target and (target - localOff) or 0
  CoopManager.dayOffsetOverride = (mode == "host" or mode == "guest") and day or nil
  installClockShim()
  CoopLog.sync("TIME_SYNC", string.format("mode=%s offset=%ds day=%s", tostring(mode),
               CoopManager.timeOffsetSec, tostring(CoopManager.dayOffsetOverride)))
end

function CoopManager.chooseTimeMode(mode)
  local localTz = (CoopManager.net and CoopManager.net.timezone) or CoopNet.detectTimezone()
  local partnerTz = CoopManager.partner.timezone or localTz
  local hostOff = CoopManager.isHost and localTz.offsetSec or partnerTz.offsetSec
  local guestOff = CoopManager.isHost and partnerTz.offsetSec or localTz.offsetSec
  local game = getGame()
  local myDay = (game and game.save and tonumber(game.save.g2DayOffset)) or 0
  local partnerDay = tonumber(CoopManager.partner.dayOffset) or 0
  local hostDay = CoopManager.isHost and myDay or partnerDay
  local guestDay = CoopManager.isHost and partnerDay or myDay
  CoopManager.applyTimeMode(mode, hostOff, guestOff, hostDay, guestDay)
  if CoopManager.net then
    CoopManager.net:send({ type = "coop_time_sync", mode = mode,
                           hostOffsetSec = hostOff, guestOffsetSec = guestOff,
                           hostDay = hostDay, guestDay = guestDay })
  end
end

local function promptTimezoneChoice(game)
  local localTz = CoopManager.net.timezone
  local partnerTz = CoopManager.partner.timezone or localTz
  local items = {
    { label = string.format("HOST %s", localTz.timeStr or "12:00"), onSelect = function()
      CoopManager.chooseTimeMode("host")
      CoopManager.showStatus("Sharing host clock!", 2.5)
    end },
    { label = string.format("GUEST %s", partnerTz.timeStr or "12:00"), onSelect = function()
      CoopManager.chooseTimeMode("guest")
      CoopManager.showStatus("Sharing guest clock!", 2.5)
    end },
    { label = "OWN CLOCKS", onSelect = function()
      CoopManager.chooseTimeMode("off")
    end },
  }
  game.stack:push(require("src.ui.Menu").new(game, items, {
    tx = 2, ty = 3, tw = 16,
    header = "SHARE CLOCK?",
    cancelable = true,
    onCancel = function() CoopManager.chooseTimeMode("off") end,
  }))
end

-- ---------------------------------------------------------------------
-- partner entity
-- ---------------------------------------------------------------------

-- Where the partner's map sits relative to ours, in pixels: 0,0 on the
-- same map, the seam offset when they stand on a connected map we are
-- drawing (route <-> town), nil when they are somewhere we cannot see.
local function partnerFrameOffset(ow)
  local pm = CoopManager.partner.map
  if not (ow and ow.map and pm) then return nil end
  if mapsMatch(pm, ow.map.id) then return 0, 0 end
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map and mapsMatch(nb.map.id, pm) then
      return nb.ox or ((nb.cx or 0) * 16), nb.oy or ((nb.cy or 0) * 16)
    end
  end
  return nil
end
CoopManager.partnerFrameOffset = partnerFrameOffset

-- ---------------------------------------------------------------------
-- KRIS OR THE BOY, as the partner sees themselves.  An older partner sends
-- no `walk`; their sprite says it while they walk or ride.
-- ---------------------------------------------------------------------

local function isKris(id)
  return type(id) == "string" and id:find("^SPRITE_KRIS") ~= nil
end

function CoopManager.partnerIsKris()
  local p = CoopManager.partner
  return isKris(p.walk or p.sprite)
end

-- The back pic the partner stands behind you in, in a co-op double, when it
-- is not your own: their form's back (Crystal names both), or on Gold and
-- Silver Kris's, cut from a Crystal ROM (lib/Kris.lua).  Returns the path
-- and whether it is true-colour, or nil to share yours.
function CoopManager.partnerBackPic(data, myWalk)
  if not CoopManager.partner.name then return nil end
  local theirs = CoopManager.partnerIsKris()
  if theirs == isKris(myWalk) then return nil end
  local forms = data and data.field and data.field.playerForms
  local form = type(forms) == "table" and forms[theirs and "girl" or "boy"]
  if type(form) == "table" and type(form.back) == "string" then
    return form.back, form.trueColor and true or false
  end
  local K = package.loaded["pkmultiplayer.kris"]
  if theirs and K and K.backPath then return K.backPath, false end
  return nil
end

local function applyPartnerPalette(npc, game)
  if npc and npc.sprite and npc.sprite.setPalette then
    local colors, key = partnerPalette(game)
    pcall(npc.sprite.setPalette, npc.sprite, colors, key)
  end
end
CoopManager.partnerPalette = partnerPalette
CoopManager.applyPartnerPalette = applyPartnerPalette

local function knownSprite(game, id)
  local sprites = game and game.data and game.data.sprites
  if type(id) ~= "string" then return false end
  if not sprites then return true end
  return sprites[id] ~= nil
end

-- What to draw when the partner names a sheet this cartridge does not have
-- (a different game, a mod sprite): this game's own player walker.  The old
-- fallback was a hard-coded SPRITE_CHRIS -- which Gold does not have at all
-- (its hero is SPRITE_RED), so every Gold partner was drawn as a placeholder.
local function defaultPlayerSprite(ow, game)
  local walk = ow and ow.player and ow.player.walkId
  if knownSprite(game, walk) then return walk end
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  if ok and FieldDefaults and FieldDefaults.fieldValue and game and game.data then
    local okV, id = pcall(FieldDefaults.fieldValue, game.data, "playerSprites", "walk")
    if okV and knownSprite(game, id) then return id end
  end
  for _, id in ipairs({ "SPRITE_RED", "SPRITE_CHRIS", "SPRITE_GOLD" }) do
    if knownSprite(game, id) then return id end
  end
  return walk or "SPRITE_RED"
end

local function ensureListed(list, npc)
  for _, n in ipairs(list) do
    if n == npc then return end
  end
  table.insert(list, npc)
end

function CoopManager.removePartnerNpc(ow)
  if ow then
    for _, listName in ipairs({ "npcs", "entities" }) do
      local list = ow[listName]
      if list then
        for i = #list, 1, -1 do
          if list[i] == CoopManager.partnerNpc or (type(list[i]) == "table" and list[i].coopPartner) then
            table.remove(list, i)
          end
        end
      end
    end
  end
  CoopManager.partnerNpc = nil
  local okF, FollowMon = pcall(require, "src.follow.FollowMon")
  if okF then FollowMon.remote = nil end
end

local function makePartnerNpc(ow, game, spriteId)
  local objDef = {
    index = PARTNER_NPC_INDEX,
    name = "COOP_PARTNER",
    sprite = spriteId,
    x = 0, y = 0,
    movement = "STAY",
    range = "NONE",
  }
  local ok, npc = pcall(NPC.new, game.data, ow.map.id, objDef)
  if not ok or not npc then
    CoopLog.error("MANAGER", "Could not build partner sprite " .. tostring(spriteId) .. ": " .. tostring(npc))
    return nil
  end
  npc.coopPartner = true
  npc.passable = true
  npc.hidden = false
  npc.mapId = ow.map.id
  npc.progress = 0
  npc.spriteName = spriteId
  -- position is driven only by CoopManager.updatePartnerRender
  npc.update = function() end
  applyPartnerPalette(npc)
  return npc
end

-- Smooth the partner toward the latest snapshot.  Snapshots arrive ~15 a
-- second; drawing them raw made the sprite stutter and pop, and drawing
-- `moving` as a wall-clock flip-flop made it moonwalk.  Here the sprite
-- chases its target at walking speed (faster when it falls behind), and the
-- walk frame comes from the distance actually travelled, exactly the way a
-- local NPC's walk cycle does.
function CoopManager.updatePartnerRender(ow, dt)
  local partner = CoopManager.partner
  local game = getGame(ow)
  local ox, oy = partnerFrameOffset(ow)
  local fresh = (now() - (partner.lastSeen or 0)) < 30
  if not ox or not fresh then
    CoopManager.removePartnerNpc(ow)
    CoopManager.render = nil
    return
  end

  local targetX = (partner.px or 0) + ox
  local targetY = (partner.py or 0) + oy
  local r = CoopManager.render
  local activeMap = ow.map.id

  if r and r.mapId ~= activeMap then
    -- WE crossed a seam: re-express the drawn position in the new map's
    -- frame using the old map's offset, so the partner does not jump
    local shifted = false
    for _, nb in ipairs(ow.neighbors or {}) do
      if nb.map and mapsMatch(nb.map.id, r.mapId) then
        r.x = r.x + (nb.ox or 0)
        r.y = r.y + (nb.oy or 0)
        shifted = true
        break
      end
    end
    if not shifted then r = nil end
  end

  if not r then
    r = { x = targetX, y = targetY, progress = 0 }
  end
  r.mapId = activeMap

  local dx, dy = targetX - r.x, targetY - r.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local moved = 0
  if dist > 48 then
    -- warp, fly, fall or a long lag spike: snap rather than slide through walls
    r.x, r.y = targetX, targetY
  elseif dist > 0.01 then
    local speed = math.max(60, dist * 9)
    local step = math.min(dist, speed * (dt or 0.016))
    r.x = r.x + dx / dist * step
    r.y = r.y + dy / dist * step
    moved = step
  end

  if moved > 0 or partner.moving then
    r.progress = (r.progress or 0) + moved
  elseif dist <= 0.01 then
    r.progress = 0
  end
  CoopManager.render = r

  -- the entity itself
  local npc = CoopManager.partnerNpc
  local spriteId = partner.sprite
  if not knownSprite(game, spriteId) then spriteId = defaultPlayerSprite(ow, game) end
  if npc and npc.mapId ~= activeMap then
    CoopManager.removePartnerNpc(ow)
    npc = nil
  end
  if not npc then
    npc = makePartnerNpc(ow, game, spriteId)
    if not npc then return end
    CoopManager.partnerNpc = npc
  elseif npc.spriteName ~= spriteId then
    npc.def.sprite = spriteId
    npc.spriteName = spriteId
    pcall(npc.refreshSprite, npc, game.data)
    applyPartnerPalette(npc)
  end

  ow.npcs = ow.npcs or {}
  ow.entities = ow.entities or {}
  ensureListed(ow.npcs, npc)
  ensureListed(ow.entities, npc)

  local rx, ry = math.floor(r.x + 0.5), math.floor(r.y + 0.5)
  npc.hidden = false
  npc.px = rx
  npc.py = ry + (partner.hopY or 0)
  npc.cellX = math.floor((rx + 8) / 16)
  npc.cellY = math.floor((ry + 8) / 16)
  npc.facing = partner.facing or "down"
  local walking = (moved > 0) or (partner.moving and dist > 0.01)
  npc.moving = walking
  npc.progress = math.floor(r.progress or 0)
  npc.stepFlip = math.floor((r.progress or 0) / 16) % 2 == 1

  -- ...and their walking Pokemon behind them
  local okF, FollowMon = pcall(require, "src.follow.FollowMon")
  if okF then
    local info = (not partner.surfing) and partner.follow or nil
    pcall(FollowMon.updateRemote, game, ow, dt, info, ox, oy)
  end
end

-- kept for callers/tests that still ask for it by the old name
local function ensurePartnerNpc(ow)
  CoopManager.updatePartnerRender(ow, 0)
end
CoopManager.ensurePartnerNpc = ensurePartnerNpc

-- ---------------------------------------------------------------------
-- local state
-- ---------------------------------------------------------------------

function CoopManager.showStatus(text, duration)
  CoopManager.statusMessage = text
  CoopManager.statusTimer = duration or 2.5
end

function CoopManager.isLocalInBattle(ow)
  local game = getGame(ow)
  if game and game.stack and game.stack.states then
    for _, st in ipairs(game.stack.states) do
      if type(st) == "table" and (st.kind == "wild" or st.kind == "trainer"
         or (st.phase ~= nil and st.chooseAction ~= nil)) then
        return true
      end
    end
  end
  return false
end

function CoopManager.setInBattle(inBattle)
  local val = (inBattle == true)
  CoopManager.localInBattle = val
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_battle_status", inBattle = val })
  end
end

function CoopManager.isLocalInDialogue(ow)
  local game = getGame(ow)
  if game and game.stack and game.stack.states then
    for _, st in ipairs(game.stack.states) do
      if type(st) == "table" and (st.isTextBox or (st.lines ~= nil and st.page ~= nil)) then
        return true
      end
    end
  end
  return false
end

function CoopManager.setInDialogue(inDialogue)
  local val = (inDialogue == true)
  if CoopManager.localInDialogue ~= val then
    CoopManager.localInDialogue = val
    if CoopManager.connected and CoopManager.net then
      CoopManager.net:send({ type = "coop_dialogue_status", inDialogue = val })
    end
  end
end

-- The partner is approaching or fighting a trainer on the map we are on.
-- Trainer sight is held for that window so both players are not pulled
-- into the same trainer separately.
function CoopManager.isPartnerEngaging(mapId)
  local e = CoopManager.partnerEngagingTrainer
  if not e then return false end
  if not CoopManager.connected then
    CoopManager.partnerEngagingTrainer = nil
    return false
  end
  if mapId == nil then
    local game = getGame()
    local ow = game and game.overworld
    mapId = ow and ow.map and ow.map.id
  end
  if mapId and e.mapId and not mapsMatch(mapId, e.mapId) then return false end
  if CoopManager.partner.inBattle then return true end
  if (now() - (CoopManager.partnerEngagingTrainerTime or 0)) > ENGAGE_WINDOW then
    CoopManager.partnerEngagingTrainer = nil
    return false
  end
  return true
end

function CoopManager.isPartnerInBattle()
  if not CoopManager.isConnected() then return false end
  return CoopManager.partner.inBattle == true
end

-- Same map, idle and heard from recently.  Returns ok, reason.
local function partnerReachable(ow, anywhere)
  local partner = CoopManager.partner
  if not CoopManager.isConnected() then return false, "Partner not linked" end
  if CoopManager.net.stalled then return false, "Partner link is weak" end
  if not anywhere and not (ow and ow.map and mapsMatch(partner.map, ow.map.id)) then
    return false, "Partner is far away"
  end
  if (now() - (partner.lastSeen or 0)) > PARTNER_FRESH then return false, "Partner not responding" end
  if partner.inBattle then return false, "Partner in battle" end
  if partner.busy or partner.inDialogue then return false, "Partner is busy" end
  return true
end

-- ...and with a Pokemon that can fight.  Returns ok, reason.
-- `anywhere`: the partner may be on another map (a BATTLE TOWER battle,
-- whose room is the challenger's alone)
function CoopManager.partnerAvailable(ow, anywhere)
  local ok, why = partnerReachable(ow, anywhere)
  if not ok then return false, why end
  if (CoopManager.partner.healthy or 0) <= 0 then return false, "Partner has no POKéMON" end
  return true
end

function CoopManager.sendEmote(emote)
  if not require("src.coop.CoopEmotes").valid(emote) then return end
  CoopManager.localEmote = emote
  CoopManager.localEmoteTimer = 2.5
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_emote", emote = emote })
  end
end

-- ---------------------------------------------------------------------
-- your medicine, their Pokemon
--
-- There is no "heal both teams" button any more: a free full heal anywhere,
-- for both of you, made every POKEMON CENTER and every potion pointless.
-- What a partner can do instead is what a friend standing next to you could:
-- hand over their OWN medicine.  Pick a POTION, a REVIVE, an ANTIDOTE... from
-- your bag, then one of your partner's Pokemon.
--
-- Their machine owns their party, so it applies the item -- ItemEffects.use,
-- exactly as if they had used it from their own bag -- and answers; the item
-- leaves YOUR bag only when it worked.
--
-- ONE ITEM, ONE HEAL, WHATEVER THE LINK DOES.  The item is set aside the
-- moment it is sent (save.coopItemHeld, by request id) and only given back
-- if the answer says it did not work.  The partner's machine remembers each
-- request it answered (save.coopItemDone): the same request arriving again
-- gets the same answer and heals nobody twice.  An answer that never came
-- (the wait ran out, the link dropped) is asked for again on the next link;
-- a partner that has no record of it never used it, and the item comes back.
-- ---------------------------------------------------------------------

CoopManager.ITEM_REPLY_WAIT = 8
CoopManager.itemRequest = nil

local function newRequestId()
  local r = (love and love.math and love.math.random) and love.math.random(1, 2^30) or math.random(1, 2^30)
  return string.format("I-%d-%d", os.time(), r)
end

local function showLines(game, lines, onDone)
  if not (game and game.stack) then return end
  local text = table.concat(lines or {}, "\f")
  if text == "" then
    if onDone then onDone() end
    return
  end
  game.stack:push(require("src.render.TextBox").new(game, text, onDone))
end

CoopManager.ITEM_DONE_MAX = 64

local function heldItems(save)
  if type(save.coopItemHeld) ~= "table" then save.coopItemHeld = {} end
  return save.coopItemHeld
end

-- the answer to a request whose item was set aside: keep it spent, or give
-- it back.  Returns the item id when this request was still open.
local function settleHeld(game, reqId, worked)
  local save = game and game.save
  if not (save and type(save.coopItemHeld) == "table") then return nil end
  local item = save.coopItemHeld[reqId]
  if not item then return nil end
  save.coopItemHeld[reqId] = nil
  if not worked then require("src.inventory.Bag").add(save, item, 1, game.data) end
  return item
end
CoopManager.settleHeldItem = settleHeld

-- on every new link: ask about each answer that never came
function CoopManager.askHeldItems(game)
  local save = game and game.save
  if not (save and type(save.coopItemHeld) == "table") then return end
  for reqId in pairs(save.coopItemHeld) do
    CoopManager.net:send({ type = "coop_item_query", req = reqId })
  end
end

local function endItemRequest(game)
  local req = CoopManager.itemRequest
  CoopManager.itemRequest = nil
  if req and req.modal then removeState(game, req.modal) end
  return req
end

local function waitForPartner(game, req, line2)
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local pName = string.upper(CoopManager.partner.name or "PARTNER")
  req.modal = CoopWaitModal.new(game, pName, function(reason)
    if CoopManager.itemRequest == req then
      CoopManager.itemRequest = nil
      if req.stage == "use" then
        -- the item stays set aside: the answer may still come
        CoopManager.showStatus(pName .. " hasn't answered yet: your item comes back if it didn't work", 4)
      elseif reason == "timeout" then
        CoopManager.showStatus(pName .. " didn't answer", 2.5)
      end
    end
  end, CoopManager.ITEM_REPLY_WAIT, { lines = { "WAITING " .. pName, line2 }, compact = true })
  game.stack:push(req.modal)
end

local function medicineIds(game)
  local ItemEffects = require("src.inventory.ItemEffects")
  local Bag = require("src.inventory.Bag")
  local out = {}
  for _, id in ipairs(Bag.order(game.save)) do
    if (game.save.inventory[id] or 0) > 0 and ItemEffects.isMedicine(id) then out[#out + 1] = id end
  end
  return out
end
CoopManager.medicineIds = medicineIds

-- one row of the partner's party, as their machine described it
local function partyLabel(m)
  local name = tostring(m.name or "?"):sub(1, 10)
  local right
  if m.egg then right = "EGG"
  elseif (m.hp or 0) <= 0 then right = "FNT"
  elseif m.status then right = string.format("%s%4d", tostring(m.status):sub(1, 3), m.hp or 0)
  else right = string.format("%7s", (m.hp or 0) .. "/" .. (m.maxHp or 0)) end
  return string.format("%-10s%s", name, right)
end

-- Start: the medicine in your bag, then the partner's party.
function CoopManager.useItemOnPartner(game, ow)
  game = game or getGame(ow)
  if CoopManager.isLocalInBattle(ow) then
    CoopManager.showStatus("Can't do that in battle!", 2)
    return
  end
  local ok, why = partnerReachable(ow)
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(game, "Collision")
    return
  end
  local ids = medicineIds(game)
  if #ids == 0 then
    CoopManager.showStatus("No medicine in your BAG!", 2.5)
    playSound(game, "Collision")
    return
  end
  local Menu = require("src.ui.Menu")
  local rows = {}
  for _, id in ipairs(ids) do
    local def = game.data.items[id]
    local itemId = id
    rows[#rows + 1] = {
      label = string.format("%-12s x%d", tostring(def and def.name or id):sub(1, 12), game.save.inventory[id] or 0),
      onSelect = function() CoopManager.askPartnerParty(game, ow, itemId) end,
    }
  end
  game.stack:push(Menu.new(game, rows, {
    tx = 1, ty = 4, tw = 18, cancelable = true, maxVisible = 6,
    header = Strings("ITEM FOR %s:", string.upper(CoopManager.partner.name or "PARTNER"):sub(1, 8)),
  }))
end

function CoopManager.askPartnerParty(game, ow, itemId)
  if CoopManager.itemRequest then return end
  if not partnerReachable(ow) then
    CoopManager.showStatus("Partner is busy", 2.5)
    return
  end
  local req = { id = newRequestId(), item = itemId, stage = "party", ow = ow }
  CoopManager.itemRequest = req
  CoopManager.net:send({ type = "coop_party_req", req = req.id })
  waitForPartner(game, req, "SHOWING TEAM...")
end

-- their party arrived: pick the Pokemon
function CoopManager.onPartnerParty(ow, msg)
  local req = CoopManager.itemRequest
  if not (req and req.stage == "party" and msg.req == req.id) then return end
  local game = getGame(ow)
  endItemRequest(game)
  if msg.refused then
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " is busy", 2.5)
    return
  end
  local Menu = require("src.ui.Menu")
  local rows = {}
  for _, m in ipairs(msg.mons or {}) do
    if type(m) == "table" and tonumber(m.slot) then
      local mon = m
      rows[#rows + 1] = {
        label = partyLabel(m),
        onSelect = function() CoopManager.sendItemUse(game, req.ow or ow, req.item, mon) end,
      }
    end
  end
  if #rows == 0 then return end
  local def = game.data.items[req.item]
  game.stack:push(Menu.new(game, rows, {
    tx = 1, ty = 4, tw = 18, cancelable = true, maxVisible = 6,
    header = Strings("USE %s ON?", tostring(def and def.name or req.item)):sub(1, 18),
  }))
end

function CoopManager.sendItemUse(game, ow, itemId, mon)
  if CoopManager.itemRequest then return end
  if (game.save.inventory[itemId] or 0) <= 0 then return end
  if not partnerReachable(ow) then
    CoopManager.showStatus("Partner is busy", 2.5)
    return
  end
  local req = { id = newRequestId(), item = itemId, stage = "use", ow = ow }
  CoopManager.itemRequest = req
  require("src.inventory.Bag").remove(game.save, itemId, 1)
  heldItems(game.save)[req.id] = itemId
  CoopManager.net:send({ type = "coop_item_use", req = req.id, item = itemId,
                         slot = mon.slot, species = mon.species,
                         from = game.save.player and game.save.player.name })
  waitForPartner(game, req, "USING ITEM...")
end

-- their answer: the item worked (spend it) or it did not
function CoopManager.onItemResult(ow, msg)
  local game = getGame(ow)
  local item = settleHeld(game, msg.req, msg.ok == true)
  local req = CoopManager.itemRequest
  if not (req and req.stage == "use" and msg.req == req.id) then
    -- the answer to a wait that already ran out (or to the last session)
    if item then
      local def = game.data.items[item]
      local name = def and def.name or tostring(item)
      CoopManager.showStatus(msg.ok and Strings("%s worked on your partner's Pokemon", name)
                             or Strings("%s came back to your BAG", name), 3.5)
    end
    return
  end
  endItemRequest(game)
  local lines = type(msg.messages) == "table" and msg.messages or {}
  if msg.ok then
    playSound(game, "Heal_HP")
  elseif msg.refused then
    lines = { Strings("%s can't take\nthat right now.", CoopManager.partner.name or "PARTNER") }
  elseif #lines == 0 then
    lines = { Strings("It won't have\nany effect.") }
  end
  showLines(game, lines)
end

-- ...and the partner's side of it
local function canTakeItem(ow)
  local game = getGame(ow)
  if CoopManager.isLocalInBattle(ow) then return false end
  if not (game and game.save and game.save.party) then return false end
  return true
end

local function partySummary(game)
  local out = {}
  for i, mon in ipairs(game.save.party or {}) do
    if type(mon) == "table" then
      local def = game.data.pokemon and game.data.pokemon[mon.species]
      out[#out + 1] = {
        slot = i, species = mon.species, level = mon.level,
        name = mon.nickname or (def and def.name) or mon.species,
        hp = mon.hp or 0, maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 0,
        status = mon.status, egg = (mon.isEgg or mon.egg) and true or nil,
      }
    end
  end
  return out
end

function CoopManager.onPartyRequest(ow, msg)
  local game = getGame(ow)
  if not canTakeItem(ow) then
    CoopManager.net:send({ type = "coop_party", req = msg.req, refused = true })
    return
  end
  CoopManager.net:send({ type = "coop_party", req = msg.req, mons = partySummary(game) })
end

local function itemDone(save)
  if type(save.coopItemDone) ~= "table" then save.coopItemDone = { order = {} } end
  return save.coopItemDone
end

local function rememberItemAnswer(save, reqId, answer)
  if type(reqId) ~= "string" then return end
  local done = itemDone(save)
  if done[reqId] == nil then done.order[#done.order + 1] = reqId end
  done[reqId] = answer
  while #done.order > CoopManager.ITEM_DONE_MAX do
    done[table.remove(done.order, 1)] = nil
  end
end

function CoopManager.onItemQuery(ow, msg)
  local game = getGame(ow)
  if not (game and game.save) then return end
  local answer = itemDone(game.save)[msg.req]
  local t = { type = "coop_item_result", req = msg.req }
  if type(answer) == "table" then
    t.ok, t.refused = answer.ok, answer.refused
  else
    t.ok, t.unknown = false, true
  end
  CoopManager.net:send(t)
end

function CoopManager.onItemUse(ow, msg)
  local game = getGame(ow)
  if game and game.save then
    local answer = itemDone(game.save)[msg.req]
    if type(answer) == "table" then
      -- the same request again: the same answer, nothing used twice
      CoopManager.net:send({ type = "coop_item_result", req = msg.req, ok = answer.ok,
                             refused = answer.refused, messages = answer.messages })
      return
    end
  end
  local function reply(t)
    t.type, t.req = "coop_item_result", msg.req
    if game and game.save and not t.refused then
      rememberItemAnswer(game.save, msg.req, { ok = t.ok == true, messages = t.messages })
    end
    CoopManager.net:send(t)
  end
  if not canTakeItem(ow) then return reply({ refused = true }) end
  local slot = tonumber(msg.slot)
  local mon = slot and game.save.party[slot]
  local itemId = msg.item
  local ItemEffects = require("src.inventory.ItemEffects")
  -- the party it was picked from is a few seconds old: same slot, same
  -- species, and medicine only -- never a stone or a candy over the wire
  if type(mon) ~= "table" or mon.species ~= msg.species or not game.data.items[itemId]
     or not ItemEffects.isMedicine(itemId) then
    return reply({ refused = true })
  end
  local okUse, kind, messages = pcall(ItemEffects.use, game.data, game.save, itemId, mon, nil, nil, ow)
  if not okUse then
    CoopLog.error("ITEM", "partner item failed: " .. tostring(kind))
    return reply({ ok = false })
  end
  local worked = kind == "consumed"
  reply({ ok = worked, messages = messages })
  if worked then
    local def = game.data.items[itemId]
    local name = mon.nickname or (game.data.pokemon[mon.species] and game.data.pokemon[mon.species].name) or mon.species
    CoopManager.showStatus(string.format("%s used %s on %s!", msg.from or CoopManager.partner.name or "Partner",
                                         def and def.name or itemId, name), 3.5)
    playSound(game, "Heal_HP")
  end
end

-- ---------------------------------------------------------------------
-- warp to partner
--
-- It used to be free, instant and unlimited: from anywhere straight onto the
-- partner, which made walking, FLY and every gate in the game optional.  Now
-- it is FLY with a partner at the other end, not a taxi:
--   * only to a town or city YOU have already been to, the same places FLY
--     would take you (field.flyOrder + save.visited, FlyMenu's rule);
--   * the partner is asked, and has to say YES;
--   * once every WARP_COOLDOWN seconds (ten minutes);
--   * only to a partner standing idle in the overworld (not in a battle, a
--     conversation, a menu or a map transition);
--   * never into a gym or the Elite Four -- those you walk into together
--     (checkStoryWarp);
--   * never while either of you is surfing, or while you are battling or
--     talking.
-- ---------------------------------------------------------------------

CoopManager.WARP_COOLDOWN = 600
CoopManager.WARP_ASK_TIMEOUT = 30
CoopManager.lastWarpAt = nil
CoopManager.warpAsk = nil      -- { id, at }: the request we are waiting on
local warpAskSeq = 0

function CoopManager.warpCooldownLeft()
  if not CoopManager.lastWarpAt then return 0 end
  return math.max(0, CoopManager.WARP_COOLDOWN - (now() - CoopManager.lastWarpAt))
end

function CoopManager.warpAsking()
  local ask = CoopManager.warpAsk
  return ask ~= nil and (now() - ask.at) <= CoopManager.WARP_ASK_TIMEOUT
end

-- A FLY destination this player has been to.
function CoopManager.flyVisited(game, mapId)
  local data, save = game and game.data, game and game.save
  if not (data and save and mapId) then return false end
  local want = normMap(mapId)
  for _, id in ipairs((data.field or {}).flyOrder or {}) do
    if normMap(id) == want then
      local def = data.maps and data.maps[id]
      if not (def and (save.visited or {})[id]) then return false end
      local okMap, Map = pcall(require, "src.world.Map")
      return (okMap and Map.isOutdoor and Map.isOutdoor(def)) or def.tileset == "PLATEAU"
    end
  end
  return false
end

-- ok, reason.  `answered`: the partner has just said yes, so their own
-- yes/no box may still be closing -- that is not "busy".
function CoopManager.canWarpToPartner(ow, answered)
  local p = CoopManager.partner
  if not CoopManager.isConnected() or not p.map then return false, "No partner available" end
  if not (ow and ow.startWarpTo) or ow.transitioning then return false, "Can't warp right now" end
  if CoopManager.isLocalInBattle(ow) then return false, "Can't warp in battle!" end
  local left = CoopManager.warpCooldownLeft()
  if left > 0 then
    local secs = math.ceil(left)
    return false, string.format("Warp ready in %d:%02d", math.floor(secs / 60), secs % 60)
  end
  if mapsMatch(p.map, ow.map and ow.map.id) then return false, "Partner is right here!" end
  if (now() - (p.lastSeen or 0)) > PARTNER_FRESH then return false, "Partner not responding" end
  if p.inBattle or ((p.busy or p.inDialogue) and not answered) then return false, "Partner is busy" end
  if p.surfing then return false, "Partner is on the water" end
  local dest = normMap(p.map) or ""
  if STORY_GATE_MAPS[dest] or LEAGUE_MAPS[dest] then return false, "Can't warp in there!" end
  if not CoopManager.flyVisited(getGame(ow), p.map) then
    return false, "Only to towns you know"
  end
  if CoopManager.isLocalInDialogue(ow) or (ow.player and ow.player.surfing) then
    return false, "Can't warp now!"
  end
  return true
end

-- A asks; B answers YES or NO; A warps on a YES (onWarpReply).
function CoopManager.warpToPartner(ow)
  local ok, why = CoopManager.canWarpToPartner(ow)
  if ok and CoopManager.warpAsking() then ok, why = false, "Waiting for an answer" end
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(getGame(ow), "Collision")
    return false
  end
  warpAskSeq = warpAskSeq + 1
  CoopManager.warpAsk = { id = warpAskSeq, at = now() }
  CoopManager.net:send({ type = "coop_warp_req", id = warpAskSeq })
  CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to warp", 3)
  return true
end

-- B: a request.  Only a player idle in the overworld is asked at all.
function CoopManager.onWarpRequest(ow, msg)
  local game = getGame(ow)
  local function reply(yes, why)
    CoopManager.net:send({ type = "coop_warp_reply", id = msg.id, ok = yes, why = why })
  end
  local idle = game and game.stack and stackTop(game) == ow and ow and not ow.transitioning
               and not CoopManager.isLocalInBattle(ow) and not CoopManager.isLocalInDialogue(ow)
  if not idle then return reply(false, "busy") end
  local TextBox = require("src.render.TextBox")
  local name = CoopManager.partner.name or "Your partner"
  game.stack:push(TextBox.new(game, name .. " wants to\nwarp to you. OK?", nil, {
    defaultNo = true,
    choice = function(yes) reply(yes == true) end,
  }))
end

-- A: the answer.  Checked again, because the world moved while B decided.
function CoopManager.onWarpReply(ow, msg)
  local ask = CoopManager.warpAsk
  if not (ask and ask.id == msg.id) then return end
  CoopManager.warpAsk = nil
  local name = CoopManager.partner.name or "Partner"
  if (now() - ask.at) > CoopManager.WARP_ASK_TIMEOUT then return end
  if not msg.ok then
    CoopManager.showStatus(msg.why == "busy" and (name .. " is busy") or (name .. " said no"), 3)
    return
  end
  local ok, why = CoopManager.canWarpToPartner(ow, true)
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(getGame(ow), "Collision")
    return
  end
  local p = CoopManager.partner
  CoopManager.lastWarpAt = now()
  ow:startWarpTo(p.map, p.cx, p.cy, p.facing or "down")
  playSound(getGame(ow), "Teleport_Exit1")
  CoopManager.net:send({ type = "coop_warp" })
  CoopManager.showStatus("Warped to " .. name .. "!", 2.5)
end

-- A: nobody answered
function CoopManager.tickWarpAsk()
  local ask = CoopManager.warpAsk
  if ask and (now() - ask.at) > CoopManager.WARP_ASK_TIMEOUT then
    CoopManager.warpAsk = nil
    CoopManager.showStatus("No answer from " .. (CoopManager.partner.name or "partner"), 3)
  end
end

-- Story gate check: a gym or the League waits until the partner is with you.
function CoopManager.checkStoryWarp(ow, destMapId)
  if not CoopManager.storySync or not CoopManager.isConnected() then
    return true
  end
  local dest = normMap(destMapId) or ""
  if not STORY_GATE_MAPS[dest] then return true end

  local partnerMap = normMap(CoopManager.partner.map)
  local current = normMap(ow and ow.map and ow.map.id)
  if not partnerMap then return true end

  local together = false
  if partnerMap == dest or partnerMap == current then
    together = true
  elseif LEAGUE_MAPS[dest] and LEAGUE_MAPS[partnerMap] then
    together = true
  else
    -- both somewhere in the same town (the gym's prefix: VIOLET_GYM -> VIOLET)
    local town = dest:match("^(.-)_GYM$")
    if town and partnerMap:find("^" .. town .. "_") and current and current:find("^" .. town .. "_") then
      together = true
    end
  end

  if not together then
    CoopManager.showStatus(string.format("Wait for %s! (%s)",
      CoopManager.partner.name or "partner", CoopManager.mapLabel(CoopManager.partner.map)), 3.5)
    playSound(getGame(ow), "Collision")
    CoopLog.sync("STORY_GATE_BLOCKED", "Blocked from " .. tostring(destMapId) .. "; partner at " .. tostring(CoopManager.partner.map))
    return false
  end
  return true
end

-- ---------------------------------------------------------------------
-- co-op battle invites
-- ---------------------------------------------------------------------

local function wireMon(m)
  if type(m) ~= "table" then return nil end
  local copy = CoopNet.wire(m) or {}
  copy._ownerTag = nil
  return copy
end
CoopManager.wireMon = wireMon

local function newInviteId()
  local r = (love and love.math and love.math.random) and love.math.random(1, 2^30) or math.random(1, 2^30)
  return string.format("%s-%d-%d", CoopManager.isHost and "H" or "G", os.time(), r)
end

-- The cartridge spells leaders three ways: pokecrystal's FALKNER, the Gold
-- import's OPP_LEADER_BUGSY, and plain OPP_LEADER for Falkner (the first
-- class in the group).  The table above only knew the first, so a guest who
-- won a co-op gym battle never got the badge.
function CoopManager.leaderBadgeFor(oppClass)
  if type(oppClass) ~= "string" then return nil end
  local key = oppClass:upper():gsub("^OPP_", ""):gsub("^LEADER_", "")
  if key == "LEADER" then key = "FALKNER" end
  return LEADER_BADGES[key]
end

local function awardLeaderBadge(game, oppClass)
  local badge = CoopManager.leaderBadgeFor(oppClass)
  if not (badge and game and game.save) then return end
  local Badges = require("src.inventory.Badges")
  if Badges.has(game.save, { id = badge }) then return end
  Badges.set(game.save, { id = badge }, true)
  CoopManager.showStatus("Earned the " .. badge .. "!", 3)
end

local function markTrainerBeaten(game, ow, msg)
  local save = game and game.save
  if not save then return end
  save.defeatedTrainers = save.defeatedTrainers or {}
  save.flags = save.flags or {}
  if msg.npcId then save.defeatedTrainers[msg.npcId] = true end
  if msg.headerEvent then save.flags[msg.headerEvent] = true end
  local cur = (game and game.overworld) or ow
  if cur and cur.map and mapsMatch(cur.map.id, msg.mapId) and cur.map.npcs then
    for _, n in ipairs(cur.map.npcs) do
      if (msg.trainerIndex and n.def and n.def.index == msg.trainerIndex) or (msg.npcId and n.id == msg.npcId) then
        save.defeatedTrainers[n.id] = true
        n.frozen = false
      end
    end
  end
end

CoopManager.markTrainerBeaten = markTrainerBeaten

-- The guest's copy of a co-op trainer battle, built from the host's invite
-- (or, for a big battle, its "go"): same trainer, same seed, our three plus
-- the host's.  Its onFinish does what beating that trainer does for a guest
-- who never ran the trainer's own script.
function CoopManager.startGuestBattle(game, ow2, msg, chosenMons)
  local BattleState = require("src.battle.BattleState")
  local wild = msg.battleKind == "wild"
  local tower = type(msg.tower) == "table"
  local p2Battle
  if wild then
    p2Battle = require("src.coop.CoopWild").guestBattle(game, msg)
  elseif tower then
    p2Battle = require("src.coop.CoopTower").guestBattle(game, msg, chosenMons)
  else
    p2Battle = BattleState.newTrainer(game, msg.oppClass, msg.partyIndex or 1)
  end
  p2Battle.isCoopGuest = true
  p2Battle.npcId = msg.npcId
  p2Battle.headerEvent = msg.headerEvent
  p2Battle.trainerIndex = msg.trainerIndex
  p2Battle.mapId = msg.mapId
  p2Battle.coopHandled = true
  -- a battle the story lets you lose (the Cherrygrove rival) must not
  -- white the guest out while the host's scene carries on
  if msg.canLose then p2Battle.canLose = true end

  -- a tower battle keeps its own finish (the partner's team handed back)
  if not tower then
    p2Battle.onFinish = function(result)
      local cOw = game.overworld or ow2
      if wild then
        if cOw and cOw.afterBattle then pcall(cOw.afterBattle, cOw, result, p2Battle) end
        return
      end
      if result == "win" then
        markTrainerBeaten(game, cOw, msg)
        awardLeaderBadge(game, msg.oppClass)
        if cOw and cOw.checkVictoryRewards and msg.oppClass then
          pcall(cOw.checkVictoryRewards, cOw, msg.oppClass, msg.partyIndex)
        end
      end
      if cOw and cOw.afterBattle then
        pcall(cOw.afterBattle, cOw, result, p2Battle)
      end
      -- A BATTLE THE STORY LETS YOU LOSE (Oak's Lab, the Cherrygrove rival)
      -- is no blackout, so afterBattle heals nobody: on the host's screen the
      -- scene's own script does it (OaksLabRivalEndBattleScript HealParty),
      -- and the guest has no script running -- their team was left at 0 HP
      -- with no way to the POKeMON CENTER.  Lost together, healed together.
      if result == "lose" and (msg.canLose or (msg.oppClass == "OPP_RIVAL1"
                               and mapsMatch(msg.mapId, "OAKS_LAB"))) then
        local Pokemon = require("src.pokemon.Pokemon")
        for _, mon in ipairs(game.save and game.save.party or {}) do
          if type(mon) == "table" and not mon.isEgg then pcall(Pokemon.heal, mon) end
        end
      end
      if result == "win" and cOw and cOw.runGen2AfterBattle and msg.trainerIndex
         and cOw.map and mapsMatch(cOw.map.id, msg.mapId) then
        pcall(cOw.runGen2AfterBattle, cOw, msg.trainerIndex)
      end
    end
  end

  local CoopBattle = require("src.coop.CoopBattle")
  CoopBattle.initBattle(p2Battle, chosenMons, msg.localMons, CoopManager.partner, msg.seed, msg.inviteId)
  local cOw = game.overworld or ow2
  if cOw and cOw.pushBattle then
    cOw:pushBattle(p2Battle)
  else
    game.stack:push(p2Battle)
  end
  return p2Battle
end

-- The party picker an accepted invite opens, remembered with its invite so
-- a cancel or a dropped link can take it down again.
function CoopManager.openGuestSelect(game, inviteId, state)
  CoopManager.guestSelect = { inviteId = inviteId, state = state }
  game.stack:push(state)
end

function CoopManager.closeGuestSelect(game, inviteId)
  local gs = CoopManager.guestSelect
  if not gs or (inviteId and gs.inviteId and gs.inviteId ~= inviteId) then return false end
  CoopManager.guestSelect = nil
  return removeState(game, gs.state)
end

function CoopManager.onBattleInviteReceived(ow, msg)
  local game = getGame(ow)
  if not game or not game.stack then return end
  local ow2 = game.overworld or ow

  local function decline(reason)
    CoopManager.net:send({ type = "coop_battle_decline", inviteId = msg.inviteId, reason = reason })
  end

  -- Only an idle player is asked.  The old path shoved the modal over
  -- whatever was open and, on accept, tore every text box and menu off the
  -- stack -- which orphaned the script waiting on them and soft-locked the
  -- game.  Busy is simply a "no" the inviter fights solo on.
  if CoopManager.isLocalInBattle(ow2) then decline("in_battle") return end
  if not overworldIdle(game, ow2) then decline("busy") return end
  local towerCap = type(msg.tower) == "table" and tonumber(msg.tower.cap) or nil
  if not towerCap and not (ow2 and ow2.map and mapsMatch(ow2.map.id, msg.mapId or CoopManager.partner.map)) then
    decline("far") return
  end
  if healthyCount(game.save) <= 0 then decline("no_mons") return end
  local eligible = (game.save and game.save.party) or {}
  if towerCap then
    eligible = require("src.coop.CoopTower").eligible(eligible, towerCap)
    if #eligible == 0 then decline("no_mons") return end
  end

  local pName = string.upper(CoopManager.partner.name or "PARTNER")
  local tName = string.upper(msg.trainerName or "TRAINER")
  local CoopBattleInviteModal = require("src.coop.CoopBattleInviteModal")
  local inviteModal
  inviteModal = CoopBattleInviteModal.new(game, pName, tName, function()
    CoopManager.activeInviteModal = nil
    local CoopBattleSelect = require("src.coop.CoopBattleSelect")
    CoopManager.openGuestSelect(game, msg.inviteId, CoopBattleSelect.new(game, eligible, function(chosenMons)
      CoopManager.guestSelect = nil
      if not CoopManager.isConnected() then
        CoopManager.showStatus("Partner link lost", 2.5)
        return
      end
      local wired = {}
      for _, m in ipairs(chosenMons) do wired[#wired + 1] = wireMon(m) end
      CoopManager.net:send({ type = "coop_battle_accept", inviteId = msg.inviteId, chosenMons = wired })

      CoopManager.startGuestBattle(game, ow2, msg, chosenMons)
      CoopManager.showStatus("Co-op battle with " .. pName .. "!", 3)
    end, function()
      CoopManager.guestSelect = nil
      decline("declined")
      CoopManager.showStatus("Declined co-op battle", 2)
    end))
  end, function()
    CoopManager.activeInviteModal = nil
    decline("declined")
    CoopManager.showStatus("Declined co-op battle", 2)
  end)
  inviteModal.inviteId = msg.inviteId
  inviteModal.timeout = INVITE_TIMEOUT

  CoopManager.activeInviteModal = inviteModal
  game.stack:push(inviteModal)
end

local function startPendingBattle(ow, pending, partnerChosen)
  local battle = pending.battle
  if partnerChosen then
    local CoopBattle = require("src.coop.CoopBattle")
    CoopBattle.initBattle(battle, pending.localChosen, partnerChosen, CoopManager.partner, pending.seed, pending.inviteId)
  end
  battle.coopHandled = true
  ow:pushBattle(battle, pending.opts)
end

function CoopManager.onBattleAccepted(ow, msg)
  local pending = CoopManager.pendingBattleInvite
  if not pending or (msg.inviteId and pending.inviteId ~= msg.inviteId) then
    -- we already gave up waiting and fought solo; the partner is now inside
    -- a battle we are not in, so tell them to carry on alone
    CoopManager.net:send({ type = "coop_battle_abort", inviteId = msg.inviteId })
    return
  end
  local game = getGame(ow)
  removeState(game, pending.waitModal)
  CoopManager.pendingBattleInvite = nil
  CoopManager.partnerEngagingTrainer = nil
  startPendingBattle(pending.ow or ow, pending, msg.chosenMons or {})
  CoopManager.showStatus("Partner joined! Battle start!", 3)
end

local DECLINE_TEXT = {
  in_battle = "Partner in battle. Solo!",
  busy = "Partner is busy. Solo!",
  far = "Partner too far. Solo!",
  no_mons = "Partner can't fight. Solo!",
  timeout = "No answer. Battling solo!",
}

function CoopManager.onBattleDeclined(ow, msg)
  local pending = CoopManager.pendingBattleInvite
  local big = CoopManager.bigBattle
  if not pending and big and msg and msg.inviteId == big.inviteId then
    -- turned down while the leader is still talking: this battle goes solo
    big.declined = true
    CoopManager.showStatus(DECLINE_TEXT[msg.reason] or "Partner won't join. Solo!", 2.5)
    return
  end
  if not pending then return end
  if msg and msg.inviteId and pending.inviteId and msg.inviteId ~= pending.inviteId then return end
  local game = getGame(ow)
  removeState(game, pending.waitModal)
  CoopManager.pendingBattleInvite = nil
  CoopManager.partnerEngagingTrainer = nil
  CoopManager.showStatus(DECLINE_TEXT[msg and msg.reason] or "Partner declined. Solo!", 2.5)
  startPendingBattle(pending.ow or ow, pending, nil)
end

-- Inviter gives up (B in the wait modal, or the timeout)
function CoopManager.cancelPendingInvite(ow, reason)
  local pending = CoopManager.pendingBattleInvite
  if not pending then return end
  CoopManager.pendingBattleInvite = nil
  CoopManager.partnerEngagingTrainer = nil
  if CoopManager.net then
    CoopManager.net:send({ type = "coop_battle_cancel", inviteId = pending.inviteId })
  end
  local game = getGame(ow)
  removeState(game, pending.waitModal)
  if reason == "timeout" then CoopManager.showStatus(DECLINE_TEXT.timeout, 2.5) end
  startPendingBattle(pending.ow or ow, pending, nil)
end

function CoopManager.onBattleCancelled(ow, msg)
  local game = getGame(ow)
  -- the party picker opened from the invite goes first: left up, it held
  -- the player in place after the inviter went solo or dropped, and a pick
  -- made in it joined a battle nobody else was in
  local picking = CoopManager.closeGuestSelect(game, msg.inviteId)
  local gb = CoopManager.guestBig
  if gb and (not msg.inviteId or gb.inviteId == msg.inviteId) then
    removeState(game, gb.modal)
    CoopManager.guestBig = nil
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " went solo", 2.5)
  end
  local modal = CoopManager.activeInviteModal
  if modal and (not msg.inviteId or modal.inviteId == msg.inviteId) then
    removeState(game, modal)
    CoopManager.activeInviteModal = nil
    CoopManager.showStatus("Partner cancelled invite", 2.5)
  elseif picking and not gb then
    CoopManager.showStatus("Partner cancelled invite", 2.5)
  end
  local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
  if okCB and CoopBattle and CoopBattle.onPartnerLeft then
    CoopBattle.onPartnerLeft(msg)
  end
  CoopManager.partnerEngagingTrainer = nil
end

-- ---------------------------------------------------------------------
-- BIG BATTLES: gym leaders, the Elite Four, the Champion, the rival, Red,
-- the Rocket executives.  The choice is made BEFORE the trainer starts
-- talking, so the partner can read the whole scene with you:
--
--   1. the script that leads to the battle starts (you talked to FALKNER)
--      with the partner on the map: CO-OP or SOLO, there and then;
--   2. CO-OP invites the partner at once.  They pick their three while the
--      leader is still speaking and read the lines along (CoopStory);
--   3. whoever is done first waits for the other -- you at the battle with
--      your three picked (60s), them with their team ready (150s) -- and the
--      battle starts the moment both are.  A timeout or B is a solo battle.
-- ---------------------------------------------------------------------

local BIG_PATTERNS = { "^OPP_LEADER", "ELITE_FOUR", "^OPP_CHAMPION$", "RIVAL",
                       "PKMN_TRAINER_RED", "ROCKET_EXECUTIVE", "GIOVANNI" }

function CoopManager.isBigBattleClass(oppClass, save)
  if type(oppClass) ~= "string" then return false end
  local c = oppClass:upper()
  local big = CoopManager.leaderBadgeFor(c) ~= nil
  for _, pat in ipairs(BIG_PATTERNS) do
    if c:find(pat) then big = true end
  end
  if not big then return false end
  -- a leader whose badge you already hold is not fought again
  local badge = CoopManager.leaderBadgeFor(c)
  if badge and save then
    local ok, Badges = pcall(require, "src.inventory.Badges")
    if ok and Badges.has(save, { id = badge }) then return false end
  end
  return true
end

function CoopManager.trainerDisplayName(game, oppClass, partyIndex)
  local rec = game and game.data and game.data.trainers and game.data.trainers[oppClass]
  local names = rec and rec.partyNames
  local name = names and (names[tonumber(partyIndex) or 1] or names[1])
  if type(name) ~= "string" or name == "" or name:find("?", 1, true) then
    name = tostring(oppClass or "TRAINER"):gsub("^OPP_", ""):gsub("^LEADER_", ""):gsub("_", " ")
    if name == "LEADER" then name = "FALKNER" end
    if name:find("^RIVAL") then name = (game and game.save and game.save.player and game.save.player.rival) or "RIVAL" end
  end
  return string.upper(name)
end

-- Run from CoopStory.begin, inside the script's coroutine: asks, and lets
-- the script carry on into the trainer's dialogue.
function CoopManager.offerBigBattle(ctx, oppClass, partyIndex)
  local game, runner, ow = ctx.game, ctx.runner, ctx.overworld
  if not (game and runner and ow) then return end
  local ok = CoopManager.partnerAvailable(ow)
  if not ok then return end
  local name = CoopManager.trainerDisplayName(game, oppClass, partyIndex)
  local choice = "solo"
  local Menu = require("src.ui.Menu")
  game.stack:push(Menu.new(game, {
    { label = Strings("CO-OP"), onSelect = function() choice = "coop" runner:resume() end },
    { label = Strings("SOLO"), onSelect = function() choice = "solo" runner:resume() end },
  }, { tx = 3, ty = 4, tw = 14, header = ("VS " .. name):sub(1, 12), cancelable = true,
       onCancel = function() choice = "solo" runner:resume() end }))
  runner:yield()

  if choice == "coop" and CoopManager.isConnected() then
    local inviteId = newInviteId()
    CoopManager.bigBattle = { inviteId = inviteId, oppClass = oppClass, partyIndex = partyIndex,
                              name = name, at = now() }
    CoopManager.net:send({ type = "coop_bigbattle_invite", inviteId = inviteId, oppClass = oppClass,
                           partyIndex = partyIndex, trainerName = name, mapId = ow.map.id })
    CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to join!", 2.5)
  else
    CoopManager.bigBattle = { solo = true, oppClass = oppClass, partyIndex = partyIndex }
  end
end

local function bigBattleGo(pending)
  local battle = pending.battle
  CoopManager.net:send({
    type = "coop_bigbattle_go",
    inviteId = pending.inviteId,
    oppClass = battle.oppClass,
    partyIndex = battle.partyIndex or 1,
    trainerName = pending.trainerName,
    npcId = battle.npcId or (battle.npc and battle.npc.id),
    headerEvent = battle.headerEvent,
    trainerIndex = battle.trainerIndex,
    mapId = battle.mapId or (pending.ow and pending.ow.map and pending.ow.map.id),
    canLose = battle.canLose or nil,
    seed = pending.seed,
    localMons = pending.wired,
  })
  local game = getGame(pending.ow)
  removeState(game, pending.waitModal)
  CoopManager.pendingBattleInvite = nil
  CoopManager.partnerEngagingTrainer = nil
  startPendingBattle(pending.ow, pending, pending.partnerMons)
  CoopManager.showStatus("Together! Battle start!", 2.5)
end

function CoopManager.hostBigBattle(ow, battle, opts, big)
  if big.solo then return false end
  if big.declined or not CoopManager.isConnected() then
    CoopManager.showStatus("Partner not here. Solo!", 2.5)
    return false
  end
  local game = getGame(ow)
  local CoopBattleSelect = require("src.coop.CoopBattleSelect")
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local function solo() ow:pushBattle(battle, opts) end
  game.stack:push(CoopBattleSelect.new(game, game.save.party, function(chosenMons)
    if not CoopManager.isConnected() then
      CoopManager.showStatus("Partner link lost. Solo!", 2.5)
      solo()
      return
    end
    local wired = {}
    for _, m in ipairs(chosenMons) do wired[#wired + 1] = wireMon(m) end
    local pending = {
      battle = battle, localChosen = chosenMons, wired = wired, opts = opts, ow = ow,
      seed = (love and love.math and love.math.random) and love.math.random(1, 1000000) or math.random(1, 1000000),
      inviteId = big.inviteId, trainerName = big.name, big = true, partnerMons = big.partnerMons,
    }
    CoopManager.pendingBattleInvite = pending
    if pending.partnerMons then
      bigBattleGo(pending)
      return
    end
    local pName = string.upper(CoopManager.partner.name or "PARTNER")
    pending.waitModal = CoopWaitModal.new(game, pName, function(reason)
      CoopManager.cancelPendingInvite(ow, reason)
    end, 60, { lines = { "WAITING " .. pName, "PICKING TEAM..." } })
    game.stack:push(pending.waitModal)
  end, solo))
  return true
end

function CoopManager.onBigBattleReady(ow, msg)
  local pending = CoopManager.pendingBattleInvite
  if pending and pending.big and pending.inviteId == msg.inviteId then
    pending.partnerMons = msg.chosenMons or {}
    bigBattleGo(pending)
    return
  end
  local big = CoopManager.bigBattle
  if big and big.inviteId == msg.inviteId then
    big.partnerMons = msg.chosenMons or {}
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " is ready!", 2.5)
    return
  end
  -- we already went solo
  CoopManager.net:send({ type = "coop_battle_cancel", inviteId = msg.inviteId })
end

function CoopManager.onBigBattleInvite(ow, msg)
  local game = getGame(ow)
  if not (game and game.stack) then return end
  local ow2 = game.overworld or ow
  local function decline(reason)
    CoopManager.net:send({ type = "coop_battle_decline", inviteId = msg.inviteId, reason = reason })
  end
  if CoopManager.isLocalInBattle(ow2) then decline("in_battle") return end
  if not overworldIdle(game, ow2) then decline("busy") return end
  if not (ow2 and ow2.map and mapsMatch(ow2.map.id, msg.mapId)) then decline("far") return end
  if healthyCount(game.save) <= 0 then decline("no_mons") return end

  local pName = string.upper(CoopManager.partner.name or "PARTNER")
  local tName = string.upper(msg.trainerName or "TRAINER")
  local CoopBattleInviteModal = require("src.coop.CoopBattleInviteModal")
  local modal = CoopBattleInviteModal.new(game, pName, tName, function()
    CoopManager.activeInviteModal = nil
    local CoopBattleSelect = require("src.coop.CoopBattleSelect")
    local CoopWaitModal = require("src.coop.CoopWaitModal")
    CoopManager.openGuestSelect(game, msg.inviteId, CoopBattleSelect.new(game, game.save.party or {}, function(chosenMons)
      CoopManager.guestSelect = nil
      if not CoopManager.isConnected() then
        CoopManager.showStatus("Partner link lost", 2.5)
        return
      end
      local wired = {}
      for _, m in ipairs(chosenMons) do wired[#wired + 1] = wireMon(m) end
      CoopManager.net:send({ type = "coop_bigbattle_ready", inviteId = msg.inviteId, chosenMons = wired })
      local gb = { inviteId = msg.inviteId, chosen = chosenMons }
      gb.modal = CoopWaitModal.new(game, pName, function(reason)
        if CoopManager.guestBig == gb then
          CoopManager.guestBig = nil
          decline("declined")
        end
      end, 150, { compact = true, lines = { "READ ALONG...", "B: LEAVE BATTLE" } })
      CoopManager.guestBig = gb
      game.stack:push(gb.modal)
    end, function()
      CoopManager.guestSelect = nil
      decline("declined")
    end))
  end, function()
    CoopManager.activeInviteModal = nil
    decline("declined")
  end)
  modal.inviteId = msg.inviteId
  modal.timeout = 30
  modal.lines = { pName, ("FACES " .. tName):sub(1, 15) .. "!", "WANT TO JOIN?" }
  CoopManager.activeInviteModal = modal
  game.stack:push(modal)
end

function CoopManager.onBigBattleGo(ow, msg)
  local game = getGame(ow)
  local gb = CoopManager.guestBig
  if not gb or gb.inviteId ~= msg.inviteId then
    -- the host thinks we are in; we are not -- they fight with the AI
    CoopManager.net:send({ type = "coop_battle_abort", inviteId = msg.inviteId })
    return
  end
  CoopManager.guestBig = nil
  gb.modal.done = true
  removeState(game, gb.modal)
  CoopManager.startGuestBattle(game, game.overworld or ow, msg, gb.chosen)
  CoopManager.showStatus("Together! Battle start!", 2.5)
end

function CoopManager.promptCoopBattle(ow, battle, opts)
  if not CoopManager.connected or not battle or battle.coopHandled then
    return false
  end
  -- Wild battles are solo, unless WILD TOGETHER asks the partner along
  -- (src/coop/CoopWild.lua)
  if battle.kind == "wild" then
    local okW, CoopWild = pcall(require, "src.coop.CoopWild")
    return okW and CoopWild.offer(ow, battle, opts) or false
  end
  if battle.kind ~= "trainer" then
    return false
  end
  battle.coopHandled = true

  -- a big battle (gym, League, rival...) was settled before its dialogue
  local big = CoopManager.bigBattle
  if big and big.oppClass == battle.oppClass then
    CoopManager.bigBattle = nil
    return CoopManager.hostBigBattle(ow, battle, opts, big)
  end

  local tower = battle.battleTower == true
  local ok, why = CoopManager.partnerAvailable(ow, tower)
  if not ok then
    if why ~= "Partner is far away" then CoopManager.showStatus(why .. ". Solo!", 2.5) end
    return false
  end

  local game = getGame(ow)
  if not (game and game.stack) then return false end
  local towerInfo = tower and require("src.coop.CoopTower").inviteInfo(game, battle) or nil
  if tower and not towerInfo then return false end
  local CoopBattleSelect = require("src.coop.CoopBattleSelect")
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local save = game.save

  local function solo()
    ow:pushBattle(battle, opts)
  end

  local items = {
    { label = Strings("CO-OP DOUBLE"), onSelect = function()
      if not CoopManager.isConnected() then
        CoopManager.showStatus("Partner link lost", 2.5)
        solo()
        return
      end
      game.stack:push(CoopBattleSelect.new(game, save.party, function(chosenMons)
        local stillOk, whyNot = CoopManager.partnerAvailable(ow, tower)
        if not stillOk then
          CoopManager.showStatus(whyNot .. ". Solo!", 2.5)
          solo()
          return
        end
        local wired = {}
        for _, m in ipairs(chosenMons) do wired[#wired + 1] = wireMon(m) end

        local seed = (love and love.math and love.math.random) and love.math.random(1, 1000000) or math.random(1, 1000000)
        local inviteId = newInviteId()
        local waitModal = CoopWaitModal.new(game, CoopManager.partner.name, function(reason)
          CoopManager.cancelPendingInvite(ow, reason)
        end, INVITE_TIMEOUT + 2)

        CoopManager.pendingBattleInvite = {
          battle = battle,
          localChosen = chosenMons,
          opts = opts,
          seed = seed,
          inviteId = inviteId,
          waitModal = waitModal,
          ow = ow,
        }
        game.stack:push(waitModal)

        CoopManager.net:send({
          type = "coop_battle_invite",
          inviteId = inviteId,
          battleKind = "trainer",
          oppClass = battle.oppClass,
          partyIndex = battle.partyIndex or 1,
          trainerName = (battle.trainer and battle.trainer.name) or battle.trainerName or "TRAINER",
          npcId = battle.npcId or (battle.npc and battle.npc.id),
          headerEvent = battle.headerEvent,
          trainerIndex = battle.trainerIndex,
          canLose = battle.canLose or nil,
          mapId = battle.mapId or (ow and ow.map and ow.map.id),
          seed = seed,
          localMons = wired,
          tower = towerInfo,
        })
      end, solo))
    end },
    { label = Strings("SOLO BATTLE"), onSelect = solo },
  }

  game.stack:push(require("src.ui.Menu").new(game, items, {
    tx = 3,
    ty = 4,
    tw = 14,
    header = "BATTLE MODE:",
    cancelable = true,
    onCancel = solo,
  }))
  return true
end

-- ---------------------------------------------------------------------
-- chat & interaction
-- ---------------------------------------------------------------------

-- LIVE CHAT.  The partner sees what you type AS you type it: every change in
-- the chat box goes out on the fast channel (unreliable, sequenced, never
-- stuck behind a battle turn), at most every LIVE_EVERY seconds, and when
-- the typing pauses the latest text is repeated on the reliable channel in
-- case the last fast packet was lost.  Every live packet carries a counter
-- so a late one never resurrects text that was already sent or cancelled.
--
-- Messages are kept in a short log the chat box shows, so nothing that
-- arrives while you are typing is missed, and a message's time on screen
-- only runs while it is actually visible (not behind a dialogue box).

CoopManager.CHAT_MAX = 64
CoopManager.CHAT_LOG_MAX = 8
CoopManager.LIVE_EVERY = 0.05
CoopManager.LIVE_SETTLE = 0.35
CoopManager.TYPING_STALE = 5
CoopManager.chatLog = {}
-- name -> fn(sender, text, own): every line the chat shows (visitors hear it)
CoopManager.chatListeners = {}
-- set while this game VISITS someone else's (src/coop/CoopVisit.lua): the
-- chat goes there instead of to a co-op partner
CoopManager.chatRoute = nil
CoopManager.partnerTyping = nil
CoopManager.partnerLiveN = 0
CoopManager.liveOut = { n = 0, at = -1 }
CoopManager.chatShown = false

local function chatDuration(text) return math.min(9, 3 + #text * 0.09) end

-- is a co-op double the screen on top?  (chat works there too)
local function coopBattleOnTop(game)
  local top = stackTop(game)
  return top ~= nil and top.coopDouble == true and top.chooseAction ~= nil
end
CoopManager.coopBattleOnTop = coopBattleOnTop

function CoopManager.openChat(game, ow)
  game = game or getGame(ow)
  if not game or not game.stack then return end
  if not (CoopManager.connected or CoopManager.chatRoute) then return end

  local top = stackTop(game)
  if top and (top.isChatBox or top.isTextBox or (top.lines ~= nil and top.page ~= nil)) then
    return
  end
  if not coopBattleOnTop(game) then
    local curOw = ow or game.overworld
    if curOw and (curOw.engaging or curOw.transitioning or curOw.inBattle) then
      return
    end
  end
  local CoopChatBox = require("src.coop.CoopChatBox")
  game.stack:push(CoopChatBox.new(game))
  CoopManager.sendChatLive("")
end

local function sendLiveNow(reliable)
  local live = CoopManager.liveOut
  local net = CoopManager.net
  if not (CoopManager.connected and net and live.text ~= nil) then return end
  live.n = live.n + 1
  live.at = now()
  live.sentText = live.text
  live.settled = reliable or false
  net:send({ type = "coop_chat_live", n = live.n, text = live.text }, (not reliable) and { fast = true } or nil)
end

-- the chat box reports its text on every change; nil + stop = box closed
function CoopManager.sendChatLive(text, stop)
  local live = CoopManager.liveOut
  if stop then
    live.text, live.sentText, live.settled = nil, nil, true
    if CoopManager.connected and CoopManager.net then
      live.n = live.n + 1
      CoopManager.net:send({ type = "coop_chat_live", n = live.n, stop = true })
    end
    return
  end
  text = tostring(text or ""):sub(1, CoopManager.CHAT_MAX)
  if text == live.sentText and live.text ~= nil then return end
  live.text = text
  if now() - (live.at or -1) >= CoopManager.LIVE_EVERY then sendLiveNow(false) end
end

-- once a frame: a change held back by the rate limit goes out, and a pause
-- in the typing is confirmed on the reliable channel
local function tickLive()
  local live = CoopManager.liveOut
  if live.text == nil then return end
  local t = now()
  if live.text ~= live.sentText then
    if t - (live.at or -1) >= CoopManager.LIVE_EVERY then sendLiveNow(false) end
  elseif not live.settled and t - (live.at or 0) >= CoopManager.LIVE_SETTLE then
    sendLiveNow(true)
  end
end

function CoopManager.onChatLive(msg)
  local n = tonumber(msg.n) or 0
  if n <= (CoopManager.partnerLiveN or 0) then return end
  CoopManager.partnerLiveN = n
  if msg.stop then
    CoopManager.partnerTyping = nil
    return
  end
  CoopManager.partnerTyping = { text = tostring(msg.text or ""):sub(1, CoopManager.CHAT_MAX), at = now() }
end

function CoopManager.sendChat(text)
  text = text and text:match("^%s*(.-)%s*$") or ""
  local live = CoopManager.liveOut
  live.text, live.sentText, live.settled = nil, nil, true
  if text == "" then
    CoopManager.sendChatLive(nil, true)
    return
  end
  text = text:sub(1, CoopManager.CHAT_MAX)

  local game = getGame()
  local sender = CoopManager.getLocalPlayerName(game) or "ME"
  if not CoopManager.connected and CoopManager.chatRoute then
    pcall(CoopManager.chatRoute, sender, text)
  end
  if CoopManager.connected and CoopManager.net then
    -- the counter goes with it: the partner drops the typing line for good
    live.n = live.n + 1
    CoopManager.net:send({ type = "coop_chat", sender = sender, text = text, n = live.n })
  end
  CoopManager.onChatReceived(sender, text, true)
end

function CoopManager.onChatReceived(sender, text, own, n)
  if type(text) ~= "string" or text == "" then return end
  sender = string.upper(tostring(sender or "PARTNER"))
  if #sender > 8 then sender = sender:sub(1, 8) end
  text = text:sub(1, CoopManager.CHAT_MAX)
  if not own then
    CoopManager.partnerTyping = nil
    n = tonumber(n)
    if n and n > (CoopManager.partnerLiveN or 0) then CoopManager.partnerLiveN = n end
  end
  local log = CoopManager.chatLog
  log[#log + 1] = { sender = sender, text = text, own = own and true or false }
  while #log > CoopManager.CHAT_LOG_MAX do table.remove(log, 1) end
  CoopManager.activeChatMessage = {
    sender = sender,
    text = text,
    timer = chatDuration(text),
    own = own and true or false,
  }
  if not own then playSound(getGame(), "Menu") end
  for _, fn in pairs(CoopManager.chatListeners) do pcall(fn, sender, text, own) end
end

function CoopManager.interact(game, ow)
  local partner = CoopManager.partner
  local pName = partner.name or "PARTNER"
  local Menu = require("src.ui.Menu")
  local items = {
    { label = Strings("HIGH FIVE!"), onSelect = function()
      CoopManager.sendEmote("heart")
      CoopManager.showStatus("High five with " .. pName .. "!", 2.5)
    end },
    { label = Strings("USE ITEM"), onSelect = function()
      CoopManager.useItemOnPartner(game, ow)
    end },
    { label = Strings("CHAT"), onSelect = function()
      CoopManager.openChat(game, ow)
    end },
    { label = Strings("TRADE"), onSelect = function()
      require("src.coop.CoopLink").invite(game, "trade")
    end },
    { label = Strings("BATTLE"), onSelect = function()
      require("src.coop.CoopLink").invite(game, "battle")
    end },
  }
  game.stack:push(Menu.new(game, items, {
    tx = 2,
    ty = 4,
    tw = 16,
    cancelable = true,
  }))
end

-- ---------------------------------------------------------------------
-- message handlers
-- ---------------------------------------------------------------------

local H = {}

H.net_connect = function(ow, msg)
  -- both ends say hello as soon as the link is up; each hello is answered
  -- with a welcome, and either one completes the handshake
  if msg and msg.resumed == false then
    pcall(function() require("src.coop.CoopLink").onNewSession() end)
  end
  sendHello(ow, "coop_hello")
end

H.net_disconnect = function(ow, msg)
  local wasConnected = CoopManager.connected
  CoopManager.connected = false
  CoopManager.removePartnerNpc(ow)
  CoopManager.render = nil
  local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
  if okCB and CoopBattle and CoopBattle.onLinkLost then pcall(CoopBattle.onLinkLost, msg.reason) end
  pcall(function() require("src.coop.CoopLink").onLinkLost(getGame(ow), msg.reason) end)
  if CoopManager.pendingBattleInvite then
    pcall(CoopManager.onBattleDeclined, ow, { inviteId = CoopManager.pendingBattleInvite.inviteId, reason = "far" })
  end
  if CoopManager.activeInviteModal or CoopManager.guestBig or CoopManager.guestSelect then
    pcall(CoopManager.onBattleCancelled, ow, {})
  end
  if CoopManager.bigBattle and not CoopManager.bigBattle.solo then
    CoopManager.bigBattle.declined = true
  end
  if msg.reason == "lost" then
    CoopManager.showStatus("Link lost. Reconnecting...", 3)
  elseif wasConnected or msg.reason == "left" then
    CoopManager.showStatus(string.format("%s left the session", CoopManager.partner.name or "Partner"), 3)
  elseif msg.reason == "unreachable" then
    CoopManager.showStatus("Host not found", 3)
  elseif msg.reason == "busy" then
    CoopManager.showStatus("The host is waiting for its own partner", 4)
  end
end

local function onHello(ow, msg)
  local bad, tellThem = incompatible(msg)
  if bad then
    CoopLog.error("MANAGER", "Incompatible partner: " .. bad)
    CoopManager.showStatus(bad, 4)
    if CoopManager.net then
      CoopManager.net:send({ type = "coop_reject", reason = tellThem or bad })
      CoopManager.net:flush()
      -- the host keeps its door open for the right partner
      CoopManager.net:dropPeer()
    end
    if CoopManager.isHost then
      CoopManager.connected = false
      CoopManager.partner = freshPartner()
    else
      resetSession()
    end
    CoopManager.lastLinkError = bad
    return
  end
  applyPartnerInfo(msg)
  if msg.type == "coop_hello" then
    sendHello(ow, "coop_welcome")
  end
  if msg.timeMode and not CoopManager.timeMode and not CoopManager.isHost then
    -- rejoining a session whose clock was already agreed
    local partnerTz = msg.timezone or {}
    local localTz = CoopManager.net.timezone or {}
    local g = getGame(ow)
    CoopManager.applyTimeMode(msg.timeMode, partnerTz.offsetSec, localTz.offsetSec, msg.dayOffset,
                              g and g.save and g.save.g2DayOffset)
  end
  completeHandshake(ow)
end
H.coop_hello = onHello
H.coop_welcome = onHello

H.coop_reject = function(ow, msg)
  CoopManager.lastLinkError = tostring(msg.reason or "PARTNER REFUSED THE LINK")
  CoopManager.showStatus(CoopManager.lastLinkError, 4)
end

H.coop_pos = function(ow, msg)
  local partner = CoopManager.partner
  local n = tonumber(msg.n) or 0
  if n > 0 and n <= (partner.posN or 0) then return end -- older snapshot
  partner.posN = n
  partner.map = msg.map
  partner.cx = msg.cx or 0
  partner.cy = msg.cy or 0
  partner.tx, partner.ty = msg.tx, msg.ty
  partner.px = msg.px or (partner.cx * 16)
  partner.py = msg.py or (partner.cy * 16)
  partner.hopY = tonumber(msg.hy) or 0
  partner.facing = msg.facing or "down"
  partner.moving = msg.moving == true
  if msg.sprite then partner.sprite = msg.sprite end
  if msg.inBattle ~= nil then partner.inBattle = msg.inBattle == true end
  if msg.inDialogue ~= nil then partner.inDialogue = msg.inDialogue == true end
  partner.busy = msg.busy == true
  partner.surfing = msg.surf == true
  if msg.healthy then partner.healthy = msg.healthy end
  -- their walking Pokemon (FollowMon.snapshot); nil = none to draw
  partner.follow = type(msg.fol) == "table" and msg.fol or nil
  partner.lastSeen = now()
end

H.coop_name_update = function(ow, msg)
  if type(msg.name) == "string" and msg.name ~= "" then
    CoopManager.partner.name = msg.name
  end
end

H.coop_time_sync = function(ow, msg)
  if msg.mode then
    CoopManager.applyTimeMode(msg.mode, msg.hostOffsetSec, msg.guestOffsetSec, msg.hostDay, msg.guestDay)
    if msg.mode ~= "off" then CoopManager.showStatus("Clocks shared!", 2) end
  end
end

H.coop_battle_status = function(ow, msg)
  local was = CoopManager.partner.inBattle
  CoopManager.partner.inBattle = (msg.inBattle == true)
  if was and not CoopManager.partner.inBattle then
    CoopManager.partnerEngagingTrainer = nil
  end
end

H.coop_dialogue_status = function(ow, msg)
  CoopManager.partner.inDialogue = (msg.inDialogue == true)
end

H.coop_emote = function(ow, msg)
  if require("src.coop.CoopEmotes").valid(msg.emote) then
    CoopManager.partner.emote = msg.emote
    CoopManager.partner.emoteTimer = 2.5
    playSound(getGame(ow), "Collision")
  end
end

H.coop_party_req = function(ow, msg) CoopManager.onPartyRequest(ow, msg) end
H.coop_party = function(ow, msg) CoopManager.onPartnerParty(ow, msg) end
H.coop_item_use = function(ow, msg) CoopManager.onItemUse(ow, msg) end
H.coop_item_result = function(ow, msg) CoopManager.onItemResult(ow, msg) end
H.coop_item_query = function(ow, msg) CoopManager.onItemQuery(ow, msg) end

H.coop_warp_req = function(ow, msg) CoopManager.onWarpRequest(ow, msg) end
H.coop_warp_reply = function(ow, msg) CoopManager.onWarpReply(ow, msg) end

H.coop_warp = function()
  CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " warped to you", 3)
end

H.coop_battle_invite = function(ow, msg) CoopManager.onBattleInviteReceived(ow, msg) end
H.coop_bigbattle_invite = function(ow, msg) CoopManager.onBigBattleInvite(ow, msg) end
H.coop_bigbattle_ready = function(ow, msg) CoopManager.onBigBattleReady(ow, msg) end
H.coop_bigbattle_go = function(ow, msg) CoopManager.onBigBattleGo(ow, msg) end
H.coop_battle_accept = function(ow, msg) CoopManager.onBattleAccepted(ow, msg) end
H.coop_battle_decline = function(ow, msg) CoopManager.onBattleDeclined(ow, msg) end
H.coop_battle_cancel = function(ow, msg) CoopManager.onBattleCancelled(ow, msg) end

local function toBattle(fnName)
  return function(ow, msg)
    local CoopBattle = require("src.coop.CoopBattle")
    if CoopBattle[fnName] then CoopBattle[fnName](msg) end
  end
end
H.coop_battle_action = toBattle("onPartnerAction")
H.coop_battle_heal = toBattle("onPartnerHealedMon")
H.coop_battle_sync = toBattle("onPartnerBattleSync")
H.coop_battle_leave = toBattle("onPartnerLeft")
H.coop_battle_replace = toBattle("onPartnerReplace")
H.coop_battle_abort = toBattle("onPartnerLeft")

H.coop_chat = function(ow, msg) CoopManager.onChatReceived(msg.sender, msg.text, false, msg.n) end
H.coop_chat_live = function(ow, msg) CoopManager.onChatLive(msg) end

-- the Cable Club over the co-op link (trade / P1 vs P2 battle)
local function link() return require("src.coop.CoopLink") end
H.coop_link = function(ow, msg) link().onLinkMessage(msg) end
H.coop_link_invite = function(ow, msg) link().onInvite(getGame(ow), msg) end
H.coop_link_accept = function(ow, msg) link().onAccept(getGame(ow), msg) end
H.coop_link_decline = function(ow, msg) link().onDecline(getGame(ow), msg) end
H.coop_link_cancel = function(ow, msg) link().onCancel(getGame(ow), msg) end

H.coop_trainer_engaging = function(ow, msg)
  CoopManager.partnerEngagingTrainer = msg
  CoopManager.partnerEngagingTrainerTime = now()
end

H.coop_trainer_defeated = function(ow, msg)
  CoopManager.partnerEngagingTrainer = nil
  if not CoopManager.storySync then return end
  local game = getGame(ow)
  markTrainerBeaten(game, ow, msg)
end

-- BUG-CATCHING CONTEST: each run is the player's own, but the partner hears
-- about it, can share the clock and is judged against you
function CoopManager.contestEvent(kind, info)
  if not (CoopManager.connected and CoopManager.net) then return end
  local m = { type = "coop_contest", kind = kind }
  for k, v in pairs(info or {}) do m[k] = v end
  CoopManager.net:send(m)
end

function CoopManager.partnerContestSecondsLeft()
  local c = CoopManager.partner.contest
  if not (c and c.active and c.secondsLeft and c.at) then return nil end
  return math.floor(c.secondsLeft - (now() - c.at))
end

-- ONE WINNER FOR A TIE.  Each board puts its own player first in a tie, so
-- an exact tie gave both of you 1st prize.  Both games now break it the same
-- way -- the lower save id wins (the host, for a partner with no id) -- by
-- lifting the partner's entry half a point when the tie is theirs.
function CoopManager.partnerWinsContestTie()
  local theirs, mine = CoopManager.partner.id, CoopManager.coopId()
  if theirs and mine then return theirs < mine end
  return not CoopManager.isHost
end

function CoopManager.partnerContestEntry()
  local c = CoopManager.partner.contest
  if not (c and c.score) then return nil end
  local score = tonumber(c.score) or 0
  if score > 0 and CoopManager.partnerWinsContestTie() then score = score + 0.5 end
  return { score = score, species = c.species, name = CoopManager.partner.name }
end

H.coop_contest = function(ow, msg)
  local partner = CoopManager.partner
  local game = getGame(ow)
  partner.contest = partner.contest or {}
  local c = partner.contest
  local function monName(species)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[species]
    return (def and def.name) or tostring(species or "?")
  end
  if msg.kind == "start" then
    partner.contest = { active = true, secondsLeft = tonumber(msg.secondsLeft) or 1200, at = now() }
    CoopManager.showStatus((partner.name or "Partner") .. " joined the contest!", 3)
  elseif msg.kind == "catch" then
    c.species, c.score = msg.species, tonumber(msg.score) or 0
    CoopManager.showStatus((partner.name or "Partner") .. " caught " .. monName(msg.species) .. "!", 3)
  elseif msg.kind == "end" then
    c.active = false
    if msg.placing then
      CoopManager.showStatus((partner.name or "Partner") .. " placed #" .. tostring(msg.placing) .. "!", 3)
    end
  end
end

H.coop_rules = function(ow, msg)
  if SHARED_RULES[msg.name] then
    CoopManager.setRule(msg.name, msg.value == true, true)
    CoopManager.showStatus(CoopManager.ruleLabel(msg.name) .. (msg.value and " ON" or " OFF") .. " (partner)", 2.5)
  end
end

-- HALL OF FAME TOGETHER.  Each player's game inducts its own team (the
-- partner walks in with you -- CoopStory shares Lance's warp -- and runs the
-- HALL OF FAME scene on their side), and each screen shows BOTH teams:
-- ours, then the partner's under their name, then the two of us.
function CoopManager.recordHallOfFame(game, entry)
  if not (CoopManager.connected and CoopManager.net) then return end
  -- a partner off somewhere else did not walk in with you
  local where = CoopManager.partner.map
  if not (where and HOF_PARTNER_MAPS[where]) then return end
  CoopManager.hofEntry = entry
  entry.coop = { partner = CoopManager.partner.name or "PARTNER",
                 mons = CoopManager.partner.hofTeam }
  CoopManager.net:send({ type = "coop_hof_team", name = CoopManager.getLocalPlayerName(game), mons = entry })
end

H.coop_hof_team = function(ow, msg)
  local team = {}
  for _, m in ipairs(type(msg.mons) == "table" and msg.mons or {}) do
    if type(m) == "table" and m.species then
      team[#team + 1] = { species = m.species, level = m.level, nickname = m.nickname }
    end
  end
  CoopManager.partner.hofTeam = team
  if CoopManager.hofEntry and CoopManager.hofEntry.coop then
    CoopManager.hofEntry.coop.mons = team
  end
  CoopManager.showStatus((msg.name or "Partner") .. " entered the HALL OF FAME!", 3)
end

H.coop_story_text = function(ow, msg)
  require("src.coop.CoopStory").onPartnerText(getGame(ow), msg)
end

H.coop_story_rewards = function(ow, msg)
  require("src.coop.CoopStory").onPartnerRewards(getGame(ow), msg)
end

-- the partner is holding a big battle's scene until we walk in (CoopStory)
H.coop_story_hold = function(ow, msg) require("src.coop.CoopStory").onPartnerHold(msg) end
H.coop_story_release = function(ow, msg) require("src.coop.CoopStory").onPartnerRelease(msg) end

-- THE STORY THIS SAVE SHARES, AND WITH WHOM.  Once both are in the world,
-- the save remembers its partner (save.coopPartner) -- so an event played
-- while the link is down is kept for them (CoopStory.queue) -- and whatever
-- was kept while apart goes out now.  A save that changes partners drops
-- what it was keeping for the old one.
local function realName(n)
  return type(n) == "string" and n ~= "" and n ~= "HOST" and n ~= "GUEST" and n ~= "PARTNER"
end

function CoopManager.bindStoryPartner(game, ow)
  local save = game and game.save
  if not (save and ow and ow.map and CoopManager.storySync and CoopManager.isConnected()) then return end
  local name = CoopManager.partner.name
  if not (realName(name) and CoopManager.partner.map) then return end
  -- the partner is their save's id; a save from before 1.5 knows a name only
  local id = CoopManager.partner.id
  local other = (id and save.coopPartnerId and save.coopPartnerId ~= id)
                or (not save.coopPartnerId and save.coopPartner ~= nil and save.coopPartner ~= name)
  if other and save.coopStoryOutbox then
    CoopLog.info("STORY", "new partner " .. name .. ": dropped events kept for " .. tostring(save.coopPartner))
    save.coopStoryOutbox = nil
  end
  save.coopPartner = name
  if id then save.coopPartnerId = id end
  if save.coopStoryOutbox then
    local n = require("src.coop.CoopStory").flushOutbox(game)
    if n > 0 then CoopManager.showStatus("Shared " .. n .. " event(s) with " .. name, 3) end
  end
end

-- SAVING TOGETHER: one player's save asks the other's game to save too, as
-- soon as it is safely back on the overworld, so the two files never
-- describe different points of the same adventure.
H.coop_save = function(ow, msg)
  CoopManager.pendingPartnerSave = { from = msg.name or CoopManager.partner.name }
end

H.coop_save_done = function(ow, msg)
  if msg.ok ~= false then
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " saved too!", 2.5)
  end
end

H.coop_bye = function(ow)
  -- the transport turns the disconnect that follows into net_disconnect
  -- with reason "left"; nothing else to do here
  CoopLog.info("MANAGER", "Partner said goodbye")
end

CoopManager.handlers = H

function CoopManager.dispatch(ow, msg)
  if type(msg) ~= "table" or type(msg.type) ~= "string" then return end
  local lobby = CoopManager.lobby
  if lobby and lobby.onNetMessage then
    local okL, consumed = pcall(lobby.onNetMessage, lobby, msg)
    if not okL then
      CoopLog.error("MANAGER", "lobby handler failed on " .. msg.type .. ": " .. tostring(consumed))
    elseif consumed then
      return
    end
  end
  local handler = H[msg.type]
  if handler then
    local ok, err = pcall(handler, ow, msg)
    if not ok then
      CoopLog.error("MANAGER", "handler " .. msg.type .. " failed: " .. tostring(err))
    end
  end
end

-- ---------------------------------------------------------------------
-- per-frame
-- ---------------------------------------------------------------------

local function followSnapshot(ow)
  local ok, FollowMon = pcall(require, "src.follow.FollowMon")
  if not ok then return nil end
  local okS, snap = pcall(FollowMon.snapshot, ow)
  return okS and snap or nil
end

-- the follower's cell (or none), so its step reaches the partner at once
local function followCell(fol)
  if type(fol) ~= "table" then return nil end
  return ("%s:%d:%d:%s"):format(tostring(fol.s), math.floor(((fol.px or 0) + 8) / 16),
                                math.floor(((fol.py or 0) + 8) / 16), tostring(fol.f))
end

local function broadcastPosition(ow, dt, force)
  local p = ow and ow.player
  if not (p and ow.map) then return end
  local game = getGame(ow)
  local inBattle = CoopManager.isLocalInBattle(ow)
  local inDialogue = CoopManager.isLocalInDialogue(ow)
  local snapshot = {
    type = "coop_pos",
    map = ow.map.id,
    cx = p.cellX, cy = p.cellY,
    tx = p.targetX, ty = p.targetY,
    px = p.px, py = p.py,
    hy = localHopY(p),
    facing = p.facing,
    moving = p.moving and true or false,
    sprite = localSpriteId(p),
    inBattle = inBattle,
    inDialogue = inDialogue,
    busy = not overworldIdle(game, ow) and not inBattle,
    healthy = healthyCount(game and game.save),
    surf = p.surfing and true or nil,
    fol = followSnapshot(ow),
  }

  -- send at once when something a viewer would notice changed (a step
  -- starting, a turn, a map change, mounting the bike), otherwise on a
  -- steady cadence: fast while walking, slow as a keepalive when still
  local last = CoopManager.lastSentPos
  local changed = not last or last.map ~= snapshot.map or last.tx ~= snapshot.tx or last.ty ~= snapshot.ty
                  or last.cx ~= snapshot.cx or last.cy ~= snapshot.cy or last.facing ~= snapshot.facing
                  or last.sprite ~= snapshot.sprite or last.inBattle ~= snapshot.inBattle
                  or last.inDialogue ~= snapshot.inDialogue or last.busy ~= snapshot.busy
                  or last.moving ~= snapshot.moving
                  or followCell(last.fol) ~= followCell(snapshot.fol)
  CoopManager.syncTimer = CoopManager.syncTimer + (dt or 0)
  local interval = (snapshot.moving or snapshot.hy ~= 0) and POS_INTERVAL_MOVING or POS_INTERVAL_IDLE
  if not (force or changed or CoopManager.syncTimer >= interval) then return end

  CoopManager.syncTimer = 0
  CoopManager.posN = CoopManager.posN + 1
  snapshot.n = CoopManager.posN
  CoopManager.lastSentPos = snapshot
  CoopManager.net:send(snapshot, { fast = true })
end

local function tickTimers(dt)
  local partner = CoopManager.partner
  if partner.emoteTimer > 0 then
    partner.emoteTimer = partner.emoteTimer - dt
    if partner.emoteTimer <= 0 then partner.emote = nil end
  end
  if CoopManager.localEmoteTimer > 0 then
    CoopManager.localEmoteTimer = CoopManager.localEmoteTimer - dt
    if CoopManager.localEmoteTimer <= 0 then CoopManager.localEmote = nil end
  end
  if CoopManager.statusTimer > 0 then
    CoopManager.statusTimer = CoopManager.statusTimer - dt
    if CoopManager.statusTimer <= 0 then CoopManager.statusMessage = nil end
  end
  -- a message only counts down while it is on screen
  local chat = CoopManager.activeChatMessage
  if chat and chat.timer > 0 and CoopManager.chatShown then
    chat.timer = chat.timer - dt
    if chat.timer <= 0 then CoopManager.activeChatMessage = nil end
  end
  CoopManager.chatShown = false
  local typing = CoopManager.partnerTyping
  if typing and now() - (typing.at or 0) > CoopManager.TYPING_STALE then
    CoopManager.partnerTyping = nil
  end
  tickLive()
end

local function runTickers(list, dt, game, ow)
  for name, fn in pairs(list) do
    local ok, err = pcall(fn, dt, game, ow)
    if not ok and CoopManager.tickerErr ~= err then
      CoopManager.tickerErr = err
      CoopLog.error("MANAGER", "ticker " .. name .. " failed: " .. tostring(err))
    end
  end
end

function CoopManager.update(ow, dt)
  dt = math.min(dt or 0.016, 0.25)
  tickTimers(dt)
  runTickers(CoopManager.idleTickers, dt, getGame(ow), ow)
  local net = CoopManager.net
  if not net or net.closed then
    if CoopManager.partnerNpc and ow then CoopManager.removePartnerNpc(ow) end
    return
  end

  net:update(dt)
  for _, msg in ipairs(net:poll()) do
    CoopManager.dispatch(ow, msg)
  end

  local okCB, CoopBattle = pcall(require, "src.coop.CoopBattle")
  if okCB and CoopBattle and CoopBattle.tick then
    local ok, err = pcall(CoopBattle.tick, dt)
    if not ok then CoopLog.error("BATTLE", "tick failed: " .. tostring(err)) end
  end

  if not CoopManager.connected then
    if ow and CoopManager.partnerNpc then CoopManager.removePartnerNpc(ow) end
    return
  end

  CoopManager.tickWarpAsk()
  local game = getGame(ow)
  pcall(function() require("src.coop.CoopStory").tick(dt, game) end)
  pcall(CoopManager.bindStoryPartner, game, ow)
  if CoopManager.pendingPartnerSave and ow and overworldIdle(game, ow) then
    local from = CoopManager.pendingPartnerSave.from
    CoopManager.pendingPartnerSave = nil
    CoopManager.savingForPartner = true
    local ok, res = pcall(function() return game:writeSave() end)
    CoopManager.savingForPartner = false
    local saved = ok and res ~= false
    CoopManager.net:send({ type = "coop_save_done", ok = saved })
    CoopManager.showStatus(saved and ("Saved with " .. tostring(from or "partner") .. "!") or "Save failed", 2.5)
  end
  if CoopManager.pendingTimePrompt and ow and overworldIdle(game, ow) then
    CoopManager.pendingTimePrompt = false
    CoopManager.timePrompted = true
    promptTimezoneChoice(game)
  end

  local pName = CoopManager.getLocalPlayerName(game)
  if pName ~= "HOST" and pName ~= "GUEST" and pName ~= CoopManager.lastSyncedName then
    CoopManager.lastSyncedName = pName
    CoopManager.syncTrainerName(game)
  end

  if ow then
    local inBattle = CoopManager.isLocalInBattle(ow)
    if inBattle ~= CoopManager.localInBattle then CoopManager.setInBattle(inBattle) end
    local inDlg = CoopManager.isLocalInDialogue(ow)
    if inDlg ~= CoopManager.localInDialogue then CoopManager.setInDialogue(inDlg) end

    CoopManager.updatePartnerRender(ow, dt)
    broadcastPosition(ow, dt)
  end
  runTickers(CoopManager.tickers, dt, game, ow)
  net:flush()
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

-- Draw authentic rotating Poké Ball above battlers (compact retro r=2.2)
function CoopManager.drawSpinningPokeball(bx, by, r)
  r = r or 2.2
  local t = now()
  local angle = (t * 5) % (2 * math.pi)
  local bob = math.floor(math.sin(t * 6) * 1.5)

  love.graphics.push()
  love.graphics.translate(bx, by + bob)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.circle("fill", 0, 0, r + 0.8)
  if love.graphics.arc then
    love.graphics.setColor(0.9, 0.15, 0.15, 1)
    love.graphics.arc("fill", 0, 0, r, math.pi, 2 * math.pi)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.arc("fill", 0, 0, r, 0, math.pi)
  else
    love.graphics.setColor(0.9, 0.15, 0.15, 1)
    love.graphics.circle("fill", 0, 0, r)
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", -r, -0.6, r * 2, 1.2)
  love.graphics.circle("fill", 0, 0, math.max(1, r * 0.45))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", 0, 0, math.max(0.5, r * 0.22))
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

-- 1px-bordered white pill with notched corners, the shape every co-op
-- label uses
local function drawPill(bx, by, bw, bh)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", bx + 1, by, bw - 2, 1)
  love.graphics.rectangle("fill", bx + 1, by + bh - 1, bw - 2, 1)
  love.graphics.rectangle("fill", bx, by + 1, 1, bh - 2)
  love.graphics.rectangle("fill", bx + bw - 1, by + 1, 1, bh - 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", bx + 1, by + 1, bw - 2, bh - 2)
end
CoopManager.drawPill = drawPill

local function screenPoint(ow, wx, wy)
  local cam = ow.camera
  local vw, vh = (ow.viewW or 160), (ow.viewH or 144)
  local fx = wx - cam.x + 8
  local fy = wy - cam.y + 16
  if Tilt.active and Tilt.active() then
    return Tilt.groundPoint(fx, fy, vw, vh)
  end
  return fx, fy
end
CoopManager.screenPoint = screenPoint

-- A small arrow on the screen edge pointing at a partner who is on this map
-- (or a connected one) but out of view.
local function drawOffscreenArrow(sx, sy, vw, vh)
  local cx, cy = vw / 2, vh / 2
  local dx, dy = sx - cx, sy - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  dx, dy = dx / len, dy / len
  local margin = 7
  local tx = (dx ~= 0) and ((dx > 0 and (vw - margin - cx) or (margin - cx)) / dx) or math.huge
  local ty = (dy ~= 0) and ((dy > 0 and (vh - margin - cy) or (margin - cy)) / dy) or math.huge
  local t = math.min(math.abs(tx), math.abs(ty))
  local ax, ay = cx + dx * t, cy + dy * t
  local px, py = -dy, dx
  local tip = 5
  local base = 3
  local pts = {
    ax + dx * tip, ay + dy * tip,
    ax + px * base, ay + py * base,
    ax - px * base, ay - py * base,
  }
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.polygon("fill", pts[1] + dx, pts[2] + dy, pts[3] + px, pts[4] + py, pts[5] - px, pts[6] - py)
  love.graphics.setColor(40 / 255, 112 / 255, 248 / 255, 1)
  love.graphics.polygon("fill", pts)
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopManager.drawWorld(ow)
  if not ow or not ow.camera then return end
  local partner = CoopManager.partner
  local npc = CoopManager.partnerNpc
  local vw, vh = (ow.viewW or 160), (ow.viewH or 144)
  local MicroFont = require("src.render.MicroFont")
  local t = now()

  if CoopManager.connected and npc and CoopManager.render then
    local sx, sy = screenPoint(ow, npc.px, npc.py - (partner.hopY or 0))
    local onScreen = sx >= -8 and sx <= vw + 8 and sy >= 0 and sy <= vh + 16
    if onScreen then
      local name = string.upper(partner.name or "PARTNER")
      if #name > 8 then name = name:sub(1, 8) end
      local bw = math.max(16, MicroFont.width(name) + 6)
      local bx = math.floor(sx - bw / 2)
      local by = math.floor(sy + 2)
      drawPill(bx, by, bw, 9)
      love.graphics.setColor(0, 0, 0, 1)
      MicroFont.draw(name, bx + 3, by + 2)
      love.graphics.setColor(1, 1, 1, 1)

      local headY = math.floor(sy - 18 + (partner.hopY or 0))
      local ballY = headY - 5
      if partner.inBattle then
        CoopManager.drawSpinningPokeball(sx, ballY, 2.0)
      elseif partner.inDialogue then
        local bxB = math.floor(sx - 5)
        local byB = math.floor(ballY - 3)
        drawPill(bxB, byB, 11, 7)
        love.graphics.setColor(0, 0, 0, 1)
        local dots = math.floor(t * 3) % 3 + 1
        for i = 1, dots do
          love.graphics.rectangle("fill", bxB + 2 + (i - 1) * 3, byB + 3, 1, 1)
        end
        love.graphics.setColor(1, 1, 1, 1)
      elseif partner.emote then
        require("src.coop.CoopEmotes").draw(getGame(ow), partner.emote, sx, sy + (partner.hopY or 0),
                                            2.5 - (partner.emoteTimer or 0))
      end
    else
      drawOffscreenArrow(sx, sy - 8, vw, vh)
    end
  end

  if CoopManager.localEmote and ow.player then
    local p = ow.player
    local sx, sy = screenPoint(ow, p.px, p.py)
    require("src.coop.CoopEmotes").draw(getGame(ow), CoopManager.localEmote, sx, sy,
                                        2.5 - (CoopManager.localEmoteTimer or 0))
  end
  for name, fn in pairs(CoopManager.worldDrawers) do
    local ok, err = pcall(fn, ow)
    if not ok and CoopManager.drawerErr ~= err then
      CoopManager.drawerErr = err
      CoopLog.error("MANAGER", "world drawer " .. name .. " failed: " .. tostring(err))
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- name -> fn(ow): feature modules drawing on the world (visitors' names)
CoopManager.worldDrawers = {}

-- word-wrap to `width` characters, at most `maxLines` lines
local function wrap(text, width, maxLines)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    while #word > width do
      if line ~= "" then lines[#lines + 1] = line; line = "" end
      lines[#lines + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  while #lines > maxLines do table.remove(lines) end
  return lines
end
CoopManager.wrap = wrap

local function drawSignal(x, y, bars)
  for i = 1, 3 do
    local h = i * 2
    if i <= bars then
      love.graphics.setColor(0, 0, 0, 1)
    else
      love.graphics.setColor(0.7, 0.7, 0.7, 1)
    end
    love.graphics.rectangle("fill", x + (i - 1) * 2, y + 6 - h, 1, h)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The link HUD: a small pill in the top-right corner, never a full window.
-- Signal bars + partner name; underneath, where the partner is when they are
-- not on a map we can see; a blinking LINK LOST while reconnecting.
local function drawHud(ow)
  local MicroFont = require("src.render.MicroFont")
  local state = CoopManager.linkState()
  if state == "off" then return end
  -- the UI pass's width, NOT ow.viewW: that is the WORLD view, which grows
  -- as the zoom goes out, and anchoring to it pushed the link and partner
  -- pills off the right edge of the screen until you zoomed back in
  local game = getGame(ow)
  local renderer = game and game.renderer
  local vw = (renderer and renderer.uiSize and select(1, renderer:uiSize())) or 160
  local partner = CoopManager.partner

  local label
  if state == "reconnecting" then
    label = (math.floor(now() * 2) % 2 == 0) and "LINK LOST" or "RECONNECT"
  elseif state == "listening" then
    label = "WAITING P2"
  elseif not CoopManager.connected then
    label = "LINKING"
  else
    label = string.upper(partner.name or "P2")
    if #label > 8 then label = label:sub(1, 8) end
  end
  local net = CoopManager.net
  local bars = (net and net.linkQuality) and net:linkQuality() or 0
  local w = MicroFont.width(label) + 14
  local x = vw - w - 1
  drawPill(x, 1, w, 9)
  drawSignal(x + 3, 2, bars)
  love.graphics.setColor(0, 0, 0, 1)
  MicroFont.draw(label, x + 11, 3)

  if CoopManager.connected and partner.map and ow and ow.map and not partnerFrameOffset(ow) then
    local area = CoopManager.mapLabel(partner.map)
    if #area > 18 then area = area:sub(1, 18) end
    local aw = MicroFont.width(area) + 6
    local ax = vw - aw - 1
    drawPill(ax, 11, aw, 9)
    love.graphics.setColor(0, 0, 0, 1)
    MicroFont.draw(area, ax + 3, 13)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopManager.drawUI(ow)
  local game = (ow and ow.game) or getGame(ow)
  local top = stackTop(game)
  local hasTextBox = top and (top.isTextBox or (top.lines ~= nil and top.page ~= nil))
  local isTypingChat = top and top.isChatBox

  -- status first, at the top, so it never sits on the dialogue box
  if CoopManager.statusMessage and CoopManager.statusTimer > 0 then
    local lines = wrap(CoopManager.statusMessage, 18, 2)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, 20, #lines + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, l in ipairs(lines) do
      Font.draw(l, 8, 8 * i)
    end
    love.graphics.setColor(1, 1, 1, 1)
  else
    drawHud(ow)
  end

  -- the partner's event, read along without being frozen by it
  local okStory, CoopStory = pcall(require, "src.coop.CoopStory")
  local page = okStory and CoopStory.currentPage and CoopStory.currentPage()
  if page and not hasTextBox and not isTypingChat then
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(page[1] or "", 8, 112)
    Font.draw(page[2] or "", 8, 128)
    -- whose scene this is, on the frame: a small blue tab
    local MicroFont = require("src.render.MicroFont")
    local who = string.upper(CoopManager.partner.name or "P2")
    if #who > 8 then who = who:sub(1, 8) end
    local tw = MicroFont.width(who) + 5
    love.graphics.setColor(0.16, 0.44, 0.97, 1)
    love.graphics.rectangle("fill", 8, 94, tw, 8)
    love.graphics.setColor(1, 1, 1, 1)
    MicroFont.draw(who, 10, 95)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if not isTypingChat then
    -- over a dialogue box the bubble moves to the top, under any status
    local statusUp = CoopManager.statusMessage and CoopManager.statusTimer > 0
    CoopManager.drawChatBubble(hasTextBox and (statusUp and 4 or 0) or nil)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- What the chat bubble shows: the partner typing live first (that is the
-- newest thing there is), then the latest message.
function CoopManager.chatBubble()
  local typing = CoopManager.partnerTyping
  if typing then
    local cursor = (math.floor(now() * 3) % 2 == 0) and "_" or " "
    local name = string.upper(CoopManager.partner.name or "PARTNER"):sub(1, 8)
    local text = typing.text ~= "" and (typing.text .. cursor) or ("is typing" .. string.rep(".", math.floor(now() * 3) % 4))
    return name, text, true
  end
  local chat = CoopManager.activeChatMessage
  if chat and chat.timer > 0 then return chat.sender, chat.text, false end
  return nil
end

-- ty = nil: the classic box along the bottom; a number: a compact box at
-- that row (over dialogue, or over a battle)
function CoopManager.drawChatBubble(ty)
  local sender, text, typing = CoopManager.chatBubble()
  if not sender then return false end
  if not typing then CoopManager.chatShown = true end
  love.graphics.setColor(1, 1, 1, 1)
  if ty == nil then
    local lines = wrap(text, 18, 2)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(sender .. ":", 8, 104)
    for i, l in ipairs(lines) do Font.draw(l, 8, 104 + i * 12) end
  else
    local lines = wrap(sender .. ": " .. text, 18, 3)
    Font.drawBox(0, ty, 20, #lines + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, l in ipairs(lines) do Font.draw(l, 8, (ty + i) * 8) end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- a co-op double draws the bubble across the top of the battle screen
function CoopManager.drawBattleChat(battle)
  if not CoopManager.connected then return end
  local game = battle and battle.game
  local top = stackTop(game)
  if top and top.isChatBox then return end
  CoopManager.drawChatBubble(0)
end

-- The last `count` lines of the chat log (and the partner's live line) for
-- the chat box, wrapped to `width`.
function CoopManager.chatLines(width, count)
  local out = {}
  local function add(s)
    for _, l in ipairs(wrap(s, width, 4)) do out[#out + 1] = l end
  end
  for _, m in ipairs(CoopManager.chatLog) do add(m.sender .. ": " .. m.text) end
  local typing = CoopManager.partnerTyping
  if typing then
    local name = string.upper(CoopManager.partner.name or "PARTNER"):sub(1, 8)
    add(name .. ": " .. (typing.text ~= "" and (typing.text .. "_") or "..."))
  end
  local first = math.max(1, #out - count + 1)
  local tail = {}
  for i = first, #out do tail[#tail + 1] = out[i] end
  return tail
end

-- Backward compatibility for single draw call
function CoopManager.draw(ow)
  CoopManager.drawUI(ow)
end

-- the feature modules register their messages, rules and per-frame work in
-- the tables above when they load.  They require this module back, so it is
-- published first: `require` would otherwise see a module still loading.
package.loaded["src.coop.CoopManager"] = CoopManager
for _, name in ipairs(CoopManager.FEATURES or {}) do
  local ok, err = pcall(require, name)
  if not ok then CoopLog.error("MANAGER", "feature " .. name .. " failed to load: " .. tostring(err)) end
end

return CoopManager
