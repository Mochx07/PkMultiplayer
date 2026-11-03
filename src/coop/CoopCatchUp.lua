-- src/coop/CoopCatchUp.lua
-- NOBODY LEFT BEHIND, NOBODY WAITING FOR NOTHING.
--
--   * A scene's hold outlives its scene no longer.  WAIT (CoopStory) and a
--     big battle's CO-OP (CoopInvites) tell the partner's game to hold its
--     own copy of the scene, and the scene's end lifts it.  A scene that
--     never reaches its end -- a script error, or the engine putting a
--     stranded script down (OverworldState:watchStuckScript) -- never lifted
--     it: for HOLD_MAX (15 minutes) the partner talked to that leader, or
--     walked onto that rival's floor, and nothing happened.  The hold now
--     goes when the script that sent it is gone, however it went.
--
--   * CATCH UP.  The player with fewer badges than the partner can ask to
--     fly to the partner's last key town -- the last new town their story
--     reached -- the way WARP TO PARTNER works: the partner has to say YES,
--     it shares the warp's cooldown, and nobody is moved out of a battle, a
--     conversation or the water.  Before asking, the box says which badges
--     the partner has and you do not.  It hands out nothing: the badges are
--     still to be won.
--
--   * A TEAM FAR BEHIND (CoopBalance).  In a co-op battle where your three
--     are GAP levels or more under the partner's, your Pokemon earn boosted
--     EXP (the cartridge's own x1.5, as a traded Pokemon does), and -- when
--     both copies have this module -- the foe is no longer levelled up
--     against the stronger team's levels alone.
--
-- What travels (coop_catchup_info / _req / _reply, and `catchUp` in a
-- battle's foe rules) goes only to a partner that has the `story.catchup`
-- capability: a 1.6.x partner sees none of it, and the CATCH UP row is not
-- offered with them.

local CoopManager = require("src.coop.CoopManager")
local I18n = require("src.coop.CoopI18n")

local CoopCatchUp = {}

CoopCatchUp.CAP = "story.catchup"
CoopManager.registerCap(CoopCatchUp.CAP)

CoopCatchUp.GAP = 8              -- levels between the two teams that count as "far behind"
CoopCatchUp.ASK_TIMEOUT = 30     -- seconds a CATCH UP request waits for its answer

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function log(msg)
  pcall(function() require("src.coop.CoopLog").info("CATCHUP", msg) end)
end

local function partnerName()
  return I18n.truncate(string.upper(CoopManager.partner and CoopManager.partner.name or "PARTNER"), 7)
end

-- ---------------------------------------------------------------------
-- 1. the hold goes with its script
-- ---------------------------------------------------------------------

CoopCatchUp.holdCtx = nil   -- the script context that sent the hold in force

-- Every frame while linked: a context that sent a hold (ctx.coopHoldSent) is
-- remembered while its script runs; the moment the runner is no longer
-- running it, a hold still marked as sent is lifted.
function CoopCatchUp.watchHold(game)
  local ow = game and game.overworld
  local runner = ow and ow.runner
  local running = runner and runner.isRunning and runner:isRunning()
  local ctx = running and runner.ctx or nil
  if ctx and ctx.coopHoldSent then CoopCatchUp.holdCtx = ctx end
  local held = CoopCatchUp.holdCtx
  if not held then return false end
  if not held.coopHoldSent then
    CoopCatchUp.holdCtx = nil   -- lifted the usual way, at the scene's end
    return false
  end
  if running and runner.ctx == held then return false end
  CoopCatchUp.holdCtx = nil
  local CoopStory = require("src.coop.CoopStory")
  if CoopStory.releaseHold then
    CoopStory.releaseHold(held)
    log("the scene that held the partner ended early; hold lifted (" .. tostring(held.coopHoldSent_map) .. ")")
    return true
  end
  return false
end

-- ---------------------------------------------------------------------
-- 2. CATCH UP
-- ---------------------------------------------------------------------

-- the badges, as a short name each ("HIVEBADGE" -> "HIVE")
local function shortBadge(id)
  return (tostring(id):gsub("BADGE$", ""):gsub("^BADGE_", ""))
end
CoopCatchUp.shortBadge = shortBadge

function CoopCatchUp.badgeIds(game)
  local out = {}
  local data, save = game and game.data, game and game.save
  if not save then return out end
  local Badges = require("src.inventory.Badges")
  for _, entry in ipairs(Badges.list(data)) do
    if Badges.has(save, entry) then out[#out + 1] = entry.id end
  end
  return out
end

-- a town FLY lands in (an outdoor map with a fly spot), in this game's data
function CoopCatchUp.isTown(game, mapId)
  local data = game and game.data
  if not (data and type(mapId) == "string") then return false end
  local warps = (data.field or {}).flyWarps or {}
  local def = data.maps and data.maps[mapId]
  if not (warps[mapId] and def) then return false end
  local okMap, Map = pcall(require, "src.world.Map")
  return okMap and Map.isOutdoor and Map.isOutdoor(def) or false
end

-- This player's key town: the last town their story reached for the first
-- time (save.coopKeyTown).  A save that never kept one starts from the
-- furthest town it has been to, in FLY's order (story order in Johto).
function CoopCatchUp.keyTown(game)
  local save = game and game.save
  if not save then return nil end
  local data = game.data
  local order = (data and data.field or {}).flyOrder or {}
  if type(save.coopTownsSeen) ~= "table" then
    local seen, last = {}, nil
    for _, id in ipairs(order) do
      if (save.visited or {})[id] and CoopCatchUp.isTown(game, id) then
        seen[id] = true
        last = id
      end
    end
    save.coopTownsSeen = seen
    save.coopKeyTown = save.coopKeyTown or last
  end
  return save.coopKeyTown
end

-- standing in a town this save has not reached before: it is the new key town
function CoopCatchUp.noteTown(game)
  local ow = game and game.overworld
  local map = ow and ow.map and ow.map.id
  if not (map and game.save) then return false end
  CoopCatchUp.keyTown(game)
  local seen = game.save.coopTownsSeen
  if seen[map] or not CoopCatchUp.isTown(game, map) then return false end
  seen[map] = true
  game.save.coopKeyTown = map
  return true
end

-- what we tell the partner: our key town and our badges
function CoopCatchUp.info(game)
  return { type = "coop_catchup_info", town = CoopCatchUp.keyTown(game), badges = CoopCatchUp.badgeIds(game) }
end

CoopCatchUp.sentFor = nil    -- the partner table (one per session) our info went to
CoopCatchUp.sentSig = nil

function CoopCatchUp.sendInfo(game, force)
  if not (CoopManager.bothHave(CoopCatchUp.CAP) and CoopManager.net) then return false end
  local msg = CoopCatchUp.info(game)
  local sig = tostring(msg.town) .. "|" .. table.concat(msg.badges, ",")
  if not force and CoopCatchUp.sentFor == CoopManager.partner and CoopCatchUp.sentSig == sig then
    return false
  end
  CoopCatchUp.sentFor, CoopCatchUp.sentSig = CoopManager.partner, sig
  CoopManager.net:send(msg)
  return true
end

function CoopCatchUp.onInfo(msg)
  if type(msg) ~= "table" then return end
  local badges = {}
  if type(msg.badges) == "table" then
    for i = 1, math.min(#msg.badges, 32) do
      local id = msg.badges[i]
      if type(id) == "string" and #id <= 24 then badges[#badges + 1] = id end
    end
  end
  CoopManager.partner.catchup = {
    town = type(msg.town) == "string" and #msg.town <= 48 and msg.town or nil,
    badges = badges,
  }
end

-- the partner's badges this player lacks, in the game's badge order
function CoopCatchUp.missing(game)
  local info = CoopManager.partner and CoopManager.partner.catchup
  local out = {}
  if not (info and game and game.save) then return out end
  local theirs = {}
  for _, id in ipairs(info.badges or {}) do theirs[id] = true end
  local Badges = require("src.inventory.Badges")
  for _, entry in ipairs(Badges.list(game.data)) do
    if theirs[entry.id] and not Badges.has(game.save, entry) then out[#out + 1] = entry.id end
  end
  return out
end

-- behind: the partner holds more badges than we do
function CoopCatchUp.behind(game)
  local info = CoopManager.partner and CoopManager.partner.catchup
  if not (info and CoopManager.isConnected and CoopManager.isConnected()) then return false end
  if not CoopManager.bothHave(CoopCatchUp.CAP) then return false end
  return #(info.badges or {}) > #CoopCatchUp.badgeIds(game) and #CoopCatchUp.missing(game) > 0
end

-- the CATCH UP row is offered at all
function CoopCatchUp.available(game)
  return CoopCatchUp.behind(game)
end

function CoopCatchUp.townLabel(game, mapId)
  local warps = (game and game.data and game.data.field or {}).flyWarps or {}
  local w = warps[mapId]
  local name = (w and type(w.name) == "string" and w.name ~= "" and w.name) or CoopManager.mapLabel(mapId)
  return string.upper(name)
end

-- ok, reason: can this player be flown to the partner's key town now?
-- `answered`: the partner has just said yes (their box may still be closing)
function CoopCatchUp.canCatchUp(game, ow, answered)
  local p = CoopManager.partner
  if not (CoopManager.isConnected() and p) then return false, "No partner available" end
  if not CoopCatchUp.behind(game) then return false, "You are not behind" end
  local town = p.catchup and p.catchup.town
  if not (town and CoopCatchUp.isTown(game, town)) then return false, "No town to go to" end
  if not (ow and ow.flyTo and ow.map) or ow.transitioning then return false, "Can't warp right now" end
  if CoopManager.isLocalInBattle(ow) then return false, "Can't warp in battle!" end
  local left = CoopManager.warpCooldownLeft()
  if left > 0 then
    local secs = math.ceil(left)
    return false, string.format("Warp ready in %d:%02d", math.floor(secs / 60), secs % 60)
  end
  if CoopManager.mapsMatch(town, ow.map.id) then return false, "You are already there" end
  if p.inBattle or ((p.busy or p.inDialogue) and not answered) then return false, "Partner is busy" end
  -- heard from lately, on a link that is not stalling (anywhere: they need
  -- not be near the town)
  if not answered and CoopManager.partnerReachable then
    local okR, whyR = CoopManager.partnerReachable(ow, true)
    if not okR then return false, whyR end
  end
  if (CoopManager.isLocalInDialogue(ow) and not answered) or (ow.player and ow.player.surfing) then
    return false, "Can't warp now!"
  end
  return true, town
end

-- The box the CATCH UP row opens: what you lack, then "meet them there?"
function CoopCatchUp.describe(game)
  local missing = CoopCatchUp.missing(game)
  local names = {}
  for _, id in ipairs(missing) do names[#names + 1] = I18n.t(shortBadge(id)) end
  -- two badges a line, two lines a page
  local lines = {}
  for i = 1, #names, 2 do
    lines[#lines + 1] = names[i] .. (names[i + 1] and (", " .. names[i + 1]) or "")
  end
  local pages = {}
  for i = 1, #lines, 2 do
    pages[#pages + 1] = lines[i] .. (lines[i + 1] and ("\n" .. lines[i + 1]) or "")
  end
  local who = partnerName()
  local head = string.format(I18n.t("%s has %d\nbadges you lack:"), who, #missing)
  return head .. "\f" .. table.concat(pages, "\f"), missing
end

CoopCatchUp.ask = nil   -- { id, at, town }: the request we are waiting on
local askSeq = 0

function CoopCatchUp.asking()
  local a = CoopCatchUp.ask
  return a ~= nil and (now() - a.at) <= CoopCatchUp.ASK_TIMEOUT
end

-- the CATCH UP row
function CoopCatchUp.open(game, ow)
  local TextBox = I18n.textBox()
  if not (game and game.stack) then return false end
  if not CoopCatchUp.behind(game) then
    CoopManager.showStatus("You are not behind", 2.5)
    return false
  end
  local text = CoopCatchUp.describe(game)
  local ok, town = CoopCatchUp.canCatchUp(game, ow)
  if not ok then
    -- still worth knowing what is missing; why there is no flight after it
    game.stack:push(require("src.render.TextBox").new(game, text, function() CoopManager.showStatus(town, 2.5) end))
    return false
  end
  local q = string.format(I18n.t("Meet %s in\n%s?"), partnerName(), CoopCatchUp.townLabel(game, town))
  -- the box is translated piece by piece above; the proxy's t() leaves it be
  game.stack:push(require("src.render.TextBox").new(game, text .. "\f" .. q, nil, {
    defaultNo = true,
    choice = function(yes) if yes then CoopCatchUp.request(game, ow) end end,
  }))
  return true
end

function CoopCatchUp.request(game, ow)
  local ok, town = CoopCatchUp.canCatchUp(game, ow, true)
  if ok and (CoopCatchUp.asking() or (CoopManager.warpAsking and CoopManager.warpAsking())) then
    ok, town = false, "Waiting for an answer"
  end
  if not ok then
    CoopManager.showStatus(town, 2.5)
    return false
  end
  askSeq = askSeq + 1
  CoopCatchUp.ask = { id = askSeq, at = now(), town = town }
  CoopManager.net:send({ type = "coop_catchup_req", id = askSeq, town = town })
  CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to catch up", 3)
  return true
end

-- the partner's side: only a player idle in the overworld is asked at all
function CoopCatchUp.onRequest(game, ow, msg)
  local function reply(yes, why)
    CoopManager.net:send({ type = "coop_catchup_reply", id = msg.id, ok = yes, why = why })
  end
  local idle = game and game.stack and ow and game.stack:top() == ow and not ow.transitioning
               and not CoopManager.isLocalInBattle(ow) and not CoopManager.isLocalInDialogue(ow)
  if not idle then return reply(false, "busy") end
  local TextBox = I18n.textBox()
  game.stack:push(TextBox.new(game, (CoopManager.partner.name or "Your partner") .. " wants to\ncatch up. OK?", nil, {
    defaultNo = true,
    choice = function(yes) reply(yes == true) end,
  }))
end

-- ours again: the answer.  Checked again -- the world moved while they decided.
function CoopCatchUp.onReply(game, ow, msg)
  local a = CoopCatchUp.ask
  if not (a and a.id == msg.id) then return false end
  CoopCatchUp.ask = nil
  local name = CoopManager.partner.name or "Partner"
  if (now() - a.at) > CoopCatchUp.ASK_TIMEOUT then return false end
  if not msg.ok then
    CoopManager.showStatus(msg.why == "busy" and (name .. " is busy") or (name .. " said no"), 3)
    return false
  end
  local ok, town = CoopCatchUp.canCatchUp(game, ow, true)
  if not ok then
    CoopManager.showStatus(town, 2.5)
    return false
  end
  CoopManager.lastWarpAt = now()
  ow:flyTo(town)
  CoopManager.net:send({ type = "coop_catchup_done", town = town })
  log("flew to the partner's key town " .. tostring(town))
  return true
end

function CoopCatchUp.tickAsk()
  local a = CoopCatchUp.ask
  if a and (now() - a.at) > CoopCatchUp.ASK_TIMEOUT then
    CoopCatchUp.ask = nil
    CoopManager.showStatus("No answer from " .. (CoopManager.partner.name or "partner"), 3)
  end
end

-- ---------------------------------------------------------------------
-- 3. a team far behind, in a co-op battle
-- ---------------------------------------------------------------------

local function average(list)
  local n, sum = 0, 0
  for _, m in ipairs(list or {}) do
    if type(m) == "table" and not m.isEgg and (tonumber(m.hp) or 1) > 0 then
      n = n + 1
      sum = sum + (tonumber(m.level) or 1)
    end
  end
  return n > 0 and sum / n or nil, n
end
CoopCatchUp.average = average

-- how many levels `mine` (the three this copy picked) trail `theirs` by, on
-- average; 0 when ahead or level
function CoopCatchUp.gap(mine, theirs)
  local a, b = average(mine), average(theirs)
  if not (a and b) then return 0 end
  return math.max(0, b - a)
end

function CoopCatchUp.farBehind(mine, theirs)
  return CoopCatchUp.gap(mine, theirs) >= CoopCatchUp.GAP
end

-- The weaker of the two teams' average level, when they are GAP apart:
-- CoopBalance levels the foe against it rather than against both.  nil
-- when they are close (the usual combined average stands).
function CoopCatchUp.weakerAverage(mine, theirs)
  local a, b = average(mine), average(theirs)
  if not (a and b) or math.abs(a - b) < CoopCatchUp.GAP then return nil end
  return math.min(a, b)
end

-- Run on each copy as its co-op battle is built (CoopBalance.apply).  EXP is
-- paid on the owner's machine only, for the owner's own party (the partner's
-- copy learns the new numbers with the next action: CoopBattle.packOwnState),
-- so this changes nothing the two copies have to agree on.
function CoopCatchUp.prepareBattle(battle, mine, theirs)
  if type(battle) ~= "table" or battle.battleTower or battle.isLinkBattle or battle.coopCatchUpExp then
    return false
  end
  local rules = type(battle.coopBalanceRules) == "table" and battle.coopBalanceRules or CoopManager
  if not (rules.balancedFoes or rules.hardFoes) then return false end
  if not CoopCatchUp.farBehind(mine, theirs) then return false end
  local orig = battle.awardExp
  if type(orig) ~= "function" then return false end
  battle.coopCatchUpExp = true
  battle.awardExp = function(self, ...)
    local party = (self.game and self.game.save and self.game.save.party) or {}
    local was = {}
    for i, m in ipairs(party) do
      if type(m) == "table" then
        was[i] = m.traded
        m.traded = true
      end
    end
    local ok, err = pcall(orig, self, ...)
    for i, m in ipairs(party) do
      if type(m) == "table" then m.traded = was[i] end
    end
    if not ok then error(err, 0) end
  end
  CoopManager.showStatus("Your team is behind: more EXP!", 3)
  log(string.format("team %d levels behind the partner's: boosted EXP", math.floor(CoopCatchUp.gap(mine, theirs))))
  return true
end

-- ---------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------

local function gameOf(ow)
  return CoopManager.getGame(ow)
end

CoopManager.handlers.coop_catchup_info = function(ow, msg) CoopCatchUp.onInfo(msg) end
CoopManager.handlers.coop_catchup_req = function(ow, msg)
  local game = gameOf(ow)
  CoopCatchUp.onRequest(game, (game and game.overworld) or ow, msg)
end
CoopManager.handlers.coop_catchup_reply = function(ow, msg)
  local game = gameOf(ow)
  CoopCatchUp.onReply(game, (game and game.overworld) or ow, msg)
end
CoopManager.handlers.coop_catchup_done = function(ow, msg)
  CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " caught up!", 3)
end

-- READY survives a dropped link on this copy (CoopManager.localReady) but
-- the partner's copy starts the new session knowing nothing of it: the
-- menu said READY ON here while they saw no READY over your head.  Said
-- again once per session (coop_ready is as old as READY: no capability).
CoopCatchUp.readyFor = nil
function CoopCatchUp.resendReady()
  if CoopCatchUp.readyFor == CoopManager.partner then return false end
  CoopCatchUp.readyFor = CoopManager.partner
  if not (CoopManager.localReady and CoopManager.net) then return false end
  CoopManager.net:send({ type = "coop_ready", ready = true })
  return true
end

CoopManager.onTick("catchup", function(dt, game)
  CoopCatchUp.watchHold(game)
  CoopCatchUp.resendReady()
  if game and game.overworld and game.overworld.map and game.save then
    CoopCatchUp.noteTown(game)
    CoopCatchUp.sendInfo(game)
  end
  CoopCatchUp.tickAsk()
end)

return CoopCatchUp
