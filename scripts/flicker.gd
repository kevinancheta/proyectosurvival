extends OmniLight3D
## Luz de fuego que titila. Poné la energía base en light_energy antes de agregarla a la escena.

var _base := 1.0
var _t := 0.0


func _ready() -> void:
	_base = light_energy
	_t = randf() * 20.0


func _process(delta: float) -> void:
	_t += delta
	light_energy = _base * (1.0 + 0.14 * sin(_t * 9.0) + 0.09 * sin(_t * 21.0 + 1.7) + 0.05 * sin(_t * 37.0))
