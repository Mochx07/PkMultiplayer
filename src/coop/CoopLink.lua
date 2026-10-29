-- src/coop/CoopLink.lua
-- TRADE and P1-vs-P2 BATTLE between the two co-op players, through the
-- game's own Cable Club.
--
-- LinkState (src/link) already does both properly -- the handshake, the
-- trade screens and confirmations, the lockstep link battle -- over its own
-- ENet socket.  Opening a second connection to a partner we are already
-- linked to would mean a second address, port and firewall rule, so
-- instead LinkState is handed an adapter with the same small surface it
-- uses (update / poll / send / close, paired / closed / error / inbox) that
-- tunnels every link message through the co-op link as `coop_link`.
--
-- Flow: one player picks TRADE or BATTLE (co-op menu, or talking to the
-- partner); the other is asked; on yes both open LinkState already past its
-- connection menus -- the asker as the side that picks the mode, the other
-- waiting for it -- and the Cable Club takes it from there.
--
-- A DROPPED LINK IS NOT A PULLED CABLE.  The co-op session survives a short
-- drop (CoopNet resends what the other side never got), so the tunnel stays
-- open through RECONNECTING: a trade's last CONFIRM still arrives and both
-- games commit, instead of one committing and the other closing -- a clone
-- or a lost Pokemon.  The tunnel closes when the session itself ends (the
-- partner left, the reconnect window ran out, or they came back as a new
-- game).  Every tunnel carries its invite's id, so a message from an older
-- trade -- a CONFIRM that arrived late -- never arms the next one.

local CoopLink = {}

CoopLink.adapter = nil   -- the live tunnel, while a LinkState runs
CoopLink.early = {}      -- link messages that beat our LinkState into existence
CoopLink.pending = nil   -- our invite, waiting for an answer
CoopLink.INVITE_TIMEOUT = 25

local function manager()
  local ok, CM = pcall(require, "src.coop.CoopManager")
  return ok and CM or nil
end

-- ---------------------------------------------------------------------
-- the tunnel
-- ---------------------------------------------------------------------

local Tunnel = {}
Tunnel.__index = Tunnel

function CoopLink.newTunnel(id)
  local t = setmetatable({ id = id, inbox = {}, paired = true, closed = false, error = nil,
                           target = "CO-OP PARTNER", address = "CO-OP PARTNER" }, Tunnel)
  for _, m in ipairs(CoopLink.early) do
    if m.link == id then t.inbox[#t.inbox + 1] = m.payload end
  end
  CoopLink.early = {}
  CoopLink.adapter = t
  return t
end

function Tunnel:update()
  local CM = manager()
  local net = CM and CM.net
  local up = CM and CM.isConnected and CM.isConnected()
  -- reconnecting: the session (and what we sent) is kept, so is the tunnel
  local waiting = net and not net.closed and net.sessionActive
                  and (net.state == "RECONNECTING" or net.state == "HANDSHAKE")
  self.paired = (up or waiting) and not self.closed
  if not (up or waiting) and not self.closed then
    -- the session ended: to LinkState this is the cable coming out
    self.closed = true
  end
end

function Tunnel:poll()
  local q = self.inbox
  self.inbox = {}
  return q
end

function Tunnel:send(msg)
  if self.closed then return end
  local CM = manager()
  if CM and CM.net then CM.net:send({ type = "coop_link", link = self.id, payload = msg }) end
end

-- LinkState closes its net when it ends; the co-op link itself stays up
function Tunnel:close()
  self.closed = true
  if CoopLink.adapter == self then CoopLink.adapter = nil end
end

function CoopLink.onLinkMessage(msg)
  if type(msg.payload) ~= "table" then return end
  local open = CoopLink.adapter and not CoopLink.adapter.closed and CoopLink.adapter
  if open and open.id == msg.link then
    table.insert(open.inbox, msg.payload)
  elseif open then
    require("src.coop.CoopLog").info("LINK", "dropped a message from another trade: " .. tostring(msg.link))
  else
    table.insert(CoopLink.early, { link = msg.link, payload = msg.payload })
    while #CoopLink.early > 64 do table.remove(CoopLink.early, 1) end
  end
end

-- ---------------------------------------------------------------------
-- starting the Cable Club on both screens
-- ---------------------------------------------------------------------

local function openLinkState(game, mode, asker, linkId)
  local LinkState = require("src.link.LinkState")
  local ls = LinkState.new(game)
  ls.net = CoopLink.newTunnel(linkId)
  ls.coopTunnel = true
  if asker then
    -- the side that picked the mode is the link "host": it announces the
    -- mode and waits for the partner's hello (LinkState's waitHello)
    ls.pendingMode = mode
    ls.helloWait = 0
    ls:sendHello(mode)
    ls.stage = "waitHello"
  else
    ls.stage = "waitMode"
    ls:sendHello(nil)
  end
  game.stack:push(ls)
  return ls
end
CoopLink.openLinkState = openLinkState

local MODE_TEXT = { trade = "TRADE", battle = "BATTLE" }

