-- src/coop/CoopInvites.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- co-op battle invites

local M = {}

function M.install(CoopManager, CMI)
local CoopManager = CMI.CoopManager
local CoopNet = CMI.CoopNet
local GEN1_LEADER_BADGES = CMI.GEN1_LEADER_BADGES
local GameVersion = CMI.GameVersion
local INVITE_TIMEOUT = CMI.INVITE_TIMEOUT
local LEADER_BADGES = CMI.LEADER_BADGES
local Pokemon = CMI.Pokemon
local Strings = CMI.Strings
local getGame = CMI.getGame
local healthyCount = CMI.healthyCount
local mapsMatch = CMI.mapsMatch
local now = CMI.now
local overworldIdle = CMI.overworldIdle
local removeState = CMI.removeState


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
function CoopManager.leaderBadgeFor(oppClass, partyIndex)
  if type(oppClass) ~= "string" then return nil end
  local key = oppClass:upper():gsub("^OPP_", ""):gsub("^LEADER_", "")
  if key == "LEADER" then key = "FALKNER" end
  if GameVersion.isGen1() and GEN1_LEADER_BADGES[key] then
    local badge = GEN1_LEADER_BADGES[key]
    if type(badge) == "table" then return badge[tonumber(partyIndex) or 0] end
    return badge
  end
  return LEADER_BADGES[key]
end

local function awardLeaderBadge(game, oppClass, partyIndex)
  local badge = CoopManager.leaderBadgeFor(oppClass, partyIndex)
  if not (badge and game and game.save) then return end
  local Badges = require("src.inventory.Badges")
  if Badges.has(game.save, { id = badge }) then return end
  Badges.set(game.save, { id = badge }, true)
  -- 1.20 duo: handed over to this player by name, in a box with the badge's
  -- fanfare, as the leader does on the other screen (src/coop/CoopDuo.lua)
  local okD, CoopDuo = pcall(require, "src.coop.CoopDuo")
  if okD and CoopDuo.on() and CoopDuo.queueBadge(game, badge) then return end
  CoopManager.showStatus("Earned the " .. badge .. "!", 3)
end

local function markTrainerBeaten(game, ow, msg)
  local save = game and game.save
  if not save then return end
  save.defeatedTrainers = save.defeatedTrainers or {}
  save.flags = save.flags or {}
  if msg.npcId then save.defeatedTrainers[msg.npcId] = true end
  -- the header's flag is a bit of the sender's cartridge (storyCompatible)
  if msg.headerEvent and CoopManager.storyCompatible() then save.flags[msg.headerEvent] = true end
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
        awardLeaderBadge(game, msg.oppClass, msg.partyIndex)
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
  CoopBattle.useRuleset(p2Battle, msg.ruleset)
  if type(msg.foeRules) == "table" then
    p2Battle.coopBalanceRules = { balancedFoes = msg.foeRules.balancedFoes == true,
                                  hardFoes = msg.foeRules.hardFoes == true,
                                  catchUp = msg.foeRules.catchUp == true or nil,
                                  gymTeam = msg.foeRules.gymTeam == true or nil }
  end
  -- THE RIVAL 2v2: the host's rival and this player's own (src/coop/CoopGyms.lua)
  if msg.rivals then
    p2Battle.coopRivalPair = require("src.coop.CoopGyms").checkPair(game.data, msg.oppClass, msg.rivals)
  end
  -- the host's boss or roaming beast, fought the same way here
  pcall(function() require("src.coop.CoopBoss").guestMark(p2Battle, msg) end)
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
  -- game.  Busy is buffered briefly if the player is just clearing a text box.
  if CoopManager.incomingInviteBuffer and CoopManager.incomingInviteBuffer.msg.inviteId ~= msg.inviteId then
    CoopManager.net:send({ type = "coop_battle_decline", inviteId = CoopManager.incomingInviteBuffer.msg.inviteId, reason = "busy" })
    CoopManager.incomingInviteBuffer = nil
  end

  if CoopManager.isLocalInBattle(ow2) then decline("in_battle") return end
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

  local function inDialogueOrScript(g, o)
    if CoopManager.isLocalInDialogue(o) then return true end
    if o and (o.engaging or (o.runner and o.runner.isRunning and o.runner:isRunning())) then
      return true
    end
    return false
  end

  if not overworldIdle(game, ow2) then
    if inDialogueOrScript(game, ow2) then
      CoopManager.incomingInviteBuffer = {
        ow = ow2,
        msg = msg,
        deadline = now() + 4.0,
        eligible = eligible,
      }
      return
    else
      decline("busy")
      return
    end
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
  -- a wild Pokemon reads as one, not as "VS WILD PIDGEY"
  if msg.battleKind == "wild" then
    -- the wire says "WILD <NAME>"; the box draws I18n.fit(line, 16), so cut
    -- nothing here: a pre-cut English line no longer matched "MET %s" whole
    -- and read "ENCONTRÓ WILD SL" in Spanish
    inviteModal.lines = { pName, "MET " .. (tName:gsub("^WILD ", "")), "FIGHT TOGETHER?" }
  end

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
  -- ...or while you are picking your three for it (CoopReady.hostBigBattle)
  local hosting = CoopManager.hostingBig
  if not pending and hosting and msg and msg.inviteId == hosting.inviteId then
    hosting.declined = true
    hosting.partnerMons = nil
    hosting.declineText = DECLINE_TEXT[msg.reason] or "Partner won't join. Solo!"
    CoopManager.showStatus(hosting.declineText, 2.5)
    return
  end
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
  if CoopManager.incomingInviteBuffer and (not msg.inviteId or CoopManager.incomingInviteBuffer.msg.inviteId == msg.inviteId) then
    CoopManager.incomingInviteBuffer = nil
  end
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

