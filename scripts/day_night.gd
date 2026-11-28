extends Node
## Ciclo de día y noche: crea el cielo, el sol y la niebla, y los va cambiando con la hora.
## time_of_day va de 0.0 a 1.0: 0.0 = medianoche, 0.25 = amanecer, 0.5 = mediodía, 0.75 = atardecer.

@export var day_length: float = 600.0   ## segundos reales que dura un día completo
@export var start_time: float = 0.30    ## hora a la que arranca la partida (0.30 = 7:12)

var time_of_day: float = 0.30
var day: int = 1

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial

const SKY_TOP_DAY := Color(0.22, 0.42, 0.72)
const SKY_HOR_DAY := Color(0.62, 0.70, 0.76)
const SKY_TOP_DUSK := Color(0.25, 0.25, 0.45)
const SKY_HOR_DUSK := Color(0.95, 0.55, 0.30)
const SKY_TOP_NIGHT := Color(0.010, 0.015, 0.040)
const SKY_HOR_NIGHT := Color(0.045, 0.055, 0.095)
const AMBIENT_DAY := Color(0.36, 0.40, 0.46)
const AMBIENT_NIGHT := Color(0.15, 0.19, 0.32)


func _ready() -> void:
	time_of_day = start_time

	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.0035
	_env.tonemap_exposure = 0.85
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.85
	_env.adjustment_contrast = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 1.0)
	add_child(_moon)

	_apply()


func _process(delta: float) -> void:
	var previous := time_of_day
	time_of_day = fmod(time_of_day + delta / day_length, 1.0)
	if time_of_day < previous:
		day += 1
	_apply()


## Devuelve la hora del juego como texto, por ejemplo "07:12".
func get_clock_text() -> String:
	var hours := time_of_day * 24.0
	var h := int(hours)
	var m := int((hours - h) * 60.0)
	return "%02d:%02d" % [h, m]


## Sirve para más adelante: los zombis, el frío, etc. dependen de si es de noche.
func is_night() -> bool:
	return _elevation() < -0.05


func _elevation() -> float:
	return sin((time_of_day - 0.25) * TAU)


func _apply() -> void:
	var elev := _elevation()
	var day_w := smoothstep(-0.05, 0.35, elev)          # 0 = noche, 1 = día pleno
	var dusk_w := clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0)  # fuerte cerca del horizonte

	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day_w).lerp(SKY_TOP_DUSK, dusk_w * 0.7)
	var hor := SKY_HOR_NIGHT.lerp(SKY_HOR_DAY, day_w).lerp(SKY_HOR_DUSK, dusk_w * 0.85)

	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_horizon_color = hor
	_sky_mat.ground_bottom_color = hor.darkened(0.5)

	_env.fog_light_color = hor
	_env.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, day_w)

	# El sol sale por un lado, cruza el cielo y se pone por el otro.
	var angle := (time_of_day - 0.25) * TAU
	_sun.rotation = Vector3(-angle, deg_to_rad(-30.0), 0.0)
	_sun.light_energy = maxf(0.0, elev) * 0.95
	_sun.light_color = Color(1.0, 0.95, 0.82).lerp(Color(1.0, 0.6, 0.35), dusk_w)
	_sun.shadow_enabled = elev > 0.02

	# La luna viene del lado opuesto y da luz azulada suave de noche.
	_moon.rotation = Vector3(-angle + PI, deg_to_rad(-30.0), 0.0)
	_moon.light_energy = maxf(0.0, -elev) * 0.5
