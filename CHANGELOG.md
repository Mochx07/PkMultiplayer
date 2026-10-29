# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.6.13

Compatible con 1.6.0–1.6.12 (mismo protocolo 16).

### Arreglado

- **Desincronización por lanzamiento de Poké Balls en combates dobles cooperativos.** Al intentar
  usar una Poké Ball desde la mochila contra los Pokémon de un entrenador durante un combate doble co-op,
  el juego ejecutaba el flujo de un solo jugador (`throwBall` local con la animación de bloqueo y el ataque
  inmediato del rival). Esto esquivaba por completo el sistema lockstep por turnos cooperativo, no enviaba
  la acción al compañero y alteraba el contador de turnos y las semillas de RNG de manera asimétrica,
  dejando a ambos jugadores irreconciliablemente desincronizados.
- **Bloqueo seguro en el menú de la mochila e intercepción defensiva.** Ahora, en cualquier combate
  cooperativo (`battle.coopDouble` / `battle.coopWild`):
  1. `ItemEffects.use` y el menú de la mochila (`BagMenu.useOn`) interceptan el intento antes de consumir
     el objeto o cerrar el menú, mostrando el mensaje canónico («El entrenador bloqueó la Poké Ball. ¡No seas ladrón!»
     o «¡No mientras combaten juntos!» en batallas salvajes), manteniendo la Poké Ball intacta en el inventario
     y sin gastar el turno local.
  2. Como defensa en profundidad, `BattleState:throwBall` y `Gen5BagUse` abortan de inmediato cualquier
     intento de avance de turno asíncrono o tirada de dados fuera de sincronía si se les llama durante combates cooperativos.

## 1.6.12

Compatible con 1.6.0–1.6.11 (mismo protocolo 16).

### Arreglado

- **Bucle infinito de turnos en combates dobles co-op (desconexión y espectador).** En combates
  dobles, al debilitarse los Pokémon seleccionados para el combate (`coopChosenMons`), el motor base
  consultaba erróneamente `save.party` en lugar de la alineación co-op. Si el jugador tenía Pokémon sanos
  en la reserva que no formaban parte del combate, la derrota no se declaraba (`self.result = "lose"`
  nunca se asignaba) pero `self.sideBeaten = "player"` quedaba bloqueado. Al quedar el jugador como
  espectador y desconectarse el compañero (`c.partnerLost = true`), el juego ejecutaba turnos sin retardo
  en cada cuadro, ciclando miles de turnos en minutos.
- **Chequeo de derrota y protección de espectador en `BattleState:playerMonFainted`.** Ahora evalúa
  la alineación cooperativa: si el compañero sigue en pie, el jugador permanece como espectador sin
  sufrir blackout prematuro; si ambos jugadores han caído o no pueden continuar, se activa el blackout
  y el combate termina de forma limpia.
- **Guardas contra bucles rápidos y reconexión en combate.** `CoopBattle.guardEmptySide` y
  `CoopBattle.onSpectatorTurn` ahora detectan de inmediato si ningún bando puede continuar
  (`sideCanContinue`), cortando cualquier ejecución anómala con un limitador de frecuencia. Además,
  la reconexión (`onNewSession` / `onLinkRestored`) ya no queda bloqueada si un timeout previo había
  activado temporalmente el control por IA.

## 1.6.11

Compatible con 1.6.0–1.6.10 (mismo protocolo 16).

### Arreglado

- **El reloj compartido desplazaba también los timestamps que deben ir en hora real.** Cuando el
  anfitrión y el compañero estaban en husos horarios distintos, el offset del reloj afectaba a los
  backups de la partida (quedaban sellados con horas en el futuro, bloqueando los backups rotativos),
  al temporizador de 20 minutos del Concurso de Bichos y al log co-op. Ahora los módulos que miden
  tiempo real (`SaveSafety`, `BugContest`, `CoopLog`, red, mods, descargas) leen el reloj del
  sistema sin offset; el reloj del mundo del juego sigue sincronizado al del anfitrión.
- **Crash en la estructura del buzón de historia offline.** Corregido un fallo de índice nil en el
  buzón de historia (`coopStoryOutbox`) al registrar entrenadores vencidos, accediendo correctamente
  a `.rewards[1].kind` en lugar del índice directo.
