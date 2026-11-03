-- SIX QA: Adversarial testing of ONE TYPE, LEVEL 100, FREE BATTLE,
-- rule refusals (0 legal mons on host and guest), and Spanish (i18n).
--
--   pair.sh <mod> six_rules_adversarial.lua 7816 gold PkMp15B PkMpBigB <out>
--
return function(game)
  local U = dofile("tests/drivers/util.lua")
  pcall(function() io.stdout:setvbuf("no") end)
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7816")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/six_rules") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end

  U.wait(5)
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local CoopLink = require("src.coop.CoopLink")
  local CoopVS = require("src.coop.CoopVS")
  local CoopMenu = require("src.coop.CoopMenu")
  local I18n = require("src.coop.CoopI18n")

  -- Force Spanish to test i18n in real UI
  I18n.forced = "es"

  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"

  -- Host party:
  -- 1. PIDGEY (Level 12, Normal/Flying)
  -- 2. CHARMANDER (Level 10, Fire)
  -- 3. SNORLAX (Level 35, Normal)
  -- 4. LUGIA (Level 60, Legend)
  -- 5. PIDGEY (Level 15, dup)
  --
  -- Guest party:
  -- 1. RATTATA (Level 8, Normal)
  -- 2. SENTRET (Level 10, Normal)
  if role == "host" then
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 12)) -- PIDGEY
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_004", 10)) -- CHARMANDER
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_143", 35)) -- SNORLAX
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_249", 60)) -- LUGIA
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_016", 15)) -- PIDGEY
  else
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_019", 8))  -- RATTATA
    table.insert(save.party, Pokemon.new(game.data, "SPECIES_161", 10)) -- SENTRET
  end

  U.teleport(game, "ROUTE29", role == "host" and 10 or 12, 8, "down")

  -- 1. Unit/Adversarial checks of party filtration
  -- ONE TYPE: lead is Pidgey (Normal/Flying). Snorlax is Normal -> kept. Charmander is Fire -> filtered. Lugia -> banned. Dup Pidgey -> dup.
  local monoK, monoL = CoopVS.legalParty(game.data, save.party, CoopVS.FORMATS.mono)
  if role == "host" then
    check(#monoK == 2 and monoK[1].species == "SPECIES_016" and monoK[2].species == "SPECIES_143",
          "ONE TYPE keeps Pidgey & Snorlax (shares Normal)")
    check(#monoL == 3, "ONE TYPE filters Charmander, Lugia, and duplicate Pidgey")
  end

  -- LEVEL 100: keeps Pidgey, Charmander, Snorlax
  local lv100K, lv100L = CoopVS.legalParty(game.data, save.party, CoopVS.FORMATS.lv100)
  if role == "host" then
    check(#lv100K == 3, "LEVEL 100 keeps Pidgey, Charmander, Snorlax")
    check(lv100K[1].species == "SPECIES_016" and lv100K[2].species == "SPECIES_004" and lv100K[3].species == "SPECIES_143",
          "LEVEL 100 party order preserved")
  end

  -- FREE BATTLE: keeps all 5
  local freeK, freeL = CoopVS.legalParty(game.data, save.party, CoopVS.FORMATS.free)
  if role == "host" then
    check(#freeK == 5 and #freeL == 0, "FREE BATTLE keeps entire party including legends and dups")
  end

  -- Zero legal mons test:
  local illegalTeam = { Pokemon.new(game.data, "SPECIES_249", 60) } -- Only Lugia
  local _, _, err = CoopVS.legalParty(game.data, illegalTeam, CoopVS.FORMATS.lv50)
  check(err == "Your team breaks the rules", "illegal party returns rules error: " .. tostring(err))

  -- Link up
  if role == "host" then
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "joining 127.0.0.1:" .. port)
  end

  local linked = false
  for _ = 1, 60 * 30 do
    if CoopManager.isConnected() and CoopManager.partner.map == "ROUTE29" then linked = true break end
    U.wait(1)
  end
  check(linked, "linked on Route 29")
  U.wait(60)

  -- 2. Test Spanish VS menu rendering
  if role == "host" then
    local menu = CoopMenu.new(game)
    game.stack:push(menu)
    U.wait(10)
    menu:openPage("vs")
    U.wait(10)
    local rows = menu:connectedRows(game.overworld, "vs")
    -- 1.20 after best of 3: MATCH, 5 formats, RECORD, REPLAYS; found by label
    local byLabel = {}
    for _, r in ipairs(rows) do byLabel[r.label] = r end
    check(#rows == 8, "VS menu has 8 rows (MATCH + 5 formats + RECORD + REPLAYS): " .. #rows)
    local want = { { "FREE BATTLE", "^COMBATE LIBRE$" }, { "LEVEL 50", "^NIVEL 50$" }, { "LEVEL 100", "^NIVEL 100$" },
                   { "LITTLE CUP", "^PEQUE.+OS$" }, { "ONE TYPE", "^MONOTIPO$" }, { "RECORD", "." }, { "REPLAYS", "^REPETICIONES$" } }
    for _, w in ipairs(want) do
      local r = byLabel[w[1]]
      local es = r and I18n.t(r.label) or "?"
      check(r ~= nil and es ~= w[1] and es:match(w[2]) ~= nil, w[1] .. " translated: " .. es)
    end
    local mrow = rows[1]
    check(mrow and mrow.label:match("^MATCH") and I18n.t(mrow.label) ~= mrow.label, "MATCH row translated: " .. (mrow and I18n.t(mrow.label) or "?"))
    U.shot(game, DIR .. "/vs_menu_es.png")

    -- Check info box translation
    local infoLines = I18n.lines(byLabel["LEVEL 50"].info) -- LEVEL 50
    check(infoLines[1] == "TODOS A NIVEL 50.", "NIVEL 50 info line 1 translated")
    check(infoLines[2] == "SIN LEGENDARIOS NI", "NIVEL 50 info line 2 translated")
    check(infoLines[3]:match("^OHKO NI EVASIO?N%.$") ~= nil, "NIVEL 50 info line 3 translated: " .. infoLines[3])

    menu:close()
  end
  U.wait(20)

  -- 3. Adversarial invite refusal test:
  -- Host temporarily swaps party to illegal team (only Lugia) and tries to invite LEVEL 50
  if role == "host" then
    local originalParty = save.party
    save.party = illegalTeam
    local inviteOk = CoopLink.invite(game, "battle", CoopVS.FORMATS.lv50)
    check(not inviteOk, "host cannot send invite when team is completely illegal")
    save.party = originalParty
  end

  -- 4. Test ONE TYPE format in real Cable Club battle!
  if role == "host" then
    check(CoopLink.invite(game, "battle", CoopVS.FORMATS.mono), "sent ONE TYPE invite")
  else
    local asked
    for _ = 1, 60 * 20 do
      asked = CoopLink.asked
      if asked then break end
      U.wait(1)
    end
    check(asked ~= nil, "guest received ONE TYPE invite")
    if asked then
      check(I18n.t(asked.lines[3]) == "REGLAS MONOTIPO", "guest invite modal shows REGLAS MONOTIPO in Spanish")
      U.shot(game, DIR .. "/invite_mono_es.png")
      U.wait(70)
      U.tap(game, "a")
    end
  end

  local battle
  for _ = 1, 60 * 40 do
    local top = game.stack:top()
    if top and top.kind == "link" and top.playerParty then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "ONE TYPE battle opened")
  if battle then
    U.shot(game, DIR .. "/battle_mono.png")
    local mine, theirs = battle.playerParty, battle.enemyParty
    local hostSide = role == "host" and mine or theirs
    local guestSide = role == "host" and theirs or mine
    check(#hostSide == 2 and hostSide[1].species == "SPECIES_016" and hostSide[2].species == "SPECIES_143",
          "host plays Pidgey and Snorlax (both Normal type, Charmander & Lugia & dup filtered)")
    check(hostSide[1].level == 50 and hostSide[2].level == 50, "host Pokemon scaled to level 50")
    check(#guestSide == 2 and guestSide[1].species == "SPECIES_019" and guestSide[2].species == "SPECIES_161",
          "guest plays Rattata and Sentret (both Normal)")
    check(guestSide[1].level == 50 and guestSide[2].level == 50, "guest Pokemon scaled to level 50")
  end

  U.wait(40)
  U.log(role .. " adversarial rules done: " .. fails .. " failures")
  love.event.quit(fails == 0 and 0 or 1)
end
