# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.5.0

**Los dos jugadores necesitan esta versión** (protocolo 14): a un compañero
con 1.4.1-alpha.6 o anterior se le dice que actualice.

### Añadido

- **Una sesión que sobrevive a los cortes.**
  - Cada mensaje del enlace va numerado y se guarda hasta que el compañero
    confirma que le llegó.
  - Si la conexión se cae, al volver se reenvía justo lo que el otro no
    recibió, incluido lo enviado en los segundos antes de notar el corte (antes
    se perdía), y lo que llega dos veces se descarta.
  - Si el compañero reinició el juego, empieza una sesión nueva y no recibe
    nada pensado para la anterior.
- **Tu sitio es tuyo.** Mientras el anfitrión espera a que vuelva su
  compañero, solo esa misma partida puede ocupar su lugar (cada partida tiene
  ahora su propio id de co-op). Otra máquina recibe "HOST IS BUSY", y una
  tercera que llama con la sesión en marcha, también.

### Corregido

- **Todo duplicado en una copia del juego que ya trae co-op** (el fork de
  Gen2Recomped con el co-op incorporado, del que salen los parches): NEW
  CO-OP GAME y CONTINUE CO-OP salían dos veces en el título, y la
  actualización co-op corría dos veces por fotograma, así que eventos,
  objetos y mensajes podían aplicarse dos veces. En un juego así, el mod
  ahora no hace nada (lo dice en `log.txt`) y solo funciona el co-op del
  juego.
- **Objetos duplicados al usar medicina en el Pokémon del compañero.** Si la
  respuesta llegaba tarde, la curación era gratis.
  - Ahora el objeto se aparta al enviarlo y solo vuelve a la mochila si no
    sirvió.
  - El juego del compañero recuerda cada petición y no cura dos veces la
    misma.
  - Una respuesta que nunca llegó se pregunta otra vez en el siguiente enlace.
- **Clones o Pokémon perdidos en el Cable Club tras un corte.**
  - El intercambio ya no se cierra en un corte corto: el último CONFIRM llega
    y los dos juegos lo completan.
  - Cada intercambio lleva su id, y un CONFIRM viejo ya no prepara el
    siguiente.
- **Eventos de historia dados dos veces.**
  - Cada evento tiene su nombre y la partida recuerda los que ya vivió (un
    reenvío, o la cola de un juego que salió sin guardar, ya no lo repite).
  - Un evento del compañero que llega a mitad de tu propio script espera a
    que termine. Antes, hablar los dos con el mismo NPC, o el script del líder
    después de un combate co-op, podía dar el objeto dos veces.
- **Regalo Misterioso.**
  - El "una vez al día" va por el calendario real, no por el reloj
    compartido.
  - Un SÍ que llega después de la espera completa el intercambio, en vez de
    perderse.
  - Un regalo que tu juego no tiene llega como otro de la misma rareza.
- **Concurso de Bichos:** un empate exacto daba el 1.er premio a los dos;
  ahora los dos juegos lo rompen igual.
- **Guardería unida:** el Pokémon del compañero ya no cría con tu partida
  cuando juegas con otra persona.
- **Salón de la Fama:** solo cuenta como co-op si tu compañero entró contigo.
- **Un invitado rechazado (otra versión, otro juego) ya no cierra la sesión
  del anfitrión,** que sigue escuchando. El invitado ve el motivo.
- **Visitantes:**
  - uno con otra versión recibe un aviso y vuelve a casa;
  - una posición atrasada ya no lo mueve hacia atrás;
  - su chat queda limitado a unas pocas líneas seguidas.
- Un paquete que se hacía pasar por un evento interno ("net_disconnect") ya
  no puede tumbar la sesión.
- El invitado que reconecta por una red lenta (ZeroTier con relay) espera
  cada vez un poco más entre intentos, en lugar de cortar el intento cada
  2 segundos.

## 1.4.1-alpha.6

**Both players need this version** (link protocol 13): a partner on alpha.5
or older is told to update.  Works on Gen2Recomped **0.8.46** (the patches are
made against it) and still on 0.8.45.

### Fixed