- **Modernización del ejecutor de pruebas (`tools/run_tests.sh`).** `test_coop.lua` ahora se corre
  a través del cargador de parches del motor (`run.lua`) en vez de Lua en crudo sin parches,
  eliminando 3 fallos falsos heredados ("3 are old") y dejando la suite completa en 219/219 (0 FAIL).

## 1.6.10

Compatible con 1.6.0–1.6.9 (mismo protocolo 16). Basta con que el **anfitrión** la tenga para
que las reglas se compartan bien; mejor que la tengan los dos.

### Arreglado

- **Las reglas co-op no coincidían en los dos juegos.** Con NEW CO-OP GAME o CONTINUE CO-OP se
  enlaza antes de cargar la partida, y el anfitrión mandaba sus reglas en ese momento (las de
  fábrica, con BALANCED FOES activado) y no las que cargaba su partida después. El compañero se
  quedaba con otras reglas: rivales rellenados en una pantalla y no en la otra, y combates
  distintos. Ahora, cuando el anfitrión carga su partida estando enlazado, vuelve a mandarlas.

## 1.6.9

Compatible con 1.6.0–1.6.8 (mismo protocolo 16).

### Añadido

- **Emotes con el teclado numérico**, sin abrir el selector: 1 sorpresa, 2 pregunta, 3 feliz,
  4 triste, 5 corazón, 6 enfado, 7 sueño y 8 ¡chócala! (la mano). Funcionan en el mapa, como la
  tecla Y. El selector (Y) muestra el número de cada uno.

## 1.6.8

Compatible con 1.6.0–1.6.7 (mismo protocolo 16).

### Añadido

- Dobles co-op: **ves qué va a hacer tu compañero.** Mientras eliges, el recuadro a la izquierda
  de LUCHA / PKMN / OBJETO / HUIR dice qué eligió: el ataque y a quién, el objeto y para quién, a
  qué Pokémon cambia, o que sigue eligiendo.
- El log co-op anota la versión del mod de tu compañero al conectar.

## 1.6.7

Compatible con 1.6.0–1.6.6 (mismo protocolo 16), pero **los dos jugadores necesitan la 1.6.7**
para que los combates dobles no se desincronicen por las reglas de dificultad.

### Arreglado

- **Cierre del juego** tras un corte: si la reconexión fallaba y el menú co-op volvía a la lista
  de "¿a quién te unes?" sin haber pasado antes por ella, el juego se cerraba con
  `CoopMenu.lua:778: attempt to perform arithmetic on field 'pickIndex'`.
- Los avisos de conexión salen enteros: en las pantallas de IP, código y puerto el consejo
  ("FIREWALL: ABRE UDP 7777; REVISA LA IP") se cortaba o ni aparecía. Con un error en pantalla,
  ocupa el sitio de la ayuda de esa pantalla.
- Dobles co-op: **cada pantalla usaba sus propias reglas de dificultad** (BALANCED FOES / HARD
  FOES). Si uno las tenía activadas y el otro no, un juego rellenaba al entrenador y el otro no:
  dos combates distintos desde el primer turno. Ahora la invitación lleva las reglas de quien
  invita y las dos pantallas pelean con ellas.
- Dobles co-op: si un Pokémon del compañero se debilitaba solo en tu pantalla, tu juego esperaba
  su elección para siempre mientras el suyo esperaba tu ataque. Ahora, si llega su siguiente
  ataque en vez de una elección, su Pokémon vuelve a entrar.
- **El chat ya no congela el combate.** En un doble co-op se abre dentro del combate, que sigue
  avanzando mientras escribes (los botones no le llegan).
- **Chat más largo:** 70 letras en 4 filas, cortando por palabras (antes 35, y una tilde contaba
  doble). El historial y los bocadillos muestran el mensaje entero.
- **Elegir 3 Pokémon:** nada se sale ya de la pantalla (el número de orden pisaba el nombre, el
  nivel los PS, y los PS se salían por la derecha). Los avisos largos ocupan dos líneas.
