-- src/coop/CoopVoice.lua
-- VOICE CHAT (nightly.2, capability "voice").  MODS -> PkMultiplayer:
--   VOICE CHAT       OFF / PUSH V (hold V, or R on a gamepad) / OPEN MIC (talks when
--                    your voice is over the noise floor)
--   VOICE BY DISTANCE on: loud within 4 cells of each other on the same map,
--                    fading out by 16 cells, silent on another map -- except
--                    in a battle together or the Cable Club, where it is full
--
-- Capture: the first recording device, 16 kHz mono 16-bit, cut in 40 ms
-- frames.  Each frame is IMA ADPCM (4 bits a sample, 4:1 -- about 8 KB/s
-- while talking, nothing while quiet), one binary packet on the fast
-- channel (CoopNet:sendRaw), marked by its first byte (MAGIC) so it never
-- reaches the JSON decoder; a partner without the capability is sent none.
-- Playback: a QueueableSource; a late or lost frame is simply skipped.
--
-- Shown: a small speaker over the partner's head (and in a battle's corner)
-- while their voice plays, a microphone at the top left while yours goes.

local CoopManager = require("src.coop.CoopManager")
local CoopLog = require("src.coop.CoopLog")

local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local char, byte = string.char, string.byte

local CoopVoice = {}
CoopVoice.CAP = "voice"
CoopVoice.MAGIC = 0xB7
CoopVoice.RATE = 16000
CoopVoice.FRAME = 640            -- samples: 40 ms
CoopVoice.OPEN_THRESHOLD = 0.02  -- RMS over which an open mic talks
CoopVoice.HANG = 0.3             -- seconds an open mic stays on after the voice
CoopVoice.NEAR, CoopVoice.FAR = 4, 16
CoopVoice.PTT_KEY = "v"
CoopManager.registerCap(CoopVoice.CAP)

-- ------------------------------------------------------------ IMA ADPCM
local STEPS = {
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
  50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
  253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
  1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
  3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
  11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
}
local INDEX_ADJ = { [0] = -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8 }

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function step(state, code)
  local s = STEPS[state.index + 1]
  local diff = rshift(s, 3)
  if band(code, 4) ~= 0 then diff = diff + s end
  if band(code, 2) ~= 0 then diff = diff + rshift(s, 1) end
  if band(code, 1) ~= 0 then diff = diff + rshift(s, 2) end
  if band(code, 8) ~= 0 then state.pred = state.pred - diff else state.pred = state.pred + diff end
  state.pred = clamp(state.pred, -32768, 32767)
  state.index = clamp(state.index + INDEX_ADJ[code], 0, 88)
end

