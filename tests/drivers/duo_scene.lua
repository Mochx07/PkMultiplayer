-- A SHARED GIFT SCENE WITH TWO LEADS (1.20 story.duo), two Gold copies.
--
--   pair.sh <mod> duo_scene.lua <port> gold <host> <guest> <out>
--
-- Both stand in CHERRYGROVE CITY by the MYSTIC WATER fisher (7,12).  The
-- host (MOCHI) talks to him: his three pages, the gift, his goodbye.  The
-- guest (TOBY) stands next to them and:
--   * reads the scene in the box over their own game, and turns its pages
--     with their own A (it waits for them; they start late on purpose, so
--     the pages they missed fold into "Skipped N pages");
--   * reacts with SELECT + UP: the host sees the bubble over TOBY and the
--     line "TOBY: WOW!";
--   * gets the gift in a box of their own, "TOBY received MYSTIC WATER!",
--     and the host's screen then reads "TOBY got one too!".
-- The host reacts too (SELECT + DOWN inside its own dialogue box) and its
-- handover page reads "MOCHI got MYSTIC WATER!", not "MOCHI & TOBY".
-- DUO_OLD=1 on the guest takes story.duo out of its caps (a partner without
-- it): the old timed feed and "You got MYSTIC WATER too!" must come back.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local old = os.getenv("DUO_OLD") == "1"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
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
  local CoopDuo = require("src.coop.CoopDuo")
  if old and role == "guest" then CM.CAPS["story.duo"] = nil end
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, Pokemon.new(game.data, role == "host" and "SPECIES_155" or "SPECIES_158", 12))
  -- the host right above the fisher (he faces up), the guest a step away
  if role == "host" then
    U.teleport(game, "CHERRYGROVE_CITY", 7, 11, "down")
  else
    U.teleport(game, "CHERRYGROVE_CITY", 6, 12, "right")
  end
  if role == "host" then CM.host(port) else U.wait(60) CM.join("127.0.0.1", port) end
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "CHERRYGROVE_CITY" then break end
    U.wait(1)
  end
  check(CM.isConnected(), "linked in CHERRYGROVE CITY")
  U.wait(90)
  check(CoopDuo.on() == not old, "story.duo is " .. (old and "off (old partner)" or "on for both"))
  local ITEM = "ITEM_095"
  local had = save.inventory[ITEM] or 0
  U.shot(game, DIR .. "/0_together.png")

  local function topText(top)
    local p = top and top.pages and top.pages[top.pageIndex or 1]
    return p and table.concat(p, " / ") or ""
  end

  -- the same second on both machines' clock
  local go = os.time() + 2
  while os.time() < go do U.wait(1) end

  if role == "host" then
    local ow = game.overworld
    U.tap(game, "a")
    U.wait(10)
    check(ow.runner and ow.runner:isRunning(), "talking to the fisher")
    local pages, lastText, reacted, sawPartnerReact, handover = 0, nil, false, false, nil
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 60 do
      local top = game.stack:top()
      local running = ow.runner and ow.runner.isRunning and ow.runner:isRunning()
      if not running and top == ow then break end
      if top and top.isTextBox then
        local txt = topText(top)
        if txt ~= lastText and txt ~= "" then
          lastText = txt
          pages = pages + 1
          U.log("host page " .. pages .. ": " .. txt)
          if txt:find("MYSTIC WATER!", 1, true) and txt:find("got", 1, true) then handover = txt end
          U.wait(40)
          U.shot(game, DIR .. ("/1_page_%d.png"):format(pages))
          if pages == 2 and not reacted then
            -- a reaction from inside our own dialogue box: SELECT + DOWN
            game.input.state.select = true
            U.wait(2)
            U.shot(game, DIR .. "/2_select_held.png")
            U.tap(game, "down")
            U.wait(2)
            game.input.state.select = false
            reacted = true
            U.wait(10)
            U.shot(game, DIR .. "/2b_own_reaction.png")
          end
        end
        if CM.partner.emote and not sawPartnerReact then
          sawPartnerReact = true
          U.log("host sees the partner react: " .. tostring(CM.partner.emote) .. " / " .. tostring(CM.statusMessage))
          U.shot(game, DIR .. "/3_partner_reaction.png")
        end
        -- the host reads at its own pace, slower than the guest
        U.wait(50)
        U.tap(game, "a")
      end
      U.wait(2)
    end
    U.log("host scene over after " .. pages .. " pages")
    check(handover ~= nil, "the handover page came up: " .. tostring(handover))
    if not old then
      check(handover and handover:find("MOCHI got", 1, true) and not handover:find("TOBY", 1, true),
            "...naming MOCHI alone on MOCHI's screen")
    else
      check(handover and handover:find("TOBY", 1, true), "an old partner: the handover names both, as before")
    end
    check((save.inventory[ITEM] or 0) == had + 1, "MOCHI has the MYSTIC WATER")
    -- the partner's reply
    local gotLine
    for _ = 1, 60 * 20 do
      if CM.partner.emote and not sawPartnerReact then
        sawPartnerReact = true
        U.log("host sees the partner react: " .. tostring(CM.partner.emote) .. " / " .. tostring(CM.statusMessage))
        U.shot(game, DIR .. "/3_partner_reaction.png")
      end
      local s = CM.statusMessage
      if s and s:find("too!", 1, true) then gotLine = s break end
      U.wait(1)
    end
    U.wait(15)
    U.shot(game, DIR .. "/4_partner_got_one.png")
    U.wait(60 * 6)
    if not old then
      check(sawPartnerReact, "the partner's reaction showed over their avatar")
      check(gotLine == "TOBY got one too!", "the host reads \"TOBY got one too!\" (" .. tostring(gotLine) .. ")")
    else
      check(gotLine == nil, "an old partner sends no reply (" .. tostring(gotLine) .. ")")
    end
  else
    local ow = game.overworld
    -- the guest starts reading late: the host is two or three pages ahead
    -- (watching for the host's own reaction all along)
    local function watch(n)
      for _ = 1, n do
        if CM.partner.emote and not game.sawHostReact then
          game.sawHostReact = true
          U.log("guest sees the host react: " .. tostring(CM.partner.emote) .. " / " .. tostring(CM.statusMessage))
          U.wait(6)
          U.shot(game, DIR .. "/3b_host_reaction.png")
        end
        U.wait(1)
      end
    end
    local firstAt
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 30 do
      if CoopStory.feed[1] then firstAt = firstAt or love.timer.getTime() end
      if firstAt and love.timer.getTime() - firstAt > (old and 0.5 or 4) then break end
      watch(1)
    end
    check(CoopStory.feed[1] ~= nil, "the host's scene shows here")
    local function feedText()
      local p = CoopStory.feed[1]
      return p and (tostring(p[1]) .. " / " .. tostring(p[2])) or "-"
    end
    local all = {}
    for i, p in ipairs(CoopStory.feed) do all[i] = tostring(p[1]) .. (p.skipped and (" [fold " .. p.skipped .. "]") or "") end
    U.log("guest feed waiting: " .. #CoopStory.feed .. " page(s): " .. table.concat(all, " | "))
    U.shot(game, DIR .. "/1_feed_first.png")
    if old then
      -- a partner without story.duo: the page turns by itself, A is not taken
      local first = feedText()
      U.wait(60 * 3)
      check(feedText() ~= first, "old partner: the page turned by itself (" .. first .. " -> " .. feedText() .. ")")
    else
      local first = feedText()
      watch(60 * 3)
      check(feedText() == first, "the page waits for TOBY's A (" .. first .. ")")
      -- a reaction: SELECT + UP
      game.input.state.select = true
      U.wait(3)
      U.shot(game, DIR .. "/2_select_held.png")
      U.tap(game, "up")
      U.wait(2)
      game.input.state.select = false
      U.wait(8)
      U.shot(game, DIR .. "/2b_own_reaction.png")
      check(CM.localEmote == "exclaim", "TOBY reacted (WOW)")
      -- turn the pages with A
      local turned, sawFold = 0, false
      for _ = 1, 40 do
        if not CoopStory.feed[1] then break end
        local before = feedText()
        if before:find("Skipped", 1, true) then
          sawFold = true
          U.shot(game, DIR .. "/3_fold.png")
        end
        U.log("guest reads: " .. before)
        U.tap(game, "a")
        watch(30)
        if feedText() ~= before then turned = turned + 1 end
        -- wait for more of the scene while it is still going
        for _ = 1, 120 do
          if CoopStory.feed[1] or not CoopDuo.partnerScene then break end
          U.wait(1)
        end
      end
      check(turned >= 2, "TOBY turned " .. turned .. " page(s) with A")
      check(game.sawHostReact == true, "the host's reaction showed over MOCHI")
      check(ow.player and ow.player.cellX == 6 and ow.player.cellY == 12, "...and stayed put (A talked to nobody, SELECT+UP walked nowhere)")
      U.log("guest saw a fold: " .. tostring(sawFold))
    end
    -- the gift
    local box
    local t1 = love.timer.getTime()
    while love.timer.getTime() - t1 < 25 do
      local top = game.stack:top()
      if top and top.coopGift then box = top break end
      if old and CM.statusMessage and CM.statusMessage:find("too!", 1, true) then break end
      U.wait(1)
    end
    if old then
      U.wait(5)
      U.shot(game, DIR .. "/4_status_old.png")
      check(box == nil and CM.statusMessage and CM.statusMessage:find("You got MYSTIC WATER too!", 1, true),
            "old partner: \"You got MYSTIC WATER too!\" (" .. tostring(CM.statusMessage) .. ")")
    else
      check(box ~= nil, "a gift box opened on TOBY's screen")
      U.wait(70)
      U.shot(game, DIR .. "/4_gift_box.png")
      local txt = box and topText(box) or ""
      U.log("guest box: " .. txt)
      check(txt:find("TOBY received", 1, true) and txt:find("MYSTIC WATER", 1, true), "\"TOBY received MYSTIC WATER!\"")
      for _ = 1, 10 do
        if game.stack:top() ~= box then break end
        U.tap(game, "a")
        U.wait(20)
      end
      check(game.stack:top() == ow, "A closes it")
    end
    check((save.inventory[ITEM] or 0) == had + 1, "TOBY has the MYSTIC WATER too")
    U.wait(60 * 4)
  end
  U.shot(game, DIR .. "/5_end.png")
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
