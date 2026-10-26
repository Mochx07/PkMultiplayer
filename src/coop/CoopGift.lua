-- src/coop/CoopGift.lua
-- MYSTERY GIFT OVER THE LINK.  Gold, Silver and Crystal swapped Mystery Gifts
-- face to face over the infrared port: each game picked an item for the
-- OTHER player, rarer ones less often, once a day per friend.  Here it runs
-- over the co-op link: START -> CO-OP -> PARTNER -> MYSTERY GIFT asks the partner,
-- whose game asks them; on a yes each game picks a gift for the other.
-- One swap a day with each partner, by the real calendar (a shared clock
-- that moves the hours must not hand out another swap).  Items only: the
-- engine has no bedroom decorations to send.  A partner's answer that comes
-- after the wait ran out still completes the swap -- they already gave
-- theirs -- and a gift this cartridge has no such item for arrives as
-- another of the same rarity.
--
-- Wire: coop_gift_req { id } -> coop_gift_reply { id, ok, why?, item? }
-- -> coop_gift_give { id, item }.  A gift that finds the BAG full waits in
-- save.coopGiftPending and is handed over when there is room.

local CoopManager = require("src.coop.CoopManager")

local CoopGift = {}

CoopGift.ASK_TIMEOUT = 30
CoopGift.asking = nil -- { id, at }

-- { item key, weight }: the cartridge's three tiers of gifts
CoopGift.TABLE = {
  { "BERRY", 8 }, { "PRZCUREBERRY", 8 }, { "MINT_BERRY", 8 }, { "ICE_BERRY", 8 },
  { "BURNT_BERRY", 8 }, { "PSNCUREBERRY", 8 }, { "GUARD_SPEC", 8 }, { "X_DEFEND", 8 },
  { "X_ATTACK", 8 }, { "BITTER_BERRY", 8 }, { "DIRE_HIT", 8 }, { "X_SPECIAL", 8 },
  { "X_ACCURACY", 8 }, { "EON_MAIL", 8 }, { "MORPH_MAIL", 8 }, { "MUSIC_MAIL", 8 },
  { "MIRACLEBERRY", 3 }, { "GOLD_BERRY", 3 }, { "REVIVE", 3 }, { "GREAT_BALL", 3 },
  { "SUPER_REPEL", 3 }, { "MAX_REPEL", 3 }, { "ELIXER", 3 }, { "ETHER", 3 },
  { "WATER_STONE", 1 }, { "FIRE_STONE", 1 }, { "LEAF_STONE", 1 }, { "THUNDERSTONE", 1 },
  { "MAX_ETHER", 1 }, { "MAX_ELIXER", 1 }, { "MAX_REVIVE", 1 }, { "SCOPE_LENS", 1 },
  { "HP_UP", 1 }, { "PP_UP", 1 }, { "RARE_CANDY", 1 }, { "BLUESKY_MAIL", 1 },
  { "MIRAGE_MAIL", 1 },
}

local function itemByKey(data, key)
  for id, def in pairs((data and data.items) or {}) do
    if type(def) == "table" and def.key == key then return id end
  end
  return nil
end

-- today, by the real calendar (os.date follows the shared clock while
-- there is one; CoopManager keeps the real one)
function CoopGift.today()
  return (CoopManager.realDate or os.date)("%Y-%m-%d")
end

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.time()
end

local function partnerName()
  return CoopManager.partner.name or "PARTNER"
end

-- one swap a day per partner save (by name for a partner with no id)
local function partnerKey()
  return CoopManager.partner.id or partnerName()
end

function CoopGift.swappedToday(save, name)
  local log = save and save.coopGifts
  if type(log) ~= "table" then return false end
  local today = CoopGift.today()
  if name then return log[name] == today end
  return log[partnerKey()] == today or log[partnerName()] == today
end

local function markToday(save)
  save.coopGifts = type(save.coopGifts) == "table" and save.coopGifts or {}
  save.coopGifts[partnerKey()] = CoopGift.today()
end

