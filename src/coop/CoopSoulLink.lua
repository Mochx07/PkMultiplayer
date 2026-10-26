-- src/coop/CoopSoulLink.lua
-- SOUL LINK, the two-player Nuzlocke.  With the rule on, the first Pokemon
-- each player catches in an area is bound to the first one the other
-- catches there; when either of the pair faints, both are gone for good --
-- the partner's falls the moment the news arrives, and neither gets back up
-- (a Pokemon Center or a REVIVE leaves it at 0 HP).  An area is a map, with
-- a cave or a tower's floors counted as one.
--
-- START -> CO-OP -> RULES -> SOUL LINKS lists the pairs.  The bonds live in each
-- save (save.soulLinks) and on every new link the two compare notes
-- (coop_soul_sync), so a faint while apart is settled the next time you
-- play together.
--
-- Wire: coop_soul_catch { area, id, species, name }, coop_soul_dead
-- { area, id }, coop_soul_sync { links = { {area, id, species, name, dead} } }.

local CoopManager = require("src.coop.CoopManager")
local Font = require("src.coop.CoopI18n").font()

local CoopSoulLink = {}

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

local function partnerName()
  return CoopManager.partner.name or "PARTNER"
end

-- UNION_CAVE_B1F and UNION_CAVE_1F are one area
function CoopSoulLink.areaOf(mapId)
  if type(mapId) ~= "string" then return nil end
  return (mapId:gsub("_B?%d+F$", ""))
end

local function links(save)
  save.soulLinks = type(save.soulLinks) == "table" and save.soulLinks or {}
  return save.soulLinks
end

-- every Pokemon the save holds: party, the open box, the other boxes
local function eachMon(save, fn)
  for _, m in ipairs(save.party or {}) do if fn(m) then return m end end
  for _, m in pairs(save.box or {}) do
    if type(m) == "table" and fn(m) then return m end
  end
  for _, box in pairs(save.boxes or {}) do
    for _, m in pairs(type(box) == "table" and box or {}) do
      if type(m) == "table" and fn(m) then return m end
    end
  end
  return nil
end

local function findMon(save, id)
  if not id then return nil end
  return eachMon(save, function(m) return m.soulId == id end)
end

local function monName(game, mon, species)
  local def = game.data.pokemon and game.data.pokemon[species or (mon and mon.species)]
  return (mon and mon.nickname) or (def and def.name) or tostring(species or "?")
end

local function newId()
  return ("%x%04x"):format(os.time(), math.random(0, 0xffff))
end

-- the rule is on and this save is playing with someone
local function active(game)
  return CoopManager.soulLink and game and game.save
end

-- BattleState:storeCaughtMon (lib/Hooks.lua): the first catch here is bound
function CoopSoulLink.onCaught(game, mon, mapId)
  if not (active(game) and type(mon) == "table") then return end
  local area = CoopSoulLink.areaOf(mapId or (game.save.player and game.save.player.map))
  if not area then return end
  local all = links(game.save)
  local link = all[area] or {}
  if link.mine then return end -- not the first one here: a free Pokemon
  mon.soulId = mon.soulId or newId()
  mon.soulArea = area
  link.mine, link.mineSpecies = mon.soulId, mon.species
  all[area] = link
  send({ type = "coop_soul_catch", area = area, id = mon.soulId, species = mon.species,
         name = mon.nickname })
  local label = CoopManager.mapLabel and CoopManager.mapLabel(area) or area
  if link.theirs then
    CoopManager.showStatus(("Soul-linked to %s's %s"):format(partnerName(),
      monName(game, nil, link.theirSpecies)), 4)
  else
    CoopManager.showStatus(("%s: first catch of %s"):format(label, monName(game, mon)), 3)
  end
end

-- one of ours is gone: its pair goes with it
local function kill(game, mon)
  mon.hp = 0
  mon.soulDead = true
  mon.status = nil
end

-- the bond broke on our side (a faint we just saw, or one we were told of)
local function breakLink(game, area, why)
  local link = links(game.save)[area]
  if not link or link.dead then return end
  link.dead = true
  local mine = findMon(game.save, link.mine)
  if mine then kill(game, mine) end
  if why == "partner" then
    local theirs = monName(game, nil, link.theirSpecies)
    local ours = mine and monName(game, mine) or "your POKéMON"
    CoopManager.showStatus(("%s's %s fell... %s too"):format(partnerName(), theirs, ours), 5)
  end
end

local H = CoopManager.handlers
local getGame = CoopManager.getGame

H.coop_soul_catch = function(ow, msg)
  local game = getGame(ow)
  if not (game and game.save and type(msg.area) == "string") then return end
  local all = links(game.save)
  local link = all[msg.area] or {}
  if link.theirs then return end
  link.theirs, link.theirSpecies, link.theirName = msg.id, msg.species, msg.name
  all[msg.area] = link
  if link.mine and CoopManager.soulLink then
    local mine = findMon(game.save, link.mine)
    CoopManager.showStatus(("Soul-linked: %s and %s"):format(
      mine and monName(game, mine) or "?", monName(game, nil, msg.species)), 4)
  end
end

H.coop_soul_dead = function(ow, msg)
  local game = getGame(ow)
  if not (game and game.save and type(msg.area) == "string") then return end
  breakLink(game, msg.area, "partner")
