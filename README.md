# PkMultiplayer — co-op online para Gen2Recomped

Juega **Pokémon Oro, Plata o Cristal** (y Rojo/Azul/Amarillo) con un amigo en el
mismo mundo: os veis caminar, chateáis, vivís los eventos de la historia juntos
y peleáis contra los entrenadores en **combates dobles 2 contra 2**.

Es un **mod** para el [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped)
oficial. No hace falta descargar ningún fork del juego, solo este zip.

*English below.*

## Instalación

1. Ten el **Gen2Recomped oficial** instalado, con tu ROM de Oro/Plata/Cristal ya importada.
2. Descarga `PkMultiplayer-<versión>.zip` de
   [Releases](https://github.com/Mochx-007/PkMultiplayer/releases).
3. En el launcher, abre la pestaña **MODS** y pulsa **Import mod .zip**, o
   arrastra el zip a la ventana. Comprueba que el mod está activado.
4. Abre el juego. Los **dos jugadores** necesitan el mod, y en la misma versión.

El launcher te avisa cuando sale una versión nueva (el mod comprueba sus
releases de GitHub).

## Cómo conectarse

- **Misma red (LAN):** uno pulsa START → **CO-OP ONLINE** → **HOST**. El otro
  entra en **JOIN** y escribe la IP que le aparece al host.
- **Por internet:** usad [ZeroTier](https://www.zerotier.com/) (una red
  virtual gratuita). Uníos los dos a la misma red y usad la IP de ZeroTier
  del host. El puerto es el **7777**.
- Desde el título también podéis elegir **NEW CO-OP GAME** o **CONTINUE CO-OP**
  para empezar o seguir una partida juntos.

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
| Pokémon que te sigue | tu primer Pokémon (no debilitado) camina detrás de ti, como en HeartGold/SoulSilver, con su icono del cartucho; háblale con **A**. Tu compañero también lo ve. Si es shiny destella, y si te quiere mucho a veces encuentra objetos (un **!** encima: háblale). Se apaga en MODS → PkMultiplayer → OPTIONS → POKEMON FOLLOWS YOU. Solo en Oro/Plata/Cristal |
| Chat | tecla **T** (también durante un combate doble); en móvil, ver arriba |
| Emotes | tecla **Y** |
| Combates dobles | contra entrenadores, en lockstep, con las reglas de dobles de HeartGold/SoulSilver y una IA rival pensada para dobles |
| Historia compartida | los eventos que vive uno los vive el otro; las batallas importantes se preguntan antes |
| Extras | intercambios por el Cable Club, P1 vs P2, objetos para los Pokémon del compañero, Concurso de Bichos y Salón de la Fama compartidos, reloj compartido |
| Warp | solo a pueblos que ya visitaste (como VUELO), tu compañero tiene que aceptar, y se recarga en 10 minutos |
| Salvajes en pareja | regla **TEAM UP WILD**: un salvaje que te sale al caminar con tu compañero cerca (8 pasos, mismo mapa) le pregunta si se une, y pelean un doble contra el salvaje y su gemelo. Juntos no hay Poké Balls; **RUN** os saca a los dos |
| Ver su combate | **WATCH**: una pantallita con el combate de tu compañero en vivo |
| Visitantes | hasta 4 jugadores más entran al mundo del anfitrión con **VISIT** (puerto de la sesión + 1): caminan, chatean y mandan emotes con todos; cada uno juega su partida |
| Soul Link | regla **SOUL LINK**: el Nuzlocke de dos. La primera captura de cada uno en un área queda unida a la del otro; si una cae, caen las dos y no se pueden curar. **SOUL LINKS** muestra las parejas |
| Guardería unida | regla **LINK DAYCARE**: con un Pokémon en tu guardería y otro en la de tu compañero, el suyo es el segundo padre en la tuya. Cada uno saca su huevo; ningún Pokémon sale de su partida |
| Torre de Combate | (Cristal) cada combate de un desafío puede ser un doble co-op: tu compañero se une desde donde esté, con Pokémon bajo el límite de nivel, y su equipo vuelve como entró |
| Regalo Misterioso | **MYSTERY GIFT**: una vez al día por compañero, cada juego elige un objeto para el otro |
| Pokédex | **POKéDEX**: lo que tiene tu compañero y tú no, y al revés. Regla **SHARE DEX**: sus capturas cuentan como VISTAS en la tuya |
| Pokégear | tu compañero encabeza la agenda (llamarlo abre el chat y le suena el Pokégear) y su marca parpadea en el mapa |
| Reconexión | la partida recuerda el último enlace: el anfitrión vuelve a escuchar y el invitado vuelve a llamar solo (opción **AUTO RECONNECT**); fila **RECONNECT** en el menú. Tras un corte, lo que se envió en esos segundos llega al volver, una sola vez, y el sitio del compañero solo lo puede ocupar su misma partida |

Menú co-op (START → CO-OP ONLINE estando conectado), siete filas sin scroll:
CHAT, EMOTE, WARP TO PARTNER, **PARTNER ▶** (ITEM FOR PARTNER, WATCH, TRADE,
BATTLE P1 VS P2, MYSTERY GIFT), POKéDEX, **RULES ▶** (STORY SYNC, TEAM UP WILD,
SHARE DEX, LINK DAYCARE, PARTNER HEAL, SOUL LINK, SOUL LINKS; el recuadro de
arriba explica la regla marcada), VERSION (tu versión, el protocolo y la de tu
compañero) y DISCONNECT. B vuelve de una página a la anterior. Sin conectar:
RECONNECT, HOST, JOIN, VISIT, STORY SYNC, EMOTE, VERSION, EXIT.

Los **ataques** caen sobre el Pokémon que hay de verdad, también en combates
individuales: el cartucho apunta al centro de la caja de 56×56, y contra un
Pokémon pequeño (Pidgey, Natu...) el golpe quedaba en el aire.

## Limitaciones conocidas

- Solo funciona en juegos de **Gen 1 y Gen 2**. En el resto el mod se carga
  pero no hace nada.
- Sin tu ROM importado para el mod, los emotes son globos dibujados por el
  mod (ver "Emotes originales").
- Con el mod de vóxeles (DramaticShapes) los combates individuales siguen en
  3D, pero los dobles co-op se juegan en la pantalla clásica (su 3D solo sabe
  de combates individuales).
- Los visitantes no comparten historia, combates ni objetos: solo el mundo,
  el chat y los emotes.
- El Pokémon que te sigue usa el icono del menú de equipo (dos frames, sin
  vista de espaldas), que es lo que el cartucho tiene; se esconde en bici y
  surfeando.
- Si Gen2Recomped cambia mucho las funciones que toca el mod, el mod lo
  detecta y deja ese módulo sin parchear (lo verás en `log.txt`). En ese
  caso hay que actualizar PkMultiplayer.

## Registro (logs)

`coop.log` y `log.txt` están en la carpeta de guardado del juego. Si algo
falla, mándalos al abrir un issue.

---

# PkMultiplayer — online co-op for Gen2Recomped

Two players, one Johto. You see each other walk, chat (**T**) and emote
(**Y**), live the story's events together, trade through the Cable Club and
fight trainers as a **2-vs-2 double battle** in lockstep, with
HeartGold/SoulSilver's doubles rules.

Your lead Pokémon also **walks behind you**, HGSS-style, wearing its
cartridge party icon (talk to it with **A**; your partner sees it too; it
sparkles when shiny and sometimes finds items). Gold, Silver and Crystal only;
switch it off under MODS → PkMultiplayer → OPTIONS.

Also: **TEAM UP WILD** (fight wild Pokémon as a co-op double), **WATCH** your
partner's battle live, up to four **VISIT**ors in the host's world, **SOUL
LINK** (the two-player Nuzlocke), **LINK DAYCARE** (breed with your partner's
Pokémon, nothing leaves its save), the **Battle Tower in multi** (Crystal),
**MYSTERY GIFT** over the link, a **POKéDEX** comparison and **SHARE DEX**,
your partner in the **POKéGEAR**, and the link picked back up on its own after
a drop or a restart. Move animations now land on the Pokémon actually there,
in singles too.

It is a mod for the official [Gen2Recomped](https://github.com/UNDERdecoded/Gen2Recomped).

**Install:** download the zip from Releases. In the launcher open **MODS** →
**Import mod .zip**, or drop the zip on the window. Both players need it.
**Play:** START → **CO-OP ONLINE** → HOST, or JOIN with the host's IP. Over the
internet, use ZeroTier. The port is 7777.

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
1.4 extras and `tests/anim_fit.lua` the move-animation fit.

### Regenerating the patches

`tools/gen_patches.py <checkout> <upstream ref> <co-op ref>` rebuilds
`lib/patches/` from a tree with the co-op changes merged into upstream.
`tools/check_patches.py` with the same arguments checks that every function
is rebuilt byte for byte, and still is when upstream has changed it.

## License

PkMultiplayer's own files are MIT (see `LICENSE`). Gen2Recomped belongs to
its authors and is under its own license. No ROM data is included. Pokémon
is a trademark of Nintendo, Creatures Inc. and GAME FREAK Inc.
