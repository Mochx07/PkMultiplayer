-- Screen fixtures rendered by two real Red games, followed by a real rival
-- invitation/team-selection flow. Every mod action uses LOVE touch events.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local T, CM = require("src.coop.CoopTouch"), require("src.coop.CoopManager")
  local I, Net = require("src.coop.CoopI18n"), require("src.coop.CoopNet")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7942")
  local dir = assert(os.getenv("SHOT_DIR"))
  local fails, serial = 0, 0
  local function check(ok, message)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. message)
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
    serial = serial + 1 point(x,y,"touchpressed",serial) U.wait(1)
    point(x,y,"touchreleased",serial) U.wait(3)
  end
  local function tap(id)
    local s = CM.chatOverlay or game.stack:top()
    for _, r in ipairs(s and s.touchKind and T.targets(s) or {}) do
      if r.id == id then tapXY(r.x + r.w/2, r.y + r.h/2) return true end
    end
    check(false, "missing touch target " .. id) return false
  end
  local function drag(x, y, toY)
    serial = serial + 1 point(x,y,"touchpressed",serial)
    point(x,toY,"touchmoved",serial) U.wait(1)
    point(x,toY,"touchreleased",serial) U.wait(3)
  end
  local function shot(name)
    U.wait(3) check(U.shot(game,dir.."/"..role.."/"..name..".png"), "screenshot "..name)
  end
  local function text(value)
    for ch in value:gmatch(".") do tap(ch == " " and "space" or "key:" .. ch) end
  end
  local function write(name, value)
    local f = assert(io.open(dir .. "/" .. name, "w")) f:write(value or "ok") f:close()
  end
  local function exists(name)
    local f = io.open(dir.."/"..name,"r") if f then f:close() return true end return false
  end
  local save = U.freshSave(game)
  save.player.name, save.player.rival = role == "host" and "MOCHI" or "TOBY", "GARY"
  save.flags = save.flags or {} save.flags.EVENT_CHOSE_SQUIRTLE = true
  local Pokemon = require("src.pokemon.Pokemon")
  for _, species in ipairs({"PIKACHU","BULBASAUR","PIDGEY","RATTATA","SQUIRTLE","CHARMANDER"}) do
    table.insert(save.party, Pokemon.new(game.data,species,20))
  end
  U.teleport(game,"PALLET_TOWN",role == "host" and 5 or 8,8,"down")
  I.forced = os.getenv("CODEX_TOUCH_LANG") or "es"
  love.window.setMode(role == "host" and 1000 or 510, role == "host" and 610 or 730)
  U.wait(20)
  tapXY(140,138) tap("back")
  -- The real name screen and role page; no physical keyboard.
  Net.DEFAULT_PORT = port
  local started = false
  local lobby = require("src.coop.CoopNewGame").new(game,function() started = true end,"new")
  lobby.nameEdit = {buf = "",pos = 1}
  game.stack:push(lobby) text("TOUCH7") shot("01_name_keyboard") tap("ok")
  check(lobby.name == "TOUCH7" and lobby.stage == "role", "touch name confirmed")
  shot("02_role")
  if role == "host" then
    tap("role:1") shot("02a_lobby_host")
    tap("addresses") shot("02b_lobby_host_address")
    local addresses = Net.addresses()
    local a = addresses[((lobby.addrPick or 0) % math.max(1,#addresses)) + 1] or {ip = Net.lanIP()}
    write("invite.txt",assert(Net.inviteCode(a.ip,port)))
  else
    tap("role:2") shot("02a_lobby_ip") tap("code")
    check(waitFor(function() return exists("invite.txt") end),"host lobby invite available")
    local f = assert(io.open(dir.."/invite.txt","r")) local code=f:read("*a") f:close()
    text(code) shot("02b_lobby_code") tap("ok")
  end
  check(waitFor(function() return lobby.stage == "confirm" end),"two real touch lobbies linked")
  shot("02c_lobby_ready") write(role.."-confirm")
  check(waitFor(function() return exists((role == "host" and "guest" or "host").."-confirm") end),"both lobbies at READY")
  tap("ready")
  check(waitFor(function() return started end),"both touch READY prompts launch the session")
  check(game.stack:top() == game.overworld,"lobby completion returns to field")
  -- These are the shared tower/contest modal classes. Red has no Crystal
  -- tower or Johto contest, so their UI is exercised as explicit fixtures.
  for _, mode in ipairs({"tower","contest"}) do
    local picked
    local modal = require("src.coop.CoopBattleInviteModal").new(game,"PARTNER",mode == "tower" and "TRAINER" or "MAGIKARP",function() picked = true end,function() picked = false end)
    game.stack:push(modal) U.wait(65) shot("03_"..mode.."_invite") tap("answer:1")
    check(picked == true, mode .. " prompt accepts by touch")
    local wait = require("src.coop.CoopWaitModal").new(game,"PARTNER",function() end,30,{compact = mode == "contest"})
    game.stack:push(wait) U.wait(35) shot("04_"..mode.."_wait") tap("back")
    check(wait.done, mode .. " waiting prompt cancels by touch")
  end
  -- Touchable translated text boxes and their generated YES/NO menus.
  local done = false
  local box = I.textBox().new(game,"PARTNER NOT READY",function() done = true end)
  game.stack:push(box) U.wait(100) shot("05_text_prompt")
  for _ = 1, 8 do if game.stack:top() ~= box then break end tap("ok") U.wait(12) end
  check(done, "mod text prompt advanced by touch")
  -- A deliberately long shared menu verifies a moving visible window,
  -- rather than merely moving the cursor in a short RULES page.
  local rows, pickedRow = {}, nil
  for n = 1, 14 do
    rows[n] = {label = I.t("CO-OP") .. " " .. n, onSelect = function() pickedRow = n end}
  end
  local long = I.menu().new(game,rows,{tx=2,ty=2,tw=16,th=12,maxVisible=5})
  game.stack:push(long) shot("05a_long_list_top") drag(70,110,42)
  check(long.scroll > 0,"drag changes long list's visible window")
  shot("05b_long_list_scroll") tap("row:" .. long.index)
  check(pickedRow == 7,"scrolled row selects and confirms by touch")
  -- Use the real VS scoreboard and exit callbacks with an isolated transport.
  local Match = require("src.coop.CoopMatch")
  local ls = require("src.link.LinkState").new(game)
  ls.net = {inbox={},paired=true,closed=false,update=function() end,close=function() end}
  local match = Match.new({best=3,asker=role == "host",myName=save.player.name,theirName=CM.partner.name})
  match.game, match.wins, match.winner, match.timer, match.over = 3,{asker=2,asked=1},"asker",1.2,true
  ls.stage = "matchOver" Match.attach(ls,match) T.attach(ls,"link")
  game.stack:push(ls) shot("05c_vs_result") tap("ok")
  check(game.stack:top() == game.overworld,"VS result dismissed by touch")
  tapXY(140,138)
  local m = game.stack:top()
  local function row(label)
    local rows = CM.isConnected() and m:connectedRows(game.overworld) or m:offlineRows()
    for n,r in ipairs(rows) do if r.label == label then
      for _ = 1,12 do
        for _,target in ipairs(T.targets(m)) do if target.id == "row:"..n then tap(target.id) return true end end
        drag(70,112,62)
      end
    end end
    check(false,"missing row "..label) return false
  end
  -- Render every connected page, enter by tapping its real row, go back
  -- by tapping BACK. RULES has more rows than the screen and is dragged.
  shot("06_connected")
  row("PARTNER") shot("07_partner")
  row("BATTLE P1 VS P2") shot("08_vs")
  row("RECORD") shot("09_record") tap("back")
  row("REPLAYS") shot("10_replays") tap("back") tap("back")
  row("MINIGAMES") shot("11_minigames") tap("back") tap("back")
  row("RULES") shot("12_rules_top")
  local before = m.index drag(70,110,55)
  check(m.index > before, "rules cursor moves by dragging") shot("13_rules_scroll") tap("back")
  row("VERSION") shot("14_diagnostics") tap("back")
  row("POKéDEX") shot("15_dex") tap("swap") shot("16_dex_swap") tap("back")
  row("RULES") row("SOUL LINKS") shot("17_souls") tap("back") tap("back")
  row("PARTNER")
  row("WATCH " .. tostring(CM.partner.name):upper():sub(1,7))
  U.wait(20) shot("18_watch") tap("back") tap("back") tap("back")
  -- An isolated catch ownership fixture uses the actual menu factory and
  -- message action, without granting a Pokemon or fabricating a wild battle.
  local catch = {game = game, coop = {turn = 1, seed = 42},
    coopCaught = {target = {name = "PIKACHU"}}, say = function() end}
  require("src.coop.CoopCatch").askKeeper(catch)
  shot("19_keeper") tap("row:2")
  check(catch.coopKeep.mine == "partner", "keeper row selected and confirmed")
  write(role.."-gallery")
  check(waitFor(function() return exists((role == "host" and "guest" or "host").."-gallery") end), "both screen galleries complete")
  U.wait(60)
  if role == "host" then game.overworld.runner:run({{"rival_battle","OPP_RIVAL1",4}},{mapId="PALLET_TOWN"}) end
  local battle, seenInvite, seenTeam, seenMode
  check(waitFor(function()
    local s = game.stack:top()
    if s.isCoopInvite then
      if not seenInvite then U.wait(65) shot("20_real_rival_invite") seenInvite = true end
      tap("answer:1")
    elseif s.isCoopBattleSelect then
      if not seenTeam then
        tap("mon:3") tap("mon:4") shot("21_real_team") seenTeam = true
      end
      tap("confirm")
    elseif s.touchKind == "list" then
      if not seenMode then shot("20_real_battle_mode") seenMode = true end
      tap("row:1")
    elseif s.isCoopWaitModal then
      if not exists(role.."-wait") then shot("22_real_wait") write(role.."-wait") end
    elseif s.coopDouble and s.phase then battle=s return true end
    return false
  end,2400),"real rival co-op battle entered with touch only")
  check(seenTeam,"real team selection driven by touch")
  if role == "guest" then check(seenInvite,"real rival invite answered by touch") end
  U.wait(120)
  shot("23_real_coop_battle")
  -- SELECT belongs to the engine virtual pad. Direct screen chat keyboard
  -- routing is covered separately without making a physical key event.
  U.wait(120)
  U.log(role.." done: "..fails.." failures")
  -- All captures and assertions have finished. Headless drivers exit here
  -- instead of waiting for optional audio/Discord workers during shutdown.
  io.stdout:flush()
  os.exit(fails == 0 and 0 or 1)
end
