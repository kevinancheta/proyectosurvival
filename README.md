# Proyecto Survival

Survival 3D multijugador con estética medieval, inspirado en Rust, The Forest y Reign of Kings. Un jugador puede ser el rey y fijar el tributo: el porcentaje de recursos que juntan los demás y van al tesoro del trono.

Hecho con **Godot 4.2 o superior** (versión estándar, no la ".NET"). Usa el renderizador de compatibilidad, así que corre también en computadoras modestas.

## Cómo abrirlo

1. Bajá Godot 4 desde https://godotengine.org/download (no necesita instalación).
2. Clonás o descargás este repositorio.
3. Abrí Godot, tocá **Importar** y elegí el archivo `project.godot` de esta carpeta.
4. Tocá **Importar y editar** y después **F5** para jugar.

La primera vez Godot tarda un momento en importar el proyecto. Si aparece algún error rojo en la consola de abajo, copialo completo y pasáselo a Claude.

## Controles

| Tecla | Acción |
|---|---|
| WASD o flechas | Moverte |
| Mouse | Mirar |
| Shift | Correr |
| Espacio | Saltar |
| Clic izquierdo (mantenido) | Golpear: talar árboles y picar rocas |
| 1 / 2 o rueda del mouse | Cambiar entre hacha y pico |
| Esc | Soltar el mouse (clic para volver a capturarlo) |

## Recolección

- Apuntá a un árbol o una roca con la mira: aparece "Clic izquierdo: Talar árbol" o "Picar roca".
- **Hacha** para la madera y **pico** para la piedra. Cada uno sirve para lo otro, pero mucho más lento: el texto de la mira avisa cuando llevás la herramienta equivocada.
- Un árbol aguanta 6 golpes de hacha (o 15 de pico), se sacude, cae y suelta 2 a 4 troncos. Queda el tocón.
- Una roca aguanta 4 golpes de pico (o 10 de hacha). Va soltando piedras mientras se rompe y se achica. Rinde 6 piedras en total con cualquiera de las dos herramientas.
- Los troncos y las piedras sueltos se recogen caminando cerca. La mochila está abajo a la izquierda.

## Estructura

- `scenes/main.tscn`: escena principal.
- `scripts/main.gd`: genera el terreno, los árboles y las rocas, y crea al jugador. Las constantes de arriba (tamaño del mundo, cantidad de árboles, altura de las colinas) se pueden cambiar.
- `scripts/tree_factory.gd`: fabrica los árboles (pinos, robles, secos) y arbustos con formas irregulares.
- `scripts/player.gd`: jugador en primera persona, herramientas, golpes y mochila.
- `scripts/tool_factory.gd`: modelos del hacha y el pico que se ven en pantalla.
- `scripts/harvestable.gd`: lógica de cada árbol y roca (golpes, caída, drops).
- `scripts/pickup.gd`: troncos y piedras sueltos en el suelo.
- `scripts/inventory.gd`: la mochila (cuántos objetos de cada tipo).
- `tests/harvest_test.gd`: prueba automática de la recolección. Se corre con `godot --headless --path . -s res://tests/harvest_test.gd`. Los avisos `mesh_get_surface_count` que salen en ese modo son normales (no hay pantalla) y no afectan al juego.
- `scripts/mesh_builder.gd`: arma modelos por código (cajas, cilindros, techos a dos aguas) con colisión.
- `scripts/medieval_factory.gd`: casas con entramado de madera, torres, castillo con sala del trono, antorchas, fogatas, pozo, puestos de mercado, empalizadas, banderas.
- `scripts/settlements.gd`: dónde van la aldea (70, 35), el castillo (125, -130), el camino de tierra y tres puestos de vigilancia.
- `scripts/flicker.gd`: luz de fuego que titila.
- `tests/structures_test.gd`: comprueba que se entra a las casas y al castillo (`godot --headless --path . -s res://tests/structures_test.gd`).
- `scripts/build_catalog.gd`, `scripts/piece.gd`, `scripts/builder.gd`: construcción. El catálogo define las piezas y su costo, `piece.gd` es cada pieza (plano, materiales, vida) y `builder.gd` el fantasma y la grilla de 3 m.
- `tests/build_test.gd`: prueba de la construcción (`godot --headless --path . -s res://tests/build_test.gd`).
- `scripts/day_night.gd`: ciclo de día y noche (dura 10 minutos reales por día).

## Plan

1. [x] Mundo base: terreno, bosque, jugador y ciclo de día y noche.
2. [x] Recolección: talar árboles, picar rocas, inventario.
3. [ ] Construcción tipo The Forest: planos, troncos y estructuras piezas por pieza.
4. [ ] Supervivencia: hambre, sed, frío y enemigos de noche.
5. [ ] Servidor multijugador.
6. [ ] Sistema de rey: trono, tributo, leyes.

## Construcción (tecla 3, martillo)
- Rueda del mouse o Q: cambiar de pieza. R: girar (techo, cofre, fogata). Clic: poner el plano.
- Apuntá al plano con el martillo y hacé clic para entregarle troncos (y piedras) de a uno hasta completarlo.
- Pieza: piso 4 troncos, pared 4, pared con puerta 5, techo 4, empalizada 3, fogata 2 troncos + 3 piedras, cofre 5.
- E: abrir/cerrar puertas y usar el cofre (guarda todo o saca todo).
- Hacha o pico sobre una pieza terminada la rompe y devuelve la mitad de los materiales; sobre un plano lo deshace.