-- a gift for the partner, from this cartridge's own items
function CoopGift.pick(game, rand)
  rand = rand or math.random
  local pool, total = {}, 0
  for _, g in ipairs(CoopGift.TABLE) do
    if itemByKey(game.data, g[1]) then
      pool[#pool + 1] = g
      total = total + g[2]
    end
  end
  if total <= 0 then return nil end
  local r = rand() * total
  for _, g in ipairs(pool) do
    r = r - g[2]
    if r <= 0 then return g[1] end
  end
  return pool[#pool][1]
end

local function itemName(game, key)
  local id = itemByKey(game.data, key)
  local def = id and game.data.items[id]
  return (def and def.name) or key
end

local function say(game, text, onDone)
  game.stack:push(require("src.render.TextBox").new(game, text, onDone))
end

-- a gift this cartridge has no item for: another one of the same rarity
function CoopGift.substitute(game, key, rand)
  if itemByKey(game.data, key) then return key end
  local weight
  for _, g in ipairs(CoopGift.TABLE) do if g[1] == key then weight = g[2] end end
  local pool = {}
  for _, g in ipairs(CoopGift.TABLE) do
    if (weight == nil or g[2] == weight) and itemByKey(game.data, g[1]) then pool[#pool + 1] = g[1] end
  end
  if #pool == 0 then return CoopGift.pick(game, rand) end
  rand = rand or math.random
  return pool[math.min(#pool, math.floor(rand() * #pool) + 1)]
end

-- into the BAG, or kept until there is room
function CoopGift.receive(game, key)
  key = CoopGift.substitute(game, key)
  local id = key and itemByKey(game.data, key)
  if not id then return false, key end
  local ok, added = pcall(function()
    return require("src.inventory.Bag").add(game.save, id, 1, game.data)
  end)
  if ok and added ~= false then return true, key end
  game.save.coopGiftPending = game.save.coopGiftPending or {}
  table.insert(game.save.coopGiftPending, key)
  return false, key
end

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

local function newId()
  return ("%d-%d"):format(os.time(), math.random(1, 1e6))
end

-- the menu row
function CoopGift.ask(game, ow)
  if not CoopManager.isConnected() then return end
  local name = partnerName()
  if CoopGift.swappedToday(game.save, name) then
    say(game, ("You swapped with\n%s today.\fCome back\ntomorrow!"):format(name))
    return
  end
  if CoopGift.asking then
    CoopManager.showStatus("Waiting for " .. name .. "...", 2)
    return
  end
  CoopGift.asking = { id = newId(), at = now() }
  send({ type = "coop_gift_req", id = CoopGift.asking.id })
  CoopManager.showStatus("Asking " .. name .. "...", 3)
end

local H = CoopManager.handlers
local getGame = CoopManager.getGame

-- B: asked
H.coop_gift_req = function(ow, msg)
  local game = getGame(ow)
  local function reply(ok, why, item)
    send({ type = "coop_gift_reply", id = msg.id, ok = ok, why = why, item = item })
  end
  if not (game and game.save) then return reply(false, "busy") end
  if CoopGift.swappedToday(game.save) then return reply(false, "done") end
  local idle = ow and CoopManager.overworldIdle(game, ow)
  if not idle then return reply(false, "busy") end
  local name = partnerName()
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, name .. " wants to\nswap GIFTS. OK?", nil, {
    defaultNo = false,
    choice = function(yes)
      if not yes then return reply(false, "no") end
      if CoopGift.swappedToday(game.save) then return reply(false, "done") end
      local gift = CoopGift.pick(game)
      if not gift then return reply(false, "none") end
      markToday(game.save)
      CoopGift.waiting = msg.id
      reply(true, nil, gift)
      CoopManager.showStatus(("Sent %s a gift!"):format(name), 3)
    end,
  }))
end

-- A: the answer, and B's gift with it
H.coop_gift_reply = function(ow, msg)
  local ask = CoopGift.asking
  local late = CoopGift.late == msg.id
  if not ((ask and ask.id == msg.id) or late) then return end
  if late then CoopGift.late = nil else CoopGift.asking = nil end
  local game = getGame(ow)
  local name = partnerName()
  if not msg.ok then
    local why = msg.why == "done" and (name .. " already swapped today")
                or msg.why == "busy" and (name .. " is busy")
                or (name .. " said no")
    CoopManager.showStatus(why, 3)
    return
  end
  markToday(game.save)
  local gift = CoopGift.pick(game)
  send({ type = "coop_gift_give", id = msg.id, item = gift })
  local got = type(msg.item) == "string" and msg.item
  if got then
    local inBag
    inBag, got = CoopGift.receive(game, got)
    pcall(function() require("src.core.Sound").play(game.data, "Item") end)
    say(game, ("%s sent you\n%s!"):format(name, itemName(game, got))
              .. (inBag and "" or "\fThe BAG is full.\nIt will wait."))
  end
end

-- B: A's gift
H.coop_gift_give = function(ow, msg)
  if CoopGift.waiting ~= msg.id then return end
  CoopGift.waiting = nil
  local game = getGame(ow)
  local key = type(msg.item) == "string" and msg.item
  if not key then return end
  local inBag
  inBag, key = CoopGift.receive(game, key)
  pcall(function() require("src.core.Sound").play(game.data, "Item") end)
  local name = partnerName()
  local function show()
    say(game, ("%s sent you\n%s!"):format(name, itemName(game, key))
              .. (inBag and "" or "\fThe BAG is full.\nIt will wait."))
  end
  if ow and CoopManager.overworldIdle(game, ow) then show()
  else CoopManager.showStatus(("%s sent you %s!"):format(name, itemName(game, key)), 4) end
end

-- nobody answered; a gift that waited for room goes in when there is some
CoopManager.onIdleTick("gift", function(dt, game)
  local ask = CoopGift.asking
  if ask and now() - ask.at > CoopGift.ASK_TIMEOUT then
    CoopGift.asking = nil
    -- their YES may still come: it completes the swap
    CoopGift.late = ask.id
    CoopManager.showStatus(partnerName() .. " didn't answer", 3)
  end
  local pending = game and game.save and game.save.coopGiftPending
  if type(pending) == "table" and #pending > 0 then
    CoopGift.retry = (CoopGift.retry or 0) + dt
    if CoopGift.retry < 5 then return end
    CoopGift.retry = 0
    local key = table.remove(pending, 1)
    if not CoopGift.receive(game, key) then
      -- still full: receive() put it back at the end
      return
    end
    CoopManager.showStatus(itemName(game, key) .. " put in the BAG", 3)
    if #pending == 0 then game.save.coopGiftPending = nil end
  end
end)

return CoopGift
