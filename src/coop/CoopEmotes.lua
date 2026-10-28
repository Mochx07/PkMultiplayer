-- src/coop/CoopEmotes.lua
-- Co-op emotes, in one place: which there are, how they look, where they
-- hang, and the quick picker.
--
-- They are the cartridge's own bubbles -- the same sheet the field draws a
-- trainer's "!" from (field.emotionBubbles; Gen 2's eight are exported by
-- RomExtractorGen2) -- hung where the field hangs them: centred, sixteen
-- pixels above the owner's centre, with the bubble's little pop-in bounce.
-- A dataset without the sheet (no ROM imported for the mod) falls back to
-- this mod's own drawn bubbles, the same size and anchor.
--
-- Ids stay the ones the link already speaks ("exclaim", "heart", ...), so an
-- older partner still understands them; the two whose art changed map on
-- (music -> happy, star -> bolt).

local CoopEmotes = {}

CoopEmotes.LIST = {
  { id = "exclaim",  bubble = 1, sym = "!",  name = "SHOCK" },
  { id = "question", bubble = 2, sym = "?",  name = "QUESTION" },
  { id = "happy",    bubble = 3, sym = ":)", name = "HAPPY" },
  { id = "sad",      bubble = 4, sym = ":(", name = "SAD" },
  { id = "heart",    bubble = 5, sym = "<3", name = "HEART" },
  { id = "bolt",     bubble = 6, sym = "#",  name = "ANGRY" },
  { id = "sleep",    bubble = 7, sym = "Z",  name = "SLEEPY" },
}
local ALIAS = { music = "happy", star = "bolt" }

CoopEmotes.DURATION = 2.5

-- Emotes of this mod's own, outside the picker and with no bubble on the
-- cartridge's sheet: always this mod's drawn bubble.  HIGH FIVE from the
-- partner menu used to send the heart ("I don't like the emoji").
CoopEmotes.EXTRA = {
  { id = "highfive", sym = "o/", name = "HIGH FIVE" },
}

local byId = {}
for _, e in ipairs(CoopEmotes.LIST) do byId[e.id] = e end
for _, e in ipairs(CoopEmotes.EXTRA) do byId[e.id] = e end

-- THE NUMBER PAD SENDS AN EMOTE AT ONCE (requested from play: "quick access
-- to the emojis, the number pad for each one"): 1-7 the picker's seven, in
-- its order, and 8 the high five.
CoopEmotes.QUICK = { "exclaim", "question", "happy", "sad", "heart", "bolt", "sleep", "highfive" }

-- the emote on key `key` ("kp1".."kp8"), or nil
function CoopEmotes.quickKey(key)
  local n = tonumber(tostring(key or ""):match("^kp(%d)$"))
  return n and CoopEmotes.QUICK[n] or nil
end

function CoopEmotes.get(id)
  if type(id) ~= "string" then return nil end
  return byId[ALIAS[id] or id]
end

function CoopEmotes.valid(id)
  return CoopEmotes.get(id) ~= nil
end

local sheetCache = {}
local function sheet(game)
  local field = game and game.data and game.data.field
  local def = field and field.emotionBubbles
  if not (def and def.path and def.bubbles) then return nil end
  local hit = sheetCache[def.path]
  if hit == nil then
    local ok, img = pcall(function()
      local Assets = require("src.render.Assets")
      if not (love.image and love.image.newImageData) then return Assets.image(def.path) end
      -- the field's own OBJ-palette pass (OverworldController obpEmoteImage):
      -- colours 0/1 -> white, 2 -> light grey, 3 -> black, so these match
      -- the trainers' "!" exactly
      local id = Assets.imageData(def.path)
      id:mapPixel(function(_, _, r, _, _, a)
        local v = 0
        if r > 0.5 then v = 1 elseif r > 0.17 then v = 170 / 255 end
        return v, v, v, a
      end)
      local made = love.graphics.newImage(id)
      made:setFilter("nearest", "nearest")
      return made
    end)
    hit = (ok and img) or false
    sheetCache[def.path] = hit
  end
  if not hit then return nil end
  return hit, def.bubbles
end

local quads = {}
local function quadFor(img, rect, key)
  local q = quads[key]
  if not q then
    q = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, img:getDimensions())
    quads[key] = q
  end
  return q
