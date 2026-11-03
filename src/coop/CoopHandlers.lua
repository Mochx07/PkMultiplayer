-- src/coop/CoopHandlers.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- message handlers

local M = {}

function M.install(CoopManager, CMI)
local CoopLog = CMI.CoopLog
local CoopManager = CMI.CoopManager
local HOF_PARTNER_MAPS = CMI.HOF_PARTNER_MAPS
local SHARED_RULES = CMI.SHARED_RULES
local applyPartnerInfo = CMI.applyPartnerInfo
local completeHandshake = CMI.completeHandshake
local freshPartner = CMI.freshPartner
local getGame = CMI.getGame
local incompatible = CMI.incompatible
local markTrainerBeaten = CMI.markTrainerBeaten
local now = CMI.now
local playSound = CMI.playSound
local resetSession = CMI.resetSession
local sendHello = CMI.sendHello


local H = {}

H.net_connect = function(ow, msg)
  -- both ends say hello as soon as the link is up; each hello is answered
  -- with a welcome, and either one completes the handshake
  if msg and msg.resumed == false then
    pcall(function() require("src.coop.CoopLink").onNewSession() end)
    pcall(function() require("src.coop.CoopBattle").onNewSession() end)
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
  -- a partner who linked from the title screen and then loaded its save
  if type(msg.id) == "string" and msg.id ~= "" then
    CoopManager.partner.id = msg.id
    if CoopManager.net and CoopManager.net.notePeerIdentity then CoopManager.net:notePeerIdentity(msg.id) end
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
H.coop_ready = function(ow, msg) CoopManager.onPartnerReady(msg) end
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
H.coop_battle_here = toBattle("onPartnerHere")
H.coop_battle_gone = toBattle("onPartnerGone")
H.coop_battle_replace = toBattle("onPartnerReplace")
H.coop_battle_abort = toBattle("onPartnerLeft")
H.coop_battle_bag = toBattle("onPartnerBag")

H.coop_chat = function(ow, msg) CoopManager.onChatReceived(msg.sender, msg.text, false, msg.n) end
H.coop_chat_live = function(ow, msg) CoopManager.onChatLive(msg) end

-- the Cable Club over the co-op link (trade / P1 vs P2 battle)
local function link() return require("src.coop.CoopLink") end
H.coop_link = function(ow, msg) link().onLinkMessage(msg) end
H.coop_link_invite = function(ow, msg) link().onInvite(getGame(ow), msg) end
H.coop_link_accept = function(ow, msg) link().onAccept(getGame(ow), msg) end
H.coop_link_decline = function(ow, msg) link().onDecline(getGame(ow), msg) end
H.coop_link_cancel = function(ow, msg) link().onCancel(getGame(ow), msg) end
-- a P1-vs-P2 match's results and leaving (1.20, src/coop/CoopMatch.lua)
H.coop_match = function(ow, msg) require("src.coop.CoopMatch").onMessage(msg) end

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

end

return M
