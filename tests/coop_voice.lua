-- VOICE CHAT (nightly.2, src/coop/CoopVoice.lua, "voice").  The IMA ADPCM
-- codec round-trips a voice-like signal within a small error, a packet
-- carries its sequence and start state, and the partner's volume follows
-- where the two of you stand.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
T.fixtures.fresh()
local CoopManager = require("src.coop.CoopManager")
local Voice = require("src.coop.CoopVoice")
require("src.coop.CoopLog").enabled = false

-- a 40 ms frame of two tones, as int16
local frame = {}
for i = 1, Voice.FRAME do
  local t = (i - 1) / Voice.RATE
  frame[i] = math.floor((math.sin(2 * math.pi * 220 * t) * 0.4 + math.sin(2 * math.pi * 660 * t) * 0.2) * 32767)
end
local data, start = Voice.encode(frame, { pred = 0, index = 0 })
T.check(#data == Voice.FRAME / 2, "4 bits a sample: " .. #data .. " bytes for " .. Voice.FRAME .. " samples")
local back = Voice.decode(data, #frame, start)
local sig, err = 0, 0
for i = 41, #frame do sig = sig + frame[i] ^ 2 err = err + (frame[i] - back[i]) ^ 2 end
local snr = 10 * math.log10(sig / math.max(1, err))
T.check(snr > 18, string.format("the round trip keeps the voice (SNR %.1f dB after the first 40 samples)", snr))

-- a packet: header + data, continuing state across frames
local state = { pred = 0, index = 0 }
local p1 = Voice.pack(65535, frame, state)
local p2 = Voice.pack(0, frame, state)
T.check(Voice.isPacket(p1) and not Voice.isPacket("{\"type\":1}"), "a voice packet is told apart from JSON by its first byte")
local s1, d1 = Voice.unpack(p1)
local s2, d2 = Voice.unpack(p2)
T.check(s1 == 65535 and s2 == 0 and #d1 == #frame and #d2 == #frame, "sequence and sample count travel (wrapping at 65536)")
local sig2, err2 = 0, 0
for i = 41, #frame do sig2 = sig2 + frame[i] ^ 2 err2 = err2 + (frame[i] - d2[i]) ^ 2 end
T.check(10 * math.log10(sig2 / math.max(1, err2)) > 18, "the second frame decodes from the state it carries")
T.check(Voice.unpack("\183short") == nil and Voice.unpack("abc") == nil, "a cut-short or foreign packet is dropped")

-- proximity
package.loaded["pkmultiplayer.options"] = { on = function() return true end, get = function() return "open" end }
CoopManager.partner.map = "ROUTE_29"
local ow = { map = { id = "ROUTE_29" }, player = { cellX = 10, cellY = 10 } }
local game = { stack = { top = function() return nil end } }
CoopManager.partner.cx, CoopManager.partner.cy = 12, 10
T.check(Voice.proximity(game, ow) == 1, "two cells apart: full volume")
CoopManager.partner.cx = 20
local mid = Voice.proximity(game, ow)
T.check(mid > 0 and mid < 1, string.format("ten cells: quieter (%.2f)", mid))
CoopManager.partner.cx = 40
T.check(Voice.proximity(game, ow) == 0, "thirty cells: silent")
CoopManager.partner.map = "CHERRYGROVE_CITY"
T.check(Voice.proximity(game, ow) == 0, "another map: silent")
local battleGame = { stack = { top = function() return { coopDouble = true } end } }
T.check(Voice.proximity(battleGame, ow) == 1, "in a battle together: full, wherever the maps say")
package.loaded["pkmultiplayer.options"] = { on = function(k) return k ~= "voiceDistance" end, get = function() return "ptt" end }
T.check(Voice.proximity(game, ow) == 1 and Voice.mode() == "ptt", "VOICE BY DISTANCE off: always full; mode PUSH V")
package.loaded["pkmultiplayer.options"] = nil
T.check(Voice.mode() == "off", "no options: voice off")

-- push to talk: V, or R on a gamepad; never while typing
local realLove = love
local downKey, downPad = false, false
love = setmetatable({
  keyboard = { isDown = function(k) return downKey and k == "v" end },
  joystick = { getJoysticks = function() return { { isGamepad = function() return true end,
                                                    isGamepadDown = function(_, b) return downPad and b == "rightshoulder" end } } end },
}, { __index = realLove })
local idle = { stack = { top = function() return {} end } }
T.check(not Voice.pttHeld(idle), "nothing held: not talking")
downKey = true
T.check(Voice.pttHeld(idle), "V held: talking")
downKey, downPad = false, true
T.check(Voice.pttHeld(idle), "R on a gamepad held: talking")
local typing = { stack = { top = function() return { isChatBox = true } end } }
T.check(not Voice.pttHeld(typing), "typing in the chat box: V is a letter, not the radio")
love = realLove

T.finish("voice chat")
