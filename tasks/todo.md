# PkMultiplayer 2.0.0-nightly.3: plan (2026-11-18) -- Gen 1 primero

Pedido de Mochi: la nightly.3 se centra en Gen 1 (Rojo/Azul/Amarillo). El plan de la 1.20 (M2/M3)
se hizo pensando en Oro/Plata/Cristal y Gen 1 se quedó atrás. Además: terceras ediciones (Amarillo,
Cristal) con un sistema de red y sincronía ordenado, **protocolo de versión nuevo**, móvil, mapa,
mejoras al combate. HGSS queda en la rama `hgss/coop`, fuera de esta nightly. Rama `v2.0/nightly.3`
(desde `v2.0/nightly.2` f24ae64).

Auditoría (2026-11-18, con pruebas reales, no de memoria):
- `CoopManager.storyCompatible` devuelve true siempre fuera de Gen 2: Rojo/Azul y Amarillo
  comparten TODO (Jessie y James, iniciales regalados, etc.).
- Rival 2v2 solo Gen 2 (`CoopGyms`: `isGen2() and not isGen1()`); `CoopBoss` solo jefes de Gen 2.
- Minijuegos Karpa y Bici solo Gen 2 (la Ruta Ciclista existe en Gen 1).
- Driver `gen1_mixed.lua` (Rojo host + Amarillo guest): el seguidor PIKACHU se dibuja con el icono de
  equipo de Gen 1 (parece Clefairy) en Rojo y en Amarillo al dibujar al compañero de Rojo; Amarillo no
  manda su seguidor (Rojo no ve el Pikachu del compañero); en el 2v2 de Gen 1 las dos espaldas
  (P1 y P2) se dibujan encimadas.
- Móvil: ninguna pantalla del mod tiene táctil; chat/emote/LISTO/voz dependen de teclas T/Y/R/V y
  números; las filas dicen "(KEY T)".

Orden (Mochi): A primero.

## A. Protocolo de versión y terceras ediciones
- [x] A1 Protocolo 17 (Mochi: "el protocolo de versión debería cambiar"): el saludo lleva el perfil
      de edición (`CoopEditions.profile`); un 16 ya no enlaza (cada uno ve qué versión tiene el otro).
- [x] A2 Matriz de versiones (`src/coop/CoopEditions.lua`; OJO: `CoopCompat.lua` ya existía, es la
      compatibilidad con DramaticShapes): por cada par, cada evento es COMPARTIDO (mismo
      flag), TRADUCIDO (mapa por nombre), EXCLUSIVO (no cruza; el otro solo lee el aviso) o
      CONFLICTIVO (cruza adaptado o se bloquea). Sustituye a `storyCompatible` y a `CoopCrossStory`.
- [x] A3 Rojo/Azul <-> Amarillo: tabla de eventos por nombre sacada de las cachés de cada versión;
      lista de exclusivos de Amarillo (Jessie y James, iniciales regalados, Pikachu) y su trato.
- [~] A4 Oro/Plata <-> Cristal: CoopFlagMap ya va por la matriz (regla 3RD ED. STORY, ahora
      encendida por defecto; lo que no tiene gemelo no cruza). Falta revisar con juegos reales: exclusivos de Cristal (Suicune/Eusine,
      Torre de Batalla, Huevo Raro, examen de la Guarida del Dragón, GS Ball) nunca cruzan; los de
      cambios medianos, adaptados cuando no rompen Oro/Plata.
- [x] A5 Un solo filtro en el que recibe (`CoopEditions.filter`): el emisor manda `src` y marca `ed`
      en los flags de los datos de su edición; si todo el evento era de la otra edición, sus objetos y
      dinero tampoco se dan. Pruebas: suite `coop_editions` (23) y driver `gen1_editions` con dos copias
      reales en los dos sentidos (Amarillo->Rojo y Rojo->Amarillo).

## B. Gen 1 al nivel de lo que ya tiene Gen 2
- [ ] B1 Gimnasios de Gen 1 en equipo (revisar pools gen1 de CoopGyms con pruebas reales, Amarillo
      con sus equipos propios).