- **Crash using an X ATTACK (or any X item, DIRE HIT, GUARD SPEC.) in a
  co-op double** ("attempt to index local 'target'").  Behind the crash, the
  boost only ever reached your own screen: from then on every hit did
  different damage on the two games.  It now rides with your turn and lands
  on both.
- **The POKé FLUTE in a co-op double** played a single battle's turn on your
  screen alone; it now wakes the whole field on both.  The **POKé DOLL** is
  refused while battling together (it would end the battle on one screen).
- **The wrong Pokemon sent out when one of you takes a while to choose.**
  After a faint, the other screen gave up after 30 seconds and sent in the
  first healthy Pokemon itself -- and when you then chose another, each
  screen had a different one out for the rest of the battle (and your late
  pick sat waiting for the next faint).  Your partner's screen now waits for
  your own pick for as long as you are linked.
- **Reviving your partner did nothing**: with their whole team down their
  slot stayed empty, so the revived Pokemon never came back in.  It now
  does, at the end of the turn: its owner picks who goes in.
- **Experience lost when the battle got out of step**: when the host's win
  closed your battle with a foe still standing on your screen, its
  experience was never paid.  It is now, before the battle closes.
- **A foe's switch in a double** (JUGGLERs and the like) could pick the
  Pokemon already out in the other slot -- two of it on the field.
- **The POKéGEAR clock showed your PLAY TIME**, not the time: its hour and
  day had nothing to do with day and night outside or the weekday Mom's
  clock set.  It now shows the clock the game runs on (shared, when you
  share a clock).

### Changed

- **A big battle waits for your partner.**  The BURNED TOWER's rival walks
  up the moment you step in, so whoever got there first always fought him
  alone -- and when the partner walked in, the scene played again on their
  game.  Now, with your partner linked but elsewhere, a gym leader / rival /
  League battle asks **WAIT (partner) or SOLO**; WAIT holds the scene until
  they walk onto the map (up to 5 minutes, B to go solo), their game does not
  play its own copy, and the usual CO-OP / SOLO question follows.

## 1.4.1-alpha.5

Plays with 1.4.1-alpha.3 and alpha.4 (same link protocol, 12).

### Added

- **Kris on a Gold or Silver screen.**  A Crystal partner who plays as Kris
  was drawn as the Gold/Silver boy: those games have no Kris.  Import a
  **Crystal** ROM in the mod's IMPORT slot (the same one the emotes use --
  they keep working from it) and her walking and bike sprites and her battle
  back pic are cut from it once, on your device, and used for her.  Without
  a Crystal ROM nothing changes.
- **Your partner's own back pic in a co-op double** whenever it is not yours:
  Kris beside the boy, or the boy beside Kris, also in Crystal (where both
  used to stand in the same one).

## 1.4.1-alpha.4

Plays with 1.4.1-alpha.3 (same link protocol, 12): only how your partner
looks changed.

### Added

- **Gen 2: your partner wears their version's colour too** -- GOLD in gold,
  SILVER in silver, CRYSTAL in crystal blue (visitors as well).  A version
  the mod does not know keeps the old blue.

## 1.4.1-alpha.3

**Both players need 1.4.1-alpha.3** (link protocol 12: an alpha.2 partner
would resolve some turns differently).  After installing it, restart the
game once.

### Added

- **Heal your partner's Pokemon from your bag** in a co-op double: the bag's
  party screen lists your three, then theirs.  The heal lands on their real
  Pokemon, on their screen too.
- **Gen 1: your partner wears their version's colour** -- RED in red, BLUE in
  blue, YELLOW in yellow (visitors too).  Gen 2 keeps the blue.
- **Host and keep playing.**  On the HOSTING screen B goes back to the game
  and the session stays open for a partner or visitors; the co-op menu then
  shows HOSTING... (with how many are visiting) and STOP HOSTING.

### Fixed

- **Confusion, sleep and other statuses no longer differ between the two
  screens.**  A WRAP / BIND held a foe on one copy of the battle and not on
  the other, and the end-of-turn effects (poison, LEECH SEED) ran in a
  different order on each; from then on every roll differed.  A test now
  plays hundreds of status-heavy doubles and compares every Pokemon on both
  copies after every turn.
