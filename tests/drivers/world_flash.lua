-- THE PARTNER'S FLASH (1.20, src/coop/CoopWorld.lua), two real Gold copies
-- linked over 127.0.0.1 in DARK CAVE (Violet side).  The host has FLASH and
-- the ZEPHYRBADGE and lights its cave the way the party menu's FLASH does
-- (save.flashLit + setDark(false)); the guest has neither.
--
--   1. the guest stands more than 8 steps away: its cave stays dark;
--   2. the host walks up within 8 steps: the guest's cave lights too.
--
--   pair.sh <mod> tests/drivers/world_flash.lua 7834 gold PkReviewUI_A PkReviewUI_B <out>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7834")
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local function waitFor(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  U.wait(5)
  pcall(function()
    local Pipelines = require("src.render.Pipelines")
    for _, e in ipairs(Pipelines.list()) do
      if e.def and e.def.drawWorld then Pipelines.setLevel(e.id, 0) end
    end
    require("src.render.Tilt").setLevel(0)
  end)
  local Pokemon = require("src.pokemon.Pokemon")
  local Badges = require("src.inventory.Badges")
  local CoopManager = require("src.coop.CoopManager")
  local CoopWorld = require("src.coop.CoopWorld")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.repelSteps = 500
  local function mon(n, moves)
    local id = ("SPECIES_%03d"):format(n)
    local m = Pokemon.new(game.data, game.data.pokemon[id] and id or next(game.data.pokemon), 90)
    m.moves = {}
    for _, mv in ipairs(moves) do m.moves[#m.moves + 1] = { id = mv, pp = 15 } end
    return m
  end
  if role == "host" then
    save.party[1] = mon(25, { "FLASH", "THUNDERSHOCK" }) -- PIKACHU
    Badges.set(save, { id = "ZEPHYRBADGE" }, true)
  else
    save.party[1] = mon(160, { "TACKLE" })
  end

  local MAP = "DARK_CAVE_VIOLET_ENTRANCE"
  U.teleport(game, MAP, 1, 1, "down")
  local ow = game.overworld
  local function walk(x, y) return ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) and not ow:npcAtCell(x, y) end
  -- two walkable cells far apart and one close to the second
  local W, H = ow.map.def.width * 2, ow.map.def.height * 2
  local cells = {}
  for y = 0, H - 1 do for x = 0, W - 1 do if walk(x, y) then cells[#cells + 1] = { x, y } end end end
  local A, Bf, Bn
  for _, a in ipairs(cells) do
    for _, b in ipairs(cells) do
      local d = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2])
      if not A and d >= 12 and d <= 16 then A, Bf = a, b end
    end
    if A then break end
  end
  if A then
    for _, b in ipairs(cells) do
      local d = math.abs(A[1] - b[1]) + math.abs(A[2] - b[2])
      if not Bn and d >= 2 and d <= 4 then Bn = b end
    end
  end
  check(A and Bf and Bn and ow.dark == true, ("%s is dark; guest %s, host far %s, near %s"):format(MAP,
    A and (A[1] .. "," .. A[2]) or "?", Bf and (Bf[1] .. "," .. Bf[2]) or "?", Bn and (Bn[1] .. "," .. Bn[2]) or "?"))
  if not (A and Bf and Bn) then love.event.quit(1) return end

  if role == "host" then
    U.teleport(game, MAP, Bf[1], Bf[2], "down")
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.teleport(game, MAP, A[1], A[2], "down")
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  ow = game.overworld
  check(waitFor(60 * 30, function()
    return CoopManager.isConnected() and CoopManager.partner.map == MAP and CoopWorld.on()
  end), "linked, both in " .. MAP .. " with world.share")
  U.wait(60)

  if role == "host" then
    -- FLASH, as the party menu does it
    check(ow:partyKnows("FLASH") ~= nil, "our PIKACHU can FLASH (ZEPHYRBADGE)")
    game.save.flashLit = true
    ow:setDark(false)
    U.wait(30)
    U.shot(game, DIR .. "/1_lit_far.png")
    check(waitFor(60 * 30, function() return CoopManager.partner.emote == "question" end),
          "the guest says it is still dark")
    U.teleport(game, MAP, Bn[1], Bn[2], "down")
    ow = game.overworld
    check(ow.dark == false, "our cave stays lit across the reload (FLASH lasts on this map)")
    U.wait(60 * 5)
    U.shot(game, DIR .. "/2_near.png")
  else
    check(waitFor(60 * 10, function() return CoopWorld.partnerLit end), "the host's FLASH is up")
    U.wait(60 * 2)
    check(ow.dark == true, "the host " .. tostring(CoopWorld.partnerSteps(ow)) .. " steps away: still dark here")
    U.shot(game, DIR .. "/1_dark_far.png")
    CoopManager.sendEmote("question")
    check(waitFor(60 * 30, function() return ow.dark == false end),
          "the host walked up (" .. tostring(CoopWorld.partnerSteps(ow)) .. " steps): our cave is lit")
    U.wait(40)
    U.shot(game, DIR .. "/2_lit_near.png")
    check(game.save.flashLit == true, "...and stays lit (save.flashLit)")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
