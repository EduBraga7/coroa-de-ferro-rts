extends Node
class_name GraphicsSettings

## Qualidade gráfica escolhida pelo jogador: [F9] alterna Alta -> Equilibrada -> Leve.
## A escolha fica salva em user://graficos.cfg. Também aceita --graphics=alta|equilibrada|leve.
##
## "Alta" é o visual completo. As outras cortam primeiro o que mais pesa na GPU (glow, sombras,
## vegetação e, na Leve, a resolução 3D) e mantêm a direção de arte: névoa, nuvens, cores e vento.
## Custos medidos numa RX 550 a 1600x900, zoom inicial, GPU livre (tools/bench_render.gd --bench-ab):
## glow 1,1 ms; sombras do sol 1,0 ms (+0,2 ms suaves); névoa/nuvens/vinheta 0,5 ms;
## vegetação 0,3 ms; resolução 3D a 77% economiza 2,3 ms.
## O renderizador Mobile não tem FSR no Godot 4.7: a escala reduzida usa filtro bilinear.

const CONFIG_PATH: String = "user://graficos.cfg"
const ORDER: Array[String] = ["alta", "equilibrada", "leve"]
const PRESETS: Dictionary = {
	"alta": {
		"nome": "Alta", "escala": 1.0, "sombra_cascatas": 2, "sombra_dist": 100.0,
		"sombra_suave": true, "glow": true, "vegetacao": 1.0,
	},
	# Imagem nítida (resolução cheia); tira o brilho difuso das luzes e simplifica a sombra
	"equilibrada": {
		"nome": "Equilibrada", "escala": 1.0, "sombra_cascatas": 1, "sombra_dist": 85.0,
		"sombra_suave": false, "glow": false, "vegetacao": 0.75,
	},
	"leve": {
		"nome": "Leve", "escala": 0.8, "sombra_cascatas": 1, "sombra_dist": 70.0,
		"sombra_suave": false, "glow": false, "vegetacao": 0.5,
	},
}

var level: String = "alta"

var _sun: DirectionalLight3D = null
var _env: Environment = null
var _foliage: Node = null
var _game_manager: GameManager = null


func setup(sun: DirectionalLight3D, env: Environment, foliage: Node, gm: GameManager) -> void:
	_sun = sun
	_env = env
	_foliage = foliage
	_game_manager = gm
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = _load_level()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--graphics="):
			var v: String = arg.get_slice("=", 1)
			if PRESETS.has(v):
				level = v
	apply(level)


func apply(lv: String) -> void:
	level = lv if PRESETS.has(lv) else "alta"
	var p: Dictionary = PRESETS[level]
	var vp: Viewport = get_viewport()
	if vp != null:
		# Só a cena 3D é renderizada menor; a HUD continua nítida (é 2D)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(p["escala"])
	if _sun != null:
		if int(p["sombra_cascatas"]) >= 2:
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			# A câmera fica a 25+ m do chão: a 1ª faixa vai até 45 m (antes 11 m, metade do mapa de
			# sombra era gasta com o ar entre a câmera e o chão)
			_sun.directional_shadow_split_1 = 0.45
		else:
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		_sun.directional_shadow_max_distance = float(p["sombra_dist"])
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if bool(p["sombra_suave"]) else RenderingServer.SHADOW_QUALITY_HARD)
	if _env != null:
		_env.glow_enabled = bool(p["glow"])
	_apply_vegetation(float(p["vegetacao"]))


## Desenha só uma fração das touceiras (a ordem das instâncias já é aleatória no mapa).
func _apply_vegetation(frac: float) -> void:
	if _foliage == null or not is_instance_valid(_foliage):
		return
	for n in _foliage.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if mm != null:
			mm.visible_instance_count = -1 if frac >= 0.999 else int(float(mm.instance_count) * frac)


func cycle() -> void:
	var idx: int = (ORDER.find(level) + 1) % ORDER.size()
	apply(ORDER[idx])
	_save_level()
	if _game_manager != null:
		_game_manager.post_alert("Qualidade gráfica: %s  [F9 alterna]" % String(PRESETS[level]["nome"]), Color(0.75, 0.90, 1.0))


func get_level_name() -> String:
	return String(PRESETS[level]["nome"])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_F9:
			cycle()
			get_viewport().set_input_as_handled()


func _load_level() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		var v: String = String(cfg.get_value("graficos", "qualidade", "alta"))
		if PRESETS.has(v):
			return v
	return "alta"


func _save_level() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("graficos", "qualidade", level)
	cfg.save(CONFIG_PATH)
