-- src/coop/CoopCrossStory.lua
-- GOLD / SILVER AND CRYSTAL SHARE THE STORY (nightly.2, EXPERIMENTAL,
-- capability "story.cross", rule "G/S+C STORY", off by default).
--
-- The two number their event flags apart -- Crystal's list is Gold's with
-- rows inserted all through it -- so the story was not shared between them
-- at all (CoopManager.storyCompatible).  With the rule on, an event lived on
-- one is passed to the other with each EVENT_G2_#### flag translated to the
-- same event on the other cartridge (src/coop/CoopFlagMap.lua, built by name
-- from pret's pokegold / pokecrystal constants: 1159 events in both).
--
-- LIMITATIONS, said in the menu: a flag with no twin on the other cartridge
-- is dropped, and so is what is laid out differently on each -- map scenes,
-- raw WRAM, special calls, object sprites and the roaming beasts.  Items,
-- money, coins, named engine flags and trainers beaten do cross.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local CoopCrossStory = {}
CoopCrossStory.CAP = "story.cross"
CoopManager.registerCap(CoopCrossStory.CAP)
CoopManager.addRule("crossStory", "G/S+C STORY", false)

local map, back = nil, nil
local function tables()
  if not map then
    local ok, m = pcall(require, "src.coop.CoopFlagMap")
    map = ok and type(m) == "table" and m.g2c or {}
    back = {}
    for g, c in pairs(map) do back[c] = g end
  end
  return map, back
end

local function isCrystal(game)
  local GV = package.loaded["src.core.GameVersion"]
  if not GV then return false end
  if game then return GV.isCrystal(game) end
  return GV.isCrystal()
end

-- the two cartridges differ (one Crystal, one Gold/Silver) and the rule is on
function CoopCrossStory.active()
  local GV = package.loaded["src.core.GameVersion"]
  local theirs = CoopManager.partner and CoopManager.partner.game
  if not (GV and GV.isGen2 and GV.isGen2() and type(theirs) == "string" and GV.isGen2(theirs)) then return false end
  if isCrystal() == isCrystal(theirs) then return false end
  return CoopManager.crossStory == true and CoopManager.bothHave(CoopCrossStory.CAP)
end

-- the same event's flag on this cartridge, or nil (no twin)
function CoopCrossStory.flag(id)
  if type(id) ~= "string" then return id end
  local n = tonumber(id:match("^EVENT_G2_(%d+)$"))
  if not n then
    -- an unnamed engine flag is a raw row number, laid out apart too
    if id:match("^FLAG_G2_%d+$") then return nil end
    return id
  end
  local g2c, c2g = tables()
  local to = isCrystal() and g2c[n] or c2g[n]
  return to and string.format("EVENT_G2_%04d", to) or nil
end

local DROP = { scene = true, scene_key = true, wram = true, special_call = true, var_sprite = true,
               roam_release = true }

-- a partner's story event, made this cartridge's (in place); how many dropped
function CoopCrossStory.translate(msg)
  if type(msg) ~= "table" or type(msg.rewards) ~= "table" then return 0 end
  local out, dropped = {}, 0
  for _, r in ipairs(msg.rewards) do
    if DROP[r.kind] then
      dropped = dropped + 1
    elseif r.kind == "set_flag" or r.kind == "clear_flag" then
      local id = CoopCrossStory.flag(r.id)
      if id then
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        c.id = id
        out[#out + 1] = c
      else
        dropped = dropped + 1
      end
    else
      out[#out + 1] = r
    end
  end
  msg.rewards = out
  if dropped > 0 then CoopLog.info("STORY", string.format("cross-version: %d piece(s) with no twin dropped", dropped)) end
  return dropped
end

-- CoopManager.storyCompatible: the other cartridge too, with the rule on
local compatible = CoopManager.storyCompatible
CoopManager.storyCompatible = function(theirGame, ...)
  if compatible(theirGame, ...) then return true end
  if theirGame and theirGame ~= (CoopManager.partner and CoopManager.partner.game) then return false end
  return CoopCrossStory.active()
end

return CoopCrossStory
