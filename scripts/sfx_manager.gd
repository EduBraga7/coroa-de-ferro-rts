extends Node
class_name SFXManager

## Motor de efeitos sonoros espaciais e contextuais ('Coroa de Ferro').
## Carrega os 51 arquivos WAV medievais em 33 bancos com pool 2D + 3D,
## prevenção de repetição, limite de polifonia, cooldown por banco e Limiter no Master.

const SFX_DIR: String = "res://assets/audio/sfx/"
const POOL_2D_SIZE: int = 12
const POOL_3D_SIZE: int = 20

const BANK_FILES: Dictionary = {
	"sword_hit": ["sfx_sword_hit_1.wav", "sfx_sword_hit_2.wav", "sfx_sword_hit_3.wav"],
	"halberd_hit": ["sfx_halberd_hit_1.wav", "sfx_halberd_hit_2.wav", "sfx_halberd_hit_3.wav"],
	"worker_hit": ["sfx_worker_hit_1.wav", "sfx_worker_hit_2.wav"],
	"arrow_shoot": ["sfx_arrow_shoot_1.wav", "sfx_arrow_shoot_2.wav", "sfx_arrow_shoot_3.wav"],
	"arrow_hit": ["sfx_arrow_hit_1.wav", "sfx_arrow_hit_2.wav", "sfx_arrow_hit_3.wav"],
	"unit_death": ["sfx_unit_death_1.wav", "sfx_unit_death_2.wav", "sfx_unit_death_3.wav"],
	"mine_gold": ["sfx_mine_gold_1.wav", "sfx_mine_gold_2.wav", "sfx_mine_gold_3.wav"],
	"chop_wood": ["sfx_chop_wood_1.wav", "sfx_chop_wood_2.wav", "sfx_chop_wood_3.wav"],
	"deposit_gold": ["sfx_deposit_gold.wav"],
	"deposit_wood": ["sfx_deposit_wood.wav"],
	"build_hammer": ["sfx_build_hammer_1.wav", "sfx_build_hammer_2.wav", "sfx_build_hammer_3.wav"],
	"build_place": ["sfx_build_place.wav"],
	"build_complete": ["sfx_build_complete.wav"],
	"building_collapse": ["sfx_building_collapse.wav"],
	"select_worker": ["sfx_select_worker.wav"],
	"select_soldier": ["sfx_select_soldier.wav"],
	"select_archer": ["sfx_select_archer.wav"],
	"select_knight": ["sfx_select_knight.wav"],
	"select_building": ["sfx_select_building.wav"],
	"select_resource": ["sfx_select_resource.wav"],
	"cmd_move": ["sfx_cmd_move_1.wav", "sfx_cmd_move_2.wav"],
	"cmd_attack": ["sfx_cmd_attack.wav"],
	"cmd_gather": ["sfx_cmd_gather.wav"],
	"cmd_rally": ["sfx_cmd_rally.wav"],
	"ui_click": ["sfx_ui_click.wav"],
	"ui_error": ["sfx_ui_error.wav"],
	"train_queue": ["sfx_train_queue.wav"],
	"train_cancel": ["sfx_train_cancel.wav"],
	"unit_ready": ["sfx_unit_ready.wav"],
	"horn_alert": ["sfx_horn_alert.wav"],
	"age_up": ["sfx_age_up.wav"],
	"victory": ["sfx_victory.wav"],
	"defeat": ["sfx_defeat.wav"],
}

var _banks: Dictionary = {}
var _last_variant: Dictionary = {}
var _cooldowns: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _muted: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_master_limiter()
	_load_banks()
	_build_pools()


func _ensure_master_limiter() -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLimiter:
			return
	var lim: AudioEffectLimiter = AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	lim.threshold_db = -6.0
	lim.soft_clip_db = 2.0
	AudioServer.add_bus_effect(idx, lim)


func _load_banks() -> void:
	_banks.clear()
	for bank_name in BANK_FILES.keys():
		var arr: Array[AudioStream] = []
		var files: Array = BANK_FILES[bank_name]
		for fname in files:
			var stream: AudioStream = load(SFX_DIR + String(fname)) as AudioStream
			if stream != null:
				arr.append(stream)
		if not arr.is_empty():
			_banks[bank_name] = arr


func _build_pools() -> void:
	for _i in range(POOL_2D_SIZE):
		var p2: AudioStreamPlayer = AudioStreamPlayer.new()
		p2.bus = "Master"
		add_child(p2)
		_pool_2d.append(p2)

	for _i in range(POOL_3D_SIZE):
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.bus = "Master"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 18.0
		p3.max_distance = 75.0
		p3.max_db = 0.0
		add_child(p3)
		_pool_3d.append(p3)


