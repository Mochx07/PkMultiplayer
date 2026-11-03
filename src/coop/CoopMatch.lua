-- src/coop/CoopMatch.lua
-- P1-vs-P2 MATCHES (1.20, capability "vs.match"): one game or the best of
-- three, and the result kept in the VS record (src/coop/CoopRecord.lua).
--
-- The Cable Club plays one link battle and leaves.  A match keeps the
-- Cable Club open instead: when a game ends both copies say who won it
-- (coop_match "result"), and once both reports are in each copy applies the
-- same rule to the same two reports -- the winner both name, or no winner
-- when they differ -- so the score can not drift apart.  Then both go back
-- into the battle without a new invite: the Cable Club sends its party again
-- and the host deals a new seed (LinkState:startMode), so every game is its
-- own battle and leaves its own replay (src/coop/CoopReplay.lua).
--
-- What goes over the tunnel is numbered by game (the coop_link envelope's
-- `game`): the next game's party can arrive while this copy still shows the
-- last game's end, and a late message from the last game must not reach the
-- next battle.  A game without a winner (RUN, a desync, the link gone) or a
-- player leaving -- B between games, or before the battle -- ends the match
-- on both copies with no result.  The asker picks 1 or 3 games; the invite
-- carries it (`best`), and only to a partner that has "vs.match" -- a
-- partner without it gets the single battle it always had.
local CoopMatch = {}

CoopMatch.CAP = "vs.match"
CoopMatch.wantBest = 1          -- what the VS page asks for next (1 or 3)
CoopMatch.NEXT_DELAY = 4        -- seconds the score shows between games
CoopMatch.OVER_DELAY = 6        -- ...and at the end of the match
CoopMatch.WAIT_LIMIT = 90       -- no report from the partner by then: over
CoopMatch.MIN_SHOW = 1          -- A skips the score only after this (the
                                -- player is still mashing through the battle)

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end

function CoopMatch.validBest(n)
  return n == 1 or n == 3
end

-- ---------------------------------------------------------------------
-- the score (pure: the same on both copies)
-- ---------------------------------------------------------------------

-- opts: { best, asker = bool, format, myName, theirName, myId, partnerId }
function CoopMatch.new(opts)
  opts = opts or {}
  local best = opts.best == 3 and 3 or 1
  return {
    best = best, need = math.floor(best / 2) + 1, game = 1,
    asker = opts.asker and true or false, format = opts.format or "free",
    myName = opts.myName or "ME", theirName = opts.theirName or "P2",
    myId = opts.myId, partnerId = opts.partnerId,
    wins = { asker = 0, asked = 0 }, results = {}, mine = {}, theirs = {}, held = {},
  }
end

function CoopMatch.mySide(m) return m.asker and "asker" or "asked" end
function CoopMatch.theirSide(m) return m.asker and "asked" or "asker" end
function CoopMatch.myWins(m) return m.wins[CoopMatch.mySide(m)] end
function CoopMatch.theirWins(m) return m.wins[CoopMatch.theirSide(m)] end

-- a finished link battle's `result` (ours: "win" / "lose" / "draw") -> the
-- side that won it, or "none"
function CoopMatch.winnerOf(m, result)
  if result == "win" then return CoopMatch.mySide(m) end
  if result == "lose" then return CoopMatch.theirSide(m) end
  return "none"
end

-- the two copies' reports -> the game's winner: the one both name, or none
function CoopMatch.agree(a, b)
  if a == b and (a == "asker" or a == "asked") then return a end
  return "none"
end

-- the agreed winner of the game being played -> "next", "won" or "void"
function CoopMatch.apply(m, winner)
  m.results[m.game] = winner
  if winner ~= "asker" and winner ~= "asked" then
    m.over, m.void = true, true
    return "void"
  end
  m.wins[winner] = m.wins[winner] + 1
  if m.wins[winner] >= m.need then
    m.over, m.winner = true, winner
    return "won"
  end
  return "next"
end

