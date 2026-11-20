-- Gen 1 co-op story driver: Pokemon Tower 6F Ghost Marowak -> 7F Mr. Fuji
-- rescue -> Mr. Fuji's House Poke Flute (story.duo scene on both screens)
-- -> Route 12 Snorlax wake into the "snorlax" co-op boss.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7920")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm_six_tower") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function topText(top)
    local p = top and top.pages and top.pages[top.pageIndex or 1]
    return p and table.concat(p, " / ") or ""
  end
  local function normText(s)
    return tostring(s or ""):gsub(" / ", " "):gsub("%s+", " ")
  end

  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local CM = require("src.coop.CoopManager")
  local CoopStory = require("src.coop.CoopStory")
  local CoopDuo = require("src.coop.CoopDuo")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")

  local function waitForChat(tag, timeoutSec)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < (timeoutSec or 25) do
      for _, line in ipairs(CM.chatLog or {}) do
        if line.text == tag then return true end
      end
      U.wait(1)
    end
    return false
  end

  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local lead = Pokemon.new(game.data, "MEWTWO", 70)
  table.insert(save.party, lead)
  Bag.add(save, "SILPH_SCOPE", 1, game.data)
  Bag.add(save, "POKE_DOLL", 1, game.data)

  -- Phase 1: Pokemon Tower 6F Ghost Marowak gate at (10,16)
  if role == "host" then
    U.teleport(game, "POKEMON_TOWER_6F", 11, 16, "left")
  else
    U.teleport(game, "POKEMON_TOWER_6F", 11, 15, "down")
  end
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  local tLink = love.timer.getTime()
  while love.timer.getTime() - tLink < 20 do
    if CM.isConnected() and CM.partner.map == "POKEMON_TOWER_6F" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in POKEMON_TOWER_6F")
  U.wait(60)
  check(CoopDuo.on(), "story.duo is active for both players")

  if role == "host" then
    CM.sendChat("GO_MAROWAK")
    U.wait(10)
    -- Step left onto (10,16) to trigger the Ghost Marowak
    U.hold(game, "left", 16)
    U.wait(65)
    local top = game.stack:top()
    check(top and top.isTextBox, "Ghost Marowak 'Be gone... Intruders...' box opened")
    U.shot(game, DIR .. "/1_marowak_begone.png")
    -- Advance into the battle and finish it immediately
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      local t = game.stack:top()
      if t and t.kind == "wild" and t.onFinish then
        t.pokeDollEscape = true
        t.onFinish("run")
        game.stack:pop()
        break
      elseif t and t.isTextBox then
        U.tap(game, "a")
      end
      U.wait(8)
    end
    U.wait(20)
    -- Dismiss the "mother's soul was calmed" text box
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 15 do
      local t = game.stack:top()
      if t == game.overworld then break end
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(10)
    end
    check(save.flags.EVENT_BEAT_GHOST_MAROWAK == true, "host calmed Ghost Marowak")
    CM.sendChat("HOST_MAROWAK_DONE")
    waitForChat("GUEST_MAROWAK_DONE", 20)
  else
    waitForChat("GO_MAROWAK", 20)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      if CoopStory.feed[1] then break end
      U.wait(1)
    end
    check(CoopStory.feed[1] ~= nil, "guest sees Marowak text in duo feed")
    U.wait(15)
    U.shot(game, DIR .. "/1_marowak_feed.png")
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 20 do
      if CoopStory.feed[1] then U.tap(game, "a") U.wait(20) end
      if save.flags.EVENT_BEAT_GHOST_MAROWAK then break end
      U.wait(2)
    end
    for _ = 1, 10 do
      if not CoopStory.feed[1] then break end
      U.tap(game, "a")
      U.wait(20)
    end
    check(save.flags.EVENT_BEAT_GHOST_MAROWAK == true, "guest received EVENT_BEAT_GHOST_MAROWAK")
    CM.sendChat("GUEST_MAROWAK_DONE")
    waitForChat("HOST_MAROWAK_DONE", 20)
  end

  U.wait(30)
  CoopStory.feed = {}

  -- Phase 2: Pokemon Tower 7F Mr. Fuji rescue + shared warp to MR_FUJIS_HOUSE
  save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 = true
  save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_1 = true
  save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_2 = true
  if role == "host" then
    U.teleport(game, "POKEMON_TOWER_7F", 10, 4, "up")
  else
    U.teleport(game, "POKEMON_TOWER_7F", 11, 4, "up")
  end
  local tP2 = love.timer.getTime()
  while love.timer.getTime() - tP2 < 20 do
    if CM.partner.map == "POKEMON_TOWER_7F" then break end
    U.wait(1)
  end
  U.wait(45)
  U.shot(game, DIR .. "/2_tower7f_fuji.png")

  if role == "host" then
    CM.sendChat("HOST_T7_READY")
    waitForChat("GUEST_T7_READY", 20)
    U.wait(10)
    U.tap(game, "a")
    U.wait(15)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 25 do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == "MR_FUJIS_HOUSE" and game.stack:top() == ow then break end
      local t = game.stack:top()
      if t and t.isTextBox then U.tap(game, "a") end
      U.wait(15)
    end
    check(game.overworld.map.id == "MR_FUJIS_HOUSE", "host warped to MR_FUJIS_HOUSE")
    check(save.flags.EVENT_RESCUED_MR_FUJI == true, "host set EVENT_RESCUED_MR_FUJI")
    check(((save.objectToggles or {}).POKEMON_TOWER_7F or {}).POKEMONTOWER7F_MR_FUJI == false,
          "host hid POKEMONTOWER7F_MR_FUJI on 7F")
    CM.sendChat("HOST_FUJI_WARPED")
    waitForChat("GUEST_FUJI_WARPED", 25)
  else
    CM.sendChat("GUEST_T7_READY")
    waitForChat("HOST_T7_READY", 20)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 25 do
      if CoopStory.feed[1] then U.tap(game, "a") U.wait(20) end
      local ow = game.overworld
      if ow and ow.map and ow.map.id == "MR_FUJIS_HOUSE" and not CoopStory.feed[1] then break end
      U.wait(2)
    end
    check(save.flags.EVENT_RESCUED_MR_FUJI == true, "guest received EVENT_RESCUED_MR_FUJI")
    check(((save.objectToggles or {}).POKEMON_TOWER_7F or {}).POKEMONTOWER7F_MR_FUJI == false,
          "guest hid POKEMONTOWER7F_MR_FUJI on 7F")
    check(game.overworld.map.id == "MR_FUJIS_HOUSE", "guest warped to MR_FUJIS_HOUSE with host")
    CM.sendChat("GUEST_FUJI_WARPED")
    waitForChat("HOST_FUJI_WARPED", 25)
  end

  U.wait(30)

  -- Phase 3: Mr. Fuji's House Poke Flute handover (story.duo scene on both screens)
  CoopStory.feed = {}
  CoopDuo.reset()
  if role == "host" then
    U.teleport(game, "MR_FUJIS_HOUSE", 3, 2, "up")
    CM.sendChat("HOST_HOUSE_READY")
    waitForChat("GUEST_HOUSE_READY", 20)
  else
    U.teleport(game, "MR_FUJIS_HOUSE", 4, 2, "left")
    CM.sendChat("GUEST_HOUSE_READY")
    waitForChat("HOST_HOUSE_READY", 20)
  end
  local tP3 = love.timer.getTime()
  while love.timer.getTime() - tP3 < 15 do
    if CM.partner.map == "MR_FUJIS_HOUSE" then break end
    U.wait(1)
  end
  U.wait(30)

  if role == "host" then
    local ow = game.overworld
    U.tap(game, "a")
    U.wait(10)
    check(ow.runner and ow.runner:isRunning(), "talking to Mr. Fuji in his house")
    local pages, lastText, sawDuo, sawHandover = 0, nil, false, nil
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 45 do
      local top = game.stack:top()
      local running = ow.runner and ow.runner.isRunning and ow.runner:isRunning()
      if not running and top == ow then break end
      if top and top.isTextBox then
        local txt = topText(top)
        if txt ~= lastText and txt ~= "" then
          lastText = txt
          pages = pages + 1
          U.log("host Fuji page " .. pages .. ": " .. txt)
          if normText(txt):find("MOCHI & TOBY", 1, true) then sawDuo = true end
          if txt:find("FLUTE", 1, true) and txt:find("received", 1, true) then sawHandover = txt end
          if pages == 1 then
            U.wait(70)
            U.shot(game, DIR .. "/3_duo_scene_host.png")
          elseif sawHandover and pages == 4 then
            U.wait(70)
            U.shot(game, DIR .. "/4_duo_handover_host.png")
          end
        end
        U.wait(25)
        U.tap(game, "a")
      end
      U.wait(2)
    end
    check(sawDuo, "Mr. Fuji addresses MOCHI & TOBY on host screen")
    check(sawHandover and sawHandover:find("MOCHI received", 1, true),
          "handover page names MOCHI alone: " .. tostring(sawHandover))
    check((save.inventory.POKE_FLUTE or 0) == 1 and save.flags.EVENT_GOT_POKE_FLUTE == true,
          "host received POKE_FLUTE and EVENT_GOT_POKE_FLUTE")
    local gotToo = false
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 25 do
      if CM.statusMessage and CM.statusMessage:find("too!", 1, true) then gotToo = true break end
      U.wait(1)
    end
    check(gotToo, "host sees 'TOBY got one too!' (" .. tostring(CM.statusMessage) .. ")")
    CM.sendChat("HOST_FLUTE_DONE")
    waitForChat("GUEST_FLUTE_DONE", 25)
  else
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 do
      if CoopStory.feed[1] then break end
      U.wait(1)
    end
    check(CoopStory.feed[1] ~= nil, "guest sees Mr. Fuji duo scene in feed")
    U.wait(20)
    U.shot(game, DIR .. "/3_duo_scene_guest.png")
    local firstLine = normText((CoopStory.feed[1] and CoopStory.feed[1][1] or "") .. " "
                               .. (CoopStory.feed[1] and CoopStory.feed[1][2] or ""))
    U.log("guest first feed page: " .. firstLine)
    check(firstLine:find("TOBY & MOCHI", 1, true), "guest's duo feed names TOBY & MOCHI first")

    -- Keep turning feed pages with A while the host's scene is running or
    -- until the gift box pops up on the guest's stack
    local giftBox
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 35 do
      local top = game.stack:top()
      if top and top.coopGift then
        giftBox = top
        break
      end
      if CoopStory.feed[1] then
        U.tap(game, "a")
        U.wait(20)
      else
        U.wait(2)
      end
    end
    check(giftBox ~= nil, "guest gets their own POKE_FLUTE gift box")
    U.wait(70)
    U.shot(game, DIR .. "/4_duo_handover_guest.png")
    local gtxt = giftBox and topText(giftBox) or ""
    U.log("guest gift box: " .. gtxt)
    check(gtxt:find("TOBY received", 1, true) and gtxt:find("FLUTE", 1, true),
          "guest gift box reads 'TOBY received POKe FLUTE!'")
    for _ = 1, 15 do
      if game.stack:top() ~= giftBox then break end
      U.tap(game, "a")
      U.wait(20)
    end
    check((save.inventory.POKE_FLUTE or 0) == 1 and save.flags.EVENT_GOT_POKE_FLUTE == true,
          "guest received POKE_FLUTE and EVENT_GOT_POKE_FLUTE")
    CM.sendChat("GUEST_FLUTE_DONE")
    waitForChat("HOST_FLUTE_DONE", 25)
  end

  -- Phase 4: Verify POKE_FLUTE wakes Route 12 Snorlax into the "snorlax" co-op boss
  if role == "host" then
    U.teleport(game, "ROUTE_12", 10, 61, "down")
  else
    U.teleport(game, "ROUTE_12", 9, 61, "down")
  end
  local tP4 = love.timer.getTime()
  while love.timer.getTime() - tP4 < 15 do
    if CM.partner.map == "ROUTE_12" then break end
    U.wait(1)
  end
  U.wait(30)
  if role == "host" then
    local ItemEffects = require("src.inventory.ItemEffects")
    local res, _, extra = ItemEffects.use(game.data, save, "POKE_FLUTE", nil, nil, nil, game.overworld)
    check(res == "flute_wake" and extra and extra.mapId == "ROUTE_12",
          "POKE_FLUTE wakes sleeping Snorlax on ROUTE_12")
    local mod = require("data.scripts.init").get("ROUTE_12")
    game.overworld.runner:run(mod.snorlaxWake.script, { npc = extra.npc })
    local sawBossMenu = false
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 15 do
      local top = game.stack:top()
      if top and top.header == "BATTLE MODE:" then
        sawBossMenu = true
        break
      elseif top and top.isTextBox then
        U.tap(game, "a")
      end
      U.wait(10)
    end
    check(sawBossMenu, "Route 12 Snorlax opens BATTLE MODE: CO-OP BOSS / SOLO BATTLE")
    U.shot(game, DIR .. "/5_snorlax_boss_menu.png")
    CM.sendChat("SNORLAX_DONE")
  else
    waitForChat("SNORLAX_DONE", 20)
  end

  U.wait(30)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