- [ ] B2 Liga de Gen 1 (Lorelei, Bruno, Agatha, Lance, campeón) en 2v2; Salón de la Fama para los dos.
- [x] B3 Rival 2v2 en Gen 1 (OPP_RIVAL1/2/3; el de Amarillo con Eevee). Hecho: CoopGyms empareja en
      Gen 1 entre la misma edición o su pareja (Rojo/Azul por el contrainicial, Amarillo por
      rivalStarter con sus combates fijos); `findBigBattle` reconoce `rival_battle`. Driver
      `gen1_rival` (dos Rojo reales: GARY con Bulbasaur y BLUE con Charmander, mismo equipo en las dos).
- [x] B4 Legendarios y jefes de Gen 1 (CoopBoss): Articuno, Zapdos, Moltres, Mewtwo son jefes (solos,
      x1,5 PS, Mewtwo x2, dos acciones por turno) CAPTURABLES juntos (CoopBoss.CATCHABLE + lanzar a
      tiempo + quién se lo queda); los Snorlax ya eran el jefe "snorlax". Driver `gen1_legend` (Zapdos,
      dos Rojo reales: mismo PS 245 en las dos).
- [ ] B5 Historia de Gen 1: S.S. Anne, Torre Pokémon (Marowak, Silph Scope), Guarida Rocket, Silph S.A.
      (Giovanni), Safari (personal), Poké Flauta; esperas y escenas a dos (story.duo) en Gen 1.
- [ ] B6 Hub de Gen 1 (Mochi: "1, 2 y la interfaz"): el Club de Cable de Gen 1 (Coliseo / Centro
      de Intercambio, 2º piso del Centro), el hub online del launcher (plaza, GTS, salas) adaptado
      al co-op en Gen 1, y su interfaz.
- [~] B7 Minijuegos en Gen 1: contrarreloj en la Ruta Ciclista de Kanto HECHA (BikeTrial.GEN1: puerta
      ROUTE_16_GATE_1F carril 8-9, ROUTE_17 de 144 casillas, meta al entrar en ROUTE_18; driver
      `gen1_bike` con dos Rojo reales: 23,4 s vs 22,6 s, mismo ganador). Falta: otro en lugar del de Karpa.

## C. Sprites
- [-] C1 Seguidor con el sprite de andar del juego si existe (PIKACHU de Amarillo), no el icono.
      (Mochi 2026-11-18: los iconos de los acompañantes no importan.)
- [ ] C2 Amarillo comparte su Pikachu seguidor con el compañero.
- [x] C3 Espaldas de P1 y P2 separadas en el 2v2 de Gen 1 (Hooks envuelve doubleBackBase en Gen 1:
      P2 14 px a la izquierda, P1 6 a la derecha; driver `gen1_backs`, parejas Pikachu/Pikachu,
      Charmander/Bulbasaur, Onix/Gyarados).

## D. Mapa
- [x] D1 Compañero en el MAPA de Gen 1 (y el mapa de Gen 2 de vuelo/zonas), con LA CABEZA del otro
      jugador (mitad superior de su sprite) en su sitio (`src/coop/CoopTownMap.lua`, envoltorio de
      TownMap:draw). Driver `gen1_townmap` (Rojo en Paleta + Amarillo en Verde, cada uno ve al otro).
- [ ] D2 Flecha del compañero: revisar en Gen 1.
- [x] D3 Compañero de otra edición (Amarillo/Cristal) bien situado en tu mapa (por id de mapa,
      probado Rojo<->Amarillo).

## E. Móvil
- [ ] E1 Táctil en las pantallas del mod (menú co-op, invitación, selección de equipo, emotes, VS).
- [ ] E2 Botones en pantalla para chat, emote, LISTO y voz; sin "(KEY T)" en móvil.
- [ ] E3 Prueba con eventos táctiles simulados en Xvfb.

