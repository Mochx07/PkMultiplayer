-- src/coop/CoopI18n.lua
-- THE MOD'S OWN WORDS IN THE PLAYER'S LANGUAGE.  MODS -> PkMultiplayer ->
-- OPTIONS -> LANGUAGE / IDIOMA: AUTO follows the game's translation (Spanish
-- when the launcher translates the game to Spanish), or ENGLISH / ESPAÑOL.
--
-- The English text stays where it is written and doubles as the key, the
-- way the engine's Strings() works, so an untranslated line simply shows in
-- English.  Translation happens where text reaches the screen -- the status
-- line, the mod's menus, boxes and text boxes, through the proxies below --
-- not at every literal: a line put together at run time ("TOBY is busy")
-- is matched against templates in the catalog ("%s is busy"), and the
-- pieces it was built from land in the translation in the same order.
--
-- What players type (chat) and the partner's own story text are never put
-- through it.
--
-- A letter the game's font has no pixels for (á, ñ, ¿... -- the English
-- cartridge's font has only é) is written without its accent, and ¿ / ¡ are
-- dropped, instead of turning into a gap.  With a font page that has them
-- (a Spanish glyph mod) they are drawn as they are.

local I18n = {}

I18n.catalogs = {}
do
  local ok, es = pcall(require, "src.coop.CoopLangES")
  if ok and type(es) == "table" then I18n.catalogs.es = es end
end

-- "auto" | "en" | "es"; tests set it directly
I18n.forced = nil

function I18n.language()
  local choice = I18n.forced
  if not choice then
    local o = package.loaded["pkmultiplayer.options"]
    choice = o and o.get and o.get("language") or "auto"
  end
  if choice == "en" or choice == "es" then return choice end
  local S = package.loaded["src.translation.Service"]
  if S and S.language == "es" then return "es" end
  return "en"
end

-- ------------------------------------------------------------ templates

-- the mod's words that are put into other lines
I18n.PIECES = {
  Partner = true, partner = true, PARTNER = true, ON = true, OFF = true,
  TRADE = true, BATTLE = true,
  ["STORY SYNC"] = true, ["TEAM UP WILD"] = true, ["SHARE DEX"] = true,
  ["LINK DAYCARE"] = true, ["PARTNER HEAL"] = true, ["PARTNER HEALS"] = true,
  ["SOUL LINK"] = true, ["BALANCED FOES"] = true, ["HARD FOES"] = true,
}

