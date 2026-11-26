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
| Esc | Soltar el mouse (clic para volver a capturarlo) |

## Estructura

- `scenes/main.tscn`: escena principal.
- `scripts/main.gd`: genera el terreno, los árboles y las rocas, y crea al jugador. Las constantes de arriba (tamaño del mundo, cantidad de árboles, altura de las colinas) se pueden cambiar.
- `scripts/player.gd`: jugador en primera persona.
- `scripts/day_night.gd`: ciclo de día y noche (dura 10 minutos reales por día).

## Plan

1. [x] Mundo base: terreno, bosque, jugador y ciclo de día y noche.
2. [ ] Recolección: talar árboles, picar rocas, inventario.
3. [ ] Construcción tipo The Forest: planos, troncos y estructuras piezas por pieza.
4. [ ] Supervivencia: hambre, sed, frío y enemigos de noche.
5. [ ] Servidor multijugador.
6. [ ] Sistema de rey: trono, tributo, leyes.
