<a id="english"></a>

<h1 align="center">PkMultiplayer</h1>

<p align="center"><b>Two-player online co-op for Gen2Recomped: play through Pokémon Gold, Silver,<br>
Crystal (and Red/Blue/Yellow) with a friend, in the same world.</b></p>

<p align="center">
  <a href="https://github.com/Mochx07/PkMultiplayer/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Mochx07/PkMultiplayer?label=release&color=39ff88"></a>
  <a href="https://github.com/Mochx07/PkMultiplayer/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Mochx07/PkMultiplayer/total"></a>
  <a href="https://github.com/Mochx07/PkMultiplayer/releases"><img alt="Nightly" src="https://img.shields.io/github/v/release/Mochx07/PkMultiplayer?include_prereleases&label=nightly&color=ff9f1c"></a>
  <a href="https://github.com/UNDERdecoded/Gen2Recomped"><img alt="Gen2Recomped 0.8.49 (stable) / 0.8.60+ (nightly)" src="https://img.shields.io/badge/Gen2Recomped-0.8.49%20%7C%200.8.60%2B%20nightly-blue"></a>
  <img alt="2 players" src="https://img.shields.io/badge/players-2%20(%2B4%20visitors)-orange">
  <img alt="English and Spanish" src="https://img.shields.io/badge/language-EN%20%7C%20ES-lightgrey">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

<p align="center">English · <a href="#espanol">Español</a> · <a href="https://mochx07.github.io/PkMultiplayer/">Website</a></p>

Two players, one Johto. You see each other walk, chat (**T**), talk (**V**) and emote
(**Y**), live the story's events together, catch wild Pokémon together, trade through the
Cable Club and fight trainers as a **2-vs-2 double battle** in lockstep, with
HeartGold/SoulSilver's doubles rules.

**Not an MMO:** it's your own playthrough, with a friend in it. No third-party
servers — one of you hosts the session from inside the game.

It is a **mod** for the official [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped):
no fork of the game to download, just this zip.

<p align="center">
  <img src="docs/img/coop.gif" alt="Two players walk together through New Bark Town, trade emotes and a chat message, then fight a 2-vs-2 double battle" width="512">
</p>

| 2-vs-2 double battles | Emotes and your partner's name |
|---|---|
| <img src="docs/img/dobles.png" alt="A co-op double battle against Pidgey and Pidgeotto, with P1 and P2 tags" width="360"> | <img src="docs/img/emotes.png" alt="Two players with emote bubbles over their heads and the partner's name tag" width="360"> |
| **Co-op menu** | **Live chat** |
| <img src="docs/img/coop-menu-en.png" alt="The co-op menu: chat, emote, ready, warp, partner, Pokédex, rules" width="360"> | <img src="docs/img/chat.png" alt="The chat box with messages between MOCHI and TOBY" width="360"> |

### New in 2.0 (nightly)