- **Items in a co-op double no longer risk a desync**: a heal now travels
  with the turn and both copies apply it as the turn opens, instead of
  whenever it arrived.
- **The host leaving no longer strands the partner**: the team picker of an
  invite closes when the host cancels or drops, instead of staying open.
- **A battle the story lets you lose** (Oak's Lab, the Cherrygrove rival),
  lost together, now heals the partner's team the way the scene heals the
  host's; it was left at 0 HP.
- **VISIT**: cancelling the host was the only way out of its screen, and it
  sent every visitor home; HOST again restarted the session.
- **"PORT 7777 IN USE"** is shown at the top of the menu (it covered EXIT),
  with what to do: another game on this machine is hosting -- JOIN or VISIT it.

## 1.4.1-alpha.2

Plays with 1.4.1-alpha.1 (same link protocol, 11): only how a co-op double
looks changed.

### Fixed

- **A switch no longer drags your partner's Pokemon along.**  While one
  player's new Pokemon was on its way out, the whole side was hidden -- the
  partner's Pokemon and both HUDs -- and the partner's then came back in the
  same grow-in, as if it had been sent out too.  Now only the switching slot
  empties, the poof lands on it (on the partner's side as well), and the
  other Pokemon stays put.
- **The foe's two Pokemon come out one at a time**, each with its own cry
  (and its own sparkle, if shiny), instead of both in the same frame.
- **The partner's HUD waits for the partner's ball** in the intro, instead of
  showing before "TOBY sent out ...".

## 1.4.1-alpha.1

**Both players need 1.4.1-alpha.1** (link protocol 11: a 1.4.1-alpha partner
would still send an egg out in a battle between you).  After installing it,
restart the game once.

### Added

- **VERSION** in the co-op menu (linked or not): highlighted, the box above
  shows this mod's version and link protocol, and once linked your partner's
  version.  A partner the link refuses for being on another protocol is now
  named by version ("PARTNER HAS V1.3.1"), on both sides.

### Fixed

- **An egg can no longer fight in BATTLE P1 VS P2.**  The cable never carried
  the egg flag, so an egg leading a party came out as a Pokemon -- on both
  machines -- and a traded egg arrived hatched.  The egg now crosses the cable
  as an egg (it stays one in a trade), and stays out of a link battle, as on
  the cartridge.
- **Going back to the launcher no longer leaves half the co-op unpatched.**
  The engine keeps its modules loaded across a trip to the launcher, still
  holding the last load's co-op code, so the next boot -- the game after the
  launcher's backdrop, or after updating the mod in the MODS panel -- could not
  patch them again ("the engine function's source is not readable": battles,
  targeting, the bag, the party menu, EXP...), stacked a second copy of every
  wrapper, and kept the old version of the mod's own modules (an update did
  not take until a restart).  The mod now writes down every change it makes
  to the engine; a new boot puts them back (only where they are still the
  mod's, so another mod's wrappers stay), drops the old link and modules, and
  patches afresh.  A Gen 3 game booted next no longer keeps Gen 2's co-op.

## 1.4.1-alpha

**Both players need 1.4.1-alpha** (link protocol 10: a 1.4.0 partner would
resolve the same co-op double differently, so the two are not allowed to pair).
An alpha: try it, and report what the foes do.

### Changed

- **The foes of a co-op double think as a team.** They scout your Pokemon
  first -- what each of yours can do to each of theirs, who can knock out
  whom, who moves first -- and the first to choose plans the whole turn with
  its partner: they split up, or gang up on a Pokemon neither could knock out
  alone.  The dangerous Pokemon is the one they want gone, not just the frail
  one, and a knockout is worth more when it lands before the target moves.
  They PROTECT when one of you is about to knock them out first, heal only
  while it still helps, set up only when it is safe, raise REFLECT or LIGHT
  SCREEN against the kind of attack you carry, never both put the same
  Pokemon to sleep, and only EXPLODE when they are going down anyway.

- **The co-op menu is three short pages instead of one long list.**  The
  first page is seven rows that fit without scrolling -- CHAT, EMOTE, WARP TO
  PARTNER, PARTNER, POKéDEX, RULES, DISCONNECT -- with what you do with your
  partner (ITEM FOR PARTNER, WATCH, TRADE, BATTLE P1 VS P2, MYSTERY GIFT)
  under PARTNER and the shared ON/OFF rules under RULES, where the box above
  says what the highlighted rule does.  B steps back a page.

### Fixed

- **One look for every emote bubble.**  Without the cartridge's bubbles (no
  ROM imported in MODS), a trainer's "!" was the field's plain box, the
  following Pokemon's find another bubble again, and the old emote screen
  was still behind EMOTE in the offline menu.  The mod's drawn bubbles are now
  the field's sheet when there is no ROM, so townspeople, trainers, your
  following Pokemon and the co-op all show the same ones; importing the ROM
  still swaps in the cartridge's.  The offline EMOTE opens the same picker.
