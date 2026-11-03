-- CATCH UP with two real copies.  The host has three badges and its story
-- reached GOLDENROD; the guest has one and stands in VIOLET.  The guest opens
-- the co-op menu: CATCH UP is there (the host's menu has none), the box says
-- which two badges the host has and they lack, and asks "Meet MOCHI in
-- GOLDENROD CITY?".  YES asks the host, the host says YES, and the guest
-- flies to GOLDENROD -- with the one badge they had.
--
-- PKM_LANG=es puts the guest's copy in Spanish.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7816")
  local ROOT = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local DIR = ROOT .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  if role == "guest" and os.getenv("PKM_LANG") == "es" then require("src.coop.CoopI18n").forced = "es" end
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CM = require("src.coop.CoopManager")
  local CoopCatchUp = require("src.coop.CoopCatchUp")
  local Badges = require("src.inventory.Badges")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  for _, n in ipairs(role == "host" and { 157, 18, 65 } or { 160, 181, 130 }) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), role == "host" and 30 or 14)
    table.insert(save.party, m)
  end
  local order = (game.data.field or {}).flyOrder or {}
  U.log(role .. " flyOrder: " .. table.concat(order, ","):sub(1, 300))
  local function find(pat)
    for _, id in ipairs(order) do if id:find(pat) then return id end end
  end
  local NEWBARK, CHERRY, VIOLET, GOLDEN = find("NEW_BARK"), find("CHERRYGROVE"), find("VIOLET"), find("GOLDENROD")
  local AZALEA = find("AZALEA")
  check(NEWBARK and VIOLET and GOLDEN and AZALEA, "the towns are in this game's FLY list")
  save.visited = save.visited or {}
  save.flags = save.flags or {}
  local here
  if role == "host" then
    for _, id in ipairs({ NEWBARK, CHERRY, VIOLET, AZALEA, GOLDEN }) do save.visited[id] = true end
    for _, b in ipairs({ "ZEPHYRBADGE", "HIVEBADGE", "PLAINBADGE" }) do Badges.set(save, { id = b }, true) end
    here = GOLDEN
  else
    for _, id in ipairs({ NEWBARK, CHERRY, VIOLET }) do save.visited[id] = true end
    Badges.set(save, { id = "ZEPHYRBADGE" }, true)
    here = VIOLET
  end
  local w = game.data.field.flyWarps[here]
  U.teleport(game, here, w.x, w.y, "down")
  if role == "host" then
    check(CM.host(port), "hosting")
  else
    U.wait(60)
    check(CM.join("127.0.0.1", port), "joined")
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map and CM.partner.catchup then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, and the partner's story info arrived")
  U.wait(60)
  local function top() return game.stack:top() end
  local TextBoxMT, ChoiceMT = require("src.render.TextBox"), require("src.ui.ChoiceBox")
  local function isBox(t) return type(t) == "table" and getmetatable(t) == TextBoxMT end
  local function isChoice(t) return type(t) == "table" and getmetatable(t) == ChoiceMT end
  local function rowsLabels(menu)
    local t = {}
    for _, r in ipairs(menu:connectedRows(game.overworld)) do t[#t + 1] = r.label end
    return t
  end
  local CoopMenu = require("src.coop.CoopMenu")
  local I18n = require("src.coop.CoopI18n")
  local menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(10)
  local labels = rowsLabels(menu)
  local at
  for i, l in ipairs(labels) do if l == "CATCH UP" then at = i end end
  if role == "host" then
    check(at == nil, "the one ahead has no CATCH UP row")
    U.shot(game, DIR .. "/1_host_menu.png")
    while top() ~= game.overworld do U.tap(game, "b") U.wait(15) end
    -- the request arrives as a YES/NO box
    local asked = false
    for _ = 1, 60 * 30 do
      local t = top()
      if isChoice(t) or isBox(t) then asked = true break end
      U.wait(2)
    end
    check(asked, "the guest's request: a YES/NO box")
    for _ = 1, 10 * 30 do if isChoice(top()) then break end U.wait(2) end
    U.wait(30)
    U.shot(game, DIR .. "/2_host_asked.png")
    U.tap(game, "up") U.wait(10)
    U.tap(game, "a") U.wait(30)
    local told = false
    for _ = 1, 15 * 30 do
      if tostring(CM.statusMessage or ""):find("caught up") then told = true break end
      U.wait(2)
    end
    U.shot(game, DIR .. "/3_host_told.png")
    check(told, "the host is told the guest caught up")
    U.wait(240)
  else
    check(at ~= nil, "CATCH UP is offered to the one behind (" .. table.concat(labels, "|") .. ")")
    menu.index = at or 1
    U.wait(10)
    U.shot(game, DIR .. "/1_guest_menu_catchup.png")
    U.tap(game, "a")
    U.wait(30)
    check(isBox(top()), "the CATCH UP box")
    local shots = 2
    for i = 1, 6 do
      U.wait(60)
      U.shot(game, DIR .. ("/%d_guest_box.png"):format(shots))
      shots = shots + 1
      local t = top()
      if isChoice(t) or not isBox(t) then break end
      U.tap(game, "a")
    end
    U.wait(30)
    U.shot(game, DIR .. ("/%d_guest_question.png"):format(shots))
    U.tap(game, "up") U.wait(10)
    U.tap(game, "a") U.wait(20)
    local flew = false
    for _ = 1, 60 * 30 do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == GOLDEN then flew = true break end
      if isBox(top()) then U.tap(game, "a") U.wait(10) end
      U.wait(2)
    end
    U.wait(120)
    U.shot(game, DIR .. ("/%d_guest_landed.png"):format(shots + 1))
    check(flew, "flew to the host's key town " .. tostring(GOLDEN) .. " (now " ..
          tostring(game.overworld and game.overworld.map and game.overworld.map.id) .. ")")
    check(Badges.count(game.data, save) == 1, "still one badge: none handed out")
    check(CM.warpCooldownLeft() > 0, "the warp's cooldown runs")
    -- the row again: still behind, but the cooldown says when
    local again = CoopMenu.new(game)
    local okNow, why = CoopCatchUp.canCatchUp(game, game.overworld)
    check(not okNow, "no second trip at once (" .. tostring(why) .. ")")
    check(again ~= nil, "(menu builds after the trip)")
    U.wait(60)
  end
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
