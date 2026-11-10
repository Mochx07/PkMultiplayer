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

## M5. Gen 3 (investigación, sin promesa)
- [x] Qué expone la Esmeralda en alfa y qué se reutiliza: `tasks/gen3-informe.md`.
      Lectura de código; sin caché de Esmeralda aquí, nada ejecutado.

## Cierre
- [x] CHANGELOG, README, insignia, versión del manifest, zip.
- [ ] Notas EN/ES y Release: las publica Mochi o las publico cuando lo diga.

## Revisión
(se rellena al cerrar cada hito)
