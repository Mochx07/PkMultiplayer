**Nightly** (test build) of 2.0. The stable release is still 1.6.17. Same protocol: it links with 2.0.0-nightly.1 and 1.6.x, but each new feature only turns on when **both** players have it. Needs Gen2Recomped 0.8.58 or later.

### New
- **Catch together, Let's Go style.** Balls can be thrown in a co-op wild battle: the throw is the turn's action and resolves the same on both screens. Both throwing in one turn is a **joint throw** (the better ball, catch rate ×1.5); the twin goes into a ball of its own. Then **WHO KEEPS IT?** (me / my partner / let fate decide — a coin that falls the same on both games when you disagree).
- **Voice chat** (mod options: VOICE CHAT off / push V / open mic, and VOICE BY DISTANCE): louder the closer you stand, silent on another map, full in a battle together. A speaker over your partner while they talk.
- **Your partner's feed:** their catches, evolutions and hatched eggs as a corner card and an emote over their avatar.
- **Level-ups in the corner** in co-op doubles (both teams), without the stats window that held the turn.
- **Battle Tower (Crystal) in duo:** join once and the seven battles go on without asking again.
- **Bug-Catching Contest:** your partner's time left and best catch, live on the map.
- **Time Capsule:** Red/Blue/Yellow and Gold/Silver/Crystal can link to chat, emote and trade (under the game's own Time Capsule rules).
- **Gold/Silver with Crystal (experimental):** rule G/S+C STORY, off by default; shares the story by translating 1159 events. Some scenes stay apart.
- **More VPNs:** besides ZeroTier, Tailscale, Radmin VPN, Hamachi and WireGuard. The host screen lists every address (SELECT steps through them) and the code follows the one shown.
- **Discord:** "Ask to Join" while hosting (a click dials in), "Co-op with TOBY", and **AFK** after 3 minutes (also a Zzz over your avatar on your partner's screen).
- **Red/Blue:** a Pokémon that follows you, with the cartridge's body-shape party icon.

### Changed
- **One CO-OP row on the title screen**, asking CONTINUE or NEW GAME.
- **Your name first** on the link screen: no more "HOST/GUEST" when you link from the title screen.
- **Chat:** your partner sees only what you send; "typing..." only once there is a letter. In battle the box takes the text box and messages show in a small strip at the top left — no more covering the Pokémon or their HP.
- **Partner arrow** in their version's colour (it pulses when they are on another map).
- **Hyper Beam and other beams in doubles** fly straight between the two Pokémon (they were a staircase of pieces), in Gen 1 and Gen 2.
- **2-vs-2 sprites:** your Pokémon no longer runs into the HUD or the text box; your partner's stands behind, to the left.
- **Walking into a big event together:** the host leads the scene and the other follows it (two invites used to cross); the arrival wait went from 1.5 s to 0.6 s.

### Fixed
- **Desync with Sandstorm / Hail in doubles:** each copy hurt a different Pokémon (an eighth of max HP apart every turn). Found by a 21-turn run with two real copies: 5 desyncs → 0.
- The host's correction lands before the next turn resolves (it was dropped when both arrived in the same frame) and now covers weather, screens and hazards.
- The **victory jingle** no longer plays when only one of the two foes falls.

## Español

**Nightly** (versión de prueba) de la 2.0. La estable sigue siendo la 1.6.17. Mismo protocolo: enlaza con la 2.0.0-nightly.1 y con 1.6.x, pero cada novedad solo se activa cuando **los dos** la tienen. Necesita Gen2Recomped 0.8.58 o posterior.

### Novedades
- **Captura en equipo, estilo Let's Go.** Ya se pueden lanzar Balls en un combate salvaje co-op: el lanzamiento es la acción del turno y sale igual en las dos pantallas. Si los dos lanzan en el mismo turno es un **lanzamiento conjunto** (la mejor Ball, ratio ×1,5) y el gemelo entra en su propia Ball. Después: **¿QUIÉN SE LO QUEDA?** (yo / para el compañero / a la suerte; si no se ponen de acuerdo, decide una moneda igual en los dos juegos).
- **Chat de voz** (opciones del mod: VOICE CHAT apagado / pulsar V / micro abierto, y VOICE BY DISTANCE): más fuerte cuanto más cerca están, nada en otro mapa, todo en combate juntos. Un altavoz sobre el compañero cuando habla.
- **Lo que hace el compañero:** sus capturas, evoluciones y huevos en una tarjeta en la esquina y con un emote sobre su avatar.
- **Subidas de nivel en la esquina** en los dobles co-op (las de los dos), sin el cuadro de estadísticas que paraba el turno.
- **Torre de Batalla (Cristal) en dúo:** se acepta una vez y los siete combates siguen sin volver a preguntar.
- **Concurso de bichos:** el tiempo y la mejor captura del compañero, en vivo en el mapa.
- **Cápsula del Tiempo:** Rojo/Azul/Amarillo y Oro/Plata/Cristal pueden enlazarse para chatear, usar emotes e intercambiar (con las reglas de la Cápsula del propio juego).
- **Oro/Plata con Cristal (experimental):** regla HISTORIA O/P+C, apagada de fábrica; comparte la historia traduciendo 1159 eventos. Algunas escenas siguen aparte.
- **Más VPN:** además de ZeroTier, Tailscale, Radmin VPN, Hamachi y WireGuard. La pantalla de anfitrión enseña todas las direcciones (SELECT cambia) y el código sigue a la elegida.
- **Discord:** «Pedir unirse» al hospedar (un clic conecta), «Co-op con TOBY», y **AFK** a los 3 minutos (también un Zzz sobre su avatar en la pantalla del compañero).
- **Rojo/Azul:** el Pokémon que los sigue, con el icono de silueta del cartucho.

### Cambios
- **Una sola fila CO-OP en el título**, que pregunta CONTINUAR o NUEVA PARTIDA.
- **Su nombre primero** en la pantalla de enlace: ya no sale «HOST/GUEST» al conectarse desde el título.
- **Chat:** el compañero ve solo lo que se envía; «escribiendo...» solo con al menos una letra. En combate la caja ocupa el cuadro de texto y los mensajes salen en una franja pequeña arriba a la izquierda: ya no tapan a los Pokémon ni la vida.
- **Flecha del compañero** con el color de su versión (late si está en otro mapa).
- **Hiperrayo y rayos en dobles** van rectos entre los dos Pokémon (antes, una escalera de trozos), en Gen 1 y Gen 2.
- **Sprites del 2v2:** su Pokémon ya no se mete en el HUD ni en el cuadro de texto; el del compañero va detrás, a la izquierda.
- **Entrar juntos a un evento importante:** la escena la lleva el anfitrión y el otro la sigue (antes se cruzaban dos invitaciones); la espera al llegar bajó de 1,5 s a 0,6 s.

### Arreglos
- **Desincronización con Tormenta Arena / Granizo en dobles:** cada copia dañaba a un Pokémon distinto (1/8 de vida por turno). Encontrado con una prueba de 21 turnos con dos copias reales: de 5 desajustes a 0.
- La corrección del anfitrión se aplica antes de resolver el siguiente turno (antes se perdía si llegaba en el mismo fotograma) y ahora incluye clima, pantallas y trampas.
- La **fanfarria de victoria** ya no suena cuando cae solo uno de los dos rivales.