end

H.coop_soul_sync = function(ow, msg)
  local game = getGame(ow)
  if not (game and game.save) then return end
  local all = links(game.save)
  for _, l in ipairs(type(msg.links) == "table" and msg.links or {}) do
    if type(l) == "table" and type(l.area) == "string" then
      local link = all[l.area] or {}
      if not link.theirs then
        link.theirs, link.theirSpecies, link.theirName = l.id, l.species, l.name
      end
      all[l.area] = link
      if l.dead and not link.dead then breakLink(game, l.area, "partner") end
    end
  end
end

function CoopSoulLink.sendSync(game)
  local out = {}
  for area, link in pairs(links(game.save)) do
    if link.mine then
      local mon = findMon(game.save, link.mine)
      out[#out + 1] = { area = area, id = link.mine, species = link.mineSpecies,
                        name = mon and mon.nickname, dead = link.dead or nil }
    end
  end
  send({ type = "coop_soul_sync", links = out })
end

CoopManager.addRule("soulLink", "SOUL LINK", false, function(on)
  if on then
    local game = getGame()
    if game and game.save then CoopSoulLink.sendSync(game) end
  end
end)

-- WATCH: a bound Pokemon at 0 HP has fainted -- the bond breaks and the
-- partner hears of it; one already gone stays at 0 HP whatever healed it.
-- Runs linked or not (a faint while apart is told on the next link).
CoopSoulLink.CHECK_EVERY = 0.25
CoopSoulLink.timer = 0
function CoopSoulLink.watch(game)
  local save = game and game.save
  if not (save and type(save.soulLinks) == "table") then return end
  for area, link in pairs(save.soulLinks) do
    local mon = link.mine and findMon(save, link.mine)
    if mon then
      if link.dead or mon.soulDead then
        if (tonumber(mon.hp) or 0) > 0 then kill(game, mon) end
        if not link.dead then link.dead = true end
      elseif (tonumber(mon.hp) or 0) <= 0 and not mon.isEgg then
        link.dead = true
        mon.soulDead = true
        send({ type = "coop_soul_dead", area = area, id = link.mine })
        if link.theirs then
          CoopManager.showStatus(("%s fell... its soul-link breaks"):format(monName(game, mon)), 4)
        end
      end
    end
  end
end

CoopManager.onIdleTick("soul", function(dt, game)
  CoopSoulLink.timer = CoopSoulLink.timer + dt
  if CoopSoulLink.timer < CoopSoulLink.CHECK_EVERY then return end
  CoopSoulLink.timer = 0
  CoopSoulLink.watch(game)
end)

CoopManager.onTick("soul", function(dt, game)
  if CoopSoulLink.serial ~= CoopManager.linkSerial then
    CoopSoulLink.serial = CoopManager.linkSerial
    if game and game.save and game.save.soulLinks then CoopSoulLink.sendSync(game) end
  end
end)

-- ---------------------------------------------------------------------
-- the list
-- ---------------------------------------------------------------------

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true
local ROWS = 5

function CoopSoulLink.open(game)
  local self = setmetatable({ game = game, top = 1 }, Screen)
  game.stack:push(self)
  return self
end

function Screen:rows()
  local out = {}
  for area, link in pairs(links(self.game.save)) do
    out[#out + 1] = { area = area, link = link }
  end
  table.sort(out, function(a, b) return a.area < b.area end)
  return out
end

function Screen:update()
  local input = self.game.input
  if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
    self.game.stack:pop()
    return
  end
  local n = #self:rows()
  if input:wasPressed("down") then self.top = math.min(math.max(1, n - ROWS + 1), self.top + 1)
  elseif input:wasPressed("up") then self.top = math.max(1, self.top - 1) end
end

local function fit(text, n)
  -- translated, then cut to n letters (not bytes: an accent is two)
  return require("src.coop.CoopI18n").fit(text, n)
end

function Screen:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 3)
  Font.draw("SOUL LINKS " .. (CoopManager.soulLink and "ON" or "OFF"), 8, 8)
  Font.drawBox(0, 3, 20, 15)
  local rows = self:rows()
  local game = self.game
  if #rows == 0 then
    Font.draw("NO PAIRS YET.", 8, 40)
    Font.draw("CATCH ONE IN A", 8, 56)
    Font.draw("NEW AREA!", 8, 64)
  end
  for i = 0, ROWS - 1 do
    local r = rows[self.top + i]
    if not r then break end
    local y = 32 + i * 18
    local label = CoopManager.mapLabel and CoopManager.mapLabel(r.area) or r.area
    if r.link.dead then label = fit(label, 13) .. " LOST" end
    Font.draw(fit(label, 18), 8, y)
    local mine = r.link.mine and findMon(game.save, r.link.mine)
    local a = r.link.mine and monName(game, mine, r.link.mineSpecies) or "-----"
    local b = r.link.theirs and (r.link.theirName or monName(game, nil, r.link.theirSpecies)) or "-----"
    Font.draw(fit(a, 8) .. "/" .. fit(b, 9), 8, y + 8)
  end
  if self.top + ROWS - 1 < #rows then Font.drawCode(0xEE, 144, 128) end
end

CoopSoulLink.Screen = Screen

return CoopSoulLink
