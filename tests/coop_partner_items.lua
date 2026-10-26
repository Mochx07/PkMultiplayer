-- CO-OP: YOUR MEDICINE ON YOUR PARTNER'S POKEMON, AND A WARP WITH LIMITS.
--
--   * the free "heal both teams" button is gone, from the co-op menu and
--     from talking to your partner;
--   * USE ITEM sends one of your medicines to one of the partner's
--     Pokemon: their machine applies it, and it leaves YOUR bag only when it
--     worked; a stale pick (another species in that slot) or anything that is
--     not medicine is refused;
--   * WARP TO PARTNER goes only to a town you have been to (FLY's rule),
--     only when the partner says YES, recharges for ten minutes, and never
--     lands in a gym, the League or on the water.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CoopManager = require("src.coop.CoopManager")
local CoopMenu = require("src.coop.CoopMenu")
require("src.coop.CoopLog").enabled = false

Data.items.POTION = { id = "POTION", index = 18, name = "POTION", price = 300 }
Data.items.ANTIDOTE = { id = "ANTIDOTE", index = 9, name = "ANTIDOTE", price = 100 }

local function newStack()
  local s = { states = {} }
  function s:push(x) table.insert(self.states, x) end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local function newGame(name)
  local save = SaveData.newGame()
  save.player.name = name
  save.party = { Pokemon.new(Data, "FIXMON_A", 20, function(a) return a end),
                 Pokemon.new(Data, "FIXMON_C", 20, function(a) return a end) }
  save.inventory = save.inventory or {}
  return { data = Data, save = save, stack = newStack(),
           input = { wasPressed = function() return false end, isDown = function() return false end } }
end

local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end,
                    isLinked = function() return true end, flush = function() end }
CoopManager.connected = true
local function lastSent(kind)
  for i = #sent, 1, -1 do if sent[i].type == kind then return sent[i] end end
end

local function overworld(game, mapId)
  local ow = { game = game, isOverworld = true, map = { id = mapId }, player = { cellX = 3, cellY = 3 } }
  function ow:startWarpTo(map, x, y, f) self.warpedTo = { map = map, x = x, y = y } end
  return ow
end

-- ---------------------------------------------------------------------
-- no free heal button
-- ---------------------------------------------------------------------

