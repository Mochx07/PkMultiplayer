-- A BEST-OF-3 P1-VS-P2 MATCH, two Gold copies (1.20, src/coop/CoopMatch.lua).
--
--   pair.sh <mod> vs_bo3.lua <port> gold <host> <guest> <out>
--
-- The host asks through the real co-op menu: PARTNER > BATTLE P1 VS P2 >
-- MATCH (switched to BEST OF 3) > LEVEL 50; the guest checks the invite
-- says BEST OF 3 GAMES and joins.  Both send one RATTATA.  Each game has a
-- planned winner -- it picks its strongest move, the other a move that does
-- no damage -- host, guest, host: 2-1.  Between games the score screen is
-- shot and read; the battles carry on without a new invite.  At the end each
-- copy checks the match, the three replays (one per game, a fresh seed
-- each) and plays game 2's back to its end, then the VS record (wins,
-- games, ELO) and its page in the menu; finally the two copies compare
-- what each wrote down (SHOT_DIR/<role>/summary.txt): they must agree.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local other = role == "host" and "guest" or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7790")
  local ROOT = os.getenv("SHOT_DIR") or "/tmp/vsbo3"
  local DIR = ROOT .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pipelines = require("src.render.Pipelines")
  for _, id in ipairs({ "voxel", "tiltshift" }) do pcall(Pipelines.setLevel, id, 0) end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopLink = require("src.coop.CoopLink")
  local CoopMatch = require("src.coop.CoopMatch")
  local CoopRecord = require("src.coop.CoopRecord")
  local CoopReplay = require("src.coop.CoopReplay")
  local CoopMenu = require("src.coop.CoopMenu")
  local save = U.freshSave(game)
  save.options = save.options or {}
  save.options.animations = false
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  table.insert(save.party, Pokemon.new(game.data, "SPECIES_019", 20))
  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")
  os.remove(DIR .. "/summary.txt")
  -- a clean record for these test identities: the numbers are exact
  pcall(love.filesystem.remove, CoopRecord.FILE)
  CoopRecord.forget()
  local replaysBefore = {}
  for _, n in ipairs(CoopReplay.list()) do replaysBefore[n] = true end

  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both on Route 29")
  U.wait(60)
  check(CoopManager.bothHave("vs.match"), "both copies have vs.match")
  local myId, partnerId = CoopManager.coopId(save), CoopManager.partner.id
  check(type(partnerId) == "string" and partnerId ~= myId, "the partner's coop id is known: " .. tostring(partnerId))

  -- the co-op menu, row by row: move the cursor down to `label`, A
  local menu
  local function rows() return menu:connectedRows(nil) end
  local function pick(label, shot)
    for _ = 1, 20 do
      local r = rows()[menu.index]
      if r and r.label == label then break end
      U.tap(game, "down")
      U.wait(3)
    end
    local r = rows()[menu.index]
    check(r and r.label == label, "menu row " .. label)
    if shot then U.shot(game, DIR .. "/" .. shot) end
    U.tap(game, "a")
    U.wait(6)
  end

  if role == "host" then
    menu = CoopMenu.new(game)
    game.stack:push(menu)
    U.wait(10)
    pick("PARTNER")
    pick("BATTLE P1 VS P2")
    pick("MATCH: 1 GAME")
    check(CoopMatch.wantBest == 3 and rows()[1].label == "MATCH: BEST OF 3", "A switched the match to BEST OF 3")
    pick("LEVEL 50", "vs_page.png")
    check(CoopLink.pending and CoopLink.pending.best == 3, "the invite went out for the best of 3")
  else
    for _ = 1, 60 * 20 do if CoopLink.asked then break end U.wait(1) end
    local asked = CoopLink.asked
    check(asked and asked.lines[3] == "LEVEL 50 RULES" and asked.lines[4] == "BEST OF 3 GAMES",
          "the invite says LEVEL 50 RULES, BEST OF 3 GAMES")
    U.wait(20)
    U.shot(game, DIR .. "/invite.png")
    U.wait(70)
    U.tap(game, "a")
  end

  -- host-side and guest-side HP, the same order on both copies
  local function ending(b)
    local host = role == "host" and b.playerParty or b.enemyParty
    local guest = role == "host" and b.enemyParty or b.playerParty
    if b.spectating then host, guest = b.playerParty, b.enemyParty end
    local o = {}
    for _, m in ipairs(host or {}) do o[#o + 1] = tostring(m.hp) end
    o[#o + 1] = "|"
    for _, m in ipairs(guest or {}) do o[#o + 1] = tostring(m.hp) end
    return table.concat(o, " ")
  end
  -- the planned winner of game g: host, guest, host
  local function iWin(g) return (g % 2 == 1) == (role == "host") end
  local function slotFor(b, win)
    local best, none
    for i, mv in ipairs(b.player and b.player.curMoves or {}) do
      local def = mv.id and game.data.moves[mv.id] or mv
      local pw = tonumber(def and def.power) or 0
      if not best or pw > best.pw then best = { i = i, pw = pw } end
      if pw == 0 and not none then none = i end
    end
    return win and (best and best.i or 1) or (none or 1)
  end

  -- the match, to its end
  local ls, m
  local games, shotNext, shotOver, lastWhere = {}, {}, false, nil
  local cur
  for _ = 1, 60 * 220 do
    local top = game.stack:top()
    -- the Cable Club under the battle (it is on top only between games)
    for _, st in ipairs(game.stack.states or {}) do
      if type(st) == "table" and st.coopMatch then ls, m = st, st.coopMatch end
    end
    local where = tostring(top and (top.stage or top.kind or top.phase))
    if where ~= lastWhere then U.log(role .. " top: " .. where) lastWhere = where end
    if top == game.overworld then
      if m and m.over then break end
      U.wait(1)
    elseif top and top.kind == "link" and not top.spectating then
      local g = m and m.game or 0
      if not cur or cur.b ~= top then
        cur = { b = top, game = g }
        games[g] = cur
      end
      cur.last = ending(top)
      cur.result = top.result
      if top.phase == "moveSelect" and not cur.shot then
        cur.shot = true
        U.shot(game, DIR .. "/game" .. g .. ".png")
      end
      if top.phase == "moveSelect" then
        top.moveIndex = slotFor(top, iWin(g))
        U.tap(game, "a")
        U.wait(4)
      else
        U.tap(game, "a")
        U.wait(6)
      end
    elseif top == ls and ls.stage == "matchNext" then
      if not shotNext[m.game] then
        shotNext[m.game] = true
        U.wait(10)
        U.shot(game, DIR .. "/score" .. m.game .. ".png")
        U.log(role .. ": after game " .. m.game .. " " .. CoopMatch.myWins(m) .. "-" .. CoopMatch.theirWins(m))
      end
      U.wait(1) -- it goes on by itself
    elseif top == ls and ls.stage == "matchOver" then
      if not shotOver then
        shotOver = true
        U.wait(10)
        U.shot(game, DIR .. "/final.png")
        U.log(role .. ": match over " .. CoopMatch.myWins(m) .. "-" .. CoopMatch.theirWins(m))
      end
      U.wait(1) -- and closes by itself
    elseif top == ls then
      U.wait(1)
    else
      U.tap(game, "a")
      U.wait(6)
    end
  end
  check(m ~= nil and m.over, "the match ended")
  check(game.stack:top() == game.overworld, "back in the overworld")
  if not m then love.event.quit(1) return end
  for g = 1, 3 do
    local gm = games[g]
    U.log(role .. ": game " .. g .. " ended '" .. tostring(gm and gm.last) .. "' " .. tostring(gm and gm.result))
    check(gm and gm.result == (iWin(g) and "win" or "lose"), "game " .. g .. ": " .. (iWin(g) and "won" or "lost") .. " as planned")
  end
  check(shotNext[1] and shotNext[2] and shotOver, "the score showed after games 1 and 2 and at the end")
  local mine, theirs = CoopMatch.myWins(m), CoopMatch.theirWins(m)
  check(m.winner == "asker" and mine == (role == "host" and 2 or 1) and theirs == (role == "host" and 1 or 2),
        "the asker (host) won 2-1: " .. mine .. "-" .. theirs)

  -- the replays: one per game
  CoopReplay.forget()
  local new = {}
  for _, n in ipairs(CoopReplay.list()) do
    if not replaysBefore[n] then new[#new + 1] = n end
  end
  check(#new == 3, "three new replays (" .. #new .. ")")
  local byGame, seeds = {}, {}
  for _, n in ipairs(new) do
    local r = CoopReplay.load(n)
    if r and r.best == 3 and r.game then byGame[r.game] = n seeds[r.game] = r.seed end
  end
  check(byGame[1] and byGame[2] and byGame[3], "...games 1, 2 and 3 of the best of 3")
  check(seeds[1] ~= seeds[2] and seeds[2] ~= seeds[3] and seeds[1] ~= seeds[3],
        "a new seed each game: " .. tostring(seeds[1]) .. " " .. tostring(seeds[2]) .. " " .. tostring(seeds[3]))
  if byGame[2] then
    check(CoopReplay.play(game, byGame[2]), "game 2's replay starts")
    local spec, specEnd
    for _ = 1, 60 * 60 do
      local top = game.stack:top()
      if top and top.spectating then spec = top specEnd = ending(top) end
      if spec and top == game.overworld then break end
      if top ~= game.overworld then U.tap(game, "a") U.wait(6) else U.wait(1) end
    end
    U.log(role .. ": replay of game 2 ended '" .. tostring(specEnd) .. "'")
    check(spec and specEnd == (games[2] and games[2].last), "game 2's replay ends exactly like game 2 did")
  end

  -- the record
  CoopRecord.forget()
  local rec = CoopRecord.against(myId, partnerId)
  local f = rec and rec.formats and rec.formats.lv50
  if role == "host" then
    check(f and f.w == 1 and f.l == 0 and f.gw == 2 and f.gl == 1 and f.elo == 1016 and f.theirElo == 984,
          "record: LEVEL 50 won 1, games 2-1, ELO 1016 vs 984")
  else
    check(f and f.w == 0 and f.l == 1 and f.gw == 1 and f.gl == 2 and f.elo == 984 and f.theirElo == 1016,
          "record: LEVEL 50 lost 1, games 1-2, ELO 984 vs 1016")
  end
  check(rec and rec.name == (role == "host" and "TOBY" or "MOCHI"), "...under the partner's name")

  -- ...and in the menu: VS > RECORD
  menu = CoopMenu.new(game)
  game.stack:push(menu)
  U.wait(10)
  pick("PARTNER")
  pick("BATTLE P1 VS P2")
  pick("RECORD")
  check(menu.page == "record" and rows()[1] and rows()[1].label == "LEVEL 50", "VS > RECORD lists LEVEL 50")
  U.wait(10)
  U.shot(game, DIR .. "/record.png")
  for _ = 1, 4 do U.tap(game, "b") U.wait(6) end

  -- the two copies compare notes
  local line = string.format("winner=%s score=%d-%d elo=%s/%s g1=%s g2=%s g3=%s",
    tostring(m.winner), role == "host" and mine or theirs, role == "host" and theirs or mine,
    tostring(f and (role == "host" and f.elo or f.theirElo)), tostring(f and (role == "host" and f.theirElo or f.elo)),
    tostring(games[1] and games[1].last), tostring(games[2] and games[2].last), tostring(games[3] and games[3].last))
  local fh = io.open(DIR .. "/summary.txt", "w")
  if fh then fh:write(line) fh:close() end
  local theirsLine
  for _ = 1, 60 * 40 do
    local fo = io.open(ROOT .. "/" .. other .. "/summary.txt", "r")
    if fo then theirsLine = fo:read("*a") fo:close() end
    if theirsLine and theirsLine ~= "" then break end
    U.wait(1)
  end
  U.log(role .. ": summary " .. line)
  check(theirsLine == line, "both copies agree on the match: " .. tostring(theirsLine))

  U.log(role .. " done: " .. fails .. " failures")
  U.wait(30)
  love.event.quit(fails == 0 and 0 or 1)
end
