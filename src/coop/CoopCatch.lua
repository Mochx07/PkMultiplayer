-- src/coop/CoopCatch.lua
-- CATCHING TOGETHER (nightly.2, capability "catch.together"), the way the
-- Let's Go games do it: in a co-op wild battle a BALL is no longer refused.
--
--   * A BALL is the turn's action, like a POTION (it goes first, with the
--     items), and is resolved inside the turn on both copies with the shared
--     die, so both screens see the same shakes and the same outcome.
--   * Both of you throw in the same turn: one JOINT THROW -- the better of
--     the two balls, the species' catch rate times 1.5 -- and both balls are
--     spent.  One of you throws: an ordinary throw.
--   * Caught: the rest of the turn is called off and both of you are asked
--     WHO KEEPS IT?  -- ME / PARTNER / LET FATE DECIDE.  The same answer from
--     both is taken; one says fate and the other names someone, that someone;
--     otherwise (both want it, both give it away, or no answer in 20 s) a
--     coin decides, the same coin on both copies (the battle's shared seed).
--     The keeper's game stores it as an ordinary catch (nickname, PC, dex);
--     the other's battle closes with a line saying who took it.
--
-- Not in the Bug-Catching Contest (its own PARK BALLs), a ghost or a battle
-- that cannot be caught, nor with a partner without the capability (their
-- copy would not know the action): there the old rule stands.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopCatch = {}

CoopCatch.CAP = "catch.together"
CoopCatch.JOINT = 1.5       -- Let's Go's two-player throw bonus on the catch rate
CoopCatch.KEEP_WAIT = 20    -- seconds to answer WHO KEEPS IT?

CoopManager.registerCap(CoopCatch.CAP)

local function I18n() return require("src.coop.CoopI18n") end
local function t(s) return I18n().t(s) end

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

-- the better ball first (a Master Ball is never wasted on the second throw)
CoopCatch.BALL_RANK = { MASTER_BALL = 5, ULTRA_BALL = 4, GREAT_BALL = 3, POKE_BALL = 2 }
local function rank(ball) return CoopCatch.BALL_RANK[ball] or 1 end

-- can a ball be thrown in this battle as a co-op action?
function CoopCatch.allowed(battle)
  if type(battle) ~= "table" or not battle.coopWild or battle.kind ~= "wild" then return false end
  if battle.ghost or battle.noCatch or battle.bugContest or battle.contest then return false end
  if battle.coopBoss or battle.coopBeast then return false end
  return CoopManager.bothHave(CoopCatch.CAP)
end

-- the wild Pokemon a ball goes at: the first one standing, the same slot on
-- both copies (in a co-op wild battle the two are one individual and its twin)
function CoopCatch.target(battle)
  local P = require("src.battle.BattleState").POS
  for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
    local b = battle:battlerAt(pos)
    if b and b.mon and (b.mon.hp or 0) > 0 and not b.fainted then return b end
  end
  return nil
end

-- CoopBattle.executeTurn: this turn's balls, in the host's frame on both copies
function CoopCatch.beginTurn(battle, localAction, partnerAction)
  if type(battle) ~= "table" then return end
  local mine = type(localAction) == "table" and localAction.coopBall or nil
  local theirs = type(partnerAction) == "table" and partnerAction.coopBall or nil
  if not (mine or theirs) then
    battle.coopBalls = nil
    return
  end
  local host, guest = mine, theirs
  if battle.isCoopGuest then host, guest = theirs, mine end
  battle.coopBalls = { host = host, guest = guest, done = false }
end

-- which ball flies, and whether it is a joint throw
function CoopCatch.pick(balls)
  if not balls then return nil, false end
  local h, g = balls.host, balls.guest
  if h and g then
    if rank(g) > rank(h) then return g, true end
    return h, true
  end
  return h or g, false
end

local function names(battle)
  local me = I18n().truncate(string.upper(tostring(CoopManager.getLocalPlayerName(battle.game) or "YOU")), 7)
  local them = I18n().truncate(string.upper(tostring(CoopManager.partner and CoopManager.partner.name or "PARTNER")), 7)
  return me, them
end

local function ballName(battle, ball)
  local def = battle.itemDef and battle:itemDef(ball)
  return (def and def.name) or tostring(ball):gsub("_", " ")
end

-- BattleState:executeAction (lib/Hooks.lua) for an action carrying a ball.
-- The first one this turn throws for both; a second one (the joint throw's
-- other half) is already in it.
function CoopCatch.execute(battle, user, action)
  local balls = battle.coopBalls
  if not balls or balls.done then return end
  balls.done = true
  local target = CoopCatch.target(battle)
  if not target then return end
  local ball, joint = CoopCatch.pick(balls)
  local Strings = require("src.core.Strings")
  local me, them = names(battle)
  local mineThrew = (battle.isCoopGuest and balls.guest) or (not battle.isCoopGuest and balls.host)
  if joint then
    battle:sayNext(string.format(t("%s and %s\nthrew together!"), me, them))
  else
    battle:sayNext(Strings("%s used\n%s!", mineThrew and me or them, ballName(battle, ball)))
  end
  -- the throw: Catching with the shared die (we are inside resolveTurn)
  local Catching = require("src.battle.Catching")
  local rate = nil
  if joint then
    local base = tonumber(target.def and target.def.catchRate) or 45
    rate = math.min(255, math.floor(base * CoopCatch.JOINT + 0.5))
  end
  local caught, shakes = Catching.attempt(ball, target.mon, target.def, battle.rng, rate,
                                          { ballDef = battle.ballDef and battle:ballDef(ball),
                                            statuses = battle.data and battle.data.statuses, battle = battle })
  CoopLog.battle("CATCH", string.format("%s throw of %s at %s: %s (%s shakes)", joint and "joint" or "single",
                 tostring(ball), tostring(target.mon.species), caught and "caught" or "missed", tostring(shakes)))
  battle.lastBall = ball
  local enemyWas = battle.enemy
  battle.enemy = target
  -- THE TWIN GOES IN TOO.  The two foes of a co-op wild battle are one
  -- Pokemon and its mirror: the ball's own animation draws in only the one
  -- it flies at, so the twin copies its every pic effect (the silhouette,
  -- hidden, back out) and a second ball is drawn on it (drawTwin).
  local P = require("src.battle.BattleState").POS
  local twin = nil
  for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
    local b = battle:battlerAt(pos)
    if b and b ~= target and b.mon and (b.mon.hp or 0) > 0 and not b.fainted then twin = { b = b, pos = pos } end
  end
  battle:actNext(function()
    battle.coopTwinCatch = twin and { main = target, twin = twin.b, pos = twin.pos } or nil
  end)
  battle:ballChain(battle:tossAnimFor(ball), caught, shakes, ball)
  if not caught then
    battle:actNext(function()
      CoopCatch.mirror(battle)
      battle.coopTwinCatch = nil
      local tf = twin and battle.picFxFor and battle:picFxFor(twin.b)
      if tf then tf.hidden, tf.kind, tf.ox, tf.oy = nil, nil, 0, 0 end
    end)
    battle:actNext(function() battle.enemy = enemyWas end)
    battle:sayNext(battle:ballMissMessage(shakes))
    return
  end
  -- CAUGHT: nothing else in this turn happens (Hooks: executeAction and
  -- endOfTurn stand down), and both are asked who keeps it
  battle.coopCaught = { target = target, mon = target.mon, ball = ball }
  -- inside their balls they stay: an animation's end puts every hidden pic
  -- back (restoreHiddenPics) except an invulnerable battler's, so both are
  -- marked so -- the battle ends with this catch anyway
  battle:actNext(function()
    for _, b in ipairs({ target, twin and twin.b or false }) do
      if b then
        b.invulnerable = true
        local pf = battle.picFxFor and battle:picFxFor(b)
        if pf then pf.hidden, pf.kind = true, nil end
      end
    end
  end)
  battle:actNext(function() require("src.core.Sound").play(battle.data, "Caught_Mon") end)
  battle:sayNext(Strings("All right!\n%s was\ncaught!", target.name))
  battle:actNext(function() CoopCatch.askKeeper(battle) end)
end

-- the twin's pic takes every effect the ball's target has this frame
function CoopCatch.mirror(battle)
  local tc = battle.coopTwinCatch
  if not (tc and battle.picFxFor) then return end
  local from, to = battle:picFxFor(tc.main), battle:picFxFor(tc.twin)
  if not (from and to) then return end
  for k in pairs(to) do if from[k] == nil then to[k] = nil end end
  for k, v in pairs(from) do to[k] = v end
end

-- BattleState:drawAnimLayer (lib/Hooks.lua): the ball's objects once more,
-- aimed at the twin's own box
function CoopCatch.drawTwin(battle, drawAnimLayer, ...)
  local tc = battle.coopTwinCatch
  if not tc then return end
  CoopCatch.mirror(battle)
  local ap = battle.animPlayer
  local so = ap and ap.sideOffsets
  if not (so and battle.animPicBox) then return end
  local box = battle:animPicBox(tc.pos, true)
  if not box then return end
  local twinSo = {}
  for k, v in pairs(so) do twinSo[k] = v end
  twinSo.enemy = box
  twinSo.flightOf, twinSo.flightTo, twinSo.flightCache = nil, nil, nil
  ap.sideOffsets = twinSo
  local ok, err = pcall(drawAnimLayer, battle, ...)
  ap.sideOffsets = so
  if not ok then CoopLog.warn("BATTLE", "twin ball: " .. tostring(err)) end
end

-- ------------------------------------------------------------------ keeper

-- picks in the host's frame -> "host" / "guest" / "coin"
local function frame(battle, pick, fromPartner)
  if pick ~= "me" and pick ~= "partner" then return "coin" end
  local hostSaid = (not battle.isCoopGuest) ~= (fromPartner == true)
  if pick == "me" then return hostSaid and "host" or "guest" end
  return hostSaid and "guest" or "host"
end

-- both answers (host's frame) -> the keeper, "host" or "guest"
function CoopCatch.decide(a, b, seed, turn)
  if a == b and a ~= "coin" then return a, false end
  if a == "coin" and b ~= "coin" then return b, false end
  if b == "coin" and a ~= "coin" then return a, false end
  -- both want it, both give it away, or both leave it to fate: the coin
  local x = ((tonumber(seed) or 1) * 31 + (tonumber(turn) or 0) * 7) % 2
  return x == 0 and "host" or "guest", true
end

-- the question waits on the battle (battle.coopKeep), not here: each copy
-- has its own
local function currentBattle()
  local CB = package.loaded["src.coop.CoopBattle"]
  return CB and CB.currentBattle
end

function CoopCatch.askKeeper(battle)
  local c = battle.coop or {}
  local caught = battle.coopCaught
  if not caught then return end
  local me, them = names(battle)
  battle.coopKeep = { turn = c.turn, mine = nil, theirs = battle.coopKeepEarly, at = 0, me = me, them = them }
  battle.coopKeepEarly = nil
  local Menu = I18n().menu()
  local game = battle.game
  local function choose(pick)
    local p = battle.coopKeep
    if not p then return end
    p.mine = pick
    send({ type = "coop_catch_keep", pick = pick, turn = p.turn })
    CoopCatch.settle(battle)
  end
  battle:say(string.format(t("Who keeps\n%s?"), caught.target.name or "IT"))
  battle.phase = "messages"
  local menu = Menu.new(game, {
    { label = t("I KEEP IT"), onSelect = function() choose("me") end },
    { label = string.format(t("FOR %s"), them), onSelect = function() choose("partner") end },
    { label = t("LET FATE DECIDE"), onSelect = function() choose("coin") end },
  }, { tx = 2, ty = 5, tw = 18, th = 8 })
  menu.coopKeepMenu = true
  -- no B: someone has to have it
  menu.cancelable = false
  game.stack:push(menu)
  battle.coopKeep.menu = menu
end

-- once a frame (CoopManager.onTick): the wait runs out into a coin
function CoopCatch.tick(dt, battle)
  battle = battle or currentBattle()
  local p = battle and battle.coopKeep
  if not p then return end
  p.at = p.at + (dt or 0)
  if p.at >= CoopCatch.KEEP_WAIT then
    p.mine = p.mine or "coin"
    p.theirs = p.theirs or "coin"
    CoopCatch.settle(battle)
  elseif CoopManager.connected == false and p.mine then
    -- the partner is gone: nobody to share with, it is yours
    p.theirs = p.theirs or "partner"
    CoopCatch.settle(battle)
  end
end

function CoopCatch.settle(battle)
  local p = battle and battle.coopKeep
  if not (p and p.mine and p.theirs) then return end
  battle.coopKeep = nil
  local c = battle.coop or {}
  local keeper, byCoin = CoopCatch.decide(frame(battle, p.mine, false), frame(battle, p.theirs, true), c.seed, p.turn)
  local mineIsKeeper = (keeper == "host") == (not battle.isCoopGuest)
  CoopLog.battle("CATCH", string.format("keeper %s (%s; me %s, partner %s)", keeper,
                 byCoin and "coin" or "agreed", tostring(p.mine), tostring(p.theirs)))
  local game = battle.game
  -- the menu, if it is still up (the time ran out)
  if p.menu and game and game.stack then
    for i = #game.stack.states, 1, -1 do
      if game.stack.states[i] == p.menu then table.remove(game.stack.states, i) break end
    end
  end
  local caught = battle.coopCaught
  if not caught then return end
  battle.queue = {}
  battle.nextInsert = 0
  battle.phase = "messages"
  if byCoin then battle:say(t("The coin decides...")) end
  if mineIsKeeper then
    battle.enemy = caught.target
    battle:act(function() battle:storeCaughtMon() end)
  else
    -- the partner's now (SHARE DEX passes it on as theirs); this copy ends
    -- the battle the way a catch does, with nothing stored and no EXP
    battle:sayNext(string.format(t("%s took\n%s!"), p.them or "PARTNER", caught.target.name or "IT"))
    battle:act(function()
      battle.noExp = true
      battle.result = "caught"
      battle.afterQueue = "finish"
    end)
  end
  if battle.phase ~= "messages" then battle.phase = "messages" end
end

CoopManager.handlers.coop_catch_keep = function(_, msg)
  local battle = currentBattle()
  if not battle then return end
  local pick = (msg.pick == "me" or msg.pick == "partner") and msg.pick or "coin"
  local p = battle.coopKeep
  if not p then
    -- their answer came before our own catch text finished
    battle.coopKeepEarly = pick
    return
  end
  p.theirs = pick
  CoopCatch.settle(battle)
end

CoopManager.onTick("CoopCatch", function(dt) CoopCatch.tick(dt) end)

return CoopCatch