- **A hit aimed at a Pokemon that switched out now lands on the one that came
  in.**  The target was remembered as the Pokemon, not the spot, so the hit
  fell on the one sitting on the bench and the one that came in took nothing.
  Both ways: a trainer's switch no longer dodges your attack either, and a
  THRASH or OUTRAGE follows the spot too.

## 1.4.0

**Both players need 1.4.0** (link protocol 9: a 1.3 partner would not
understand the new invites).

### Added

- **TEAM UP WILD** (shared rule, off by default): a wild Pokemon that jumps
  out of the grass -- a step or SWEET SCENT, never a scripted one, a roaming
  beast or the Bug-Catching Contest -- while your partner is within eight
  steps on the same map asks them to join.  On a yes it is a co-op double
  against the wild Pokemon and its twin, in the same lockstep as a trainer
  double.  No BALL can be thrown together; RUN gets you both away.
- **WATCH <partner>**: a small live screen of your partner's battle -- their
  foe and their Pokemon, levels, HP bars, status and the line on their text
  box.  Frames only go out while someone is watching.
- **VISIT**: up to four more players can walk the host's world while a
  session is open (the session's port + 1).  Everybody sees everybody, with
  names over their heads, and the chat and emotes reach the whole group.
  Visitors play their own game: no story, battles or items cross with them.
- **SOUL LINK** (shared rule): the two-player Nuzlocke.  The first catch of
  each of you in an area (a cave's or a tower's floors are one area) is
  bound to the other's; when either faints both are gone, and no POKEMON
  CENTER or REVIVE brings them back.  A faint while apart is settled on the
  next link.  SOUL LINKS lists the pairs.
- **LINK DAYCARE** (shared rule): with one Pokemon in your Route 34 DAY-CARE
  and one in your partner's, theirs is the second parent at yours (and yours
  at theirs).  Each game lays its own egg.  Nobody's Pokemon leaves its save:
  only a copy travels, and only the breeding sums see it.
- **The BATTLE TOWER in multi** (Crystal): each of the seven battles can be a
  co-op double.  The partner is asked wherever they are, brings up to three
  Pokemon under the level cap, fights the same opponent and gets their team
  back as it went in.  The challenge and its prizes are the challenger's.
- **MYSTERY GIFT** over the link: once a day per partner, each game picks an
  item for the other from the cartridge's own table.
- **POKeDEX**: what your partner has caught that you have not, and the other
  way round.  **SHARE DEX** (shared rule) marks each other's catches as SEEN.
- **Your partner in the POKeGEAR**: first in the phone book (a call opens the
  chat and rings their POKeGEAR) and a blinking mark on the town map.
- **Picking the link back up**: the save remembers the last link; the host
  listens again and the guest dials again on their own when the save is back
  on the map (MODS -> PkMultiplayer -> OPTIONS -> AUTO RECONNECT).  A
  RECONNECT row in the menu, and the round trip in ms in its header.
- **The walking Pokemon** sparkles when it is shiny, and a friendly one now
  and then finds an item ("!" over it); talk to it to get it.

### Changed

