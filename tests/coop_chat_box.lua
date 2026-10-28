-- THE CHAT BOX AND THE HIGH FIVE (src/coop/CoopChatBox.lua, CoopEmotes).
--
-- Reported from play:
--   * "when I use the chat in a battle the game freezes until I close it":
--     in a co-op double the chat is drawn inside the battle, which stays the
--     top state and keeps running on a mute pad;
--   * "the chat should take a bit more text without running off", then
--     "longer to write": 70 letters on four rows, broken at the spaces,
--     counted in letters (an accented letter is two bytes);
--   * "the high five button is too long, I don't like the emoji": HIGH FIVE
--     shows a drawn hand, and its Spanish label fits the menu.
--
--   cd <Gen2Recomped checkout>
--   luajit <mod>/tests/run.lua <mod>/tests/coop_chat_box.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local CoopManager = require("src.coop.CoopManager")
local Box = require("src.coop.CoopChatBox")
local CoopEmotes = require("src.coop.CoopEmotes")
require("src.coop.CoopLog").enabled = false
local function letters(t) return select(2, t:gsub("[^\128-\191]", "")) end

-- the rows: broken at spaces, four of them, 17 then 18 letters
local rows = Box.layout("Hola Toby, ¿vamos a la Ruta 32 después de ganar? ¡Sí!")
T.check(rows and #rows == 4, "a 52-letter message takes four rows")
T.check(rows and rows[1]:find("^Hola Toby, ¿vamos") and rows[3]:find("^después"), "...broken at the spaces, not inside a word")
for _, r in ipairs(rows or {}) do T.check(letters(r) <= 18, "no row is wider than the box (" .. r .. ")") end
T.check(Box.layout(string.rep("palabra ", 12)) == nil, "a message that needs a fifth row does not fit")

-- typing: letters, not bytes, and only while it fits
local sent = {}
CoopManager.net = { send = function(_, m) sent[#sent + 1] = m return true end, flush = function() end }
CoopManager.connected = true
local game = { stack = { states = {}, top = function(s) return s.states[#s.states] end,
                         push = function(s, x) s.states[#s.states + 1] = x end, pop = function(s) return table.remove(s.states) end } }
local box = Box.new(game)
box.swallowOpenKey = false
box:onTextInput("ñññññññññññññññññññ")
T.check(letters(box.text) == 19, "accented letters count once each (" .. letters(box.text) .. ")")
box.text = ""
box:onTextInput(string.rep("ab cd ", 30))
T.check(letters(box.text) <= 70 and Box.layout(box.text) ~= nil, "a long paste stops where the rows are full")

-- in a co-op double the chat is drawn inside the battle, which stays on top
local battle = { coopDouble = true, chooseAction = function() end, game = game }
game.stack:push(battle)
CoopManager.chatOverlay = nil
CoopManager.openChat(game)
T.check(CoopManager.chatOverlay and CoopManager.chatOverlay.overlay, "in a co-op double the chat opens inside the battle")
T.check(game.stack:top() == battle, "...and the battle stays the top state")
CoopManager.chatOverlay:cancel()
T.check(CoopManager.chatOverlay == nil, "closing it leaves the battle as it was")

-- the mute pad: nothing pressed, the rest of the input as it is
local real = { wasPressed = function() return true end, isDown = function() return true end, mode = 2 }
local mute = Box.mutedInput(real)
T.check(mute:wasPressed("a") == false and mute:isDown("b") == false and mute.mode == 2,
        "the battle under the chat reads no button")

-- messages from the partner: whole, in letters
T.check(CoopManager.CHAT_MAX >= 70, "a whole chat box message gets through")
T.check(CoopManager.clipLetters("áéíóú", 3) == "áéí", "a long message is cut between letters, never inside one")

-- the high five
T.check(CoopEmotes.valid("highfive"), "HIGH FIVE has its own emote")
T.check(CoopEmotes.get("highfive").bubble == nil, "...drawn by the mod, not one of the cartridge's bubbles")
local ES = require("src.coop.CoopLangES")
local label = (type(ES) == "table" and (ES.strings or ES)["HIGH FIVE!"]) or nil
if label then T.check(letters(label) <= 14, "the Spanish HIGH FIVE fits the partner menu (" .. label .. ")") end

-- the number pad: one key per emote (requested from play)
T.check(CoopEmotes.quickKey("kp1") == "exclaim" and CoopEmotes.quickKey("kp7") == "sleep",
        "number pad 1-7: the picker's emotes, in its order")
T.check(CoopEmotes.quickKey("kp8") == "highfive", "number pad 8: the high five")
T.check(CoopEmotes.quickKey("kp9") == nil and CoopEmotes.quickKey("1") == nil, "other keys send nothing")
for _, id in ipairs(CoopEmotes.QUICK) do T.check(CoopEmotes.valid(id), "quick emote " .. id .. " exists") end

T.finish("co-op chat box and high five")