end

-- the field bubble's pop: up a few pixels and settle (frames since shown)
local function bounce(age)
  local t = math.floor((age or 0) * 60)
  if t < 4 then return -t end
  if t < 8 then return -(8 - t) end
  return 0
end

-- Draw emote `id` for an entity whose screen-space feet are at (fx, fy)
-- (bottom-centre of a 16x16 walker) and that has been up for `age` seconds.
function CoopEmotes.draw(game, id, fx, fy, age)
  local e = CoopEmotes.get(id)
  if not e then return end
  local cx = math.floor(fx)
  -- the owner's centre is 8 above the feet; the bubble's centre 16 above that
  local cy = math.floor(fy - 8 - 16 + bounce(age))
  local img, bubbles = sheet(game)
  local rect = bubbles and e.bubble and bubbles[e.bubble]
  if img and rect then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, quadFor(img, rect, tostring(img) .. e.bubble),
                       cx - math.floor(rect.w / 2), cy - math.floor(rect.h / 2))
    return
  end
  -- no sheet: this mod's own drawn bubble, same size and anchor
  local drawn = CoopEmotes.drawnBubble(e.id)
  if drawn then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(drawn, cx - 8, cy - 8)
  end
end

-- ---------------------------------------------------------------------
-- The drawn bubbles, for a game without the cartridge's sheet (the MODS
-- panel's optional ROM import gives the real ones; lib/Emotes.lua).  This
-- mod's own 16x16 art, in the field's OBJ shades: # black, + grey, o white,
-- . clear.  The bubble is shared; each emote paints a 10x10 symbol into it.
-- ---------------------------------------------------------------------

local BUBBLE = {
  "..############..",
  ".#oooooooooooo#.",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  "#oooooooooooooo#",
  ".#oooooooooooo#.",
  "..##oooo#######.",
  "....#oo#........",
  ".....##.........",
}

local SYMBOLS = {
  exclaim = {
    "....##....",
    "...####...",
    "...####...",
    "...####...",
    "....##....",
    "....##....",
    "..........",
    "....##....",
    "....##....",
    "..........",
  },
  question = {
    "...####...",
    "..##..##..",
    "......##..",
    ".....##...",
    "....##....",
    "....##....",
    "..........",
    "....##....",
    "....##....",
    "..........",
  },
  happy = {
    "..........",
    "..#....#..",
    ".#+#..#+#.",
    "..........",
    ".#......#.",
    ".##....##.",
    "..######..",
    "...####...",
    "..........",
    "..........",
  },
  sad = {
    "..........",
    ".#......#.",
    "..##..##..",
    "..........",
    "...+..+...",
    "..........",
    "...####...",
    "..#....#..",
    ".#......#.",
    "..........",
  },
  heart = {
    "..........",
    ".##...##..",
    "#++#.####.",
    "#+#######.",
    "#########.",
    ".#######..",
    "..#####...",
    "...###....",
    "....#.....",
    "..........",
  },
  bolt = {
    "......##..",
    ".....##...",
    "....##....",
    "...######.",
    "......##..",
    ".....##...",
    "....##....",
    "...##.....",
    "..##......",
    "..........",
  },
  -- an open hand, palm out: four fingers and the thumb
  highfive = {
    ".#.#.#.#..",
    "#+#+#+#+#.",
    "#+#+#+#+#.",
    "#+#+#+#+#.",
    "#+++++++##",
    "#++++++++#",
    "#+++++++#.",
    ".#+++++#..",
    "..#####...",
    "..........",
  },
  sleep = {
    "..........",
    ".######...",
    ".....##...",
    "....##....",
    "...##.....",
    "..##......",
    ".######.#.",
    ".......##.",
    "......#.#.",
    "..........",
  },
}

local drawnCache = {}

