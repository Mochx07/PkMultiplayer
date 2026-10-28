-- src/coop/CoopWild.lua
-- WILD TOGETHER.  With the rule on, a wild Pokemon that jumps out of the
-- grass (a step or SWEET SCENT -- never a scripted one, a roaming beast or
-- the Bug-Catching Contest) while the partner is close by on the same map
-- asks them to join: on a yes it is a co-op double, the wild Pokemon and its
-- twin against one Pokemon of each of you, in the same lockstep as a trainer
-- double.  No answer, or a no, and it is your battle alone.
--
-- Together you fight; you don't catch.  A BALL can't be aimed with four
-- Pokemon out ("Not while you battle together!") -- pick SOLO-style play by
-- leaving the rule off when you are hunting.  RUN gets both of you away.
--
-- Wire: coop_battle_invite with battleKind = "wild" and the wild Pokemon as
-- it stands (wildMon), so both copies fight the same one; coop_wild_run.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopWild = {}

-- how close the partner must be, in cells, to be asked
CoopWild.NEAR = 8
CoopWild.TEAM = 3

CoopManager.addRule("wildTogether", "TEAM UP WILD", false)

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

local function healthy(mon)
  return mon and not (mon.isEgg or mon.egg) and (tonumber(mon.hp) or 0) > 0
end

function CoopWild.near(ow)
  local p, partner = ow and ow.player, CoopManager.partner
  if not (p and partner) then return false end
  local d = math.abs((partner.cx or 0) - (p.cellX or 0)) + math.abs((partner.cy or 0) - (p.cellY or 0))
  return d <= CoopWild.NEAR
end

-- a random encounter, of the kind two can share
function CoopWild.shareable(ow, battle)
  if not (battle and battle.kind == "wild" and ow and ow.pkmRandomEncounter) then return false end
  if battle.roamer or battle.battleType or battle.safari or battle.bugContest
     or battle.ghost or battle.demo or battle.dead or battle.noRun then
    return false
  end
  return battle.enemy and battle.enemy.mon ~= nil
end

-- OverworldState:pushBattle (via CoopManager.promptCoopBattle): true when the
-- partner has been asked and the battle waits on the answer
function CoopWild.offer(ow, battle, opts)
  if not CoopManager.wildTogether then return false end
  if not CoopWild.shareable(ow, battle) then return false end
  if not CoopManager.partnerAvailable(ow) then return false end
  if not CoopWild.near(ow) then return false end
  local game = CoopManager.getGame(ow)
  if not (game and game.stack and game.save) then return false end
  local chosen = {}
  for _, m in ipairs(game.save.party or {}) do
    if healthy(m) then chosen[#chosen + 1] = m end
    if #chosen >= CoopWild.TEAM then break end
  end
  if #chosen == 0 then return false end
  battle.coopHandled = true

  local wired = {}
  for _, m in ipairs(chosen) do wired[#wired + 1] = CoopManager.wireMon(m) end
  local seed = (love and love.math and love.math.random) and love.math.random(1, 1000000)
               or math.random(1, 1000000)
  local inviteId = ("w%d-%d"):format(os.time(), math.random(1, 1e6))
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local waitModal = CoopWaitModal.new(game, CoopManager.partner.name, function(reason)
    CoopManager.cancelPendingInvite(ow, reason)
  end, CoopManager.INVITE_TIMEOUT and (CoopManager.INVITE_TIMEOUT + 2) or 22)
  CoopManager.pendingBattleInvite = {
    battle = battle, localChosen = chosen, opts = opts, seed = seed,
    inviteId = inviteId, waitModal = waitModal, ow = ow,
  }
  game.stack:push(waitModal)
  local mon = battle.enemy.mon
  send({
    type = "coop_battle_invite",
    inviteId = inviteId,
    battleKind = "wild",
    trainerName = "WILD " .. tostring(battle.enemy.name or "POKéMON"),
    wildMon = CoopManager.wireMon(mon),
    species = mon.species,
    level = mon.level,
    mapId = ow.map and ow.map.id,
    seed = seed,
    localMons = wired,
    ruleset = require("src.coop.CoopBattle").rulesetName(battle),
  })
  CoopLog.info("WILD", "asked partner to join vs " .. tostring(mon.species))
  return true
end

-- the guest's copy of the same wild battle
function CoopWild.guestBattle(game, msg)
  local BattleState = require("src.battle.BattleState")
  local b = BattleState.newWild(game, msg.species, tonumber(msg.level) or 5)
  local mon = type(msg.wildMon) == "table" and msg.wildMon
  if mon then
    -- the host's individual, not a fresh roll: same DVs, moves, HP
    local copy = CoopManager.wireMon(mon)
    b:placeBattler(BattleState.POS.OPPONENT_LEFT, BattleState.makeBattler(game.data, copy, false))
  end
  return b
end

-- CoopBattle.initBattle: a wild battle becomes a co-op one (both copies)
function CoopWild.prepare(battle)
  if battle.kind ~= "wild" then return end
  battle.coopWild = true
  if not battle.enemyParty and battle.enemy and battle.enemy.mon then
    -- the double mirrors a lone Pokemon so the field is two on two
    battle.enemyParty = { battle.enemy.mon }
  end
end

-- RUN in a co-op wild battle: no roll, both get away
function CoopWild.run(battle)
  send({ type = "coop_wild_run", inviteId = battle.coop and battle.coop.inviteId })
  battle.phase = "messages"
  require("src.core.Sound").play(battle.data, "Run")
  battle:say(battle:romText("_GotAwayText", "Got away safely!"))
  battle.result = "run"
  battle.afterQueue = "finish"
end

CoopManager.handlers.coop_wild_run = function(ow, msg)
  local CoopBattle = require("src.coop.CoopBattle")
  local battle = CoopBattle.currentBattle
  if not (battle and battle.coopWild) then return end
  if msg.inviteId and battle.coop and battle.coop.inviteId ~= msg.inviteId then return end
  CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " ran. Got away!", 3)
  CoopBattle.forceFinishBattle(battle, "run")
end

CoopWild.NO_BALL = "Not while you\nbattle together!"

return CoopWild
