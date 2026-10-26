-- src/coop/CoopDayCare.lua
-- SHARE DAY CARE: BREEDING ACROSS THE TWO GAMES.  With the rule on, when your
-- Route 34 DAY-CARE boards ONE Pokemon and your partner's boards one too,
-- the partner's counts as the second parent at yours (and yours at theirs):
-- the old man's "they seem to get along", the egg, its moves and DVs are the
-- cartridge's own, worked out with the pair.  Each game lays its OWN egg.
--
-- Nobody's Pokemon ever leaves its save: what crosses is a copy, used only
-- by the breeding sums (DayCare.pair / parents / compatibility / eggSpecies /
-- inheritMoves / step and Gen2Breeding.inheritDVs, wrapped in lib/Hooks.lua).
-- The DAY-CARE's own talk -- "your X is doing fine", taking it back -- only
-- ever sees your own.  A pair from different trainers is the cartridge's
-- better match, so a friend's Pokemon breeds faster than your own two.
--
-- The copy is kept in the save (save.coopDayCareMate), so the pair keeps
-- walking when you play apart; it changes when the partner's day care does,
-- and goes when the rule is switched off or the save links with another
-- partner (the copy names the partner save it came from).
--
-- Wire: coop_daycare { mon } (nil: nothing boarded at theirs).

local CoopManager = require("src.coop.CoopManager")

local CoopDayCare = {}

local MAN, LADY = 1, 2

local function send(msg)
  if CoopManager.connected and CoopManager.net then CoopManager.net:send(msg) end
end

local function DC()
  return require("src.pokemon.DayCare")
end

-- the one Pokemon boarded here (not an egg), or nil when none or two
function CoopDayCare.lone(save, mon)
  mon = mon or DC().mon
  local a, b = mon(save, MAN), mon(save, LADY)
  if a and b then return nil end
  local one = a or b
  if one and not one.isEgg then return one, a and LADY or MAN end
  return nil
end

-- DayCare.mon, while a breeding sum is being worked out: the empty pen holds
-- the partner's Pokemon
CoopDayCare.scope = nil
function CoopDayCare.mon(original, save, which)
  local mon = original(save, which)
  if mon or CoopDayCare.scope ~= save then return mon end
  if which ~= MAN and which ~= LADY then return nil end
  local mate = type(save.coopDayCareMate) == "table" and save.coopDayCareMate.mon
  if type(mate) ~= "table" then return nil end
  local own, empty = CoopDayCare.lone(save, original)
  if own and empty == which then return mate end
  return nil
end

-- run fn with the partner's Pokemon standing in the empty pen of `save`
function CoopDayCare.within(save, fn, ...)
  local prev = CoopDayCare.scope
  CoopDayCare.scope = save
  local r = { pcall(fn, ...) }
  CoopDayCare.scope = prev
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2, table.maxn(r))
end

-- what our day care boards, for the partner
local function signature(save)
  local one = CoopDayCare.lone(save)
  if not one then return "-" end
  return tostring(one.species) .. ":" .. tostring(one.otId) .. ":" .. tostring(one.level)
         .. ":" .. tostring(one.dvs and one.dvs.attack) .. tostring(one.dvs and one.dvs.special)
end

function CoopDayCare.announce(save)
  local one = CoopDayCare.lone(save)
  send({ type = "coop_daycare", mon = one and CoopManager.wireMon(one) or nil })
end

CoopManager.handlers.coop_daycare = function(ow, msg)
  local game = CoopManager.getGame(ow)
  local save = game and game.save
  if not save then return end
  if not CoopManager.shareDayCare then return end
  local name = CoopManager.partner.name or "PARTNER"
  local had = type(save.coopDayCareMate) == "table" and save.coopDayCareMate.mon
  if type(msg.mon) == "table" and msg.mon.species then
    local mon = CoopManager.wireMon(msg.mon)
    mon.isEgg = nil
    save.coopDayCareMate = { partner = name, partnerId = CoopManager.partner.id, mon = mon }
    if not had and CoopDayCare.lone(save) then
      local def = game.data.pokemon and game.data.pokemon[mon.species]
      CoopManager.showStatus(("%s's %s joins your DAY-CARE"):format(name, (def and def.name) or "POKéMON"), 4)
    end
  else
    save.coopDayCareMate = nil
  end
end

CoopManager.addRule("shareDayCare", "LINK DAYCARE", false, function(on)
  local game = CoopManager.getGame()
  local save = game and game.save
  if not save then return end
  if on then
    CoopDayCare.sent = nil -- announce on the next frame
  else
    save.coopDayCareMate = nil
  end
end)

-- tell the partner whenever what we board changes (and once per link)
CoopManager.onTick("daycare", function(dt, game)
  local save = game and game.save
  if not (save and CoopManager.shareDayCare) then return end
  local mate = save.coopDayCareMate
  if type(mate) == "table" and mate.partnerId and CoopManager.partner.id
     and mate.partnerId ~= CoopManager.partner.id then
    -- linked with someone else now: the last partner's Pokemon is not theirs
    save.coopDayCareMate = nil
  end
  CoopDayCare.timer = (CoopDayCare.timer or 0) - dt
  if CoopDayCare.timer > 0 and CoopDayCare.serial == CoopManager.linkSerial then return end
  CoopDayCare.timer = 1
  local sig = signature(save)
  if sig ~= CoopDayCare.sent or CoopDayCare.serial ~= CoopManager.linkSerial then
    CoopDayCare.sent = sig
    CoopDayCare.serial = CoopManager.linkSerial
    CoopDayCare.announce(save)
  end
end)

return CoopDayCare