## F. Combate
- [ ] F1 C3 + revisión del 2v2 de Gen 1 (animaciones, objetivos, cuadro del compañero).
- [x] F2 Salvaje juntos = 2 contra 1: UN solo Pokémon salvaje, no dos (Mochi, 2026-11-18). Hecho:
      sin gemelo (modo "solo en su lado" de CoopBoss); probado Rojo+Amarillo reales.
- [x] F3 Captura conjunta: los dos pulsan A en el mismo momento; si van sincronizados, probabilidad
      alta (Mochi, 2026-11-18). Hecho (cap `catch.aim`): si los dos tiran BALL el mismo turno, antes
      de resolverlo sale un aro que se cierra sobre el Pokémon en 1,2 s; cada copia mide el fallo de su
      jugador (ms) y lo manda; con los dos, el peor decide: <=100 ms x3 (PERFECTA), <=250 x2,25,
      <=450 x1,75, si no x1,5 (la tirada conjunta de antes). Suite `coop_catch_aim` (18) y driver
      `catch_aim` con dos copias de Oro (mismo resultado en las dos).

## Hecho
- [x] EMOTE sin compañero: la burbuja sale sobre tu jugador (antes cerraba el menú y no hacía nada).
      dfb2526, driver `emote_solo.lua` en Rojo y en Plata en español.

# PkMultiplayer 2.0.0-nightly.2: plan (2026-11-17)

Después de publicar (rama nightly, para la nightly.3): seguidor de Rojo probado con ROM real; historia
Oro<->Cristal probada con dos juegos reales; R del mando para hablar; Ball de la captura en dobles por
encima del HUD. Descartado: IPv6 (ENet 1.3.13 solo IPv4), inscripción conjunta al concurso (script de
recepción del otro juego).

Plan completo: `~/.claude/plans/radiant-honking-crescent.md`. Rama `v2.0/nightly.2` (desde
`nightly` 2c395f7). Árbol fusionado `~/Downloads/PkMplayer-merge` (coop-snapshot), parches
contra 85512413. Todo lo nuevo, detrás de caps; protocolo sin cambios.

- [x] A1 Flecha del compañero con el color de su versión (late si está en otro mapa)
- [x] A2 Sin fanfarria de victoria mientras quede un rival en pie (dobles, Gen 1/2)
- [x] A3 Rayos en dobles por la línea real (Gen 2: giro + escala; Gen 1: piezas en la línea)
- [x] A4 Subidas de nivel en una tarjeta en la esquina (ambos equipos), sin cuadro de stats
- [x] B5 Una sola fila CO-OP en el título (gancho ui.title_menu.items; parche TitleState quitado)
- [x] B6 Paso del nombre en la pantalla de enlace (CoopProfile; al continuar, nombre del save)
- [x] B7 Chat: solo lo enviado; "escribiendo" con >=1 letra; en combate, caja en el cuadro de
      texto y mensajes en una franja arriba a la izquierda
- [x] C8 Captura conjunta estilo Let's Go + ¿quién se lo queda? (catch.together); gemelo en su Ball
- [x] D9 Eventos visuales para el otro jugador (cola de avisos)
- [x] D10 Retraso al entrar a la vez a un evento
- [x] D11 Parque Nacional / Torre de Batalla (Cristal)
- [x] D12 Sincronización de combates (firma ampliada, detección antes de resolver, estrés)
- [x] E13 Gen 1: paridad, fallos, captura en Gen 1 (probar con Amarillo)
- [x] E14 Oro/Plata <-> Cristal experimental
- [x] E15 Cápsula del Tiempo
- [x] F16 VPNs (Hamachi, Tailscale, Radmin, WireGuard, IPv6)
- [x] F17 Chat de voz con proximidad (pulsar / micro abierto)
- [x] F18 Discord: unirse, AFK
- [x] G19 Sprites de batalla dual
- [x] H20 2.0.0-nightly.2 PUBLICADA (pre-release + zip); web actualizada (novedades, guía VPN, lastmod), homepage del repo = web, README enlaza la web
- [~] I21 gen1recomp: esqueleto local que carga (~/Downloads/PkMultiplayer-Gen1Recomp); falta decidir el 2v2 y portar

# PkMultiplayer 1.20.0: plan