local function escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- "%s used %s on %s!" -> pattern, and how many pieces it takes
local function compile(key)
  local out, n, pos = { "^" }, 0, 1
  while true do
    local a, b, spec = key:find("%%(%d*[sd])", pos)
    if not a then break end
    out[#out + 1] = escape(key:sub(pos, a - 1))
    out[#out + 1] = spec:sub(-1) == "d" and "(%-?%d+)" or "(.-)"
    n = n + 1
    pos = b + 1
  end
  if n == 0 then return nil end
  out[#out + 1] = escape(key:sub(pos)) .. "$"
  return table.concat(out), n
end

local templates = {}   -- lang -> sorted list of { pattern, n, to }

local function templatesFor(lang)
  if templates[lang] then return templates[lang] end
  local list = {}
  for key, to in pairs(I18n.catalogs[lang] or {}) do
    if type(key) == "string" and type(to) == "string" and key:find("%%%d*[sd]") then
      local pattern, n = compile(key)
      if pattern then
        -- the more fixed text a template has, the sooner it is tried
        list[#list + 1] = { pattern = pattern, n = n, to = to,
                            fixed = #key:gsub("%%%d*[sd]", "") }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.fixed ~= b.fixed then return a.fixed > b.fixed end
    return a.pattern < b.pattern
  end)
  templates[lang] = list
  return list
end

local function fill(to, pieces)
  local i = 0
  return (to:gsub("%%(%d*)([sd])", function(index, _)
    i = i + 1
    local k = tonumber(index) or i
    return tostring(pieces[k] or "")
  end))
end

local function lookup(lang, text)
  local cat = I18n.catalogs[lang]
  if not cat then return nil end
  local hit = cat[text]
  if type(hit) == "string" then return hit end
  for _, t in ipairs(templatesFor(lang)) do
    local pieces = { text:match(t.pattern) }
    if #pieces == t.n and pieces[1] ~= nil then
      -- a piece that is one of the mod's own words ("Partner", a rule's
      -- name, ON) is translated too; a player's name never is
      for i, p in ipairs(pieces) do
        local inner = I18n.PIECES[p] and cat[p]
        if type(inner) == "string" then pieces[i] = inner end
      end
      return fill(t.to, pieces)
    end
  end
  return nil
end

-- --------------------------------------------------------- the glyphs

local FOLD = {
  ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
  ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ü"] = "U", ["Ñ"] = "N",
  ["¿"] = "", ["¡"] = "",
}

local drawable = {}
local cache = { lang = nil, n = 0, map = {} }
local function canDraw(ch)
  local known = drawable[ch]
  if known ~= nil then return known end
  local ok, Font = pcall(require, "src.render.Font")
  local yes = false
  if ok and Font.split then
    local okS, spans = pcall(Font.split, ch)
    yes = okS and type(spans) == "table" and #spans == 1 and spans[1].code ~= nil
  end
  drawable[ch] = yes
  return yes
end

-- forget what the font could draw (a glyph page registered later)
function I18n.resetGlyphs()
  drawable = {}
  cache = { lang = nil, n = 0, map = {} }
end

-- the text, with the letters this font cannot draw written plainly
function I18n.fitGlyphs(text)
  if not text:find("[\195\194]") then return text end
  return (text:gsub("[\194\195][\128-\191]", function(ch)
    if FOLD[ch] == nil or canDraw(ch) then return ch end
    return FOLD[ch]
  end))
end

-- ------------------------------------------------------------ the call

-- `text` in the player's language (unchanged when there is no translation)
function I18n.t(text)
  if type(text) ~= "string" or text == "" then return text end
  local lang = I18n.language()
  if lang == "en" then return text end
  if cache.lang ~= lang then cache.lang, cache.n, cache.map = lang, 0, {} end
  local hit = cache.map[text]
  if hit then return hit end
  local out = lookup(lang, text)
  if not out and (text:find("\f", 1, true) or text:find("\n", 1, true)) then
    -- page by page, then line by line
    local sep = text:find("\f", 1, true) and "\f" or "\n"
    local parts, changed = {}, false
    for part in (text .. sep):gmatch("(.-)" .. sep) do
      local tr = (part ~= "" and (lookup(lang, part) or (sep == "\f" and I18n.t(part)))) or part
      if tr ~= part then changed = true end
      parts[#parts + 1] = tr
    end
    if changed then out = table.concat(parts, sep) end
  end
  out = I18n.fitGlyphs(out or text)
  if cache.n > 4000 then cache.n, cache.map = 0, {} end
  cache.map[text] = out
  cache.n = cache.n + 1
  return out
end

-- `text` translated and cut to `n` letters
function I18n.fit(text, n)
  text = I18n.t(tostring(text or ""))
  if not n then return text end
  local count, cut = 0, #text
  for pos in text:gmatch("()[^\128-\191]") do
    count = count + 1
    if count > n then cut = pos - 1 break end
  end
  return text:sub(1, cut)
end

-- Lines written to be read together (the RULES help, three short lines):
-- translated as one block, and the translation's own lines handed back.
function I18n.lines(list)
  if type(list) ~= "table" or I18n.language() == "en" then return list end
  local joined = table.concat(list, "\n")
  local out = I18n.t(joined)
  if out == joined then
    local each = {}
    for i, l in ipairs(list) do each[i] = I18n.t(l) end
    return each
  end
  local lines = {}
  for l in (out .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  return lines
end

-- ------------------------------------------------------------ proxies

-- Font, translating what it draws and measures.  Each proxy looks its
-- module up on every call (a test, or another mod, may swap it).
local function live(name)
  return function(_, k) return require(name)[k] end
end

local fontProxy
function I18n.font()
  if fontProxy then return fontProxy end
  fontProxy = setmetatable({
    draw = function(text, ...) return require("src.render.Font").draw(I18n.t(text), ...) end,
    width = function(text, ...) return require("src.render.Font").width(I18n.t(text), ...) end,
    fit = function(text, ...) return require("src.render.Font").fit(I18n.t(text), ...) end,
  }, { __index = function(_, k)
    if k == "raw" then return require("src.render.Font") end
    return require("src.render.Font")[k]
  end })
  return fontProxy
end

local textBoxProxy
function I18n.textBox()
  if textBoxProxy then return textBoxProxy end
  textBoxProxy = setmetatable({
    new = function(game, text, ...) return require("src.render.TextBox").new(game, I18n.t(text), ...) end,
  }, { __index = live("src.render.TextBox") })
  return textBoxProxy
end

local menuProxy
function I18n.menu()
  if menuProxy then return menuProxy end
  menuProxy = setmetatable({
    new = function(game, items, opts, ...)
      if I18n.language() ~= "en" then
        for _, it in ipairs(type(items) == "table" and items or {}) do
          if type(it) == "table" and type(it.label) == "string" then it.label = I18n.t(it.label) end
        end
        if type(opts) == "table" and type(opts.header) == "string" then opts.header = I18n.t(opts.header) end
      end
      return require("src.ui.Menu").new(game, items, opts, ...)
    end,
  }, { __index = live("src.ui.Menu") })
  return menuProxy
end

-- the start menu, the title screen: rows the engine draws itself, through
-- its own Strings() catalog
function I18n.engineOverrides(strings)
  if not (strings and strings.override) or I18n.language() == "en" then return end
  for _, key in ipairs({ "CONTINUE CO-OP", "NEW CO-OP GAME", "CO-OP (LAN)", "CO-OP ONLINE" }) do
    local to = I18n.t(key)
    if to ~= key then pcall(strings.override, strings, key, to) end
  end
end

return I18n
