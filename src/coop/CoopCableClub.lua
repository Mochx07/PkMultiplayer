-- src/coop/CoopCableClub.lua
-- THE CABLE CLUB WITH YOUR PARTNER (nightly.3, B6).
--
-- On Red / Blue / Yellow the Cable Club receptionist (2F of every POKeMON
-- CENTER) saves the game and opens the engine's own link door
-- (src/online/LinkRooms.lua: the LINK screen's HOST / JOIN, a code to read
-- out, a second connection).  Two co-op players are already linked, so with
-- the partner on the line she asks first who to link with:
--
--   * the partner's name: TRADE CENTER or COLOSSEUM, and the partner is
--     asked on their screen (CoopLink: the same trade / P1-vs-P2 battle the
--     co-op menu offers, through the co-op link -- no code, no address);
--   * OTHER: the engine's link door as before, for anybody else.
--
-- Only the receptionist's door is taken over (room "any" with no phase and
-- no role: the Gen 1 path, OverworldState:cableClubReceptionist).  Gen 2's
-- and Gen 3's scripts open the door with phase "connect" and keep walking
-- their own room script afterwards; those are left to the engine.
local CoopCableClub = {}

local function manager()
  return package.loaded["src.coop.CoopManager"]
end

local function isGen1()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.isGen1 and GV.isGen1() == true
end

-- is this LinkRooms.open call the Gen 1 receptionist's, with a partner on
-- the line?
function CoopCableClub.applies(room, opts)
  if room ~= "any" then return false end
  if type(opts) == "table" and (opts.phase ~= nil or opts.role ~= nil) then return false end
  if not isGen1() then return false end
  local CM = manager()
  return CM ~= nil and CM.isConnected ~= nil and CM.isConnected() == true
end

-- the rows of the question, for the screen and for the tests
function CoopCableClub.rows(partnerName)
  local name = string.upper(tostring(partnerName or "PARTNER"))
  if #name > 10 then name = name:sub(1, 10) end
  return { name, "OTHER" }
end

local function i18nMenu()
  return require("src.coop.CoopI18n").menu()
end

local function pickRoom(game, onPicked, onBack)
  local Menu = i18nMenu()
  game.stack:push(Menu.new(game, {
    { label = "TRADE CENTER", onSelect = function() onPicked("trade") end },
    { label = "COLOSSEUM", onSelect = function() onPicked("battle") end },
  }, { tx = 4, ty = 5, tw = 15, header = "WHICH ROOM?", cancelable = true, onCancel = onBack }))
end

-- `open` is the engine's LinkRooms.open, for OTHER
function CoopCableClub.open(game, open, room, opts, onDone)
  local CM = manager()
  local rows = CoopCableClub.rows(CM and CM.partner and CM.partner.name)
  local Menu = i18nMenu()
  local function other()
    return open(game, room, opts, onDone)
  end
  local function back()
    -- B on the question: the receptionist's "Please come again!"
    if onDone then onDone("noconnect") end
  end
  game.stack:push(Menu.new(game, {
    { label = rows[1], onSelect = function()
      pickRoom(game, function(mode)
        local CoopLink = require("src.coop.CoopLink")
        if not CoopLink.invite(game, mode) and onDone then onDone("noconnect") end
      end, back)
    end },
    { label = rows[2], onSelect = other },
  }, { tx = 4, ty = 4, tw = 15, header = "LINK WITH", cancelable = true, onCancel = back }))
  return true
end

return CoopCableClub