The **2.0 nightly** builds are test builds on the [releases page](https://github.com/Mochx07/PkMultiplayer/releases)
(marked *Pre-release*); **1.6.17 stays the stable one**. The nightly needs **Gen2Recomped 0.8.60 or later**.
Starting with **2.0.0-nightly.3**, the link uses **protocol 17** (both players must be on nightly.3+).

- **Gen 1 co-op parity (Red, Blue and Yellow):** all 8 Kanto gyms, the Pokémon League and Hall of Fame,
  rival 2-vs-2 battles, catchable legendary bosses (Articuno, Zapdos, Moltres, Mewtwo), shared Kanto
  storyline (S.S. Anne, Pokémon Tower, Rocket Hideout, Silph Co., Safari Zone, Snorlax), Kanto's Bike
  Trial, direct Cable Club linking with your partner, and separated 2-vs-2 back sprites.
- **Edition matrix (protocol 17):** Red/Blue with Yellow and Gold/Silver with Crystal share one story
  through a single receiver filter while keeping edition-exclusive events safely in their own save.
- **Official Link Hub (no VPN needed):** `HOST ONLINE` and `JOIN` by code (up to 24 characters, Ctrl+V
  or touch keyboard) link straight through the game's own connection ladder and official Link Hub.
- **2-vs-1 wild co-op and timed joint catching:** wild co-op battles face a single wild Pokémon at full
  1-vs-1 sprite scale (no mirrored twin); both players throwing a Ball on the same turn triggers a
  shrinking-ring timing bonus (up to ×3 catch rate), followed by **who keeps it** (me / my partner /
  let fate decide) with a synchronized **roulette** whenever both players pick conflicting options.
- **Partner on the Town Map:** your partner's avatar head shows directly on the Gen 1 and Gen 2 Town
  Map, even across different editions.
- **Mobile touch support:** touch controls across the mod's menus, invites, VS screens, emotes and
  code entry; no keyboard hints on phones and on-screen/gamepad **R** for push-to-talk (**PUSH R**).
- **Voice chat:** push-to-talk (**V** / **R**) or open mic, louder the closer you stand on the map.
- **Time Capsule:** Red/Blue/Yellow and Gold/Silver/Crystal can link to chat, emote and trade.
- **Your partner's feed & QoL:** partner catches, evolutions and eggs on your screen; level-ups in a
  corner card; Battle Tower in duo (Crystal); live Bug-Catching Contest; Tailscale, Radmin VPN,
  Hamachi and WireGuard besides ZeroTier; Discord "Ask to Join" and **AFK** status; solo emotes.

### What makes it different

- **The story, together**: events, world items and badges happen in both saves at once.
- **2-vs-2 doubles against the game's own trainers and leaders**, in lockstep, with HeartGold/SoulSilver's doubles rules.
- **Soul Link** (the two-player Nuzlocke), a **linked Day-Care** and the **Battle Tower in multi** (Crystal).
- **Your lead Pokémon follows you**, HGSS-style, and your partner sees it.
- **Catching together and voice chat** (2.0 nightly).
- **English and Spanish**, switchable in the mod's options.

## Installation

1. Have the **official Gen2Recomped** installed, with your Gold/Silver/Crystal ROM already imported.
2. Download `PkMultiplayer-<version>.zip` from
   [Releases](https://github.com/Mochx07/PkMultiplayer/releases).
3. In the launcher, open the **MODS** tab and press **Import mod .zip**, or drop the
   zip on the window. Make sure the mod is enabled.
4. Start the game. **Both players** need the mod, on the same version.

The launcher tells you when a new version is out (the mod checks its GitHub releases).

## Connecting

- **Same network (LAN):** one player presses START → **CO-OP ONLINE** → **HOST**. The
  host sees a short **code** (for example `30AG-0B4`) and their IP. The other goes to
  **JOIN** → **TYPE A CODE** and types the code (or pastes it with **Ctrl+V**), or
  **TYPE THE IP** to dial the IP in with the D-pad.
- **Over the internet:** both join the same free VPN network —
  [ZeroTier](https://www.zerotier.com/), and in the 2.0 nightly also
  [Tailscale](https://tailscale.com/), [Radmin VPN](https://www.radmin-vpn.com/), Hamachi or
  WireGuard. The host's code already carries their VPN address; in the nightly the host
  screen lists every address it found with its VPN's name (**SELECT** switches) and the code
  follows the one shown. The port is UDP **7777**; change it on the **PORT** row (for
  example, for two games on the same PC).
- **JOIN** remembers the last three hosts you joined: pick one and you're in.
- If something fails, the menu gives the full reason and what to do (open the UDP
  port in the firewall, the same mod version, etc.).
- From the title screen you can also start or carry on a game together: **NEW CO-OP GAME**
  / **CONTINUE CO-OP** in 1.6.17, a single **CO-OP** row that asks CONTINUE or NEW GAME in the
  2.0 nightly (which first asks your **name**, the one your partner sees).

## On a phone (iOS / Android)

| | |
|---|---|
| Chat | START → CO-OP ONLINE → **CHAT**; in a double battle, **SELECT**. The phone's keyboard opens, its return key sends, and **A** brings the keyboard back if you closed it. |
| Emotes | START → CO-OP ONLINE → **EMOTE** |
| ZeroTier IP | shown on its own when the ZeroTier app is connected (networks on ZeroTier Central's automatic ranges) |

## Language

The mod speaks English and Spanish: MODS → PkMultiplayer → OPTIONS →
**LANGUAGE / IDIOMA** (**AUTO** follows the language you translate the game to in the
launcher; **ESPANOL** pins Spanish).

## Original emotes (optional)

Out of the box the emotes are bubbles the mod draws. For **the cartridge's own**:
launcher → **MODS** → on PkMultiplayer press **IMPORT** and pick your Gold, Silver or
Crystal ROM. The mod cuts the 8 bubbles out once, on your device (the trainers'
original "!" comes back too). The mod ships nothing from the ROM.

## What's included

| | |
|---|---|
| Shared world | your partner walks on your map, with their name above them |
| Walking Pokémon | your first (non-fainted) Pokémon walks behind you, HeartGold/SoulSilver-style, with its cartridge icon; talk to it with **A**. Your partner sees it too. It sparkles when shiny, and when it loves you it sometimes finds items (a **!** above it: talk to it). Switch it off under MODS → PkMultiplayer → OPTIONS → POKEMON FOLLOWS YOU. Gold/Silver/Crystal; also Red/Blue in the 2.0 nightly (with the cartridge's body-shape icon); Yellow keeps its Pikachu |
| Chat | **T** key (also during a double battle); on phones, see above. In the 2.0 nightly your partner sees only what you send, "typing..." shows once there is a letter, and in battle the chat sits in the text box with messages in a small strip at the top left |
| Voice chat | (2.0 nightly) MODS → PkMultiplayer → OPTIONS → **VOICE CHAT**: off, **PUSH V** (hold V, or R on a gamepad) or **OPEN MIC**; **VOICE BY DISTANCE** makes your partner louder the closer you stand (silent on another map, full in a battle together). A speaker over them while they talk |
| Emotes | **Y** key |
| Double battles | against trainers, in lockstep, with HeartGold/SoulSilver's doubles rules and a foe AI written for doubles |
| Shared story | what one player lives, the other lives too; important battles ask first (in the 2.0 nightly, walking in together lets the host lead the scene). In Red/Blue/Yellow too: the leaders' badges and TMs, the Mt. Moon fossil (one each), gifts. Gold/Silver and Crystal number their events differently: in 1.6.17 they don't share the story; in the 2.0 nightly the **G/S+C STORY** rule (experimental, off by default) translates it |
| Ready / Not ready | **R** key (or **READY** in the menu): your partner sees **OK** next to your name before a big battle |
| Co-op result | after each co-op double, for a few seconds at the top: each player's knockouts and EXP, and the Pokémon that did the most. In the 2.0 nightly, level-ups of both teams show in a corner card during the battle |
| Your partner's feed | (2.0 nightly) their catches, evolutions and hatched eggs as a card in the corner and an emote over their avatar |
| Where they are | if your partner is out of view, an arrow on the screen edge points their way (in their version's colour in the nightly, pulsing when they are on another map) and the place's name shows at the top |
| Extras | Cable Club trades, P1 vs P2, items for your partner's Pokémon, a shared Bug-Catching Contest and Hall of Fame, a shared clock |
| Warp | only to towns you've already visited (like FLY); your partner has to accept, and it recharges in 10 minutes |
| Wild Pokémon together | **TEAM UP WILD** rule: a wild Pokémon that jumps you while walking with your partner nearby (8 steps, same map) asks them to join, and you fight a double against it and its twin. **RUN** takes you both out. In 1.6.17 there are no Poké Balls together |
| Catch together | (2.0 nightly) a ball is your turn's action; both throwing in one turn is a joint throw (the better ball, catch rate ×1.5). Caught: **WHO KEEPS IT?** — the same answer from both wins, a name beats "let fate decide", otherwise a coin decides (the same coin on both games) |
| Watch their battle | **WATCH**: a little screen with your partner's battle, live |
| Visitors | up to 4 more players walk into the host's world with **VISIT** (session port + 1): they walk, chat and emote with everyone; each plays their own game |
| Soul Link | **SOUL LINK** rule: the two-player Nuzlocke. Each player's first catch in an area is bound to the other's; if one falls, both fall and can't be healed. **SOUL LINKS** shows the pairs |
| Linked Day-Care | **LINK DAYCARE** rule: with a Pokémon in your Day-Care and another in your partner's, theirs is the second parent in yours. Each takes their own egg; no Pokémon leaves its save |
| Battle Tower | (Crystal) each battle of a challenge can be a co-op double: your partner joins from wherever they are, with Pokémon under the level cap, and their team comes back as it went in. In the 2.0 nightly they join once and the seven battles go on without asking again |
| Time Capsule | (2.0 nightly) Red/Blue/Yellow with Gold/Silver/Crystal: chat, emotes and trades through the Cable Club, under the game's own Time Capsule rules; nothing else crosses between the two worlds |
| Discord | (2.0 nightly) "Ask to Join" on your profile while hosting (a click dials in), "Co-op with ..." in your status, and **AFK** after 3 minutes (also a Zzz over your avatar on your partner's screen) |
| Mystery Gift | **MYSTERY GIFT**: once a day per partner, each game picks an item for the other |
| Pokédex | **POKéDEX**: what your partner has and you don't, and the other way round. **SHARE DEX** rule: their catches count as SEEN in yours |
| Pokégear | your partner tops the phone list (calling them opens the chat and rings their Pokégear) and their marker blinks on the map |
| Reconnecting | the game remembers the last link: the host listens again and the guest calls back on its own (**AUTO RECONNECT** option); **RECONNECT** row in the menu. After a drop, what was sent in those seconds arrives once you're back, only once, and only the partner's own game can take their seat |

The co-op menu (START → CO-OP ONLINE while linked), nine rows without scrolling:
CHAT, EMOTE, READY, WARP TO PARTNER, **PARTNER ▶** (ITEM FOR PARTNER, WATCH, TRADE,
BATTLE P1 VS P2, MYSTERY GIFT), POKéDEX, **RULES ▶** (STORY SYNC, TEAM UP WILD, SHARE
DEX, LINK DAYCARE, PARTNER HEAL, SOUL LINK, SOUL LINKS; the box above explains the
highlighted rule), VERSION and DISCONNECT. B goes back a page. **VERSION** opens the
link status: ping, loss, resent messages, reconnections, battle desyncs corrected and
both players' versions. Not linked: RECONNECT, HOST, JOIN, VISIT, PORT, STORY SYNC,
EMOTE, VERSION, EXIT. The rules are saved with the game.

**Move animations** land on the Pokémon actually there, in single battles too: the
cartridge aims at the center of the 56×56 box, so against a small Pokémon (Pidgey,
Natu...) the hit landed in the air.

## Known limitations

- It only works in **Gen 1 and Gen 2** games. In the rest the mod loads but does nothing.
- Without your ROM imported for the mod, the emotes are bubbles the mod draws (see
  "Original emotes").
- PkMultiplayer has no 3D of its own. If you also use **DramaticShapes** (a separate 3D
  mod bundled with Gen2Recomped), the co-op works in its 3D world, but co-op doubles are
  played on the classic screen (its 3D only knows single battles).
- Visitors don't share the story, battles or items: only the world, the chat and the emotes.
- 2.0 nightly: voice chat needs a microphone the game can open (push-to-talk is **V** on a
  keyboard or **R** on a gamepad; on a phone without one, use open mic); IPv6 addresses are
  not offered, because the game's network library (ENet 1.3.13 in LÖVE 11.5) only speaks
  IPv4 — every VPN listed also gives an IPv4 one;
  Gold/Silver ↔ Crystal story is experimental and leaves some scenes apart.
- The walking Pokémon uses the party-menu icon (two frames, no back view), which is
  what the cartridge has; it hides on the bike and while surfing.
- If Gen2Recomped changes the functions the mod touches a lot, the mod notices and
  leaves that module unpatched (you'll see it in `log.txt`). Then PkMultiplayer needs
  an update.

## Logs

`coop.log` and `log.txt` are in the game's save folder (Linux:
`~/.local/share/Gen2Recomp/`, Windows: `%APPDATA%\Gen2Recomp\`). If something fails,
open an [issue](https://github.com/Mochx07/PkMultiplayer/issues/new/choose) and attach
both players' `coop.log`.

---

<a id="espanol"></a>

# PkMultiplayer en español

<p align="center"><a href="#english">English</a> · Español</p>

Juega **Pokémon Oro, Plata o Cristal** (y Rojo/Azul/Amarillo) con un amigo en el
mismo mundo: se ven caminar, chatean, hablan por voz, viven los eventos de la historia
juntos, capturan juntos y pelean contra los entrenadores en **combates dobles 2 contra 2**.

**No es un MMO:** es tu partida de siempre, con un amigo dentro. Sin servidores
de nadie: uno de los dos aloja la sesión desde su propio juego.

Es un **mod** para el [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped)
oficial. No hace falta descargar ningún fork del juego, solo este zip.

### Novedades de la 2.0 (nightly)

Las **2.0 nightly** son versiones de prueba en [Releases](https://github.com/Mochx07/PkMultiplayer/releases)
(marcadas *Pre-release*); **la estable sigue siendo la 1.6.17**. La nightly necesita **Gen2Recomped 0.8.60
o posterior**. Desde la **2.0.0-nightly.3** el enlace usa **protocolo 17** (los dos jugadores deben
usar nightly.3+).

- **Paridad de Gen 1 (Rojo, Azul y Amarillo):** los 8 gimnasios de Kanto, la Liga Pokémon y el Salón
  de la Fama en 2 contra 2, rival en 2 contra 2, legendarios capturables como jefes (Articuno,
  Zapdos, Moltres, Mewtwo), historia co-op de Kanto (S.S. Anne, Torre Pokémon, Guarida Rocket,
  Silph S.A., Zona Safari, Snorlax), Contrarreloj en bici en Ruta Ciclista, enlace directo en el
  Club de Cable y espaldas separadas en los dobles de Gen 1.
- **Matriz de ediciones (protocolo 17):** Rojo/Azul con Amarillo y Oro/Plata con Cristal comparten
  historia con un solo filtro al recibir, manteniendo los eventos exclusivos de edición a salvo en
  su propia partida.
- **Link Hub oficial sin VPN:** `HOST ONLINE` y `JOIN` por código (hasta 24 caracteres, Ctrl+V o
  teclado táctil) conectan directo a través de la escalera de red y el Link Hub oficial del juego.
- **Salvajes 2 contra 1 y captura conjunta sincronizada:** los salvajes en pareja son un solo Pokémon
  con su sprite completo de 1 contra 1; si ambos lanzan Ball en el mismo turno sale un aro de puntería
  (hasta ×3 de captura) y luego deciden **quién se lo queda** con una **ruleta** sincronizada cuando
  eligen opciones distintas.
- **Compañero en el Mapa:** la cabeza de tu compañero se ve en el Mapa de Gen 1 y Gen 2, incluso
  entre ediciones distintas.
- **Soporte táctil en móvil:** toque en las pantallas del mod (menús, invitaciones, VS, emotes y
  teclado táctil para códigos), sin pistas de teclado y botón **R** para hablar (**PUSH R**).
- **Chat de voz:** pulsar **V** / **R** o micro abierto, más fuerte cuanto más cerca estén en el mapa.
- **Cápsula del Tiempo:** Rojo/Azul/Amarillo con Oro/Plata/Cristal para chatear, mandar emotes e intercambiar.
- **Más mejoras de la 2.0:** actividad del compañero, subidas de nivel en esquina, Torre de Batalla en
  dúo (Cristal), Concurso de bichos en vivo, más VPNs (Tailscale, Radmin VPN, Hamachi y WireGuard),
  Discord («Pedir unirse» y **AFK**) y emotes también en solitario.

### Lo que lo hace distinto

- **La historia, juntos**: los eventos, objetos del mundo y medallas se viven a la vez en las dos partidas.
- **Dobles 2 contra 2 contra los entrenadores y líderes del juego**, sincronizados, con reglas de HeartGold/SoulSilver.
- **Soul Link** (el Nuzlocke de dos), **guardería compartida** y **Torre de Combate en dúo** (Cristal).
- **Tu Pokémon te sigue** como en HGSS, y tu compañero lo ve.
- **Captura en equipo y chat de voz** (2.0 nightly).
- **Español e inglés**, a elegir en las opciones del mod.

## Instalación

1. Ten el **Gen2Recomped oficial** instalado, con tu ROM de Oro/Plata/Cristal ya importada.
2. Descarga `PkMultiplayer-<versión>.zip` de
   [Releases](https://github.com/Mochx07/PkMultiplayer/releases).
3. En el launcher, abre la pestaña **MODS** y pulsa **Import mod .zip**, o
   arrastra el zip a la ventana. Comprueba que el mod está activado.
4. Abre el juego. Los **dos jugadores** necesitan el mod, y en la misma versión.

El launcher te avisa cuando sale una versión nueva (el mod comprueba sus
releases de GitHub).

## Cómo conectarse

- **Misma red (LAN):** uno pulsa START → **CO-OP ONLINE** → **HOST**. Al host
  le aparece un **código** corto (por ejemplo `30AG-0B4`) y su IP. El otro
  entra en **JOIN** → **TYPE A CODE** y escribe el código (o lo pega con
  **Ctrl+V**), o **TYPE THE IP** para marcar la IP con la cruceta.
- **Por internet:** únanse los dos a la misma red de una VPN gratuita:
  [ZeroTier](https://www.zerotier.com/) y, en la 2.0 nightly, también
  [Tailscale](https://tailscale.com/), [Radmin VPN](https://www.radmin-vpn.com/), Hamachi o
  WireGuard. El código del host ya lleva su dirección de la VPN; en la nightly la pantalla
  de anfitrión enseña todas las direcciones con el nombre de su VPN (**SELECT** cambia) y el
  código sigue a la elegida. El puerto es el UDP **7777**; se cambia en la fila **PORT**
  (por ejemplo, para dos juegos en el mismo PC).
- **JOIN** recuerda los tres últimos hosts a los que te uniste: elige uno y listo.
- Si algo falla, el menú dice el motivo completo y qué hacer (abrir el puerto
  UDP en el firewall, la misma versión del mod, etc.).
- Desde el título también pueden empezar o seguir una partida juntos: **NEW CO-OP GAME** /
  **CONTINUE CO-OP** en la 1.6.17; una sola fila **CO-OP** que pregunta CONTINUAR o NUEVA
  PARTIDA en la 2.0 nightly (que antes pide tu **nombre**, el que verá tu compañero).

## En el móvil (iOS / Android)

| | |
|---|---|
| Chat | START → CO-OP ONLINE → **CHAT**; en un combate doble, **SELECT**. Se abre el teclado del teléfono, la tecla de retorno envía y **A** vuelve a sacar el teclado si lo cerraste. |
| Emotes | START → CO-OP ONLINE → **EMOTE** |
| IP de ZeroTier | se muestra sola si la app de ZeroTier está conectada (redes con los rangos automáticos de ZeroTier Central) |

## Idioma

El mod habla español: MODS → PkMultiplayer → OPTIONS → **LANGUAGE / IDIOMA**
(**AUTO** sigue el idioma al que traduces el juego en el launcher; **ESPANOL**
lo fija). Para ver las tildes y la ñ en píxeles, instala también un mod de
glifos españoles; sin él, el texto sale sin tildes.

<p align="center"><img src="docs/img/menu-coop.png" alt="Menú co-op en español" width="360"></p>

## Emotes originales (opcional)

Sin nada más, los emotes son globos dibujados por el mod. Para tener **los
del cartucho**: launcher → **MODS** → en PkMultiplayer pulsa **IMPORT** y
elige tu ROM de Oro, Plata o Cristal. El mod recorta los 8 globos una vez en
tu dispositivo (también vuelve el "!" original de los entrenadores). El mod
no incluye nada del ROM.

## Qué incluye

| | |
|---|---|
| Mundo compartido | ves a tu compañero en tu mapa, con su nombre encima |
| Pokémon que te sigue | tu primer Pokémon (no debilitado) camina detrás de ti, como en HeartGold/SoulSilver, con su icono del cartucho; háblale con **A**. Tu compañero también lo ve. Si es shiny destella, y si te quiere mucho a veces encuentra objetos (un **!** encima: háblale). Se apaga en MODS → PkMultiplayer → OPTIONS → POKEMON FOLLOWS YOU. Oro/Plata/Cristal; en la 2.0 nightly también Rojo/Azul (con el icono de silueta del cartucho); Amarillo mantiene su Pikachu |
| Chat | tecla **T** (también durante un combate doble); en móvil, ver arriba. En la 2.0 nightly tu compañero ve solo lo que envías, «escribiendo...» sale con al menos una letra, y en combate el chat va en el cuadro de texto con los mensajes en una franja pequeña arriba a la izquierda |
| Chat de voz | (2.0 nightly) MODS → PkMultiplayer → OPTIONS → **VOICE CHAT**: apagado, **PUSH V** (mantener V, o R en el mando) u **OPEN MIC**; **VOICE BY DISTANCE** hace que se oiga más fuerte cuanto más cerca estén (nada en otro mapa, todo en combate juntos). Un altavoz sobre el compañero cuando habla |
| Emotes | tecla **Y** |
| Combates dobles | contra entrenadores, en lockstep, con las reglas de dobles de HeartGold/SoulSilver y una IA rival pensada para dobles |
| Historia compartida | los eventos que vive uno los vive el otro; las batallas importantes se preguntan antes. También en Rojo/Azul/Amarillo: medallas y MT de los líderes, el fósil de Mt. Moon (uno para cada uno), regalos. Oro/Plata y Cristal numeran sus eventos distinto: en la 1.6.17 no comparten la historia; en la 2.0 nightly la regla **HISTORIA O/P+C** (experimental, apagada de fábrica) la traduce. En la nightly, si entran juntos a un evento, la escena la lleva el anfitrión |
| Listo / No listo | tecla **R** (o **READY** en el menú): tu compañero ve **OK** junto a tu nombre antes de un combate grande |
| Resultado co-op | tras cada doble co-op, unos segundos arriba: los K.O. y la EXP de cada uno y el Pokémon que más hizo. En la 2.0 nightly, las subidas de nivel de los dos salen en una tarjeta en la esquina durante el combate |
| Lo que hace el compañero | (2.0 nightly) sus capturas, evoluciones y huevos en una tarjeta en la esquina y con un emote sobre su avatar |
| Dónde está | si tu compañero no está a la vista, una flecha en el borde de la pantalla apunta hacia él (en la nightly, del color de su versión y latiendo si está en otro mapa) y arriba sale el nombre del sitio |
| Extras | intercambios por el Cable Club, P1 vs P2, objetos para los Pokémon del compañero, Concurso de Bichos y Salón de la Fama compartidos, reloj compartido |
| Warp | solo a pueblos que ya visitaste (como VUELO), tu compañero tiene que aceptar, y se recarga en 10 minutos |
| Salvajes en pareja | regla **TEAM UP WILD**: un salvaje que te sale al caminar con tu compañero cerca (8 pasos, mismo mapa) le pregunta si se une, y pelean un doble contra el salvaje y su gemelo. **RUN** los saca a los dos. En la 1.6.17 juntos no hay Poké Balls |
| Captura en equipo | (2.0 nightly) la Ball es la acción del turno; si los dos lanzan en el mismo turno es un lanzamiento conjunto (la mejor Ball, ratio ×1,5). Al atraparlo: **¿QUIÉN SE LO QUEDA?** — gana la misma respuesta de los dos, un nombre gana a «a la suerte», y si no, decide una moneda (la misma en los dos juegos) |
| Ver su combate | **WATCH**: una pantallita con el combate de tu compañero en vivo |
| Visitantes | hasta 4 jugadores más entran al mundo del anfitrión con **VISIT** (puerto de la sesión + 1): caminan, chatean y mandan emotes con todos; cada uno juega su partida |
| Soul Link | regla **SOUL LINK**: el Nuzlocke de dos. La primera captura de cada uno en un área queda unida a la del otro; si una cae, caen las dos y no se pueden curar. **SOUL LINKS** muestra las parejas |
| Guardería unida | regla **LINK DAYCARE**: con un Pokémon en tu guardería y otro en la de tu compañero, el suyo es el segundo padre en la tuya. Cada uno saca su huevo; ningún Pokémon sale de su partida |
| Torre de Combate | (Cristal) cada combate de un desafío puede ser un doble co-op: tu compañero se une desde donde esté, con Pokémon bajo el límite de nivel, y su equipo vuelve como entró. En la 2.0 nightly se une una vez y los siete combates siguen sin volver a preguntar |
| Cápsula del Tiempo | (2.0 nightly) Rojo/Azul/Amarillo con Oro/Plata/Cristal: chat, emotes e intercambios por el Cable Club, con las reglas de la Cápsula del propio juego; nada más cruza entre los dos mundos |
| Discord | (2.0 nightly) «Pedir unirse» en tu perfil mientras hospedas (un clic conecta), «Co-op con ...» en tu estado y **AFK** a los 3 minutos (también un Zzz sobre tu avatar en la pantalla del compañero) |
| Regalo Misterioso | **MYSTERY GIFT**: una vez al día por compañero, cada juego elige un objeto para el otro |
| Pokédex | **POKéDEX**: lo que tiene tu compañero y tú no, y al revés. Regla **SHARE DEX**: sus capturas cuentan como VISTAS en la tuya |
| Pokégear | tu compañero encabeza la agenda (llamarlo abre el chat y le suena el Pokégear) y su marca parpadea en el mapa |
| Reconexión | la partida recuerda el último enlace: el anfitrión vuelve a escuchar y el invitado vuelve a llamar solo (opción **AUTO RECONNECT**); fila **RECONNECT** en el menú. Tras un corte, lo que se envió en esos segundos llega al volver, una sola vez, y el sitio del compañero solo lo puede ocupar su misma partida |

Menú co-op (START → CO-OP ONLINE estando conectado), nueve filas sin scroll:
CHAT, EMOTE, READY, WARP TO PARTNER, **PARTNER ▶** (ITEM FOR PARTNER, WATCH,
TRADE, BATTLE P1 VS P2, MYSTERY GIFT), POKéDEX, **RULES ▶** (STORY SYNC, TEAM UP
WILD, SHARE DEX, LINK DAYCARE, PARTNER HEAL, SOUL LINK, SOUL LINKS; el recuadro
de arriba explica la regla marcada), VERSION y DISCONNECT. B vuelve de una
página a la anterior. **VERSION** abre el estado del enlace: ping, pérdida,
mensajes reenviados, reconexiones, desfases de combate corregidos y las
versiones de los dos. Sin conectar: RECONNECT, HOST, JOIN, VISIT, PORT, STORY
SYNC, EMOTE, VERSION, EXIT. Las reglas se guardan en la partida.

Los **ataques** caen sobre el Pokémon que hay de verdad, también en combates
individuales: el cartucho apunta al centro de la caja de 56×56, y contra un
Pokémon pequeño (Pidgey, Natu...) el golpe quedaba en el aire.

## Limitaciones conocidas

- Solo funciona en juegos de **Gen 1 y Gen 2**. En el resto el mod se carga
  pero no hace nada.
- Sin tu ROM importado para el mod, los emotes son globos dibujados por el
  mod (ver "Emotes originales").
- PkMultiplayer no tiene 3D propio. Si además usas **DramaticShapes** (otro mod,
  de 3D, que viene con Gen2Recomped), el co-op funciona en su mundo 3D, pero los
  dobles co-op se juegan en la pantalla clásica (su 3D solo sabe de combates
  individuales).
- Los visitantes no comparten historia, combates ni objetos: solo el mundo,
  el chat y los emotes.
- 2.0 nightly: el chat de voz necesita un micrófono que el juego pueda abrir (para hablar se
  mantiene **V** en el teclado o **R** en el mando; en un móvil sin mando, usen el micro
  abierto); no se ofrecen direcciones IPv6, porque la librería de red del juego (ENet 1.3.13
  en LÖVE 11.5) solo habla IPv4 — todas las VPN de la lista dan también una IPv4; la historia entre Oro/Plata y Cristal es experimental y deja algunas
  escenas aparte.
- El Pokémon que te sigue usa el icono del menú de equipo (dos frames, sin
  vista de espaldas), que es lo que el cartucho tiene; se esconde en bici y
  surfeando.
- Si Gen2Recomped cambia mucho las funciones que toca el mod, el mod lo
  detecta y deja ese módulo sin parchear (lo verás en `log.txt`). En ese
  caso hay que actualizar PkMultiplayer.

## Registro (logs)

`coop.log` y `log.txt` están en la carpeta de guardado del juego
(Linux: `~/.local/share/Gen2Recomp/`, Windows: `%APPDATA%\Gen2Recomp\`).
Si algo falla, abre un [issue](https://github.com/Mochx07/PkMultiplayer/issues/new/choose)
y adjunta el `coop.log` de los dos jugadores.

---

## How it works (for developers)

The co-op needs changes in the middle of about a hundred engine functions.
The mod carries **none of the engine's code**:

- `src/` holds the co-op modules, served to `require` under the names the
  engine asks for.
- `lib/Hooks.lua` wraps the engine functions that only need co-op code
  before or after them.
- `lib/patches/*.lua` are **edits**: where each one goes (the line, plus the
  FNV-1a hashes of the lines around it), how many lines it removes, and the
  co-op's own new lines. Lines the edit only moves or re-indents are named
  by number and hash, not copied.
- `lib/Transplant.lua` reads each engine function's source from the
  player's own copy of the game, applies the edits, and compiles the result
  in an environment that resolves the engine file's locals through the
  upvalues of its own functions. If another mod (for example the bundled
  voxel mod) already wrapped a function, the co-op version goes inside that
  wrapper and the wrapper stays in place. When upstream has changed a
  function, the edits are placed by context. If they cannot be placed, that
  module is left unpatched and the log says so.

### Tests

From a Gen2Recomped checkout:

```sh
luajit <mod>/tests/run.lua <mod>/tests/coop_lockstep.lua       # each suite
luajit <mod>/tests/run.lua <mod>/tests/patch_scope.lua         # every name resolves
PKM_EAGER=1 PKM_PRE=<mod>/tests/foreign_wrapper_pre.lua \
  luajit <mod>/tests/run.lua <mod>/tests/foreign_wrapper.lua   # another mod's wrappers survive
```

`tests/drivers/coop_smoke.lua` runs two real game instances linked over
127.0.0.1 (`PKM_ROLE=host|guest`, see the file).  So do `wild_together.lua`,
`watch_smoke.lua` and `tower_smoke.lua` (Crystal); `visit_smoke.lua` runs
three (`PKM_ROLE=host|guest|visitor`).  `tests/coop_features.lua` covers the
1.4 extras, `tests/anim_fit.lua` the move-animation fit,
`tests/coop_gen1_story.lua` Red/Blue/Yellow's shared story and
`tests/coop_ux.lua` the invite codes, menus and 1.6 extras.
`tools/run_tests.sh` runs every suite; `tools/i18n_check.py` lists on-screen
lines the Spanish catalog does not cover.

### Regenerating the patches

`tools/gen_patches.py <checkout> <upstream ref> <co-op ref>` rebuilds
`lib/patches/` from a tree with the co-op changes merged into upstream.
`tools/check_patches.py` with the same arguments checks that every function
is rebuilt byte for byte, and still is when upstream has changed it.

### gen1recomp

A separate build for the official [gen1recomp](https://github.com/bryanthaboi/gen1recomp) is in
progress, in its own repository and built only on gen1recomp's own mod API.

## License

PkMultiplayer's own files are MIT (see `LICENSE`). Gen2Recomped belongs to
its authors and is under its own license; this mod ships none of its code (the
patches in `lib/patches` carry only the co-op's own lines, anchored by hashes of
the engine's). No ROM data is included.

The screenshots and the GIF in `docs/img` show Pokémon art, which belongs to
Nintendo, Creatures Inc. and GAME FREAK Inc.: they are not covered by the MIT
license. Pokémon is a trademark of Nintendo, Creatures Inc. and GAME FREAK Inc.

PkMultiplayer is a free, non-commercial fan project. It is not affiliated with or
endorsed by Nintendo, The Pokémon Company, GAME FREAK, Creatures Inc. or the
author of Gen2Recomped.
