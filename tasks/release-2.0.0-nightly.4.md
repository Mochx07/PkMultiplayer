**Nightly** (test build) of 2.0 refining joint catching, 2-vs-1 wild battles, Elite Four entrance triggers, and desktop/mobile touch UI. The stable release is still 1.6.17. Uses **link protocol 17** (update both players to `2.0.0-nightly.4` so both see the catch roulette and full 1-vs-1 wild layout). Needs Gen2Recomped 0.8.58 or later.

### New
- **Joint catch keeper roulette (`CoopCatch`):** when both players catch a wild Pokémon together and pick conflicting options (both want it, both pass it, or both leave it to fate), a synchronized deterministic roulette spins on both screens, decelerates with ticks, and highlights the winner. Selecting first also displays `Waiting for <partner>...` until the other player chooses.

### Changed
- **Full 1-vs-1 wild sprite in 2-vs-1 wild co-op (`BattleState`):** a lone wild Pokémon facing two players now renders with its full-size 1-vs-1 sprite and column instead of the shrunken 2-vs-2 slot, with move animations, the timed-catch aim ring, and P1/P2 HUDs aligned cleanly without clipping its feet.
- **Removed the corner `CO-OP` overlay button:** open the co-op menu through `START -> CO-OP`.

### Fixed
- **Desktop touch mode no longer gets stuck:** using the mouse in mod menus on PC no longer locks touch hitboxes or the on-screen touch keyboard on permanently; any keyboard or gamepad input exits touch mode immediately, and clicking empty background/letterbox space to focus the window while touch mode is off neither activates touch nor cancels the open menu.
- **Spanish touch keyboard `W`/`L` display bug:** keycaps and typed input now render literally without passing through `Font.localize` (which mapped single-letter win/loss labels `W -> V` and `L -> D` in Spanish), and the cursor renders as a clean 6x1 bar instead of missing glyph `_`.
- **Phantom `CO-OP / SOLO` prompt before the Elite Four (Indigo Plateau):** stepping near the Indigo Plateau rival rematch coord trigger when its guards fail (or talking to an already-beaten Elite Four member) no longer pops up an empty `CO-OP / SOLO` menu or strands the partner in `READ ALONG...`. `CoopStory.findBigBattle` now pre-evaluates leading read-only guards and cancels any unconsumed invite when a script finishes.
- **Touch UI polish:** list menu row bounds stay strictly inside the Game Boy menu frame, the compact `READ ALONG...` wait modal places `BACK` below its top header clear of the bottom dialogue box, `BACK` on battle invites sits outside the modal border, and button/keycap labels are centered.

## Español

**Nightly** (versión de prueba) de la 2.0 con mejoras en captura conjunta, salvajes 2 contra 1, disparadores de la entrada de los Altos Mandos y correcciones del modo táctil en PC y móvil. La estable sigue siendo la 1.6.17. Usa **protocolo 17** (actualiza ambos jugadores a `2.0.0-nightly.4` para ver la ruleta de captura y el sprite 1v1 en salvajes). Necesita Gen2Recomped 0.8.58 o posterior.

### Novedades
- **Ruleta visual en captura conjunta (`CoopCatch`):** cuando los dos atrapan un Pokémon a la vez y eligen opciones distintas (ambos lo quieren, ambos lo ceden o ambos lo dejan a la suerte), gira una ruleta sincronizada y determinista en ambas pantallas hasta marcar al ganador. Además muestra `Esperando a <compañero>...` mientras el otro elige.

### Cambios
- **Sprite 1v1 completo del salvaje en 2 contra 1 (`BattleState`):** el Pokémon salvaje en solitario frente a los dos jugadores usa ahora su sprite de 1 contra 1 a tamaño real (sin encoger ni desplazar al hueco 2v2), con animaciones, aro de captura y HUDs de P1/P2 ajustados para no cortarle los pies.
- **Eliminado el botón `CO-OP` de la esquina:** el menú co-op se abre desde `START -> CO-OP`.

### Arreglos
- **El modo táctil en PC ya no se queda pegado:** pulsar cualquier tecla o botón/stick del mando desactiva al instante el modo táctil y el teclado en pantalla, y hacer clic fuera del menú para enfocar la ventana cuando el táctil está apagado ya no lo activa ni cancela la pantalla.
- **Teclado táctil en español (`W` aparecía como `V` y `L` como `D`):** las teclas y el texto escrito se dibujan literalmente sin pasar por `Font.localize`, y el cursor usa una barra limpia en vez del carácter `_` inexistente.
- **Menú fantasma `CO-OP / SOLO` antes de los Altos Mandos (Meseta Añil):** acercarse al disparador del rival cuando no correspondía combate (o hablar con un Alto Mando ya vencido) ya no abre un `CO-OP / SOLO` sin efecto ni deja al compañero colgado en `LEE CON ÉL...`.
- **Arreglos visuales táctiles:** los recuadros de filas en menús respetan los bordes del marco, el botón `ATRAS` en `LEE CON ÉL...` queda arriba sin pisar el diálogo inferior, `ATRAS` en invitaciones queda fuera del marco y los textos de teclas y botones van centrados.