- **Choca esos cinco:** el menú dice "¡CHÓCALA!" (antes no cabía) y sale una mano en vez del
  corazón.

## 1.6.6

Compatible con 1.6.0–1.6.5 (mismo protocolo 16), pero **los dos jugadores necesitan la 1.6.6**
para que el combate se reanude tras un corte y para recibir el log del otro.

### Añadido

- **Reconexión en mitad de un combate doble.** Si se corta la conexión, los dos ven
  "RECONECTANDO..." en el centro de la pantalla y el combate espera. Al volver, cada juego dice
  en qué combate y turno está: si siguen en el mismo, se reenvía lo que se perdió y la pantalla
  del invitado se pone igual que la del anfitrión, y sigue jugando el compañero. La IA solo toma
  sus Pokémon si no vuelve en 3 minutos (antes, 20 segundos), si su juego ya no está en ese
  combate (lo reinició) o si usa una versión anterior.
- **El log co-op se comparte solo.** Cada juego envía las líneas de su `coop.log` al compañero
  mientras están enlazados (las de un corte, al reconectar), y el compañero las guarda en
  `coop-partner.log` junto a su `coop.log`. Ya no hace falta pasarse el archivo para revisar un
  fallo. Se apaga en MODS → PkMultiplayer → OPTIONS → **SHARE CO-OP LOG**.

### Arreglado

- Dobles co-op: tras un corte con la IA al mando, el combate podía quedarse sin ningún Pokémon en
  tu lado y jugar cientos de turnos vacíos por segundo, sin terminar nunca. Ahora, si tu lado
  queda vacío dos turnos seguidos sin nadie pendiente de entrar, sale el siguiente Pokémon sano
  del equipo que toque, y si no queda ninguno el combate se da por perdido.

## 1.6.5

Compatible con 1.6.0–1.6.4 (mismo protocolo 16): no hace falta que el compañero actualice.

### Arreglado

- Dobles co-op (Oro/Plata/Cristal y Rojo/Azul/Amarillo): un ataque en área repetía su
  animación en cada objetivo, así que SURF, TERREMOTO, MAGNITUD o EXPLOSIÓN (los dos rivales y
  tu compañero) se veían tres veces para un solo ataque. Ahora la animación sale una vez y los
  demás objetivos muestran el golpe con su parpadeo y su sonido.

## 1.6.4

Compatible con 1.6.0–1.6.3 (mismo protocolo 16), pero los dos jugadores deben actualizar
para que el arreglo funcione.

### Arreglado

- Dobles co-op: **las dos pantallas calculaban el combate con reglas distintas.** El conjunto
  de reglas de combate (ruleset: gen1_faithful, modern_clean...) es una opción de cada partida,
  y cada copia usaba el suyo: desde el primer turno salían daños distintos (y con gen1_faithful
  los rivales no gastan PP). Ahora la invitación lleva el ruleset del anfitrión y el invitado lo
  usa durante el combate (entrenadores, salvajes en pareja y la Torre).
- Dobles co-op: con BALANCED FOES, un entrenador con un solo Pokémon trae copias de él, y la
  corrección que el anfitrión manda cada turno mezclaba los PS y el estado de los dos gemelos en
  la pantalla del invitado; las dos copias ya no volvían a coincidir en todo el combate. Ahora
  cada corrección solo toca a su propio Pokémon.

## 1.6.3

Compatible con 1.6.0, 1.6.1 y 1.6.2 (mismo protocolo 16), pero conviene que los dos
jugadores actualicen: el arreglo actúa en la copia de cada uno.

### Arreglado

- Dobles co-op: el Pokémon del compañero se quedaba en el campo a 0 PS (medio hundido) el
  resto del combate, mientras en su pantalla ya peleaba con el que había sacado después. Pasaba
  cuando las dos copias del combate no coincidían en el turno en que cayó: esta copia nunca lo
  daba por debilitado, su elección quedaba esperando y sus ataques se leían contra el caído; a
  veces el combate acababa a medias. Ahora, al abrir cada turno, si el compañero dice que su
  Pokémon está debilitado, sale y entra el que eligió.

## 1.6.2

