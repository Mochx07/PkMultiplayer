-- src/coop/CoopMinigame.lua
-- THE MINIGAME FRAME (1.20, M3): what every co-op minigame shares, so each
-- game is only its own rules.
--
--   * invite: one player picks a game (co-op menu > MINIGAMES); the other is
--     asked (JOIN / DECLINE).  A game is offered only when BOTH copies have
--     its capability ("minigame.<id>"), so a partner without it never sees it.
--   * start: on JOIN the asker deals the seed and both start a 3-second
--     countdown when they hear about it (the two clocks are not one; a
--     minigame is not lockstep -- each copy plays its own player and sends
--     its score, so a few frames between the two starts do not matter).
--   * play: the game's own update/draw run on each copy; the frame keeps the
--     clock (def.duration seconds) and both scores (each copy reports its
--     own with session:setScore; the partner's arrives as coop_mg_score).
--   * end: time up (or session:finish()) -> each copy sends its FINAL score;
--     once both are in (or after a grace) both show the same result, worked
--     out the same way from the same two numbers.  Either player leaving
--     (B for 1 s, the link dropping) ends it on both with no winner.
--
-- A game module registers itself:
--   CoopMinigame.register({
--     id = "karp",                         -- short, [%w_]
--     name = "MAGIKARP CONTEST",           -- menu row, <= 16
--     info = { "...", "...", "..." },      -- the box above the row, <= 18 each
--     duration = 120,                      -- seconds of play
--     lowWins = false,                     -- true: the lower score wins (a time)
--     canStart = function(game, ow) return ok, why end,  -- optional, each copy
--     start = function(session, game, ow) end,           -- after the countdown
--     update = function(session, dt, game, ow) end,
--     draw = function(session, ow) end,                  -- over the field
--     scoreText = function(score) return "84.2 cm" end,  -- optional
--     finish = function(session, game, result) end,      -- optional, both copies
--     quietField = true,   -- optional: no wild encounter or trainer sight while on
--     waitForPartner = true, -- optional: finishing early waits for the partner's whole clock
--   })
-- session fields: id, seed, session:random(...) (like math.random, seeded:
-- the same sequence on both copies), asker (bool), t (seconds played),
-- score, partnerScore, data (the game's own table).
local CoopMinigame = {}

CoopMinigame.GAMES = {}
CoopMinigame.ORDER = {}
CoopMinigame.COUNTDOWN = 3
CoopMinigame.RESULT_GRACE = 8     -- seconds to wait for the partner's final score
CoopMinigame.RESULT_SHOW = 6
CoopMinigame.INVITE_TIMEOUT = 25
CoopMinigame.session = nil
CoopMinigame.pending = nil        -- our invite, waiting for an answer
CoopMinigame.asked = nil          -- their invite, on screen

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end
local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
local function T(s) return require("src.coop.CoopI18n").t(s) end

function CoopMinigame.register(def)
  assert(type(def) == "table" and type(def.id) == "string" and def.id:match("^[%w_]+$"), "minigame id")
  assert(type(def.name) == "string" and type(def.start) == "function", "minigame name/start")
  if not CoopMinigame.GAMES[def.id] then CoopMinigame.ORDER[#CoopMinigame.ORDER + 1] = def.id end
  CoopMinigame.GAMES[def.id] = def
  local CM = manager()
  if CM and CM.registerCap then CM.registerCap("minigame." .. def.id) end
  return def
end

-- the games both copies can play, in the order they registered
function CoopMinigame.available()
  local CM = manager()
  local out = {}
  for _, id in ipairs(CoopMinigame.ORDER) do
    if CM and CM.bothHave and CM.bothHave("minigame." .. id) then out[#out + 1] = CoopMinigame.GAMES[id] end
  end
  return out
end

-- a game that asked for a quiet field (def.quietField) is on: no wild
-- encounter and no trainer spotting the player (lib/Hooks.lua asks)
function CoopMinigame.fieldQuiet()
  local s = CoopMinigame.session
  return s ~= nil and s.def ~= nil and s.def.quietField == true and s.phase ~= "result"
end

-- ---------------------------------------------------------------------
-- the session
-- ---------------------------------------------------------------------

local Session = {}
Session.__index = Session

local function newSession(def, mid, seed, asker)
  -- its own generator (Park-Miller; exact in a double), so the sequence is
  -- the same on both copies whatever the engine or love.math do
  local state = (math.floor(tonumber(seed) or 1) % 2147483646) + 1
  return setmetatable({ def = def, id = def.id, mid = mid, seed = seed, rngState = state, asker = asker,
                        phase = "countdown", clock = CoopMinigame.COUNTDOWN, t = 0,
                        score = 0, partnerScore = nil, final = nil, partnerFinal = nil,
                        data = {}, holdB = 0 }, Session)
end
CoopMinigame.newSession = newSession

-- like math.random: () -> [0,1), (n) -> 1..n, (a, b) -> a..b; the same on both copies
function Session:random(a, b)
  self.rngState = (self.rngState * 48271) % 2147483647
  local f = (self.rngState - 1) / 2147483646
  if a == nil then return f end
  if b == nil then a, b = 1, a end
  return a + math.floor(f * (b - a + 1))
end

function Session:setScore(v)
  self.score = v
  local CM = manager()
  -- the partner's HUD follows; a few a second are plenty
  local t = now()
  if CM and CM.net and (not self.lastSent or t - self.lastSent > 0.25) then
    self.lastSent = t
    CM.net:send({ type = "coop_mg_score", mid = self.mid, score = v })
  end
end

-- the game says it is over for this player (a race finished, a find made)
function Session:finish()
  if self.phase ~= "play" then return end
  self.phase = "waitResult"
  self.final = self.score
  -- def.waitForPartner (a race): the partner may still be playing, and their
  -- final comes at their time-up at the latest -- wait out the clock too
  self.clock = CoopMinigame.RESULT_GRACE + (self.def.waitForPartner and math.max(0, self.clock) or 0)
  local CM = manager()
  if CM and CM.net then CM.net:send({ type = "coop_mg_final", mid = self.mid, score = self.final }) end
  CoopMinigame.settle(self)
end

-- both copies decide the same way from the same two numbers
function CoopMinigame.outcome(def, mine, theirs)
  if mine == nil and theirs == nil then return "none" end
  if theirs == nil then return "win" end
  if mine == nil then return "lose" end
  if mine == theirs then return "draw" end
  local better = def.lowWins and (mine < theirs) or (not def.lowWins and mine > theirs)
  return better and "win" or "lose"
end

function CoopMinigame.settle(s, force)
  if s.phase ~= "waitResult" then return end
  if s.partnerFinal == nil and not force then return end
  s.result = CoopMinigame.outcome(s.def, s.final, s.partnerFinal)
  s.phase = "result"
  s.clock = CoopMinigame.RESULT_SHOW
  local CM = manager()
  if CM and CM.showStatus then
    local key = ({ win = "You win!", lose = "%s wins!", draw = "A draw!", none = "Nobody played" })[s.result]
    CM.showStatus(string.format(T(key), tostring(CM.partner and CM.partner.name or "PARTNER")), 4)
  end
  if s.def.finish then pcall(s.def.finish, s, CoopMinigame.game, s.result) end
end

function CoopMinigame.abort(reason, tell)
  local s = CoopMinigame.session
  if not s then return end
  CoopMinigame.session = nil
  local CM = manager()
  if tell and CM and CM.net then CM.net:send({ type = "coop_mg_quit", mid = s.mid }) end
  if s.def.finish then pcall(s.def.finish, s, CoopMinigame.game, "quit") end
  if CM and CM.showStatus then CM.showStatus(T(reason or "The game was stopped"), 3) end
end

function CoopMinigame.update(dt, game, ow)
  CoopMinigame.game = game
  local s = CoopMinigame.session
  if not s then return end
  local CM = manager()
  if not (CM and CM.isConnected and CM.isConnected()) then
    CoopMinigame.abort("The link dropped: game over", false)
    return
  end
  -- B held for a second leaves the game (on both)
  local input = game and game.input
  if input and input.isDown and input:isDown("b") and s.phase ~= "result" then
    s.holdB = s.holdB + dt
    if s.holdB >= 1 then CoopMinigame.abort("You left the game", true) return end
  else
    s.holdB = 0
  end
  if s.phase == "countdown" then
    s.clock = s.clock - dt
    if s.clock <= 0 then
      s.phase = "play"
      s.clock = s.def.duration or 60
      local ok, err = pcall(s.def.start, s, game, ow)
      if not ok then
        require("src.coop.CoopLog").error("MINIGAME", s.id .. " start: " .. tostring(err))
        CoopMinigame.abort("The game could not start", true)
      end
    end
  elseif s.phase == "play" then
    s.t = s.t + dt
    s.clock = s.clock - dt
    if s.def.update then
      local ok, err = pcall(s.def.update, s, dt, game, ow)
      if not ok then require("src.coop.CoopLog").error("MINIGAME", s.id .. " update: " .. tostring(err)) end
    end
    if s.phase == "play" and s.clock <= 0 then s:finish() end
  elseif s.phase == "waitResult" then
    s.clock = s.clock - dt
    if s.clock <= 0 then CoopMinigame.settle(s, true) end
  elseif s.phase == "result" then
    s.clock = s.clock - dt
    if s.clock <= 0 then CoopMinigame.session = nil end
  end
end

-- the clock and both scores along the top, then the game's own drawing
function CoopMinigame.draw(ow)
  local s = CoopMinigame.session
  if not s then return end
  if s.phase == "play" and s.def.draw then s.def.draw(s, ow) end
  local Font = require("src.render.Font")
  local CM = manager()
  local I18n = require("src.coop.CoopI18n")
  local fmt = s.def.scoreText or function(v) return tostring(v) end
  love.graphics.setColor(1, 1, 1, 1)
  -- five rows: the third line (the partner's score) clears the bottom edge
  Font.drawBox(0, 0, 20, 5)
  love.graphics.setColor(0, 0, 0, 1)
  local top
  if s.phase == "countdown" then
    top = I18n.fit(T(s.def.name), 12) .. "  " .. tostring(math.max(1, math.ceil(s.clock)))
  elseif s.phase == "play" then
    local secs = math.max(0, math.ceil(s.clock))
    top = I18n.fit(T(s.def.name), 12) .. string.format(" %d:%02d", math.floor(secs / 60), secs % 60)
  elseif s.phase == "waitResult" then
    top = I18n.fit(T("Waiting for partner"), 18)
  else
    local key = ({ win = "You win!", lose = "%s wins!", draw = "A draw!", none = "Nobody played" })[s.result] or ""
    top = I18n.fit(string.format(T(key), tostring(CM and CM.partner.name or "PARTNER")), 18)
  end
  Font.draw(top, 8, 8)
  local me = I18n.truncate(tostring(CM and CM.getLocalPlayerName and CM.getLocalPlayerName(CoopMinigame.game) or "YOU"):upper(), 7)
  local them = I18n.truncate(tostring(CM and CM.partner.name or "PARTNER"):upper(), 7)
  local theirs = s.partnerFinal or s.partnerScore
  Font.draw(I18n.fit(me .. " " .. fmt(s.final or s.score), 18), 8, 16)
  Font.draw(I18n.fit(them .. " " .. (theirs ~= nil and fmt(theirs) or "-"), 18), 8, 24)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------
-- invites
-- ---------------------------------------------------------------------

function CoopMinigame.invite(game, id, ow)
  local CM = manager()
  local def = CoopMinigame.GAMES[id]
  if not (CM and def and CM.isConnected and CM.isConnected()) then return false end
  if not CM.bothHave("minigame." .. id) then CM.showStatus(T("Partner can't play that"), 2.5) return false end
  if CoopMinigame.session or CoopMinigame.pending then CM.showStatus(T("A game is already on"), 2.5) return false end
  if def.canStart then
    local ok, why = def.canStart(game, ow)
    if not ok then CM.showStatus(T(why or "Not here"), 2.5) return false end
  end
  local mid = string.format("M%d-%d", os.time(), math.random(1, 2 ^ 24))
  local pName = string.upper(CM.partner.name or "PARTNER")
  local modal = require("src.coop.CoopWaitModal").new(game, pName, function(reason)
    if CoopMinigame.pending and CoopMinigame.pending.mid == mid then
      CoopMinigame.pending = nil
      CM.net:send({ type = "coop_mg_cancel", mid = mid })
      if reason == "timeout" then CM.showStatus(pName .. " didn't answer", 2.5) end
    end
  end, CoopMinigame.INVITE_TIMEOUT + 2, { lines = { "ASKING " .. pName, T(def.name) .. "?" }, cancelLabel = "B: CANCEL" })
  CoopMinigame.pending = { mid = mid, id = id, modal = modal }
  game.stack:push(modal)
  CM.net:send({ type = "coop_mg_invite", mid = mid, game = id, name = CM.getLocalPlayerName(game) })
  return true
end

local function closeModal(game, modal)
  if not modal then return end
  modal.done = true
  local CM = manager()
  if CM and CM.removeState then CM.removeState(game, modal) end
end

function CoopMinigame.onInvite(game, msg)
  local CM = manager()
  if not (CM and game) then return end
  local function answer(kind, reason) CM.net:send({ type = kind, mid = msg.mid, reason = reason }) end
  local def = CoopMinigame.GAMES[msg.game]
  if not def then answer("coop_mg_decline", "unknown") return end
  if CoopMinigame.session or CoopMinigame.pending or CoopMinigame.asked then answer("coop_mg_decline", "busy") return end
  if not (CM.overworldIdle and CM.overworldIdle(game, game.overworld)) then answer("coop_mg_decline", "busy") return end
  if def.canStart then
    local ok = def.canStart(game, game.overworld)
    if not ok then answer("coop_mg_decline", "here") return end
  end
  local who = string.upper(tostring(msg.name or CM.partner.name or "PARTNER"))
  local Invite = require("src.coop.CoopBattleInviteModal")
  local modal = Invite.new(game, who, "", function()
    CoopMinigame.asked = nil
    answer("coop_mg_accept")
  end, function()
    CoopMinigame.asked = nil
    answer("coop_mg_decline", "declined")
  end)
  modal.inviteId = msg.mid
  modal.timeout = CoopMinigame.INVITE_TIMEOUT
  local I18n = require("src.coop.CoopI18n")
  modal.lines = { I18n.truncate(who, 16), T("WANTS TO PLAY!"), I18n.fit(T(def.name), 16) }
  CoopMinigame.asked = modal
  game.stack:push(modal)
end

-- the asker hears yes: it deals the seed and starts; the partner starts on GO
function CoopMinigame.onAccept(game, msg)
  local p = CoopMinigame.pending
  if not (p and p.mid == msg.mid) then return end
  CoopMinigame.pending = nil
  closeModal(game, p.modal)
  -- love.math, not math.random: nothing seeds the latter, so every first game
  -- of a launch was dealt the same seed (the same treasure cell each time)
  local lm = love and love.math and love.math.random
  local seed = lm and lm(1, 2 ^ 30) or math.random(1, 2 ^ 30)
  local CM = manager()
  CM.net:send({ type = "coop_mg_go", mid = p.mid, game = p.id, seed = seed })
  CoopMinigame.session = newSession(CoopMinigame.GAMES[p.id], p.mid, seed, true)
end

function CoopMinigame.onGo(game, msg)
  local def = CoopMinigame.GAMES[msg.game]
  if not def or CoopMinigame.session then return end
  CoopMinigame.session = newSession(def, msg.mid, tonumber(msg.seed) or 1, false)
end

function CoopMinigame.onDecline(game, msg)
  local p = CoopMinigame.pending
  if not (p and p.mid == msg.mid) then return end
  CoopMinigame.pending = nil
  closeModal(game, p.modal)
  local CM = manager()
  local why = ({ busy = "Partner is busy", here = "Partner can't play there" })[msg.reason] or "Partner said no"
  if CM then CM.showStatus(T(why), 2.5) end
end

function CoopMinigame.onCancel(game, msg)
  local modal = CoopMinigame.asked
  if modal and modal.inviteId == msg.mid then
    CoopMinigame.asked = nil
    closeModal(game, modal)
  end
end

function CoopMinigame.onScore(msg)
  local s = CoopMinigame.session
  if s and s.mid == msg.mid and tonumber(msg.score) then s.partnerScore = tonumber(msg.score) end
end

function CoopMinigame.onFinal(msg)
  local s = CoopMinigame.session
  if not (s and s.mid == msg.mid) then return end
  s.partnerFinal = tonumber(msg.score)
  s.partnerScore = s.partnerFinal
  CoopMinigame.settle(s)
end

function CoopMinigame.onQuit(msg)
  local s = CoopMinigame.session
  if s and s.mid == msg.mid then CoopMinigame.abort("Partner left the game", false) end
end

-- ---------------------------------------------------------------------
-- wiring into the manager
-- ---------------------------------------------------------------------

local CM = manager()
if CM and CM.handlers then
  local H = CM.handlers
  local g = function(ow) return CM.getGame(ow) end
  H.coop_mg_invite = function(ow, msg) CoopMinigame.onInvite(g(ow), msg) end
  H.coop_mg_accept = function(ow, msg) CoopMinigame.onAccept(g(ow), msg) end
  H.coop_mg_decline = function(ow, msg) CoopMinigame.onDecline(g(ow), msg) end
  H.coop_mg_cancel = function(ow, msg) CoopMinigame.onCancel(g(ow), msg) end
  H.coop_mg_go = function(ow, msg) CoopMinigame.onGo(g(ow), msg) end
  H.coop_mg_score = function(_, msg) CoopMinigame.onScore(msg) end
  H.coop_mg_final = function(_, msg) CoopMinigame.onFinal(msg) end
  H.coop_mg_quit = function(_, msg) CoopMinigame.onQuit(msg) end
  if CM.onTick then CM.onTick("minigame", function(dt, game, ow) CoopMinigame.update(dt, game, ow) end) end
  -- the link gone: the tickers above stop, so this one ends the game
  if CM.onIdleTick then
    CM.onIdleTick("minigame", function()
      if CoopMinigame.session and not (CM.isConnected and CM.isConnected()) then
        CoopMinigame.abort("The link dropped: game over", false)
      end
    end)
  end
  if CM.onDraw then CM.onDraw("minigame", CoopMinigame.draw) end
end

return CoopMinigame
