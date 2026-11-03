-- A BIG BATTLE'S ANSWER WHILE THE HOST PICKS THEIR THREE.  Host and guest in
-- WILL's room; the host talks to WILL, says CO-OP, reads through his speech
-- and opens the team picker.  While it is up, the guest:
--
--   PKM_MODE=late   ...only now confirms their own three (coop_bigbattle_ready).
--                   Before the fix the host's copy had already taken the
--                   invite down: it answered with a cancel ("MOCHI went
--                   solo"), then sat 60s in WAITING for a ready it had thrown
--                   away, and fought solo.  Now: the co-op double starts.
--   PKM_MODE=leave  ...presses B in READ ALONG (coop_battle_decline).  Before
--                   the fix the decline was dropped and the host's double
--                   started with the guest's three played by the AI, the
--                   guest never in it.  Now: the host battles solo at once.
--
-- The two copies pace each other through files in SHOT_DIR (use a fresh
-- output folder for every run).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7812")
  local MODE = os.getenv("PKM_MODE") or "late"
  local ROOT = os.getenv("SHOT_DIR") or "/tmp/pkm"
  local DIR = ROOT .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. " [" .. MODE .. "]: " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function mark(name)
    os.execute("mkdir -p '" .. ROOT .. "'")
    local f = io.open(ROOT .. "/sync_" .. name, "w")
    if f then f:write("1") f:close() end
  end
  local function marked(name)
    local f = io.open(ROOT .. "/sync_" .. name, "r")
    if f then f:close() return true end
    return false
  end
  local function waitMark(name, secs)
    for _ = 1, secs * 60 do
      if marked(name) then return true end
      U.wait(1)
    end
    return false
  end
  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CM = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  for _, n in ipairs(role == "host" and { 157, 18, 65 } or { 160, 181, 130 }) do
    local m = Pokemon.new(game.data, ("SPECIES_%03d"):format(n), 70)
    m.moves = { { id = "TACKLE", pp = 35 } }
    table.insert(save.party, m)
  end
  save.g2Scenes = save.g2Scenes or {}
  save.g2Scenes.WILLS_ROOM = 1
  if role == "host" then
    U.teleport(game, "WILLS_ROOM", 5, 8, "up")
    check(CM.host(port), "hosting")
  else
    U.teleport(game, "WILLS_ROOM", 5, 13, "up")
    U.wait(60)
    check(CM.join("127.0.0.1", port), "joined")
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CM.isConnected() and CM.partner.map == "WILLS_ROOM" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both in WILL's room")
  U.wait(90)
  local function top() return game.stack:top() end
  local function battleTop()
    local t = top()
    if t and (t.kind == "trainer" or t.coopDouble or t.isCoopGuest) then return t end
    return nil
  end
  local function waitModal()
    for _, s in ipairs(game.stack.states or {}) do if s.isCoopWaitModal then return s end end
    return nil
  end
  local function menuLabels(s)
    if type(s) ~= "table" then return nil end
    for _, v in pairs(s) do
      if type(v) == "table" and type(v[1]) == "table" and v[1].label then
        local t = {}
        for _, it in ipairs(v) do t[#t + 1] = tostring(it.label) end
        return table.concat(t, "/")
      end
    end
  end

  if role == "host" then
    U.tap(game, "a")
    local asked = false
    for _ = 1, 8 * 30 do
      local l = menuLabels(top())
      if l and l:find("CO%-OP") then asked = true break end
      U.wait(2)
    end
    check(asked, "WILL: CO-OP / SOLO asked")
    U.shot(game, DIR .. "/1_host_coop_solo.png")
    U.tap(game, "a")   -- CO-OP
    -- through WILL's speech, up to the team picker
    local picker = false
    for _ = 1, 40 * 30 do
      local t = top()
      if t and t.isCoopBattleSelect then picker = true break end
      if t ~= game.overworld then U.tap(game, "a") U.wait(12) else U.wait(2) end
    end
    check(picker, "the host's team picker is up")
    U.shot(game, DIR .. "/2_host_picker.png")
    mark("host_select")
    local word = MODE == "late" and "guest_ready" or "guest_left"
    check(waitMark(word, 40), "the guest's answer came while the picker is up (" .. word .. ")")
    U.wait(60)
    U.shot(game, DIR .. "/3_host_picker_after_answer.png")
    U.tap(game, "start")
    local started, sawWait
    for _ = 1, 15 * 30 do
      if waitModal() then sawWait = true end
      started = battleTop()
      if started then break end
      U.wait(2)
    end
    U.wait(30)
    U.shot(game, DIR .. "/4_host_after_pick.png")
    check(started ~= nil, "the battle starts within a few seconds of the pick")
    check(not sawWait, "no WAITING box for an answer already given")
    if MODE == "late" then
      check(started and started.coopDouble == true, "a co-op double with the guest")
    else
      check(started and not started.coopDouble, "solo: no double with an absent partner's team")
    end
    mark("host_done")
  else
    local invited = false
    for _ = 1, 30 * 30 do
      if CM.activeInviteModal then invited = true break end
      U.wait(2)
    end
    check(invited, "the big-battle invite arrives")
    U.wait(70)
    U.shot(game, DIR .. "/1_guest_invite.png")
    for _ = 1, 3 do U.tap(game, "a") U.wait(40) end
    if MODE == "late" then
      -- three picked; hold the confirm until the host is in their picker
      check(waitMark("host_select", 60), "the host reached their picker first")
      U.shot(game, DIR .. "/2_guest_picker_late.png")
      U.tap(game, "start")
      U.wait(10)
      mark("guest_ready")
      local inBattle, kicked
      for _ = 1, 25 * 30 do
        local t = top()
        if t and t.isCoopGuest then inBattle = true break end
        if CM.statusMessage and tostring(CM.statusMessage):find("went solo") then kicked = true end
        U.wait(2)
      end
      U.wait(30)
      U.shot(game, DIR .. "/3_guest_after.png")
      check(not kicked, "the guest is not told the host went solo")
      check(inBattle, "the guest is in the co-op double")
    else
      U.tap(game, "start")
      U.wait(20)
      check(waitModal() ~= nil, "READ ALONG: the guest's three are in, waiting for the battle")
      check(waitMark("host_select", 60), "the host reached their picker")
      U.shot(game, DIR .. "/2_guest_read_along.png")
      U.tap(game, "b")
      U.wait(20)
      check(waitModal() == nil, "B: the guest left the battle")
      mark("guest_left")
      local pulled = false
      for _ = 1, 15 * 30 do
        local t = top()
        if t and t.isCoopGuest then pulled = true end
        U.wait(2)
        if marked("host_done") then break end
      end
      U.wait(30)
      U.shot(game, DIR .. "/3_guest_after.png")
      check(not pulled, "the guest is not pulled into a battle they left")
    end
  end
  U.wait(60)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