Compatible con 1.6.0 y 1.6.1 (mismo protocolo 16).

### Arreglado

- El Pokémon que te sigue podía quedar encimado con un NPC del pueblo: los dos dibujos se
  turnaban en la misma casilla. Ahora un NPC que camina por su cuenta no entra en la casilla
  del seguidor (ni en la que está por pisar), y el seguidor espera si alguien ocupa su
  siguiente paso. Tú sigues pudiendo pasar a través de él, y las escenas y la vista de los
  entrenadores no cambian.
- NEW CO-OP GAME / CONTINUE CO-OP: al esperar invitado, el código y el puerto se salían por el
  borde inferior de la caja. Y en todo el mod los textos ya no pisan el borde derecho de las
  cajas (antes se cortaban en el borde de la pantalla).

## 1.6.1

Compatible con 1.6.0 (mismo protocolo 16): no hace falta que el compañero actualice.

### Cambiado

- Parches regenerados contra **Gen2Recomped 0.8.47** (8d5b438). En la 0.8.47 cambiaron
  `BattleState`, `TrainerAI`, `BagMenu` y `OverworldController`; con 1.6.0 el mod ponía
  encima sus versiones de la 0.8.46 y se perdían los arreglos nuevos del motor (y el
  `interact` del mundo nuevo usa `GEN4_SIGN_FACING`, que la versión vieja no conocía).
  Ahora los cambios del co-op se colocan sobre el código de la 0.8.47.

### Arreglado

- Dobles: cada rival se coloca según **sus propios píxeles**. Un Pokémon alto (Pidgeotto,
  Tyranitar, Onix) sube lo justo para no pisar el nombre de tu Pokémon y uno pequeño se queda
  donde estaba; si es muy ancho se corre para no salirse por la derecha. Las animaciones de
  ataque apuntan a ese mismo sitio.
- Dobles: el nombre y nivel de tus Pokémon van sobre una franja blanca, legibles aunque un
  rival gigante (Lugia, Gyarados) llegue hasta ahí.
- Ningún texto del mod se sale ya de la pantalla: lo que no cabe desde donde empieza se corta
  con un punto. Los avisos de arriba tienen 3 líneas en vez de 2 (en español se cortaban).
- La ayuda de la selección de equipo ("[A] PICK/CONFIRM [B] BACK") se salía de la pantalla
  también en inglés: ahora "A:PICK  B:BACK".
- 10 textos que salían en inglés con el mod en español.

### Compatible con el 3D de DramaticShapes

- Con el mundo en 3D (DramaticShapes, incluido en Gen2Recomped) las capas del co-op se dibujaban
  sobre una imagen que el 3D reemplaza: no se veían o salían corridas. Ahora entran por el mismo
  camino que los efectos del juego (`ctx.drawFx`) y se colocan con la cámara 3D: el nombre del
  compañero, sus emotes y los tuyos, los puntitos de "hablando", la Poké Ball de "en combate",
  "¡LISTO!", los nombres de los visitantes y la flecha al borde cuando no está en cuadro. Lo que va
  sobre la cabeza sube con la altura de los personajes en 3D, también cerca de la cámara.
- Los combates dobles co-op siguen en la pantalla clásica: DramaticShapes todavía no escenifica
  dobles.

## 1.6.0

**Los dos jugadores necesitan esta versión** (protocolo 16). Incluye lo que
iba a ser 1.5.2.

### Añadido

- **Entrar con un código.** El host ve un código corto (`30AG-0B4`: su IP y,
  si no es el 7777, su puerto). JOIN → **TYPE A CODE**: se escribe o se pega
  con Ctrl+V; también desde NEW CO-OP GAME / CONTINUE CO-OP (SELECT). El dial
  de la IP sigue para el mando.
- **JOIN recuerda los tres últimos hosts.** Y una fila **PORT** para cambiar el
  puerto (dos juegos en el mismo PC). La pantalla de host dice también el
  puerto de las visitas.
- **Los errores, enteros y con qué hacer**: "HOST NOT FOUND" dice que abras el
  puerto UDP en el firewall y revises la IP; "PORT IN USE", que te unas o
  visites; otra versión, que los dos necesitáis la misma. Antes se cortaban a
  18 letras. Con el mismo protocolo pero otra versión, un aviso suave al
  enlazar.