-- Red / Blue / Yellow name their Elite Four by name (OPP_LORELEI); Gold
-- and Crystal file them under OPP_ELITE_FOUR_*.
local BIG_PATTERNS = { "^OPP_LEADER", "ELITE_FOUR", "^OPP_CHAMPION$", "^CHAMPION$", "RIVAL",
                       "PKMN_TRAINER_RED", "^RED$", "ROCKET_EXECUTIVE", "GIOVANNI",
                       "^OPP_LORELEI$", "^LORELEI$", "^OPP_BRUNO$", "^BRUNO$", "^OPP_AGATHA$", "^AGATHA$",
                       "^OPP_LANCE$", "^LANCE$" }

function CoopManager.isBigBattleClass(oppClass, save, partyIndex)
  if type(oppClass) ~= "string" then return false end
  local c = oppClass:upper()
  local badge = CoopManager.leaderBadgeFor(c, partyIndex)
  local big = badge ~= nil
  for _, pat in ipairs(BIG_PATTERNS) do
    if c:find(pat) then big = true end
  end
  if not big then return false end
  -- a leader whose badge you already hold is not fought again
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
  local ok = CoopManager.partnerAvailable(ow, false, true)
  if not ok then return end
  CoopManager.warnNotReady()
  local name = CoopManager.trainerDisplayName(game, oppClass, partyIndex)
  local choice = "solo"
  local Menu = require("src.coop.CoopI18n").menu()
  game.stack:push(Menu.new(game, {
    { label = Strings("CO-OP"), onSelect = function() choice = "coop" runner:resume() end },
    { label = Strings("SOLO"), onSelect = function() choice = "solo" runner:resume() end },
  }, { tx = 3, ty = 4, tw = 14, header = require("src.coop.CoopI18n").truncate("VS " .. name, 12), cancelable = true,
       onCancel = function() choice = "solo" runner:resume() end }))
  runner:yield()

  if choice == "coop" and CoopManager.isConnected() then
    local inviteId = newInviteId()
    CoopManager.bigBattle = { inviteId = inviteId, oppClass = oppClass, partyIndex = partyIndex,
                              name = name, at = now() }
    CoopManager.net:send({ type = "coop_story_hold", map = ow.map.id, class = oppClass })
    -- CoopStory.finish lifts it (coop_story_release) when the scene ends
    ctx.coopHoldSent, ctx.coopHoldSent_map = true, ow.map.id
    CoopManager.net:send({ type = "coop_bigbattle_invite", inviteId = inviteId, oppClass = oppClass,
                           partyIndex = partyIndex, trainerName = name, mapId = ow.map.id })
    CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to join!", 2.5)
  else
    CoopManager.bigBattle = { solo = true, oppClass = oppClass, partyIndex = partyIndex }
  end
end

CMI.markTrainerBeaten = markTrainerBeaten
CMI.newInviteId = newInviteId
CMI.startPendingBattle = startPendingBattle
CMI.wireMon = wireMon
end

return M