func get_loaded_bank_counts() -> Dictionary:
	var total_streams: int = 0
	for k in _banks.keys():
		total_streams += (_banks[k] as Array).size()
	return {"banks": _banks.size(), "streams": total_streams}


func is_muted() -> bool:
	return _muted


func set_muted(val: bool) -> void:
	_muted = val
	if _muted:
		for p2 in _pool_2d:
			if p2.playing:
				p2.stop()
		for p3 in _pool_3d:
			if p3.playing:
				p3.stop()


func toggle_muted() -> bool:
	set_muted(not _muted)
	return _muted


func _pick_stream(bank: String) -> AudioStream:
	if not _banks.has(bank):
		return null
	var arr: Array = _banks[bank]
	if arr.is_empty():
		return null
	if arr.size() == 1:
		return arr[0] as AudioStream
	var last_i: int = int(_last_variant.get(bank, -1))
	var idx: int = _rng.randi_range(0, arr.size() - 1)
	if idx == last_i:
		idx = (idx + _rng.randi_range(1, arr.size() - 1)) % arr.size()
	_last_variant[bank] = idx
	return arr[idx] as AudioStream


func _check_cooldown(bank: String, cooldown_ms: int) -> bool:
	if cooldown_ms <= 0:
		return true
	var now: int = Time.get_ticks_msec()
	var prev: int = int(_cooldowns.get(bank, -999999))
	if now - prev < cooldown_ms:
		return false
	_cooldowns[bank] = now
	return true


func _acquire_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	var chosen: AudioStreamPlayer = _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D_SIZE
	return chosen


func _acquire_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	var chosen: AudioStreamPlayer3D = _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D_SIZE
	return chosen


func _play_2d(bank: String, vol_db: float = -4.0, pitch: float = 1.0, pitch_jitter: float = 0.04, cooldown_ms: int = 35) -> void:
	if _muted or DisplayServer.get_name() == "headless":
		return
	if _pool_2d.is_empty() or not _check_cooldown(bank, cooldown_ms):
		return
	var stream: AudioStream = _pick_stream(bank)
	if stream == null:
		return
	var p: AudioStreamPlayer = _acquire_2d()
	p.stop()
	p.stream = stream
	p.volume_db = vol_db + _rng.randf_range(-0.8, 0.8)
	p.pitch_scale = clampf(pitch * _rng.randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), 0.5, 2.0)
	p.play()


func _play_3d(bank: String, world_pos: Vector3, vol_db: float = -2.0, pitch: float = 1.0, pitch_jitter: float = 0.06, cooldown_ms: int = 65) -> void:
	if _muted or DisplayServer.get_name() == "headless":
		return
	if _pool_3d.is_empty() or not _check_cooldown(bank, cooldown_ms):
		return
	var stream: AudioStream = _pick_stream(bank)
	if stream == null:
		return
	var p: AudioStreamPlayer3D = _acquire_3d()
	p.stop()
	p.stream = stream
	p.global_position = world_pos
	p.volume_db = vol_db + _rng.randf_range(-1.0, 1.0)
	p.pitch_scale = clampf(pitch * _rng.randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), 0.5, 2.0)
	p.play()


# ==============================================================================
# API CONTEXTUAL PARA GAMEPLAY E UI
# ==============================================================================

func play_select_unit(u_type: String) -> void:
	match u_type:
		"worker":
			_play_2d("select_worker", -5.0, 1.0, 0.03, 55)
		"archer":
			_play_2d("select_archer", -5.0, 1.0, 0.03, 55)
		"scout":
			_play_2d("select_archer", -5.5, 1.08, 0.03, 55)
		"knight":
			_play_2d("select_knight", -4.5, 1.0, 0.03, 55)
		"captain":
			_play_2d("select_knight", -4.0, 0.86, 0.02, 55)
		"ram":
			_play_2d("select_knight", -4.0, 0.78, 0.02, 55)
		"spearman":
			_play_2d("select_soldier", -4.5, 1.06, 0.03, 55)
		_:
			_play_2d("select_soldier", -4.5, 1.0, 0.03, 55)


func play_select_building() -> void:
	_play_2d("select_building", -4.5, 1.0, 0.02, 55)


func play_select_resource() -> void:
	_play_2d("select_resource", -5.5, 1.0, 0.03, 55)


func play_cmd_move() -> void:
	_play_2d("cmd_move", -7.5, 1.0, 0.03, 70)


func play_cmd_attack() -> void:
	_play_2d("cmd_attack", -4.5, 1.0, 0.03, 75)


func play_cmd_gather() -> void:
	_play_2d("cmd_gather", -5.0, 1.0, 0.03, 75)


func play_cmd_rally() -> void:
	_play_2d("cmd_rally", -4.5, 1.0, 0.02, 75)


