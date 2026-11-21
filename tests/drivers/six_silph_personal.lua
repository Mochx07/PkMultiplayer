-- Gen 1 co-op story driver:
-- 1. Personal case: Silph Co. 7F Lapras gift stays PERSONAL (host gets Lapras,
--    guest's EVENT_GOT_LAPRAS stays unset and guest claims their own Lapras).
-- 2. Shared Card Key door + Silph Co. 11F Giovanni fight: host unlocks the
--    11F Card Key door at (6,13) (door opens live on guest's screen too),
--    steps onto (6,13) to trigger Giovanni, and defeats him (EVENT_BEAT_SILPH_CO_GIOVANNI
--    + Silph Rockets leave on both screens).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7922")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm_six_silph") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local CM = require("src.coop.CoopManager")
  local CoopStory = require("src.coop.CoopStory")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")

  local function waitForChat(tag, timeoutSec)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < (timeoutSec or 25) do
      for _, line in ipairs(CM.chatLog or {}) do
        if line.text == tag then return true end
      end
      if CoopStory.feed[1] then U.tap(game, "a") end
      U.wait(2)
    end
    return false
  end

  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local lead = Pokemon.new(game.data, "MEWTWO", 100)
  table.insert(save.party, lead)
  Bag.add(save, "CARD_KEY", 1, game.data)

  -- Phase 1: Silph Co. 7F Lapras gift (SILPHCO7F_SILPH_WORKER_M1 is at (1,5))
  if role == "host" then
    U.teleport(game, "SILPH_CO_7F", 2, 5, "left")
  else
    U.teleport(game, "SILPH_CO_7F", 2, 6, "up")
  end
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  local tLink = love.timer.getTime()
  while love.timer.getTime() - tLink < 20 do
    if CM.isConnected() and CM.partner.map == "SILPH_CO_7F" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in SILPH_CO_7F")
  U.wait(60)

  if role == "host" then
    CM.sendChat("GO_LAPRAS")
    U.wait(10)
    U.tap(game, "a")
    U.wait(15)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      local t = game.stack:top()
      if t == game.overworld then break end
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(15)
    end
    check(save.flags.EVENT_GOT_LAPRAS == true, "host set EVENT_GOT_LAPRAS")
    check(#save.party == 2 and save.party[2].species == "LAPRAS", "host received LAPRAS in party")
    U.shot(game, DIR .. "/1_host_got_lapras.png")
    CM.sendChat("HOST_LAPRAS_DONE")
    waitForChat("GUEST_LAPRAS_DONE", 25)
  else
    waitForChat("GO_LAPRAS", 20)
    waitForChat("HOST_LAPRAS_DONE", 25)
    U.wait(30)
    CoopStory.feed = {}
    check(not save.flags.EVENT_GOT_LAPRAS, "guest EVENT_GOT_LAPRAS stayed unset (personal)")
    check(#save.party == 1, "guest did not receive host's Lapras")
    -- Guest now talks to the worker at (1,5) to claim their own personal Lapras
    U.teleport(game, "SILPH_CO_7F", 2, 5, "left")
    U.wait(20)
    U.tap(game, "a")
    U.wait(15)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      local t = game.stack:top()
      if t == game.overworld then break end
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(15)
    end
    check(save.flags.EVENT_GOT_LAPRAS == true and #save.party == 2 and save.party[2].species == "LAPRAS",
          "guest claimed their own personal LAPRAS from the worker")
    U.shot(game, DIR .. "/1_guest_own_lapras.png")
    CM.sendChat("GUEST_LAPRAS_DONE")
  end

  U.wait(30)
  CoopStory.feed = {}

  -- Phase 2: Silph Co. 11F Card Key door unlock + Giovanni fight reaching the partner
  if role == "host" then
    U.teleport(game, "SILPH_CO_11F", 6, 14, "up")
    CM.sendChat("HOST_S11_READY")
    waitForChat("GUEST_S11_READY", 20)
  else
    U.teleport(game, "SILPH_CO_11F", 7, 14, "up")
    CM.sendChat("GUEST_S11_READY")
    waitForChat("HOST_S11_READY", 20)
  end
  local tP2 = love.timer.getTime()
  while love.timer.getTime() - tP2 < 15 do
    if CM.partner.map == "SILPH_CO_11F" then break end
    U.wait(1)
  end
  U.wait(30)

  local function hasGiovanniNpc(ow)
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == "SILPHCO11F_GIOVANNI" then return true end
    end
    return false
  end
  check(hasGiovanniNpc(game.overworld), "SILPHCO11F_GIOVANNI is present before the trigger")

  if role == "host" then
    -- Press A facing the locked Card Key door at (6,13) to unlock it for both players
    U.tap(game, "a")
    U.wait(20)
    local tDoor = love.timer.getTime()
    while love.timer.getTime() - tDoor < 10 do
      local t = game.stack:top()
      if t == game.overworld then break end
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(10)
    end
    check(save.flags.EVENT_SILPH_CO_11_UNLOCKED_DOOR == true, "host unlocked Silph Co. 11F Card Key door")
    U.wait(15)
    -- Step 1 tile up through the now-open doorway onto (6,13) and wait at (6,13)
    -- for Giovanni to walk 3 tiles down from (6,9) to (6,12) and engage
    local tStep = love.timer.getTime()
    while love.timer.getTime() - tStep < 5 do
      if game.overworld.player.cellY <= 13 then break end
      U.hold(game, "up", 2)
    end
    while game.overworld.player.moving do U.wait(1) end
    local menuUp = false
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      local t = game.stack:top()
      if t and t.header and tostring(t.header):find("VS ", 1, true) then
        menuUp = true
        break
      end
      U.wait(2)
    end
    check(menuUp, "VS GIOVANNI big-battle menu opened before pre-battle speech")
    U.shot(game, DIR .. "/2_vs_giovanni_menu.png")
    -- Pick SOLO (row 2) so the host's win must reach the guest via CoopStory rewards
    U.tap(game, "down")
    U.wait(10)
    U.tap(game, "a")
    U.wait(15)
    -- Advance pre-battle speech into BattleState, then win the battle
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 25 do
      local t = game.stack:top()
      if t and t.kind == "trainer" and t.onFinish then
        game.stack:pop()
        t.onFinish("win")
        break
      elseif t and t.isTextBox then
        U.tap(game, "a")
      end
      U.wait(10)
    end
    -- Dismiss post-battle defeat dialogue
    local t2 = love.timer.getTime()
    while love.timer.getTime() - t2 < 15 do
      local t = game.stack:top()
      if t == game.overworld then break end
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(10)
    end
    check(save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI == true, "host set EVENT_BEAT_SILPH_CO_GIOVANNI")
    check(not hasGiovanniNpc(game.overworld), "Giovanni left host's SILPH_CO_11F")
    U.shot(game, DIR .. "/3_host_giovanni_cleared.png")
    CM.sendChat("HOST_GIO_DONE")
    waitForChat("GUEST_GIO_DONE", 20)
  else
    -- Guest stands on SILPH_CO_11F and receives the Card Key door unlock + Giovanni defeat + Rocket exodus
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 30 do
      if CoopStory.feed[1] then U.tap(game, "a") U.wait(15) end
      if save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI then break end
      U.wait(2)
    end
    U.wait(30)
    CoopStory.feed = {}
    check(save.flags.EVENT_SILPH_CO_11_UNLOCKED_DOOR == true,
          "guest received EVENT_SILPH_CO_11_UNLOCKED_DOOR and opened the 11F door live")
    check(save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI == true,
          "guest received EVENT_BEAT_SILPH_CO_GIOVANNI from host's Giovanni fight")
    check(not hasGiovanniNpc(game.overworld),
          "SILPHCO11F_GIOVANNI and Rockets vanished on guest's screen too")
    U.shot(game, DIR .. "/3_guest_giovanni_cleared.png")
    CM.sendChat("GUEST_GIO_DONE")
    waitForChat("HOST_GIO_DONE", 20)
  end

  U.wait(30)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