-- THE CABLE CLUB NEEDS A POKEMON ON BOTH SIDES.  The game only offers LINK
-- with a party (StartMenu), so LinkState and LinkBattle assume one: an empty
-- party on either side crashed the link battle (LinkBattle.newGuest) and
-- left a trade room with nothing to trade.  A trade needs a Pokemon; a
-- battle needs one that is not an egg.
function CoopLink.partyReady(game, mode)
  local party = game and game.save and game.save.party or {}
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(party) do
    if type(mon) == "table" and (mode ~= "battle" or not Party.isEgg(mon)) then return true end
  end
  return false
end

-- one player asks
function CoopLink.invite(game, mode)
  local CM = manager()
  if not (CM and CM.isConnected and CM.isConnected()) then
    if CM then CM.showStatus("No partner linked", 2) end
    return false
  end
  if not MODE_TEXT[mode] then return false end
  if not CoopLink.partyReady(game, mode) then
    CM.showStatus("You have no POKéMON!", 2.5)
    return false
  end
  local id = string.format("L%d-%d", os.time(), math.random(1, 2 ^ 24))
  local CoopWaitModal = require("src.coop.CoopWaitModal")
  local pName = string.upper(CM.partner.name or "PARTNER")
  local modal = CoopWaitModal.new(game, pName, function(reason)
    if CoopLink.pending and CoopLink.pending.id == id then
      CoopLink.pending = nil
      CM.net:send({ type = "coop_link_cancel", id = id })
      if reason == "timeout" then CM.showStatus(pName .. " didn't answer", 2.5) end
    end
  end, CoopLink.INVITE_TIMEOUT + 2, { lines = { "ASKING " .. pName, "TO " .. MODE_TEXT[mode] .. "..." },
                                      cancelLabel = "B: CANCEL" })
  CoopLink.pending = { id = id, mode = mode, modal = modal }
  game.stack:push(modal)
  CM.net:send({ type = "coop_link_invite", id = id, mode = mode, name = CM.getLocalPlayerName(game) })
  return true
end

-- the other is asked
function CoopLink.onInvite(game, msg)
  local CM = manager()
  if not (game and CM) then return end
  local function answer(kind, reason)
    CM.net:send({ type = kind, id = msg.id, reason = reason })
  end
  -- no POKeMON first: that one will not go away by waiting
  local wanted = MODE_TEXT[msg.mode] and msg.mode or nil
  if wanted and not CoopLink.partyReady(game, wanted) then
    answer("coop_link_decline", "no_mons")
    return
  end
  if CoopLink.adapter or CoopLink.pending then answer("coop_link_decline", "busy") return end
  local ow = game.overworld
  if not (CM.overworldIdle and CM.overworldIdle(game, ow)) then answer("coop_link_decline", "busy") return end
  local mode = MODE_TEXT[msg.mode] and msg.mode or nil
  if not mode then return end
  local who = string.upper(tostring(msg.name or CM.partner.name or "PARTNER"))
  local Invite = require("src.coop.CoopBattleInviteModal")
  local modal = Invite.new(game, who, "", function()
    CoopLink.asked = nil
    answer("coop_link_accept")
    openLinkState(game, mode, false, msg.id)
  end, function()
    CoopLink.asked = nil
    answer("coop_link_decline", "declined")
  end)
  modal.inviteId = msg.id
  modal.timeout = CoopLink.INVITE_TIMEOUT
  modal.lines = { require("src.coop.CoopI18n").truncate(who, 16), mode == "trade" and "WANTS TO TRADE!" or "WANTS TO BATTLE!",
                  mode == "trade" and "OPEN TRADE ROOM?" or "P1 VS P2 BATTLE?" }
  CoopLink.asked = modal
  game.stack:push(modal)
end

local function closePending(game)
  local p = CoopLink.pending
  CoopLink.pending = nil
  if p and p.modal then
    p.modal.done = true
    local CM = manager()
    if CM and CM.removeState then CM.removeState(game, p.modal) end
  end
  return p
end

function CoopLink.onAccept(game, msg)
  local p = CoopLink.pending
  if not (p and p.id == msg.id) then return end
  closePending(game)
  openLinkState(game, p.mode, true, p.id)
end

function CoopLink.onDecline(game, msg)
  local p = CoopLink.pending
  if not (p and p.id == msg.id) then return end
  closePending(game)
  local CM = manager()
  if CM then
    local why = (msg.reason == "busy" and "Partner is busy")
      or (msg.reason == "no_mons" and "Partner has no POKéMON")
      or "Partner said no"
    CM.showStatus(why, 2.5)
  end
end

function CoopLink.onCancel(game, msg)
  local modal = CoopLink.asked
  if modal and modal.inviteId == msg.id then
    CoopLink.asked = nil
    local CM = manager()
    if CM and CM.removeState then CM.removeState(game, modal) end
  end
end

-- the co-op link dropped; `reason` "lost" is a drop the session may
-- recover from, and an open trade waits it out (Tunnel:update)
function CoopLink.onLinkLost(game, reason)
  if CoopLink.pending then closePending(game) end
  if reason == "lost" then return end
  if CoopLink.adapter then CoopLink.adapter.closed = true end
  CoopLink.early = {}
end

-- the link came back as a new session (the partner restarted): nothing of
-- an open trade survives on their side
function CoopLink.onNewSession()
  if CoopLink.adapter then CoopLink.adapter.closed = true end
  CoopLink.early = {}
end

return CoopLink
