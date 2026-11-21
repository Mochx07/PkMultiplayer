-- Gen 1 GYMS FOR TWO (nightly.3, B1).  Both players stand in a gym in
-- front of its leader; the host talks to him and picks CO-OP, the guest
-- accepts, both pick a team: the leader fights the two of them in a 2v2
-- with a team made for two (CoopGyms: more of his type, levels above the
-- weaker team), the same team on both screens.  Red, Blue or Yellow
-- (each with its own leader teams); PKM_GYM picks the gym (PEWTER_GYM).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local role = os.getenv("PKM_ROLE") or "host"
  local port = tonumber(os.getenv("PKM_PORT") or "7900")
  local GYM = os.getenv("PKM_GYM") or "PEWTER_GYM"
  local DIR = (os.getenv("SHOT_DIR") or "/tmp/pkm") .. "/" .. role
  local fails = 0
  local function check(ok, msg)
    U.log((ok and "ok   " or "FAIL ") .. role .. ": " .. msg)
    if not ok then fails = fails + 1 end
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local CoopManager = require("src.coop.CoopManager")
  local save = U.freshSave(game)
  save.player.name = role == "host" and "MOCHI" or "TOBY"
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_STARTER = true
  local GYM_LEVEL = {
    PEWTER_GYM = 16, CERULEAN_GYM = 20, VERMILION_GYM = 24, CELADON_GYM = 30,
    FUCHSIA_GYM = 44, SAFFRON_GYM = 44, CINNABAR_GYM = 48, VIRIDIAN_GYM = 52,
  }
  local lv = GYM_LEVEL[GYM] or 16
  local team = role == "host" and { { "SQUIRTLE", lv }, { "PIDGEY", lv - 3 }, { "RATTATA", lv - 4 } }
    or { { "BULBASAUR", lv - 1 }, { "SPEAROW", lv - 4 } }
  for _, t in ipairs(team) do
    local mon = Pokemon.new(game.data, t[1], t[2])
    -- reliable single-target non-Normal lead move (hits Ghosts, never hits ally)
    mon.moves[1] = { id = role == "host" and "WATER_GUN" or "VINE_WHIP", pp = 25 }
    table.insert(save.party, mon)
  end

  -- the leader of this gym, wherever the map puts him
  U.teleport(game, GYM, 4, 10, "up")
  U.wait(30)
  local ow = game.overworld
  local leader
  for _, npc in ipairs(ow.npcs or {}) do
    local d = npc.def or {}
    if d.trainerClass and CoopManager.leaderBadgeFor(d.trainerClass, d.trainerParty) then leader = npc break end
  end
  check(leader ~= nil, "found the leader of " .. GYM .. ": " .. tostring(leader and leader.def.trainerClass)
        .. " #" .. tostring(leader and leader.def.trainerParty))
  if not leader then love.event.quit(1) return end
  local lx, ly = leader.cellX, leader.cellY
  -- the gym's trainers are beaten on the way to the leader (as in play):
  -- none of them stops either player on the last steps
  save.defeatedTrainers = save.defeatedTrainers or {}
  for _, npc in ipairs(ow.npcs or {}) do
    local d = npc.def or {}
    if d.trainerClass and npc ~= leader then save.defeatedTrainers[npc.id] = true end
  end
  -- host right below him facing up, guest one to the side
  if role == "host" then U.teleport(game, GYM, lx, ly + 1, "up")
  else U.teleport(game, GYM, lx + 1, ly + 1, "up") end
  U.wait(30)
  ow = game.overworld
  if role == "host" then
    CoopManager.balancedFoes = true
    check(CoopManager.host(port), "hosting on " .. port)
  else
    U.wait(60)
    check(CoopManager.join("127.0.0.1", port), "dialling 127.0.0.1:" .. port)
  end
  local linked = false
  for _ = 1, 60 * 40 do
    if CoopManager.isConnected() and CoopManager.partner.map == GYM then linked = true break end
    U.wait(1)
  end
  check(linked, "linked, both in " .. GYM)
  U.wait(90)

  local function topName()
    local t = game.stack:top()
    if not t then return "nil" end
    if t == game.overworld then return "overworld" end
    if t.isCoopInvite then return "invite" end
    if t.isCoopBattleSelect then return "select" end
    if t.phase then return "battle:" .. tostring(t.phase) .. (t.coopDouble and ":coop" or "") end
    return tostring(t.header or t.title or t)
  end
  if role == "host" then
    U.shot(game, DIR .. "/0_in_front.png")
    U.tap(game, "a")       -- talk to the leader
  end
  local battle, last, askedShot
  for i = 1, 60 * 60 do
    local name = topName()
    if name ~= last then U.log(role .. ": top " .. name) last = name end
    local t = game.stack:top()
    if t and t.phase and t.coopDouble then battle = t break end
    if role == "host" and t and t ~= game.overworld and not t.phase and not t.isCoopBattleSelect and not askedShot then
      askedShot = true
      U.shot(game, DIR .. "/1_coop_or_solo.png")
    end
    if role == "guest" and t and t.isCoopInvite and i % 30 == 0 then U.tap(game, "a") end
    if t and t.isCoopBattleSelect and i % 20 == 0 then U.tap(game, "start") end
    -- CO-OP (first row) on the host's question, then the leader's speech
    if role == "host" and t and t ~= game.overworld and not t.phase and not t.isCoopBattleSelect and i % 30 == 0 then U.tap(game, "a") end
    if role == "host" and t and t.phase and not t.coopDouble and i > 60 * 40 then break end
    U.wait(1)
  end
  check(battle ~= nil, "a co-op 2v2 against the leader is up")
  if battle then
    U.wait(40)
    U.shot(game, DIR .. "/2_battle.png")
    local names, key = {}, {}
    local data = game.data
    for _, m in ipairs(battle.enemyParty or {}) do
      local def = data.pokemon[m.species]
      names[#names + 1] = tostring(def and def.name or m.species) .. ":" .. tostring(m.level)
      key[#key + 1] = tostring(m.species) .. ":" .. tostring(m.level) .. ":" .. tostring(m.hp)
    end
    local plan = battle.coopGymTeam
    U.log(("%s: %s brings %s (plan foes=%s shift=%s)"):format(role, tostring(battle.oppClass),
      table.concat(names, " "), tostring(plan and plan.foes), tostring(plan and plan.shift)))
    check(plan ~= nil, "the leader brings a team made for two")
    check(plan and #battle.enemyParty == plan.foes, "his party has the planned size (" .. #(battle.enemyParty or {}) .. ")")
    check(#(battle.enemyParty or {}) > 2, "more than the cartridge's two")
    local k = table.concat(key, ",")
    -- compared through files next to the screenshots (a chat line is too
    -- short for six Pokemon)
    local root = os.getenv("SHOT_DIR") or "/tmp/pkm"
    local mine = io.open(root .. "/team_" .. role .. ".txt", "w")
    if mine then mine:write(k) mine:close() end
    local other = role == "host" and "guest" or "host"
    local agreed
    for _ = 1, 60 * 20 do
      local f = io.open(root .. "/team_" .. other .. ".txt", "r")
      if f then
        local t = f:read("*a") f:close()
        if t and t ~= "" then agreed = (t == k) break end
      end
      U.wait(1)
    end
    check(agreed == true, "both copies built the same leader team")

    -- win it quickly: the same change on both copies at the same point
    -- (before any turn) keeps them in step
    if os.getenv("PKM_WIN") ~= "0" then
      for _, m in ipairs(battle.enemyParty or {}) do
        m.hp = 1
        if m.stats then m.stats.speed, m.stats.attack, m.stats.special = 1, 1, 1 end
      end
      local P = require("src.battle.BattleState").POS
      for _, pos in ipairs({ P.OPPONENT_LEFT, P.OPPONENT_RIGHT }) do
        local b = battle:battlerAt(pos)
        if b and b.mon then
          b.mon.hp = 1
          if b.mon.stats then b.mon.stats.speed, b.mon.stats.attack, b.mon.stats.special = 1, 1, 1 end
        end
      end
      local done = false
      for i = 1, 60 * 240 do
        local t = game.stack:top()
        if t == game.overworld then done = true break end
        if i % 15 == 0 then
          if t and t.forceSwitch and t.index then
            local list = t.party or save.party or {}
            local cur = list[t.index]
            if not cur or (cur.hp or 0) <= 0 then
              for idx, m in ipairs(list) do
                if (m.hp or 0) > 0 then t.index = idx break end
              end
            end
          end
          U.tap(game, "a")
        end
        U.wait(1)
      end
      check(done, "the battle ended and both are back in the gym")
      for _ = 1, 60 * 10 do
        if game.stack:top() == game.overworld then break end
        U.tap(game, "a") U.wait(10)
      end
      U.wait(120)
      local badge = CoopManager.leaderBadgeFor(battle.oppClass, battle.partyIndex)
      local Badges = require("src.inventory.Badges")
      check(badge and Badges.has(save, { id = badge }), "this player holds the " .. tostring(badge))
      U.shot(game, DIR .. "/3_after.png")
    end
  else
    U.shot(game, DIR .. "/2_no_coop.png")
  end
  U.wait(120)
  U.log(("%s done: %d failures"):format(role, fails))
  love.event.quit(fails == 0 and 0 or 1)
end
