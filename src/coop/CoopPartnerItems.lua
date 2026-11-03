-- src/coop/CoopPartnerItems.lua
-- YOUR MEDICINE, THEIR POKEMON (split out of CoopManager.lua for 1.20).
-- install(CoopManager) defines these CoopManager.* functions on the manager
-- itself, so every caller keeps using the names it always did.
--
-- There is no "heal both teams" button any more: a free full heal anywhere,
-- for both of you, made every POKEMON CENTER and every potion pointless.
-- What a partner can do instead is what a friend standing next to you could:
-- hand over their OWN medicine.  Pick a POTION, a REVIVE, an ANTIDOTE... from
-- your bag, then one of your partner's Pokemon.
--
-- Their machine owns their party, so it applies the item -- ItemEffects.use,
-- exactly as if they had used it from their own bag -- and answers; the item
-- leaves YOUR bag only when it worked.
--
-- ONE ITEM, ONE HEAL, WHATEVER THE LINK DOES.  The item is set aside the
-- moment it is sent (save.coopItemHeld, by request id) and only given back
-- if the answer says it did not work.  The partner's machine remembers each
-- request it answered (save.coopItemDone): the same request arriving again
-- gets the same answer and heals nobody twice.  An answer that never came
-- (the wait ran out, the link dropped) is asked for again on the next link;
-- a partner that has no record of it never used it, and the item comes back.
-- ---------------------------------------------------------------------

local CoopLog = require("src.coop.CoopLog")
local Pokemon = require("src.pokemon.Pokemon")
local Strings = require("src.core.Strings")

local M = {}

function M.install(CoopManager)
local getGame, removeState = CoopManager.getGame, CoopManager.removeState
local playSound, partnerReachable = CoopManager.playSound, CoopManager.partnerReachable
local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

CoopManager.ITEM_REPLY_WAIT = 8
CoopManager.itemRequest = nil

local function newRequestId()
  local r = (love and love.math and love.math.random) and love.math.random(1, 2^30) or math.random(1, 2^30)
  return string.format("I-%d-%d", os.time(), r)
end

local function showLines(game, lines, onDone)
  if not (game and game.stack) then return end
  local text = table.concat(lines or {}, "\f")
  if text == "" then
    if onDone then onDone() end
    return
  end
  game.stack:push(require("src.coop.CoopI18n").textBox().new(game, text, onDone))
end

CoopManager.ITEM_DONE_MAX = 64

local function heldItems(save)
  if type(save.coopItemHeld) ~= "table" then save.coopItemHeld = {} end
  return save.coopItemHeld
end

-- the answer to a request whose item was set aside: keep it spent, or give
-- it back.  Returns the item id when this request was still open.
local function settleHeld(game, reqId, worked)
  local save = game and game.save
  if not (save and type(save.coopItemHeld) == "table") then return nil end
  local item = save.coopItemHeld[reqId]
  if not item then return nil end
  save.coopItemHeld[reqId] = nil
  if not worked then require("src.inventory.Bag").add(save, item, 1, game.data) end
  return item
end
CoopManager.settleHeldItem = settleHeld

-- on every new link: ask about each answer that never came
function CoopManager.askHeldItems(game)
  local save = game and game.save
  if not (save and type(save.coopItemHeld) == "table") then return end
  for reqId in pairs(save.coopItemHeld) do
    CoopManager.net:send({ type = "coop_item_query", req = reqId })
  end
end

local function endItemRequest(game)
  local req = CoopManager.itemRequest
  CoopManager.itemRequest = nil
  if req and req.modal then removeState(game, req.modal) end
  return req
end

local function waitForPartner(game, req, line2)
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local pName = string.upper(CoopManager.partner.name or "PARTNER")
  req.modal = CoopWaitModal.new(game, pName, function(reason)
    if CoopManager.itemRequest == req then
      CoopManager.itemRequest = nil
      if req.stage == "use" then
        -- the item stays set aside: the answer may still come
        CoopManager.showStatus(pName .. " hasn't answered yet: your item comes back if it didn't work", 4)
      elseif reason == "timeout" then
        CoopManager.showStatus(pName .. " didn't answer", 2.5)
      end
    end
  end, CoopManager.ITEM_REPLY_WAIT, { lines = { "WAITING " .. pName, line2 }, compact = true,
                                       cancelLabel = "B: STOP WAITING" })
  game.stack:push(req.modal)
end