- **Rojo, Azul y Amarillo comparten la historia.** Sus eventos son Lua, no
  scripts, y el compañero no recibía nada. Ahora cada uno se compara antes y
  después: flags, objetos que desaparecen del mapa, objetos recogidos,
  mochila y dinero. Medalla y MT de los líderes, OAK'S PARCEL, el fósil de
  Mt. Moon (uno cada uno, nunca los dos) y los regalos llegan al compañero;
  un Pokémon regalado, una compra o un legendario siguen siendo de cada uno.
- **Los líderes de Rojo/Azul/Amarillo preguntan CO-OP o SOLO antes de
  hablar**, como en Oro: el compañero elige equipo mientras lee. KOGA tiene su
  SOULBADGE, GIOVANNI solo da la EARTHBADGE en su gimnasio, y LORELEI, BRUNO,
  AGATHA y LANCE cuentan como combates grandes.
- **LISTO / NO LISTO** (tecla **R**, o READY en el menú): el compañero lo ve
  sobre tu cabeza y como **OK** junto a tu nombre; si un líder pregunta CO-OP
  y tu compañero no está listo, te lo dice. Se borra al empezar el combate.
- **Resultado co-op** tras cada doble: unos segundos arriba, los K.O. y la EXP
  de cada uno y el Pokémon que más hizo.
- **Dónde está tu compañero**: en otro mapa, una flecha en el borde apunta
  hacia él (por el mapa de la región; Kanto queda al este de Johto) y arriba
  sale el nombre del sitio.
- **Estado del enlace** (VERSION): ping, pérdida, mensajes reenviados,
  repetidos descartados, reconexiones, desfases de combate corregidos y las
  versiones de los dos.

- **El mod en español.** Nueva opción en MODS → PkMultiplayer → OPTIONS →
  **LANGUAGE / IDIOMA**:
  - **AUTO** (por defecto) sigue el idioma al que el launcher traduce el
    juego;
  - **ENGLISH** o **ESPANOL** lo fijan.
  - Se traducen los menús co-op, las reglas y sus explicaciones, los avisos,
    las invitaciones, la elección de equipo, la Pokédex co-op, WATCH, los
    emotes, el Pokémon que te sigue y la fila del título y del menú START.
  - El chat y los nombres de los jugadores nunca se traducen.
  - Con el mod de glifos españoles (letras del cartucho Edición Oro) se
    dibujan á é í ó ú ñ ¿ ¡. Sin él, se escriben sin tilde en vez de salir
    como huecos.
- La fila del menú START se llama ahora **CO-OP ONLINE**: funciona por
  internet (ZeroTier), no solo en la red local.

### Cambiado

- **Oro/Plata y Cristal no comparten la historia.** Numeran sus eventos de
  forma distinta (Cristal añadió flags por en medio), y copiarlos marcaba
  eventos equivocados. Al enlazar sale el aviso; combates, intercambios y
  chat siguen igual.
- Las reglas se guardan en la partida, también STORY SYNC sin conectar.
- Rojo/Azul/Amarillo no preguntan por el reloj ni enseñan LINK DAYCARE.
- Una invitación ya no se acepta con la A que venías pulsando: hace falta
  soltarla y pulsar otra vez (tras 0,8 s). Si caduca, lo dice. La etiqueta de
  B se ve siempre mientras esperas.
- Un salvaje en pareja se anuncia como tal ("¿LUCHAR JUNTOS?").
- En NEW CO-OP GAME, cada uno ve su propia hora primero, y salir pide B dos
  veces.

### Corregido

- El aviso de arriba partía mal las palabras con acentos (contaba bytes, no
  letras), y la fuente pequeña dibujaba cada letra acentuada como dos "?".
- Una victoria co-op contra GIOVANNI en el Escondite Rocket ya no da la
  EARTHBADGE al invitado.
- La bandera de entrenador de un compañero de Cristal ya no se escribe en una
  partida de Oro/Plata (marcaba otro evento).

## 1.5.1

