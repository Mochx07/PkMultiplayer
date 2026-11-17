-- src/coop/CoopFeed.lua
-- WHAT THE PARTNER JUST DID (nightly.2, capability "events.feed").  Their
-- catches, evolutions and hatched eggs used to happen in silence on your
-- screen (only SHARE DEX quietly added a SEEN entry).  Now each one is a
-- card that slides into the top-right corner of the map -- the partner's
-- colour, what happened -- and a burst over their avatar, so you look over.
--
-- From the engine's own events (main.lua subscribes): pokemon.caught,
-- pokemon.evolved, pokemon.egg_hatched.  A catch made together
-- (src/coop/CoopCatch.lua) is not repeated: both of you were there.

local CoopManager = require("src.coop.CoopManager")

local CoopFeed = {}

CoopFeed.CAP = "events.feed"
CoopFeed.SHOW = 4      -- seconds a card stays
CoopFeed.ROWS = 2      -- cards on screen at once
CoopFeed.queue = {}

CoopManager.registerCap(CoopFeed.CAP)

local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
local function I18n() return require("src.coop.CoopI18n") end

local function speciesName(game, id)
  local data = game and game.data
  local def = data and data.pokemon and data.pokemon[id]
  return string.upper(tostring((def and def.name) or id or "?"))
end

local function send(msg)
  if CoopManager.connected and CoopManager.net and CoopManager.bothHave(CoopFeed.CAP) then
    CoopManager.net:send(msg)
  end
end

-- the engine's events, on this player's game
function CoopFeed.onCaught(p)
  if type(p) ~= "table" then return end
  local battle = p.battle
  if type(battle) == "table" and battle.coopWild then return end
  local mon = p.mon
  local shiny = false
  if type(mon) == "table" then
    local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
    shiny = ok and Pokemon.isShiny and Pokemon.isShiny(mon) or false
  end
  send({ type = "coop_event", kind = "caught", species = p.species or (mon and mon.species),
         shiny = shiny or nil, nick = mon and mon.nickname or nil })
end

function CoopFeed.onEvolved(p)
  if type(p) ~= "table" then return end
  send({ type = "coop_event", kind = "evolved", from = p.fromSpecies, species = p.toSpecies,
         nick = type(p.mon) == "table" and p.mon.nickname or nil })
end

function CoopFeed.onHatched(p)
  local mon = type(p) == "table" and p.mon
  if type(mon) ~= "table" then return end
  send({ type = "coop_event", kind = "hatched", species = mon.species })
end

-- the line a card shows
function CoopFeed.line(game, e, who)
  who = I18n().truncate(string.upper(tostring(who or "PARTNER")), 7)
  local t = I18n().t
  if e.kind == "caught" then
    return string.format(t(e.shiny and "%s CAUGHT A SHINY %s!" or "%s CAUGHT %s!"), who, speciesName(game, e.species))
  elseif e.kind == "evolved" then
    return string.format(t("%s: %s EVOLVED INTO %s!"), who, speciesName(game, e.from), speciesName(game, e.species))
  elseif e.kind == "hatched" then
    return string.format(t("%s'S EGG HATCHED: %s!"), who, speciesName(game, e.species))
  end
  return nil
end

CoopManager.handlers.coop_event = function(ow, msg)
  if msg.kind ~= "caught" and msg.kind ~= "evolved" and msg.kind ~= "hatched" then return end
  local q = CoopFeed.queue
  q[#q + 1] = { kind = msg.kind, species = msg.species, from = msg.from, shiny = msg.shiny and true or nil,
                who = CoopManager.partner and CoopManager.partner.name }
  while #q > 6 do table.remove(q, 1) end
  -- the burst over their head
  CoopManager.partner.emote = msg.kind == "caught" and "exclaim" or "happy"
  CoopManager.partner.emoteTimer = 2.5
  local Sound = package.loaded["src.core.Sound"]
  local game = type(ow) == "table" and ow.game
  if Sound and Sound.play and type(game) == "table" and game.data then pcall(Sound.play, game.data, "Menu") end
end

-- the cards to show at time t (each one's clock starts on screen)
function CoopFeed.cards(t)
  local q = CoopFeed.queue
  for i = #q, 1, -1 do
    if q[i].at and t - q[i].at > CoopFeed.SHOW then table.remove(q, i) end
  end
  local live = {}
  for i, e in ipairs(q) do
    if i > CoopFeed.ROWS then break end
    e.at = e.at or t
    live[#live + 1] = e
  end
  return live
end

-- CoopManager.drawUI: over the map, top right, under the status line
function CoopFeed.draw(game, top)
  if not (love and love.graphics) then return end
  local t = clock()
  local cards = CoopFeed.cards(t)
  if #cards == 0 then return end
  local MicroFont = require("src.render.MicroFont")
  local g = love.graphics
  local col = CoopManager.partnerPalette and CoopManager.partnerPalette()[3] or { 40, 112, 248 }
  local y = (top or 0) + 2
  for _, e in ipairs(cards) do
    local text = CoopFeed.line(game, e, e.who) or ""
    -- two lines when it does not fit the corner
    local maxW = 118
    local lines = { text }
    if MicroFont.width(text) > maxW then
      local a, b = "", ""
      for word in text:gmatch("%S+") do
        if b == "" and MicroFont.width(a == "" and word or (a .. " " .. word)) <= maxW then
          a = a == "" and word or (a .. " " .. word)
        else
          b = b == "" and word or (b .. " " .. word)
        end
      end
      lines = { a, b }
    end
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, MicroFont.width(l)) end
    w = w + 12
    local h = #lines * 7 + 4
    local age = t - e.at
    local slide = math.max(0, math.min(1, age / 0.2, (CoopFeed.SHOW - age) / 0.2))
    local x = math.floor(160 - (w + 2) * slide)
    if CoopManager.drawPill then CoopManager.drawPill(x, y, w, h) end
    g.setColor(col[1] / 255, col[2] / 255, col[3] / 255, 1)
    g.rectangle("fill", x + 3, y + 3, 4, h - 6)
    if e.shiny then
      g.setColor(240 / 255, 200 / 255, 0, 1)
      g.rectangle("fill", x + 3, y + 3, 4, 2)
    end
    g.setColor(0, 0, 0, 1)
    for i, l in ipairs(lines) do MicroFont.draw(l, x + 9, y + 2 + (i - 1) * 7) end
    y = y + h + 2
  end
  g.setColor(1, 1, 1, 1)
end

return CoopFeed
