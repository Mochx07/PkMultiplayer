-- Two real game instances, the mod installed, linked over 127.0.0.1.
--
--   PKM_ROLE=host|guest PKM_PORT=7790 SHOT_DIR=/tmp/pkm \
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=<mod>/tests/drivers/coop_smoke.lua love .
--
-- Each copy checks the mod booted and patched cleanly, links up, waits to see
-- the other's avatar on the same map, and screenshots the overworld and the
-- start menu.  The host then fights a co-op double on its own (the partner's
-- slot played by the stand-in AI) and screenshots it: the doubles layout,
-- the HUDs and the move animations are drawn by patched engine code.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  local STATE = rawget(_G, "__PKMULTIPLAYER")
  check(STATE ~= nil, "the mod booted")
  if not STATE then love.event.quit(1) return end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local function species(n)
    local id = ("SPECIES_%03d"):format(n)
    return game.data.pokemon[id] and id or next(game.data.pokemon)
  end
  local team = role == "host" and { 155, 16, 19 } or { 158, 161, 163 }
  for _, n in ipairs(team) do
    table.insert(save.party, Pokemon.new(game.data, species(n), 14))
  end

  U.teleport(game, "NEW_BARK_TOWN", role == "host" and 6 or 8, 8, "down")
  check(game.overworld ~= nil, "in the overworld")

  -- every patched engine module that is loaded by now came through clean
  local index = loadstring(STATE.mod:read("lib/patches/index.lua"))()
  for _, spec in ipairs(index.modules) do
    local report = STATE.reports[spec.module]
    if package.loaded[spec.module] then
      check(report ~= nil and #report.drift == 0 and #report.missing == 0
            and #report.failed == 0,
            "patched " .. spec.module)
    end
  end

  local solo = os.getenv("PKM_SOLO") == "1"
  if solo then
    -- no partner: only the start menu and the double below
  elseif role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = solo
  for _ = 1, solo and 0 or 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner and CoopManager.partner.name then
      linked = true
      break
    end
    U.wait(1)
  end
  if not solo then
  check(linked, "linked with " .. tostring(CoopManager.partner and CoopManager.partner.name))

  -- the partner's avatar walks on this map
  local seen = false
  for _ = 1, 60 * 10 do
    for _, npc in ipairs(game.overworld.npcs or {}) do
      if npc.coopPartner then seen = true end
    end
    if seen then break end
    U.wait(1)
  end
  check(seen, "the partner stands in New Bark Town")
  CoopManager.sendChat(role == "host" and "HI TOBY!" or "HEY MOCHI")
  U.wait(90)
  check(#(CoopManager.chatLog or {}) >= 1, "chat crossed the link")
  U.shot(game, DIR .. "/1_overworld.png")
  end

  U.tap(game, "start")
  U.wait(20)
  local top = game.stack:top()
  local hasRow = false
  for _, item in ipairs(top and top.items or {}) do
    if tostring(item.label):find("CO%-OP") then hasRow = true end
  end
  check(hasRow, "the start menu offers CO-OP ONLINE")
  U.shot(game, DIR .. "/2_start_menu.png")
  U.tap(game, "b")
  U.wait(10)

  if not solo then
    -- the linked co-op menu (its first row is CHAT, the phone's way in)
    game.stack:push(require("src.coop.CoopMenu").new(game))
    U.wait(10)
    U.shot(game, DIR .. "/2b_coop_menu.png")
    U.tap(game, "a")
    U.wait(15)
    local chat = game.stack:top()
    check(chat and chat.isChatBox, "CHAT in the co-op menu opens the chat box")
    U.shot(game, DIR .. "/2c_chat.png")
    U.tap(game, "b")
    U.wait(10)

    -- the emote picker: the cartridge's bubbles when this copy imported a
    -- ROM for the mod, the mod's drawn ones when it did not
    local field = game.data.field
    U.log(role .. ": emote sheet " .. tostring(field.emotionBubbles and field.emotionBubbles.path))
    check(require("src.coop.CoopEmotes").openPicker(game), "the emote picker opens")
    U.wait(10)
    U.shot(game, DIR .. "/2d_emotes.png")
    U.tap(game, "b")
    U.wait(10)
  end

  if not solo then U.wait(120) end
  if role == "host" then
    CoopManager.disconnect()
    U.wait(10)
    local BattleState = require("src.battle.BattleState")
    local CoopBattle = require("src.coop.CoopBattle")
    local battle = BattleState.newTrainer(game, "OPP_LEADER", 1)
    local partnerMons = {}
    for _, n in ipairs({ 158, 161, 163 }) do
      partnerMons[#partnerMons + 1] = Pokemon.new(game.data, species(n), 14)
    end
    local mine = { save.party[1], save.party[2], save.party[3] }
    CoopBattle.initBattle(battle, mine, partnerMons, { name = "TOBY" }, 4242, nil)
    battle.coop.partnerLost = true
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    U.wait(30)
    -- through the intro to the first FIGHT / PKMN / PACK / RUN
    for _ = 1, 150 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(5)
    end
    U.wait(10)
    check(battle.phase == "menu", "reached the action menu (" .. tostring(battle.phase) .. ")")
    U.shot(game, DIR .. "/3_double_menu.png")
    check(game.stack:top() == battle and battle.coopDouble, "a co-op double is up")
    U.tap(game, "a")
    U.wait(10)
    U.shot(game, DIR .. "/4_double_moves.png")
    U.tap(game, "a")
    U.wait(8)
    U.tap(game, "a")
    for i = 1, 6 do
      U.wait(25)
      U.shot(game, DIR .. ("/5_double_turn_%d.png"):format(i))
    end
  else
    U.wait(200)
  end

  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