local function medicineIds(game)
  local ItemEffects = require("src.inventory.ItemEffects")
  local Bag = require("src.inventory.Bag")
  local out = {}
  for _, id in ipairs(Bag.order(game.save)) do
    if (game.save.inventory[id] or 0) > 0 and ItemEffects.isMedicine(id) then out[#out + 1] = id end
  end
  return out
end
CoopManager.medicineIds = medicineIds

-- one row of the partner's party, as their machine described it
local function partyLabel(m)
  local I18n = require("src.coop.CoopI18n")
  local name = I18n.truncate(m.name or "?", 10)
  local right
  if m.egg then right = "EGG"
  elseif (m.hp or 0) <= 0 then right = "FNT"
  elseif m.status then right = string.format("%s%4d", I18n.truncate(tostring(m.status), 3), m.hp or 0)
  else right = string.format("%7s", (m.hp or 0) .. "/" .. (m.maxHp or 0)) end
  return string.format("%s%s", I18n.padRight(name, 10), right)
end

-- Start: the medicine in your bag, then the partner's party.
function CoopManager.useItemOnPartner(game, ow)
  game = game or getGame(ow)
  if CoopManager.isLocalInBattle(ow) then
    CoopManager.showStatus("Can't do that in battle!", 2)
    return
  end
  local ok, why = partnerReachable(ow)
  if not ok then
    CoopManager.showStatus(why, 2.5)
    playSound(game, "Collision")
    return
  end
  local ids = medicineIds(game)
  if #ids == 0 then
    CoopManager.showStatus("No medicine in your BAG!", 2.5)
    playSound(game, "Collision")
    return
  end
  local I18n = require("src.coop.CoopI18n")
  local Menu = I18n.menu()
  local rows = {}
  for _, id in ipairs(ids) do
    local def = game.data.items[id]
    local itemId = id
    local itemName = I18n.truncate(def and def.name or id, 12)
    rows[#rows + 1] = {
      label = string.format("%s x%d", I18n.padRight(itemName, 12), game.save.inventory[id] or 0),
      onSelect = function() CoopManager.askPartnerParty(game, ow, itemId) end,
    }
  end
  game.stack:push(Menu.new(game, rows, {
    tx = 1, ty = 4, tw = 18, cancelable = true, maxVisible = 6,
    header = Strings("ITEM FOR %s:", I18n.truncate(string.upper(CoopManager.partner.name or "PARTNER"), 8)),
  }))
end

function CoopManager.askPartnerParty(game, ow, itemId)
  if CoopManager.itemRequest then return end
  if not partnerReachable(ow) then
    CoopManager.showStatus("Partner is busy", 2.5)
    return
  end
  local req = { id = newRequestId(), item = itemId, stage = "party", ow = ow }
  CoopManager.itemRequest = req
  CoopManager.net:send({ type = "coop_party_req", req = req.id })
  waitForPartner(game, req, "SHOWING TEAM...")
end

-- their party arrived: pick the Pokemon
function CoopManager.onPartnerParty(ow, msg)
  local req = CoopManager.itemRequest
  if not (req and req.stage == "party" and msg.req == req.id) then return end
  local game = getGame(ow)
  endItemRequest(game)
  if msg.refused then
    CoopManager.showStatus((CoopManager.partner.name or "Partner") .. " is busy", 2.5)
    return
  end
  local Menu = require("src.coop.CoopI18n").menu()
  local rows = {}
  for _, m in ipairs(msg.mons or {}) do
    if type(m) == "table" and tonumber(m.slot) then
      local mon = m
      rows[#rows + 1] = {
        label = partyLabel(m),
        onSelect = function() CoopManager.sendItemUse(game, req.ow or ow, req.item, mon) end,
      }
    end
  end
  if #rows == 0 then return end
  local def = game.data.items[req.item]
  local I18n = require("src.coop.CoopI18n")
  local itemName = I18n.truncate(def and def.name or req.item, 10)
  game.stack:push(Menu.new(game, rows, {
    tx = 1, ty = 4, tw = 18, cancelable = true, maxVisible = 6,
    header = I18n.truncate(Strings("USE %s ON?", itemName), 18),
  }))
end

function CoopManager.sendItemUse(game, ow, itemId, mon)
  if CoopManager.itemRequest then return end
  if (game.save.inventory[itemId] or 0) <= 0 then return end
  if not partnerReachable(ow) then
    CoopManager.showStatus("Partner is busy", 2.5)
    return
  end
  local req = { id = newRequestId(), item = itemId, stage = "use", ow = ow }
  CoopManager.itemRequest = req
  require("src.inventory.Bag").remove(game.save, itemId, 1)
  heldItems(game.save)[req.id] = itemId
  CoopManager.net:send({ type = "coop_item_use", req = req.id, item = itemId,
                         slot = mon.slot, species = mon.species,
                         from = game.save.player and game.save.player.name })
  waitForPartner(game, req, "USING ITEM...")
end

-- their answer: the item worked (spend it) or it did not
function CoopManager.onItemResult(ow, msg)
  local game = getGame(ow)
  local item = settleHeld(game, msg.req, msg.ok == true)
  local req = CoopManager.itemRequest
  if not (req and req.stage == "use" and msg.req == req.id) then
    -- the answer to a wait that already ran out (or to the last session)
    if item then
      local def = game.data.items[item]
      local name = def and def.name or tostring(item)
      CoopManager.showStatus(msg.ok and Strings("%s worked on your partner's Pokemon", name)
                             or Strings("%s came back to your BAG", name), 3.5)
    end
    return
  end
  endItemRequest(game)
  local lines = type(msg.messages) == "table" and msg.messages or {}
  if msg.ok then
    playSound(game, "Heal_HP")
  elseif msg.refused then
    lines = { Strings("%s can't take\nthat right now.", CoopManager.partner.name or "PARTNER") }
  elseif #lines == 0 then
    lines = { Strings("It won't have\nany effect.") }
  end
  showLines(game, lines)
end

-- ...and the partner's side of it
local function canTakeItem(ow)
  local game = getGame(ow)
  if CoopManager.isLocalInBattle(ow) then return false end
  if not (game and game.save and game.save.party) then return false end
  return true
end

local function partySummary(game)
  local out = {}
  for i, mon in ipairs(game.save.party or {}) do
    if type(mon) == "table" then
      local def = game.data.pokemon and game.data.pokemon[mon.species]
      out[#out + 1] = {
        slot = i, species = mon.species, level = mon.level,
        name = mon.nickname or (def and def.name) or mon.species,
        hp = mon.hp or 0, maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 0,
        status = mon.status, egg = (mon.isEgg or mon.egg) and true or nil,
      }
    end
  end
  return out
end

function CoopManager.onPartyRequest(ow, msg)
  local game = getGame(ow)
  if not canTakeItem(ow) then
    CoopManager.net:send({ type = "coop_party", req = msg.req, refused = true })
    return
  end
  CoopManager.net:send({ type = "coop_party", req = msg.req, mons = partySummary(game) })
end

local function itemDone(save)
  if type(save.coopItemDone) ~= "table" then save.coopItemDone = { order = {} } end
  return save.coopItemDone
end

local function rememberItemAnswer(save, reqId, answer)
  if type(reqId) ~= "string" then return end
  local done = itemDone(save)
  if done[reqId] == nil then done.order[#done.order + 1] = reqId end
  done[reqId] = answer
  while #done.order > CoopManager.ITEM_DONE_MAX do
    done[table.remove(done.order, 1)] = nil
  end
end

function CoopManager.onItemQuery(ow, msg)
  local game = getGame(ow)
  if not (game and game.save) then return end
  local answer = itemDone(game.save)[msg.req]
  local t = { type = "coop_item_result", req = msg.req }
  if type(answer) == "table" then
    t.ok, t.refused = answer.ok, answer.refused
  else
    t.ok, t.unknown = false, true
  end
  CoopManager.net:send(t)
end

function CoopManager.onItemUse(ow, msg)
  local game = getGame(ow)
  if game and game.save then
    local answer = itemDone(game.save)[msg.req]
    if type(answer) == "table" then
      -- the same request again: the same answer, nothing used twice
      CoopManager.net:send({ type = "coop_item_result", req = msg.req, ok = answer.ok,
                             refused = answer.refused, messages = answer.messages })
      return
    end
  end
  local function reply(t)
    t.type, t.req = "coop_item_result", msg.req
    if game and game.save and not t.refused then
      rememberItemAnswer(game.save, msg.req, { ok = t.ok == true, messages = t.messages })
    end
    CoopManager.net:send(t)
  end
  if not canTakeItem(ow) then return reply({ refused = true }) end
  local slot = tonumber(msg.slot)
  local mon = slot and game.save.party[slot]
  local itemId = msg.item
  local ItemEffects = require("src.inventory.ItemEffects")
  -- the party it was picked from is a few seconds old: same slot, same
  -- species, and medicine only -- never a stone or a candy over the wire
  if type(mon) ~= "table" or mon.species ~= msg.species or not game.data.items[itemId]
     or not ItemEffects.isMedicine(itemId) then
    return reply({ refused = true })
  end
  local okUse, kind, messages = pcall(ItemEffects.use, game.data, game.save, itemId, mon, nil, nil, ow)
  if not okUse then
    CoopLog.error("ITEM", "partner item failed: " .. tostring(kind))
    return reply({ ok = false })
  end
  local worked = kind == "consumed"
  reply({ ok = worked, messages = messages })
  if worked then
    local def = game.data.items[itemId]
    local name = mon.nickname or (game.data.pokemon[mon.species] and game.data.pokemon[mon.species].name) or mon.species
    CoopManager.showStatus(string.format("%s used %s on %s!", msg.from or CoopManager.partner.name or "Partner",
                                         def and def.name or itemId, name), 3.5)
    playSound(game, "Heal_HP")
  end
end
end

return M
