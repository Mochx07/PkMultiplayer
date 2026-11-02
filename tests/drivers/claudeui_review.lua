-- UI REVIEW between two real game instances (Gold or Yellow), linked over
-- 127.0.0.1, in the language PKM_LANG (en | es).
--
--   pair.sh <mod> tests/drivers/claudeui_review.lua <port> <gold|yellow> <host> <guest> <out>
--
-- Screenshots every co-op screen the players see: the co-op menu and its
-- pages, chat, emotes, status lines, the warp prompt, the battle invite, the
-- wait modal (and whether START / A / SELECT pressed on it reach the
-- overworld), and, in a co-op wild double, the partner's plan box left of
-- FIGHT / PKMN / PACK / RUN for each kind of choice the partner makes.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7830")
  local LANG = os.getenv("PKM_LANG") or "en"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local n = 0
  local function shot(name)
    n = n + 1
    U.shot(game, DIR .. ("/%02d_%s.png"):format(n, name))
  end
  local function secs(s)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < s do U.wait(1) end
  end
  local function waitFor(pred, s)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < (s or 20) do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end
  local function topName()
    local t = game.stack:top()
    if not t then return "nil" end
    if t == game.overworld then return "overworld" end
    if t.isCoopInvite then return "invite" end
    if t.isCoopBattleSelect then return "select" end
    if t.isCoopWaitModal then return "waitmodal" end
    if t.isChatBox then return "chat" end
    if t.isTextBox then return "textbox" end
    return tostring(t.kind or t.phase or t.isCoopMenu and "coopmenu" or t)
  end

  U.wait(5)
  local I18n = require("src.coop.CoopI18n")
  I18n.forced = LANG
  local GameVersion = require("src.core.GameVersion")
  local gen1 = GameVersion.isGen1()
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopBattle = require("src.coop.CoopBattle")
  local BattleState = require("src.battle.BattleState")
  local P = BattleState.POS
  local save = U.freshSave(game)
  -- seven letters: the longest name a player can give
  save.player.name = role == "host" and "MOCHIXL" or "TOBYMON"

  local function speciesNamed(name)
    for id, def in pairs(game.data.pokemon) do
      if def.name == name then return id end
    end
    return next(game.data.pokemon)
  end
  local function mapLike(cands)
    for _, id in ipairs(cands) do if game.data.maps[id] then return id end end
    for id in pairs(game.data.maps) do
      for _, c in ipairs(cands) do if id:find(c, 1, true) then return id end end
    end
    return cands[1]
  end
  local HOME = gen1 and mapLike({ "PALLET_TOWN" }) or "NEW_BARK_TOWN"
  local AWAY = gen1 and mapLike({ "PALLET_TOWN" }) or "NEW_BARK_TOWN"
  local WILD = gen1 and mapLike({ "ROUTE_1", "ROUTE1" }) or "ROUTE29"
  U.log(role .. ": gen1=" .. tostring(gen1) .. " home=" .. HOME .. " away=" .. AWAY .. " wild=" .. WILD)
  save.visited = save.visited or {}
  for _, m in ipairs({ HOME, AWAY, WILD }) do save.visited[m] = true end

  local team = role == "host" and { "BULBASAUR", "PIDGEOTTO" } or { "CHARMANDER", "BUTTERFREE" }
  for _, nm in ipairs(team) do
    local m = Pokemon.new(game.data, speciesNamed(nm), 50)
    if role == "host" then
      m.moves = { { id = "HARDEN", pp = 30 }, { id = "GROWL", pp = 40 } }
    else
      m.moves = { { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
                  { id = "HARDEN", pp = 30 }, { id = "EARTHQUAKE", pp = 10 } }
    end
    table.insert(save.party, m)
  end

  U.teleport(game, WILD, role == "host" and 10 or 12, 8, "down")

  -- ------------------------------------------------------------ offline
  if role == "host" then
    game.stack:push(require("src.coop.CoopMenu").new(game))
    U.wait(15)
    shot("menu_offline")
    U.tap(game, "b"); U.wait(10)
    if game.stack:top() ~= game.overworld then game.stack:pop() end
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(90)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = waitFor(function()
    return CoopManager.isConnected() and CoopManager.partner and CoopManager.partner.map == WILD
  end, 40)
  check(linked, "linked, both on " .. WILD)
  if not linked then love.event.quit(1) return end
  U.wait(60)
  shot("linked_overworld")

  -- ------------------------------------------------------------ menus (host)
  if role == "host" then
    local CoopMenu = require("src.coop.CoopMenu")
    local menu = CoopMenu.new(game)
    game.stack:push(menu)
    U.wait(15)
    shot("menu_main")
    -- every row once, so a row's info box shows
    for i = 1, 3 do U.tap(game, "down"); U.wait(6) end
    shot("menu_main_ready_warp")
    for i = 1, 6 do U.tap(game, "down"); U.wait(6) end
    shot("menu_main_bottom")
    menu.page, menu.index, menu.scroll = "partner", 1, 1
    U.wait(10)
    shot("menu_partner")
    menu.page, menu.index, menu.scroll = "rules", 1, 1
    U.wait(10)
    shot("menu_rules_1")
    for i = 1, 4 do U.tap(game, "down"); U.wait(6) end
    shot("menu_rules_5")
    for i = 1, 4 do U.tap(game, "down"); U.wait(6) end
    shot("menu_rules_last")
    while game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(10)
    -- a status line with the partner's name: a coop_story_hold from them
    require("src.coop.CoopStory").onPartnerHold({ map = WILD, class = "OPP_FALKNER" })
    U.wait(5)
    shot("status_waiting_for_you")
    local heard = waitFor(function() return #(CoopManager.chatLog or {}) >= 1 end, 25)
    check(heard, "the partner's chat line arrives")
    U.wait(20)
    shot("chat_received")
    secs(2)
    shot("emote_received")
    secs(4)
  else
    -- the guest chats and sends an emote once the host is out of its menus
    secs(16)
    CoopManager.sendChat(LANG == "es" and "HOLA, ¿QUÉ TAL? VAMOS AL GIMNASIO" or "HI! LET'S GO TO THE GYM TOGETHER")
    secs(2)
    CoopManager.sendEmote(require("src.coop.CoopEmotes").LIST[2].id)
    secs(4)
    -- guest: its chat box and the emote picker
    CoopManager.openChat(game, game.overworld)
    U.wait(10)
    local box = game.stack:top()
    if box and box.onTextInput then box:onTextInput(LANG == "es" and "ESPERAME AQUÍ" or "WAIT FOR ME HERE") end
    U.wait(10)
    shot("chat_box_typing")
    U.tap(game, "b"); U.wait(10)
    if game.stack:top() ~= game.overworld then game.stack:pop() end
    require("src.coop.CoopEmotes").openPicker(game)
    U.wait(15)
    shot("emote_picker")
    U.tap(game, "right"); U.wait(6)
    shot("emote_picker_2")
    U.tap(game, "b"); U.wait(10)
    if game.stack:top() ~= game.overworld then game.stack:pop() end
  end
  secs(3)
  shot("after_chat")

  -- ------------------------------------------------------------ warp prompt
  -- the guest steps to another town; the host asks to warp there
  if role == "guest" then
    U.teleport(game, AWAY, 6, 8, "down")
    local asked = waitFor(function() return game.stack:top() and game.stack:top().isTextBox end, 25)
    check(asked, "the warp question arrives")
    U.wait(40)
    shot("warp_prompt")
    -- answer NO
    for _ = 1, 4 do U.tap(game, "a"); U.wait(12) end
    U.wait(30)
    shot("warp_answered")
    while game.stack:top() ~= game.overworld do U.tap(game, "b"); U.wait(10) end
    U.teleport(game, WILD, 12, 8, "down")
  else
    waitFor(function() return CoopManager.partner.map == AWAY end, 25)
    U.wait(60)
    CoopManager.lastWarpAt = nil
    local ok = CoopManager.warpToPartner(game.overworld)
    check(ok, "warp asked")
    U.wait(5)
    shot("warp_asked_status")
    waitFor(function() return CoopManager.warpAsk == nil end, 25)
    U.wait(5)
    shot("warp_reply_status")
    waitFor(function() return CoopManager.partner.map == WILD end, 25)
  end
  secs(4)

  -- ------------------------------------------------------------ the battle
  local function topBattle()
    local top = game.stack:top()
    return top and top.coopDouble and top or nil
  end
  local foeSpecies = speciesNamed("PIDGEY")
  local leak = {}
  if role == "host" then
    CoopManager.setRule("wildTogether", true)
    U.wait(30)
    local ow = game.overworld
    local battle = BattleState.newWild(game, foeSpecies, 12)
    battle.onFinish = function(r) ow:afterBattle(r, battle) end
    ow.pkmRandomEncounter = true
    ow:pushBattle(battle)
    ow.pkmRandomEncounter = nil
    check(CoopManager.pendingBattleInvite ~= nil, "the partner is asked")
    local modalUp = waitFor(function()
      for _, s in ipairs(game.stack.states) do if s.isCoopWaitModal then return true end end
      return false
    end, 10)
    check(modalUp, "the host waits in the wait modal")
    U.wait(20)
    shot("host_wait_modal")
    -- START / A / SELECT on the wait modal must not reach the overworld
    leak.before = topName()
    U.tap(game, "start"); U.wait(4)
    U.tap(game, "select"); U.wait(4)
    U.tap(game, "a"); U.wait(4)
    leak.after = topName()
    shot("host_wait_modal_after_keys")
    U.log("host: wait-modal top before/after keys: " .. leak.before .. " / " .. leak.after)
  else
    local asked = waitFor(function() return CoopManager.activeInviteModal ~= nil end, 40)
    check(asked, "the invite arrives")
    U.wait(70)
    shot("guest_invite")
    U.tap(game, "a"); U.wait(30)
    shot("guest_select")
    -- keep the host waiting a little so its wait modal is seen
    secs(4)
    U.tap(game, "start"); U.wait(30)
  end

  local battle
  waitFor(function() battle = topBattle() return battle ~= nil end, 25)
  check(battle and battle.coopWild, "a co-op wild double is up")
  if not battle then love.event.quit(1) return end
  if role == "host" then
    -- nothing the keys did on the wait modal is left on the stack
    local opened = false
    for _, s in ipairs(game.stack.states) do
      if s ~= battle and s ~= game.overworld and (s.items or s.isCoopMenu) then opened = true end
    end
    check(not opened, "no start menu opened under the battle by keys pressed on the wait modal")
  end
  waitFor(function()
    if battle.phase == "menu" then return true end
    U.tap(game, "a"); U.wait(4)
    return false
  end, 30)
  check(battle.phase == "menu", "reached FIGHT / PKMN / PACK / RUN")
  local c = battle.coop

  local function mvOf(mon, id)
    for _, mv in ipairs(mon.moves or {}) do if mv.id == id then return mv end end
  end

  if role == "guest" then
    local me = battle:battlerAt(P.PLAYER_LEFT)
    local plan = {
      -- turn 1: into the PACK and out again, then TACKLE on the right foe
      function()
        secs(14)
        U.tap(game, "down"); U.wait(15)
        U.log("guest: after DOWN+A? top=" .. topName())
        U.tap(game, "a"); U.wait(30)
        U.log("guest: pack open? top=" .. topName() .. " waitingUI=" .. tostring(battle.waitingUI))
        shot("guest_in_bag")
        secs(5)
        U.tap(game, "b"); U.wait(30)
        U.log("guest: pack closed? top=" .. topName())
        secs(3)
        local mv = mvOf(me.mon, "TACKLE")
        mv.targetPosition = P.OPPONENT_RIGHT
        battle:chooseAction(mv)
      end,
      function() battle:chooseAction(mvOf(me.mon, "GROWL")) end,
      function() battle:chooseAction(mvOf(me.mon, "HARDEN")) end,
      function() battle:chooseAction(mvOf(me.mon, "EARTHQUAKE")) end,
    }
    for turn = 1, #plan do
      local ok = waitFor(function()
        if c.turn == turn and battle.phase == "menu" and game.stack:top() == battle then return true end
        if battle.phase ~= "menu" and battle.phase ~= "waitPartner" and game.stack:top() == battle then
          U.tap(game, "a"); U.wait(3)
        end
        return false
      end, 60)
      if not ok then U.log("guest: turn " .. turn .. " menu not reached, phase " .. tostring(battle.phase)) break end
      secs(2)
      shot(("guest_turn%d_menu"):format(turn))
      plan[turn]()
      U.log("guest: turn " .. turn .. " chosen")
    end
    -- the host keeps looking at its plan box from here; just idle
    secs(40)
  else
    -- every other kind of choice, drawn into the same box at turn 1 before
    -- the guest makes its own (it waits 14 s): the partner's choice for the
    -- turn written straight in, then taken out again
    local function injectCases()
      local function xid(key)
        for id, def in pairs(game.data.items) do
          if id == key or def.name == key then return id end
        end
        return key
      end
      local cases = {
        { "item_xattack_self", { kind = "item", id = xid("X_ATTACK") } },
        { "item_potion_named", { kind = "item", id = xid("SUPER_POTION"), targetNick = "BUTTERFREE" } },
        { "item_flute_everyone", { kind = "item", id = xid("POKE_FLUTE"), boost = { flute = true } } },
        { "move_foe1_dup", { kind = "move", id = "TACKLE", target = P.OPPONENT_LEFT } },
        { "move_long_name", { kind = "move", id = "DOUBLE_EDGE", target = P.OPPONENT_RIGHT } },
        { "move_on_you", { kind = "move", id = "TACKLE", target = P.PLAYER_RIGHT } },
        { "switch", { kind = "switch", index = 2 } },
        { "locked", { kind = "locked" } },
        { "dup_long_species", { kind = "move", id = "TACKLE", target = P.OPPONENT_RIGHT }, "BUTTERFREE" },
      }
      c.partnerActions = c.partnerActions or {}
      for _, case in ipairs(cases) do
        local f1, f2 = battle:battlerAt(P.OPPONENT_LEFT), battle:battlerAt(P.OPPONENT_RIGHT)
        local n1, n2 = f1 and f1.name, f2 and f2.name
        if case[3] and f1 and f2 then f1.name, f2.name = case[3], case[3] end
        c.partnerActions[c.turn] = case[2]
        U.wait(4)
        local lines = CoopBattle.partnerPlan(battle) or {}
        U.log(("host: %s plan: %s | %s | %s"):format(case[1], tostring(lines[1]), tostring(lines[2]), tostring(lines[3])))
        shot("plan_" .. case[1])
        if case[3] and f1 and f2 then f1.name, f2.name = n1, n2 end
      end
      c.partnerActions[c.turn] = nil
      c.partnerInBag = true
      U.wait(4)
      shot("plan_in_bag_injected")
      c.partnerInBag = nil
    end
    local labels = { "tackle_foe2", "growl_allfoes", "harden_self", "earthquake_everyone" }
    for turn = 1, 4 do
      local ok = waitFor(function()
        if c.turn == turn and battle.phase == "menu" and game.stack:top() == battle then return true end
        if battle.phase ~= "menu" and battle.phase ~= "waitPartner" and game.stack:top() == battle then
          U.tap(game, "a"); U.wait(3)
        end
        return false
      end, 60)
      if not ok then U.log("host: turn " .. turn .. " menu not reached, phase " .. tostring(battle.phase)) break end
      if turn == 1 then
        U.wait(10)
        injectCases()
        shot("plan_choosing")
        local bag = waitFor(function() return c.partnerInBag == true end, 20)
        check(bag, "the partner's PACK shows in the plan box")
        U.wait(10)
        shot("plan_in_bag")
        waitFor(function() return c.partnerInBag ~= true end, 20)
        U.wait(10)
        shot("plan_out_of_bag")
      end
      local got = waitFor(function() return c.partnerActions and c.partnerActions[c.turn] ~= nil end, 30)
      check(got, "turn " .. turn .. ": the partner's choice arrived")
      U.wait(10)
      local lines = CoopBattle.partnerPlan(battle) or {}
      U.log(("host: turn %d plan: %s | %s | %s"):format(turn, tostring(lines[1]), tostring(lines[2]), tostring(lines[3])))
      shot("plan_" .. labels[turn])
      local me = battle:battlerAt(P.PLAYER_LEFT)
      battle:chooseAction(mvOf(me.mon, turn % 2 == 1 and "HARDEN" or "GROWL"))
    end
    -- the turn plays out on both screens before either copy quits
    secs(15)
  end

  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