-- samples: array of int16 -> packed nibbles (string), starting state
function CoopVoice.encode(samples, state)
  state = state or { pred = 0, index = 0 }
  local start = { pred = state.pred, index = state.index }
  local out, hi = {}, nil
  for i = 1, #samples do
    local s = STEPS[state.index + 1]
    local d = samples[i] - state.pred
    local code = 0
    if d < 0 then code = 8 d = -d end
    if d >= s then code = bor(code, 4) d = d - s end
    if d >= rshift(s, 1) then code = bor(code, 2) d = d - rshift(s, 1) end
    if d >= rshift(s, 2) then code = bor(code, 1) end
    step(state, code)
    if hi == nil then hi = code else out[#out + 1] = char(bor(lshift(hi, 4), code)) hi = nil end
  end
  if hi ~= nil then out[#out + 1] = char(lshift(hi, 4)) end
  return table.concat(out), start
end

function CoopVoice.decode(data, count, start)
  local state = { pred = start.pred, index = start.index }
  local out = {}
  for i = 1, #data do
    local b = byte(data, i)
    for _, code in ipairs({ rshift(b, 4), band(b, 15) }) do
      if #out >= count then break end
      step(state, code)
      out[#out + 1] = state.pred
    end
  end
  return out
end

-- one packet: MAGIC, seq (2), start pred (2, signed), index, count (2), data
function CoopVoice.pack(seq, samples, state)
  local data, start = CoopVoice.encode(samples, state)
  local p = start.pred % 65536
  return char(CoopVoice.MAGIC, band(seq, 255), band(rshift(seq, 8), 255),
              rshift(p, 8), band(p, 255), start.index,
              band(#samples, 255), rshift(#samples, 8)) .. data
end

function CoopVoice.unpack(packet)
  if type(packet) ~= "string" or #packet < 9 or byte(packet, 1) ~= CoopVoice.MAGIC then return nil end
  local seq = byte(packet, 2) + byte(packet, 3) * 256
  local p = byte(packet, 4) * 256 + byte(packet, 5)
  if p >= 32768 then p = p - 65536 end
  local index = clamp(byte(packet, 6), 0, 88)
  local count = byte(packet, 7) + byte(packet, 8) * 256
  if count > 4096 then return nil end
  return seq, CoopVoice.decode(packet:sub(9), count, { pred = p, index = index })
end

function CoopVoice.isPacket(data)
  return type(data) == "string" and byte(data, 1) == CoopVoice.MAGIC
end

-- ------------------------------------------------------------ settings
local function opts() return package.loaded["pkmultiplayer.options"] end
function CoopVoice.mode()
  local o = opts()
  local m = o and o.get and o.get("voice")
  if m == "ptt" or m == "open" then return m end
  return "off"
end
function CoopVoice.byDistance()
  local o = opts()
  return not (o and o.on) or o.on("voiceDistance")
end

-- how loud the partner is, 0..1, from where the two of you stand
function CoopVoice.proximity(game, ow)
  if not CoopVoice.byDistance() then return 1 end
  local top = game and game.stack and game.stack.top and game.stack:top()
  if top and (top.coopDouble or top.verdict or top.isLinkState) then return 1 end
  local partner = CoopManager.partner
  local here = ow and ow.map and ow.map.id
  if not (partner and partner.map and here and CoopManager.mapsMatch(partner.map, here)) then return 0 end
  local p = ow.player
  if not p then return 1 end
  local px = p.cellX or math.floor((p.px or 0) / 16)
  local py = p.cellY or math.floor((p.py or 0) / 16)
  local d = math.sqrt(((partner.cx or 0) - px) ^ 2 + ((partner.cy or 0) - py) ^ 2)
  if d <= CoopVoice.NEAR then return 1 end
  if d >= CoopVoice.FAR then return 0 end
  return 1 - (d - CoopVoice.NEAR) / (CoopVoice.FAR - CoopVoice.NEAR)
end

-- ------------------------------------------------------------ capture
CoopVoice.mic = nil
CoopVoice.pending = {}
CoopVoice.encState = { pred = 0, index = 0 }
CoopVoice.seq = 0
CoopVoice.talking = false
CoopVoice.lastVoiceAt = -1
CoopVoice.feedOverride = nil -- tests / drivers: fn() -> array of floats

local function clock() return love and love.timer and love.timer.getTime() or os.clock() end

local function openMic()
  if CoopVoice.mic or CoopVoice.micFailed then return CoopVoice.mic end
  local la = love and love.audio
  if not (la and la.getRecordingDevices) then CoopVoice.micFailed = true return nil end
  local ok, devs = pcall(la.getRecordingDevices)
  local dev = ok and devs and devs[1]
  if not dev then
    CoopVoice.micFailed = true
    CoopLog.warn("VOICE", "no microphone found")
    return nil
  end
  local started = pcall(dev.start, dev, CoopVoice.RATE, CoopVoice.RATE, 16, 1)
  if not started then
    CoopVoice.micFailed = true
    CoopLog.warn("VOICE", "the microphone would not start")
    return nil
  end
  CoopLog.info("VOICE", "microphone: " .. tostring(dev.getName and dev:getName() or "?"))
  CoopVoice.mic = dev
  return dev
end

local function closeMic()
  if CoopVoice.mic then pcall(CoopVoice.mic.stop, CoopVoice.mic) end
  CoopVoice.mic = nil
  CoopVoice.pending = {}
  CoopVoice.talking = false
end

-- new samples as floats -1..1
local function readMic()
  if CoopVoice.feedOverride then return CoopVoice.feedOverride() end
  local dev = openMic()
  if not dev then return nil end
  local ok, n = pcall(dev.getSampleCount, dev)
  if not ok or (n or 0) <= 0 then return nil end
  local okD, sd = pcall(dev.getData, dev)
  if not okD or not sd then return nil end
  local out = {}
  for i = 0, sd:getSampleCount() - 1 do out[#out + 1] = sd:getSample(i) end
  return out
end

-- on a gamepad, R (Gen 1 and 2 have no R button; L can be a second A)
CoopVoice.PTT_PAD = "rightshoulder"

local function padHeld()
  local js = love and love.joystick
  if not (js and js.getJoysticks) then return false end
  for _, j in ipairs(js.getJoysticks()) do
    local ok, down = pcall(function() return j:isGamepad() and j:isGamepadDown(CoopVoice.PTT_PAD) end)
    if ok and down then return true end
  end
  return false
end

-- the push-to-talk key (V, or R on a gamepad) is held, and nothing is typed
function CoopVoice.pttHeld(game)
  local kb = love and love.keyboard
  local key = kb and kb.isDown and kb.isDown(CoopVoice.PTT_KEY)
  if not (key or padHeld()) then return false end
  if CoopManager.chatOverlay then return false end
  local top = game and game.stack and game.stack.top and game.stack:top()
  if top and (top.isChatBox or top.onTextInput) then return false end
  return true
end

function CoopVoice.capture(game, dt)
  local mode = CoopVoice.mode()
  local sendable = mode ~= "off" and CoopManager.connected and CoopManager.bothHave(CoopVoice.CAP)
  if not sendable then
    if CoopVoice.mic then closeMic() end
    return
  end
  local samples = readMic()
  if not samples then return end
  local pend = CoopVoice.pending
  for _, s in ipairs(samples) do pend[#pend + 1] = s end
  local t = clock()
  while #pend >= CoopVoice.FRAME do
    local frame, sum = {}, 0
    for i = 1, CoopVoice.FRAME do
      local v = pend[i]
      sum = sum + v * v
      frame[i] = clamp(math.floor(v * 32767 + 0.5), -32768, 32767)
    end
    local rest = {}
    for i = CoopVoice.FRAME + 1, #pend do rest[#rest + 1] = pend[i] end
    pend = rest
    local rms = math.sqrt(sum / CoopVoice.FRAME)
    local talk
    if mode == "ptt" then
      talk = CoopVoice.pttHeld(game)
    else
      if rms >= CoopVoice.OPEN_THRESHOLD then CoopVoice.lastVoiceAt = t end
      talk = t - CoopVoice.lastVoiceAt <= CoopVoice.HANG
    end
    if talk then
      CoopVoice.seq = (CoopVoice.seq + 1) % 65536
      local packet = CoopVoice.pack(CoopVoice.seq, frame, CoopVoice.encState)
      local net = CoopManager.net
      if net and net.sendRaw then net:sendRaw(packet) end
      CoopVoice.talkingAt = t
    else
      -- a fresh start for the next burst: no step carried over a silence
      CoopVoice.encState = { pred = 0, index = 0 }
    end
    CoopVoice.talking = talk
  end
  CoopVoice.pending = pend
end

-- ------------------------------------------------------------ playback
CoopVoice.source = nil
CoopVoice.lastSeq = nil
CoopVoice.received = 0

local function source()
  if CoopVoice.source or CoopVoice.sourceFailed then return CoopVoice.source end
  local la = love and love.audio
  local ok, src = pcall(function() return la.newQueueableSource(CoopVoice.RATE, 16, 1, 8) end)
  if not ok or not src then CoopVoice.sourceFailed = true return nil end
  CoopVoice.source = src
  return src
end

-- CoopNet: a voice packet from the partner
function CoopVoice.onPacket(packet, game, ow)
  if CoopVoice.mode() == "off" then return end
  local seq, samples = CoopVoice.unpack(packet)
  if not seq then return end
  if CoopVoice.lastSeq then
    local ahead = (seq - CoopVoice.lastSeq) % 65536
    if ahead == 0 or ahead > 32768 then return end -- a late one: skipped
  end
  CoopVoice.lastSeq = seq
  CoopVoice.received = CoopVoice.received + 1
  CoopManager.partnerSpeakingAt = clock()
  local vol = CoopVoice.proximity(game, ow)
  CoopVoice.lastVolume = vol
  if vol <= 0 then return end
  local src = source()
  if not src then return end
  local okS, sd = pcall(love.sound.newSoundData, #samples, CoopVoice.RATE, 16, 1)
  if not okS then return end
  for i, v in ipairs(samples) do sd:setSample(i - 1, v / 32768) end
  pcall(src.setVolume, src, vol)
  if (src:getFreeBufferCount() or 0) > 0 then
    src:queue(sd)
    if not src:isPlaying() then src:play() end
  end
end

-- is the partner talking right now (for the speaker over their head)?
function CoopVoice.partnerTalking()
  return CoopManager.partnerSpeakingAt ~= nil and clock() - CoopManager.partnerSpeakingAt < 0.3
end
function CoopVoice.selfTalking()
  return CoopVoice.talking and CoopVoice.talkingAt ~= nil and clock() - CoopVoice.talkingAt < 0.3
end

-- a 7x7 speaker (partner) or microphone (you) at x, y
function CoopVoice.drawIcon(x, y, mic)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x - 1, y - 1, 9, 9)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x, y, 7, 7)
  g.setColor(0, 0, 0, 1)
  if mic then
    g.rectangle("fill", x + 2, y + 1, 3, 4)
    g.rectangle("fill", x + 1, y + 4, 1, 1)
    g.rectangle("fill", x + 5, y + 4, 1, 1)
    g.rectangle("fill", x + 3, y + 5, 1, 2)
  else
    g.rectangle("fill", x + 1, y + 2, 2, 3)
    g.polygon("fill", x + 3, y + 2, x + 5, y, x + 5, y + 7, x + 3, y + 5)
    local phase = math.floor(clock() * 6) % 2
    if phase == 0 then g.rectangle("fill", x + 6, y + 2, 1, 3) end
  end
  g.setColor(1, 1, 1, 1)
end

CoopManager.onTick("voice", function(dt, game, ow)
  local net = CoopManager.net
  local inbox = net and net.voiceInbox
  if inbox and #inbox > 0 then
    net.voiceInbox = {}
    for _, packet in ipairs(inbox) do
      local okP, errP = pcall(CoopVoice.onPacket, packet, game, ow or (game and game.overworld))
      if not okP and errP ~= CoopVoice.lastErr then CoopVoice.lastErr = errP CoopLog.error("VOICE", tostring(errP)) end
    end
  end
  local ok, err = pcall(CoopVoice.capture, game, dt)
  if not ok and err ~= CoopVoice.lastErr then
    CoopVoice.lastErr = err
    CoopLog.error("VOICE", tostring(err))
  end
end)

return CoopVoice
