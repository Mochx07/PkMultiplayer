-- (tests/patch_cache.lua's PKM_PRE) a LOVE that can hash and keep files, so
-- main.lua turns the patch cache on the way it does in the real game
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local bit = require("bit")
love.data = love.data or {}
-- stands in for md5: FNV-1a, as raw bytes
love.data.hash = function(_, text)
  local h = 0x811C9DC5
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    if h < 0 then h = h + 0x100000000 end
    h = (h * 0x193 + (h * 0x100) % 0x10000 * 0x10000) % 0x100000000
  end
  return string.char(math.floor(h / 0x1000000) % 256, math.floor(h / 0x10000) % 256,
                     math.floor(h / 0x100) % 256, h % 256) .. #text
end
love.data.encode = function(_, _, raw)
  return (raw:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end