do
  local game = newGame("ME")
  local menu = CoopMenu.new(game)
  local labels = {}
  for _, page in ipairs({ "main", "partner", "rules" }) do
    for _, row in ipairs(menu:connectedRows(overworld(game, "ROUTE_29"), page)) do labels[#labels + 1] = row.label end
  end
  local joined = table.concat(labels, "|")
  -- (PARTNER HEALS is the separate after-battle rule toggle, not a heal)
  T.check(not joined:find("HEAL BOTH", 1, true), "the co-op menu has no heal-both-teams row (" .. joined .. ")")
  T.check(joined:find("ITEM FOR PARTNER", 1, true) ~= nil, "the co-op menu offers ITEM FOR PARTNER")
  T.check(CoopManager.healBothParties == nil, "the heal-both-parties function is gone")

  -- the menu is pages now: seven rows up top, PARTNER and RULES below them
  local function cells(text) local n = 0 for _ in tostring(text):gmatch("[^\128-\191]") do n = n + 1 end return n end
  local ow = overworld(game, "ROUTE_29")
  local top = menu:connectedRows(ow)
  T.check(#top <= 9, "the co-op menu's first page fits without scrolling (" .. #top .. " rows)")
  local fits, described = true, true
  for _, page in ipairs({ "main", "partner", "rules" }) do
    for _, row in ipairs(menu:connectedRows(ow, page)) do
      if cells(row.label) > (row.sub and 15 or 16) then fits = false end
      if page == "rules" then
        if not (row.info and #row.info >= 1 and #row.info <= 3) then described = false end
        for _, line in ipairs(row.info or {}) do if cells(line) > 18 then described = false end end
      end
    end
  end
  T.check(fits, "every label fits its 16 columns (15 beside a page arrow)")
  T.check(described, "every rule says what it does, in three lines of 18")
  local rules = menu:connectedRows(ow, "rules")
  T.check(cells(rules[1].label) == 16 and rules[1].label:match("O[NF]F?$") ~= nil,
          "a rule's ON/OFF sits at the right edge (" .. rules[1].label .. ")")

  -- VERSION: this mod's version and protocol, and the partner's once linked
  local verRow
  for _, row in ipairs(top) do if row.label == "VERSION" then verRow = row end end
  T.check(verRow and verRow.info and verRow.info[1] == "MOD V" .. CoopManager.modVersion():upper(),
          "the VERSION row shows this mod's version (" .. tostring(verRow and verRow.info[1]) .. ")")
  T.check(verRow and verRow.info[2] == "LINK PROTOCOL " .. require("src.coop.CoopNet").PROTOCOL,
          "...and the link protocol")
  local offlineVer
  for _, row in ipairs(menu:offlineRows()) do if row.label == "VERSION" then offlineVer = row end end
  T.check(offlineVer ~= nil, "the VERSION row is on the offline page too")
  local savedIsConn = CoopManager.isConnected
  CoopManager.isConnected = function() return true end
  CoopManager.partner.version = "1.4.0"
  for _, row in ipairs(menu:connectedRows(ow)) do
    if row.label == "VERSION" then verRow = row end
  end
  T.check(verRow.info[3] == "P2 V1.4.0", "linked, it shows the partner's version too")
  CoopManager.partner.version = nil
  CoopManager.isConnected = savedIsConn

  -- A on PARTNER opens its page; B comes back to the PARTNER row, not the top
  local where
  for i, row in ipairs(top) do if row.sub == "partner" then where = i end end
  menu.index = where
  top[where].run()
  T.check(menu.page == "partner" and menu.index == 1, "A on PARTNER opens the partner page")
  local realIsConn = CoopManager.isConnected
  CoopManager.isConnected = function() return true end
  game.input = { wasPressed = function(_, k) return k == "b" end, isDown = function() return false end }
  local popped = false
  local realPop = game.stack.pop
  game.stack.pop = function() popped = true end
  menu:update(1 / 60)
  T.check(menu.page == "main" and menu.index == where and not popped,
          "B on a page goes back to the row it was opened from")
  menu:update(1 / 60)
  T.check(popped, "B on the first page closes the menu")
  game.stack.pop, CoopManager.isConnected = realPop, realIsConn
  game.input = { wasPressed = function() return false end, isDown = function() return false end }

  local pushed
  game.stack.push = function(_, st) pushed = st end
  CoopManager.interact(game, overworld(game, "ROUTE_29"))
  local talk = {}
  for _, it in ipairs(pushed and pushed.items or {}) do talk[#talk + 1] = it.label end
  joined = table.concat(talk, "|")
  T.check(not joined:find("HEAL"), "talking to the partner offers no heal (" .. joined .. ")")
  T.check(joined:find("USE ITEM", 1, true) ~= nil, "talking to the partner offers USE ITEM")
end

-- ---------------------------------------------------------------------
-- the partner's machine applies the item
-- ---------------------------------------------------------------------

do
  local theirs = newGame("FRIEND")
  local ow = overworld(theirs, "ROUTE_29")
  local hurt = theirs.save.party[1]
  hurt.hp = 5

  sent = {}
  CoopManager.onPartyRequest(ow, { req = "R1" })
  local party = lastSent("coop_party")
  T.check(party and party.req == "R1" and #party.mons == 2, "the partner answers with their party")
  T.check(party.mons[1].hp == 5 and party.mons[1].slot == 1 and party.mons[1].species == "FIXMON_A",
          "each row carries slot, species and HP")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U1", item = "POTION", slot = 1, species = "FIXMON_A", from = "ME" })
  local r = lastSent("coop_item_result")
  T.check(r and r.ok == true and hurt.hp == 25, "a POTION from the partner heals 20 HP on the owner's copy")

  sent = {}
  local full = theirs.save.party[2]
  local before = full.hp
  CoopManager.onItemUse(ow, { req = "U2", item = "POTION", slot = 2, species = "FIXMON_C" })
  r = lastSent("coop_item_result")
  T.check(r and r.ok == false and full.hp == before, "a POTION on a full-HP Pokemon does nothing and says so")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U3", item = "POTION", slot = 1, species = "FIXMON_C" })
  r = lastSent("coop_item_result")
  T.check(r and r.refused and hurt.hp == 25, "a stale pick (another species in the slot) is refused")

  sent = {}
  CoopManager.onItemUse(ow, { req = "U4", item = "FIX_TM", slot = 1, species = "FIXMON_A" })
  r = lastSent("coop_item_result")
  T.check(r and r.refused, "only medicine crosses the wire; a TM is refused")

  hurt.status = "PSN"
  sent = {}
  CoopManager.onItemUse(ow, { req = "U5", item = "ANTIDOTE", slot = 1, species = "FIXMON_A" })
  r = lastSent("coop_item_result")
  T.check(r and r.ok and hurt.status == nil, "an ANTIDOTE cures the partner's poisoned Pokemon")
end

-- ---------------------------------------------------------------------
-- your bag pays only when it worked
-- ---------------------------------------------------------------------

do
  local mine = newGame("ME")
  local ow = overworld(mine, "ROUTE_29")
  local Bag = require("src.inventory.Bag")
  Bag.add(mine.save, "POTION", 2, Data)
  CoopManager.partner.map = "ROUTE_29"
  CoopManager.partner.lastSeen = 1e12
  CoopManager.partner.inBattle, CoopManager.partner.busy, CoopManager.partner.inDialogue = false, false, false
  local ids = CoopManager.medicineIds(mine)
  T.check(#ids == 1 and ids[1] == "POTION", "the item list is the medicine in your bag")

  CoopManager.itemRequest = nil
  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  local use = lastSent("coop_item_use")
  T.check(use and use.item == "POTION" and use.slot == 1, "the pick goes to the partner")
  T.check(mine.save.inventory.POTION == 1 and mine.save.coopItemHeld[use.req] == "POTION",
          "...and the item is set aside while they answer")
  CoopManager.onItemResult(ow, { req = use.req, ok = false, messages = { "It won't have\nany effect." } })
  T.check(mine.save.inventory.POTION == 2, "an item that did nothing stays in your bag")

  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  use = lastSent("coop_item_use")
  CoopManager.onItemResult(ow, { req = use.req, ok = true, messages = { "Recovered!" } })
  T.check(mine.save.inventory.POTION == 1, "an item that worked is spent from YOUR bag")
  CoopManager.onItemResult(ow, { req = use.req, ok = true })
  T.check(mine.save.inventory.POTION == 1, "a repeated answer spends nothing more")

  -- the wait runs out: the item stays set aside, and the late answer settles it
  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  use = lastSent("coop_item_use")
  CoopManager.itemRequest = nil
  T.check((mine.save.inventory.POTION or 0) == 0, "an unanswered item is not in the bag")
  CoopManager.onItemResult(ow, { req = use.req, ok = false })
  T.check(mine.save.inventory.POTION == 1 and mine.save.coopItemHeld[use.req] == nil,
          "a late 'did nothing' gives it back")

  -- never answered at all: asked again on the next link; no record = never used
  sent = {}
  CoopManager.sendItemUse(mine, ow, "POTION", { slot = 1, species = "FIXMON_A" })
  use = lastSent("coop_item_use")
  CoopManager.itemRequest = nil
  sent = {}
  CoopManager.askHeldItems(mine)
  local q = lastSent("coop_item_query")
  T.check(q and q.req == use.req, "a new link asks about the answer that never came")
  local theirs = newGame("THEM")
  local theirOw = overworld(theirs, "ROUTE_29")
  sent = {}
  CoopManager.onItemQuery(theirOw, q)
  local a = lastSent("coop_item_result")
  T.check(a and a.unknown and not a.ok, "a partner with no record of it says so")
  CoopManager.onItemResult(ow, a)
  T.check(mine.save.inventory.POTION == 1, "...and the item comes back")
end

-- the partner's side: the same request twice heals once
do
  local theirs = newGame("THEM")
  local ow = overworld(theirs, "ROUTE_29")
  local mon = theirs.save.party[1]
  local full = mon.stats and mon.stats.hp or mon.maxHp or mon.hp
  mon.hp = 1
  local Bag = require("src.inventory.Bag")
  sent = {}
  CoopManager.onItemUse(ow, { req = "TWICE", item = "POTION", slot = 1, species = mon.species })
  local first = lastSent("coop_item_result")
  local hpAfter = mon.hp
  mon.hp = 1
  sent = {}
  CoopManager.onItemUse(ow, { req = "TWICE", item = "POTION", slot = 1, species = mon.species })
  local second = lastSent("coop_item_result")
  T.check(first and first.ok and hpAfter > 1, "the first request heals")
  T.check(second and second.ok and mon.hp == 1, "the same request again answers the same and heals nothing")
  sent = {}
  CoopManager.onItemQuery(ow, { req = "TWICE" })
  local q = lastSent("coop_item_result")
  T.check(q and q.ok and not q.unknown, "asked later, it remembers the heal")
  local _ = full and Bag
end

-- ---------------------------------------------------------------------
-- the warp: FLY's towns, the partner's YES, a ten-minute recharge, and
-- never into gyms or onto water
-- ---------------------------------------------------------------------

Data.field = Data.field or {}
Data.field.flyOrder = { "VIOLET_CITY", "CHERRYGROVE_CITY" }
Data.maps = Data.maps or {}
Data.maps.VIOLET_CITY = Data.maps.VIOLET_CITY or { id = "VIOLET_CITY", tileset = "OVERWORLD" }
Data.maps.CHERRYGROVE_CITY = Data.maps.CHERRYGROVE_CITY or { id = "CHERRYGROVE_CITY", tileset = "OVERWORLD" }

do
  local mine = newGame("ME")
  mine.save.visited = { VIOLET_CITY = true }
  local p = CoopManager.partner
  p.name = "TOBY"
  p.map, p.cx, p.cy, p.lastSeen = "VIOLET_CITY", 5, 6, 1e12
  p.inBattle, p.busy, p.inDialogue, p.surfing = false, false, false, false
  CoopManager.lastWarpAt = nil
  CoopManager.warpAsk = nil
  T.check(CoopManager.WARP_COOLDOWN >= 600, "the warp recharges for ten minutes")

  local ow = overworld(mine, "ROUTE_29")
  ow.game = mine
  local ok, why = CoopManager.canWarpToPartner(ow)
  T.check(ok, "a warp to an idle partner in a town you know is allowed (" .. tostring(why) .. ")")

  -- asking does not move you: the partner has to answer
  sent = {}
  T.check(CoopManager.warpToPartner(ow) and ow.warpedTo == nil, "WARP asks first and does not move you")
  local req = lastSent("coop_warp_req")
  T.check(req ~= nil, "the partner is sent a warp request")
  T.check(not CoopManager.warpToPartner(ow), "a second WARP while waiting is refused")

  -- a NO keeps you where you are
  CoopManager.onWarpReply(ow, { type = "coop_warp_reply", id = req.id, ok = false })
  T.check(ow.warpedTo == nil and CoopManager.warpAsk == nil, "a NO keeps you where you are")
  T.check(CoopManager.warpCooldownLeft() == 0, "...and costs no recharge")

  -- a YES (their yes/no box still closing) warps you onto them
  CoopManager.warpToPartner(ow)
  req = lastSent("coop_warp_req")
  p.inDialogue = true
  CoopManager.onWarpReply(ow, { type = "coop_warp_reply", id = req.id, ok = true })
  p.inDialogue = false
  T.check(ow.warpedTo and ow.warpedTo.map == "VIOLET_CITY", "a YES lands you on the partner")
  T.check(lastSent("coop_warp") ~= nil, "the partner is told you arrived")

  ow = overworld(mine, "ROUTE_29")
  ok, why = CoopManager.canWarpToPartner(ow)
  T.check(not ok and tostring(why):find("Warp ready in"), "the next warp waits for the recharge (" .. tostring(why) .. ")")

  CoopManager.lastWarpAt = nil
  p.map = "CHERRYGROVE_CITY"
  ok, why = CoopManager.canWarpToPartner(ow)
  T.check(not ok and tostring(why):find("towns you know"), "no warping to a town you have never been to (" .. tostring(why) .. ")")
  p.map = "ROUTE_30"
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping onto a route (not a FLY destination)")
  p.map = "VIOLET_GYM"
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping into a gym")
  p.map = "VIOLET_CITY"
  p.surfing = true
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping onto a partner who is surfing")
  p.surfing = false
  p.inBattle = true
  ok = CoopManager.canWarpToPartner(ow)
  T.check(not ok, "no warping to a partner in a battle")
  p.inBattle = false

  -- B's side: busy players are not asked; idle ones get a YES/NO box
  local theirs = newGame("TOBY")
  local tow = overworld(theirs, "VIOLET_CITY")
  tow.game = theirs
  theirs.overworld = tow
  theirs.stack:push(tow)
  sent = {}
  CoopManager.onWarpRequest(tow, { type = "coop_warp_req", id = 7 })
  local box = theirs.stack:top()
  T.check(box ~= tow and box and box.choice, "an idle partner is asked YES / NO")
  box.choice(true)
  local reply = lastSent("coop_warp_reply")
  T.check(reply and reply.id == 7 and reply.ok == true, "...and their YES goes back")
end

T.finish("co-op partner items and warp")
