-- src/coop/CoopDex.lua
-- THE TWO POKéDEXES SIDE BY SIDE.  START -> CO-OP -> POKéDEX lists what your
-- partner has caught that you have not, and the other way round.  With the
-- SHARE DEX rule on, everything either of you catches counts as SEEN in the
-- other's Pokédex (seen, not owned: you can read its entry and where it
-- lives, the catch is still yours to make).
--
-- Wire: coop_dex_req -> coop_dex { owned, seen } (the whole dex, on asking
-- and on linking), coop_dex_add { owned } (each new catch, as it happens).

local CoopManager = require("src.coop.CoopManager")
local Font = require("src.coop.CoopI18n").font()

local CoopDex = {}

-- the partner's dex as last heard: { owned = set, seen = set } or nil
CoopDex.partner = nil
-- what we last told the partner we own, to send only what is new
CoopDex.announced = nil
CoopDex.CHECK_EVERY = 1.0
CoopDex.checkTimer = 0

local getGame = CoopManager.getGame

local function dexOf(save)
  local d = save and save.pokedex
  if type(d) ~= "table" then return nil end
  d.seen = d.seen or {}
  d.owned = d.owned or {}
  return d
end

local function keys(set)
  local out = {}
  for k, v in pairs(set or {}) do
    if v then out[#out + 1] = k end
  end
  table.sort(out)
  return out
end

local function toSet(list)
  local out = {}
  for _, k in ipairs(type(list) == "table" and list or {}) do
    if type(k) == "string" then out[k] = true end
  end
  return out
end

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

function CoopDex.sendWhole(game)
  local d = dexOf(game and game.save)
  if not d then return end
  CoopDex.announced = {}
  for k, v in pairs(d.owned) do if v then CoopDex.announced[k] = true end end
  send({ type = "coop_dex", owned = keys(d.owned), seen = keys(d.seen) })
end

function CoopDex.request()
  send({ type = "coop_dex_req" })
end

-- SHARE DEX: the partner's catches become our SEEN entries
function CoopDex.applyShared(game, ownedList)
  if not CoopManager.shareDex then return 0 end
  local d = dexOf(game and game.save)
  local data = game and game.data
  if not d then return 0 end
  local added = 0
  for _, id in ipairs(ownedList) do
    if not d.seen[id] and (not data or not data.pokemon or data.pokemon[id]) then
      d.seen[id] = true
      added = added + 1
    end
  end
  return added
end

local H = CoopManager.handlers

H.coop_dex_req = function(ow)
  CoopDex.sendWhole(getGame(ow))
end

H.coop_dex = function(ow, msg)
  CoopDex.partner = { owned = toSet(msg.owned), seen = toSet(msg.seen) }
  local added = CoopDex.applyShared(getGame(ow), keys(CoopDex.partner.owned))
  if added > 0 then
    CoopManager.showStatus(("SHARE DEX: +%d seen"):format(added), 2.5)
  end
end

H.coop_dex_add = function(ow, msg)
  local game = getGame(ow)
  local p = CoopDex.partner or { owned = {}, seen = {} }
  CoopDex.partner = p
  local list = {}
  for _, id in ipairs(type(msg.owned) == "table" and msg.owned or {}) do
    if type(id) == "string" then
      p.owned[id], p.seen[id] = true, true
      list[#list + 1] = id
    end
  end
  CoopDex.applyShared(game, list)
end

CoopManager.addRule("shareDex", "SHARE DEX", false, function(on, fromPartner)
  -- switching it on brings in everything the partner already has
  if on then CoopDex.request() end
end)

-- each new catch goes out as it lands in our dex; the whole dex goes out
-- once per link
CoopManager.onTick("dex", function(dt, game)
  local d = dexOf(game and game.save)
  if not d then return end
  if CoopDex.serial ~= CoopManager.linkSerial then
    -- a new link: the partner may be someone else
    CoopDex.serial = CoopManager.linkSerial
    CoopDex.reset()
  end
  if not CoopDex.announced then
    CoopDex.sendWhole(game)
    return
  end
  CoopDex.checkTimer = CoopDex.checkTimer + dt
  if CoopDex.checkTimer < CoopDex.CHECK_EVERY then return end
  CoopDex.checkTimer = 0
  local new = {}
  for id, v in pairs(d.owned) do
    if v and not CoopDex.announced[id] then
      CoopDex.announced[id] = true
      new[#new + 1] = id
    end
  end
  if #new > 0 then
    table.sort(new)
    send({ type = "coop_dex_add", owned = new })
  end
end)

function CoopDex.reset()
  CoopDex.partner = nil
  CoopDex.announced = nil
end

-- ---------------------------------------------------------------------
-- the screen
-- ---------------------------------------------------------------------

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local ROWS = 9

-- species ids in Pokédex order
local function byDex(data, set, minus)
  local out = {}
  for id in pairs(set or {}) do
    if not (minus and minus[id]) then out[#out + 1] = id end
  end
  local mons = data and data.pokemon or {}
  table.sort(out, function(a, b)
    local da = mons[a] and mons[a].dex or 9999
    local db = mons[b] and mons[b].dex or 9999
    if da ~= db then return da < db end
    return a < b
  end)
  return out
end

local function count(set)
  local n = 0
  for _, v in pairs(set or {}) do if v then n = n + 1 end end
  return n
end

function CoopDex.open(game)
  CoopDex.request()
  local self = setmetatable({ game = game, tab = 1, top = 1, cursor = 1 }, Screen)
  game.stack:push(self)
  return self
end

function Screen:lists()
  local data = self.game.data
  local mine = (dexOf(self.game.save) or {}).owned or {}
  local theirs = CoopDex.partner and CoopDex.partner.owned
  if not theirs then return nil end
  return { byDex(data, theirs, mine), byDex(data, mine, theirs) }, mine, theirs
end

function Screen:update()
  local input = self.game.input
  local lists = self:lists()
  if input:wasPressed("b") or input:wasPressed("start") then
    self.game.stack:pop()
    return
  end
  if not lists then return end
  local list = lists[self.tab]
  if input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("select") then
    self.tab = 3 - self.tab
    self.top, self.cursor = 1, 1
  elseif input:wasPressed("down") then
    self.cursor = math.min(#list, self.cursor + 1)
  elseif input:wasPressed("up") then
    self.cursor = math.max(1, self.cursor - 1)
  end
  if self.cursor < self.top then self.top = self.cursor end
  if self.cursor > self.top + ROWS - 1 then self.top = self.cursor - ROWS + 1 end
end

local function fit(text, n)
  -- translated, then cut to n letters (not bytes: an accent is two)
  return require("src.coop.CoopI18n").fit(text, n)
end

function Screen:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  local name = fit(CoopManager.partner.name or "PARTNER", 7)
  local lists, mine, theirs = self:lists()
  Font.drawBox(0, 0, 20, 4)
  Font.draw("POKéDEX", 8, 8)
  if not lists then
    Font.drawBox(0, 4, 20, 14)
    Font.draw("ASKING " .. name .. "...", 8, 48)
    Font.draw("B:BACK", 8, 128)
    return
  end
  Font.draw(("YOU %3d  %s %3d"):format(count(mine), name, count(theirs)), 8, 16)
  Font.drawBox(0, 4, 20, 14)
  local title = (self.tab == 1) and (name .. " HAS") or "ONLY YOU HAVE"
  Font.draw(title, 8, 40)
  local list = lists[self.tab]
  local mons = self.game.data and self.game.data.pokemon or {}
  if #list == 0 then
    Font.draw("NOTHING!", 24, 56)
  end
  for i = 0, ROWS - 1 do
    local id = list[self.top + i]
    if not id then break end
    local def = mons[id]
    local y = 52 + i * 8
    local num = def and def.dex and ("%03d"):format(def.dex) or "---"
    Font.draw(num .. " " .. fit(def and def.name or id, 10), 24, y)
    if self.top + i == self.cursor then Font.drawCode(0xED, 12, y) end
  end
  Font.draw("SEL:SWAP  B:BACK", 8, 128)
end

CoopDex.Screen = Screen

return CoopDex
