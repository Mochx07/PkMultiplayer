-- Authentic pixel-perfect micro font for 160x144 Game Boy resolution.
-- Replaces ugly fractional scaling of 8x8 font with a dedicated 4x5/5x5 pixel font
-- that renders 1:1 with integer pixels: zero deformation, zero blur, 100% crisp.

local MicroFont = {}

local GLYPH_WIDTHS = {
  ["I"] = 3, ["1"] = 3, [":"] = 2, ["."] = 2, ["!"] = 2, ["?"] = 3, ["-"] = 3,
  ["<"] = 3, [">"] = 3, ["#"] = 5, ["*"] = 5, ["("] = 2, [")"] = 2,
  ["M"] = 5, ["T"] = 5, ["V"] = 5, ["W"] = 5, ["Y"] = 5, [" "] = 2
}

local GLYPHS = {
  ["A"] = { 0x6, 0x9, 0xF, 0x9, 0x9 },
  ["B"] = { 0xE, 0x9, 0xE, 0x9, 0xE },
  ["C"] = { 0x7, 0x8, 0x8, 0x8, 0x7 },
  ["D"] = { 0xE, 0x9, 0x9, 0x9, 0xE },
  ["E"] = { 0xF, 0x8, 0xE, 0x8, 0xF },
  ["F"] = { 0xF, 0x8, 0xE, 0x8, 0x8 },
  ["G"] = { 0x7, 0x8, 0xB, 0x9, 0x7 },
  ["H"] = { 0x9, 0x9, 0xF, 0x9, 0x9 },
  ["I"] = { 0x7, 0x2, 0x2, 0x2, 0x7 },
  ["J"] = { 0x1, 0x1, 0x1, 0x9, 0x6 },
  ["K"] = { 0x9, 0xA, 0xC, 0xA, 0x9 },
  ["L"] = { 0x8, 0x8, 0x8, 0x8, 0xF },
  ["M"] = { 0x11, 0x1B, 0x15, 0x11, 0x11 },
  ["N"] = { 0x9, 0xD, 0xB, 0x9, 0x9 },
  ["O"] = { 0x6, 0x9, 0x9, 0x9, 0x6 },
  ["P"] = { 0xE, 0x9, 0xE, 0x8, 0x8 },
  ["Q"] = { 0x6, 0x9, 0x9, 0xB, 0x7 },
  ["R"] = { 0xE, 0x9, 0xE, 0xA, 0x9 },
  ["S"] = { 0x7, 0x8, 0x6, 0x1, 0xE },
  ["T"] = { 0x1F, 0x4, 0x4, 0x4, 0x4 },
  ["U"] = { 0x9, 0x9, 0x9, 0x9, 0x6 },
  ["V"] = { 0x11, 0x11, 0xA, 0xA, 0x4 },
  ["W"] = { 0x11, 0x11, 0x15, 0x1B, 0x11 },
  ["X"] = { 0x9, 0x9, 0x6, 0x9, 0x9 },
  ["Y"] = { 0x11, 0xA, 0x4, 0x4, 0x4 },
  ["Z"] = { 0xF, 0x1, 0x6, 0x8, 0xF },
  ["0"] = { 0x6, 0x9, 0x9, 0x9, 0x6 },
  ["1"] = { 0x2, 0x6, 0x2, 0x2, 0x7 },
  ["2"] = { 0xE, 0x1, 0x6, 0x8, 0xF },
  ["3"] = { 0xE, 0x1, 0x6, 0x1, 0xE },
  ["4"] = { 0x9, 0x9, 0xF, 0x1, 0x1 },
  ["5"] = { 0xF, 0x8, 0xE, 0x1, 0xE },
  ["6"] = { 0x7, 0x8, 0xE, 0x9, 0x6 },
  ["7"] = { 0xF, 0x1, 0x2, 0x4, 0x4 },
  ["8"] = { 0x6, 0x9, 0x6, 0x9, 0x6 },
  ["9"] = { 0x6, 0x9, 0x7, 0x1, 0xE },
  [":"] = { 0x0, 0x2, 0x0, 0x2, 0x0 },
  ["/"] = { 0x1, 0x2, 0x4, 0x8, 0x0 },
  ["-"] = { 0x0, 0x0, 0x7, 0x0, 0x0 },
  ["."] = { 0x0, 0x0, 0x0, 0x0, 0x2 },
  ["!"] = { 0x2, 0x2, 0x2, 0x0, 0x2 },
  ["?"] = { 0x6, 0x1, 0x2, 0x0, 0x2 },
  ["<"] = { 0x2, 0x4, 0x8, 0x4, 0x2 },
  [">"] = { 0x8, 0x4, 0x2, 0x4, 0x8 },
  ["#"] = { 0xA, 0x1F, 0xA, 0x1F, 0xA },
  ["*"] = { 0x4, 0x15, 0xE, 0x15, 0x4 },
  ["("] = { 0x2, 0x4, 0x4, 0x4, 0x2 },
  [")"] = { 0x8, 0x4, 0x4, 0x4, 0x8 },
  [" "] = { 0x0, 0x0, 0x0, 0x0, 0x0 },
}

