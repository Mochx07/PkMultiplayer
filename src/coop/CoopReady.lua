-- src/coop/CoopReady.lua (split out of CoopManager.lua for 1.20)
-- install(CoopManager, CMI) runs this code where it used to sit in
-- CoopManager.lua: CoopManager.* names are the manager's own, and CMI
-- carries the manager's file-level locals it reads (and the ones it
-- hands on to the code after it).
--
-- READY / NOT READY: before a gym or the League, each one says when they
-- are set (key R, or READY in the co-op menu).  The partner sees it over
-- your head and beside your name, and a leader's CO-OP / SOLO question says
-- when they are not.  It clears itself once a co-op battle starts.

local M = {}

function M.install(CoopManager, CMI)
local CoopManager = CMI.CoopManager
local GameVersion = CMI.GameVersion
local INVITE_TIMEOUT = CMI.INVITE_TIMEOUT
local Strings = CMI.Strings
local getGame = CMI.getGame
local healthyCount = CMI.healthyCount
local mapsMatch = CMI.mapsMatch
local newInviteId = CMI.newInviteId
local now = CMI.now
local overworldIdle = CMI.overworldIdle
local removeState = CMI.removeState
local startPendingBattle = CMI.startPendingBattle
local wireMon = CMI.wireMon

CoopManager.localReady = false

function CoopManager.setReady(on, quiet)
  on = on and true or false
  if CoopManager.localReady == on and quiet then return end
  CoopManager.localReady = on
  if CoopManager.connected and CoopManager.net then
    CoopManager.net:send({ type = "coop_ready", ready = on })
  end
  if not quiet then CoopManager.showStatus(on and "You are READY!" or "You are not ready", 2) end
end

-- asked CO-OP or SOLO while the partner said they are not ready
function CoopManager.warnNotReady()
  if CoopManager.partner and CoopManager.partner.ready == false then
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " is not ready", 3)
  end
end

-- a co-op battle has started: both are back to "not ready"
function CoopManager.clearReady()
  CoopManager.localReady = false
  if CoopManager.partner then CoopManager.partner.ready = nil end
end

function CoopManager.onPartnerReady(msg)
  local partner = CoopManager.partner
  partner.ready = msg.ready == true
  partner.readyAt = now()
  local name = partner.name or "Partner"
  CoopManager.showStatus(partner.ready and (name .. " is READY!") or (name .. " is not ready"), 2.5)
end

-- RED / BLUE / YELLOW'S LEADERS ARE ASKED ABOUT FIRST TOO.  Their talk
-- handlers are Lua (data/scripts/gyms.lua: BROCK -> ow:engageTrainer), not
-- script rows, so CoopStory.begin never saw them coming and the partner was
-- only invited after the leader's speech, with no time to pick a team.
-- OverworldState:engageTrainer calls this before the first line; with the
-- answer in, it calls engageTrainer again, and this lets it through.
CoopManager.BIG_ANSWER_TTL = 120   -- seconds an answer waits for its battle

