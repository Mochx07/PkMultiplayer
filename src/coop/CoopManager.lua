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
local Font = require("src.coop.CoopI18n").font()
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

-- the file-level locals the split-out parts (src/coop/Coop*.lua installed
-- below) read and hand back; filled in just before each one is installed
local CMI = {}

-- Capabilities: what this copy can do beyond protocol 16, announced in the
-- hello as a list of names.  A copy from before 1.20 sends none (and ignores
-- ours), so a feature that needs the partner too checks bothHave(cap) and
-- stays off otherwise: the two still link, they just leave it out.  A new
-- feature calls CoopManager.registerCap("name") where it is loaded.
CoopManager.CAPS = {}

function CoopManager.registerCap(name)
  assert(type(name) == "string" and name:match("^[%w_.%-]+$"), "bad capability name")
  CoopManager.CAPS[name] = true
end

CoopManager.registerCap("vs.sleep")     -- src/coop/CoopSleepClause.lua
CoopManager.registerCap("vs.formats")   -- src/coop/CoopVS.lua
CoopManager.registerCap("vs.match")     -- src/coop/CoopMatch.lua: best of 3, the VS record

-- ours, sorted (the hello and the logs read the same)
function CoopManager.localCaps()
  local out = {}
  for name in pairs(CoopManager.CAPS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- a received list -> a set; anything that is not a short name is dropped
local function capSet(list)
  local set = {}
  if type(list) ~= "table" then return set end
  for i = 1, math.min(#list, 64) do
    local name = list[i]
    if type(name) == "string" and #name <= 32 and name:match("^[%w_.%-]+$") then set[name] = true end
  end
  return set
end
CoopManager.capSet = capSet

function CoopManager.partnerHas(name)
  local caps = CoopManager.partner and CoopManager.partner.caps
  return caps ~= nil and caps[name] == true
end

function CoopManager.bothHave(name)
  return CoopManager.CAPS[name] == true and CoopManager.partnerHas(name)
end

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
-- THE RULES ARE KEPT IN THE SAVE (save.coopRules): set here or by the
-- partner, they are what this game starts with the next time it loads.
local function keepRule(name)
  local ok, G = pcall(require, "src.core.Game")
  local save = ok and type(G) == "table" and G.save
  if type(save) ~= "table" then return end
  save.coopRules = type(save.coopRules) == "table" and save.coopRules or {}
  save.coopRules[name] = CoopManager[name]
end

-- The host's rules, all of them, to the partner (who takes them as the
-- session's: H.coop_rules).
function CoopManager.sendRules()
  if not (CoopManager.connected and CoopManager.net) then return end
  for name in pairs(SHARED_RULES) do
    CoopManager.net:send({ type = "coop_rules", name = name, value = CoopManager[name] })
  end
end

-- called once a save is up (Game.restoreSave); a guest who is linked
-- already plays by the host's rules.
--
-- THE HOST'S SAVE CAN COME UP AFTER THE LINK.  Reported from play: the rules
-- were not the same on both games.  NEW CO-OP GAME / CONTINUE CO-OP link
-- first and load the save after, and the rules went to the partner only at
-- the link -- the host's defaults (BALANCED FOES on), not the ones its save
-- then loaded (off).  A host that loads its save while linked sends the
-- rules again.
function CoopManager.loadRules(save)
  local kept = type(save) == "table" and save.coopRules
  if type(kept) ~= "table" then return end
  if CoopManager.connected and not CoopManager.isHost then return end
  local changed = false
  for name in pairs(SHARED_RULES) do
    if type(kept[name]) == "boolean" and CoopManager[name] ~= kept[name] then
      CoopManager[name] = kept[name]
      changed = true
    end
  end
  if CoopManager.connected and CoopManager.isHost then
    if changed then CoopLog.info("MANAGER", "the host's save brought its rules: sent to the partner again") end
    CoopManager.sendRules()
  end
end

function CoopManager.setRule(name, value, fromPartner)
  if not SHARED_RULES[name] then return end
  CoopManager[name] = value and true or false
  pcall(keepRule, name)
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
  "src.coop.CoopBalance",
  "src.coop.CoopLogShare",
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

-- RED / BLUE / YELLOW'S OWN LEADERS.  KOGA held the SOULBADGE before Janine
-- (in Gold he is OPP_ELITE_FOUR_KOGA, so the key never meets him there), and
-- GIOVANNI is three battles of which only the third -- Viridian's gym,
-- data/scripts/victories.lua OPP_GIOVANNI#3 -- is a leader's: a guest who
-- beat him in the Rocket Hideout must not walk out with the EARTHBADGE.
local GEN1_LEADER_BADGES = {
  KOGA = "SOULBADGE",
  GIOVANNI = { [3] = "EARTHBADGE" },
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
    -- a co-op double still waiting for a dropped partner keeps the session
    -- open past the transport's own window (CoopNet:update)
    CoopManager.net.holdSession = function()
      local CB = package.loaded["src.coop.CoopBattle"]
      return type(CB) == "table" and CB.waitingOnLink ~= nil and CB.waitingOnLink() == true
    end
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
  CoopManager.incomingInviteBuffer = nil
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
    -- `id`: the save now played (a 1.6.0-1.6.16 copy ignores the field)
    CoopManager.net:send({ type = "coop_name_update", name = playerName,
                           id = CoopManager.coopId(game and game.save) })
  end
end

-- GOLD / SILVER AND CRYSTAL NUMBER THEIR EVENT FLAGS APART.  The engine
-- keeps a Gen 2 event flag as the cartridge's own bit (EVENT_G2_%04d,
-- src/script/Gen2Flags.lua), and Crystal's list is Gold's with rows
-- inserted all through it: the same bit is another event on the other
-- cartridge, and nothing in the engine maps one onto the other.  Between
-- the two the story is not shared -- copied across, it set the wrong
-- events -- while the rest of the co-op (battles, trades, chat) carries on.
-- `theirGame` defaults to the linked partner's.
function CoopManager.storyCompatible(theirGame)
  theirGame = theirGame or (CoopManager.partner and CoopManager.partner.game)
  if type(theirGame) ~= "string" or not GameVersion.isGen2() then return true end
  if not GameVersion.isGen2(theirGame) then return true end
  return GameVersion.isCrystal() == GameVersion.isCrystal(theirGame)
end

function CoopManager.syncTrainerDefeated(npcId, headerEvent, trainerIndex, mapId, oppClass, partyIndex)
  if not CoopManager.storySync then return end
  if CoopManager.isConnected() and not CoopManager.storyCompatible() then return end
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
    caps = CoopManager.localCaps(),
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
  -- the place the host keeps for its partner while the link is down is for
  -- the save the partner says it plays NOW, not the one it resumed with
  if partner.id and CoopManager.net and CoopManager.net.notePeerIdentity then
    CoopManager.net:notePeerIdentity(partner.id)
  end
  partner.version = msg.ver or nil
  -- a hello without caps comes from a copy before 1.20: it has none
  partner.caps = capSet(msg.caps)
  -- in the log too: two copies on different versions play different
  -- battles, and the on-screen notice is gone by the time a log is read
  if partner.version ~= CoopManager.loggedPartnerVersion then
    CoopManager.loggedPartnerVersion = partner.version
    local theirs = {}
    for name in pairs(partner.caps) do theirs[#theirs + 1] = name end
    table.sort(theirs)
    CoopLog.info("MANAGER", string.format("partner %s runs v%s (this game v%s); caps [%s] / ours [%s]",
                 tostring(partner.name), tostring(partner.version or "?"), tostring(CoopManager.modVersion()),
                 table.concat(theirs, " "), table.concat(CoopManager.localCaps(), " ")))
  end
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

-- What a fresh link should know, after "Linked with ...!": the story kept
-- apart between Gold/Silver and Crystal, and a partner on another release
-- of the mod that still speaks this protocol (it works; the two may differ).
function CoopManager.linkNotices()
  local notices = {}
  if CoopManager.storySync and not CoopManager.storyCompatible() then
    notices[#notices + 1] = "Story not shared: Gold/Silver and Crystal"
  end
  local theirs = CoopManager.partner.version
  if theirs and tostring(theirs) ~= CoopManager.modVersion() then
    notices[#notices + 1] = string.format("Partner has v%s, you v%s", tostring(theirs), CoopManager.modVersion())
  end
  CoopManager.pendingNotices = notices
  CoopManager.noticeTimer = 3
  return notices
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
    CoopManager.linkNotices()
    -- the guest keeps the host on its JOIN list
    if not CoopManager.isHost and CoopManager.net then
      local ip, port = tostring(CoopManager.net.address or ""):match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
      if ip then pcall(CoopNet.rememberHost, ip, tonumber(port)) end
    end
  end
  CoopManager.lastSyncedName = CoopManager.getLocalPlayerName(getGame(ow))
  -- medicine handed over whose answer never came
  pcall(CoopManager.askHeldItems, getGame(ow))
  -- the host's rules are the session's rules
  if CoopManager.isHost and not wasConnected then CoopManager.sendRules() end

  -- Host proposes the clock once per session when the two disagree
  local partnerTz = CoopManager.partner.timezone
  local localTz = CoopManager.net.timezone
  -- Red / Blue / Yellow have no clock to share
  if CoopManager.isHost and not CoopManager.timeMode and partnerTz and localTz
     and not GameVersion.isGen1()
     and math.abs((partnerTz.offsetSec or 0) - (localTz.offsetSec or 0)) >= 1800
     and not CoopManager.timePrompted then
    CoopManager.pendingTimePrompt = true
  end
end

-- ---------------------------------------------------------------------
-- time of day: both players can agree to share one clock.  mode is
-- (src/coop/CoopClock.lua)
CMI.CoopLog = CoopLog
CMI.CoopManager = CoopManager
CMI.CoopNet = CoopNet
CMI.getGame = getGame
CMI.realDate = realDate
CMI.realTime = realTime
require("src.coop.CoopClock").install(CoopManager, CMI)
local promptTimezoneChoice = CMI.promptTimezoneChoice

-- ---------------------------------------------------------------------
-- partner entity
-- (src/coop/CoopPartnerNpc.lua)
CMI.CoopLog = CoopLog
CMI.CoopManager = CoopManager
CMI.NPC = NPC
CMI.PARTNER_NPC_INDEX = PARTNER_NPC_INDEX
CMI.getGame = getGame
CMI.mapsMatch = mapsMatch
CMI.now = now
CMI.partnerPalette = partnerPalette
require("src.coop.CoopPartnerNpc").install(CoopManager, CMI)
local partnerFrameOffset = CMI.partnerFrameOffset

-- ---------------------------------------------------------------------
-- local state
-- ---------------------------------------------------------------------

function CoopManager.showStatus(text, duration)
  -- in the player's language (src/coop/CoopI18n.lua)
  local okI, I18n = pcall(require, "src.coop.CoopI18n")
  if okI then text = I18n.t(text) end
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
local function partnerReachable(ow, anywhere, forBattleInvite)
  local partner = CoopManager.partner
  if not CoopManager.isConnected() then return false, "Partner not linked" end
  if CoopManager.net.stalled then return false, "Partner link is weak" end
  -- the same room: in the League too.  1.6.16 counted the whole corridor
  -- (the center, every chamber) as "here", so WILL's CO-OP invite and his
  -- lines reached a partner still in the center, and the GO warped them in
  -- through the door that had shut behind you.  The partner walks in.
  if not anywhere and not (ow and ow.map and mapsMatch(partner.map, ow.map.id)) then
    return false, "Partner is far away"
  end
  if (now() - (partner.lastSeen or 0)) > PARTNER_FRESH then return false, "Partner not responding" end
  if partner.inBattle then return false, "Partner in battle" end
  if partner.busy and not (forBattleInvite and partner.inDialogue) then return false, "Partner is busy" end
  if not forBattleInvite and partner.inDialogue then return false, "Partner is busy" end
  return true
end

-- ...and with a Pokemon that can fight.  Returns ok, reason.
-- `anywhere`: the partner may be on another map (a BATTLE TOWER battle,
-- whose room is the challenger's alone)
function CoopManager.partnerAvailable(ow, anywhere, forBattleInvite)
  local ok, why = partnerReachable(ow, anywhere, forBattleInvite)
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
-- your medicine, their Pokemon: src/coop/CoopPartnerItems.lua
CoopManager.playSound = playSound
CoopManager.partnerReachable = partnerReachable
require("src.coop.CoopPartnerItems").install(CoopManager)

-- ---------------------------------------------------------------------
-- warp to partner
-- (src/coop/CoopWarp.lua)
CMI.CoopLog = CoopLog
CMI.CoopManager = CoopManager
CMI.LEAGUE_MAPS = LEAGUE_MAPS
CMI.PARTNER_FRESH = PARTNER_FRESH
CMI.STORY_GATE_MAPS = STORY_GATE_MAPS
CMI.getGame = getGame
CMI.mapsMatch = mapsMatch
CMI.normMap = normMap
CMI.now = now
CMI.playSound = playSound
CMI.stackTop = stackTop
require("src.coop.CoopWarp").install(CoopManager, CMI)

-- ---------------------------------------------------------------------
-- co-op battle invites
-- (src/coop/CoopInvites.lua)
CMI.CoopManager = CoopManager
CMI.CoopNet = CoopNet
CMI.GEN1_LEADER_BADGES = GEN1_LEADER_BADGES
CMI.GameVersion = GameVersion
CMI.INVITE_TIMEOUT = INVITE_TIMEOUT
CMI.LEADER_BADGES = LEADER_BADGES
CMI.Pokemon = Pokemon
CMI.Strings = Strings
CMI.getGame = getGame
CMI.healthyCount = healthyCount
CMI.mapsMatch = mapsMatch
CMI.now = now
CMI.overworldIdle = overworldIdle
CMI.removeState = removeState
require("src.coop.CoopInvites").install(CoopManager, CMI)
local markTrainerBeaten, newInviteId, startPendingBattle, wireMon = CMI.markTrainerBeaten, CMI.newInviteId, CMI.startPendingBattle, CMI.wireMon

-- ---------------------------------------------------------------------
-- READY / NOT READY: before a gym or the League, each one says when they
-- (src/coop/CoopReady.lua)
CMI.CoopManager = CoopManager
CMI.GameVersion = GameVersion
CMI.INVITE_TIMEOUT = INVITE_TIMEOUT
CMI.Strings = Strings
CMI.getGame = getGame
CMI.healthyCount = healthyCount
CMI.mapsMatch = mapsMatch
CMI.newInviteId = newInviteId
CMI.now = now
CMI.overworldIdle = overworldIdle
CMI.removeState = removeState
CMI.startPendingBattle = startPendingBattle
CMI.wireMon = wireMon
require("src.coop.CoopReady").install(CoopManager, CMI)

-- ---------------------------------------------------------------------
-- chat & interaction
-- (src/coop/CoopChat.lua)
CMI.CoopManager = CoopManager
CMI.Strings = Strings
CMI.getGame = getGame
CMI.now = now
CMI.playSound = playSound
CMI.stackTop = stackTop
require("src.coop.CoopChat").install(CoopManager, CMI)
local coopBattleOnTop, tickLive = CMI.coopBattleOnTop, CMI.tickLive

-- ---------------------------------------------------------------------
-- message handlers
-- (src/coop/CoopHandlers.lua)
CMI.CoopLog = CoopLog
CMI.CoopManager = CoopManager
CMI.HOF_PARTNER_MAPS = HOF_PARTNER_MAPS
CMI.SHARED_RULES = SHARED_RULES
CMI.applyPartnerInfo = applyPartnerInfo
CMI.completeHandshake = completeHandshake
CMI.freshPartner = freshPartner
CMI.getGame = getGame
CMI.incompatible = incompatible
CMI.markTrainerBeaten = markTrainerBeaten
CMI.now = now
CMI.playSound = playSound
CMI.resetSession = resetSession
CMI.sendHello = sendHello
require("src.coop.CoopHandlers").install(CoopManager, CMI)

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
  -- the chat drawn inside a battle goes with the battle (or when something
  -- else, a party screen, comes over it)
  local overlay = CoopManager.chatOverlay
  if overlay and not coopBattleOnTop(overlay.game) then pcall(overlay.cancel, overlay) end
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

  local buf = CoopManager.incomingInviteBuffer
  if buf then
    local bOw = buf.ow or ow
    local bGame = getGame(bOw)
    if CoopManager.isLocalInBattle(bOw) then
      CoopManager.net:send({ type = "coop_battle_decline", inviteId = buf.msg.inviteId, reason = "in_battle" })
      CoopManager.incomingInviteBuffer = nil
    elseif overworldIdle(bGame, bOw) then
      local msg = buf.msg
      local isBig = buf.isBigBattle
      CoopManager.incomingInviteBuffer = nil
      if isBig then
        CoopManager.onBigBattleInvite(bOw, msg)
      else
        CoopManager.onBattleInviteReceived(bOw, msg)
      end
    elseif now() >= buf.deadline then
      CoopManager.net:send({ type = "coop_battle_decline", inviteId = buf.msg.inviteId, reason = "busy" })
      CoopManager.incomingInviteBuffer = nil
    end
  end
  -- the link's notices, one after another on the status line
  local notices = CoopManager.pendingNotices
  if notices and #notices > 0 then
    CoopManager.noticeTimer = (CoopManager.noticeTimer or 0) - dt
    if CoopManager.noticeTimer <= 0 then
      CoopManager.showStatus(table.remove(notices, 1), 3.5)
      CoopManager.noticeTimer = 3.5
    end
  end
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

  -- THE SAVE PLAYED CHANGED UNDER THE LINK.  Linked from the title screen,
  -- the hello (and the transport's identity) carried the boot save's id;
  -- CONTINUE then loads the real save.  The partner is told the new id (it
  -- is the one this copy comes back with after a drop) along with the name.
  local myId = game and game.save and CoopManager.coopId(game.save)
  local idChanged = myId ~= nil and CoopManager.net.identity ~= myId
  if idChanged then stampIdentity() end
  local pName = CoopManager.getLocalPlayerName(game)
  if pName ~= "HOST" and pName ~= "GUEST" and (pName ~= CoopManager.lastSyncedName or idChanged) then
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
-- (src/coop/CoopHud.lua)
CMI.CoopLog = CoopLog
CMI.CoopManager = CoopManager
CMI.Font = Font
CMI.Tilt = Tilt
CMI.getGame = getGame
CMI.mapsMatch = mapsMatch
CMI.now = now
CMI.partnerFrameOffset = partnerFrameOffset
CMI.stackTop = stackTop
require("src.coop.CoopHud").install(CoopManager, CMI)