-- ---------------------------------------------------------------------
-- the tunnel (CoopLink's adapter) numbered by game
-- ---------------------------------------------------------------------

-- a coop_link message for `t` -> into its inbox, held for a later game, or
-- dropped (an earlier game's)
function CoopMatch.route(t, msg)
  local m = t.match
  local n = tonumber(msg.game)
  if not (m and n) or n == m.game then
    table.insert(t.inbox, msg.payload)
  elseif n > m.game then
    m.held[#m.held + 1] = { game = n, payload = msg.payload }
  end
end

-- the next game: what is left of the last one goes, what waited for this
-- one comes in, and a new recording starts
function CoopMatch.nextGame(t)
  local m = t.match
  m.game = m.game + 1
  m.battle = nil
  t.inbox = {}
  local keep = {}
  for _, e in ipairs(m.held) do
    if e.game == m.game then t.inbox[#t.inbox + 1] = e.payload
    elseif e.game > m.game then keep[#keep + 1] = e end
  end
  m.held = keep
  if t.recInfo then
    t.recInfo.game = m.game
    require("src.coop.CoopReplay").start(t, t.recInfo)
  end
end

local function send(t, msg)
  local CM = manager()
  msg.type, msg.link = "coop_match", t.id
  if CM and CM.net then CM.net:send(msg) end
end

-- the tunnel closes for good with the match still on: the partner is told
function CoopMatch.onClose(t)
  local m = t.match
  if not m or m.over then return end
  m.over = true
  if not m.partnerLeft and not t.closed then
    m.left = true
    send(t, { kind = "leave", game = m.game })
  end
end

-- coop_match from the partner, for the open tunnel (`t`, a test's own)
function CoopMatch.onMessage(msg, t)
  local CoopLink = package.loaded["src.coop.CoopLink"]
  t = t or (CoopLink and CoopLink.adapter)
  local m = t and t.match
  if not (m and msg.link == t.id) then return end
  if msg.kind == "result" then
    local n = tonumber(msg.game)
    if n and type(msg.winner) == "string" then m.theirs[n] = msg.winner end
  elseif msg.kind == "leave" and not m.over then
    -- (a match already settled here ends by itself, with its score shown)
    m.partnerLeft = true
    -- a battle that is still on ends now (LinkBattle reads this as the
    -- cable coming out: a draw)
    t.closed = true
  end
end

-- ---------------------------------------------------------------------
-- the Cable Club, kept open between games
-- ---------------------------------------------------------------------

local MATCH_STAGES = { matchWait = true, matchNext = true, matchOver = true }
CoopMatch.STAGES = MATCH_STAGES

local function i18n() return require("src.coop.CoopI18n") end

local function record(m)
  if not m.winner then return end
  local CoopRecord = require("src.coop.CoopRecord")
  m.recorded = CoopRecord.add({
    myId = m.myId, partnerId = m.partnerId, partnerName = m.theirName, format = m.format,
    won = m.winner == CoopMatch.mySide(m),
    gamesWon = CoopMatch.myWins(m), gamesLost = CoopMatch.theirWins(m),
  })
end

-- both reports of the game are in: score it
local function settle(ls, m)
  local n = m.game
  local outcome = CoopMatch.apply(m, CoopMatch.agree(m.mine[n], m.theirs[n]))
  require("src.coop.CoopLog").info("LINK", string.format("match game %d: %s / %s -> %s (%d-%d)",
    n, tostring(m.mine[n]), tostring(m.theirs[n]), outcome, CoopMatch.myWins(m), CoopMatch.theirWins(m)))
  if outcome == "won" then record(m) end
  ls.stage = outcome == "next" and "matchNext" or "matchOver"
  m.timer = 0
end

-- the battle of this game ended (the Cable Club is on top again)
local function gameEnded(ls, m)
  local n = m.game
  local b = m.battle
  m.mine[n] = CoopMatch.winnerOf(m, b and b.result)
  send(ls.net, { kind = "result", game = n, winner = m.mine[n] })
  ls.stage = "matchWait"
  m.timer = 0
end

-- out of the Cable Club; closing the tunnel tells the partner when the
-- match is still on (CoopMatch.onClose)
local function leave(ls, m, text)
  ls:exitWith(text and i18n().t(text) or nil)
end

-- one frame of a match stage (the Cable Club itself did its net checks)
local function step(ls, m, dt)
  local input = ls.game.input
  m.timer = (m.timer or 0) + (dt or 0)
  if ls.stage == "matchWait" then
    if m.theirs[m.game] then
      settle(ls, m)
    elseif input:wasPressed("b") and m.timer > CoopMatch.MIN_SHOW then
      leave(ls, m)
    elseif m.timer > CoopMatch.WAIT_LIMIT then
      leave(ls, m, "No answer from\n" .. i18n().truncate(m.theirName, 10) .. ".")
    end
  elseif ls.stage == "matchNext" then
    if input:wasPressed("b") and m.timer > CoopMatch.MIN_SHOW then
      leave(ls, m)
    elseif (input:wasPressed("a") and m.timer > CoopMatch.MIN_SHOW) or m.timer > CoopMatch.NEXT_DELAY then
      CoopMatch.nextGame(ls.net)
      ls:startMode("battle", ls.isHost)
    end
  elseif ls.stage == "matchOver" then
    if ((input:wasPressed("a") or input:wasPressed("b")) and m.timer > CoopMatch.MIN_SHOW)
       or m.timer > CoopMatch.OVER_DELAY then
      leave(ls, m)
    end
  end
end

-- `ls` (a LinkState on CoopLink's tunnel) plays match `m`
function CoopMatch.attach(ls, m)
  local t = ls.net
  t.match = m
  ls.coopMatch = m
  local update, draw = ls.update, ls.draw
  ls.update = function(self, dt)
    local top = self.game.stack:top() == self
    if self.matchGone then return end
    if top and m.partnerLeft then
      leave(self, m, i18n().truncate(m.theirName, 10) .. " left\nthe match.")
      return
    end
    if top and self.stage == "battleRunning" then
      gameEnded(self, m)
      return
    end
    local was = self.stage
    update(self, dt)
    if self.matchGone then return end
    if was == "battleWait" and self.stage == "battleRunning" then
      -- the battle of this game: its end closes the game, not the tunnel
      local b = self.game.stack:top()
      m.battle = b
      if type(b) == "table" and type(b.finish) == "function" then
        local finish = b.finish
        b.finish = function(s, ...)
          t.softClose = true
          finish(s, ...)
          t.softClose = nil
        end
      end
      return
    end
    if MATCH_STAGES[self.stage] and self.game.stack:top() == self then step(self, m, dt) end
  end
  local exitWith = ls.exitWith
  ls.exitWith = function(self, ...)
    self.matchGone = true
    return exitWith(self, ...)
  end
  ls.draw = function(self, ...)
    if MATCH_STAGES[self.stage] then
      CoopMatch.drawStage(self, m)
    else
      draw(self, ...)
      if self.stage == "battleWait" or self.stage == "battleRunning" then
        CoopMatch.drawScore(m, 88)
      end
    end
  end
  return m
end

-- ---------------------------------------------------------------------
-- drawing (160 x 144)
-- ---------------------------------------------------------------------

local function font() return i18n().font() end

-- "MOCHI      1" / "TOBY       0" under "GAME 2 OF 3"
function CoopMatch.drawScore(m, y)
  local Font = font()
  local I = i18n()
  love.graphics.setColor(0, 0, 0, 1)
  if m.best == 3 then
    Font.draw(string.format("GAME %d OF 3", m.game), 16, y)
  end
  Font.draw(I.truncate(tostring(m.myName):upper(), 10), 16, y + 12)
  Font.draw(tostring(CoopMatch.myWins(m)), 128, y + 12)
  Font.draw(I.truncate(tostring(m.theirName):upper(), 10), 16, y + 22)
  Font.draw(tostring(CoopMatch.theirWins(m)), 128, y + 22)
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopMatch.statusLine(ls, m)
  local I = i18n()
  local them = I.truncate(tostring(m.theirName):upper(), 6)
  if ls.stage == "matchWait" then return "WAITING FOR " .. them end
  if ls.stage == "matchNext" then return "NEXT: GAME " .. (m.game + 1) end
  if m.void then return "NO RESULT" end
  if m.winner == CoopMatch.mySide(m) then return "YOU WIN!" end
  return them .. " WINS!"
end

function CoopMatch.drawStage(ls, m)
  local Font = font()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  local fmt = require("src.coop.CoopVS").format(m.format)
  Font.draw(fmt and fmt.name or "FREE BATTLE", 8, 6)
  Font.draw(m.best == 3 and "BEST OF 3" or "ONE GAME", 8, 16)
  CoopMatch.drawScore(m, 36)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(CoopMatch.statusLine(ls, m), 8, 88)
  if ls.stage == "matchOver" and m.recorded then
    local r = m.recorded
    Font.draw(string.format("ELO %d", r.elo or 0), 16, 104)
  end
  local hint = (ls.stage == "matchNext" and "A: NEXT  B: LEAVE")
    or (ls.stage == "matchWait" and "B: LEAVE") or "A: OK"
  Font.draw(hint, 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

return CoopMatch
