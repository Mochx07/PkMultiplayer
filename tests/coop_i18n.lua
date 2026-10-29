-- THE MOD IN SPANISH (src/coop/CoopI18n.lua, src/coop/CoopLangES.lua).
--
-- Lines are translated where they reach the screen: whole lines, lines put
-- together at run time (templates), pieces put back in the Spanish order,
-- help boxes as blocks.  Players' names and chat are never translated; a
-- letter the font cannot draw is written without its accent.  And every
-- translation keeps its pieces and fits the box it is drawn in.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local I18n = require("src.coop.CoopI18n")
local ES = require("src.coop.CoopLangES")
local CoopManager = require("src.coop.CoopManager")
require("src.coop.CoopLog").enabled = false

-- a font with every letter, then one without the Spanish ones
local realFont = package.loaded["src.render.Font"]
local function fontWith(all)
  package.loaded["src.render.Font"] = setmetatable({
    split = function(ch)
      local plain = not ch:find("[\128-\255]") or ch == "é"
      return { { code = (all or plain) and 1 or nil } }
    end,
  }, { __index = realFont })
  I18n.resetGlyphs()
end

fontWith(true)
I18n.forced = "en"
T.check(I18n.t("Partner is busy") == "Partner is busy", "ENGLISH: lines stay as written")
I18n.forced = "es"
T.check(I18n.t("Partner is busy") == "Tu compañero está ocupado", "ESPAÑOL: a whole line")
T.check(I18n.t("Linked with TOBY!") == "¡Enlazado con TOBY!", "a line built at run time, by its template")
T.check(I18n.t("WARP (4:05)") == "IR (4:05)", "numbers keep their zeros")
T.check(I18n.t("MISTY's STARMIE joins your DAY-CARE") == "STARMIE de MISTY entra en tu GUARDERÍA",
        "pieces go in the Spanish order")
T.check(I18n.t("STORY SYNC ON (partner)") == "HIST. COMÚN SÍ (compañero)", "the mod's own words inside a line too")
T.check(I18n.t("SAD is busy") == "SAD está ocupado", "a player called like a word keeps their name")
T.check(I18n.t("You swapped with\nTOBY today.\fCome back\ntomorrow!") == "Ya cambiaste con\nTOBY hoy.\f¡Vuelve\nmañana!",
        "pages and lines in one text box")