**Los dos jugadores necesitan esta versión** (protocolo 15): con 1.5.0 el
equipo del rival y el daño de un turno saldrían distintos en cada juego.

### Añadido

- **Dificultad co-op**, dos reglas compartidas en RULES:
  - **BALANCED FOES** (activada por defecto): un entrenador de un doble co-op
    trae al menos dos Pokémon por cada tres de los vuestros (los de más son
    copias de su propio equipo, en orden). Si vuestro equipo le saca ventaja,
    sube uno o dos niveles.
  - **HARD FOES**: un rival por cada Pokémon vuestro, y tres niveles más.
  - Las dos desactivadas dejan el equipo del cartucho. Nunca afectan a los
    salvajes en pareja, la Torre de Combate ni P1 vs P2. Los dos juegos
    calculan el mismo equipo sin tirar dados.
- **Entrenadores más listos en Oro, Plata y Cristal** (combates
  individuales):
  - antes elegían su movimiento al azar, porque el motor solo lee la IA de
    Gen 1;
  - ahora eligen con la misma lectura del combate que los rivales de los
    dobles co-op (quién puede debilitar a quién, quién se mueve antes, qué ya
    está activo);
  - líderes, Alto Mando, campeón, rival, RED y ejecutivos del Team Rocket lo
    hacen siempre; los COOLTRAINER casi siempre; el resto, la mitad de las
    veces, para no castigar al que empieza;
  - los objetos, cambios y movimientos bloqueados siguen siendo los del
    cartucho;
  - se desactiva en MODS → PkMultiplayer → OPTIONS → SMARTER TRAINERS.
- **Una pantalla para todo el lado en los dobles co-op:** en Oro, Plata y
  Cristal, REFLECT y PANTALLA LUZ protegían solo al Pokémon que las usó, y su
  compañero quedaba al descubierto. Ahora, como en HeartGold/SoulSilver,
  cubren a los dos Pokémon de su lado (también los de los rivales). La IA lo
  tiene en cuenta y no la repite si el compañero ya la tiene.
- **Animaciones de Rojo, Azul y Amarillo en los dobles co-op** sobre los
  Pokémon que de verdad luchan: antes se dibujaban en los dos puntos del
  combate individual, así que el ataque del Pokémon del compañero salía del
  tuyo y caía entre los dos rivales. Los combates individuales de Gen 1 se ven
  igual que siempre.
- **Ataques en área animados en cada rival:** en un doble co-op de Gen 1 o
  Gen 2, ROCK SLIDE, SURF, BLIZZARD y compañía mostraban su animación solo
  sobre el primer objetivo, y el segundo recibía el golpe sin ver nada. Ahora
  la animación se repite en cada uno.

### Corregido

- **Combate co-op sincronizado:**
  - cada turno las dos copias comparan una firma del estado (HP, estado,
    etapas, PP, objeto, contadores, banquillo rival) y, si difieren, el
    invitado toma la palabra del anfitrión;
  - la sincronización de un turno viejo ya no pisa el HP de uno nuevo;
  - las acciones, cambios y sincronizaciones enviados durante un corte llegan
    al reconectar, y ya nadie se queda esperando un turno perdido;
  - la IA solo toma el Pokémon del compañero tras 20 s sin enlace, y se lo
    avisa.
- **IA rival de los dobles:**
  - ya no repite GROWL, LEER y compañía sin fin;
  - ya no encadena PROTECT;
  - ve el REFLECT y la PANTALLA LUZ de Oro, Plata y Cristal;
  - ya no calcula el daño reducido de un ataque en área cuando solo queda un
    objetivo en pie.
- **Nuestros Pokémon miraban hacia el otro lado en los combates dobles co-op**
  con el mod de vóxeles (DramaticShapes) activado. En sus combates 3D los dos
  bandos miran a la cámara, así que cambia la foto de espaldas de tu lado por
  la de frente, y lo seguía haciendo en los dobles co-op, que se juegan en la
  pantalla clásica. Ahora, mientras dura un doble co-op o un salvaje en
  pareja, tu Pokémon y el del compañero salen de espaldas, mirando a los
  rivales.

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
