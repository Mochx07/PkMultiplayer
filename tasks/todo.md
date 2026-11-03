# PkMultiplayer 1.20.0: plan

Base: 1.6.17 (Gen2Recomped 0.8.49, protocolo 16). Parches intermedios 1.17–1.19 los
hace Mochi en paralelo; todo lo de aquí va en ramas `v1.20/*` y se mezcla al final.

Regla de cada hito: suites verdes + al menos un driver de dos copias reales + textos EN/ES
(`tools/i18n_check.py`) antes de marcarlo hecho.

## M0. Cimientos (lo necesitan los demás)
- [x] Capacidades en el saludo (`caps`), **sin subir el protocolo** (sigue en 16): un 1.20
      conecta con un 1.6.x y lo nuevo queda apagado. `CoopManager.registerCap(name)`,
      `bothHave(name)`. Prueba `tests/coop_caps.lua` (14/14) + smoke real de dos copias.
- [~] Menú co-op: ya está en páginas (principal 9 filas, PARTNER, RULES) desde 1.6.x;
      la página VS Y MINIJUEGOS se añade con M1/M3 y P1 VS P2 se mueve ahí.
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
- [ ] Cláusula de sueño dentro del combate (necesita hook determinista en el combate de enlace).
- [ ] Al mejor de 3 con vista previa de equipos.
- [x] Repeticiones (`src/coop/CoopReplay.lua`): el túnel anota equipos, semilla, nivel y
      acciones de cada combate P1 VS P2; al cerrar escribe un JSON en
      `modstorage/PkMultiplayer/replays/` (se guardan los 20 últimos). Se ven con el
      espectador del motor (`LinkBattle.newSpectator`) alimentado mensaje a mensaje.
      Menú: VS > REPETICIONES, y REPETICIONES sin conexión. No va nada extra por la red.
      Pruebas: `tests/coop_replay.lua` 25/25; driver real `vs_replay.lua`: en las dos copias
      la repetición termina con los mismos PS y ganador que el combate.
- [ ] Historial y ELO local por compañero.
- [ ] (después) Equipos de alquiler, draft, 2v2 de 4 jugadores con VISIT, torneo.

## M2. Historia co-op renovada
Lo que pidió Mochi (2026-11-02): poca cosa en equipo, quedarse atrás, esperas y
bloqueos, rocas/MO/mundo sin compartir, y sobre todo **que ninguno sea el fantasma o la
sombra del otro**: los diálogos, eventos y la historia deben reconocer a los dos.
- [ ] Diálogos con los dos: los NPC clave hablan a los dos por su nombre y a veces
      a cada uno por separado (Elm, rival, líderes), no solo "{PLAYER} & {PARTNER}".
- [ ] Eventos con papel para cada uno: en las escenas, cada jugador hace algo (uno
      recibe el objeto, el otro la explicación) en vez de que uno mire.
- [ ] Sin esperas muertas: el que no dispara la escena puede seguir jugando o unirse
      a mitad; las puertas de la historia no bloquean al que llega tarde.
- [ ] Gimnasios en equipo: el líder en doble con equipo ajustado; medalla para los dos.
- [ ] Rival en 2v2.
- [ ] MO compartidas: la del compañero sirve a menos de 8 pasos.
- [ ] Bestias legendarias: ubicación compartida en el Pokégear; el encuentro es doble co-op.
- [ ] Jefes de banda: Gyarados rojo, Sudowoodo, Snorlax, Red (dos acciones por turno).
- [ ] Ponerse al día: ir al último punto clave del compañero.
- [ ] Rocas de Fuerza sincronizadas.

## M3. Minijuegos (diseño propio)
- [ ] Marco común `CoopMinigame`: invitación, cuenta atrás, marcador, resultados, premio.
- [ ] Concurso de Magikarp en el Lago de la Furia (gana el más largo, a tiempo).
- [ ] Contrarreloj en bici por la Ruta Ciclista con el fantasma del compañero.
- [ ] Búsqueda del tesoro (frío/caliente).

## M4. Optimización
- [ ] Mensajes binarios y posiciones por diferencia en el canal no fiable.
- [ ] Caché del Transplant por hash del archivo del motor.
- [ ] Retardo de entrada que se ajusta al ping.
- [ ] CI en GitHub Actions con las suites.

## M5. Gen 3 (investigación, sin promesa)
- [ ] Ver qué expone la Esmeralda en alfa de Gen2Recomped (combate, guardado, mapas).
- [ ] Informe: qué partes del co-op se podrían reutilizar y qué falta en el upstream.

## Cierre
- [ ] CHANGELOG + notas EN/ES, README, insignia, zip, Release.

## Revisión
(se rellena al cerrar cada hito)