local help = I18n.lines({ "STORY EVENTS ONE", "OF YOU SEES COUNT", "FOR BOTH OF YOU." })
T.check(#help == 3 and help[1] == "LO QUE UNO VIVE EN", "a help box is translated as one block")
T.check(I18n.t("this line is nowhere") == "this line is nowhere", "a line with no translation shows in English")

-- the font has no Spanish letters (no glyph mod)
fontWith(false)
T.check(I18n.t("Partner is busy") == "Tu companero esta ocupado", "without the glyphs the accents go, not the letters")
T.check(I18n.t("Linked with TOBY!") == "Enlazado con TOBY!", "...and ¿ ¡ are left out")
T.check(I18n.fit("Partner is busy", 6) == "Tu com", "fit cuts letters, not bytes")
fontWith(true)
T.check(I18n.fit("Partner is busy", 6) == "Tu com", "...also with accents drawn")
T.check(I18n.fit("NEW AREA!", 20) == "¡ZONA NUEVA!", "fit translates first")

-- AUTO follows the game's translation
I18n.forced = nil
package.loaded["pkmultiplayer.options"] = { get = function() return "auto" end }
package.loaded["src.translation.Service"] = { language = "es" }
T.check(I18n.language() == "es", "AUTO: a game translated to Spanish shows the mod in Spanish")
package.loaded["src.translation.Service"] = { language = "original" }
T.check(I18n.language() == "en", "AUTO: otherwise English")
package.loaded["pkmultiplayer.options"] = { get = function() return "es" end }
T.check(I18n.language() == "es", "ESPAÑOL chosen: always Spanish")
package.loaded["pkmultiplayer.options"] = nil
package.loaded["src.translation.Service"] = nil

-- the status line speaks it
I18n.forced = "es"
CoopManager.showStatus("TOBY didn't answer", 2)
T.check(CoopManager.statusMessage == "TOBY no respondió", "the status line is translated")

-- the status box wraps an accented line by letters, not bytes
local w = CoopManager.wrap("¡Tu compañero se fue! Juega la IA.", 18, 2)
T.check(w[1] == "¡Tu compañero se" and w[2] == "fue! Juega la IA.", "the status line wraps by letters")

-- every translation keeps its pieces and fits its box
local function letters(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function pieces(s)
  local n = 0
  for _ in s:gmatch("%%%d*[sd]") do n = n + 1 end
  return n
end
local bad = {}
for en, es in pairs(ES) do
  if pieces(en) ~= pieces(es) then bad[#bad + 1] = "pieces: " .. en end
  if en:find("\n") and not en:find("%%") and not en:find("\f") then
    for l in (es .. "\n"):gmatch("(.-)\n") do
      if letters(l) > 18 then bad[#bad + 1] = "box line > 18: " .. l end
    end
  end
end
T.check(#bad == 0, "every translation keeps its pieces and box width " .. table.concat(bad, "; "))
for _, rule in ipairs({ "STORY SYNC", "TEAM UP WILD", "SHARE DEX", "LINK DAYCARE", "PARTNER HEAL",
                        "SOUL LINK", "BALANCED FOES", "HARD FOES" }) do
  T.check(ES[rule] and letters(ES[rule]) <= 13, "the rule " .. rule .. " fits beside SÍ/NO")
end
for _, row in ipairs({ "CHAT  (KEY T)", "EMOTE  (KEY Y)", "WARP TO PARTNER", "PARTNER", "RULES",
                       "VERSION", "DISCONNECT", "ITEM FOR PARTNER", "TRADE", "BATTLE P1 VS P2",
                       "MYSTERY GIFT", "SOUL LINKS", "STOP HOSTING", "STOP VISITING", "HOST", "JOIN",
                       "VISIT", "EXIT", "CONTINUE CO-OP", "NEW CO-OP GAME", "CO-OP ONLINE" }) do
  T.check(ES[row] and letters(ES[row]) <= 16, "the row " .. row .. " fits its menu")
end

-- UTF-8 sanitization & truncation resilience
T.check(I18n.cleanUTF8("Hello World") == "Hello World", "cleanUTF8 preserves ASCII")
T.check(I18n.cleanUTF8("POCIÓN MÁXIMA") == "POCIÓN MÁXIMA", "cleanUTF8 preserves valid Spanish UTF-8")
T.check(I18n.cleanUTF8("POCI\195") == "POCI", "cleanUTF8 drops trailing incomplete 2-byte lead")
T.check(I18n.cleanUTF8("TEST\226\128") == "TEST", "cleanUTF8 drops trailing incomplete 3-byte sequence")
T.check(I18n.cleanUTF8("TEST\240\144\128") == "TEST", "cleanUTF8 drops trailing incomplete 4-byte sequence")
T.check(I18n.cleanUTF8("\128\129abc") == "abc", "cleanUTF8 drops stray continuation bytes")

T.check(I18n.truncate("ANTIPARÁLISIS", 12) == "ANTIPARÁLISI", "truncate cuts at character boundaries, preserving Á")
T.check(I18n.truncate("ANTIPAR\195", 12) == "ANTIPAR", "truncate drops trailing raw-sliced orphan byte")
T.check(I18n.padRight("POCIÓN", 10) == "POCIÓN    ", "padRight aligns by character count rather than byte count")

-- Simulated UnicodeFont failure protection
local S = rawget(_G, "__PKMULTIPLAYER")
local Hooks = S and S.hooks
if Hooks then
  T.check(type(Hooks.cleanUTF8) == "function", "Hooks exports cleanUTF8")
  T.check(Hooks.cleanUTF8("SUPERPOC\195") == "SUPERPOC", "Hooks.cleanUTF8 sanitizes truncated strings")

  local fakeUnicodeFont = {
    font = function() return { getWidth = function(s) if s:find("\195") then error("UTF-8 decoding error: Not enough space") end return 8 end } end,
    draw = function(code, x, y, h) error("UTF-8 decoding error: Not enough space") end,
    width = function(code, h) error("UTF-8 decoding error: Not enough space") end,
    code = function(char) return -1 end,
  }
  Hooks.modules["src.translation.UnicodeFont"](fakeUnicodeFont)
  local drawOk = pcall(function() fakeUnicodeFont.draw(-1, 0, 0, 8) end)
  T.check(drawOk, "UnicodeFont.draw hook catches decoding errors without throwing")
  local widthOk, w = pcall(function() return fakeUnicodeFont.width(-1, 8) end)
  T.check(widthOk and w == 8, "UnicodeFont.width hook safely returns default height on error")
end

I18n.forced = nil
package.loaded["src.render.Font"] = realFont
I18n.resetGlyphs()
T.finish("the mod in Spanish")