Base: 1.6.17 (Gen2Recomped 0.8.49, protocolo 16). Parches intermedios 1.17–1.19 los
hace Mochi en paralelo; todo lo de aquí va en ramas `v1.20/*` y se mezcla al final.

Regla de cada hito: suites verdes + al menos un driver de dos copias reales + textos EN/ES
(`tools/i18n_check.py`) antes de marcarlo hecho.

## M0. Cimientos (lo necesitan los demás)
- [x] Capacidades en el saludo (`caps`), **sin subir el protocolo** (sigue en 16): un 1.20
      conecta con un 1.6.x y lo nuevo queda apagado. `CoopManager.registerCap(name)`,
      `bothHave(name)`. Prueba `tests/coop_caps.lua` (14/14) + smoke real de dos copias.
- [x] Menú co-op en páginas: PARTNER > BATTLE P1 VS P2 abre la página VS (formatos, MATCH,
      RECORD, REPLAYS) y PARTNER > MINIGAMES la de minijuegos. Revisado el 2026-11-10: no
      hace falta una página aparte "VS Y MINIJUEGOS".
- [x] Partir `CoopManager.lua` (3875 -> 1276 líneas) sin cambiar comportamiento. Cada parte
      es `require("src.coop.X").install(CoopManager, CMI)` en el sitio donde estaba; `CMI`
      lleva los locales de archivo que lee y los que pasa a lo siguiente. Módulos (en
      `MODULES` de main.lua): CoopPartnerItems, CoopClock, CoopPartnerNpc, CoopWarp,
      CoopInvites (+ grandes combates), CoopReady, CoopChat, CoopHandlers, CoopHud.
      Se quedan en CoopManager: constantes, helpers, saludo, estado local, bucle por frame.
      Verificado: todas las suites, i18n_check, y con dos copias reales coop_smoke,
      wild_together, league_door y watch_smoke (0 fallos, logs sin errores).

## M1. Modo VS (sobre el P1 VS P2 del Cable Club)
- [x] Formatos (cap `vs.formats`, `src/coop/CoopVS.lua`): COMBATE LIBRE, NIVEL 50, NIVEL 100,
      PEQUEÑOS (nivel 5, solo primeras etapas que evolucionan), MONOTIPO. Cláusulas de especie
      y objeto, sin legendarios, sin OHKO ni evasión. Se toma el equipo tal cual y quedan
      fuera los que no cumplen (se avisa cuántos); solo se rechaza si no queda nadie.
      Nivel por `forceLevel` del motor, sin su menú; equipo enviado por hook a
      `Protocol.packParty`. Menú PARTNER > BATTLE P1 VS P2 > formato (B vuelve por páginas).
      Pruebas: `tests/coop_vs.lua` 35/35; driver real `vs_level50.lua` 0 fallos en las 2 copias.
- [x] Cláusula de sueño (cap `vs.sleep`, `src/coop/CoopSleepClause.lua`, agente claude-sleep):
      en los formatos con reglas; REST no cuenta; también en las repeticiones y en cada juego
      del mejor de 3. Suite 46/46; drivers reales NIVEL 50 / LIBRE / guest en español OK.
- [x] Al mejor de 3 (cap `vs.match`, `src/coop/CoopMatch.lua`): MATCH: 1 GAME / BEST OF 3 en
      la página VS; la invitación lo lleva (`best`) y el invitado lo ve. Entre combates siguen en
      el Cable Club sin otra invitación (nueva semilla del host, marcador en pantalla); cada
      copia dice quién ganó cada combate (`coop_match result`) y las dos aplican la misma regla
      a los dos informes. Lo del túnel va numerado por combate. Cada combate, su repetición.
      Salir (B entre combates, RUN, enlace caído) termina la partida en las dos sin resultado.
      Pruebas: `tests/coop_bo3.lua` 98/98; driver real `vs_bo3.lua` 2-1 completo, 0 fallos en
      las 2 copias. (Sin vista previa de equipos: queda pendiente.)