- **Move animations land on the Pokemon actually there**, in single battles
  as well as doubles.  The cartridge aims every hit at the middle of the full
  56x56 box, so on a small foe (Pidgey, Natu...) it landed in the air above
  it; each side's half of an animation now goes onto the pic's own pixels.
  With DramaticShapes' 3D battles each side is also corrected when the camera
  swings.
- With DramaticShapes on, co-op doubles are fought on the classic battle
  screen: its 3D staging only knows singles and drew every name and HP bar
  twice.
- The co-op menu scrolls when it has more than nine rows.

## 1.3.1

Same link protocol (8): plays with 1.2.0 and 1.3.0.

### Fixed

- **Stack overflow after going back to the launcher.**  Loading the game a
  second time in the same session left two of the mod's module searchers in
  `package.loaders`, each calling the other; the first engine module still
  waiting for its patch (typically the battle code, when a fight started)
  crashed the game.  There is now one searcher for the whole process, and it
  patches for the load that is current.

## 1.3.0

Works with a 1.2.0 partner (same link protocol, 8); they just do not see
your walking Pokemon until they update.

### Added

- **Your Pokemon follows you**, the way it does in HeartGold / SoulSilver:
  the first party Pokemon that is not fainted (and not an egg) walks one
  cell behind you, wearing its party menu icon -- the cartridge's own
  overworld Pokemon sheets, from your ROM import.  It changes when the lead
  does, hides on the bike and while surfing, crosses map seams with you,
  and A on it shows how it feels about you (its friendship).  Gold, Silver
  and Crystal.  ON by default: MODS -> PkMultiplayer -> OPTIONS ->
  POKEMON FOLLOWS YOU.
- In co-op you see your partner's walking Pokemon behind them too.

### Fixed

- The README still said the emotes could only be drawn bubbles; since 1.2.0
  they are the cartridge's own when you import your ROM for the mod.

## 1.2.0

Both players need 1.2.0: the link protocol is now 8 (the warp request is new).

### Added

- **The cartridge's own emote bubbles again.**  Optional: import your Gold,
  Silver or Crystal ROM for this mod in the MODS panel (IMPORT on the mod's
  row).  The eight bubbles are cut from it once on your device and used for
  the co-op emotes and for every trainer's "!", as in the old co-op build.
  Nothing from the ROM ships with the mod.
- Without the ROM, the emotes are now this mod's own drawn 16x16 bubbles
  instead of the tiny text pills.

### Changed

- **WARP TO PARTNER, much harder to use:** only to a town or city you have
  already visited (the places FLY can take you), your partner has to say
  YES, and it recharges for ten minutes.  A NO costs no recharge.

### Fixed

- TRADE and BATTLE P1 VS P2 with no POKeMON crashed the game (the link
  battle has no lead to send out).  Now you cannot ask without a POKeMON, a
  partner with none declines on their own, and both are told why.

## 1.1.0

### Added

- Playable on phones: a **CHAT** row at the top of the linked co-op menu, and
  **SELECT** opens the chat in a co-op double (on the action menu, or while
  waiting for the partner) -- the touch layout has no T key.  On a phone the
  chat raises the on-screen keyboard, and **A** brings it back if it was
  swiped away.

### Fixed

- The ZeroTier address now shows on iOS and Android.  It is found by asking
  the OS which address it would route to each of ZeroTier's address pools,
  which needs no shell; the `ip` / `ipconfig` lookups remain as the fallback
  on desktops (for networks on a custom range).
- Closing the chat no longer turns text input off on desktops.
- The linked co-op menu fits its box again: no RESUME row (B closes the
  menu), the first row clear of the border, and PARTNER HEAL short enough
  not to run past the edge.

## 1.0.0

### Added

- The co-op from the PkMplayer fork (its "v29"), now as a mod for the
  official Gen2Recomped: no fork to download any more.
- The link (LAN / ZeroTier), the partner's avatar, chat and emotes.
- Co-op double battles in lockstep, with HeartGold/SoulSilver's doubles
  rules and a doubles AI for the foe.
- Shared story events, Hall of Fame, Bug-Catching Contest, clock and saves.
- Trades through the Cable Club over the link; P1 vs P2 battles.
