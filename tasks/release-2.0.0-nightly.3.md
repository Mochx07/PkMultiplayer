**Nightly** (test build) of 2.0 focused on **Gen 1 (Red / Blue / Yellow)**, third editions, official Link Hub connectivity and mobile touch support. The stable release is still 1.6.17. **New link protocol (17):** both players need `2.0.0-nightly.3` (it no longer links with protocol 16; each copy tells you which version the other player has). Needs Gen2Recomped 0.8.58 or later.

### New
- **Protocol 17 and Edition Matrix (`CoopEditions`):** Red/Blue with Yellow and Gold/Silver with Crystal share one story through a single receiver filter (`3RD ED. STORY` enabled by default). Shared events sync or translate cleanly by name, while edition-exclusive events (Yellow's Jessie & James, gift starters, Pikachu; Crystal exclusives) stay in their own save with a clean notice to your partner.
- **Gen 1 Gyms & Pokémon League in 2-vs-2:** all 8 Kanto gyms (16/16 verified across Red and Yellow, Pewter through Viridian) and all 5 League rooms (Lorelei, Bruno, Agatha, Lance and Champion) work as co-op doubles, awarding badges, TMs and Hall of Fame credit to both players.
- **Gen 1 Rival 2-vs-2 & Legendary Bosses:** Red/Blue counter-pick and Yellow Eevee rival battles pair into 2-vs-2 doubles; Articuno, Zapdos, Moltres (1.5× HP) and Mewtwo (2× HP) are two-action co-op bosses you can catch together.
- **Gen 1 Co-op Story:** S.S. Anne, Pokémon Tower (Marowak, Mr. Fuji, Poké Flute), Rocket Hideout (Lift Key, Giovanni, Silph Scope), Silph Co. (Card Key doors, personal Lapras, Giovanni + Rocket exodus), Safari Zone (shared HM/Teeth/Surf) and Snorlax, with two-lead scenes (`story.duo`).
- **Gen 1 Cable Club & Official Link Hub (no VPN needed):** the Cable Club receptionist offers `LINK WITH <partner> / OTHER` to enter Trade Center or Colosseum directly over the co-op link without a code. `HOST ONLINE` and `JOIN` by code (up to 24 characters, Ctrl+V or on-screen touch keyboard) connect through the game's own link ladder and official Link Hub.
- **Gen 1 Bike Trial:** Kanto's Cycling Road (Route 16 Gate -> Route 17 -> Route 18).
- **Partner on the Town Map (`CoopTownMap`):** your partner's avatar head is drawn directly on the Gen 1 and Gen 2 Town Map, mapped by map ID across editions.
- **Timed joint catching (`catch.aim`):** when both players throw a Ball on the same turn, a ring closes on the wild Pokémon in 1.2 s; pressing A in time scales the catch bonus up to ×3 (`PERFECT` <=100 ms, ×2.25 <=250 ms, ×1.75 <=450 ms, ×1.5 base).
- **Mobile touch controls:** touch support across the mod's menus, invites, team select, emotes, VS screens and Link Hub code entry; keyboard hints are hidden on phones and on-screen/gamepad **R** acts as push-to-talk (`PUSH R`).

### Changed
- **Wild co-op is now 2-vs-1:** a single wild Pokémon faces both players (no mirrored twin).
- **Gen 1 2-vs-2 back sprites:** P1 and P2 back sprites now stand side by side instead of overlapping.
- **Catch Ball placement in doubles:** the thrown Ball sits higher so it stays clear of the double-battle HUD names (Gen 1 and Gen 2).
- **Engine version warning:** running on a Gen2Recomped older than 0.8.58 now logs and shows an on-screen notice instead of loading silently without patches.

### Fixed
- **Solo emotes:** pressing `EMOTE` without a connected partner now shows the bubble over your own character instead of closing the menu silently.
- **24-character Link Hub codes:** preserved intact via Ctrl+V, touch keyboard and New Co-op Game, wrapping cleanly onto two lines.

## Español

**Nightly** (versión de prueba) de la 2.0 centrada en **Gen 1 (Rojo / Azul / Amarillo)**, terceras ediciones, conexión por Link Hub oficial y soporte táctil en móvil. La estable sigue siendo la 1.6.17. **Protocolo nuevo (17):** los dos jugadores necesitan `2.0.0-nightly.3` (ya no enlaza con protocolo 16; cada copia avisa qué versión tiene el otro). Necesita Gen2Recomped 0.8.58 o posterior.

### Novedades
- **Protocolo 17 y matriz de ediciones (`CoopEditions`):** Rojo/Azul con Amarillo y Oro/Plata con Cristal comparten historia bajo un único filtro al recibir (`3RD ED. STORY` encendida por defecto). Los eventos comunes se comparten o traducen por nombre, y los exclusivos de edición (Jessie y James, iniciales regalados y Pikachu en Amarillo; exclusivos de Cristal) se quedan en su partida con un aviso para el compañero.
- **Gimnasios y Liga Pokémon de Gen 1 en 2 contra 2:** los 8 gimnasios de Kanto (16/16 verificados en Rojo y Amarillo, de Ciudad Plateada a Verde) y las 5 salas de la Liga (Lorelei, Bruno, Agatha, Lance y campeón) funcionan en doble co-op con medalla, MT y Salón de la Fama para los dos.
- **Rival en 2 contra 2 y legendarios jefes en Gen 1:** combates de rival emparejados (contrainicial en Rojo/Azul y Eevee en Amarillo); Articuno, Zapdos, Moltres (×1,5 PS) y Mewtwo (×2 PS) son jefes co-op de dos acciones capturables juntos.
- **Historia co-op de Kanto:** S.S. Anne, Torre Pokémon (Marowak, Sr. Fuji, Poké Flauta), Guarida Rocket (Llave Ascensor, Giovanni, Visor Silph), Silph S.A. (puertas Llave Magnética, Lapras personal, Giovanni y retirada Rocket), Zona Safari (MO y Dientes compartidos) y Snorlax, con escenas a dos (`story.duo`).
- **Club de Cable y Link Hub oficial sin VPN:** la recepcionista ofrece `LINK WITH <compañero> / OTHER` para entrar al Centro de Intercambio o Coliseo por el enlace co-op sin código; `HOST ONLINE` y `JOIN` por código (hasta 24 caracteres, `Ctrl+V` o teclado táctil) conectan por la escalera y Link Hub oficial del juego.
- **Contrarreloj en bici en Gen 1:** Ruta Ciclista de Kanto (Puerta Ruta 16 -> Ruta 17 -> Ruta 18).
- **Compañero en el Mapa (`CoopTownMap`):** la cabeza de tu compañero aparece sobre el Mapa de Gen 1 y Gen 2, situada por id de mapa entre ediciones.
- **Captura conjunta sincronizada (`catch.aim`):** cuando los dos lanzan Ball en el mismo turno se cierra un aro sobre el salvaje en 1,2 s; pulsar A a tiempo sube el bono hasta ×3 (PERFECTA <=100 ms, ×2,25 <=250 ms, ×1,75 <=450 ms, ×1,5 base).
- **Controles táctiles en móvil:** toque en menús del mod, invitaciones, selección de equipo, emotes, pantallas VS y teclado táctil para códigos del Link Hub; sin pistas de teclado en móvil y botón **R** (táctil o mando) para pulsar y hablar (`PUSH R`).

### Cambios
- **Salvajes en pareja ahora son 2 contra 1:** un solo Pokémon salvaje frente a los dos jugadores (sin gemelo espejo).
- **Espaldas separadas en dobles de Gen 1:** los sprites de P1 y P2 ya no se enciman.
- **Ball más alta en dobles:** la Poké Ball queda libre de los nombres del HUD (Gen 1 y Gen 2).
- **Aviso si el motor es anterior a 0.8.58:** avisa en pantalla y en el log en vez de cargar en silencio sin parches.

### Arreglos
- **Emotes en solitario:** usar `EMOTE` sin compañero muestra el globo sobre tu personaje en vez de cerrar el menú sin hacer nada.
- **Códigos largos del Link Hub (24 caracteres):** conservados completos en `Ctrl+V`, teclado táctil y Nueva Partida Co-op, con salto limpio en dos líneas.