local atlasImage = nil
local quads = {}
local initialized = false

function MicroFont.init()
  if initialized then return end
  initialized = true

  if not (love and love.image and love.graphics and love.graphics.newQuad) then
    return
  end

  local totalW = 0
  for ch, _ in pairs(GLYPHS) do
    local w = GLYPH_WIDTHS[ch] or 4
    totalW = totalW + w + 1
  end

  local ok, imgData = pcall(love.image.newImageData, math.max(64, totalW), 5)
  if not ok or not imgData then return end

  -- Clear to transparent
  imgData:mapPixel(function() return 0, 0, 0, 0 end)

  local curX = 0
  for ch, rows in pairs(GLYPHS) do
    local w = GLYPH_WIDTHS[ch] or 4
    for r = 1, 5 do
      local val = rows[r] or 0
      for c = w - 1, 0, -1 do
        local bit = math.floor(val / (2^c)) % 2
        if bit == 1 then
          imgData:setPixel(curX + (w - 1 - c), r - 1, 1, 1, 1, 1)
        end
      end
    end
    quads[ch] = love.graphics.newQuad(curX, 0, w, 5, imgData:getWidth(), 5)
    curX = curX + w + 1
  end

  atlasImage = love.graphics.newImage(imgData)
  if atlasImage and atlasImage.setFilter then
    atlasImage:setFilter("nearest", "nearest")
  end
end

-- The tiny font has 26 letters and no accents: a line is put in the
-- player's language first (src/coop/CoopI18n.lua), then each accented or
-- foreign letter is written as its plain one (Ñ as N, ¿ and ¡ dropped) --
-- one glyph per letter, never the two "?" its two UTF-8 bytes used to make.
local PLAIN = {
  ["á"] = "A", ["é"] = "E", ["í"] = "I", ["ó"] = "O", ["ú"] = "U", ["ü"] = "U", ["ñ"] = "N",
  ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ü"] = "U", ["Ñ"] = "N",
  ["¿"] = "", ["¡"] = "",
}

local function prepare(text)
  text = tostring(text)
  local ok, I18n = pcall(require, "src.coop.CoopI18n")
  if ok then text = I18n.t(text) end
  text = text:gsub("[\192-\255][\128-\191]*", function(ch) return PLAIN[ch] or "?" end)
  return text:upper()
end
MicroFont.prepare = prepare

function MicroFont.width(text)
  if not text then return 0 end
  text = prepare(text)
  local w = 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    local gw = GLYPH_WIDTHS[ch] or 4
    w = w + gw + 1
  end
  return math.max(0, w - 1)
end

function MicroFont.height()
  return 5
end

function MicroFont.draw(text, x, y)
  if not text then return 0 end
  text = prepare(text)
  if not initialized then MicroFont.init() end

  x = math.floor(x or 0)
  y = math.floor(y or 0)
  local penX = x

  if atlasImage and love.graphics and love.graphics.draw then
    for i = 1, #text do
      local ch = text:sub(i, i)
      local q = quads[ch] or quads["?"]
      local gw = GLYPH_WIDTHS[ch] or 4
      if q then
        love.graphics.draw(atlasImage, q, penX, y)
      end
      penX = penX + gw + 1
    end
  else
    -- Fallback: direct 1x1 rectangles for headless or mock environments
    for i = 1, #text do
      local ch = text:sub(i, i)
      local rows = GLYPHS[ch] or GLYPHS["?"]
      local gw = GLYPH_WIDTHS[ch] or 4
      if rows then
        for r = 1, 5 do
          local val = rows[r] or 0
          for c = gw - 1, 0, -1 do
            local bit = math.floor(val / (2^c)) % 2
            if bit == 1 and love.graphics and love.graphics.rectangle then
              love.graphics.rectangle("fill", penX + (gw - 1 - c), y + r - 1, 1, 1)
            end
          end
        end
      end
      penX = penX + gw + 1
    end
  end

  return penX - x
end

return MicroFont