- [x] Repeticiones (`src/coop/CoopReplay.lua`): el túnel anota equipos, semilla, nivel y
      acciones de cada combate P1 VS P2; al cerrar escribe un JSON en
      `modstorage/PkMultiplayer/replays/` (se guardan los 20 últimos). Se ven con el
      espectador del motor (`LinkBattle.newSpectator`) alimentado mensaje a mensaje.
      Menú: VS > REPETICIONES, y REPETICIONES sin conexión. No va nada extra por la red.
      Pruebas: `tests/coop_replay.lua` 25/25; driver real `vs_replay.lua`: en las dos copias
      la repetición termina con los mismos PS y ganador que el combate.
- [x] Historial y ELO local por compañero (`src/coop/CoopRecord.lua`): por id co-op del
      compañero y formato, victorias/derrotas, combates y ELO (1000, K 32, enteros, calculado
      desde el id menor: las dos copias guardan números espejo). En
      `modstorage/PkMultiplayer/vs_record.json` (se escribe al acabar, en las dos copias, sin
      depender de guardar partida). Menú VS > RECORD.
- [ ] (después) Equipos de alquiler, draft, 2v2 de 4 jugadores con VISIT, torneo.

## M2. Historia co-op renovada
Lo que pidió Mochi (2026-11-02): poca cosa en equipo, quedarse atrás, esperas y
bloqueos, rocas/MO/mundo sin compartir, y sobre todo **que ninguno sea el fantasma o la
sombra del otro**: los diálogos, eventos y la historia deben reconocer a los dos.
- [x] Diálogos con los dos: los NPC clave hablan a los dos por su nombre y a veces **Hecho (parcial):** cada pantalla pone primero a su jugador (`raw`), y la entrega nombra solo a quien recibe (`CoopDuo`, cap `story.duo`).
      a cada uno por separado (Elm, rival, líderes), no solo "{PLAYER} & {PARTNER}".
- [x] Eventos con papel para cada uno: en las escenas, cada jugador hace algo (uno **Hecho:** el compañero pasa páginas con su A, reacciona (SELECT+dirección), recibe su objeto/medalla con recuadro y sonido propios.
      recibe el objeto, el otro la explicación) en vez de que uno mire.
- [x] Sin esperas muertas: el que no dispara la escena puede seguir jugando o unirse **Hecho:** retención de escena muerta liberada, respuesta durante la elección de tres conservada, READY tras reconectar (`CoopCatchUp`).
      a mitad; las puertas de la historia no bloquean al que llega tarde.
- [x] Gimnasios en equipo (`CoopGyms`, cap `story.gyms`) —: el líder en doble con equipo ajustado; medalla para los dos.
- [x] Rival en 2v2 (`CoopGyms`): el rival de cada uno, mismo combate.
- [x] MO compartidas: la del compañero sirve a menos de 8 pasos (`src/coop/CoopWorld.lua`,
      cap `world.share`): CORTE, GOLPE ROCA, FUERZA, SURF, TORBELLINO y CASCADA con el
      Pokémon y la medalla del compañero; su DESTELLO ilumina tu cueva.
- [x] Bestias legendarias (`CoopBoss`, cap `story.bosses`) —: ubicación compartida en el Pokégear; el encuentro es doble co-op.
- [x] Jefes de banda (`CoopBoss`) —: Gyarados rojo, Sudowoodo, Snorlax, Red (dos acciones por turno).
- [x] Ponerse al día: ir al último punto clave del compañero. **Hecho:** PONERSE AL DÍA (cap `story.catchup`), + EXP x1,5 y rivales equilibrados al equipo más débil.
- [x] Rocas de Fuerza sincronizadas (`CoopWorld`): el motor de la otra copia empuja la
      misma roca; quien entra al mapa del compañero las encuentra donde él las dejó.

## M3. Minijuegos (diseño propio)
- [x] Marco común `CoopMinigame` (invitación, cuenta atrás, marcador, resultado igual en las dos
      copias, salir con B, corte de enlace, semilla compartida, `quietField`, `waitForPartner`,
      espera mientras el compañero siga mandando puntuación). Menú PARTNER > MINIJUEGOS.
