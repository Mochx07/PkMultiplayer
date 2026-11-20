-- Two real Red copies. All mod navigation is through LOVE touch events.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local T = require("src.coop.CoopTouch")
  local CM = require("src.coop.CoopManager")
  local Net = require("src.coop.CoopNet")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7940")
  local dir = assert(os.getenv("SHOT_DIR"))
  local fails, serial = 0, 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function waitFor(fn, frames)
    for _ = 1, frames or 1800 do if fn() then return true end U.wait(1) end
    return false
  end
  local function point(x, y, method, id)
    local p = game.renderer.uiPresentation
    love[method](id, p.x + x * p.scaleX, p.y + y * p.scaleY, 0, 0, 1)
  end
  local function tapXY(x, y)
    serial = serial + 1
    point(x, y, "touchpressed", serial) U.wait(1)
    point(x, y, "touchreleased", serial) U.wait(3)
  end
  local function tap(id)
    local s = CM.chatOverlay or game.stack:top()
    for _, r in ipairs(s and s.touchKind and T.targets(s) or {}) do
      if r.id == id then tapXY(r.x + r.w / 2, r.y + r.h / 2) return true end
    end
    check(false, "missing target " .. id .. " in " .. tostring(s and s.stage))
    return false
  end
  local function shot(name)
    U.wait(3)
    check(U.shot(game, dir .. "/" .. role .. "/" .. name .. ".png"), "screenshot " .. name)
  end
  local function open() tapXY(140, 138) U.wait(3) return game.stack:top() end
  local function row(label)
    local s = game.stack:top()
    if label == "READY" then label = require("src.coop.CoopI18n").t("READY") end
    local rows = CM.isConnected() and s:connectedRows(game.overworld) or s:offlineRows()
    for n, r in ipairs(rows) do
      if r.label == label or ((label == "CHAT" or label == "EMOTE" or label == require("src.coop.CoopI18n").t("READY") or label == "PORT ") and r.label:find(label, 1, true) == 1) then
        -- Drag the visible list until this row is exposed.
        for _ = 1, 12 do
          for _, target in ipairs(T.targets(s)) do if target.id == "row:" .. n then return tap(target.id) end end
          serial = serial + 1
          point(70, 110, "touchpressed", serial)
          point(70, 60, "touchmoved", serial)
          point(70, 60, "touchreleased", serial) U.wait(3)
        end
      end
    end
    check(false, "missing menu row " .. label)
  end
  local function typeText(text)
    for ch in text:gmatch(".") do tap(ch == " " and "space" or "key:" .. ch) end
  end
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  local Pokemon = require("src.pokemon.Pokemon")
  for _, sp in ipairs({"PIKACHU", "BULBASAUR", "PIDGEY"}) do
    table.insert(save.party, Pokemon.new(game.data, sp, 20))
  end
  U.teleport(game, "PALLET_TOWN", role == "host" and 5 or 8, 8, "down")
  -- Different letterboxes; a second run can choose Spanish through the env.
  love.window.setMode(role == "host" and 960 or 540, role == "host" and 540 or 690)
  require("src.coop.CoopI18n").forced = os.getenv("CODEX_TOUCH_LANG") or "en"
  if os.getenv("CODEX_TOUCH_PAD") == "1" then
    local pad = require("src.core.TouchControls")
    pad:setPreview(true) pad.active, pad.enabled = true, true
    check(pad:visible(), "real engine virtual touch controls enabled")
  end
  U.wait(30)
  shot("00_field")
  local m = open()
  check(m.touchKind == "menu", "touch opens co-op menu from field")
  shot("01_menu_offline")
  if role == "host" then
    row("PORT ")
    shot("02_port")
    local digits = ("%05d"):format(port)
    for n = 1, 5 do
      tap("digit:" .. n)
      for _ = 1, (tonumber(digits:sub(n,n)) - m.portEdit[n]) % 10 do tap("up") end
    end
    tap("ok")
    check(m.port == port, "port entered by touch")
    row("HOST")
    check(m.stage == "hosting", "HOST tapped")
    tap("addresses")
    shot("03_host_code")
    local addresses = Net.addresses()
    local pick = addresses[((m.addrPick or 0) % math.max(1, #addresses)) + 1]
      or { ip = Net.lanIP() }
    local code = assert(Net.inviteCode(pick.ip, port))
    local f = assert(io.open(dir .. "/invite.txt", "w")) f:write(code) f:close()
    U.log(role .. ": displayed invite " .. code)
  else
    row("JOIN") shot("02_join_list")
    local rows = m:joinRows()
    for n, r in ipairs(rows) do if r.label == "TYPE THE IP" then tap("row:" .. n) break end end
    shot("02a_address_entry") tap("digit:12") tap("up") tap("down") tap("back")
    for n, r in ipairs(rows) do if r.label == "TYPE A CODE" then tap("row:" .. n) break end end
    check(m.stage == "codeEntry", "code keyboard opened by touch")
    tap("ok")
    check(m.errorMsg == "WRONG CODE", "empty code rejected")
    local code
    check(waitFor(function()
      local f = io.open(dir .. "/invite.txt", "r")
      if f then code = f:read("*a") f:close() end
      return code and #code > 0
    end), "read host's displayed invite")
    if not code then love.event.quit(1) return end
    typeText(code)
    check(m.code == code, "invite typed only on on-screen keyboard")
    shot("03_join_keyboard") tap("ok")
  end
  check(waitFor(function() return CM.isConnected() end), "two real copies linked")
  U.wait(90)
  shot("04_menu_linked")
  if game.stack:top().touchKind == "menu" then tap("back") end
  open() row("CHAT")
  check(game.stack:top().isChatBox, "CHAT tapped")
  typeText(role == "host" and "TOUCH HOST" or "TOUCH GUEST")
  shot("05_chat_keyboard") tap("ok")
  check(waitFor(function()
    for _, line in ipairs(CM.chatLog or {}) do
      if line.text == (role == "host" and "TOUCH GUEST" or "TOUCH HOST") then return true end
    end
  end), "received partner's touch-typed chat")
  shot("06_chat_received") tap("back")
  open() row("EMOTE") shot("07_emotes") tap("emote:3")
  check(CM.localEmote ~= nil, "emote picked by touch")
  if os.getenv("CODEX_TOUCH_EMOTE_BACK") == "1" then
    open() row("EMOTE") shot("07b_emote_back") tap("back")
    check(game.stack:top() == game.overworld, "emote BACK cancels by touch below number labels")
    U.log(role .. " done: " .. fails .. " failures")
    io.stdout:flush() os.exit(fails == 0 and 0 or 1)
  end
  open() row("READY")
  check(CM.localReady == true, "READY toggled by touch")
  shot("08_ready") tap("back")
  -- Synchronize via the chat message already sent by touch. Wait for both
  -- ready flags before one side sends the actual VS invitation.
  check(waitFor(function() return CM.partner.ready == true end), "partner READY received")
  U.wait(role == "host" and 90 or 1)
  if role == "host" then
    open() row("PARTNER") shot("09_partner")
    row("BATTLE P1 VS P2") shot("10_vs")
    row("FREE BATTLE") shot("11_wait")
  else
    check(waitFor(function() return game.stack:top().isCoopInvite end), "real battle invite received")
    U.wait(65) shot("09_battle_invite") tap("answer:1")
  end
  local battle
  check(waitFor(function()
    local s = game.stack:top()
    if s.touchKind == "link" and s.stage == "battleOptions" then tap("ok") end
    if s.phase and s.chooseAction then battle = s return true end
    return false
  end, 2400), "touch invitation acceptance starts real VS battle")
  U.wait(120)
  shot("12_vs_battle")
  check(#(game.input.pressQueue or {}) == 0, "no synthetic key queue used")
  U.wait(120)
  U.log(role .. " done: " .. fails .. " failures")
  -- All captures and assertions have finished. Headless drivers exit here
  -- instead of waiting for optional audio/Discord workers during shutdown.
  io.stdout:flush()
  os.exit(fails == 0 and 0 or 1)
end
