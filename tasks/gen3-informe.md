# Gen 3 (Esmeralda) y el co-op: informe de investigación (1.20, M5)

Hecho el 2026-11-10 leyendo el código de Gen2Recomped **0.8.57** (`b205bf4e`).
No hay caché de Esmeralda en esta máquina, así que nada de esto se ha ejecutado
con una partida de Gen 3: es lectura de código, no una prueba.

## Resumen

Llevar el co-op de historia a Esmeralda es posible, pero es un proyecto aparte,
no un añadido a 1.20. El combate y el mundo usan los mismos módulos que ya
parcheamos, así que esa parte se aprovecha casi entera. Lo que no se aprovecha
es todo lo que cuelga del motor de scripts y de los menús, que en Gen 3 son
otros archivos. Estimación a ojo: entre un tercio y la mitad del trabajo que
costó Gen 2.

Además, desde 0.8.50 el motor trae su propio online (`src/online/`, 21 900
líneas). No hace co-op de historia, pero cambia qué merece la pena construir.

## Qué expone el motor para Gen 3

| Parte | Dónde | Sirve al co-op tal cual |
|---|---|---|
| Combate | `src/battle/BattleState.lua` (el mismo de Gen 1/2, 13 296 líneas) + `Gen3Battle.lua`, `Gen3MoveEffects.lua`, `Gen3AI.lua`, `Abilities.lua` | Sí en estructura: mismas posiciones, `sides`, `battlerAt`, `self.ally` |
| Dobles | Nativos: `Gen3Commands.DOUBLE_KINDS` (entrenadores dobles), combates con compañero (Steven) | Sí: no hay que forzar el doble como en Gen 2 |
| Mundo | `src/world/OverworldController.lua` (el mismo) + `Gen3Elevation`, `Gen3FieldMove`, `Gen3Weather`… | Sí para presencia; las MO son otros módulos |
| Scripts | `src/script/Gen3ScriptVM.lua` + `Gen3Commands.lua` (`g3_trainer_battle`, `g3_set_flag`, `waitstate`) | No: `CoopStory` engancha `ScriptRunner` y `Commands` de Gen 2 |
| Menús | `Gen3StartMenu`, `Gen3BagMenu`, `Gen3PartyMenu`, `Gen3SummaryMenu` | No: parcheamos `Menu`, `BagMenu`, `PartyMenu` de Gen 1/2 |
| Guardado | `src/core/SaveData.lua` (el mismo) | Sí: el id co-op y las reglas viven ahí |
| Pokémon por la red | `src/online/MonCodec.lua` (formato v3: personalidad, IV, EV, naturaleza, habilidad) | Sí, y hay que usarlo: el formato viejo pierde esos datos |

## Qué se puede reutilizar de PkMultiplayer

- **Sin tocar:** red y sesión (`CoopNet`, `CoopWire`), capacidades, chat, emotes,
  registro compartido, minijuegos (el marco), menú co-op, traducción.
- **Con cambios pequeños:** presencia del compañero y su Pokémon (otra hoja de
  sprites y `Gen3Elevation` para dibujarlo en la capa correcta), combates P1 VS
  P2 (el motor ya trae `LinkBattleModern` para Gen 3+: mejor apoyarse en él que
  en nuestro túnel).
- **Hay que rehacer:**
  1. `CoopStory` para `Gen3ScriptVM`: banderas, variables (`VAR_*`, que en Gen 2
     no existen) y esperas de escena.
  2. Los parches de `BattleState` validados con las reglas de Gen 3: habilidades
     y clima meten tiradas de RNG nuevas, y el orden de esas tiradas es lo que
     mantiene las dos copias iguales. Es la parte con más riesgo de desincronía.
  3. Menús propios de Gen 3 (objeto en combate, cambio, equipo del compañero).
  4. Tablas por juego: gimnasios en equipo, jefes, puntos de PONERSE AL DÍA.

## Qué falta en el motor

- El mod se apaga solo en generación 3 o más (`main.lua:147`); `manifest.json`
  dice "Gen 1 and Gen 2 only". Hay que partir los parches por generación.
- El motor aún marca Esmeralda como alfa. Su propio documento
  (`docs/online-design.md`, 1.4) dice que no se ha terminado ningún combate de
  Gen 3/4/5 por enlace de punta a punta.
- No hay punto de extensión para scripts de Gen 3 equivalente al que usamos en
  Gen 2: habría que envolver `Gen3Commands` como hacemos con `Commands`.

## El online propio del motor (0.8.50–0.8.57)

Lo que trae: códigos de invitación, combates e intercambios en todos los juegos,
salas de enlace dentro del juego, GTS sin servidor, combates de 4, y "mundos"
de hasta 16 jugadores.

Lo que **no** trae: historia compartida. En un mundo cada jugador juega su
propia partida y los demás son una capa de presencia (`online-design.md` 2.8).
No hay combates de entrenador en doble con el compañero, ni banderas de
historia compartidas, ni gimnasios o jefes para dos.

Consecuencias para PkMultiplayer:

- El co-op de historia sigue siendo lo que solo hace este mod.
- VS, repeticiones y minijuegos de 1.20 ahora tienen equivalente parcial en el
  motor. No conviene crecer por ahí (torneos, draft, 2v2 de 4): el motor ya lo
  cubre.
- Los parches de 1.6.17 **no entran en 0.8.57** (`BattleState` queda sin
  parchear). 1.20 los trae rehechos contra 0.8.57 y deja de funcionar en 0.8.49.

## Recomendación

1. No empezar Gen 3 hasta que el motor saque Esmeralda de alfa.
2. Si se hace, empezar por el tramo pequeño: presencia + chat + combate doble
   co-op contra entrenadores, sin historia compartida. Eso ya dice si las dos
   copias se mantienen iguales con habilidades y clima.
3. Antes de eso, una prueba de humo con una caché real de Esmeralda: quitar el
   corte de generación, ver qué parches entran y correr `coop_lockstep` con
   datos de Gen 3.