-- The drawn bubble for emote `id` as 16x16 ImageData (nil without
-- love.image).  lib/Emotes.lua lays these out as the field's sheet when no
-- ROM was imported, so a trainer's "!" wears the same bubble as the co-op's.
function CoopEmotes.drawnBubbleData(id)
  local e = CoopEmotes.get(id)
  local sym = e and SYMBOLS[e.id]
  if not (sym and love and love.image and love.image.newImageData) then return nil end
  local ok, data = pcall(function()
    local data = love.image.newImageData(16, 16)
    local shade = { ["#"] = 0, ["+"] = 170 / 255, ["o"] = 1 }
    local function put(x, y, ch)
      local v = shade[ch]
      if v then data:setPixel(x, y, v, v, v, 1) end
    end
    for y, row in ipairs(BUBBLE) do
      for x = 1, 16 do put(x - 1, y - 1, row:sub(x, x)) end
    end
    for y, row in ipairs(sym) do
      for x = 1, 10 do
        if row:sub(x, x) ~= "." then put(x + 2, y + 1, row:sub(x, x)) end
      end
    end
    return data
  end)
  return ok and data or nil
end

-- The emote that sits in slot `i` of the field's sheet (EMOTE_* order).
function CoopEmotes.forBubble(i)
  for _, e in ipairs(CoopEmotes.LIST) do
    if e.bubble == i then return e end
  end
  return nil
end

-- The drawn bubble for emote `id` as an Image (nil without a renderer).
function CoopEmotes.drawnBubble(id)
  local e = CoopEmotes.get(id)
  if not e then return nil end
  local hit = drawnCache[e.id]
  if hit ~= nil then return hit or nil end
  local ok, img = pcall(function()
    local made = love.graphics.newImage(assert(CoopEmotes.drawnBubbleData(e.id)))
    made:setFilter("nearest", "nearest")
    return made
  end)
  drawnCache[e.id] = (ok and img) or false
  return drawnCache[e.id] or nil
end

-- ---------------------------------------------------------------------
-- the quick picker: a strip of bubbles along the top, LEFT/RIGHT and A
-- ---------------------------------------------------------------------

local Picker = {}
Picker.__index = Picker
Picker.isOpaque = false
Picker.isEmotePicker = true

function CoopEmotes.newPicker(game, onPick)
  return setmetatable({ game = game, onPick = onPick, index = 1, timer = 0 }, Picker)
end

function Picker:update(dt)
  self.timer = self.timer + (dt or 0.016)
  local input = self.game.input
  if not input then return end
  local n = #CoopEmotes.LIST
  if input:wasPressed("left") or input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("right") or input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  elseif input:wasPressed("a") and self.timer > 0.1 then
    self.game.stack:pop()
    if self.onPick then self.onPick(CoopEmotes.LIST[self.index].id) end
  end
end

function Picker:draw()
  local Font = require("src.coop.CoopI18n").font()
  local n = #CoopEmotes.LIST
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 20, 7)
  local step = 20
  local x0 = math.floor((160 - (n - 1) * step) / 2)
  local MicroFont = require("src.render.MicroFont")
  for i = 1, n do
    -- feet at y=40 puts each bubble's centre at y=16
    CoopEmotes.draw(self.game, CoopEmotes.LIST[i].id, x0 + (i - 1) * step, 40, 1)
    -- its number-pad key, under the name row
    love.graphics.setColor(0, 0, 0, 1)
    MicroFont.draw(tostring(i), x0 + (i - 1) * step - 1, 43)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- the cursor under the picked one, and its name
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(0xEE, x0 + (self.index - 1) * step - 4, 24)
  Font.draw(CoopEmotes.LIST[self.index].name, 8, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

function CoopEmotes.openPicker(game)
  local ok, CM = pcall(require, "src.coop.CoopManager")
  if not (ok and CM and (CM.connected or CM.chatRoute)) then return false end
  local top = game.stack:top()
  if top and top.isEmotePicker then return false end
  game.stack:push(CoopEmotes.newPicker(game, function(id) CM.sendEmote(id) end))
  return true
end

return CoopEmotes