- [x] Concurso de Magikarp (`mg/MagikarpContest`, cap `minigame.karp`): Lago de la Furia, 2 min,
      medida del motor, se sueltan, 1 GREAT BALL al día al ganador.
- [x] Contrarreloj en bici (`mg/BikeTrial`, cap `minigame.bike`): Ruta 16 > 17 > 18, fantasma +
      barra de avance, récord por partida.
- [x] Búsqueda del tesoro (`mg/Treasure`, cap `minigame.treasure`): Gen 1 y Gen 2, frío/templado/
      caliente.
      Verificado con el árbol mezclado: suites + los tres drivers reales (ocultos) sin fallos.

## M4. Optimización
- [x] Posiciones binarias y por diferencia en el canal no fiable (`src/coop/CoopWire.lua`,
      cap `net.binpos`): 284 bytes de JSON -> 96 el fotograma clave, 19 un paso. La
      diferencia se apoya en un fotograma clave que el compañero confirmó, así que una
      pérdida no congela a nadie. Los demás mensajes rápidos (WATCH, visitantes, chat en
      vivo) siguen en JSON. Suite `coop_wire` 31/31; visto en el coop.log de dos copias reales.
- [x] Caché del Transplant por hash del archivo del motor y del parche
      (`modstorage/PkMultiplayer/patchcache/`). Carga del mod medida con luajit: 77 ms sin
      caché; con caché ~22 ms más el hash (md5 nativo de LÖVE; en la prueba el hash es Lua
      y pesa 40 ms, así que el número real con md5 no está medido). Suite `patch_cache`
      15/15; en el juego real, segunda carga: 57 de 71 funciones de BattleState desde la caché.
- [x] Retardo que se ajusta al ping: no hay retardo de entrada que ajustar (los combates
      son por turnos). Lo que sí dependía del ping era el arranque de los minijuegos: quien
      invita espera medio ping suavizado (`CoopNet:oneWay`, máx. 1 s) y las dos copias
      llegan al YA a la vez.
- [x] CI en GitHub Actions: ya existía (`.github/workflows/tests.yml`), pero
      `tools/run_tests.sh` salía siempre con 0. Ahora devuelve error si algo falla.

## M4b. Motor 0.8.57 (no estaba en el plan)
- [x] Los parches de 1.6.17 no entran en Gen2Recomped 0.8.57 (`BattleState` sin parchear).
      Árbol fusionado mezclado con v0.8.57 (commit 07aadf99; conflictos en BattleState x5
      y BagMenu x1), parches regenerados contra `b205bf4e`, 123/123 exactos.
      1.20 deja de funcionar en 0.8.49: `game_version` del manifest lo exige.

## M4c. Motor 0.8.58 y paso a 2.0 (2026-11-13)
- [x] Gen2Recomped sacó 0.8.58 (`85512413`: Nuzlocke, Soul Link, randomizer, personaje a
      medida). Árbol fusionado mezclado (commit c03461f8; un conflicto en
      `OverworldState:update`, que el mod no trasplanta), parches regenerados, 123/123 exactos.
      Con estos parches 0.8.57 ya no sirve (`patch_scope` y `foreign_wrapper` fallan ahí):
      `game_version` exige 0.8.58 (`0.7.6` es lo que dice el juego corrido desde el código).
- [x] La 1.20 sale como **2.0**: primero `2.0.0-nightly.1`, pre-release en GitHub.
- [ ] Sin probar: co-op con los modos de partida de 0.8.58 (Nuzlocke, Soul Link, randomizer).

## M5. Gen 3 (investigación, sin promesa)
- [x] Qué expone la Esmeralda en alfa y qué se reutiliza: `tasks/gen3-informe.md`.
      Lectura de código; sin caché de Esmeralda aquí, nada ejecutado.

## Cierre
- [x] CHANGELOG, README, insignia, versión del manifest, zip.
- [x] Notas EN/ES y Release: publicada como Nightly `v2.0.0-nightly.1` (pre-release) el 2026-11-13.

## Revisión
(se rellena al cerrar cada hito)