function CoopManager.askBigBattle(ow, npc, onDone)
  if not (GameVersion.isGen1() and CoopManager.storySync) then return false end
  local d = type(npc) == "table" and npc.def
  local class, party = d and d.trainerClass, d and d.trainerParty
  if type(class) ~= "string" or not (ow and ow.engageTrainer and ow.map) then return false end
  local game = getGame(ow)
  if not (game and game.stack and game.save) then return false end
  local big = CoopManager.bigBattle
  if big and big.oppClass == class and now() - (big.at or 0) < CoopManager.BIG_ANSWER_TTL then
    return false
  end
  if not CoopManager.isBigBattleClass(class, game.save, party) then return false end
  if not CoopManager.partnerAvailable(ow, false, true) then return false end
  if not mapsMatch(CoopManager.partner.map, ow.map.id) then return false end
  CoopManager.warnNotReady()
  local name = CoopManager.trainerDisplayName(game, class, party)
  local function answer(choice)
    if choice == "coop" and CoopManager.isConnected() then
      local inviteId = newInviteId()
      CoopManager.bigBattle = { inviteId = inviteId, oppClass = class, partyIndex = party,
                                name = name, at = now() }
      CoopManager.net:send({ type = "coop_bigbattle_invite", inviteId = inviteId, oppClass = class,
                             partyIndex = party, trainerName = name, mapId = ow.map.id })
      CoopManager.showStatus("Asked " .. (CoopManager.partner.name or "partner") .. " to join!", 2.5)
    else
      CoopManager.bigBattle = { solo = true, oppClass = class, partyIndex = party, at = now() }
    end
    ow:engageTrainer(npc, onDone)
  end
  local Menu = require("src.coop.CoopI18n").menu()
  game.stack:push(Menu.new(game, {
    { label = Strings("CO-OP"), onSelect = function() answer("coop") end },
    { label = Strings("SOLO"), onSelect = function() answer("solo") end },
  }, { tx = 3, ty = 4, tw = 14, header = require("src.coop.CoopI18n").truncate("VS " .. name, 12), cancelable = true,
       onCancel = function() answer("solo") end }))
  return true
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
    -- the difficulty, the host's word for both copies (CoopBalance)
    foeRules = battle.coopBalanceRules,
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
  -- WHILE YOU PICK YOUR THREE, THE INVITE IS STILL LIVE.  promptCoopBattle
  -- has already taken it off CoopManager.bigBattle, so the partner's word in
  -- these seconds -- their three picked (coop_bigbattle_ready), or B in their
  -- READ ALONG box (coop_battle_decline) -- found no invite: the ready was
  -- answered with a cancel that threw them out, the decline was dropped, and
  -- either way you then sat 60s in WAITING for nobody.
  CoopManager.hostingBig = big
  -- the difficulty this battle is fought at, on both copies (CoopBalance)
  battle.coopBalanceRules = battle.coopBalanceRules or require("src.coop.CoopBalance").currentRules()
  local function solo() CoopManager.hostingBig = nil ow:pushBattle(battle, opts) end
  game.stack:push(CoopBattleSelect.new(game, game.save.party, function(chosenMons)
    CoopManager.hostingBig = nil
    if big.declined then
      CoopManager.showStatus(big.declineText or "Partner won't join. Solo!", 2.5)
      solo()
      return
    end
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
  local hosting = CoopManager.hostingBig
  if not (big and big.inviteId == msg.inviteId) and hosting and hosting.inviteId == msg.inviteId
     and not hosting.declined then
    big = hosting
  end
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

  if CoopManager.incomingInviteBuffer and CoopManager.incomingInviteBuffer.msg.inviteId ~= msg.inviteId then
    CoopManager.net:send({ type = "coop_battle_decline", inviteId = CoopManager.incomingInviteBuffer.msg.inviteId, reason = "busy" })
    CoopManager.incomingInviteBuffer = nil
  end

  if CoopManager.isLocalInBattle(ow2) then decline("in_battle") return end
  if not (ow2 and ow2.map and mapsMatch(ow2.map.id, msg.mapId)) then decline("far") return end
  if healthyCount(game.save) <= 0 then decline("no_mons") return end

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
        isBigBattle = true,
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
      end, 150, { compact = true, lines = { "READ ALONG..." }, cancelLabel = "B: LEAVE BATTLE" })
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
  modal.lines = { pName, require("src.coop.CoopI18n").truncate("FACES " .. tName, 15) .. "!", "WANT TO JOIN?" }
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
  local ok, why = CoopManager.partnerAvailable(ow, tower, true)
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
        local stillOk, whyNot = CoopManager.partnerAvailable(ow, tower, true)
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

        -- the difficulty this battle is fought at, on both copies (CoopBalance)
        battle.coopBalanceRules = require("src.coop.CoopBalance").currentRules()
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
          ruleset = require("src.coop.CoopBattle").rulesetName(battle),
          foeRules = battle.coopBalanceRules,
        })
      end, solo))
    end },
    { label = Strings("SOLO BATTLE"), onSelect = solo },
  }

  game.stack:push(require("src.coop.CoopI18n").menu().new(game, items, {
    tx = 3,
    ty = 4,
    tw = 14,
    header = "BATTLE MODE:",
    cancelable = true,
    onCancel = solo,
  }))
  return true
end

end

return M