func play_melee_hit(u_type: String, world_pos: Vector3) -> void:
	match u_type:
		"knight":
			_play_3d("halberd_hit", world_pos, -1.5, 1.0, 0.06, 70)
		"captain":
			_play_3d("halberd_hit", world_pos, -1.0, 0.86, 0.05, 70)
		"ram":
			_play_3d("halberd_hit", world_pos, 0.5, 0.66, 0.04, 160)
			_play_3d("build_place", world_pos, -4.0, 0.75, 0.04, 160)
		"worker":
			_play_3d("worker_hit", world_pos, -4.0, 1.0, 0.06, 80)
		"spearman":
			_play_3d("sword_hit", world_pos, -2.5, 1.08, 0.06, 65)
		"scout":
			_play_3d("sword_hit", world_pos, -3.0, 1.12, 0.06, 65)
		_:
			_play_3d("sword_hit", world_pos, -2.0, 1.0, 0.06, 65)


func play_arrow_shoot(world_pos: Vector3) -> void:
	_play_3d("arrow_shoot", world_pos, -3.5, 1.0, 0.07, 65)


func play_arrow_hit(world_pos: Vector3) -> void:
	_play_3d("arrow_hit", world_pos, -3.0, 1.0, 0.08, 60)


func play_unit_death(world_pos: Vector3) -> void:
	_play_3d("unit_death", world_pos, -2.0, 1.0, 0.07, 85)


func play_harvest_resource(r_type: String, world_pos: Vector3) -> void:
	match r_type:
		"gold":
			_play_3d("mine_gold", world_pos, -4.0, 1.0, 0.06, 120)
		"stone":
			_play_3d("mine_gold", world_pos, -3.5, 0.76, 0.05, 120)
		"wood":
			_play_3d("chop_wood", world_pos, -3.5, 1.0, 0.07, 120)
		_:
			_play_3d("chop_wood", world_pos, -9.0, 1.28, 0.07, 150)


func play_deposit(r_type: String, world_pos: Vector3) -> void:
	match r_type:
		"gold":
			_play_3d("deposit_gold", world_pos, -4.0, 1.0, 0.04, 140)
		"stone":
			_play_3d("deposit_gold", world_pos, -4.5, 0.80, 0.04, 140)
		"wood":
			_play_3d("deposit_wood", world_pos, -4.0, 1.0, 0.04, 140)
		_:
			_play_3d("deposit_wood", world_pos, -6.5, 1.16, 0.04, 140)


func play_build_hammer(world_pos: Vector3) -> void:
	_play_3d("build_hammer", world_pos, -3.5, 1.0, 0.06, 150)


func play_build_place(world_pos: Vector3) -> void:
	_play_3d("build_place", world_pos, -2.0, 1.0, 0.03, 90)


func play_build_complete(world_pos: Vector3 = Vector3.INF) -> void:
	if world_pos.x == INF:
		_play_2d("build_complete", -4.0, 1.0, 0.02, 180)
	else:
		_play_3d("build_complete", world_pos, -1.5, 1.0, 0.02, 180)


func play_building_collapse(world_pos: Vector3) -> void:
	_play_3d("building_collapse", world_pos, 0.0, 1.0, 0.04, 220)


func play_ui_click() -> void:
	_play_2d("ui_click", -7.0, 1.0, 0.03, 30)


func play_ui_error() -> void:
	_play_2d("ui_error", -4.5, 1.0, 0.02, 110)


func play_train_queue() -> void:
	_play_2d("train_queue", -5.0, 1.0, 0.02, 45)


func play_train_cancel() -> void:
	_play_2d("train_cancel", -5.0, 1.0, 0.02, 45)


func play_unit_ready() -> void:
	_play_2d("unit_ready", -4.0, 1.0, 0.02, 160)


func play_market_trade() -> void:
	_play_2d("deposit_gold", -6.0, 1.06, 0.03, 90)


func play_age_up() -> void:
	_play_2d("age_up", -3.0, 1.0, 0.01, 400)


func play_horn_alert() -> void:
	_play_2d("horn_alert", -2.5, 1.0, 0.02, 600)


func play_victory() -> void:
	_play_2d("victory", -2.0, 1.0, 0.0, 500)


func play_defeat() -> void:
	_play_2d("defeat", -2.5, 1.0, 0.0, 500)


# ==============================================================================
# WRAPPERS LEGADOS PARA COMPATIBILIDADE
# ==============================================================================

func play_select() -> void:
	play_select_unit("soldier")


func play_command() -> void:
	play_cmd_move()


func play_hit_melee() -> void:
	play_melee_hit("soldier", Vector3.ZERO)


func play_shoot_arrow() -> void:
	play_arrow_shoot(Vector3.ZERO)


func play_harvest() -> void:
	play_harvest_resource("gold", Vector3.ZERO)
