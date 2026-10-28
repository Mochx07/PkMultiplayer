-- A CO-OP DOUBLE ACROSS A DROPPED LINK (src/coop/CoopBattle.lua).
--
-- What a copy sends while the session is reconnecting is kept by the
-- session and delivered when it resumes, so a turn, a pick after a faint or
-- the host's sync is never lost to a drop; the AI only takes the partner's
-- Pokemon after a long silence, and then tells them so; a partner who came
-- back as a new game ends the shared battle; and a message for a turn far
-- ahead is not stored.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_battle_link.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local CoopManager = require("src.coop.CoopManager")
local CoopBattle = require("src.coop.CoopBattle")
require("src.coop.CoopLog").enabled = false

local sent = {}
local net = { send = function(_, m) sent[#sent + 1] = m return true end, closed = false,
              sessionActive = true, flush = function() end, isLinked = function() return false end }
CoopManager.net = net
CoopManager.showStatus = function() end
local realConnected = CoopManager.isConnected
local up = false
CoopManager.isConnected = function() return up end

local function newBattle()
  local mon = { species = "FIXMON_A", hp = 20 }
  local states = {}
  local battle = { coopChosenMons = { mon }, phase = "menu", game = { stack = { states = states } } }
  states[1] = battle
  battle.coop = { inviteId = "LINK1", turn = 3, partnerActions = {}, partnerStates = {},
                  replaceQueue = {}, everOnStack = true }
  CoopBattle.currentBattle = battle
  return battle, mon
end

local function lastOf(kind)
  for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end
end

-- the session is reconnecting: what we send waits in it
do
  local battle, mon = newBattle()
  CoopManager.connected = false
  sent = {}
  CoopBattle.sendReplacement(battle, mon)
  T.check(lastOf("coop_battle_replace") ~= nil, "a pick after a faint is kept while the link reconnects")
  net.closed = true
  sent = {}
  CoopBattle.sendReplacement(battle, mon)
  T.check(#sent == 0, "...but not once the session is gone")
  net.closed = false
end

-- a long silence: the AI takes over, and the partner is told
do
  local battle = newBattle()
  sent = {}
  for _ = 1, math.ceil(CoopBattle.LINK_GRACE / 0.5) + 1 do CoopBattle.tick(0.5) end
  T.check(battle.coop.partnerLost, "after the grace period the AI plays the partner's Pokemon")
  local leave = lastOf("coop_battle_leave")
  T.check(leave and leave.inviteId == "LINK1", "...and the partner is told, for when the link comes back")
  T.check(CoopBattle.LINK_GRACE >= 120, "a drop of a minute or two never hands the slot to the AI")
end

-- a turn too far ahead is not stored
do
  local battle = newBattle()
  CoopBattle.onPartnerAction({ inviteId = "LINK1", turn = 3 + CoopBattle.TURN_AHEAD_MAX + 3,
                               action = { kind = "spectator" } })
  T.check(next(battle.coop.partnerActions) == nil, "an action for a turn far ahead is dropped")
  battle.coop.localReady = false
  CoopBattle.onPartnerAction({ inviteId = "LINK1", turn = 4, action = { kind = "spectator" } })
  T.check(battle.coop.partnerActions[4] ~= nil, "the next turn's action is kept")
end

-- THE LINK CAME BACK AS A NEW SESSION (log 2026-10-28 22:28: a one-minute
-- drop handed the partner's Pokemon to the AI for good).  The battle asks
-- whether the partner is still in it before giving up on them.
do
  local battle = newBattle()
  up = true
  CoopBattle.onNewSession()
  T.check(not battle.coop.partnerLost and battle.coop.awaitingResume, "a new session first asks if the partner is still in the battle")
  sent = {}
  CoopBattle.onLinkRestored()
  local here = lastOf("coop_battle_here")
  T.check(here and here.inviteId == "LINK1" and here.turn == 3, "...by saying which battle and turn we are on")
  -- they are: the battle goes on with them, and what they missed is sent again
  battle.coop.sentActions = { [3] = { type = "coop_battle_action", inviteId = "LINK1", turn = 3, action = { kind = "move" } } }
  sent = {}
  CoopBattle.onPartnerHere({ inviteId = "LINK1", turn = 3 })
  T.check(not battle.coop.partnerLost and not battle.coop.awaitingResume, "a partner still in the battle plays on")
  local again = lastOf("coop_battle_action")
  T.check(again and again.turn == 3, "...and gets the action of the turn they are on again")
  up = false
end

do
  -- they restarted: their game says so, and the AI takes their Pokemon at once
  local battle = newBattle()
  up = true
  CoopBattle.onNewSession()
  CoopBattle.onPartnerGone({ inviteId = "LINK1" })
  T.check(battle.coop.partnerLost, "a partner whose game left the battle hands their Pokemon to the AI")
  up = false
end

do
  -- an older version answers nothing: the AI takes over after a short wait
  local battle = newBattle()
  up = true
  CoopBattle.onNewSession()
  CoopBattle.onLinkRestored()
  for _ = 1, math.ceil(CoopBattle.RESUME_WAIT / 0.5) + 1 do CoopBattle.tick(0.5) end
  T.check(battle.coop.partnerLost, "with no answer the AI takes over after RESUME_WAIT")
  up = false
end

do
  -- a battle we are not in (or no longer in) is answered "gone"
  local battle = newBattle()
  sent = {}
  CoopBattle.onPartnerHere({ inviteId = "SOMETHING_ELSE", turn = 1 })
  local gone = lastOf("coop_battle_gone")
  T.check(gone and gone.inviteId == "SOMETHING_ELSE", "a battle we are not in is answered with coop_battle_gone")
  T.check(not battle.coop.partnerLost, "...and does not touch ours")
end

do
  -- the session's own reconnect window running out still waits for them
  local battle = newBattle()
  CoopBattle.onLinkLost("timeout")
  T.check(not battle.coop.partnerLost and battle.coop.linkLostAt, "the session timing out keeps waiting (RECONNECTING...)")
  local okDraw, err = pcall(CoopBattle.drawWaitPrompt, battle)
  T.check(okDraw, "the RECONNECTING box draws (" .. tostring(err) .. ")")
  T.check(CoopBattle.drawReconnecting(battle) == true, "...in place of the wait prompt while the link is down")
  CoopBattle.onLinkLost("left")
  T.check(battle.coop.partnerLost, "a goodbye hands their Pokemon to the AI")
end

-- early actions for battles not up yet are kept for a few battles only
do
  CoopBattle.currentBattle = nil
  CoopBattle.early = {}
  for i = 1, CoopBattle.EARLY_MAX * 3 do
    CoopBattle.onPartnerAction({ inviteId = "INV" .. i, turn = 1, action = { kind = "spectator" } })
  end
  local n = 0
  for _ in pairs(CoopBattle.early) do n = n + 1 end
  T.check(n <= CoopBattle.EARLY_MAX, "stray early actions do not pile up (" .. n .. ")")
end

CoopManager.isConnected = realConnected
T.finish("co-op double across a dropped link")
